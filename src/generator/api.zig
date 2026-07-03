const std = @import("std");
const grammar = @import("generator_grammar");
const ll_generator = @import("ll_generator");
const lr_generator = @import("lr_generator");
const common = @import("generator_common");

pub const Grammar = grammar.Grammar;
pub const Rule = grammar.Rule;
pub const RightHandSide = grammar.RightHandSide;
pub const SymbolRef = grammar.SymbolRef;
pub const SymbolKind = grammar.SymbolKind;
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
    return grammar.parse(allocator, source);
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
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const output = try generateParserAlloc(arena.allocator(), source, .ll, .{ .with_procedures = false });
    try std.testing.expect(std.mem.indexOf(u8, output, "pub fn parse") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "parse__AugmentedStart") != null);
}
