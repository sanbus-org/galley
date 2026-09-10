#!/bin/bash
# Cross-compiles the Galley generator CLI for every shipped platform and
# lays the binaries out in npm package-dir layout for packaging.
#
# Usage: ./scripts/js/build_compiler_binaries.sh <checkout> <out-dir> [zig]
# Writes <out-dir>/cli-<os>-<arch>/bin/galley[.exe]. Fails loudly on the
# first target that does not compile.
#
# Run (CI compiler-cli job does this on ubuntu):
#   ./scripts/js/build_compiler_binaries.sh "$GITHUB_WORKSPACE" /tmp/galley-cli
set -euo pipefail

CHECKOUT="${1:?usage: build_compiler_binaries.sh <checkout> <out-dir> [zig]}"
OUT_DIR="${2:?usage: build_compiler_binaries.sh <checkout> <out-dir> [zig]}"
ZIG="${3:-${ZIG_EXECUTABLE:-zig}}"

# zig target -> npm platform directory.
TARGETS="aarch64-macos:cli-darwin-arm64 x86_64-macos:cli-darwin-x64 x86_64-linux:cli-linux-x64 aarch64-linux:cli-linux-arm64 x86_64-windows:cli-win32-x64 aarch64-windows:cli-win32-arm64"

for pair in $TARGETS; do
	target="${pair%%:*}"
	dirname="${pair##*:}"
	prefix="$OUT_DIR/$dirname"
	rm -rf "$prefix"
	mkdir -p "$prefix/bin"
	stage="$(mktemp -d)"
	trap 'rm -rf "$stage"' EXIT
	(cd "$CHECKOUT" && "$ZIG" build -Dtarget="$target" -Doptimize=ReleaseFast --prefix "$stage" galley)
	binary="$stage/bin/galley"
	case "$target" in
	*-windows) binary="$binary.exe" ;;
	esac
	test -s "$binary" || {
		echo "build_compiler_binaries: missing $binary" >&2
		exit 1
	}
	cp "$binary" "$prefix/bin/"
	trap - EXIT
	rm -rf "$stage"
	echo "build_compiler_binaries: $target -> $prefix/bin/$(basename "$binary")"
done
echo "build_compiler_binaries: done ($OUT_DIR)"
