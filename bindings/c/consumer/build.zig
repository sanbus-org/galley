//! Builds a Galley-generated parser as a C-API shared library.
//!
//! This is the external entry point for C and C++ consumers. Invoke it from
//! inside a Galley checkout (or a fetched copy) with the sources produced by
//! the generator CLI:
//!
//! ```sh
//! zig build --build-file bindings/c/consumer/build.zig \
//!     -Dparser-source=/abs/path/parser.zig \
//!     -Dparser-type=ll \
//!     -Dlib-name=mylang \
//!     -Doptimize=ReleaseFast \
//!     --prefix /abs/out install
//! ```
//!
//! Installs `lib<lib-name>.dylib|so` (the C API) and `include/galley.h`
//! under the prefix.

const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const parser_source = b.option([]const u8, "parser-source", "Path to the generated parser Zig source (required)") orelse
        return error.MissingParserSource;
    const parser_type = b.option([]const u8, "parser-type", "Parser family of the grammar: ll or lr (default ll)") orelse "ll";
    const lib_name = b.option([]const u8, "lib-name", "Installed library base name (default galley-parser)") orelse "galley-parser";
    const capi_version = b.option([]const u8, "capi-version", "Version string reported by galley_version") orelse "dev";

    if (!std.mem.eql(u8, parser_type, "ll") and !std.mem.eql(u8, parser_type, "lr")) {
        std.log.err("invalid -Dparser-type '{s}': expected ll or lr", .{parser_type});
        return error.InvalidParserType;
    }

    const galley_dep = b.dependency("galley", .{
        .target = target,
        .optimize = optimize,
    });

    const runtime_options_mod = b.createModule(.{
        .root_source_file = galley_dep.path("src/runtime/default_runtime_options.zig"),
        .target = target,
        .optimize = optimize,
    });
    const procedures_mod = b.createModule(.{
        .root_source_file = galley_dep.path("src/cli/templates/procedures.zig"),
        .target = target,
        .optimize = optimize,
    });
    const config_mod = b.createModule(.{
        .root_source_file = galley_dep.path("src/cli/templates/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    const error_messages_mod = b.createModule(.{
        .root_source_file = galley_dep.path(b.fmt("src/cli/templates/{s}_error_messages.zig", .{parser_type})),
        .target = target,
        .optimize = optimize,
    });
    const parser_mod = b.createModule(.{
        .root_source_file = .{ .cwd_relative = parser_source },
        .target = target,
        .optimize = optimize,
    });
    const runtime_mod = b.createModule(.{
        .root_source_file = galley_dep.path("src/runtime/api.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = switch (target.result.os.tag) {
            .linux, .macos => true,
            else => null,
        },
        .imports = &.{
            .{ .name = "procedures", .module = procedures_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "error_messages", .module = error_messages_mod },
            .{ .name = "parser", .module = parser_mod },
            .{ .name = "runtime_options", .module = runtime_options_mod },
        },
    });
    runtime_mod.addImport("galley", runtime_mod);
    procedures_mod.addImport("galley", runtime_mod);
    config_mod.addImport("galley", runtime_mod);
    error_messages_mod.addImport("galley", runtime_mod);
    parser_mod.addImport("galley", runtime_mod);

    const capi_mod = b.createModule(.{
        .root_source_file = galley_dep.path("bindings/c/capi.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    capi_mod.addImport("galley", runtime_mod);
    const capi_options = b.addOptions();
    capi_options.addOption([]const u8, "version", capi_version);
    capi_mod.addImport("capi_options", capi_options.createModule());

    const capi_lib = b.addLibrary(.{
        .name = lib_name,
        .linkage = .dynamic,
        .root_module = capi_mod,
    });
    b.installArtifact(capi_lib);
    const header_install = b.addInstallFile(galley_dep.path("bindings/c/galley.h"), "include/galley.h");
    b.getInstallStep().dependOn(&header_install.step);
}
