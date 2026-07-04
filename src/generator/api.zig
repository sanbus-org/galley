const std = @import("std");
const galley_grammar = @import("galley_grammar");
const ll_generator = @import("ll_generator");
const lr_generator = @import("lr_generator");
const common = @import("generator_common");

pub const Grammar = galley_grammar.procedures.Grammar;
pub const Rule = galley_grammar.procedures.Rule;
pub const RightHandSide = galley_grammar.procedures.RightHandSide;
pub const SymbolRef = galley_grammar.procedures.SymbolRef;
pub const SymbolKind = galley_grammar.procedures.SymbolKind;
pub const Options = common.Options;

pub const ParserType = enum {
    ll,
    lr,

    pub fn parse(value: []const u8) ?ParserType {
        if (std.ascii.eqlIgnoreCase(value, "ll")) return .ll;
        if (std.ascii.eqlIgnoreCase(value, "lr")) return .lr;
        return null;
    }
};

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

pub fn emitParserFromSource(
    allocator: std.mem.Allocator,
    source: []const u8,
    writer: *std.Io.Writer,
    parser_type: ParserType,
    options: Options,
) !void {
    const parsed_grammar = try parseGrammar(allocator, source);
    try emitParser(allocator, parsed_grammar, writer, parser_type, options);
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
