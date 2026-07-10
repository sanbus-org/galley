const std = @import("std");
const common = @import("common.zig");

pub const Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    clap_mod: *std.Build.Module,
    generator_modules: common.GeneratorModules,
    generate_parser_file_exe: *std.Build.Step.Compile,
    filters: []const []const u8 = &.{},
    filtered_test_run_steps: ?*std.ArrayList(*std.Build.Step) = null,
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
    "json-augmented",
    "json-structured-ast",
    "lisp",
    "lua",
    "test-ll",
    "test-ll1",
};

pub fn add(b: *std.Build, matrix_step: *std.Build.Step, options: Options) !void {
    const parser_types: []const ParserTypeSpec = parser_type_specs[0..];

    var prev_generate_step: ?*std.Build.Step = null;

    for (languages) |language| {
        for (parser_types) |parser_type| {
            if (!filterMatchesMatrixCase(b.allocator, options.filters, parser_type.name, language)) continue;

            const grammar_path = try std.fs.path.join(b.allocator, &.{ "languages", language, parser_type.grammar_name });
            defer b.allocator.free(grammar_path);

            b.build_root.handle.access(b.graph.io, grammar_path, .{}) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            };

            for (matrix_variants, 0..) |variant, variant_index| {
                try addCase(
                    b,
                    matrix_step,
                    options,
                    language,
                    parser_type.name,
                    grammar_path,
                    variant,
                    variant_index == 0,
                    &prev_generate_step,
                );
            }
        }
    }
}

fn addCase(
    b: *std.Build,
    matrix_step: *std.Build.Step,
    options: Options,
    language: []const u8,
    parser_type: []const u8,
    grammar_path: []const u8,
    variant: MatrixVariant,
    is_first_variant: bool,
    prev_generate_step: *?*std.Build.Step,
) !void {
    const case_name = try std.mem.concat(b.allocator, u8, &.{ "generated-", parser_type, "-", language, "-", variant.name });
    const parser_basename = try std.mem.concat(b.allocator, u8, &.{ case_name, ".zig" });

    const generate_parser = b.addRunArtifact(options.generate_parser_file_exe);
    generate_parser.addArg("--grammar");
    generate_parser.addFileArg(b.path(grammar_path));
    generate_parser.addArg("--parser-type");
    generate_parser.addArg(parser_type);
    generate_parser.addArg("--label");
    generate_parser.addArg(try std.mem.concat(b.allocator, u8, &.{ parser_type, "/", language, "/", variant.name }));
    generate_parser.addArg("--output");
    const generated_parser_path = generate_parser.addOutputFileArg(parser_basename);
    generate_parser.addArgs(variant.args);
    generate_parser.stdio = .inherit;
    if (prev_generate_step.*) |prev| {
        generate_parser.step.dependOn(prev);
    }
    prev_generate_step.* = &generate_parser.step;
    matrix_step.dependOn(&generate_parser.step);

    const procedures_path = try std.fs.path.join(b.allocator, &.{ "languages", language, "procedures.zig" });
    const config_path = try std.fs.path.join(b.allocator, &.{ "languages", language, "config.zig" });

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
    const generated_parser = common.addGeneratedParserModule(
        b,
        options.target,
        options.optimize,
        case_name,
        try std.mem.concat(b.allocator, u8, &.{ case_name, "-parser" }),
        generated_parser_path,
        procedures_mod,
        config_mod,
        options.generator_modules.ll_generator_mod,
        options.generator_modules.lr_generator_mod,
    );
    const galley_parser_mod = generated_parser.runtime_mod;
    const parser_cli_options = b.addOptions();
    parser_cli_options.addOption(
        []const u8,
        "api_benchmark_step",
        "run-api-bench-generated-parser-matrix",
    );

    const parser_library_tests = b.addTest(.{
        .root_module = galley_parser_mod,
        .filters = options.filters,
    });
    const run_parser_library_tests = b.addRunArtifact(parser_library_tests);
    matrix_step.dependOn(&run_parser_library_tests.step);
    trackFilteredTestRun(b, options, &run_parser_library_tests.step);

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

    if (is_first_variant) {
        const exe_tests = b.addTest(.{
            .root_module = exe.root_module,
        });
        const run_exe_tests = b.addRunArtifact(exe_tests);
        matrix_step.dependOn(&run_exe_tests.step);
        trackFilteredTestRun(b, options, &run_exe_tests.step);
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
        variant.name,
        variant.args,
        variant.input_size,
    );
}

fn addLanguageSamples(
    b: *std.Build,
    matrix_step: *std.Build.Step,
    options: Options,
    galley_parser_mod: *std.Build.Module,
    exe: *std.Build.Step.Compile,
    language: []const u8,
    case_name: []const u8,
    config_label: []const u8,
    variant_args: []const []const u8,
    input_size: u16,
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
                config_label,
                sample_path,
                variant_args,
                input_size,
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
    config_label: []const u8,
    input_path: []const u8,
    variant_args: []const []const u8,
    input_size: u16,
) !void {
    const stat = try b.build_root.handle.statFile(b.graph.io, input_path, .{});
    const max_size = (@as(u64, 1) << @intCast(input_size));
    if (stat.size >= max_size) return;

    if (!shouldSkipGeneratedParserApiTests(variant_args, stat.size)) {
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
            "matrix",
            config_label,
            input_path,
            sample_input,
        );
        matrix_step.dependOn(&run_parser_api_tests.step);
        trackFilteredTestRun(b, options, &run_parser_api_tests.step);
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addArgs(&.{ "--verbosity", "0", "--iterations", "1" });

    if (std.mem.endsWith(u8, input_path, ".grm")) {
        const cache_dir = try std.fs.path.join(b.allocator, &.{ ".zig-cache", "matrix-validation", case_name });
        const cached_input = try std.fs.path.join(b.allocator, &.{ cache_dir, std.fs.path.basename(input_path) });

        const mkdir = b.addSystemCommand(&.{ "mkdir", "-p", cache_dir });
        mkdir.has_side_effects = true;

        const copy_input = b.addSystemCommand(&.{ "cp", input_path, cached_input });
        copy_input.has_side_effects = true;
        copy_input.step.dependOn(&mkdir.step);

        run_cmd.addArg(cached_input);
        run_cmd.step.dependOn(&copy_input.step);
    } else {
        run_cmd.addFileArg(b.path(input_path));
    }

    matrix_step.dependOn(&run_cmd.step);
}

fn addGeneratedParserApiTest(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    galley_parser_mod: *std.Build.Module,
    case_name: []const u8,
    suite: []const u8,
    config_label: []const u8,
    sample_path: []const u8,
    sample_input: []const u8,
) *std.Build.Step.Run {
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
        .root_module = parser_api_test_mod,
    });
    const run_parser_api_tests = b.addRunArtifact(parser_api_tests);
    run_parser_api_tests.addFileInput(b.path(sample_path));
    return run_parser_api_tests;
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

pub fn filterMatchesMatrixCase(
    allocator: std.mem.Allocator,
    test_filters: []const []const u8,
    parser_type: []const u8,
    language: []const u8,
) bool {
    if (test_filters.len == 0) return true;

    const parser_name = std.mem.concat(allocator, u8, &.{ parser_type, "-", language }) catch return false;
    defer allocator.free(parser_name);

    for (test_filters) |filter| {
        if (std.mem.eql(u8, filter, "generated_parser_api")) return true;
        if (std.mem.eql(u8, filter, parser_name)) return true;
        if (std.mem.indexOf(u8, filter, parser_name) != null) return true;
        if (std.mem.indexOf(u8, parser_name, filter) != null) return true;
    }
    return false;
}

pub fn filterMatchesGalleyParity(allocator: std.mem.Allocator, test_filters: []const []const u8) bool {
    if (test_filters.len == 0) return true;
    return filterMatchesMatrixCase(allocator, test_filters, "ll", "galley") or
        filterMatchesMatrixCase(allocator, test_filters, "lr", "galley");
}

fn trackFilteredTestRun(b: *std.Build, options: Options, run_step: *std.Build.Step) void {
    if (options.filters.len == 0) return;
    if (options.filtered_test_run_steps) |filtered_test_run_steps| {
        filtered_test_run_steps.append(b.allocator, run_step) catch @panic("OOM");
    }
}
