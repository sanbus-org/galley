const std = @import("std");
const generator = @import("galley_generator");

const max_source_size = 1024 * 1024 * 1024;

const CliOptions = struct {
    grammar_path: ?[]const u8 = null,
    output_path: ?[]const u8 = null,
    config_output_path: ?[]const u8 = null,
    config_base_path: ?[]const u8 = null,
    parser_type: ?generator.ParserType = null,
    label: ?[]const u8 = null,
    strip_recovery_annotations: bool = false,
    indentation_syntax: bool = false,
    generator_options: generator.Options = .{},
    // Which option flags were present: absent flags leave the base
    // config's constant untouched (same contract as the CLI).
    ast_edited: bool = false,
    procedures_edited: bool = false,
    error_recovery_edited: bool = false,
    ast_for_terminals_edited: bool = false,
    position_tracking_edited: bool = false,
    input_streaming_edited: bool = false,
    allow_no_ast_tree_procedures_edited: bool = false,
    indentation_syntax_edited: bool = false,
};

pub fn main(init: std.process.Init) !void {
    const options = try parseArgs(init);
    const grammar_path = options.grammar_path orelse fatal("error: --grammar is required\n", .{});
    const output_path = options.output_path orelse fatal("error: --output is required\n", .{});
    const parser_type = options.parser_type orelse fatal("error: --parser-type is required\n", .{});

    if (options.label) |label| std.debug.print("generating {s}\n", .{label});

    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, grammar_path, init.gpa, .limited(max_source_size));
    defer init.gpa.free(source);

    // Option flags materialize as constants in the variant's config.zig:
    // the generated parser reads its configuration from that file at
    // comptime, never from generator-side overrides. When a base config is
    // supplied (the language's own config.zig), flags EDIT it in place —
    // preserving language truths (indentation syntax, message templates)
    // that variant flags do not express — otherwise the documented default
    // template is written.
    if (options.config_output_path) |config_output_path| {
        var config_data: []const u8 = undefined;
        if (options.config_base_path) |base_path| {
            const base = std.Io.Dir.cwd().readFileAlloc(init.io, base_path, init.gpa, .limited(max_source_size)) catch |err| switch (err) {
                error.FileNotFound => fatal("error: --config-base file not found: {s}\n", .{base_path}),
                else => return err,
            };
            defer init.gpa.free(base);
            config_data = try editedConfigFromFlags(init.gpa, base, options);
        } else {
            var config_buffer = std.Io.Writer.Allocating.init(init.gpa);
            try generator.config_file.write(&config_buffer.writer, options.generator_options, options.indentation_syntax);
            config_data = try init.gpa.dupe(u8, config_buffer.written());
            config_buffer.deinit();
        }
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = config_output_path, .data = config_data });
        init.gpa.free(config_data);
    }

    generator.atomic_file.write(
        init.io,
        .cwd(),
        output_path,
        .replace,
        ParserEmission{
            .allocator = init.arena.allocator(),
            .source = source,
            .parser_type = parser_type,
            .options = options.generator_options,
            .strip_recovery_annotations = options.strip_recovery_annotations,
        },
        ParserEmission.emit,
    ) catch |err| switch (err) {
        error.DuplicateRuleHeader => std.process.exit(1),
        else => return err,
    };
}

/// Applies every option flag present in `options` as an in-place constant
/// edit on `base`, using the shared single editing primitive.
fn editedConfigFromFlags(gpa: std.mem.Allocator, base: []const u8, options: CliOptions) ![]const u8 {
    var updated: ?[]const u8 = null;
    errdefer if (updated) |buffer| gpa.free(buffer);
    const o = options.generator_options;
    inline for (.{
        .{ "ast", if (options.ast_edited) (if (o.with_ast) "true" else "false") else null },
        .{ "procedures", if (options.procedures_edited) (if (o.with_procedures) "true" else "false") else null },
        .{ "error_recovery", if (options.error_recovery_edited) (if (o.with_error_recovery) "true" else "false") else null },
        .{ "ast_for_terminals", if (options.ast_for_terminals_edited) (if (o.ast_for_terminals) "true" else "false") else null },
        .{ "position_tracking", if (options.position_tracking_edited) (if (o.with_position_tracking orelse false) "true" else "false") else null },
        .{ "input_streaming", if (options.input_streaming_edited) (if (o.with_input_streaming) "true" else "false") else null },
        .{ "allow_no_ast_tree_procedures", if (options.allow_no_ast_tree_procedures_edited) (if (o.allow_no_ast_tree_procedures) "true" else "false") else null },
        .{ "indentation_syntax", if (options.indentation_syntax_edited) (if (options.indentation_syntax) "true" else "false") else null },
    }) |edit| {
        if (edit[1]) |value| {
            const next = try generator.config_file.editedConstantSource(gpa, updated orelse base, edit[0], value);
            if (updated) |previous| gpa.free(previous);
            updated = next;
        }
    }
    return updated orelse gpa.dupe(u8, base);
}

const ParserEmission = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    parser_type: generator.ParserType,
    options: generator.Options,
    strip_recovery_annotations: bool,

    fn emit(self: ParserEmission, writer: *std.Io.Writer) !void {
        if (self.strip_recovery_annotations) {
            const grammar = try generator.parseGrammar(self.allocator, self.source);
            const automatic_grammar = try generator.grammarWithoutRecoveryAnnotations(self.allocator, grammar);
            try generator.emitParser(self.allocator, automatic_grammar, writer, self.parser_type, self.options);
        } else {
            try generator.emitParserFromSource(self.allocator, self.source, writer, self.parser_type, self.options);
        }
    }
};

fn parseArgs(init: std.process.Init) !CliOptions {
    var result = CliOptions{};

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();

    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printUsage(init);
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--grammar")) {
            result.grammar_path = args.next() orelse fatal("error: --grammar requires a path\n", .{});
        } else if (std.mem.startsWith(u8, arg, "--grammar=")) {
            result.grammar_path = arg["--grammar=".len..];
        } else if (std.mem.eql(u8, arg, "--output")) {
            result.output_path = args.next() orelse fatal("error: --output requires a path\n", .{});
        } else if (std.mem.startsWith(u8, arg, "--output=")) {
            result.output_path = arg["--output=".len..];
        } else if (std.mem.eql(u8, arg, "--config-output")) {
            result.config_output_path = args.next() orelse fatal("error: --config-output requires a path\n", .{});
        } else if (std.mem.startsWith(u8, arg, "--config-output=")) {
            result.config_output_path = arg["--config-output=".len..];
        } else if (std.mem.eql(u8, arg, "--config-base")) {
            result.config_base_path = args.next() orelse fatal("error: --config-base requires a path\n", .{});
        } else if (std.mem.startsWith(u8, arg, "--config-base=")) {
            result.config_base_path = arg["--config-base=".len..];
        } else if (std.mem.eql(u8, arg, "--parser-type")) {
            const value = args.next() orelse fatal("error: --parser-type requires ll or lr\n", .{});
            result.parser_type = generator.ParserType.parse(value) orelse fatal("error: unsupported parser type: {s}\n", .{value});
        } else if (std.mem.startsWith(u8, arg, "--parser-type=")) {
            const value = arg["--parser-type=".len..];
            result.parser_type = generator.ParserType.parse(value) orelse fatal("error: unsupported parser type: {s}\n", .{value});
        } else if (std.mem.eql(u8, arg, "--label")) {
            result.label = args.next() orelse fatal("error: --label requires text\n", .{});
        } else if (std.mem.startsWith(u8, arg, "--label=")) {
            result.label = arg["--label=".len..];
        } else if (std.mem.eql(u8, arg, "--strip-recovery-annotations")) {
            result.strip_recovery_annotations = true;
        } else if (std.mem.eql(u8, arg, "--indentation-syntax")) {
            result.indentation_syntax = true;
            result.indentation_syntax_edited = true;
        } else if (std.mem.eql(u8, arg, "--with-ast")) {
            result.generator_options.with_ast = true;
            result.ast_edited = true;
        } else if (std.mem.eql(u8, arg, "--no-ast")) {
            result.generator_options.with_ast = false;
            result.ast_edited = true;
        } else if (std.mem.eql(u8, arg, "--with-procedures")) {
            result.generator_options.with_procedures = true;
            result.procedures_edited = true;
        } else if (std.mem.eql(u8, arg, "--no-procedures")) {
            result.generator_options.with_procedures = false;
            result.procedures_edited = true;
        } else if (std.mem.eql(u8, arg, "--allow-no-ast-tree-procedures")) {
            result.generator_options.allow_no_ast_tree_procedures = true;
            result.allow_no_ast_tree_procedures_edited = true;
        } else if (std.mem.eql(u8, arg, "--with-error-recovery")) {
            result.generator_options.with_error_recovery = true;
            result.error_recovery_edited = true;
        } else if (std.mem.eql(u8, arg, "--no-error-recovery")) {
            result.generator_options.with_error_recovery = false;
            result.error_recovery_edited = true;
        } else if (std.mem.eql(u8, arg, "--with-position-tracking")) {
            result.generator_options.with_position_tracking = true;
            result.position_tracking_edited = true;
        } else if (std.mem.eql(u8, arg, "--no-position-tracking")) {
            result.generator_options.with_position_tracking = false;
            result.position_tracking_edited = true;
        } else if (std.mem.eql(u8, arg, "--with-input-streaming")) {
            result.generator_options.with_input_streaming = true;
            result.input_streaming_edited = true;
        } else if (std.mem.eql(u8, arg, "--no-input-streaming")) {
            result.generator_options.with_input_streaming = false;
            result.input_streaming_edited = true;
        } else if (std.mem.eql(u8, arg, "--ast-for-terminals")) {
            result.generator_options.ast_for_terminals = true;
            result.ast_for_terminals_edited = true;
        } else if (std.mem.eql(u8, arg, "--no-ast-for-terminals")) {
            result.generator_options.ast_for_terminals = false;
            result.ast_for_terminals_edited = true;
        } else {
            fatal("error: unknown argument: {s}\n", .{arg});
        }
    }

    return result;
}

fn printUsage(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll(
        \\usage: generate-parser-file --grammar <PATH> --output <PATH> --parser-type ll|lr [OPTIONS]
        \\
        \\Options:
        \\  -h, --help                 Display this help and exit.
        \\      --grammar <PATH>       Grammar file to parse.
        \\      --output <PATH>        Generated parser output path.
        \\      --config-output <PATH> Write the generation-time config.zig for
        \\                             this variant (constants derived from the
        \\                             option flags below) to this path.
        \\      --parser-type ll|lr    Parser backend to generate.
        \\      --label <TEXT>         Progress label printed before generation.
        \\      --strip-recovery-annotations
        \\                             Test-only: clear recovery annotations before generation.
        \\      --indentation-syntax   Sets indentation_syntax = true in the
        \\                             written config.zig.
        \\      --with-ast             Enables AST construction.
        \\      --no-ast               Disables AST construction.
        \\      --with-procedures      Enables procedure hooks.
        \\      --no-procedures        Disables procedure hooks.
        \\      --allow-no-ast-tree-procedures
        \\                             Treats standard tree-manipulation helpers as
        \\                             no-ops in no-AST mode instead of a compile error.
        \\      --with-error-recovery  Enables syntax-error recovery.
        \\      --no-error-recovery    Disables syntax-error recovery.
        \\      --with-position-tracking
        \\                             Enables line and column tracking.
        \\      --no-position-tracking Disables line and column tracking.
        \\      --with-input-streaming Enables incremental file input.
        \\      --no-input-streaming   Loads complete files before parsing.
        \\      --ast-for-terminals    Enables AST nodes for terminals.
        \\      --no-ast-for-terminals Disables AST nodes for terminals.
        \\
    );
    try stdout.flush();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
