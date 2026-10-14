const std = @import("std");
const galley_pkg = @import("galley");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const galley = b.dependency("galley", .{
        .target = target,
        .optimize = optimize,
    });

    // `-Dgrammar` selects the grammar under languages/ that the benchmark
    // compiles directly (default json), the way the python, js, and java
    // benchmark builds take the parser directory. `-Dast`, `-Dprocedures`,
    // `-Derror-recovery`, and `-Dast-for-terminals` splice over
    // languages/<grammar>/config.zig's constants so one source tree builds
    // every benchmark CI matrix row without editing the checked-in config.
    // The demo keeps its own checked-in config; only the benchmark honors
    // the overrides.
    const grammar = b.option(
        []const u8,
        "grammar",
        "Grammar directory under languages/ to compile the benchmark from",
    ) orelse "json";
    const language_dir = b.fmt("../../languages/{s}", .{grammar});

    const config_overrides = galley_pkg.readConfigOverrides(b);
    const benchmark_config: ?std.Build.LazyPath = if (config_overrides.isUnset())
        null
    else
        galley_pkg.overriddenConfigRoot(
            b,
            grammar,
            b.fmt("{s}/config.zig", .{language_dir}),
            config_overrides,
        ) catch |err| {
            std.debug.panic(
                "failed to apply config overrides to {s}/config.zig: {s}",
                .{ language_dir, @errorName(err) },
            );
        };

    const generate_demo = b.addRunArtifact(galley.artifact("galley"));
    generate_demo.addFileArg(b.path("."));
    generate_demo.addFileInput(b.path("ll.grm"));
    generate_demo.addFileInput(b.path("config.zig"));

    // Pin --parser-type ll the way configure-benchmarks.sh does: one
    // library embeds one parser, and languages/json also ships lr.grm.
    const generate_benchmark = b.addRunArtifact(galley.artifact("galley"));
    generate_benchmark.addArgs(&.{ "--parser-type", "ll" });
    generate_benchmark.addFileArg(b.path(language_dir));
    generate_benchmark.addFileInput(b.path(b.fmt("{s}/ll.grm", .{language_dir})));
    generate_benchmark.addFileInput(b.path(b.fmt("{s}/config.zig", .{language_dir})));

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
    run_demo.addPassthruArgs();
    const run_step = b.step("run", "Run the key/value demo");
    run_step.dependOn(&run_demo.step);

    const benchmark_parser = galley_pkg.addParserModule(b, galley, .{
        .target = target,
        .optimize = optimize,
        .language_dir = b.path(language_dir),
        .parser_type = .ll,
        .config = benchmark_config,
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
    run_benchmark.addPassthruArgs();
    const run_benchmark_step = b.step("run-benchmark", "Run the throughput benchmark");
    run_benchmark_step.dependOn(&run_benchmark.step);
}
