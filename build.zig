const std = @import("std");
const common = @import("build/common.zig");
const tests = @import("build-tests.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clap = b.dependency("clap", .{});

    const generator = common.addGeneratorModules(b, target, optimize);
    const galley_cli = common.addGalleyCli(b, target, optimize, generator, .{
        .install_default = true,
        .add_galley_step = true,
        .include_generate_parser_file = true,
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
    package_consumer_step.dependOn(&package_consumer.step);

    var dir = try b.build_root.handle.openDir(b.graph.io, common.languages_path, .{ .iterate = true });
    defer dir.close(b.graph.io);

    var walker = try dir.walk(b.allocator);
    defer walker.deinit();
    var ll_galley_exe: ?*std.Build.Step.Compile = null;
    while (try walker.next(b.graph.io)) |entry| {
        if (entry.kind != .directory and entry.kind != .sym_link) continue;

        inline for ([_][]const u8{ "ll", "lr" }) |parser_type| {
            if (try common.addLanguageParser(
                b,
                target,
                optimize,
                generator,
                clap.module("clap"),
                entry.path,
                parser_type,
            )) |parser| {
                if (std.mem.eql(u8, entry.path, "galley") and std.mem.eql(u8, parser_type, "ll")) {
                    ll_galley_exe = parser.exe;
                }
                try common.addApiBenchmark(b, target, optimize, parser);
            }
        }
    }

    const test_filters = b.option([]const []const u8, "test-filter", "Select tests by suite:, case:, and name:") orelse &.{};
    try tests.add(b, .{
        .target = target,
        .optimize = optimize,
        .clap_mod = clap.module("clap"),
        .generator = generator,
        .generate_parser_file_exe = galley_cli.generate_parser_file_exe.?,
        .ll_galley_exe = ll_galley_exe orelse return error.MissingBootstrapGalleyParser,
        .test_filters = test_filters,
    });
}
