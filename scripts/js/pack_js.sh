#!/bin/bash
# Packs every JavaScript package into a versioned tarball for CI artifacts.
#
# The tarballs are the dev-channel payload (published to GitHub Packages
# by scripts/js/publish_tgz.sh) and the downloadable record of every
# build. Staging (copy, compile-kit/CLI assembly, version pin, optional
# dev-scope rewrite) lives in scripts/js/stage_js_package.sh, shared with
# the stable publisher, so both paths stage byte-identical trees for the
# same version. Packing here only runs `npm pack` over them.
#
# Version: ${PACKAGE_VERSION:-run version from scripts/package_version.py}
# (product version on v* tags, dev version otherwise). DEV_SCOPE passes
# through to staging (empty on tags for stable names, @sanbus-org for the
# dev channel). The repo is never touched; dist/ must already be built
# (npm run build) and CLI_ARTIFACTS must hold the compiler binaries for
# the cli-* packages.
#
# Usage: ./scripts/js/pack_js.sh <outdir>
set -euo pipefail

test $# = 1 || {
	echo "pack_js: usage: pack_js.sh <outdir>" >&2
	exit 2
}
OUTDIR="$1"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
JS_DIR="$ROOT/bindings/js"
VERSION="${PACKAGE_VERSION:-"$(python3 "$ROOT/scripts/package_version.py")"}"

# Directory order is dependency order: core first, universal last,
# prebuilt CLI packages after everything that could resolve them.
# Keep in sync with scripts/js/publish_tgz.sh.
PACKAGES="core node bun deno wasm universal cli-darwin-arm64 cli-darwin-x64 cli-linux-x64 cli-linux-arm64 cli-win32-x64 cli-win32-arm64"

mkdir -p "$OUTDIR"
for dir in $PACKAGES; do
	work="$(mktemp -d)"
	trap 'rm -rf "$work"' EXIT
	"$ROOT/scripts/js/stage_js_package.sh" "$JS_DIR/$dir" "$work/stage" "$VERSION"
	case "$dir" in
	cli-*) ;;
	*)
		# `files` whitelists dist/ but npm pack does not require it to
		# exist: refuse a tarball with no compiled output instead of
		# shipping one silently.
		test -d "$work/stage/dist" || {
			echo "pack_js: $dir has no dist/ (run npm run build first)" >&2
			exit 1
		}
		;;
	esac
	# --ignore-scripts: dist/ is already built; the staged copy has no
	# node_modules for prepare/prepublishOnly's tsc to resolve.
	tgz="$(cd "$work/stage" && npm pack --ignore-scripts)"
	mv "$work/stage/$tgz" "$OUTDIR/"
	echo "pack_js: packed $tgz"
	trap - EXIT
	rm -rf "$work"
done
echo "pack_js: done"
