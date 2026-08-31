const std = @import("std");
const galley_pkg = @import("galley");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const galley = b.dependency("galley", .{
        .target = target,
        .optimize = optimize,
    });
    const parser_mod = galley_pkg.addParserModule(b, galley, .{
        .target = target,
        .optimize = optimize,
        .language_dir = galley.path("languages/galley"),
        .parser_type = .ll,
        .procedures_imports = &.{
            .{ .name = "generator_common", .module = galley.module("generator_common") },
        },
    });

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
