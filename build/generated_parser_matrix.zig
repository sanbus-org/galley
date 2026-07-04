const std = @import("std");

pub const Options = struct {
    target: std.Build.ResolvedTarget,
    clap_mod: *std.Build.Module,
    ll_generator_mod: *std.Build.Module,
    lr_generator_mod: *std.Build.Module,
    generate_parser_file_exe: *std.Build.Step.Compile,
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

pub fn add(b: *std.Build, matrix_step: *std.Build.Step, options: Options) !void {
    const languages = [_][]const u8{
        "galley",
        "augmented-json",
        "json",
        "json-structured-ast",
        "lisp",
        "lua",
        "test-ll",
        "test-ll1",
    };

    for (languages) |language| {
        for (parser_type_specs) |parser_type| {
            const grammar_path = try std.fs.path.join(b.allocator, &.{ "languages", language, parser_type.grammar_name });
            defer b.allocator.free(grammar_path);

            b.build_root.handle.access(b.graph.io, grammar_path, .{}) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            };

            for (matrix_variants) |variant| {
                try addCase(
                    b,
                    matrix_step,
                    options,
                    language,
                    parser_type.name,
                    grammar_path,
                    variant,
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
) !void {
    const matrix_optimize: std.builtin.OptimizeMode = .ReleaseFast;
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

    const procedures_path = try std.fs.path.join(b.allocator, &.{ "languages", language, "procedures.zig" });
    const config_path = try std.fs.path.join(b.allocator, &.{ "languages", language, "config.zig" });

    const procedures_mod = b.addModule(try std.mem.concat(b.allocator, u8, &.{ case_name, "-procedures" }), .{
        .root_source_file = b.path(procedures_path),
        .target = options.target,
        .optimize = matrix_optimize,
    });
    const config_mod = b.addModule(try std.mem.concat(b.allocator, u8, &.{ case_name, "-config" }), .{
        .root_source_file = b.path(config_path),
        .target = options.target,
        .optimize = matrix_optimize,
    });
    const parser_mod = b.addModule(try std.mem.concat(b.allocator, u8, &.{ case_name, "-parser" }), .{
        .root_source_file = generated_parser_path,
        .target = options.target,
        .optimize = matrix_optimize,
    });
    const galley_parser_mod = b.addModule(case_name, .{
        .root_source_file = b.path("src/parser_library.zig"),
        .target = options.target,
        .optimize = matrix_optimize,
        .imports = &.{
            .{ .name = "procedures", .module = procedures_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "parser", .module = parser_mod },
        },
    });
    galley_parser_mod.addImport("galley", galley_parser_mod);
    procedures_mod.addImport("galley", galley_parser_mod);
    procedures_mod.addImport("ll_generator", options.ll_generator_mod);
    procedures_mod.addImport("lr_generator", options.lr_generator_mod);
    config_mod.addImport("galley", galley_parser_mod);
    parser_mod.addImport("galley", galley_parser_mod);

    const parser_library_tests = b.addTest(.{
        .root_module = galley_parser_mod,
    });
    const run_parser_library_tests = b.addRunArtifact(parser_library_tests);
    matrix_step.dependOn(&run_parser_library_tests.step);

    const galley_cli_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = options.target,
        .optimize = matrix_optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "clap", .module = options.clap_mod },
            .{ .name = "galley", .module = galley_parser_mod },
        },
    });
    const exe = b.addExecutable(.{
        .name = case_name,
        .root_module = galley_cli_mod,
    });

    try addValidationInputs(b, matrix_step, options.target, matrix_optimize, galley_parser_mod, exe, language, variant.input_size);
}

fn addValidationInputs(
    b: *std.Build,
    matrix_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    galley_parser_mod: *std.Build.Module,
    exe: *std.Build.Step.Compile,
    language: []const u8,
    input_size: u16,
) !void {
    if (std.mem.eql(u8, language, "galley")) {
        for (&[_][]const u8{
            "languages/galley/ll.grm",
            "languages/galley/lr.grm",
            "languages/json/ll.grm",
            "languages/test-ll/ll.grm",
            "languages/test-ll1/ll.grm",
        }) |input_path| {
            try addValidationInput(b, matrix_step, target, optimize, galley_parser_mod, exe, input_path, input_size);
        }
    } else if (std.mem.eql(u8, language, "json-structured-ast")) {
        try addSampleValidationInputs(b, matrix_step, target, optimize, galley_parser_mod, exe, "json", input_size);
    } else if (std.mem.eql(u8, language, "augmented-json")) {
        try addSampleValidationInputs(b, matrix_step, target, optimize, galley_parser_mod, exe, "json", input_size);
        try addSampleValidationInputs(b, matrix_step, target, optimize, galley_parser_mod, exe, "augmented-json", input_size);
    } else {
        try addSampleValidationInputs(b, matrix_step, target, optimize, galley_parser_mod, exe, language, input_size);
    }
}

fn addSampleValidationInputs(
    b: *std.Build,
    matrix_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    galley_parser_mod: *std.Build.Module,
    exe: *std.Build.Step.Compile,
    sample_language: []const u8,
    input_size: u16,
) !void {
    const samples_path = try std.fs.path.join(b.allocator, &.{ "languages", sample_language, "samples" });
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
            try addValidationInput(b, matrix_step, target, optimize, galley_parser_mod, exe, sample_path, input_size);
        }
    }
}

fn addValidationInput(
    b: *std.Build,
    matrix_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    galley_parser_mod: *std.Build.Module,
    exe: *std.Build.Step.Compile,
    input_path: []const u8,
    input_size: u16,
) !void {
    const stat = try b.build_root.handle.statFile(b.graph.io, input_path, .{});
    const max_size = (@as(u64, 1) << @intCast(input_size));
    if (stat.size >= max_size) return;

    const sample_input = try b.build_root.handle.readFileAlloc(
        b.graph.io,
        input_path,
        b.allocator,
        .limited(std.math.maxInt(usize)),
    );
    addGeneratedParserApiTest(b, matrix_step, target, optimize, galley_parser_mod, input_path, sample_input);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addFileArg(b.path(input_path));
    run_cmd.addArgs(&.{ "--verbosity", "0", "--iterations", "1" });
    matrix_step.dependOn(&run_cmd.step);
}

fn addGeneratedParserApiTest(
    b: *std.Build,
    test_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    galley_parser_mod: *std.Build.Module,
    sample_path: []const u8,
    sample_input: []const u8,
) void {
    const parser_api_test_options = b.addOptions();
    parser_api_test_options.addOption([]const u8, "sample_path", sample_path);
    parser_api_test_options.addOption([]const u8, "sample_input", sample_input);
    const parser_api_test_mod = b.createModule(.{
        .root_source_file = b.path("src/generated_parser_library_test.zig"),
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
    test_step.dependOn(&run_parser_api_tests.step);
}
