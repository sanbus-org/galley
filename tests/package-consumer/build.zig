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
        .root_source_file = galley.path("languages/galley/procedures.zig"),
        .target = target,
        .optimize = optimize,
    });
    const config_mod = b.createModule(.{
        .root_source_file = galley.path("languages/galley/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    const error_messages_mod = b.createModule(.{
        .root_source_file = galley.path("languages/galley/ll_error_messages.zig"),
        .target = target,
        .optimize = optimize,
    });
    const parser_source_mod = b.createModule(.{
        .root_source_file = galley.path("languages/galley/_ll-parser.zig"),
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

    const consumer_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "galley_generator", .module = galley.module("galley_generator") },
        },
    });
    const consumer = b.addExecutable(.{
        .name = "galley-package-consumer",
        .root_module = consumer_mod,
    });
    const run_consumer = b.addRunArtifact(consumer);
    const parser_consumer_mod = b.createModule(.{
        .root_source_file = b.path("src/parser_consumer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "galley_parser", .module = parser_mod },
        },
    });
    const parser_consumer = b.addExecutable(.{
        .name = "galley-parser-consumer",
        .root_module = parser_consumer_mod,
    });
    const run_parser_consumer = b.addRunArtifact(parser_consumer);
    b.getInstallStep().dependOn(&run_consumer.step);
    b.getInstallStep().dependOn(&run_parser_consumer.step);
}
