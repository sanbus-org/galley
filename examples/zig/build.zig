const std = @import("std");
const galley_pkg = @import("galley");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const galley = b.dependency("galley", .{
        .target = target,
        .optimize = optimize,
    });

    const generate_demo = b.addRunArtifact(galley.artifact("galley"));
    generate_demo.addArg(b.pathFromRoot("."));
    generate_demo.addFileInput(b.path("ll.grm"));
    generate_demo.addFileInput(b.path("config.zig"));

    const generate_benchmark = b.addRunArtifact(galley.artifact("galley"));
    generate_benchmark.addArg(b.pathFromRoot("benchmark"));
    generate_benchmark.addFileInput(b.path("benchmark/ll.grm"));
    generate_benchmark.addFileInput(b.path("benchmark/config.zig"));

    const demo_parser = galley_pkg.addParserModule(b, galley, .{
        .target = target,
        .optimize = optimize,
        .language_dir = b.path("."),
        .parser_type = .ll,
    });
    const demo = b.addExecutable(.{
        .name = "demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "parser", .module = demo_parser },
            },
        }),
    });
    demo.step.dependOn(&generate_demo.step);
    b.installArtifact(demo);

    const run_demo = b.addRunArtifact(demo);
    if (b.args) |args| {
        run_demo.addArgs(args);
    }
    const run_step = b.step("run", "Run the key/value demo");
    run_step.dependOn(&run_demo.step);

    const benchmark_parser = galley_pkg.addParserModule(b, galley, .{
        .target = target,
        .optimize = optimize,
        .language_dir = b.path("benchmark"),
        .parser_type = .ll,
    });
    const benchmark = b.addExecutable(.{
        .name = "benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmark.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "parser", .module = benchmark_parser },
            },
        }),
    });
    benchmark.step.dependOn(&generate_benchmark.step);
    b.installArtifact(benchmark);

    const run_benchmark = b.addRunArtifact(benchmark);
    if (b.args) |args| {
        run_benchmark.addArgs(args);
    }
    const run_benchmark_step = b.step("run-benchmark", "Run the JSON throughput benchmark");
    run_benchmark_step.dependOn(&run_benchmark.step);
}
