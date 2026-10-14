const std = @import("std");
const parser = @import("parser-under-test");

// `"if"@-letter@-digit@-"_"` forbids a name byte right after the keyword. At
// the start of a statement the decision between the keyword form and a name
// then falls back to the name ("iffy"); in the middle of the keyword form
// there is nothing to fall back to, so "else" followed by a name byte is a
// syntax error. The LL and LR grammars build the same trees.

const Node = parser.data_structures.Node;
const has_ast = parser.parser.is_ast_enabled;

fn expectParsed(input: []const u8) !parser.ParsedInput {
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, null, .{});
    errdefer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
    return parsed;
}

fn expectRejected(input: []const u8) !void {
    try std.testing.expectError(
        parser.ParseError.SyntaxError,
        parser.parseBytes(std.testing.io, std.testing.allocator, input, null, .{}),
    );
}

/// The names of the first statement's own children, joined by `/`.
fn firstStatementShape(parsed: *parser.ParsedInput, buffer: []u8) ![]const u8 {
    const nodes = &parsed.session.node_allocator;
    var statement = nodes.at(parsed.result.ast_root.?).first_child;
    while (!std.mem.eql(u8, parser.parser.variables[nodes.at(statement).variable], "Statement")) {
        statement = nodes.at(statement).next;
    }
    var writer = std.Io.Writer.fixed(buffer);
    var child = nodes.at(statement).first_child;
    while (child != Node.invalid_pointer) : (child = nodes.at(child).next) {
        if (nodes.at(child).variable == Node.invalid_variable) continue;
        if (writer.end != 0) try writer.writeAll("/");
        try writer.writeAll(parser.parser.variables[nodes.at(child).variable]);
    }
    return writer.buffered();
}

fn expectFirstStatement(input: []const u8, expected: []const u8) !void {
    var parsed = try expectParsed(input);
    defer parsed.deinit();
    if (comptime !has_ast) return;
    var buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings(expected, try firstStatementShape(&parsed, &buffer));
}

test "a keyword matches when no name byte follows it" {
    try expectFirstStatement("if a else b", "Conditional");
    try expectFirstStatement("if  a  else  b", "Conditional");
    try expectFirstStatement("if a else b;iffy", "Conditional");
}

test "a name that starts with a keyword is a name" {
    try expectFirstStatement("iffy", "Name");
    try expectFirstStatement("if_", "Name");
    try expectFirstStatement("if1", "Name");
    try expectFirstStatement("ifx;if a else b", "Name");
    try expectFirstStatement("i", "Name");
}

test "a keyword with nothing after it is still the keyword" {
    try expectRejected("if");
    try expectRejected("if ");
}

test "a keyword in the middle of a rule rejects a name byte right after it" {
    try expectRejected("if a elsex");
    try expectRejected("if a else_b");
    try expectRejected("if a else1");
    try expectRejected("if a elseb");
}

test "a keyword in the middle of a rule still takes spaces after it" {
    try expectFirstStatement("if a else   b", "Conditional");
}
