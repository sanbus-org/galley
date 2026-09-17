#!/bin/bash
# Stages one JavaScript package for packing/publishing: copies the source
# tree (never node_modules), assembles the compile kit (core) or the
# prebuilt CLI binary (cli-*), and pins the manifest version.
#
# The repo combines siblings with `file:` dependencies, which npm packs
# verbatim and which break for registry consumers. Staging rewrites every
# `file:../<sibling>` spec to the release version. Repo files are never
# touched; pass a destination outside the repo.
#
# DEV_SCOPE (empty for stable releases): when set to a scope such as
# @sanbus-org, every @sanbus/ package reference is rewritten to it — the
# manifest name, all dependency keys, import specifiers in sources, and
# the platform-package map the loader resolves at runtime — so the staged
# tree stays internally consistent under its dev identity. A `repository`
# field linking the package to sanbus-org/galley is added so GitHub
# Packages associates it with the repo. Staging then fails loudly if any
# @sanbus/ reference survives in a packed text file, so a new reference
# in a new file type breaks here instead of shipping a half-renamed
# package.
#
# Usage: ./scripts/js/stage_js_package.sh <srcdir> <destdir> <version>
set -euo pipefail

test $# = 3 || {
	echo "stage_js_package: usage: stage_js_package.sh <srcdir> <destdir> <version>" >&2
	exit 2
}
SRC="$1"
DEST="$2"
VERSION="$3"
DEV_SCOPE="${DEV_SCOPE:-}"
DEV_SCOPE="${DEV_SCOPE%/}"
FROM_SCOPE="@sanbus/"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dir="$(basename "$SRC")"

rm -rf "$DEST"
mkdir -p "$DEST"
# Copy everything the manifest's `files` whitelist can pack, never
# node_modules (snapshots of siblings must not leak into tarballs).
tar --exclude='./node_modules' --exclude='./*.tgz' -cf - -C "$SRC" . | tar -xf - -C "$DEST"
case "$dir" in
core)
	# Consumers compile with no checkout: ship the consumer build plus
	# every source it reads, assembled fresh from this checkout (the
	# repo never tracks the kit).
	"$ROOT/scripts/js/assemble_compile_kit.sh" "$DEST/compile-kit"
	;;
cli-*)
	# Platform packages ship one prebuilt binary, laid out by
	# build_compiler_binaries.sh under $CLI_ARTIFACTS/<dir>/bin/.
	# The repo never tracks binaries, so staging fails without them.
	: "${CLI_ARTIFACTS:?stage_js_package: set CLI_ARTIFACTS at built compiler binaries (scripts/js/build_compiler_binaries.sh)}"
	mkdir -p "$DEST/bin"
	cp "$CLI_ARTIFACTS/$dir"/bin/galley* "$DEST/bin/"
	chmod +x "$DEST"/bin/galley*
	;;
esac
node -e "
    const fs = require('fs');
    const [dest, version, devScope, fromScope] = process.argv.slice(1);
    const manifest = dest + '/package.json';
    const data = JSON.parse(fs.readFileSync(manifest, 'utf8'));
    // The root VERSION file is the single source of truth for the version too,
    // not just the skip check in the publish scripts.
    data.version = version;
    if (devScope) {
      if (typeof data.name === 'string' && data.name.startsWith(fromScope)) {
        data.name = devScope + '/' + data.name.slice(fromScope.length);
      }
      data.repository = { type: 'git', url: 'https://github.com/sanbus-org/galley.git' };
    }
    for (const scope of ['dependencies', 'devDependencies', 'optionalDependencies']) {
      const renamed = {};
      for (const [dep, spec] of Object.entries(data[scope] || {})) {
        const name = (devScope && dep.startsWith(fromScope))
          ? devScope + '/' + dep.slice(fromScope.length)
          : dep;
        renamed[name] = (typeof spec === 'string' && spec.startsWith('file:../'))
          ? version
          : spec;
      }
      if (data[scope]) {
        data[scope] = renamed;
      }
    }
    fs.writeFileSync(manifest, JSON.stringify(data, null, 2) + '\n');
  " -- "$DEST" "$VERSION" "$DEV_SCOPE" "$FROM_SCOPE"
pinned="$(node -p "require(process.argv[1]).version" -- "$DEST/package.json")"
test "$pinned" = "$VERSION" || {
	echo "stage_js_package: version pin failed ($pinned != $VERSION)" >&2
	exit 1
}
if [ -n "$DEV_SCOPE" ]; then
	# Import specifiers, the loader's platform map, and install docs must
	# follow the renamed identity. Binaries (bin/galley*) never carry npm
	# scopes (verified: no @sanbus/ in src/, bindings/c, or the addon
	# sources they build from), so only text files are rewritten.
	while IFS= read -r -d '' file; do
		# `#` delimiters: the scopes contain `/`, and `\@` keeps perl
		# from reading the scope as an array in the replacement.
		perl -pi -e "s#\\@${FROM_SCOPE#@}#\\@${DEV_SCOPE#@}/#g" "$file"
	done < <(find "$DEST" \( -name '*.js' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.ts' -o -name '*.mts' -o -name '*.cts' -o -name '*.map' -o -name '*.md' -o -name '*.json' \) -not -name '*lock*' -print0)
	# Lockfiles keep their stale file: references but are never packed
	# (no manifest lists them in `files`), so they are excluded rather
	# than rewritten.
	leftover="$(grep -rl --exclude='*lock*' --exclude-dir=node_modules "$FROM_SCOPE" "$DEST" || true)"
	# The manifest is rewritten above (node renames, perl rewrites), so
	# anything left anywhere — including package.json — is a reference
	# in a field this script does not cover yet: fail here, loudly.
	test -z "$leftover" || {
		echo "stage_js_package: unrenamed $FROM_SCOPE references survive in:" >&2
		printf '%s\n' "$leftover" >&2
		exit 1
	}
fi
echo "stage_js_package: staged $dir@$VERSION${DEV_SCOPE:+ ($DEV_SCOPE)}"
