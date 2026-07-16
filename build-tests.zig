const std = @import("std");
const common = @import("build/common.zig");
const generated_parser_matrix = @import("build/generated_parser_matrix.zig");
const test_selection = @import("build/test_selection.zig");

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
    const ll_galley = (try common.addLanguageParser(b, target, optimize, generator, clap.module("clap"), "galley", "ll")) orelse
        return error.MissingBootstrapGalleyParser;
    const test_filters = b.option([]const []const u8, "test-filter", "Select tests by suite:, case:, and name:") orelse &.{};

    try add(b, .{
        .target = target,
        .optimize = optimize,
        .clap_mod = clap.module("clap"),
        .generator = generator,
        .generator_cli_mod = galley_cli.generator_cli_mod,
        .generate_parser_file_exe = galley_cli.generate_parser_file_exe.?,
        .ll_galley_exe = ll_galley.exe,
        .test_filters = test_filters,
    });
}

pub const Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    clap_mod: *std.Build.Module,
    generator: common.GeneratorModules,
    generator_cli_mod: *std.Build.Module,
    generate_parser_file_exe: *std.Build.Step.Compile,
    ll_galley_exe: *std.Build.Step.Compile,
    test_filters: []const []const u8,
};

pub fn add(b: *std.Build, options: Options) !void {
    const target = options.target;
    const optimize = options.optimize;
    const generator = options.generator;
    const generate_parser_file_exe = options.generate_parser_file_exe;

    // Usage: zig build test -Dtest-filter="case:ll-sanbus"
    // Usage: zig build test -Dtest-filter="suite:runtime" -Dtest-filter="name:dropSelf"
    // Long-running samples: zig build test --test-timeout 30m
    const selection = try test_selection.Selection.parse(b.allocator, options.test_filters);
    var filtered_test_run_steps: std.ArrayList(*std.Build.Step) = .empty;
    var matrix_filtered_test_run_steps: std.ArrayList(*std.Build.Step) = .empty;

    const test_step = b.step("test", "Run all tests (build + generator + runtime + matrix + parity)");

    if (selection.includes(.build)) {
        const build_test_mod = b.createModule(.{
            .root_source_file = b.path("build/test_selection.zig"),
            .target = target,
            .optimize = optimize,
        });
        const build_tests = b.addTest(.{
            .name = "build-tests",
            .root_module = build_test_mod,
            .filters = selection.names,
        });
        const run_build_tests = b.addRunArtifact(build_tests);
        test_step.dependOn(&run_build_tests.step);
        trackFilteredTestRun(b.allocator, &filtered_test_run_steps, selection.names, &run_build_tests.step);
    }

    if (selection.includes(.generator)) {
        const generator_tests = b.addTest(.{
            .name = "generator-tests",
            .root_module = generator.galley_generator_mod,
            .filters = selection.names,
        });
        const run_generator_tests = b.addRunArtifact(generator_tests);
        test_step.dependOn(&run_generator_tests.step);
        trackFilteredTestRun(b.allocator, &filtered_test_run_steps, selection.names, &run_generator_tests.step);

        const generator_cli_tests = b.addTest(.{
            .name = "generator-cli-tests",
            .root_module = options.generator_cli_mod,
            .filters = selection.names,
        });
        const run_generator_cli_tests = b.addRunArtifact(generator_cli_tests);
        test_step.dependOn(&run_generator_cli_tests.step);
        trackFilteredTestRun(b.allocator, &filtered_test_run_steps, selection.names, &run_generator_cli_tests.step);

        inline for ([_][]const u8{ "ll", "lr" }) |parser_type| {
            const run_procedure_hook_tests = try addProcedureHookTests(b, options, parser_type, selection.names);
            test_step.dependOn(&run_procedure_hook_tests.step);
            trackFilteredTestRun(b.allocator, &filtered_test_run_steps, selection.names, &run_procedure_hook_tests.step);
        }
    }

    if (selection.includes(.runtime)) {
        const runtime_test_procedures_mod = b.createModule(.{
            .root_source_file = b.path("languages/galley/procedures.zig"),
            .target = target,
            .optimize = optimize,
        });
        const runtime_test_config_mod = b.createModule(.{
            .root_source_file = b.path("languages/galley/config.zig"),
            .target = target,
            .optimize = optimize,
        });
        const runtime_test_error_messages_mod = b.createModule(.{
            .root_source_file = b.path("languages/galley/ll_error_messages.zig"),
            .target = target,
            .optimize = optimize,
        });
        const runtime_test_parser_mod = b.createModule(.{
            .root_source_file = b.path("languages/galley/_ll-parser.zig"),
            .target = target,
            .optimize = optimize,
        });
        const runtime_test_options = b.addOptions();
        runtime_test_options.addOption(bool, "include", true);
        const runtime_test_mod = b.createModule(.{
            .root_source_file = b.path("src/runtime/api.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "procedures", .module = runtime_test_procedures_mod },
                .{ .name = "config", .module = runtime_test_config_mod },
                .{ .name = "error_messages", .module = runtime_test_error_messages_mod },
                .{ .name = "parser", .module = runtime_test_parser_mod },
                .{ .name = "runtime_test_options", .module = runtime_test_options.createModule() },
            },
        });
        runtime_test_mod.addImport("galley", runtime_test_mod);
        runtime_test_procedures_mod.addImport("galley", runtime_test_mod);
        runtime_test_procedures_mod.addImport("ll_generator", generator.ll_generator_mod);
        runtime_test_procedures_mod.addImport("lr_generator", generator.lr_generator_mod);
        runtime_test_config_mod.addImport("galley", runtime_test_mod);
        runtime_test_error_messages_mod.addImport("galley", runtime_test_mod);
        runtime_test_parser_mod.addImport("galley", runtime_test_mod);
        const runtime_tests = b.addTest(.{
            .name = "runtime-tests",
            .root_module = runtime_test_mod,
            .filters = selection.names,
        });
        const run_runtime_tests = b.addRunArtifact(runtime_tests);
        test_step.dependOn(&run_runtime_tests.step);
        trackFilteredTestRun(b.allocator, &filtered_test_run_steps, selection.names, &run_runtime_tests.step);
    }

    const generated_parser_matrix_step = b.step("test-generated-parser-matrix", "Generate and test parser option matrix");
    if (selection.includesMatrix()) {
        const matrix_work = DependencyGroup.create(b, "generated-parser-matrix-work");
        _ = try generated_parser_matrix.add(b, &matrix_work.step, .{
            .target = target,
            .optimize = optimize,
            .clap_mod = options.clap_mod,
            .generator_modules = generator,
            .generate_parser_file_exe = generate_parser_file_exe,
            .selection = selection,
            .filtered_test_run_steps = &matrix_filtered_test_run_steps,
        });
        generated_parser_matrix_step.dependOn(&matrix_work.step);
        test_step.dependOn(&matrix_work.step);
        filtered_test_run_steps.appendSlice(b.allocator, matrix_filtered_test_run_steps.items) catch @panic("OOM");
        if (selection.names.len != 0) {
            addTestFilterGuard(b, generated_parser_matrix_step, matrix_filtered_test_run_steps.items);
        }
    } else {
        addSelectionFailure(b, generated_parser_matrix_step, "the selected filters do not include a matrix suite");
    }

    const parity_step = b.step("test-galley-bootstrap-parity", "Compare parser output generated by ll-galley and lr-galley");
    if (selection.includes(.galley_parity)) {
        const generate_lr_galley_parser = b.addRunArtifact(generate_parser_file_exe);
        generate_lr_galley_parser.stdio = .inherit;
        generate_lr_galley_parser.addArg("--grammar");
        generate_lr_galley_parser.addFileArg(b.path("languages/galley/lr.grm"));
        generate_lr_galley_parser.addArg("--parser-type");
        generate_lr_galley_parser.addArg("lr");
        generate_lr_galley_parser.addArg("--label");
        generate_lr_galley_parser.addArg("lr/galley/bootstrap-parity");
        generate_lr_galley_parser.addArg("--output");
        const lr_galley_parser_path = generate_lr_galley_parser.addOutputFileArg("galley-lr-bootstrap.zig");
        const lr_galley_exe = addGalleyBootstrapParser(
            b,
            target,
            optimize,
            generator,
            options.clap_mod,
            lr_galley_parser_path,
        );

        parity_step.dependOn(&options.ll_galley_exe.step);
        parity_step.dependOn(&lr_galley_exe.step);
        try addGalleyBootstrapParityCase(b, parity_step, options.ll_galley_exe, lr_galley_exe, "json-ll-no-ast", "languages/json/ll.grm", "_ll-parser.zig", &.{"--no-ast"});
        try addGalleyBootstrapParityCase(b, parity_step, options.ll_galley_exe, lr_galley_exe, "json-lr-no-ast", "languages/json/lr.grm", "_lr-parser.zig", &.{"--no-ast"});
        try addGalleyBootstrapParityCase(b, parity_step, options.ll_galley_exe, lr_galley_exe, "json-ll-with-ast", "languages/json/ll.grm", "_ll-parser.zig", &.{"--with-ast"});
        try addGalleyBootstrapParityCase(b, parity_step, options.ll_galley_exe, lr_galley_exe, "json-lr-with-ast", "languages/json/lr.grm", "_lr-parser.zig", &.{"--with-ast"});
        test_step.dependOn(parity_step);
    } else {
        addSelectionFailure(b, parity_step, "the selected filters do not include suite:galley-parity");
    }

    if (selection.names.len != 0) {
        addTestFilterGuard(b, test_step, filtered_test_run_steps.items);
    }
}

fn addProcedureHookTests(
    b: *std.Build,
    options: Options,
    parser_type: []const u8,
    filters: []const []const u8,
) !*std.Build.Step.Run {
    const generated_name = try std.fmt.allocPrint(b.allocator, "procedure-hooks-{s}-parser.zig", .{parser_type});
    const generate_parser = b.addRunArtifact(options.generate_parser_file_exe);
    generate_parser.addArg("--grammar");
    generate_parser.addFileArg(b.path("tests/procedure-hooks/grammar.grm"));
    generate_parser.addArg("--parser-type");
    generate_parser.addArg(parser_type);
    generate_parser.addArg("--label");
    generate_parser.addArg(try std.fmt.allocPrint(b.allocator, "{s}/procedure-hooks/tests", .{parser_type}));
    generate_parser.addArg("--output");
    const generated_parser_path = generate_parser.addOutputFileArg(generated_name);
    generate_parser.addArgs(&.{
        "--with-ast",
        "--with-procedures",
        "--input-size",
        "16",
        "--ast-for-terminals",
    });
    generate_parser.stdio = .inherit;

    const procedures_mod = b.createModule(.{
        .root_source_file = b.path("tests/procedure-hooks/procedures.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const config_mod = b.createModule(.{
        .root_source_file = b.path("tests/procedure-hooks/config.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const error_messages_mod = b.createModule(.{
        .root_source_file = b.path("tests/procedure-hooks/error_messages.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const parser_name = try std.fmt.allocPrint(b.allocator, "procedure-hooks-{s}", .{parser_type});
    const generated_parser = common.addGeneratedParserModule(
        b,
        options.target,
        options.optimize,
        parser_name,
        try std.fmt.allocPrint(b.allocator, "{s}-source", .{parser_name}),
        generated_parser_path,
        procedures_mod,
        config_mod,
        error_messages_mod,
        options.generator.ll_generator_mod,
        options.generator.lr_generator_mod,
    );

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/procedure_hooks_test.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{.{ .name = "parser-under-test", .module = generated_parser.runtime_mod }},
    });
    const tests = b.addTest(.{
        .name = try std.fmt.allocPrint(b.allocator, "procedure-hooks-{s}-tests", .{parser_type}),
        .root_module = test_mod,
        .filters = filters,
    });
    return b.addRunArtifact(tests);
}

const DependencyGroup = struct {
    step: std.Build.Step,

    fn create(b: *std.Build, name: []const u8) *DependencyGroup {
        const group = b.allocator.create(DependencyGroup) catch @panic("OOM");
        group.* = .{
            .step = std.Build.Step.init(.{
                .id = .top_level,
                .name = name,
                .owner = b,
                .makeFn = make,
            }),
        };
        return group;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = step;
        _ = options;
    }
};

fn trackFilteredTestRun(
    allocator: std.mem.Allocator,
    filtered_test_run_steps: *std.ArrayList(*std.Build.Step),
    name_filters: []const []const u8,
    run_step: *std.Build.Step,
) void {
    if (name_filters.len == 0) return;
    filtered_test_run_steps.append(allocator, run_step) catch @panic("OOM");
}

const SelectionFailure = struct {
    step: std.Build.Step,
    message: []const u8,

    fn create(b: *std.Build, message: []const u8) *SelectionFailure {
        const failure = b.allocator.create(SelectionFailure) catch @panic("OOM");
        failure.* = .{
            .step = std.Build.Step.init(.{
                .id = .fail,
                .name = "invalid-test-selection",
                .owner = b,
                .makeFn = make,
            }),
            .message = message,
        };
        return failure;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;
        const failure: *SelectionFailure = @fieldParentPtr("step", step);
        try step.result_error_msgs.append(step.owner.allocator, failure.message);
        return error.MakeFailed;
    }
};

fn addSelectionFailure(b: *std.Build, target_step: *std.Build.Step, message: []const u8) void {
    const failure = SelectionFailure.create(b, message);
    target_step.dependOn(&failure.step);
}

const TestFilterGuard = struct {
    step: std.Build.Step,
    run_steps: []const *std.Build.Step,

    fn create(b: *std.Build, run_steps: []const *std.Build.Step) *TestFilterGuard {
        const guard = b.allocator.create(TestFilterGuard) catch @panic("OOM");
        guard.* = .{
            .step = std.Build.Step.init(.{
                .id = .fail,
                .name = "test-filter-guard",
                .owner = b,
                .makeFn = make,
            }),
            .run_steps = run_steps,
        };
        return guard;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) !void {
        _ = options;
        const guard: *TestFilterGuard = @fieldParentPtr("step", step);

        var total_ran: u32 = 0;
        for (guard.run_steps) |run_step| {
            total_ran += run_step.test_results.test_count;
        }
        if (total_ran == 0) {
            try step.result_error_msgs.append(
                step.owner.allocator,
                "no tests matched -Dtest-filter; nothing was run",
            );
            return error.MakeFailed;
        }
    }
};

fn addTestFilterGuard(
    b: *std.Build,
    test_step: *std.Build.Step,
    run_steps: []const *std.Build.Step,
) void {
    const guard = TestFilterGuard.create(b, run_steps);
    for (run_steps) |run_step| {
        guard.step.dependOn(run_step);
    }
    test_step.dependOn(&guard.step);
}

fn addGalleyBootstrapParser(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    generator: common.GeneratorModules,
    clap_mod: *std.Build.Module,
    parser_source: std.Build.LazyPath,
) *std.Build.Step.Compile {
    const procedures_mod = b.addModule("galley-bootstrap-parity-procedures", .{
        .root_source_file = b.path("languages/galley/procedures.zig"),
        .target = target,
        .optimize = optimize,
    });
    const config_mod = b.addModule("galley-bootstrap-parity-config", .{
        .root_source_file = b.path("languages/galley/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    const error_messages_mod = b.addModule("galley-bootstrap-parity-lr-error-messages", .{
        .root_source_file = b.path("languages/galley/lr_error_messages.zig"),
        .target = target,
        .optimize = optimize,
    });
    const generated_parser = common.addGeneratedParserModule(
        b,
        target,
        optimize,
        "lr-galley-bootstrap-parity-runtime",
        "lr-galley-bootstrap-parity-source",
        parser_source,
        procedures_mod,
        config_mod,
        error_messages_mod,
        generator.ll_generator_mod,
        generator.lr_generator_mod,
    );

    const cli_options = b.addOptions();
    cli_options.addOption([]const u8, "api_benchmark_step", "run-api-bench-lr-galley");
    const cli_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/parser.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "clap", .module = clap_mod },
            .{ .name = "build_options", .module = cli_options.createModule() },
            .{ .name = "galley", .module = generated_parser.runtime_mod },
        },
    });
    return b.addExecutable(.{
        .name = "lr-galley-bootstrap-parity",
        .root_module = cli_mod,
    });
}

fn addGalleyBootstrapParityCase(
    b: *std.Build,
    parity_step: *std.Build.Step,
    ll_galley_exe: *std.Build.Step.Compile,
    lr_galley_exe: *std.Build.Step.Compile,
    name: []const u8,
    grammar_path: []const u8,
    output_name: []const u8,
    options: []const []const u8,
) !void {
    const base_dir = try std.fs.path.join(b.allocator, &.{ ".zig-cache", "galley-bootstrap-parity", name });
    const ll_dir = try std.fs.path.join(b.allocator, &.{ base_dir, "ll" });
    const lr_dir = try std.fs.path.join(b.allocator, &.{ base_dir, "lr" });
    const grammar_name = std.fs.path.basename(grammar_path);
    const ll_input = try std.fs.path.join(b.allocator, &.{ ll_dir, grammar_name });
    const lr_input = try std.fs.path.join(b.allocator, &.{ lr_dir, grammar_name });
    const ll_output = try std.fs.path.join(b.allocator, &.{ ll_dir, output_name });
    const lr_output = try std.fs.path.join(b.allocator, &.{ lr_dir, output_name });

    const setup = b.addSystemCommand(&.{ "mkdir", "-p", ll_dir, lr_dir });
    setup.has_side_effects = true;

    const copy_ll_input = b.addSystemCommand(&.{ "cp", grammar_path, ll_input });
    copy_ll_input.has_side_effects = true;
    copy_ll_input.step.dependOn(&setup.step);

    const copy_lr_input = b.addSystemCommand(&.{ "cp", grammar_path, lr_input });
    copy_lr_input.has_side_effects = true;
    copy_lr_input.step.dependOn(&setup.step);

    const run_ll_galley = b.addRunArtifact(ll_galley_exe);
    run_ll_galley.has_side_effects = true;
    run_ll_galley.addArg(ll_input);
    run_ll_galley.addArgs(options);
    run_ll_galley.step.dependOn(&copy_ll_input.step);

    const run_lr_galley = b.addRunArtifact(lr_galley_exe);
    run_lr_galley.has_side_effects = true;
    run_lr_galley.addArg(lr_input);
    run_lr_galley.addArgs(options);
    run_lr_galley.step.dependOn(&copy_lr_input.step);

    const compare_outputs = b.addSystemCommand(&.{ "diff", "-u", ll_output, lr_output });
    compare_outputs.has_side_effects = true;
    compare_outputs.step.dependOn(&run_ll_galley.step);
    compare_outputs.step.dependOn(&run_lr_galley.step);
    parity_step.dependOn(&compare_outputs.step);
}
