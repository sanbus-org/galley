#!/bin/sh
# Fetches a Galley checkout into the system cache for the examples.
#
# This cache exists solely for the convenience of the examples: the bindings
# themselves require GALLEY_CHECKOUT and never fetch or write per-grammar
# output outside the language dir.
#
# Usage:
#   GALLEY_CHECKOUT=$(examples/scripts/fetch-galley.sh) python -m galley_bindings examples/python
#   GALLEY_CHECKOUT=$(examples/scripts/fetch-galley.sh) cargo build --manifest-path examples/rust/Cargo.toml
#
# Environment: GALLEY_REPOSITORY (default https://github.com/sanbus-org/galley.git),
# GALLEY_TAG (default main).
set -eu

REPOSITORY="${GALLEY_REPOSITORY:-https://github.com/sanbus-org/galley.git}"
TAG="${GALLEY_TAG:-main}"

cache_root() {
	case "$(uname -s)" in
	Darwin) printf '%s/Library/Caches' "${HOME:-/tmp}" ;;
	MINGW* | MSYS* | CYGWIN* | Windows_NT)
		if [ -n "${LOCALAPPDATA:-}" ]; then printf '%s' "$LOCALAPPDATA"; else printf '%s' "${TMPDIR:-/tmp}"; fi
		;;
	*)
		if [ -n "${XDG_CACHE_HOME:-}" ]; then printf '%s' "$XDG_CACHE_HOME"; else printf '%s/.cache' "${HOME:-/tmp}"; fi
		;;
	esac
}

CACHE_DIR="$(cache_root)/galley-bindings/fetch"
SOURCE_DIR="$CACHE_DIR/galley-src"
STAMP="$CACHE_DIR/galley-tag"

mkdir -p "$CACHE_DIR"

previous=""
if [ -f "$STAMP" ]; then previous="$(cat "$STAMP" 2>/dev/null || true)"; fi
if [ -d "$SOURCE_DIR" ] && [ "$previous" = "$TAG" ] && [ -f "$SOURCE_DIR/build.zig" ]; then
	printf '%s\n' "$SOURCE_DIR"
	exit 0
fi

rm -rf "$SOURCE_DIR"
git clone --depth 1 --branch "$TAG" --single-branch --recurse-submodules=false "$REPOSITORY" "$SOURCE_DIR" >&2
printf '%s' "$TAG" >"$STAMP"
printf '%s\n' "$SOURCE_DIR"
