const std = @import("std");
const common = @import("build/common.zig");
const generated_parser_matrix = @import("build/generated_parser_matrix.zig");
const test_selection = @import("build/test_selection.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const generator = common.addGeneratorModules(b, target, optimize);
    const galley_cli = common.addGalleyCli(b, target, optimize, generator, .{
        .install_default = true,
        .add_galley_step = true,
        .include_generate_parser_file = true,
    });
    const test_filters = b.option([]const []const u8, "test-filter", "Select tests by suite:, case:, and name:") orelse &.{};

    try add(b, .{
        .target = target,
        .optimize = optimize,
        .generator = generator,
        .generator_cli_mod = galley_cli.generator_cli_mod,
        .generate_parser_file_exe = galley_cli.generate_parser_file_exe.?,
        .test_filters = test_filters,
    });
}

pub const Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    generator: common.GeneratorModules,
    generator_cli_mod: *std.Build.Module,
    generate_parser_file_exe: *std.Build.Step.Compile,
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
    const benchmark_progress_test_step = b.step(
        "test-benchmark-progress",
        "Run benchmark progress planning and terminal rendering tests",
    );
    const run_benchmark_progress_tests = b.addSystemCommand(&.{
        "python3",
        "-m",
        "unittest",
        "scripts/test_benchmark.py",
    });
    run_benchmark_progress_tests.setCwd(b.path("."));
    benchmark_progress_test_step.dependOn(&run_benchmark_progress_tests.step);
    const recovery_comparison = try addGalleyRecoveryComparison(b, options, selection.names);
    const recovery_comparison_step = b.step(
        "compare-galley-recovery",
        "Show automatic and explicit recovery on the same malformed Galley grammar",
    );
    recovery_comparison_step.dependOn(&recovery_comparison.run_demo.step);

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
        if (selection.names.len == 0) {
            test_step.dependOn(&run_benchmark_progress_tests.step);
        }
    }

    if (selection.includes(.generator)) {
        for (recovery_comparison.run_tests) |run_tests| {
            test_step.dependOn(&run_tests.step);
            trackFilteredTestRun(b.allocator, &filtered_test_run_steps, selection.names, &run_tests.step);
        }

        const generator_common_tests = b.addTest(.{
            .name = "generator-common-tests",
            .root_module = generator.generator_common_mod,
            .filters = selection.names,
        });
        const run_generator_common_tests = b.addRunArtifact(generator_common_tests);
        test_step.dependOn(&run_generator_common_tests.step);
        trackFilteredTestRun(b.allocator, &filtered_test_run_steps, selection.names, &run_generator_common_tests.step);

        const galley_grammar_procedure_tests = b.addTest(.{
            .name = "galley-grammar-procedure-tests",
            .root_module = generator.galley_grammar_procedures_mod,
            .filters = selection.names,
        });
        const run_galley_grammar_procedure_tests = b.addRunArtifact(galley_grammar_procedure_tests);
        test_step.dependOn(&run_galley_grammar_procedure_tests.step);
        trackFilteredTestRun(b.allocator, &filtered_test_run_steps, selection.names, &run_galley_grammar_procedure_tests.step);

        const json_unicode_procedure_test_mod = b.createModule(.{
            .root_source_file = b.path("languages/json-unicode/procedures.zig"),
            .target = target,
            .optimize = optimize,
        });
        const json_unicode_procedure_tests = b.addTest(.{
            .name = "json-unicode-procedure-tests",
            .root_module = json_unicode_procedure_test_mod,
            .filters = selection.names,
        });
        const run_json_unicode_procedure_tests = b.addRunArtifact(json_unicode_procedure_tests);
        test_step.dependOn(&run_json_unicode_procedure_tests.step);
        trackFilteredTestRun(b.allocator, &filtered_test_run_steps, selection.names, &run_json_unicode_procedure_tests.step);

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
            const run_symbol_kind_identity_tests = try addSymbolKindIdentityTests(b, options, parser_type, selection.names);
            test_step.dependOn(&run_symbol_kind_identity_tests.step);
            trackFilteredTestRun(b.allocator, &filtered_test_run_steps, selection.names, &run_symbol_kind_identity_tests.step);

            const run_procedure_hook_tests = try addProcedureHookTests(b, options, parser_type, selection.names);
            test_step.dependOn(&run_procedure_hook_tests.step);
            trackFilteredTestRun(b.allocator, &filtered_test_run_steps, selection.names, &run_procedure_hook_tests.step);

            const run_explicit_recovery_tests = try addExplicitRecoveryTests(b, options, parser_type, selection.names);
            test_step.dependOn(&run_explicit_recovery_tests.step);
            trackFilteredTestRun(b.allocator, &filtered_test_run_steps, selection.names, &run_explicit_recovery_tests.step);

            const run_galley_recovery_tests = try addGalleyRecoveryTests(b, options, parser_type, selection.names);
            test_step.dependOn(&run_galley_recovery_tests.step);
            trackFilteredTestRun(b.allocator, &filtered_test_run_steps, selection.names, &run_galley_recovery_tests.step);

            const run_json_recovery_tests = try addJsonRecoveryTests(b, options, parser_type, selection.names);
            test_step.dependOn(&run_json_recovery_tests.step);
            trackFilteredTestRun(b.allocator, &filtered_test_run_steps, selection.names, &run_json_recovery_tests.step);

            inline for (std.meta.tags(InputRefillTestKind)) |kind| {
                const run_input_refill_tests = try addInputRefillTests(b, options, parser_type, kind, selection.names);
                test_step.dependOn(&run_input_refill_tests.step);
                trackFilteredTestRun(b.allocator, &filtered_test_run_steps, selection.names, &run_input_refill_tests.step);
            }
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
        const runtime_options = b.addOptions();
        runtime_options.addOption(bool, "include_tests", true);
        runtime_options.addOption(bool, "ast_memory_benchmark", generator.ast_memory_benchmark);
        const runtime_test_mod = b.createModule(.{
            .root_source_file = b.path("src/runtime/api.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = common.runtimeLinkLibC(target),
            .imports = &.{
                .{ .name = "procedures", .module = runtime_test_procedures_mod },
                .{ .name = "config", .module = runtime_test_config_mod },
                .{ .name = "error_messages", .module = runtime_test_error_messages_mod },
                .{ .name = "parser", .module = runtime_test_parser_mod },
                .{ .name = "runtime_options", .module = runtime_options.createModule() },
            },
        });
        runtime_test_mod.addImport("galley", runtime_test_mod);
        runtime_test_procedures_mod.addImport("galley", runtime_test_mod);
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

    const parity_step = b.step("test-galley-bootstrap-parity", "Compare parser output from LL-backed and LR-backed generator APIs");
    if (selection.includes(.galley_parity)) {
        const lr_backed_generator = addLrBackedGenerator(
            b,
            target,
            optimize,
            generator,
            generate_parser_file_exe,
        );

        try addGalleyBootstrapParityCase(b, parity_step, generate_parser_file_exe, lr_backed_generator, "json-ll-no-ast", "ll", "languages/json/ll.grm", &.{"--no-ast"});
        try addGalleyBootstrapParityCase(b, parity_step, generate_parser_file_exe, lr_backed_generator, "json-lr-no-ast", "lr", "languages/json/lr.grm", &.{"--no-ast"});
        try addGalleyBootstrapParityCase(b, parity_step, generate_parser_file_exe, lr_backed_generator, "json-ll-with-ast", "ll", "languages/json/ll.grm", &.{"--with-ast"});
        try addGalleyBootstrapParityCase(b, parity_step, generate_parser_file_exe, lr_backed_generator, "json-lr-with-ast", "lr", "languages/json/lr.grm", &.{"--with-ast"});
        try addGalleyBootstrapParityCase(b, parity_step, generate_parser_file_exe, lr_backed_generator, "json-recovery-ll-no-ast", "ll", "languages/json-recovery/ll.grm", &.{ "--no-ast", "--with-error-recovery" });
        try addGalleyBootstrapParityCase(b, parity_step, generate_parser_file_exe, lr_backed_generator, "json-recovery-lr-no-ast", "lr", "languages/json-recovery/lr.grm", &.{ "--no-ast", "--with-error-recovery" });
        try addGalleyBootstrapParityCase(b, parity_step, generate_parser_file_exe, lr_backed_generator, "json-recovery-ll-with-ast", "ll", "languages/json-recovery/ll.grm", &.{ "--with-ast", "--with-error-recovery" });
        try addGalleyBootstrapParityCase(b, parity_step, generate_parser_file_exe, lr_backed_generator, "json-recovery-lr-with-ast", "lr", "languages/json-recovery/lr.grm", &.{ "--with-ast", "--with-error-recovery" });
        test_step.dependOn(parity_step);
    } else {
        addSelectionFailure(b, parity_step, "the selected filters do not include suite:galley-parity");
    }

    if (selection.names.len != 0) {
        addTestFilterGuard(b, test_step, filtered_test_run_steps.items);
    }
}

const GalleyRecoveryComparison = struct {
    run_tests: [2]*std.Build.Step.Run,
    run_demo: *std.Build.Step.Run,
};

fn addGalleyRecoveryComparison(
    b: *std.Build,
    options: Options,
    filters: []const []const u8,
) !GalleyRecoveryComparison {
    const automatic_parser_path = addGalleyRecoveryComparisonGeneration(b, options, "automatic", true);
    const explicit_parser_path = addGalleyRecoveryComparisonGeneration(b, options, "explicit", false);
    const automatic_parser = addGalleyRecoveryComparisonParser(b, options, "automatic", automatic_parser_path);
    const explicit_parser = addGalleyRecoveryComparisonParser(b, options, "explicit", explicit_parser_path);

    const automatic_artifacts = addGalleyRecoveryComparisonArtifacts(b, options, "automatic", false, automatic_parser, filters);
    const explicit_artifacts = addGalleyRecoveryComparisonArtifacts(b, options, "explicit", true, explicit_parser, filters);
    explicit_artifacts.run_demo.step.dependOn(&automatic_artifacts.run_demo.step);

    return .{
        .run_tests = .{ automatic_artifacts.run_tests, explicit_artifacts.run_tests },
        .run_demo = explicit_artifacts.run_demo,
    };
}

const GalleyRecoveryComparisonArtifacts = struct {
    run_tests: *std.Build.Step.Run,
    run_demo: *std.Build.Step.Run,
};

fn addGalleyRecoveryComparisonArtifacts(
    b: *std.Build,
    options: Options,
    mode: []const u8,
    is_explicit: bool,
    generated_parser: common.GeneratedParserModule,
    filters: []const []const u8,
) GalleyRecoveryComparisonArtifacts {
    const comparison_options = b.addOptions();
    comparison_options.addOption([]const u8, "heading", if (is_explicit) "Explicit" else "Automatic");
    comparison_options.addOption([]const u8, "label", mode);
    comparison_options.addOption(bool, "is_explicit", is_explicit);
    const comparison_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/galley_recovery_comparison.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "parser-under-test", .module = generated_parser.runtime_mod },
            .{ .name = "comparison-options", .module = comparison_options.createModule() },
        },
    });
    const tests = b.addTest(.{
        .name = b.fmt("galley-recovery-comparison-{s}-tests", .{mode}),
        .root_module = comparison_mod,
        .filters = filters,
    });
    const demo = b.addExecutable(.{
        .name = b.fmt("compare-galley-recovery-{s}", .{mode}),
        .root_module = comparison_mod,
    });
    const run_demo = b.addRunArtifact(demo);
    run_demo.stdio = .inherit;
    return .{
        .run_tests = b.addRunArtifact(tests),
        .run_demo = run_demo,
    };
}

fn addGalleyRecoveryComparisonGeneration(
    b: *std.Build,
    options: Options,
    mode: []const u8,
    strip_recovery_annotations: bool,
) std.Build.LazyPath {
    const generate_parser = b.addRunArtifact(options.generate_parser_file_exe);
    generate_parser.addArg("--grammar");
    generate_parser.addFileArg(b.path("languages/galley/ll.grm"));
    generate_parser.addArg("--parser-type");
    generate_parser.addArg("ll");
    generate_parser.addArg("--output");
    const output = generate_parser.addOutputFileArg(b.fmt("galley-recovery-comparison-{s}.zig", .{mode}));
    generate_parser.addArgs(&.{
        "--no-ast",
        "--no-procedures",
        "--with-error-recovery",
        "--input-size",
        "16",
    });
    if (strip_recovery_annotations) generate_parser.addArg("--strip-recovery-annotations");
    return output;
}

fn addGalleyRecoveryComparisonParser(
    b: *std.Build,
    options: Options,
    mode: []const u8,
    parser_path: std.Build.LazyPath,
) common.GeneratedParserModule {
    const procedures_mod = b.createModule(.{
        .root_source_file = b.path("tests/explicit-recovery/procedures.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const config_mod = b.createModule(.{
        .root_source_file = b.path("tests/explicit-recovery/config.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const error_messages_mod = b.createModule(.{
        .root_source_file = b.path("languages/galley/ll_error_messages.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    return common.addGeneratedParserModule(
        b,
        options.target,
        options.optimize,
        b.fmt("galley-recovery-comparison-{s}", .{mode}),
        b.fmt("galley-recovery-comparison-{s}-source", .{mode}),
        parser_path,
        procedures_mod,
        config_mod,
        error_messages_mod,
        options.generator.runtime_options_mod,
    );
}

fn addSymbolKindIdentityTests(
    b: *std.Build,
    options: Options,
    parser_type: []const u8,
    filters: []const []const u8,
) !*std.Build.Step.Run {
    const parser_name = b.fmt("symbol-kind-identity-{s}", .{parser_type});
    const generate_parser = b.addRunArtifact(options.generate_parser_file_exe);
    generate_parser.addArg("--grammar");
    generate_parser.addFileArg(b.path("tests/symbol-kind-identity/grammar.grm"));
    generate_parser.addArg("--parser-type");
    generate_parser.addArg(parser_type);
    generate_parser.addArg("--label");
    generate_parser.addArg(b.fmt("{s}/symbol-kind-identity/tests", .{parser_type}));
    generate_parser.addArg("--output");
    const generated_parser_path = generate_parser.addOutputFileArg(b.fmt("{s}-parser.zig", .{parser_name}));
    generate_parser.addArgs(&.{
        "--no-ast",
        "--no-procedures",
        "--input-size",
        "16",
    });

    const procedures_mod = b.createModule(.{
        .root_source_file = b.path("tests/symbol-kind-identity/procedures.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const config_mod = b.createModule(.{
        .root_source_file = b.path("tests/symbol-kind-identity/config.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const error_messages_mod = b.createModule(.{
        .root_source_file = b.path("tests/symbol-kind-identity/error_messages.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const generated_parser = common.addGeneratedParserModule(
        b,
        options.target,
        options.optimize,
        parser_name,
        b.fmt("{s}-source", .{parser_name}),
        generated_parser_path,
        procedures_mod,
        config_mod,
        error_messages_mod,
        options.generator.runtime_options_mod,
    );

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/symbol_kind_identity_test.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{.{ .name = "parser-under-test", .module = generated_parser.runtime_mod }},
    });
    const tests = b.addTest(.{
        .name = b.fmt("{s}-tests", .{parser_name}),
        .root_module = test_mod,
        .filters = filters,
    });
    return b.addRunArtifact(tests);
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
        options.generator.runtime_options_mod,
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

fn addExplicitRecoveryTests(
    b: *std.Build,
    options: Options,
    parser_type: []const u8,
    filters: []const []const u8,
) !*std.Build.Step.Run {
    const generated_name = try std.fmt.allocPrint(b.allocator, "explicit-recovery-{s}-parser.zig", .{parser_type});
    const generate_parser = b.addRunArtifact(options.generate_parser_file_exe);
    generate_parser.addArg("--grammar");
    generate_parser.addFileArg(b.path(try std.fmt.allocPrint(
        b.allocator,
        "tests/explicit-recovery/{s}.grm",
        .{parser_type},
    )));
    generate_parser.addArg("--parser-type");
    generate_parser.addArg(parser_type);
    generate_parser.addArg("--label");
    generate_parser.addArg(try std.fmt.allocPrint(b.allocator, "{s}/explicit-recovery/tests", .{parser_type}));
    generate_parser.addArg("--output");
    const generated_parser_path = generate_parser.addOutputFileArg(generated_name);
    generate_parser.addArgs(&.{
        "--with-ast",
        "--with-procedures",
        "--with-error-recovery",
        "--input-size",
        "16",
    });
    generate_parser.stdio = .inherit;

    const procedures_mod = b.createModule(.{
        .root_source_file = b.path("tests/explicit-recovery/procedures.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const config_mod = b.createModule(.{
        .root_source_file = b.path("tests/explicit-recovery/config.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const error_messages_mod = b.createModule(.{
        .root_source_file = b.path("tests/explicit-recovery/error_messages.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const parser_name = try std.fmt.allocPrint(b.allocator, "explicit-recovery-{s}", .{parser_type});
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
        options.generator.runtime_options_mod,
    );

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/explicit_recovery_test.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{.{ .name = "parser-under-test", .module = generated_parser.runtime_mod }},
    });
    const tests = b.addTest(.{
        .name = try std.fmt.allocPrint(b.allocator, "explicit-recovery-{s}-tests", .{parser_type}),
        .root_module = test_mod,
        .filters = filters,
    });
    return b.addRunArtifact(tests);
}

fn addGalleyRecoveryTests(
    b: *std.Build,
    options: Options,
    parser_type: []const u8,
    filters: []const []const u8,
) !*std.Build.Step.Run {
    const generate_parser = b.addRunArtifact(options.generate_parser_file_exe);
    generate_parser.addArg("--grammar");
    generate_parser.addFileArg(b.path(b.fmt("languages/galley/{s}.grm", .{parser_type})));
    generate_parser.addArg("--parser-type");
    generate_parser.addArg(parser_type);
    generate_parser.addArg("--output");
    const parser_path = generate_parser.addOutputFileArg(b.fmt("galley-recovery-{s}-parser.zig", .{parser_type}));
    generate_parser.addArgs(&.{
        "--no-ast",
        "--no-procedures",
        "--with-error-recovery",
        "--input-size",
        "16",
    });

    const procedures_mod = b.createModule(.{
        .root_source_file = b.path("tests/explicit-recovery/procedures.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const config_mod = b.createModule(.{
        .root_source_file = b.path("tests/explicit-recovery/config.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const error_messages_mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("languages/galley/{s}_error_messages.zig", .{parser_type})),
        .target = options.target,
        .optimize = options.optimize,
    });
    const generated_parser = common.addGeneratedParserModule(
        b,
        options.target,
        options.optimize,
        b.fmt("galley-recovery-{s}", .{parser_type}),
        b.fmt("galley-recovery-{s}-source", .{parser_type}),
        parser_path,
        procedures_mod,
        config_mod,
        error_messages_mod,
        options.generator.runtime_options_mod,
    );
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/galley_recovery_test.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{.{ .name = "parser-under-test", .module = generated_parser.runtime_mod }},
    });
    const tests = b.addTest(.{
        .name = b.fmt("galley-recovery-{s}-tests", .{parser_type}),
        .root_module = test_mod,
        .filters = filters,
    });
    return b.addRunArtifact(tests);
}

fn addJsonRecoveryTests(
    b: *std.Build,
    options: Options,
    parser_type: []const u8,
    filters: []const []const u8,
) !*std.Build.Step.Run {
    const generate_parser = b.addRunArtifact(options.generate_parser_file_exe);
    generate_parser.addArg("--grammar");
    generate_parser.addFileArg(b.path(b.fmt("languages/json-recovery/{s}.grm", .{parser_type})));
    generate_parser.addArg("--parser-type");
    generate_parser.addArg(parser_type);
    generate_parser.addArg("--output");
    const parser_path = generate_parser.addOutputFileArg(b.fmt("json-recovery-{s}-parser.zig", .{parser_type}));
    generate_parser.addArgs(&.{
        "--no-ast",
        "--no-procedures",
        "--with-error-recovery",
        "--input-size",
        "16",
    });

    const procedures_mod = b.createModule(.{
        .root_source_file = b.path("languages/json-recovery/procedures.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const config_mod = b.createModule(.{
        .root_source_file = b.path("languages/json-recovery/config.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });
    const error_messages_mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("languages/json-recovery/{s}_error_messages.zig", .{parser_type})),
        .target = options.target,
        .optimize = options.optimize,
    });
    const generated_parser = common.addGeneratedParserModule(
        b,
        options.target,
        options.optimize,
        b.fmt("json-recovery-{s}", .{parser_type}),
        b.fmt("json-recovery-{s}-source", .{parser_type}),
        parser_path,
        procedures_mod,
        config_mod,
        error_messages_mod,
        options.generator.runtime_options_mod,
    );
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/json_recovery_test.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{.{ .name = "parser-under-test", .module = generated_parser.runtime_mod }},
    });
    const tests = b.addTest(.{
        .name = b.fmt("json-recovery-{s}-tests", .{parser_type}),
        .root_module = test_mod,
        .filters = filters,
    });
    return b.addRunArtifact(tests);
}

const InputRefillTestKind = enum {
    sliding,
    indentation,
    recovery_eof,
    ast_limit,
    unbuffered_read_error,
};

fn addInputRefillTests(
    b: *std.Build,
    options: Options,
    parser_type: []const u8,
    kind: InputRefillTestKind,
    filters: []const []const u8,
) !*std.Build.Step.Run {
    const language = if (kind == .indentation) "sanbus" else "json";
    const label = @tagName(kind);
    const parser_name = b.fmt("input-refill-{s}-{s}", .{ parser_type, label });

    const generate_parser = b.addRunArtifact(options.generate_parser_file_exe);
    generate_parser.addArg("--grammar");
    generate_parser.addFileArg(b.path(b.fmt("languages/{s}/{s}.grm", .{ language, parser_type })));
    generate_parser.addArg("--parser-type");
    generate_parser.addArg(parser_type);
    generate_parser.addArg("--label");
    generate_parser.addArg(b.fmt("{s}/input-refill/{s}", .{ parser_type, label }));
    generate_parser.addArg("--output");
    const parser_path = generate_parser.addOutputFileArg(b.fmt("{s}-parser.zig", .{parser_name}));
    generate_parser.addArgs(&.{
        "--no-procedures",
        "--with-position-tracking",
        "--input-size",
        "16",
    });
    if (kind == .unbuffered_read_error) {
        generate_parser.addArg("--no-input-refill");
    } else {
        generate_parser.addArg("--with-input-refill");
    }
    if (kind == .ast_limit) {
        generate_parser.addArg("--with-ast");
    } else {
        generate_parser.addArg("--no-ast");
    }
    if (kind == .recovery_eof) generate_parser.addArg("--with-error-recovery");

    const procedures_mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("languages/{s}/procedures.zig", .{language})),
        .target = options.target,
        .optimize = options.optimize,
    });
    const config_mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("languages/{s}/config.zig", .{language})),
        .target = options.target,
        .optimize = options.optimize,
    });
    const error_messages_mod = b.createModule(.{
        .root_source_file = b.path(b.fmt("languages/{s}/{s}_error_messages.zig", .{ language, parser_type })),
        .target = options.target,
        .optimize = options.optimize,
    });
    const generated_parser = common.addGeneratedParserModule(
        b,
        options.target,
        options.optimize,
        parser_name,
        b.fmt("{s}-source", .{parser_name}),
        parser_path,
        procedures_mod,
        config_mod,
        error_messages_mod,
        options.generator.runtime_options_mod,
    );

    const test_options = b.addOptions();
    test_options.addOption(bool, "sliding", kind == .sliding);
    test_options.addOption(bool, "indentation", kind == .indentation);
    test_options.addOption(bool, "recovery_eof", kind == .recovery_eof);
    test_options.addOption(bool, "ast_limit", kind == .ast_limit);
    test_options.addOption(bool, "refill_enabled", kind != .unbuffered_read_error);
    test_options.addOption(
        bool,
        "read_error",
        kind == .sliding or
            kind == .indentation or
            kind == .recovery_eof or
            kind == .unbuffered_read_error,
    );
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/input_refill_test.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "parser-under-test", .module = generated_parser.runtime_mod },
            .{ .name = "test_options", .module = test_options.createModule() },
        },
    });
    const tests = b.addTest(.{
        .name = b.fmt("{s}-tests", .{parser_name}),
        .root_module = test_mod,
        .filters = filters,
    });
    const run_tests = b.addRunArtifact(tests);

    return run_tests;
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

fn addLrBackedGenerator(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    generator: common.GeneratorModules,
    ll_backed_generator: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const generate_lr_parser = b.addRunArtifact(ll_backed_generator);
    generate_lr_parser.addArg("--grammar");
    generate_lr_parser.addFileArg(b.path("languages/galley/lr.grm"));
    generate_lr_parser.addArgs(&.{ "--parser-type", "lr", "--with-error-recovery", "--output" });
    const parser_source = generate_lr_parser.addOutputFileArg("galley-lr-bootstrap.zig");

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
        "galley-lr-backed-runtime",
        "galley-lr-backed-source",
        parser_source,
        procedures_mod,
        config_mod,
        error_messages_mod,
        generator.runtime_options_mod,
    );

    const generator_mod = b.createModule(.{
        .root_source_file = b.path("src/generator/api.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "generator_common", .module = generator.generator_common_mod },
            .{ .name = "galley_grammar", .module = generated_parser.runtime_mod },
            .{ .name = "ll_generator", .module = generator.ll_generator_mod },
            .{ .name = "lr_generator", .module = generator.lr_generator_mod },
        },
    });
    const tool_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/generate_parser_file.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "galley_generator", .module = generator_mod },
        },
    });
    return b.addExecutable(.{
        .name = "generate-parser-file-lr-backed",
        .root_module = tool_mod,
    });
}

fn addGalleyBootstrapParityCase(
    b: *std.Build,
    parity_step: *std.Build.Step,
    ll_backed_generator: *std.Build.Step.Compile,
    lr_backed_generator: *std.Build.Step.Compile,
    name: []const u8,
    parser_type: []const u8,
    grammar_path: []const u8,
    options: []const []const u8,
) !void {
    const run_ll_backed = b.addRunArtifact(ll_backed_generator);
    run_ll_backed.setName(b.fmt("generate parity LL-backed output {s}", .{name}));
    run_ll_backed.addArg("--grammar");
    run_ll_backed.addFileArg(b.path(grammar_path));
    run_ll_backed.addArgs(&.{ "--parser-type", parser_type, "--output" });
    const ll_output = run_ll_backed.addOutputFileArg(b.fmt("{s}-ll-backed.zig", .{name}));
    run_ll_backed.addArgs(options);

    const run_lr_backed = b.addRunArtifact(lr_backed_generator);
    run_lr_backed.setName(b.fmt("generate parity LR-backed output {s}", .{name}));
    run_lr_backed.addArg("--grammar");
    run_lr_backed.addFileArg(b.path(grammar_path));
    run_lr_backed.addArgs(&.{ "--parser-type", parser_type, "--output" });
    const lr_output = run_lr_backed.addOutputFileArg(b.fmt("{s}-lr-backed.zig", .{name}));
    run_lr_backed.addArgs(options);

    const compare_outputs = b.addSystemCommand(&.{ "diff", "-u" });
    compare_outputs.addFileArg(ll_output);
    compare_outputs.addFileArg(lr_output);
    compare_outputs.setName(b.fmt("test parity {s}", .{name}));
    common.expectSilentSuccess(compare_outputs);
    parity_step.dependOn(&compare_outputs.step);
}
