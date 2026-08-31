const std = @import("std");
const galley_pkg = @import("galley");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const galley = b.dependency("galley", .{
        .target = target,
        .optimize = optimize,
    });
    const parser = galley_pkg.addParserModule(b, galley, .{
        .target = target,
        .optimize = optimize,
        .language_dir = b.path("."),
        .parser_type = @field(galley_pkg.ParserType, "@@PARSER_TYPE@@"),
    });

    const runner_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "galley_parser", .module = parser },
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
        generate_cmd.addArg(b.pathFromRoot("."));
    }
    const generate_step = b.step("generate", "Regenerate the parser from the grammar file");
    generate_step.dependOn(&generate_cmd.step);
}
