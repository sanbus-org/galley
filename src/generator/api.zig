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
pub const Annotations = galley_grammar.procedures.Annotations;
pub const RecoveryPoint = galley_grammar.procedures.RecoveryPoint;
pub const RecoveryResume = galley_grammar.procedures.RecoveryResume;
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
                    .annotations = try cloneAnnotations(allocator, source_symbol.annotations),
                };
            }
            cloned_rhs.* = .{
                .symbols = cloned_symbols,
                .annotations = try cloneAnnotations(allocator, source_rhs.annotations),
            };
        }
        cloned_rule.* = .{
            .header = try allocator.dupe(u8, source_rule.header),
            .annotations = try cloneAnnotations(allocator, source_rule.annotations),
            .right_hand_sides = cloned_right_hand_sides,
        };
    }

    const cloned_grammar = try allocator.create(Grammar);
    cloned_grammar.* = .{ .rules = cloned_rules };
    return cloned_grammar;
}

fn cloneAnnotations(allocator: std.mem.Allocator, source: Annotations) !Annotations {
    const recovery_points = try allocator.alloc(RecoveryPoint, source.recovery_points.len);
    for (source.recovery_points, recovery_points) |point, *cloned| {
        cloned.* = .{
            .terminal = try allocator.dupe(u8, point.terminal),
            .@"resume" = point.@"resume",
        };
    }
    return .{
        .procedures = try cloneStringSlice(allocator, source.procedures),
        .recovery_points = recovery_points,
    };
}

fn cloneStringSlice(allocator: std.mem.Allocator, source: []const []const u8) ![]const []const u8 {
    const cloned = try allocator.alloc([]const u8, source.len);
    for (source, cloned) |item, *cloned_item| {
        cloned_item.* = try allocator.dupe(u8, item);
    }
    return cloned;
}

fn grammarWithoutRecoveryAnnotations(allocator: std.mem.Allocator, source: *const Grammar) !*Grammar {
    const rules = try allocator.alloc(Rule, source.rules.len);
    for (source.rules, rules) |source_rule, *rule| {
        const right_hand_sides = try allocator.alloc(RightHandSide, source_rule.right_hand_sides.len);
        for (source_rule.right_hand_sides, right_hand_sides) |source_rhs, *rhs| {
            const symbols = try allocator.alloc(SymbolRef, source_rhs.symbols.len);
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
    const grammar = try allocator.create(Grammar);
    grammar.* = .{ .rules = rules };
    return grammar;
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

test "grammar model preserves unified recovery and procedure annotations" {
    const source = "Start!^\"}\"!';\x03^@lhsHook\n" ++
        "|!\",\"^@productionHook \"a\" Child!^']\x03@occurrenceHook\n" ++
        "\n" ++
        "Child\n" ++
        "| \"x\"\n";

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const grammar = try parseGrammar(arena.allocator(), source);
    try std.testing.expectEqual(@as(usize, 2), grammar.rules.len);
    const start = grammar.rules[0];
    try std.testing.expectEqualStrings("lhsHook", start.annotations.procedures[0]);
    try std.testing.expectEqual(@as(usize, 2), start.annotations.recovery_points.len);
    try std.testing.expectEqualStrings("}", start.annotations.recovery_points[0].terminal);
    try std.testing.expectEqual(RecoveryResume.before, start.annotations.recovery_points[0].@"resume");
    try std.testing.expectEqualStrings(";", start.annotations.recovery_points[1].terminal);
    try std.testing.expectEqual(RecoveryResume.after, start.annotations.recovery_points[1].@"resume");

    const production = start.right_hand_sides[0];
    try std.testing.expectEqualStrings("productionHook", production.annotations.procedures[0]);
    try std.testing.expectEqualStrings(",", production.annotations.recovery_points[0].terminal);
    try std.testing.expectEqual(RecoveryResume.after, production.annotations.recovery_points[0].@"resume");

    const occurrence = production.symbols[1];
    try std.testing.expectEqual(.variable, occurrence.kind);
    try std.testing.expectEqualStrings("occurrenceHook", occurrence.annotations.procedures[0]);
    try std.testing.expectEqualStrings("]", occurrence.annotations.recovery_points[0].terminal);
    try std.testing.expectEqual(RecoveryResume.before, occurrence.annotations.recovery_points[0].@"resume");
}

test "recovery caret placement is structural when terminals contain carets" {
    const source = "Start!^\"^\"!\"^\"^!^'^\x03!'\x5e\x03^\n" ++
        "| \"x\"\n";

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const grammar = try parseGrammar(arena.allocator(), source);
    const points = grammar.rules[0].annotations.recovery_points;
    try std.testing.expectEqual(@as(usize, 4), points.len);
    for (points) |point| try std.testing.expectEqualStrings("^", point.terminal);
    try std.testing.expectEqual(RecoveryResume.before, points[0].@"resume");
    try std.testing.expectEqual(RecoveryResume.after, points[1].@"resume");
    try std.testing.expectEqual(RecoveryResume.before, points[2].@"resume");
    try std.testing.expectEqual(RecoveryResume.after, points[3].@"resume");
}

test "parsed grammar rejects duplicate headers and invalid recovery annotations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.DuplicateRuleHeader, parseGrammar(arena.allocator(),
        \\Start
        \\| "a"
        \\
        \\Start
        \\| "b"
        \\
    ));
    try std.testing.expectError(error.InvalidRecoveryTarget, parseGrammar(arena.allocator(),
        \\Start
        \\| "a"!^";"
        \\
    ));
    try std.testing.expectError(error.EmptyRecoveryTerminal, parseGrammar(arena.allocator(),
        \\Start!^""
        \\| "a"
        \\
    ));
    try std.testing.expectError(error.NulRecoveryTerminal, parseGrammar(arena.allocator(),
        \\Start!^"\x00"
        \\| "a"
        \\
    ));
    try std.testing.expectError(error.SyntaxError, parseGrammar(arena.allocator(),
        \\Start!^digit
        \\| "a"
        \\
    ));
    try std.testing.expectError(error.SyntaxError, parseGrammar(arena.allocator(),
        \\Start!";"
        \\| "a"
        \\
    ));
    try std.testing.expectError(error.SyntaxError, parseGrammar(arena.allocator(),
        \\Start@hook!^";"
        \\| "a"
        \\
    ));
}

test "programmatic grammar validation rejects duplicate headers and terminal occurrence recovery" {
    const recovery = [_]RecoveryPoint{.{ .terminal = ";", .@"resume" = .after }};
    const terminal_symbols = [_]SymbolRef{.{
        .id = "a",
        .kind = .terminal,
        .annotations = .{ .recovery_points = &recovery },
    }};
    const duplicate_rules = [_]Rule{
        .{ .header = "Start", .right_hand_sides = &.{.{ .symbols = &.{} }} },
        .{ .header = "Start", .right_hand_sides = &.{.{ .symbols = &.{} }} },
    };
    const invalid_rules = [_]Rule{.{
        .header = "Start",
        .right_hand_sides = &.{.{ .symbols = &terminal_symbols }},
    }};

    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try std.testing.expectError(error.DuplicateRuleHeader, emitParser(
        std.testing.allocator,
        &.{ .rules = &duplicate_rules },
        &output.writer,
        .ll,
        .{},
    ));
    try std.testing.expectError(error.InvalidRecoveryTarget, emitParser(
        std.testing.allocator,
        &.{ .rules = &invalid_rules },
        &output.writer,
        .lr,
        .{},
    ));
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

fn expectNotContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) != null) {
        std.debug.print("unexpected generated text:\n{s}\n", .{needle});
        return error.UnexpectedGeneratedText;
    }
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

    const output = try generateParserAlloc(arena.allocator(), semantic_hook_grammar, .ll, .{
        .with_ast = false,
        .with_procedures = false,
        .with_error_recovery = true,
    });

    _ = try expectContains(output, "pub const is_error_recovery_enabled = true;");
    _ = try expectContains(output, "pub const error_recovery_mode: ErrorRecoveryMode = .automatic;");
    _ = try expectContains(output, "fn llRecoveryOffset(");
    _ = try expectContains(output, "const report_syntax_error = context.beginSyntaxRecovery();");
    _ = try expectContains(output, "try parse_Item(context)");
    _ = try expectContains(output, "builtin.zig_backend == .stage2_llvm or builtin.zig_backend == .stage2_aarch64");
    _ = try expectContains(output, "return @call(.always_tail, ll_syntax_error_");
    _ = try expectContains(output, "return ll_syntax_error_");
    _ = try expectContains(output, "context.skipRecoveryInput(recovery_offset);");
    _ = try expectContains(output, "context.finishSyntaxRecovery();");
    _ = try expectContains(output, "if (report_syntax_error) 1 else 0");
    _ = try expectContains(output, "if (context.hasSyntaxErrors()) return root.ParseError.SyntaxError;");
    _ = try expectContains(output, "llRecoveryOffset(context, &[_][]const u8{\"a\"}, if (report_syntax_error) 1 else 0)");
}

test "generateParserAlloc emits position-based LR recovery" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const output = try generateParserAlloc(arena.allocator(), semantic_hook_grammar, .lr, .{
        .with_procedures = false,
        .with_error_recovery = true,
    });

    _ = try expectContains(output, "pub const is_error_recovery_enabled = true;");
    _ = try expectContains(output, "pub const error_recovery_mode: ErrorRecoveryMode = .automatic;");
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

test "generateParserAlloc defaults to fail-fast syntax errors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const ll_output = try generateParserAlloc(arena.allocator(), semantic_hook_grammar, .ll, .{ .with_procedures = false });
    _ = try expectContains(ll_output, "pub const is_error_recovery_enabled = false;");
    _ = try expectContains(ll_output, "pub const error_recovery_mode: ErrorRecoveryMode = .disabled;");
    _ = try expectContains(ll_output, "try context.recordSyntaxDiagnostic(");
    _ = try expectContains(ll_output, "return root.ParseError.SyntaxError;");
    try expectNotContains(ll_output, "llRecoveryOffset");
    try expectNotContains(ll_output, "beginSyntaxRecovery");
    try expectNotContains(ll_output, "ll_syntax_error_");
    try expectNotContains(ll_output, "always_tail");

    const lr_output = try generateParserAlloc(arena.allocator(), semantic_hook_grammar, .lr, .{ .with_procedures = false });
    _ = try expectContains(lr_output, "pub const is_error_recovery_enabled = false;");
    _ = try expectContains(lr_output, "pub const error_recovery_mode: ErrorRecoveryMode = .disabled;");
    _ = try expectContains(lr_output, "try context.recordSyntaxDiagnostic(");
    _ = try expectContains(lr_output, "return root.ParseError.SyntaxError;");
    try expectNotContains(lr_output, "lrRecoveryOffset");
    try expectNotContains(lr_output, "state_recovery:");
    try expectNotContains(lr_output, "lr_syntax_error_");
    try expectNotContains(lr_output, ".is_recovery");
}

test "disabled recovery annotations are inert in LL and LR generation" {
    const plain_source =
        \\Start
        \\| Item
        \\
        \\Item
        \\| "x" Item
        \\|
        \\
    ;
    const annotated_source =
        \\Start!^"synchronization"
        \\|!";"^ Item!^","
        \\
        \\Item
        \\| "x" Item
        \\|
        \\
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const options: Options = .{
        .with_ast = false,
        .with_procedures = false,
        .with_error_recovery = false,
    };

    inline for ([_]ParserType{ .ll, .lr }) |parser_type| {
        const plain = try generateParserAlloc(arena.allocator(), plain_source, parser_type, options);
        const annotated = try generateParserAlloc(arena.allocator(), annotated_source, parser_type, options);
        try std.testing.expectEqualStrings(plain, annotated);
    }
}

test "Galley recovery annotations preserve the canonical LR topology" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const source = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "languages/galley/lr.grm",
        arena.allocator(),
        .limited(1024 * 1024),
    );
    const annotated = try parseGrammar(arena.allocator(), source);
    const stripped = try grammarWithoutRecoveryAnnotations(arena.allocator(), annotated);
    const options: Options = .{
        .with_ast = true,
        .with_procedures = true,
        .with_error_recovery = true,
    };

    try std.testing.expect(try lr_generator.canonicalTopologyEqualForTesting(arena.allocator(), annotated, stripped, options));
    try std.testing.expectEqual(@as(usize, 126), try lr_generator.canonicalStateCountForTesting(arena.allocator(), annotated, options));

    var annotated_messages: std.Io.Writer.Allocating = .init(arena.allocator());
    var stripped_messages: std.Io.Writer.Allocating = .init(arena.allocator());
    try lr_generator.emitErrorMessagesWithOptions(arena.allocator(), annotated, &annotated_messages.writer, options);
    try lr_generator.emitErrorMessagesWithOptions(arena.allocator(), stripped, &stripped_messages.writer, options);
    try std.testing.expectEqualStrings(annotated_messages.written(), stripped_messages.written());
}

test "generateParserAlloc emits explicit-only recovery when annotations exist" {
    const source =
        \\Start
        \\| "a" Child!";"^
        \\
        \\Child
        \\| "x"
        \\
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const options: Options = .{
        .with_ast = false,
        .with_procedures = false,
        .with_error_recovery = true,
    };
    const ll_output = try generateParserAlloc(arena.allocator(), source, .ll, options);
    _ = try expectContains(ll_output, "pub const is_error_recovery_enabled = true;");
    _ = try expectContains(ll_output, "pub const error_recovery_mode: ErrorRecoveryMode = .explicit;");
    _ = try expectContains(ll_output, "const ExplicitRecoveryScope = struct");
    _ = try expectContains(ll_output, "context.tryExplicitRecovery(scope.id, scope.target, scope.points)");
    try expectNotContains(ll_output, "llRecoveryOffset");

    const lr_output = try generateParserAlloc(arena.allocator(), source, .lr, options);
    _ = try expectContains(lr_output, "pub const is_error_recovery_enabled = true;");
    _ = try expectContains(lr_output, "pub const error_recovery_mode: ErrorRecoveryMode = .explicit;");
    _ = try expectContains(lr_output, "const ExplicitRecoveryScope = struct");
    _ = try expectContains(lr_output, "context.tryExplicitRecovery(scope.id, scope.target, scope.points)");
    try expectNotContains(lr_output, "lrRecoveryOffset");
}

test "LL syntax error recovery tail calls have a portable fallback" {
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
        .with_error_recovery = true,
    });
    const no_ast_terminal = try generatedFunction(no_ast_output, "inline fn parse_terminal_a(");
    _ = try expectContains(no_ast_terminal, "builtin.zig_backend == .stage2_llvm or builtin.zig_backend == .stage2_aarch64");
    _ = try expectContains(no_ast_terminal, "return @call(.always_tail, ll_syntax_error_");
    _ = try expectContains(no_ast_terminal, "return ll_syntax_error_");

    const terminal_ast_output = try generateParserAlloc(arena.allocator(), source, .ll, .{
        .with_ast = true,
        .with_procedures = false,
        .with_error_recovery = true,
        .ast_for_terminals = true,
    });
    const terminal_ast_parser = try generatedFunction(terminal_ast_output, "inline fn parse_terminal_a(");
    try expectNotContains(terminal_ast_parser, "@call(.always_tail");
    _ = try expectContains(terminal_ast_parser, "return ll_syntax_error_");
}
