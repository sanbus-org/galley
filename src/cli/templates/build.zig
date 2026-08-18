const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const galley = b.dependency("galley", .{
        .target = target,
        .optimize = optimize,
    });
    const runtime_options_mod = b.createModule(.{
        .root_source_file = galley.path("src/runtime/default_runtime_options.zig"),
    });
    const procedures_mod = b.createModule(.{
        .root_source_file = b.path("procedures.zig"),
        .target = target,
        .optimize = optimize,
    });
    const config_mod = b.createModule(.{
        .root_source_file = b.path("config.zig"),
        .target = target,
        .optimize = optimize,
    });
    const error_messages_mod = b.createModule(.{
        .root_source_file = b.path("@@ERROR_MESSAGES@@"),
        .target = target,
        .optimize = optimize,
    });
    const parser_source_mod = b.createModule(.{
        .root_source_file = b.path("@@PARSER_SOURCE@@"),
        .target = target,
        .optimize = optimize,
    });
    const parser_mod = b.createModule(.{
        .root_source_file = galley.path("src/runtime/api.zig"),
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
            .{ .name = "parser", .module = parser_source_mod },
            .{ .name = "runtime_options", .module = runtime_options_mod },
        },
    });
    parser_mod.addImport("galley", parser_mod);
    procedures_mod.addImport("galley", parser_mod);
    config_mod.addImport("galley", parser_mod);
    error_messages_mod.addImport("galley", parser_mod);
    parser_source_mod.addImport("galley", parser_mod);

    const runner_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "galley_parser", .module = parser_mod },
        },
    });
    const runner = b.addExecutable(.{
        .name = "@@RUNNER_NAME@@",
        .root_module = runner_mod,
    });
    b.installArtifact(runner);

    const run_cmd = b.addRunArtifact(runner);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Parse a source file with the generated parser");
    run_step.dependOn(&run_cmd.step);

    const galley_cli = galley.artifact("galley");
    const generate_cmd = b.addRunArtifact(galley_cli);
    if (b.args) |args| {
        generate_cmd.addArgs(args);
    } else {
        generate_cmd.addArg(".");
    }
    const generate_step = b.step("generate", "Regenerate the parser from the grammar file");
    generate_step.dependOn(&generate_cmd.step);
}
