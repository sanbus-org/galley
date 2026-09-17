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
# Usage: ./scripts/js/stage_js_package.sh <srcdir> <destdir> <version>
set -euo pipefail

test $# = 3 || {
	echo "stage_js_package: usage: stage_js_package.sh <srcdir> <destdir> <version>" >&2
	exit 2
}
SRC="$1"
DEST="$2"
VERSION="$3"

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
    const [dest, version] = process.argv.slice(1);
    const manifest = dest + '/package.json';
    const data = JSON.parse(fs.readFileSync(manifest, 'utf8'));
    // The root VERSION file is the single source of truth for the version too,
    // not just the skip check in the publish scripts.
    data.version = version;
    for (const scope of ['dependencies', 'devDependencies', 'optionalDependencies']) {
      for (const [dep, spec] of Object.entries(data[scope] || {})) {
        if (typeof spec === 'string' && spec.startsWith('file:../')) {
          data[scope][dep] = version;
        }
      }
    }
    fs.writeFileSync(manifest, JSON.stringify(data, null, 2) + '\n');
  " -- "$DEST" "$VERSION"
pinned="$(node -p "require(process.argv[1]).version" -- "$DEST/package.json")"
test "$pinned" = "$VERSION" || {
	echo "stage_js_package: version pin failed ($pinned != $VERSION)" >&2
	exit 1
}
echo "stage_js_package: staged $dir@$VERSION"
