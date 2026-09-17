#!/bin/bash
# Assembles the self-contained C/C++ kit for one platform: everything a C
# or C++ consumer needs without checking out the Galley repo.
#
# Layout:
#   bin/galley[.exe]               the generator CLI for this platform
#   include/galley.h               the public C header (for -I)
#   share/galley/compile-kit/      the consumer build plus every source it
#                                  reads (via assemble_compile_kit.sh)
#   VERSION                        the kit version, for traceability
#   README.md                      the two commands plus requirements
#
# One kit serves C and C++ alike: both consume the same C ABI, so the
# kit ships the means of production. The parser library itself is
# generated from the consumer's own .grm by the two commands below.
# Consumers still need a Zig
# toolchain (the compile step runs `zig build`) plus a C compiler.
#
# Usage: ./scripts/c/assemble_c_kit.sh <platform-dir> <destdir> <version>
#   platform-dir: e.g. cli-linux-x64 (selects bin/galley* from CLI_ARTIFACTS)
set -euo pipefail

test $# = 3 || {
	echo "assemble_c_kit: usage: assemble_c_kit.sh <platform-dir> <destdir> <version>" >&2
	exit 2
}
PLATFORM="$1"
DEST="$2"
VERSION="$3"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

case "$PLATFORM" in
cli-darwin-arm64 | cli-darwin-x64 | cli-linux-x64 | cli-linux-arm64 | cli-win32-x64 | cli-win32-arm64) ;;
*)
	echo "assemble_c_kit: unknown platform $PLATFORM" >&2
	exit 1
	;;
esac
# The repo never tracks binaries, so the kit fails without built CLIs.
: "${CLI_ARTIFACTS:?assemble_c_kit: set CLI_ARTIFACTS at built compiler binaries (scripts/js/build_compiler_binaries.sh)}"
test -f "$CLI_ARTIFACTS/$PLATFORM"/bin/galley* || {
	echo "assemble_c_kit: no CLI binary under $CLI_ARTIFACTS/$PLATFORM/bin" >&2
	exit 1
}

rm -rf "$DEST"
mkdir -p "$DEST/bin" "$DEST/include" "$DEST/share/galley"
cp "$CLI_ARTIFACTS/$PLATFORM"/bin/galley* "$DEST/bin/"
chmod +x "$DEST"/bin/galley*
cp "$ROOT/bindings/c/galley.h" "$DEST/include/"
# The compile inputs are the one shared kit every binding ships; a new
# file there reaches C consumers automatically, with no second list here.
"$ROOT/scripts/js/assemble_compile_kit.sh" "$DEST/share/galley/compile-kit"
printf '%s\n' "$VERSION" >"$DEST/VERSION"
cat >"$DEST/README.md" <<EOF
# Galley C/C++ kit ($VERSION, $PLATFORM)
Generate and compile a Galley parser with no repo checkout.
Requires a Zig 0.16.0+ toolchain and a C compiler.
One kit serves C and C++ (same C ABI).
Reference integration: examples/c (CMake) and examples/cpp in the Galley repo.
# 1. Generate the parser and metadata next to your grammar (ll.grm plus
#    config.zig; procedures.c next to them is picked up automatically).
#    Below, \$KIT is the extracted kit directory.
"\$KIT/bin/galley" --emit-metadata <language-dir>
# 2. Compile the shared library next to the grammar.
zig build --build-file "\$KIT/share/galley/compile-kit/build.zig" \\
  -Dlanguage-dir=<language-dir> -Dlib-name=<name> \\
  -Doutput='lib<name>.so (lib<name>.dylib on macOS)' -Doptimize=ReleaseFast \\
  --prefix <language-dir> install
# Link your program against it with -I"\$KIT/include" -L<language-dir> -l<name>.
EOF
echo "assemble_c_kit: $DEST"
