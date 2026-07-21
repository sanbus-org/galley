const std = @import("std");
const generator = @import("galley_generator");

const max_input_size = 1024 * 1024 * 1024;

const CliOptions = struct {
    grammar_path: ?[]const u8 = null,
    output_path: ?[]const u8 = null,
    parser_type: ?generator.ParserType = null,
    label: ?[]const u8 = null,
    strip_recovery_annotations: bool = false,
    generator_options: generator.Options = .{},
};

pub fn main(init: std.process.Init) !void {
    const options = try parseArgs(init);
    const grammar_path = options.grammar_path orelse fatal("error: --grammar is required\n", .{});
    const output_path = options.output_path orelse fatal("error: --output is required\n", .{});
    const parser_type = options.parser_type orelse fatal("error: --parser-type is required\n", .{});

    if (options.label) |label| std.debug.print("generating {s}\n", .{label});

    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, grammar_path, init.gpa, .limited(max_input_size));
    defer init.gpa.free(source);

    var output = try std.Io.Dir.cwd().createFile(init.io, output_path, .{ .truncate = true });
    defer output.close(init.io);

    var file_buffer: [8192]u8 = undefined;
    var file_writer = output.writer(init.io, &file_buffer);
    if (options.strip_recovery_annotations) {
        const grammar = try generator.parseGrammar(init.arena.allocator(), source);
        const automatic_grammar = try grammarWithoutRecoveryAnnotations(init.arena.allocator(), grammar);
        try generator.emitParser(init.arena.allocator(), automatic_grammar, &file_writer.interface, parser_type, options.generator_options);
    } else {
        try generator.emitParserFromSource(init.arena.allocator(), source, &file_writer.interface, parser_type, options.generator_options);
    }
    try file_writer.interface.flush();
}

fn grammarWithoutRecoveryAnnotations(allocator: std.mem.Allocator, source: *const generator.Grammar) !*generator.Grammar {
    const rules = try allocator.alloc(generator.Rule, source.rules.len);
    for (source.rules, rules) |source_rule, *rule| {
        const right_hand_sides = try allocator.alloc(generator.RightHandSide, source_rule.right_hand_sides.len);
        for (source_rule.right_hand_sides, right_hand_sides) |source_rhs, *rhs| {
            const symbols = try allocator.alloc(generator.SymbolRef, source_rhs.symbols.len);
            for (source_rhs.symbols, symbols) |source_symbol, *symbol| {
                symbol.* = .{
                    .id = source_symbol.id,
                    .kind = source_symbol.kind,
                    .annotations = .{ .procedures = source_symbol.annotations.procedures },
                };
            }
            rhs.* = .{
                .symbols = symbols,
                .annotations = .{ .procedures = source_rhs.annotations.procedures },
            };
        }
        rule.* = .{
            .header = source_rule.header,
            .annotations = .{ .procedures = source_rule.annotations.procedures },
            .right_hand_sides = right_hand_sides,
        };
    }

    const grammar = try allocator.create(generator.Grammar);
    grammar.* = .{ .rules = rules };
    return grammar;
}

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
        } else if (std.mem.eql(u8, arg, "--with-ast")) {
            result.generator_options.with_ast = true;
        } else if (std.mem.eql(u8, arg, "--no-ast")) {
            result.generator_options.with_ast = false;
        } else if (std.mem.eql(u8, arg, "--with-procedures")) {
            result.generator_options.with_procedures = true;
        } else if (std.mem.eql(u8, arg, "--no-procedures")) {
            result.generator_options.with_procedures = false;
        } else if (std.mem.eql(u8, arg, "--with-error-recovery")) {
            result.generator_options.with_error_recovery = true;
        } else if (std.mem.eql(u8, arg, "--no-error-recovery")) {
            result.generator_options.with_error_recovery = false;
        } else if (std.mem.eql(u8, arg, "--ast-for-terminals")) {
            result.generator_options.ast_for_terminals = true;
        } else if (std.mem.eql(u8, arg, "--no-ast-for-terminals")) {
            result.generator_options.ast_for_terminals = false;
        } else if (std.mem.eql(u8, arg, "--input-size")) {
            const value = args.next() orelse fatal("error: --input-size requires a bit width\n", .{});
            result.generator_options.input_size = std.fmt.parseInt(u16, value, 10) catch fatal("error: invalid --input-size: {s}\n", .{value});
        } else if (std.mem.startsWith(u8, arg, "--input-size=")) {
            const value = arg["--input-size=".len..];
            result.generator_options.input_size = std.fmt.parseInt(u16, value, 10) catch fatal("error: invalid --input-size: {s}\n", .{value});
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
        \\      --parser-type ll|lr    Parser backend to generate.
        \\      --label <TEXT>         Progress label printed before generation.
        \\      --strip-recovery-annotations
        \\                             Test-only: clear recovery annotations before generation.
        \\      --with-ast             Enables AST construction.
        \\      --no-ast               Disables AST construction.
        \\      --with-procedures      Enables procedure hooks.
        \\      --no-procedures        Disables procedure hooks.
        \\      --with-error-recovery  Enables syntax-error recovery.
        \\      --no-error-recovery    Disables syntax-error recovery.
        \\      --ast-for-terminals    Enables AST nodes for terminals.
        \\      --no-ast-for-terminals Disables AST nodes for terminals.
        \\      --input-size <BITS>    Number of bits required to fit input size.
        \\
    );
    try stdout.flush();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
