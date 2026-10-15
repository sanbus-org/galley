const std = @import("std");
const common = @import("common.zig");

/// A configuration the runtime refuses to compile, with the exact message.
const Refusal = struct {
    name: []const u8,
    /// Grammar the parser is generated from, so the configuration check is
    /// the only error.
    grammar_path: []const u8,
    config_path: []const u8,
    message: []const u8,
};

const refusals = [_]Refusal{
    .{
        .name = "ast-for-terminals-without-ast-or-procedures",
        .grammar_path = "tests/self-repeating/grammar.grm",
        .config_path = "tests/config-refusals/ast-for-terminals-config.zig",
        .message = "config.zig: ast_for_terminals = true requires ast = true or procedures = true; enable one of them or set ast_for_terminals = false",
    },
    .{
        .name = "newline-after-block-end-without-indentation-syntax",
        .grammar_path = "tests/self-repeating/grammar.grm",
        .config_path = "tests/config-refusals/newline-after-block-end-config.zig",
        .message = "config.zig: newline_after_block_end = true requires indentation_syntax = true; enable indentation_syntax or set newline_after_block_end = false",
    },
    .{
        .name = "block-terminals-without-indentation-syntax",
        .grammar_path = "tests/config-refusals/block-terminals.grm",
        .config_path = "tests/config-refusals/block-terminals-config.zig",
        .message = "config.zig: block_start/block_end require indentation_syntax = true; enable indentation_syntax or remove them from the grammar",
    },
};

/// Adds one compile step per refused configuration. Each step builds the
/// runtime against a fixture `config.zig` and passes only when compilation
/// fails with the expected message. The parser is generated from a real
/// grammar so the configuration check is the only error.
pub fn addConfigRefusalTests(
    b: *std.Build,
    test_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    generator: common.GeneratorModules,
    generate_parser_file_exe: *std.Build.Step.Compile,
) void {
    for (refusals) |refusal| {
        const generate_parser = b.addRunArtifact(generate_parser_file_exe);
        generate_parser.addArg("--grammar");
        generate_parser.addFileArg(b.path(refusal.grammar_path));
        generate_parser.addArgs(&.{ "--parser-type", "ll", "--label", "config-refusals" });
        generate_parser.addArg("--output");
        const generated_parser_path = generate_parser.addOutputFileArg(b.fmt("{s}-parser.zig", .{refusal.name}));
        generate_parser.stdio = .inherit;

        const procedures_mod = b.createModule(.{
            .root_source_file = b.path("tests/self-repeating/procedures.zig"),
            .target = target,
            .optimize = optimize,
        });
        const config_mod = b.createModule(.{
            .root_source_file = b.path(refusal.config_path),
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
            null,
            null,
            generated_parser_path,
            procedures_mod,
            config_mod,
            error_messages_mod,
            generator.runtime_options_mod,
            generator.signals_mod,
        );
        const root_mod = b.createModule(.{
            .root_source_file = b.path("tests/config-refusals/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "parser-under-test", .module = generated_parser.runtime_mod }},
        });
        const compile = b.addObject(.{
            .name = b.fmt("config-refusal-{s}", .{refusal.name}),
            .root_module = root_mod,
        });
        compile.expect_errors = .{ .contains = refusal.message };
        test_step.dependOn(&compile.step);
    }
}
