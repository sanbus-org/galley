//! Builds a Galley-generated parser as a C-API shared library.
//!
//! External entry point for C and C++ consumers. Invoke from inside a
//! Galley checkout (or fetched copy) with sources produced by the generator
//! CLI.
//!
//! Procedure hook implementations enter the shared library through one of
//! two inputs:
//!
//! - `-Dprocedures-c-source=<file>` compiles a C source file into the
//!   library (the C and C++ consumers' native tongue).
//! - `-Dprocedures-object=<file>` links a prebuilt object file or static
//!   archive produced by another native toolchain (for example rustc's
//!   `--crate-type=staticlib` output) whose symbols implement the hooks.
//!
//! The generated `procedures.zig` next to the parser declares extern entry
//! points — `reduction_<VariableName>`, the general `reduction`, and every
//! author-defined grammar hook as `hook_<name>` — which the input
//! implements directly; the linker resolves them when the shared library
//! is built. Passing both inputs fails: one implementation owns the entry
//! points.
//!
//! Installs `lib<lib-name>.dylib|so` and `include/galley.h`.

const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const parser_source = b.option([]const u8, "parser-source", "Path to the generated parser Zig source (required)") orelse
        return error.MissingParserSource;
    const parser_type = b.option([]const u8, "parser-type", "Parser family: ll or lr (default ll)") orelse "ll";
    const lib_name = b.option([]const u8, "lib-name", "Installed library base name (default galley-parser)") orelse "galley-parser";
    const capi_version = b.option([]const u8, "capi-version", "Version string reported by galley_version") orelse "dev";
    const procedures_c_source = b.option([]const u8, "procedures-c-source", "C source file implementing procedure hooks");
    const procedures_object = b.option([]const u8, "procedures-object", "Prebuilt object file or static archive implementing procedure hooks");
    const procedures_zig_source = b.option([]const u8, "procedures-zig-source", "Custom procedures.zig overriding the default template");
    const config_zig_source = b.option([]const u8, "config-zig-source", "Path to config.zig (default: config.zig next to parser)");
    const error_messages_zig_source = b.option([]const u8, "error-messages-zig-source", "Custom error-messages.zig overriding the default template");

    if (procedures_c_source != null and procedures_object != null) {
        std.log.err("pass either -Dprocedures-c-source or -Dprocedures-object, not both: one implementation owns the procedure entry points", .{});
        return error.ConflictingProcedureInputs;
    }

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
        .root_source_file = if (procedures_zig_source) |src|
            .{ .cwd_relative = src }
        else
            galley_dep.path("src/cli/templates/procedures.zig"),
        .target = target,
        .optimize = optimize,
    });
    const config_mod = b.createModule(.{
        .root_source_file = if (config_zig_source) |src|
            .{ .cwd_relative = src }
        else blk: {
            const parser_dir = std.fs.path.dirname(parser_source) orelse ".";
            const candidate = b.pathJoin(&.{ parser_dir, "config.zig" });
            break :blk .{ .cwd_relative = candidate };
        },
        .target = target,
        .optimize = optimize,
    });
    const error_messages_mod = b.createModule(.{
        .root_source_file = if (error_messages_zig_source) |src|
            .{ .cwd_relative = src }
        else
            galley_dep.path(b.fmt("src/cli/templates/{s}_error_messages.zig", .{parser_type})),
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

    if (procedures_c_source) |c_source| {
        capi_lib.root_module.addCSourceFile(.{
            .file = .{ .cwd_relative = c_source },
        });
    }
    if (procedures_object) |object| {
        capi_lib.root_module.addObjectFile(.{ .cwd_relative = object });
    }

    b.installArtifact(capi_lib);
    const header_install = b.addInstallFile(galley_dep.path("bindings/c/galley.h"), "include/galley.h");
    b.getInstallStep().dependOn(&header_install.step);
}
