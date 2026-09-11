#!/bin/bash
# Publishes the Galley JavaScript packages to the npm registry in
# dependency order (core, adapters, universal last).
#
# Idempotent: any package whose lockstep version already exists on the
# registry is skipped, so re-runs (docs-only pushes, retries) are green.
#
# The repo combines siblings with `file:` dependencies, which npm packs
# verbatim and which break for registry consumers. Each package is
# therefore published from a temp copy whose `file:../<sibling>` specs
# are rewritten to the lockstep VERSION. Repo files are never touched.
#
# Auth is OIDC trusted publishing (no token): configure the repo as a
# trusted publisher on npmjs.com once, then this runs with `id-token:
# write` and `--provenance`. First publish of a scope needs
# `--access public`, passed every time (harmless afterwards).
#
# Run (CI publish job does this after the test gate is green):
#   ./scripts/publish_js.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JS_DIR="$ROOT/bindings/js"
VERSION="$(python3 "$ROOT/scripts/product_version.py")"

# Directory order is dependency order: core first, universal last,
# prebuilt CLI packages after everything that could resolve them.
PACKAGES="core node bun deno wasm universal cli-darwin-arm64 cli-darwin-x64 cli-linux-x64 cli-linux-arm64 cli-win32-x64 cli-win32-arm64"

for dir in $PACKAGES; do
	manifest="$JS_DIR/$dir/package.json"
	name="$(node -p "require('$manifest').name")"
	if npm view "$name@$VERSION" version >/dev/null 2>&1; then
		echo "publish_js: skip $name@$VERSION (already on the registry)"
		continue
	fi
	work="$(mktemp -d)"
	trap 'rm -rf "$work"' EXIT
	# Copy everything the manifest's `files` whitelist can pack, never
	# node_modules (snapshots of siblings must not leak into tarballs).
	tar --exclude='./node_modules' --exclude='./*.tgz' -cf - -C "$JS_DIR/$dir" . | tar -xf - -C "$work"
	case "$dir" in
	core)
		# Consumers compile with no checkout: ship the consumer build plus
		# every source it reads, assembled fresh from this checkout (the
		# repo never tracks the kit).
		"$ROOT/scripts/js/assemble_compile_kit.sh" "$work/compile-kit"
		;;
	cli-*)
		# Platform packages ship one prebuilt binary, laid out by
		# build_compiler_binaries.sh under $CLI_ARTIFACTS/<dir>/bin/.
		# The repo never tracks binaries, so publish fails without them.
		: "${CLI_ARTIFACTS:?publish_js: set CLI_ARTIFACTS at built compiler binaries (scripts/js/build_compiler_binaries.sh)}"
		mkdir -p "$work/bin"
		cp "$CLI_ARTIFACTS/$dir"/bin/galley* "$work/bin/"
		chmod +x "$work"/bin/galley*
		;;
	esac
	node -e "
    const fs = require('fs');
    const manifest = '$work/package.json';
    const data = JSON.parse(fs.readFileSync(manifest, 'utf8'));
    // The root VERSION file is the single source of truth for the version too,
    // not just the skip check above.
    data.version = '$VERSION';
    for (const scope of ['dependencies', 'devDependencies', 'optionalDependencies']) {
      for (const [dep, spec] of Object.entries(data[scope] || {})) {
        if (typeof spec === 'string' && spec.startsWith('file:../')) {
          data[scope][dep] = '$VERSION';
        }
      }
    }
    fs.writeFileSync(manifest, JSON.stringify(data, null, 2) + '\n');
  "
	pinned="$(node -p "require('$work/package.json').version")"
	test "$pinned" = "$VERSION" || {
		echo "publish_js: version pin failed ($pinned != $VERSION)" >&2
		exit 1
	}
	echo "publish_js: publishing $name@$VERSION"
	# --ignore-scripts: dist/ is already built by CI; the temp copy has no
	# node_modules for prepare/prepublishOnly's tsc to resolve.
	# --provenance needs GitHub's OIDC mint, so local bootstrapping runs
	# without it; CI always has ACTIONS_ID_TOKEN_REQUEST_TOKEN set.
	publish_flags="--ignore-scripts --access public"
	if [ -n "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
		publish_flags="$publish_flags --provenance"
	fi
	# Prereleases must never become latest: 0.2.0-beta.1 publishes under
	# --tag beta (suffix up to the first dot), stable releases keep npm's
	# default latest tag.
	case "$VERSION" in
	*-*)
		prerelease="${VERSION#*-}"
		publish_flags="$publish_flags --tag ${prerelease%%.*}"
		;;
	esac
	# Intentionally word-split: flags never contain spaces.
	# shellcheck disable=SC2086
	npm publish "$work" $publish_flags
	trap - EXIT
	rm -rf "$work"
done
echo "publish_js: done"
