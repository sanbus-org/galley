const std = @import("std");
const parser = @import("parser-under-test");

// A flattened variable (`@<`) builds no node: its children join the nearest
// node around it, and its hooks do not run there. The LL and LR grammars
// build the same trees from the same inputs, LL's lists in one loop and LR's
// as one chain, so a list far longer than recursion survives flattens into
// one node either way.

const Node = parser.data_structures.Node;
const has_ast = parser.parser.is_ast_enabled;
const has_procedures = parser.parser.are_procedures_enabled;
const is_explicit = parser.parser.is_error_recovery_enabled and parser.parser.error_recovery_mode == .explicit;

const depth = 100_000;

fn ignoreDiagnostic(_: []const u8) void {}

fn resetProcedures() void {
    if (comptime has_procedures) parser.procedures.reset();
}

fn variableName(nodes: anytype, address: Node.Pointer) []const u8 {
    return parser.parser.variables[nodes.at(address).variable];
}

/// The names of `address`'s children in order, each checked to link back
/// to it.
fn expectChildren(nodes: anytype, address: Node.Pointer, expected: []const []const u8) !void {
    const node = nodes.at(address);
    try std.testing.expectEqual(expected.len, node.children_count);
    var child = node.first_child;
    var previous = Node.invalid_pointer;
    for (expected) |name| {
        try std.testing.expect(child != Node.invalid_pointer);
        try std.testing.expectEqualStrings(name, variableName(nodes, child));
        try std.testing.expectEqual(address, nodes.at(child).parent);
        try std.testing.expectEqual(previous, nodes.at(child).prior);
        previous = child;
        child = nodes.at(child).next;
    }
    try std.testing.expectEqual(Node.invalid_pointer, child);
    try std.testing.expectEqual(previous, node.last_child);
}

fn childAt(nodes: anytype, address: Node.Pointer, index: usize) Node.Pointer {
    var child = nodes.at(address).first_child;
    for (0..index) |_| child = nodes.at(child).next;
    return child;
}

test "flattened lists join the node around them" {
    if (comptime !has_ast) return error.SkipZigTest;
    const input = "[a,b,[c],d];=1+2+3;[]";
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, null, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
    const nodes = &parsed.session.node_allocator;
    const root = parsed.result.ast_root.?;
    try expectChildren(nodes, root, &.{ "Entry", "Entry", "Entry" });

    const array = childAt(nodes, root, 0);
    try expectChildren(nodes, array, &.{"Array"});
    const outer = childAt(nodes, array, 0);
    try expectChildren(nodes, outer, &.{ "Item", "Item", "Item", "Item" });
    try std.testing.expectEqualStrings("[a,b,[c],d]", input[nodes.at(outer).text_start..][0..nodes.at(outer).text_length]);
    const nested = childAt(nodes, childAt(nodes, outer, 2), 0);
    try expectChildren(nodes, nested, &.{"Item"});

    const sum = childAt(nodes, childAt(nodes, root, 1), 0);
    try expectChildren(nodes, sum, &.{ "Number", "Number", "Number" });
    try std.testing.expectEqualStrings("1+2+3", input[nodes.at(sum).text_start..][0..nodes.at(sum).text_length]);

    const empty = childAt(nodes, childAt(nodes, root, 2), 0);
    try expectChildren(nodes, empty, &.{});
}

test "a list far longer than recursion allows flattens into one node" {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try list.append(std.testing.allocator, '[');
    for (0..depth) |index| try list.appendSlice(std.testing.allocator, if (index == 0) "a" else ",a");
    try list.append(std.testing.allocator, ']');

    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, list.items, null, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(list.items.len, parsed.result.parsed_bytes);
    if (comptime !has_ast) return;
    const nodes = &parsed.session.node_allocator;
    const array = childAt(nodes, childAt(nodes, parsed.result.ast_root.?, 0), 0);
    try std.testing.expectEqual(@as(u32, depth), nodes.at(array).children_count);
    // Start, Entry, Array, and an Item and a Word per member: no node for
    // any level of the list.
    try std.testing.expectEqual(@as(usize, 3 + 2 * depth), nodes.counter);
}

test "a variable's hooks run only on its nodes that exist" {
    if (comptime !has_procedures) return error.SkipZigTest;
    resetProcedures();
    const input = "=1+2+3+4";
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, null, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
    try std.testing.expectEqual(@as(usize, 1), parser.procedures.totalCount());
    // With or without AST construction, the Sum takes every term its
    // flattened continuations parsed.
    try std.testing.expectEqual(@as(u32, 4), parser.procedures.lastTotalChildren());
}

test "an error inside a flattened list recovers at the node around it" {
    if (comptime !is_explicit) return error.SkipZigTest;
    const input = "[a,,b];=1";
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .syntax_error_reporter = &ignoreDiagnostic });
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes(input, null));
    {
        var diagnostics_guard = try session.readLatest();
        defer diagnostics_guard.deinit();
        try std.testing.expectEqual(@as(usize, 1), diagnostics_guard.syntaxErrorCount());
        const diagnostic = diagnostics_guard.lastDiagnostic() orelse return error.MissingDiagnostic;
        const syntax = switch (diagnostic) {
            .syntax => |value| value,
            .semantic, .indentation, .hook => return error.ExpectedSyntaxDiagnostic,
        };
        const recovery = syntax.recovery orelse return error.MissingRecoveryContext;
        try std.testing.expectEqualStrings("]", recovery.terminal);
        switch (recovery.target) {
            .lhs_variable => |variable| try std.testing.expectEqualStrings("Array", variable),
            else => return error.WrongRecoveryTarget,
        }
    }
    if (comptime !has_ast) return;
    var tree_guard = try session.readCurrent();
    defer tree_guard.deinit();
    const nodes = &session.node_allocator;
    const root = tree_guard.result.ast_root orelse return error.MissingAstRoot;
    try expectChildren(nodes, root, &.{ "Entry", "Entry" });
    const sum = childAt(nodes, childAt(nodes, root, 1), 0);
    try expectChildren(nodes, sum, &.{"Number"});
}
