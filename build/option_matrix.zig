const std = @import("std");
const common = @import("common.zig");

/// Single source of truth for the pairwise generation-option matrix.
///
/// The full cartesian product of generation flags across languages would
/// explode test time, so this matrix covers the remaining flags pairwise
/// (2-wise) on one tiny grammar instead. The main matrix in
/// `generated_parser_matrix.zig` covers `ast × procedures × terminal-ast`
/// across languages; the targeted generator-suite tests cover
/// indentation, verbatim, and streaming kinds with fixed flags. What is
/// left — `position_tracking × input_streaming` crossed with the rest —
/// lives here.
///
/// Every variant below is 2-wise covering for the seven flags, plus one
/// explicit sliding-window representative. Sliding needs a three-way
/// interaction (`streaming` without retention: no AST, no procedures, no
/// verbatim) that pairwise alone does not guarantee, and it exercises
/// distinct runtime code (`sliding_input_enabled` in `src/runtime/api.zig`),
/// so it gets its own row rather than emerging by accident.
const OptionFlags = struct {
    ast: bool,
    procedures: bool,
    terminal_ast: bool,
    error_recovery: bool,
    position_tracking: bool,
    input_streaming: bool,
    allow_no_ast_tree: bool,

    /// Feature-model gate. Every variant must satisfy it; `addOptionMatrix`
    /// asserts this, so an invalid combination fails the build instead of
    /// silently testing something meaningless.
    fn isValid(self: OptionFlags) bool {
        if (self.terminal_ast and !self.ast) return false;
        if (self.allow_no_ast_tree and (self.ast or !self.procedures)) return false;
        return true;
    }

    fn appendArgs(self: OptionFlags, generate_parser: *std.Build.Step.Run) void {
        generate_parser.addArg(if (self.ast) "--with-ast" else "--no-ast");
        generate_parser.addArg(if (self.procedures) "--with-procedures" else "--no-procedures");
        generate_parser.addArg(if (self.terminal_ast) "--ast-for-terminals" else "--no-ast-for-terminals");
        generate_parser.addArg(if (self.error_recovery) "--with-error-recovery" else "--no-error-recovery");
        generate_parser.addArg(if (self.position_tracking) "--with-position-tracking" else "--no-position-tracking");
        generate_parser.addArg(if (self.input_streaming) "--with-input-streaming" else "--no-input-streaming");
        if (self.allow_no_ast_tree) generate_parser.addArg("--allow-no-ast-tree-procedures");
    }
};

const OptionVariant = struct {
    name: []const u8,
    flags: OptionFlags,
};

/// 2-wise covering set for the seven flags (80 valid pairs), verified by
/// exhaustive pair enumeration, plus the sliding representative.
const option_matrix_variants = [_]OptionVariant{
    .{ .name = "minimal", .flags = .{ .ast = false, .procedures = false, .terminal_ast = false, .error_recovery = false, .position_tracking = false, .input_streaming = false, .allow_no_ast_tree = false } },
    .{ .name = "everything", .flags = .{ .ast = true, .procedures = true, .terminal_ast = true, .error_recovery = true, .position_tracking = true, .input_streaming = true, .allow_no_ast_tree = false } },
    .{ .name = "allow-retained-streaming", .flags = .{ .ast = false, .procedures = true, .terminal_ast = false, .error_recovery = false, .position_tracking = true, .input_streaming = true, .allow_no_ast_tree = true } },
    .{ .name = "allow-recovery", .flags = .{ .ast = false, .procedures = true, .terminal_ast = false, .error_recovery = true, .position_tracking = false, .input_streaming = false, .allow_no_ast_tree = true } },
    .{ .name = "terminal-only", .flags = .{ .ast = true, .procedures = false, .terminal_ast = true, .error_recovery = false, .position_tracking = false, .input_streaming = false, .allow_no_ast_tree = false } },
    .{ .name = "ast-recovery-streaming", .flags = .{ .ast = true, .procedures = false, .terminal_ast = false, .error_recovery = true, .position_tracking = false, .input_streaming = true, .allow_no_ast_tree = false } },
    .{ .name = "minimal-position", .flags = .{ .ast = false, .procedures = false, .terminal_ast = false, .error_recovery = false, .position_tracking = true, .input_streaming = false, .allow_no_ast_tree = false } },
    .{ .name = "sliding", .flags = .{ .ast = false, .procedures = false, .terminal_ast = false, .error_recovery = false, .position_tracking = true, .input_streaming = true, .allow_no_ast_tree = false } },
};

pub fn addOptionMatrix(
    b: *std.Build,
    test_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    generator: common.GeneratorModules,
    generate_parser_file_exe: *std.Build.Step.Compile,
    parser_type: []const u8,
    filters: []const []const u8,
    filtered_test_run_steps: *std.ArrayList(*std.Build.Step),
) !void {
    for (option_matrix_variants) |variant| {
        std.debug.assert(variant.flags.isValid());
        const run_tests = try addOptionVariantTests(
            b,
            target,
            optimize,
            generator,
            generate_parser_file_exe,
            parser_type,
            variant,
            filters,
        );
        test_step.dependOn(&run_tests.step);
        if (filters.len != 0) filtered_test_run_steps.append(b.allocator, &run_tests.step) catch @panic("OOM");
    }
}

fn addOptionVariantTests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    generator: common.GeneratorModules,
    generate_parser_file_exe: *std.Build.Step.Compile,
    parser_type: []const u8,
    variant: OptionVariant,
    filters: []const []const u8,
) !*std.Build.Step.Run {
    const parser_name = b.fmt("option-matrix-{s}-{s}", .{ parser_type, variant.name });
    const generate_parser = b.addRunArtifact(generate_parser_file_exe);
    generate_parser.addArg("--grammar");
    generate_parser.addFileArg(b.path("tests/self-repeating/grammar.grm"));
    generate_parser.addArg("--parser-type");
    generate_parser.addArg(parser_type);
    generate_parser.addArg("--label");
    generate_parser.addArg(b.fmt("{s}/option-matrix/{s}", .{ parser_type, variant.name }));
    generate_parser.addArg("--output");
    const generated_parser_path = generate_parser.addOutputFileArg(b.fmt("{s}-parser.zig", .{parser_name}));
    generate_parser.addArg("--config-output");
    const generated_config_path = generate_parser.addOutputFileArg(b.fmt("{s}-config.zig", .{parser_name}));
    variant.flags.appendArgs(generate_parser);
    generate_parser.stdio = .inherit;

    const procedures_mod = b.createModule(.{
        .root_source_file = b.path("tests/self-repeating/procedures.zig"),
        .target = target,
        .optimize = optimize,
    });
    const config_mod = b.createModule(.{
        .root_source_file = generated_config_path,
        .target = target,
        .optimize = optimize,
    });
    const error_messages_mod = b.createModule(.{
        .root_source_file = b.path("tests/self-repeating/error_messages.zig"),
        .target = target,
        .optimize = optimize,
    });
    const generated_parser = common.addGeneratedParserModule(
        b,
        target,
        optimize,
        parser_name,
        b.fmt("{s}-source", .{parser_name}),
        generated_parser_path,
        procedures_mod,
        config_mod,
        error_messages_mod,
        generator.runtime_options_mod,
    );

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/tests/self_repeating_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "parser-under-test", .module = generated_parser.runtime_mod }},
    });
    const tests = b.addTest(.{
        .name = b.fmt("{s}-tests", .{parser_name}),
        .root_module = test_mod,
        .filters = filters,
    });
    return b.addRunArtifact(tests);
}

test "every option-matrix variant satisfies the feature model" {
    for (option_matrix_variants) |variant| {
        try std.testing.expect(variant.flags.isValid());
    }
}

test "option matrix covers every valid flag pair" {
    const flag_count = 7;
    // Exhaustive pair check over all valid global assignments.
    var value: usize = 0;
    while (value < (@as(usize, 1) << flag_count)) : (value += 1) {
        const candidate = OptionFlags{
            .ast = value & 0b0000001 != 0,
            .procedures = value & 0b0000010 != 0,
            .terminal_ast = value & 0b0000100 != 0,
            .error_recovery = value & 0b0001000 != 0,
            .position_tracking = value & 0b0010000 != 0,
            .input_streaming = value & 0b0100000 != 0,
            .allow_no_ast_tree = value & 0b1000000 != 0,
        };
        if (!candidate.isValid()) continue;
        const candidate_bits = [_]bool{
            candidate.ast,
            candidate.procedures,
            candidate.terminal_ast,
            candidate.error_recovery,
            candidate.position_tracking,
            candidate.input_streaming,
            candidate.allow_no_ast_tree,
        };
        for (0..flag_count) |i| {
            for (i + 1..flag_count) |j| {
                var found = false;
                for (option_matrix_variants) |variant| {
                    const variant_bits = [_]bool{
                        variant.flags.ast,
                        variant.flags.procedures,
                        variant.flags.terminal_ast,
                        variant.flags.error_recovery,
                        variant.flags.position_tracking,
                        variant.flags.input_streaming,
                        variant.flags.allow_no_ast_tree,
                    };
                    if (variant_bits[i] == candidate_bits[i] and variant_bits[j] == candidate_bits[j]) {
                        found = true;
                        break;
                    }
                }
                try std.testing.expect(found);
            }
        }
    }
}
