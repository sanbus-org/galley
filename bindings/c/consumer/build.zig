//! Builds a Galley-generated parser as a C-API shared library.
//!
//! External entry point for C and C++ consumers. Invoke from inside a
//! Galley checkout (or fetched copy) with sources produced by the generator
//! CLI.
//!
//! All language-owned Zig sources are inferred from the parser location
//! when no explicit flag is given: `config.zig`, `procedures.zig`, and
//! `{ll,lr}_error_messages.zig` next to the parser are used automatically
//! when present, with language-agnostic templates as fallback. A C/C++
//! procedure implementation (`procedures.c` or `procedures.cpp` next to the
//! parser) is likewise compiled in when present. Explicit flags override
//! inference and are for non-standard layouts only — the reference
//! `examples/c` and `examples/cpp` builds pass only `parser-source` and
//! `parser-type` and rely on inference.
//!
//! Procedure hook implementations enter the shared library through one of
//! two inputs:
//!
//! - `-Dprocedures-c-source=<file>` compiles a C source file into the
//!   library (the C and C++ consumers' native tongue). When omitted and
//!   no `-Dprocedures-object` is given, a `procedures.c` or
//!   `procedures.cpp` next to the parser is used if it exists.
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
const galley_pkg = @import("galley");

fn exists(io: std.Io, path: []const u8) bool {
    if (std.fs.path.isAbsolute(path)) {
        std.Io.Dir.accessAbsolute(io, path, .{}) catch return false;
        return true;
    } else {
        std.Io.Dir.cwd().access(io, path, .{}) catch return false;
        return true;
    }
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const parser_source = b.option([]const u8, "parser-source", "Path to the generated parser Zig source (required)") orelse
        return error.MissingParserSource;
    const parser_type = b.option([]const u8, "parser-type", "Parser family: ll or lr (default ll)") orelse "ll";
    const lib_name = b.option([]const u8, "lib-name", "Installed library base name (default galley-parser)") orelse "galley-parser";
    const capi_version = b.option([]const u8, "capi-version", "Version string reported by galley_version") orelse "dev";
    const procedures_c_source = b.option([]const u8, "procedures-c-source", "C source file implementing procedure hooks (default: procedures.c or procedures.cpp next to parser when present)");
    const procedures_object = b.option([]const u8, "procedures-object", "Prebuilt object file or static archive implementing procedure hooks");
    const procedures_zig_source = b.option([]const u8, "procedures-zig-source", "Custom procedures.zig (default: procedures.zig next to parser when present, otherwise template)");
    const config_zig_source = b.option([]const u8, "config-zig-source", "Path to config.zig (default: config.zig next to parser)");
    const error_messages_zig_source = b.option([]const u8, "error-messages-zig-source", "Custom error-messages.zig (default: {ll,lr}_error_messages.zig next to parser when present, otherwise template)");

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

    const parser_dir = std.fs.path.dirname(parser_source) orelse ".";
    const language_dir: std.Build.LazyPath = .{ .cwd_relative = parser_dir };
    const procedures_file: std.Build.LazyPath = if (procedures_zig_source) |src|
        .{ .cwd_relative = src }
    else blk: {
        const candidate = b.pathJoin(&.{ parser_dir, "procedures.zig" });
        if (exists(b.graph.io, candidate)) break :blk .{ .cwd_relative = candidate };
        break :blk galley_dep.path("src/cli/templates/procedures.zig");
    };
    const config_file: std.Build.LazyPath = if (config_zig_source) |src|
        .{ .cwd_relative = src }
    else
        .{ .cwd_relative = b.pathJoin(&.{ parser_dir, "config.zig" }) };
    const error_file: std.Build.LazyPath = if (error_messages_zig_source) |src|
        .{ .cwd_relative = src }
    else blk: {
        const file_name = b.fmt("{s}_error_messages.zig", .{parser_type});
        const candidate = b.pathJoin(&.{ parser_dir, file_name });
        if (exists(b.graph.io, candidate)) break :blk .{ .cwd_relative = candidate };
        break :blk galley_dep.path(b.fmt("src/cli/templates/{s}_error_messages.zig", .{parser_type}));
    };
    const runtime_mod = galley_pkg.addParserModule(b, galley_dep, .{
        .target = target,
        .optimize = optimize,
        .language_dir = language_dir,
        .parser_type = if (std.mem.eql(u8, parser_type, "ll")) .ll else .lr,
        .parser_source = .{ .cwd_relative = parser_source },
        .procedures = procedures_file,
        .config = config_file,
        .error_messages = error_file,
    });

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
    capi_lib.root_module.addIncludePath(galley_dep.path("bindings/c"));

    if (procedures_c_source) |c_source| {
        capi_lib.root_module.addCSourceFile(.{
            .file = .{ .cwd_relative = c_source },
        });
    } else if (procedures_object) |object| {
        capi_lib.root_module.addObjectFile(.{ .cwd_relative = object });
    } else {
        const candidates = [_][]const u8{
            b.pathJoin(&.{ parser_dir, "procedures.c" }),
            b.pathJoin(&.{ parser_dir, "procedures.cpp" }),
        };
        for (candidates) |candidate| {
            if (exists(b.graph.io, candidate)) {
                capi_lib.root_module.addCSourceFile(.{
                    .file = .{ .cwd_relative = candidate },
                });
                break;
            }
        }
    }

    b.installArtifact(capi_lib);
    const header_install = b.addInstallFile(galley_dep.path("bindings/c/galley.h"), "include/galley.h");
    b.getInstallStep().dependOn(&header_install.step);
}
