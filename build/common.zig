const std = @import("std");

pub const languages_path = "languages";

pub const CoreModules = struct {
    generator_common_mod: *std.Build.Module,
    ll_generator_mod: *std.Build.Module,
    lr_generator_mod: *std.Build.Module,
    galley_grammar_library_mod: *std.Build.Module,
    galley_generator_mod: *std.Build.Module,
};

pub const GalleyCli = struct {
    generator_cli_exe: *std.Build.Step.Compile,
    install_generator_cli: *std.Build.Step.InstallArtifact,
    generate_parser_file_exe: ?*std.Build.Step.Compile = null,
};

pub const GalleyCliOptions = struct {
    install_default: bool = false,
    add_galley_step: bool = false,
    include_generate_parser_file: bool = false,
};

pub const LanguageParser = struct {
    entry_path: []const u8,
    parser_type: []const u8,
    parser_name: []const u8,
    galley_parser_mod: *std.Build.Module,
    procedures_mod: *std.Build.Module,
    config_mod: *std.Build.Module,
    parser_mod: *std.Build.Module,
    galley_cli_mod: *std.Build.Module,
    exe: *std.Build.Step.Compile,
    install_artifact: *std.Build.Step.InstallArtifact,
    build_step: *std.Build.Step,
    run_step: *std.Build.Step,
};

pub fn addCoreModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) CoreModules {
    const generator_common_mod = b.addModule("generator_common", .{
        .root_source_file = b.path("src/generator/common.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ll_generator_mod = b.addModule("ll_generator", .{
        .root_source_file = b.path("src/generator/ll.zig"),
        .target = target,
        .optimize = optimize,
    });
    ll_generator_mod.addImport("generator_common", generator_common_mod);
    const lr_generator_mod = b.addModule("lr_generator", .{
        .root_source_file = b.path("src/generator/lr.zig"),
        .target = target,
        .optimize = optimize,
    });
    lr_generator_mod.addImport("generator_common", generator_common_mod);
    const galley_grammar_procedures_mod = b.addModule("galley_grammar_procedures", .{
        .root_source_file = b.path("languages/galley/procedures.zig"),
        .target = target,
        .optimize = optimize,
    });
    const galley_grammar_config_mod = b.addModule("galley_grammar_config", .{
        .root_source_file = b.path("languages/galley/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    const galley_grammar_parser_mod = b.addModule("galley_grammar_parser", .{
        .root_source_file = b.path("languages/galley/_ll-parser.zig"),
        .target = target,
        .optimize = optimize,
    });
    const galley_grammar_library_mod = b.addModule("galley_grammar", .{
        .root_source_file = b.path("src/parser_library.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "procedures", .module = galley_grammar_procedures_mod },
            .{ .name = "config", .module = galley_grammar_config_mod },
            .{ .name = "parser", .module = galley_grammar_parser_mod },
        },
    });
    galley_grammar_library_mod.addImport("galley", galley_grammar_library_mod);
    galley_grammar_procedures_mod.addImport("galley", galley_grammar_library_mod);
    galley_grammar_procedures_mod.addImport("ll_generator", ll_generator_mod);
    galley_grammar_procedures_mod.addImport("lr_generator", lr_generator_mod);
    galley_grammar_config_mod.addImport("galley", galley_grammar_library_mod);
    galley_grammar_parser_mod.addImport("galley", galley_grammar_library_mod);

    const galley_generator_mod = b.addModule("galley_generator", .{
        .root_source_file = b.path("src/generator/api.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "generator_common", .module = generator_common_mod },
            .{ .name = "galley_grammar", .module = galley_grammar_library_mod },
            .{ .name = "ll_generator", .module = ll_generator_mod },
            .{ .name = "lr_generator", .module = lr_generator_mod },
        },
    });

    return .{
        .generator_common_mod = generator_common_mod,
        .ll_generator_mod = ll_generator_mod,
        .lr_generator_mod = lr_generator_mod,
        .galley_grammar_library_mod = galley_grammar_library_mod,
        .galley_generator_mod = galley_generator_mod,
    };
}

pub fn addGalleyCli(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: CoreModules,
    options: GalleyCliOptions,
) GalleyCli {
    const cli_options = b.addOptions();
    cli_options.addOption([]const u8, "galley_root", b.pathFromRoot("."));
    cli_options.addOption(
        []const u8,
        "clap_source",
        b.pathFromRoot("zig-pkg/clap-0.12.0-oBajB7foAQDqlSwaSG5g0yq7xGbQARUsBk5T64gAOqP5/clap.zig"),
    );

    const generator_cli_mod = b.createModule(.{
        .root_source_file = b.path("src/generator/cli.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_options", .module = cli_options.createModule() },
            .{ .name = "galley_generator", .module = core.galley_generator_mod },
        },
    });
    const generator_cli_exe = b.addExecutable(.{
        .name = "galley",
        .root_module = generator_cli_mod,
    });
    const install_generator_cli = b.addInstallArtifact(generator_cli_exe, .{});

    if (options.install_default) {
        b.getInstallStep().dependOn(&install_generator_cli.step);
    }
    if (options.add_galley_step) {
        const generator_cli_step = b.step("galley", "Build the Galley generator");
        generator_cli_step.dependOn(&install_generator_cli.step);
    }

    var generate_parser_file_exe: ?*std.Build.Step.Compile = null;
    if (options.include_generate_parser_file) {
        const generate_parser_file_mod = b.createModule(.{
            .root_source_file = b.path("src/tools/generate_parser_file.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "galley_generator", .module = core.galley_generator_mod },
            },
        });
        generate_parser_file_exe = b.addExecutable(.{
            .name = "generate-parser-file",
            .root_module = generate_parser_file_mod,
        });
    }

    return .{
        .generator_cli_exe = generator_cli_exe,
        .install_generator_cli = install_generator_cli,
        .generate_parser_file_exe = generate_parser_file_exe,
    };
}

pub fn parserName(
    allocator: std.mem.Allocator,
    parser_type: []const u8,
    entry_path: []const u8,
) ![]const u8 {
    return std.mem.concat(allocator, u8, &.{ parser_type, "-", entry_path });
}

pub fn apiBenchmarkRunStepName(
    allocator: std.mem.Allocator,
    parser_name: []const u8,
) ![]const u8 {
    return std.mem.concat(allocator, u8, &.{ "run-api-bench-", parser_name });
}

pub fn addLanguageParser(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: CoreModules,
    clap_mod: *std.Build.Module,
    entry_path: []const u8,
    parser_type: []const u8,
) !?LanguageParser {
    const parser_file_name = try parserFileName(b.allocator, parser_type);
    defer b.allocator.free(parser_file_name);

    const parser_path = try std.fs.path.join(
        b.allocator,
        &.{ languages_path, entry_path, parser_file_name },
    );
    defer b.allocator.free(parser_path);

    const exists = b.build_root.handle.access(b.graph.io, parser_path, .{});
    if (exists) |_| {} else |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    }

    return try addLanguageParserFromFile(
        b,
        target,
        optimize,
        core,
        clap_mod,
        entry_path,
        parser_type,
        b.path(parser_path),
    );
}

pub fn addLanguageParserFromFile(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    core: CoreModules,
    clap_mod: *std.Build.Module,
    entry_path: []const u8,
    parser_type: []const u8,
    parser_file: std.Build.LazyPath,
) !LanguageParser {
    const procedures_path = try std.fs.path.join(
        b.allocator,
        &.{ languages_path, entry_path, "procedures.zig" },
    );
    defer b.allocator.free(procedures_path);

    const config_path = try std.fs.path.join(
        b.allocator,
        &.{ languages_path, entry_path, "config.zig" },
    );
    defer b.allocator.free(config_path);

    const procedures_mod = b.addModule("procedures", .{
        .root_source_file = b.path(procedures_path),
        .target = target,
    });
    const config_mod = b.addModule("config", .{
        .root_source_file = b.path(config_path),
        .target = target,
    });
    const parser_mod = b.addModule("parser", .{
        .root_source_file = parser_file,
        .target = target,
    });

    const parser_name = try parserName(b.allocator, parser_type, entry_path);
    const api_benchmark_run_step_name = try apiBenchmarkRunStepName(b.allocator, parser_name);
    const parser_cli_options = b.addOptions();
    parser_cli_options.addOption([]const u8, "api_benchmark_step", api_benchmark_run_step_name);

    const galley_parser_mod = b.addModule(parser_name, .{
        .root_source_file = b.path("src/parser_library.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "procedures", .module = procedures_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "parser", .module = parser_mod },
        },
    });
    galley_parser_mod.addImport("galley", galley_parser_mod);

    const galley_cli_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "clap", .module = clap_mod },
            .{ .name = "build_options", .module = parser_cli_options.createModule() },
            .{ .name = "galley", .module = galley_parser_mod },
        },
    });
    procedures_mod.addImport("galley", galley_parser_mod);
    procedures_mod.addImport("ll_generator", core.ll_generator_mod);
    procedures_mod.addImport("lr_generator", core.lr_generator_mod);
    config_mod.addImport("galley", galley_parser_mod);
    parser_mod.addImport("galley", galley_parser_mod);

    const exe = b.addExecutable(.{
        .name = parser_name,
        .root_module = galley_cli_mod,
    });
    const install_artifact = b.addInstallArtifact(exe, .{});

    const description = try std.mem.concat(
        b.allocator,
        u8,
        &.{ "Run the ", entry_path, " compiler" },
    );

    const build_step = b.step(parser_name, description);
    build_step.dependOn(&install_artifact.step);

    const run_step_name = try std.mem.concat(
        b.allocator,
        u8,
        &.{ "run-", parser_name },
    );
    const run_step = b.step(run_step_name, description);

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(&install_artifact.step);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    return .{
        .entry_path = entry_path,
        .parser_type = parser_type,
        .parser_name = parser_name,
        .galley_parser_mod = galley_parser_mod,
        .procedures_mod = procedures_mod,
        .config_mod = config_mod,
        .parser_mod = parser_mod,
        .galley_cli_mod = galley_cli_mod,
        .exe = exe,
        .install_artifact = install_artifact,
        .build_step = build_step,
        .run_step = run_step,
    };
}

pub fn addApiBenchmark(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    parser: LanguageParser,
) !void {
    const api_benchmark_name = try std.mem.concat(
        b.allocator,
        u8,
        &.{ "api-bench-", parser.parser_name },
    );
    const api_benchmark_run_step_name = try std.mem.concat(
        b.allocator,
        u8,
        &.{ "run-", api_benchmark_name },
    );

    const api_benchmark_mod = b.createModule(.{
        .root_source_file = b.path("src/benchmarks/api_benchmark.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "galley", .module = parser.galley_parser_mod },
        },
    });
    const api_benchmark_exe = b.addExecutable(.{
        .name = api_benchmark_name,
        .root_module = api_benchmark_mod,
    });
    const install_api_benchmark_artifact = b.addInstallArtifact(api_benchmark_exe, .{});

    const api_benchmark_description = try std.mem.concat(
        b.allocator,
        u8,
        &.{ "Benchmark the ", parser.entry_path, " parser API" },
    );

    const api_benchmark_step = b.step(api_benchmark_name, api_benchmark_description);
    api_benchmark_step.dependOn(&install_api_benchmark_artifact.step);

    const api_benchmark_run_step = b.step(api_benchmark_run_step_name, api_benchmark_description);
    const api_benchmark_run_cmd = b.addRunArtifact(api_benchmark_exe);
    api_benchmark_run_step.dependOn(&api_benchmark_run_cmd.step);
    api_benchmark_run_cmd.step.dependOn(&install_api_benchmark_artifact.step);

    if (b.args) |args| {
        api_benchmark_run_cmd.addArgs(args);
    }
}

pub fn addDelegatedTestStep(
    b: *std.Build,
    name: []const u8,
    description: []const u8,
    delegated_step_name: []const u8,
    test_filter_opt: []const []const u8,
) void {
    const step = b.step(name, description);
    const run_tests = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "build",
        "--build-file",
        b.pathFromRoot("build-tests.zig"),
        delegated_step_name,
    });
    for (test_filter_opt) |f| {
        const d = std.fmt.allocPrint(b.allocator, "-Dtest-filter={s}", .{f}) catch unreachable;
        run_tests.addArg(d);
    }
    if (b.args) |args| {
        run_tests.addArg("--");
        run_tests.addArgs(args);
    }
    step.dependOn(&run_tests.step);
}

fn parserFileName(allocator: std.mem.Allocator, parser_type: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "_{s}-parser.zig", .{parser_type});
}
