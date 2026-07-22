const std = @import("std");
const common = @import("common.zig");
const test_selection = @import("test_selection.zig");

pub const Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    clap_mod: *std.Build.Module,
    generator_modules: common.GeneratorModules,
    generate_parser_file_exe: *std.Build.Step.Compile,
    selection: test_selection.Selection,
    filtered_test_run_steps: ?*std.ArrayList(*std.Build.Step) = null,
};

pub const Work = struct {
    compile: usize = 0,
    api: usize = 0,
    errors: usize = 0,
    cli: usize = 0,

    pub fn total(self: Work) usize {
        return self.compile + self.api + self.errors + self.cli;
    }
};

const MatrixVariant = struct {
    name: []const u8,
    input_size: u16,
    args: []const []const u8,
};

const matrix_variants = [_]MatrixVariant{
    .{
        .name = "no-ast-procedures-size16",
        .input_size = 16,
        .args = &.{ "--no-ast", "--with-procedures", "--input-size", "16", "--no-ast-for-terminals" },
    },
    .{
        .name = "no-ast-procedures-size32",
        .input_size = 32,
        .args = &.{ "--no-ast", "--with-procedures", "--input-size", "32", "--no-ast-for-terminals" },
    },
    .{
        .name = "ast-no-procedures-no-terminal-ast-size16",
        .input_size = 16,
        .args = &.{ "--with-ast", "--no-procedures", "--input-size", "16", "--no-ast-for-terminals" },
    },
    .{
        .name = "ast-no-procedures-terminal-ast-size16",
        .input_size = 16,
        .args = &.{ "--with-ast", "--no-procedures", "--input-size", "16", "--ast-for-terminals" },
    },
    .{
        .name = "ast-no-procedures-no-terminal-ast-size32",
        .input_size = 32,
        .args = &.{ "--with-ast", "--no-procedures", "--input-size", "32", "--no-ast-for-terminals" },
    },
    .{
        .name = "ast-no-procedures-terminal-ast-size32",
        .input_size = 32,
        .args = &.{ "--with-ast", "--no-procedures", "--input-size", "32", "--ast-for-terminals" },
    },
    .{
        .name = "ast-procedures-no-terminal-ast-size16",
        .input_size = 16,
        .args = &.{ "--with-ast", "--with-procedures", "--input-size", "16", "--no-ast-for-terminals" },
    },
    .{
        .name = "ast-procedures-terminal-ast-size16",
        .input_size = 16,
        .args = &.{ "--with-ast", "--with-procedures", "--input-size", "16", "--ast-for-terminals" },
    },
    .{
        .name = "ast-procedures-no-terminal-ast-size32",
        .input_size = 32,
        .args = &.{ "--with-ast", "--with-procedures", "--input-size", "32", "--no-ast-for-terminals" },
    },
    .{
        .name = "ast-procedures-terminal-ast-size32",
        .input_size = 32,
        .args = &.{ "--with-ast", "--with-procedures", "--input-size", "32", "--ast-for-terminals" },
    },
};

fn testsErrorRecovery(variant: MatrixVariant) bool {
    return std.mem.eql(u8, variant.name, "no-ast-procedures-size16") or
        std.mem.eql(u8, variant.name, "ast-procedures-no-terminal-ast-size16");
}

const ParserTypeSpec = struct {
    name: []const u8,
    grammar_name: []const u8,
};

const parser_type_specs = [_]ParserTypeSpec{
    .{ .name = "ll", .grammar_name = "ll.grm" },
    .{ .name = "lr", .grammar_name = "lr.grm" },
};

const languages = [_][]const u8{
    "galley",
    "json",
    "json-recovery",
    "json-augmented",
    "json-structured-ast",
    "lisp",
    "lua",
    "sanbus",
    "ll1",
};

pub fn add(b: *std.Build, matrix_step: *std.Build.Step, options: Options) !Work {
    const parser_types: []const ParserTypeSpec = parser_type_specs[0..];

    var prev_generate_step: ?*std.Build.Step = null;
    var matched_cases: std.ArrayList([]const u8) = .empty;
    var work: Work = .{};

    for (languages) |language| {
        for (parser_types) |parser_type| {
            const grammar_path = try std.fs.path.join(b.allocator, &.{ "languages", language, parser_type.grammar_name });
            defer b.allocator.free(grammar_path);

            b.build_root.handle.access(b.graph.io, grammar_path, .{}) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            };

            const selected_case = try std.mem.concat(b.allocator, u8, &.{ parser_type.name, "-", language });
            if (!options.selection.matchesCase(selected_case)) continue;
            matched_cases.append(b.allocator, selected_case) catch @panic("OOM");

            for (matrix_variants) |variant| {
                try addCase(
                    b,
                    matrix_step,
                    options,
                    language,
                    parser_type.name,
                    grammar_path,
                    variant,
                    &prev_generate_step,
                    &work,
                );
            }
        }
    }

    for (options.selection.cases) |selected_case| {
        for (matched_cases.items) |matched_case| {
            if (std.mem.eql(u8, selected_case, matched_case)) break;
        } else {
            std.log.err("unknown or unavailable matrix case '{s}'", .{selected_case});
            return error.InvalidTestFilter;
        }
    }

    if (work.total() == 0) {
        std.log.err("the selected matrix suites and cases contain no runnable work", .{});
        return error.NoTestsSelected;
    }
    return work;
}

fn addCase(
    b: *std.Build,
    matrix_step: *std.Build.Step,
    options: Options,
    language: []const u8,
    parser_type: []const u8,
    grammar_path: []const u8,
    variant: MatrixVariant,
    prev_generate_step: *?*std.Build.Step,
    work: *Work,
) !void {
    const work_before = work.total();
    const case_name = try std.mem.concat(b.allocator, u8, &.{ "generated-", parser_type, "-", language, "-", variant.name });
    const case_label = b.fmt("{s}/{s}/{s}", .{ parser_type, language, variant.name });
    const parser_basename = try std.mem.concat(b.allocator, u8, &.{ case_name, ".zig" });

    const generate_parser = b.addRunArtifact(options.generate_parser_file_exe);
    generate_parser.addArg("--grammar");
    generate_parser.addFileArg(b.path(grammar_path));
    generate_parser.addArg("--parser-type");
    generate_parser.addArg(parser_type);
    generate_parser.addArg("--label");
    generate_parser.addArg(case_label);
    generate_parser.addArg("--output");
    const generated_parser_path = generate_parser.addOutputFileArg(parser_basename);
    generate_parser.addArgs(variant.args);
    generate_parser.stdio = .inherit;
    const procedures_path = try std.fs.path.join(b.allocator, &.{ "languages", language, "procedures.zig" });
    const config_path = try std.fs.path.join(b.allocator, &.{ "languages", language, "config.zig" });
    const error_messages_file_name = try common.errorMessagesFileName(b.allocator, parser_type);
    const error_messages_path = try std.fs.path.join(b.allocator, &.{ "languages", language, error_messages_file_name });

    const procedures_mod = b.addModule(try std.mem.concat(b.allocator, u8, &.{ case_name, "-procedures" }), .{
        .root_source_file = b.path(procedures_path),
        .target = options.target,
        .optimize = options.optimize,
    });
    const config_mod = b.addModule(try std.mem.concat(b.allocator, u8, &.{ case_name, "-config" }), .{
        .root_source_file = b.path(config_path),
        .target = options.target,
        .optimize = options.optimize,
    });
    const error_messages_mod = b.addModule(try std.mem.concat(b.allocator, u8, &.{ case_name, "-error-messages" }), .{
        .root_source_file = b.path(error_messages_path),
        .target = options.target,
        .optimize = options.optimize,
    });
    const generated_parser = common.addGeneratedParserModule(
        b,
        options.target,
        options.optimize,
        case_name,
        try std.mem.concat(b.allocator, u8, &.{ case_name, "-parser" }),
        generated_parser_path,
        procedures_mod,
        config_mod,
        error_messages_mod,
        options.generator_modules.ll_generator_mod,
        options.generator_modules.lr_generator_mod,
        options.generator_modules.runtime_options_mod,
    );
    const galley_parser_mod = generated_parser.runtime_mod;

    if (options.selection.includes(.matrix_error) and variant.input_size == 16) if (errorInputs(language)) |inputs| {
        const run_parser_error_tests = addGeneratedParserErrorTest(
            b,
            options.target,
            options.optimize,
            galley_parser_mod,
            case_name,
            case_label,
            inputs.valid,
            inputs.malformed,
            inputs.multiple_errors,
            inputs.small_window_error_count,
            inputs.diagnostic_line,
            inputs.diagnostic_column,
            inputs.unexpected_token_prefix,
            inputs.expected_token,
            false,
            options.selection.names,
        );
        matrix_step.dependOn(&run_parser_error_tests.step);
        trackFilteredTestRun(b, options, &run_parser_error_tests.step);
        work.errors += 1;

        if (testsErrorRecovery(variant)) {
            const recovery_case_name = try std.mem.concat(b.allocator, u8, &.{ case_name, "-error-recovery" });
            const recovery_case_label = b.fmt("{s}/error-recovery", .{case_label});
            const recovery_parser_basename = try std.mem.concat(b.allocator, u8, &.{ recovery_case_name, ".zig" });
            const generate_recovery_parser = b.addRunArtifact(options.generate_parser_file_exe);
            generate_recovery_parser.addArg("--grammar");
            generate_recovery_parser.addFileArg(b.path(grammar_path));
            generate_recovery_parser.addArg("--parser-type");
            generate_recovery_parser.addArg(parser_type);
            generate_recovery_parser.addArg("--label");
            generate_recovery_parser.addArg(recovery_case_label);
            generate_recovery_parser.addArg("--output");
            const recovery_parser_path = generate_recovery_parser.addOutputFileArg(recovery_parser_basename);
            generate_recovery_parser.addArgs(variant.args);
            generate_recovery_parser.addArg("--with-error-recovery");
            generate_recovery_parser.stdio = .inherit;

            const recovery_procedures_mod = b.addModule(try std.mem.concat(b.allocator, u8, &.{ recovery_case_name, "-procedures" }), .{
                .root_source_file = b.path(procedures_path),
                .target = options.target,
                .optimize = options.optimize,
            });
            const recovery_config_mod = b.addModule(try std.mem.concat(b.allocator, u8, &.{ recovery_case_name, "-config" }), .{
                .root_source_file = b.path(config_path),
                .target = options.target,
                .optimize = options.optimize,
            });
            const recovery_error_messages_mod = b.addModule(try std.mem.concat(b.allocator, u8, &.{ recovery_case_name, "-error-messages" }), .{
                .root_source_file = b.path(error_messages_path),
                .target = options.target,
                .optimize = options.optimize,
            });

            const recovery_parser = common.addGeneratedParserModule(
                b,
                options.target,
                options.optimize,
                recovery_case_name,
                try std.mem.concat(b.allocator, u8, &.{ recovery_case_name, "-parser" }),
                recovery_parser_path,
                recovery_procedures_mod,
                recovery_config_mod,
                recovery_error_messages_mod,
                options.generator_modules.ll_generator_mod,
                options.generator_modules.lr_generator_mod,
                options.generator_modules.runtime_options_mod,
            );
            const run_recovery_error_tests = addGeneratedParserErrorTest(
                b,
                options.target,
                options.optimize,
                recovery_parser.runtime_mod,
                recovery_case_name,
                recovery_case_label,
                inputs.valid,
                inputs.malformed,
                inputs.multiple_errors,
                inputs.small_window_error_count,
                inputs.diagnostic_line,
                inputs.diagnostic_column,
                inputs.unexpected_token_prefix,
                inputs.expected_token,
                true,
                options.selection.names,
            );
            matrix_step.dependOn(&run_recovery_error_tests.step);
            trackFilteredTestRun(b, options, &run_recovery_error_tests.step);
            work.errors += 1;

            if ((std.mem.eql(u8, language, "json") or std.mem.eql(u8, language, "json-recovery")) and
                std.mem.eql(u8, variant.name, "no-ast-procedures-size16"))
            {
                const recovery_cli_options = b.addOptions();
                recovery_cli_options.addOption([]const u8, "api_benchmark_step", "run-api-bench-generated-parser-matrix");
                const recovery_cli_mod = b.createModule(.{
                    .root_source_file = b.path("src/cli/parser.zig"),
                    .target = options.target,
                    .optimize = options.optimize,
                    .link_libc = true,
                    .imports = &.{
                        .{ .name = "clap", .module = options.clap_mod },
                        .{ .name = "build_options", .module = recovery_cli_options.createModule() },
                        .{ .name = "galley", .module = recovery_parser.runtime_mod },
                    },
                });
                const recovery_cli = b.addExecutable(.{
                    .name = try std.mem.concat(b.allocator, u8, &.{ recovery_case_name, "-cli" }),
                    .root_module = recovery_cli_mod,
                });
                const run_recovery_cli = b.addRunArtifact(recovery_cli);
                run_recovery_cli.setName(b.fmt("test recovery CLI options {s}", .{recovery_case_label}));
                run_recovery_cli.addArgs(&.{ "--max-errors", "2", "--recovery-window", "64", "--help" });
                run_recovery_cli.expectStdOutMatch("--max-errors <MAX_ERRORS>");
                run_recovery_cli.expectStdOutMatch("--recovery-window <BYTES>");
                run_recovery_cli.expectStdErrEqual("");
                matrix_step.dependOn(&run_recovery_cli.step);
                work.errors += 1;
            }
        }
    };

    const parser_cli_options = b.addOptions();
    parser_cli_options.addOption(
        []const u8,
        "api_benchmark_step",
        "run-api-bench-generated-parser-matrix",
    );

    const galley_cli_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/parser.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "clap", .module = options.clap_mod },
            .{ .name = "build_options", .module = parser_cli_options.createModule() },
            .{ .name = "galley", .module = galley_parser_mod },
        },
    });
    const exe = b.addExecutable(.{
        .name = case_name,
        .root_module = galley_cli_mod,
    });
    const install_artifact = b.addInstallArtifact(exe, .{});
    const build_step = b.step(case_name, try std.mem.concat(b.allocator, u8, &.{ "Build matrix variant: ", case_name }));
    build_step.dependOn(&install_artifact.step);
    build_step.dependOn(&generate_parser.step);

    if (options.selection.includes(.matrix_compile)) {
        matrix_step.dependOn(&exe.step);
        work.compile += 1;
    }

    const api_benchmark_mod = b.createModule(.{
        .root_source_file = b.path("src/benchmarks/api_benchmark.zig"),
        .target = options.target,
        .optimize = options.optimize,
        .imports = &.{
            .{ .name = "galley", .module = galley_parser_mod },
        },
    });
    const api_benchmark_name = try std.mem.concat(b.allocator, u8, &.{ "api-bench-", case_name });
    const api_benchmark_exe = b.addExecutable(.{
        .name = api_benchmark_name,
        .root_module = api_benchmark_mod,
    });
    const install_api_benchmark_artifact = b.addInstallArtifact(api_benchmark_exe, .{});
    const api_benchmark_step = b.step(api_benchmark_name, try std.mem.concat(b.allocator, u8, &.{ "Benchmark matrix variant API: ", case_name }));
    api_benchmark_step.dependOn(&install_api_benchmark_artifact.step);

    try addLanguageSamples(
        b,
        matrix_step,
        options,
        galley_parser_mod,
        exe,
        language,
        case_name,
        case_label,
        variant.name,
        variant.args,
        variant.input_size,
        work,
    );

    if (work.total() != work_before) {
        if (prev_generate_step.*) |prev| {
            generate_parser.step.dependOn(prev);
        }
        prev_generate_step.* = &generate_parser.step;
    }
}

fn addLanguageSamples(
    b: *std.Build,
    matrix_step: *std.Build.Step,
    options: Options,
    galley_parser_mod: *std.Build.Module,
    exe: *std.Build.Step.Compile,
    language: []const u8,
    case_name: []const u8,
    case_label: []const u8,
    config_label: []const u8,
    variant_args: []const []const u8,
    input_size: u16,
    work: *Work,
) !void {
    const samples_path = try std.fs.path.join(b.allocator, &.{ "languages", language, "samples" });
    defer b.allocator.free(samples_path);

    var samples_dir: ?@TypeOf(b.build_root.handle) = b.build_root.handle.openDir(b.graph.io, samples_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    if (samples_dir) |*samples_dir_handle| {
        defer samples_dir_handle.close(b.graph.io);
        var samples_walker = try samples_dir_handle.walk(b.allocator);
        defer samples_walker.deinit();

        while (try samples_walker.next(b.graph.io)) |sample_entry| {
            if (sample_entry.kind != .file and sample_entry.kind != .sym_link) continue;

            const sample_path = try std.fs.path.join(
                b.allocator,
                &.{ samples_path, sample_entry.path },
            );
            try addValidationInput(
                b,
                matrix_step,
                options,
                galley_parser_mod,
                exe,
                case_name,
                case_label,
                config_label,
                sample_path,
                variant_args,
                input_size,
                work,
            );
        }
    }
}

fn addValidationInput(
    b: *std.Build,
    matrix_step: *std.Build.Step,
    options: Options,
    galley_parser_mod: *std.Build.Module,
    exe: *std.Build.Step.Compile,
    case_name: []const u8,
    case_label: []const u8,
    config_label: []const u8,
    input_path: []const u8,
    variant_args: []const []const u8,
    input_size: u16,
    work: *Work,
) !void {
    const stat = try b.build_root.handle.statFile(b.graph.io, input_path, .{});
    const max_size = (@as(u64, 1) << @intCast(input_size));
    if (stat.size >= max_size) return;

    if (options.selection.includes(.matrix_api) and !shouldSkipGeneratedParserApiTests(variant_args, stat.size)) {
        const sample_input = try b.build_root.handle.readFileAlloc(
            b.graph.io,
            input_path,
            b.allocator,
            .limited(std.math.maxInt(usize)),
        );
        const run_parser_api_tests = addGeneratedParserApiTest(
            b,
            options.target,
            options.optimize,
            galley_parser_mod,
            case_name,
            case_label,
            "matrix",
            config_label,
            input_path,
            sample_input,
            options.selection.names,
        );
        matrix_step.dependOn(&run_parser_api_tests.step);
        trackFilteredTestRun(b, options, &run_parser_api_tests.step);
        work.api += 1;
    }

    if (!options.selection.includes(.matrix_cli)) return;

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.setName(b.fmt("test CLI {s} {s}", .{ case_label, std.fs.path.basename(input_path) }));
    common.expectSilentSuccess(run_cmd);
    run_cmd.addArgs(&.{
        "--verbosity",
        "0",
        "--iterations",
        "1",
    });

    if (std.mem.endsWith(u8, input_path, ".grm")) {
        const cache_dir = try std.fs.path.join(b.allocator, &.{ ".zig-cache", "matrix-validation", case_name });
        const cached_input = try std.fs.path.join(b.allocator, &.{ cache_dir, std.fs.path.basename(input_path) });

        const mkdir = b.addSystemCommand(&.{ "mkdir", "-p", cache_dir });
        mkdir.has_side_effects = true;
        common.expectSilentSuccess(mkdir);

        const copy_input = b.addSystemCommand(&.{ "cp", input_path, cached_input });
        copy_input.has_side_effects = true;
        common.expectSilentSuccess(copy_input);
        copy_input.step.dependOn(&mkdir.step);

        run_cmd.addArg(cached_input);
        run_cmd.step.dependOn(&copy_input.step);
    } else {
        run_cmd.addFileArg(b.path(input_path));
    }

    matrix_step.dependOn(&run_cmd.step);
    work.cli += 1;
}

fn addGeneratedParserApiTest(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    galley_parser_mod: *std.Build.Module,
    case_name: []const u8,
    case_label: []const u8,
    suite: []const u8,
    config_label: []const u8,
    sample_path: []const u8,
    sample_input: []const u8,
    filters: []const []const u8,
) *std.Build.Step.Run {
    const sample_name = std.fs.path.basename(sample_path);
    const parser_api_test_options = b.addOptions();
    parser_api_test_options.addOption([]const u8, "case_name", case_name);
    parser_api_test_options.addOption([]const u8, "suite", suite);
    parser_api_test_options.addOption([]const u8, "config_label", config_label);
    parser_api_test_options.addOption([]const u8, "sample_path", sample_path);
    parser_api_test_options.addOption([]const u8, "sample_input", sample_input);
    const parser_api_test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/generated_parser_library_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "parser-under-test", .module = galley_parser_mod },
            .{ .name = "test_options", .module = parser_api_test_options.createModule() },
        },
    });
    const parser_api_tests = b.addTest(.{
        .name = b.fmt("{s}-api-{s}", .{ case_name, sample_name }),
        .root_module = parser_api_test_mod,
        .filters = filters,
    });
    const run_parser_api_tests = b.addRunArtifact(parser_api_tests);
    run_parser_api_tests.setName(b.fmt("test API {s} {s}", .{ case_label, sample_name }));
    run_parser_api_tests.addFileInput(b.path(sample_path));
    return run_parser_api_tests;
}

const ErrorInputs = struct {
    valid: []const u8,
    malformed: []const u8,
    multiple_errors: []const u8,
    small_window_error_count: usize,
    diagnostic_line: u32,
    diagnostic_column: u32,
    unexpected_token_prefix: []const u8,
    expected_token: []const u8,
};

fn errorInputs(language: []const u8) ?ErrorInputs {
    if (std.mem.eql(u8, language, "json") or std.mem.eql(u8, language, "json-recovery")) {
        return .{
            .valid = "{}",
            .malformed = "{",
            .multiple_errors = "[true  !, false  ?, null]",
            .small_window_error_count = 1,
            .diagnostic_line = 1,
            .diagnostic_column = 2,
            .unexpected_token_prefix = "\x00",
            .expected_token = "}",
        };
    }
    if (std.mem.eql(u8, language, "json-augmented")) {
        return .{
            .valid = "null",
            .malformed = "*null",
            .multiple_errors = "**null",
            .small_window_error_count = 2,
            .diagnostic_line = 1,
            .diagnostic_column = 6,
            .unexpected_token_prefix = "\x00",
            .expected_token = ")",
        };
    }
    if (std.mem.eql(u8, language, "sanbus")) {
        return .{
            .valid = "Item:\n  - value: str\n",
            .malformed = "Item:\n  - value! str\n",
            .multiple_errors = "Item:\n  - first! str\n  - second! str\n",
            .small_window_error_count = 1,
            .diagnostic_line = 2,
            .diagnostic_column = 10,
            .unexpected_token_prefix = "!",
            .expected_token = ":",
        };
    }
    if (std.mem.eql(u8, language, "galley")) {
        return .{
            .valid = "Start\n| \"x\"\n",
            .malformed = "Start\n| ?\n| \"x\"\n",
            .multiple_errors = "Start\n| ?\n| ?\n| \"valid\"\n\nNext\n| \"still-valid\"\n",
            .small_window_error_count = 1,
            .diagnostic_line = 2,
            .diagnostic_column = 3,
            .unexpected_token_prefix = "?",
            .expected_token = "\"",
        };
    }
    return null;
}

fn addGeneratedParserErrorTest(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    galley_parser_mod: *std.Build.Module,
    case_name: []const u8,
    case_label: []const u8,
    valid_input: []const u8,
    malformed_input: []const u8,
    multiple_errors_input: []const u8,
    small_window_error_count: usize,
    diagnostic_line: u32,
    diagnostic_column: u32,
    unexpected_token_prefix: []const u8,
    expected_token: []const u8,
    error_recovery_enabled: bool,
    filters: []const []const u8,
) *std.Build.Step.Run {
    const test_options = b.addOptions();
    test_options.addOption([]const u8, "valid_input", valid_input);
    test_options.addOption([]const u8, "malformed_input", malformed_input);
    test_options.addOption([]const u8, "multiple_errors_input", multiple_errors_input);
    test_options.addOption(usize, "small_window_error_count", small_window_error_count);
    test_options.addOption(u32, "diagnostic_line", diagnostic_line);
    test_options.addOption(u32, "diagnostic_column", diagnostic_column);
    test_options.addOption([]const u8, "unexpected_token_prefix", unexpected_token_prefix);
    test_options.addOption([]const u8, "expected_token", expected_token);
    test_options.addOption(bool, "error_recovery_enabled", error_recovery_enabled);
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/generated_parser_error_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "parser-under-test", .module = galley_parser_mod },
            .{ .name = "test_options", .module = test_options.createModule() },
        },
    });
    const tests = b.addTest(.{
        .name = b.fmt("{s}-error-tests", .{case_name}),
        .root_module = test_mod,
        .filters = filters,
    });
    const run_tests = b.addRunArtifact(tests);
    run_tests.setName(b.fmt("test errors {s}", .{case_label}));
    return run_tests;
}

const large_sample_api_test_skip_threshold: u64 = 5 * 1024 * 1024;

fn shouldSkipGeneratedParserApiTests(variant_args: []const []const u8, sample_size: u64) bool {
    if (sample_size <= large_sample_api_test_skip_threshold) return false;

    var procedures_enabled = false;
    var terminal_ast_enabled = false;
    for (variant_args) |arg| {
        if (std.mem.eql(u8, arg, "--with-procedures")) procedures_enabled = true;
        if (std.mem.eql(u8, arg, "--ast-for-terminals")) terminal_ast_enabled = true;
    }
    return procedures_enabled and terminal_ast_enabled;
}

fn trackFilteredTestRun(b: *std.Build, options: Options, run_step: *std.Build.Step) void {
    if (options.selection.names.len == 0) return;
    if (options.filtered_test_run_steps) |filtered_test_run_steps| {
        filtered_test_run_steps.append(b.allocator, run_step) catch @panic("OOM");
    }
}
