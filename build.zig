const std = @import("std");
const common = @import("build/common.zig");

pub const ParserType = common.ParserType;
pub const AddParserModuleOptions = common.AddParserModuleOptions;
pub const addParserModule = common.addParserModule;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const generator = common.addGeneratorModules(b, target, optimize);
    _ = common.addGalleyCli(b, target, optimize, generator, .{
        .install_default = true,
        .add_galley_step = true,
    });

    const package_consumer_step = b.step(
        "test-package-consumer",
        "Build and run an external project using galley_generator",
    );
    const package_consumer = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "build",
        "--build-file",
        b.pathFromRoot("tests/package-consumer/build.zig"),
    });
    if (b.graph.max_jobs) |max_jobs| {
        package_consumer.addArg(b.fmt("-j{d}", .{max_jobs}));
    }
    package_consumer_step.dependOn(&package_consumer.step);

    const test_filters = b.option([]const []const u8, "test-filter", "Select tests by suite:, case:, and name:") orelse &.{};
    _ = common.addDelegatedTestStep(b, "test", "Run all tests (build + generator + runtime + matrix + parity)", "test", test_filters, generator.ast_memory_benchmark);
    _ = common.addDelegatedTestStep(
        b,
        "test-generated-parser-matrix",
        "Generate and test parser option matrix",
        "test-generated-parser-matrix",
        test_filters,
        generator.ast_memory_benchmark,
    );
    _ = common.addDelegatedTestStep(
        b,
        "test-galley-bootstrap-parity",
        "Compare parser output from LL-backed and LR-backed generator APIs",
        "test-galley-bootstrap-parity",
        test_filters,
        generator.ast_memory_benchmark,
    );
    _ = common.addDelegatedTestStep(
        b,
        "test-benchmark-progress",
        "Run benchmark progress planning and terminal rendering tests",
        "test-benchmark-progress",
        &.{},
        generator.ast_memory_benchmark,
    );
    _ = common.addDelegatedTestStep(
        b,
        "compare-galley-recovery",
        "Show automatic and explicit recovery on the same malformed Galley grammar",
        "compare-galley-recovery",
        &.{},
        generator.ast_memory_benchmark,
    );

    var dir = try b.build_root.handle.openDir(b.graph.io, common.languages_path, .{ .iterate = true });
    defer dir.close(b.graph.io);

    var walker = try dir.walk(b.allocator);
    defer walker.deinit();
    while (try walker.next(b.graph.io)) |entry| {
        if (entry.kind != .directory and entry.kind != .sym_link) continue;

        inline for ([_][]const u8{ "ll", "lr" }) |parser_type| {
            if (try common.addLanguageParser(
                b,
                target,
                optimize,
                generator,
                entry.path,
                parser_type,
            )) |parser| {
                try common.addBenchmark(b, target, optimize, parser);
            }
        }
    }
}
