#!/bin/bash
# Assembles the dependency-less compile kit shipped inside @sanbus/galley-core.
#
# The kit is the consumer build plus every source it reads, copied from this
# checkout: the consumer build.zig verbatim, and under sources/ a slim
# dependency root (a stub build.zig re-exporting build/common.zig) holding
# verbatim copies of build/common.zig, src/runtime/, the CLI
# procedure/error-message templates, bindings/c/capi.zig and galley.h, and
# the Node NAPI addon.c.
#
# Nothing here is a second implementation: the gate (builder.mjs) invokes
# the same consumer build with the same flags; only the source root differs
# (kit for consumers, GALLEY_CHECKOUT for contributors). The repo never
# tracks the kit: publish assembles it into the tarball, contributors and CI
# assemble it on demand.
#
# Usage: ./scripts/js/assemble_compile_kit.sh [DEST]
# DEST defaults to bindings/js/core/compile-kit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="${1:-$ROOT/bindings/js/core/compile-kit}"

# Fingerprints are opaque package identities (like every build.zig.zon in
# this repo); pinned so published kits are reproducible.
KIT_FINGERPRINT="0x9b32495afbb480a7"
GALLEY_SRC_FINGERPRINT="0x10fec39ee461014"

for source in \
	"$ROOT/bindings/c/consumer/build.zig" \
	"$ROOT/build/common.zig" \
	"$ROOT/src/runtime/api.zig" \
	"$ROOT/src/cli/templates/procedures.zig" \
	"$ROOT/src/cli/templates/ll_error_messages.zig" \
	"$ROOT/src/cli/templates/lr_error_messages.zig" \
	"$ROOT/bindings/c/capi.zig" \
	"$ROOT/bindings/c/galley.h" \
	"$ROOT/bindings/js/node/addon.c"; do
	test -f "$source" || {
		echo "assemble_compile_kit: missing $source" >&2
		exit 1
	}
done

rm -rf "$DEST"
mkdir -p "$DEST/sources/build" "$DEST/sources/src/runtime" \
	"$DEST/sources/src/cli/templates" "$DEST/sources/bindings/c" \
	"$DEST/sources/bindings/js/node"

cp "$ROOT/bindings/c/consumer/build.zig" "$DEST/build.zig"
cat >"$DEST/build.zig.zon" <<EOF
.{
    .name = .galley_compile_kit,
    .version = "0.0.0",
    .fingerprint = $KIT_FINGERPRINT,
    .minimum_zig_version = "0.16.0",
    .dependencies = .{
        .galley = .{
            .path = "sources",
        },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
    },
}
EOF
# Slim dependency root: only what `@import("galley")` in the consumer build
# needs (the parser assembler). The dependency's own build declares the
# standard options so the consumer's target/optimize pass-through resolves.
cat >"$DEST/sources/build.zig" <<'EOF'
const std = @import("std");
const common = @import("build/common.zig");

pub const ParserType = common.ParserType;
pub const AddParserModuleOptions = common.AddParserModuleOptions;
pub const addParserModule = common.addParserModule;

pub fn build(b: *std.Build) void {
    _ = b.standardTargetOptions(.{});
    _ = b.standardOptimizeOption(.{});
}
EOF
cat >"$DEST/sources/build.zig.zon" <<EOF
.{
    .name = .galley,
    .version = "0.0.0",
    .fingerprint = $GALLEY_SRC_FINGERPRINT,
    .minimum_zig_version = "0.16.0",
    .dependencies = .{},
    .paths = .{
        "build.zig",
        "build.zig.zon",
    },
}
EOF
cp "$ROOT/build/common.zig" "$DEST/sources/build/common.zig"
cp -r "$ROOT/src/runtime/." "$DEST/sources/src/runtime/"
for template in procedures.zig ll_error_messages.zig lr_error_messages.zig; do
	cp "$ROOT/src/cli/templates/$template" "$DEST/sources/src/cli/templates/$template"
done
cp "$ROOT/bindings/c/capi.zig" "$ROOT/bindings/c/galley.h" "$DEST/sources/bindings/c/"
cp "$ROOT/bindings/js/node/addon.c" "$DEST/sources/bindings/js/node/addon.c"
echo "assemble_compile_kit: $DEST"
