const std = @import("std");
const galley_grammar = @import("galley_grammar");
const ll_generator = @import("ll_generator");
const lr_generator = @import("lr_generator");
const common = @import("generator_common");

pub const ParserType = galley_grammar.data_structures.ParserType;
pub const Grammar = galley_grammar.procedures.Grammar;
pub const Rule = galley_grammar.procedures.Rule;
pub const RightHandSide = galley_grammar.procedures.RightHandSide;
pub const SymbolRef = galley_grammar.procedures.SymbolRef;
pub const SymbolKind = galley_grammar.procedures.SymbolKind;
pub const Options = common.Options;

pub fn parseGrammar(allocator: std.mem.Allocator, source: []const u8) !*Grammar {
    var parsed = try galley_grammar.parseBytes(std.Io.failing, allocator, source, .{});
    defer parsed.deinit();

    const parsed_grammar = galley_grammar.procedures.grammarFromAstAllocator(parsed.session.astAllocator()) orelse
        return error.GrammarModelMissing;
    return try cloneGrammar(allocator, parsed_grammar);
}

fn cloneGrammar(allocator: std.mem.Allocator, source: *const Grammar) !*Grammar {
    const cloned_rules = try allocator.alloc(Rule, source.rules.len);
    for (source.rules, cloned_rules) |source_rule, *cloned_rule| {
        const cloned_right_hand_sides = try allocator.alloc(RightHandSide, source_rule.right_hand_sides.len);
        for (source_rule.right_hand_sides, cloned_right_hand_sides) |source_rhs, *cloned_rhs| {
            const cloned_symbols = try allocator.alloc(SymbolRef, source_rhs.symbols.len);
            for (source_rhs.symbols, cloned_symbols) |source_symbol, *cloned_symbol| {
                cloned_symbol.* = .{
                    .id = try allocator.dupe(u8, source_symbol.id),
                    .kind = source_symbol.kind,
                    .procedures = try cloneStringSlice(allocator, source_symbol.procedures),
                };
            }
            cloned_rhs.* = .{
                .symbols = cloned_symbols,
                .procedures = try cloneStringSlice(allocator, source_rhs.procedures),
            };
        }
        cloned_rule.* = .{
            .header = try allocator.dupe(u8, source_rule.header),
            .procedures = try cloneStringSlice(allocator, source_rule.procedures),
            .right_hand_sides = cloned_right_hand_sides,
        };
    }

    const cloned_grammar = try allocator.create(Grammar);
    cloned_grammar.* = .{ .rules = cloned_rules };
    return cloned_grammar;
}

fn cloneStringSlice(allocator: std.mem.Allocator, source: []const []const u8) ![]const []const u8 {
    const cloned = try allocator.alloc([]const u8, source.len);
    for (source, cloned) |item, *cloned_item| {
        cloned_item.* = try allocator.dupe(u8, item);
    }
    return cloned;
}

pub fn emitParser(
    allocator: std.mem.Allocator,
    parsed_grammar: *const Grammar,
    writer: *std.Io.Writer,
    parser_type: ParserType,
    options: Options,
) !void {
    switch (parser_type) {
        .ll => try ll_generator.emitParserWithOptions(allocator, parsed_grammar, writer, options),
        .lr => try lr_generator.emitParserWithOptions(allocator, parsed_grammar, writer, options),
    }
}

pub fn emitErrorMessages(
    allocator: std.mem.Allocator,
    parsed_grammar: *const Grammar,
    writer: *std.Io.Writer,
    parser_type: ParserType,
    options: Options,
) !void {
    switch (parser_type) {
        .ll => try ll_generator.emitErrorMessagesWithOptions(allocator, parsed_grammar, writer, options),
        .lr => try lr_generator.emitErrorMessagesWithOptions(allocator, parsed_grammar, writer, options),
    }
}

pub fn emitParserFromSource(
    allocator: std.mem.Allocator,
    source: []const u8,
    writer: *std.Io.Writer,
    parser_type: ParserType,
    options: Options,
) !void {
    var parsed = try galley_grammar.parseBytes(std.Io.failing, allocator, source, .{});
    defer parsed.deinit();

    const parsed_grammar = galley_grammar.procedures.grammarFromAstAllocator(parsed.session.astAllocator()) orelse
        return error.GrammarModelMissing;

    try emitParser(allocator, parsed_grammar, writer, parser_type, options);
}

pub fn emitErrorMessagesFromSource(
    allocator: std.mem.Allocator,
    source: []const u8,
    writer: *std.Io.Writer,
    parser_type: ParserType,
    options: Options,
) !void {
    var parsed = try galley_grammar.parseBytes(std.Io.failing, allocator, source, .{});
    defer parsed.deinit();

    const parsed_grammar = galley_grammar.procedures.grammarFromAstAllocator(parsed.session.astAllocator()) orelse
        return error.GrammarModelMissing;

    try emitErrorMessages(allocator, parsed_grammar, writer, parser_type, options);
}

pub fn generateParserAlloc(
    allocator: std.mem.Allocator,
    source: []const u8,
    parser_type: ParserType,
    options: Options,
) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    try emitParserFromSource(allocator, source, &output.writer, parser_type, options);
    return output.toOwnedSlice();
}

pub fn generateErrorMessagesAlloc(
    allocator: std.mem.Allocator,
    source: []const u8,
    parser_type: ParserType,
    options: Options,
) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    try emitErrorMessagesFromSource(allocator, source, &output.writer, parser_type, options);
    return output.toOwnedSlice();
}

test generateParserAlloc {
    const source =
        \\Start
        \\| "a"
        \\
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const output = try generateParserAlloc(arena.allocator(), source, .ll, .{ .with_procedures = false });
    try std.testing.expect(std.mem.indexOf(u8, output, "pub fn parse") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "parse__AugmentedStart") != null);
}

test "LR rejects indistinguishable variable and terminal occurrence hooks" {
    const variable_source =
        \\Start
        \\| Choice
        \\
        \\Choice
        \\| Target@selected "x" "1"
        \\| Target "x" "2"
        \\
        \\Target
        \\| "t"
        \\
    ;
    const terminal_source =
        \\Start
        \\| Choice
        \\
        \\Choice
        \\| "t"@selected "x"
        \\| "t" "y"
        \\
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(
        error.AmbiguousProcedureHooks,
        generateParserAlloc(arena.allocator(), variable_source, .lr, .{}),
    );
    try std.testing.expectError(
        error.AmbiguousProcedureHooks,
        generateParserAlloc(arena.allocator(), terminal_source, .lr, .{ .ast_for_terminals = true }),
    );
}

test "LR accepts indistinguishable occurrences with identical hook chains" {
    const variable_source =
        \\Start
        \\| Choice
        \\
        \\Choice
        \\| Target@selected "x" "1"
        \\| Target@selected "x" "2"
        \\
        \\Target
        \\| "t"
        \\
    ;
    const terminal_source =
        \\Start
        \\| Choice
        \\
        \\Choice
        \\| "t"@selected "x"
        \\| "t"@selected "y"
        \\
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    _ = try generateParserAlloc(arena.allocator(), variable_source, .lr, .{});
    _ = try generateParserAlloc(arena.allocator(), terminal_source, .lr, .{ .ast_for_terminals = true });
}

fn expectContains(haystack: []const u8, needle: []const u8) !usize {
    const index = std.mem.indexOf(u8, haystack, needle) orelse {
        std.debug.print("missing expected text:\n{s}\n", .{needle});
        return error.MissingExpectedText;
    };
    return index;
}

fn expectContainsAfter(haystack: []const u8, needle: []const u8, start: usize) !usize {
    const index = std.mem.indexOfPos(u8, haystack, start, needle) orelse {
        std.debug.print("missing expected text after byte {d}:\n{s}\n", .{ start, needle });
        return error.MissingExpectedText;
    };
    return index;
}

fn generatedFunction(output: []const u8, declaration: []const u8) ![]const u8 {
    const start = try expectContains(output, declaration);
    const end = std.mem.indexOfPos(u8, output, start, "\n}\n") orelse
        return error.GeneratedFunctionEndMissing;
    return output[start .. end + "\n}\n".len];
}

const semantic_hook_grammar =
    \\Start
    \\| Items
    \\
    \\Items
    \\| Item ItemsTail
    \\
    \\ItemsTail
    \\| Item ItemsTail
    \\|
    \\
    \\Item
    \\| "a"
    \\
;

test "generateErrorMessagesAlloc emits semantic LL syntax error hooks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const output = try generateErrorMessagesAlloc(arena.allocator(), semantic_hook_grammar, .ll, .{ .with_procedures = false });

    _ = try expectContains(output, "pub fn syntax_error_ll_ItemsTail__expected_Item_or_end_of_ItemsTail");
    _ = try expectContains(output, "pub fn syntax_error_ll_Item__expected_terminal_a");
}

test "generateParserAlloc emits LL syntax error hook fallback chain" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const output = try generateParserAlloc(arena.allocator(), semantic_hook_grammar, .ll, .{ .with_procedures = false });

    const exact = try expectContains(output, "@hasDecl(error_messages, \"syntax_error_ll_ItemsTail__expected_Item_or_end_of_ItemsTail\")");
    const symbol = try expectContainsAfter(output, "@hasDecl(error_messages, \"syntax_error_ll_ItemsTail\")", exact);
    const parser_level = try expectContainsAfter(output, "@hasDecl(error_messages, \"syntax_error_ll\")", symbol);
    const global = try expectContainsAfter(output, "@hasDecl(error_messages, \"syntax_error\")", parser_level);
    _ = try expectContainsAfter(output, "root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi)", global);
}

test "generateParserAlloc emits position-based LL recovery" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const output = try generateParserAlloc(arena.allocator(), semantic_hook_grammar, .ll, .{ .with_ast = false, .with_procedures = false });

    _ = try expectContains(output, "fn llRecoveryOffset(");
    _ = try expectContains(output, "const report_syntax_error = context.beginSyntaxRecovery();");
    _ = try expectContains(output, "try parse_Item(context)");
    _ = try expectContains(output, "return @call(.always_tail, ll_syntax_error_");
    _ = try expectContains(output, "context.skipRecoveryInput(recovery_offset);");
    _ = try expectContains(output, "context.finishSyntaxRecovery();");
    _ = try expectContains(output, "if (report_syntax_error) 1 else 0");
    _ = try expectContains(output, "if (context.hasSyntaxErrors()) return root.ParseError.SyntaxError;");
    _ = try expectContains(output, "llRecoveryOffset(context, &[_][]const u8{\"a\"}, if (report_syntax_error) 1 else 0)");
}

test "generateParserAlloc emits position-based LR recovery" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const output = try generateParserAlloc(arena.allocator(), semantic_hook_grammar, .lr, .{ .with_procedures = false });

    _ = try expectContains(output, "fn lrRecoveryOffset(");
    _ = try expectContains(output, "state_recovery: while (true)");
    _ = try expectContains(output, "if (result.is_recovery) continue :state_recovery;");
    _ = try expectContains(output, ".is_recovery = true");
    _ = try expectContains(output, "const report_syntax_error = context.beginSyntaxRecovery();");
    _ = try expectContains(output, "lrRecoveryOffset(context, lr_recovery_candidates_");
    _ = try expectContains(output, "if (report_syntax_error) 1 else 0");
    _ = try expectContains(output, "context.skipRecoveryInput(recovery_offset);");
    _ = try expectContains(output, "_ = stack.pop() orelse unreachable;");
    _ = try expectContains(output, "if (context.hasSyntaxErrors()) return root.ParseError.SyntaxError;");
    _ = try expectContains(output, "@hasDecl(error_messages, \"syntax_error_lr_state_");
}

test "LL syntax error tail calls follow generated parser ABI" {
    const source =
        \\Start
        \\| "a"
        \\
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const no_ast_output = try generateParserAlloc(arena.allocator(), source, .ll, .{
        .with_ast = false,
        .with_procedures = false,
    });
    const no_ast_terminal = try generatedFunction(no_ast_output, "inline fn parse_terminal_a(");
    _ = try expectContains(no_ast_terminal, "return @call(.always_tail, ll_syntax_error_");

    const terminal_ast_output = try generateParserAlloc(arena.allocator(), source, .ll, .{
        .with_ast = true,
        .with_procedures = false,
        .ast_for_terminals = true,
    });
    const terminal_ast_parser = try generatedFunction(terminal_ast_output, "inline fn parse_terminal_a(");
    try std.testing.expect(std.mem.indexOf(u8, terminal_ast_parser, "@call(.always_tail") == null);
    _ = try expectContains(terminal_ast_parser, "return ll_syntax_error_");
}
