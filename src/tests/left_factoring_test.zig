const std = @import("std");
const parser = @import("parser-under-test");
const procedures = parser.procedures;

fn parse(input: []const u8) !void {
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
}

fn expectTrace(expected: []const procedures.Hook) !void {
    const actual = procedures.trace();
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |want, got| try std.testing.expectEqual(want, got);
}

test "factored parser reduces the first shared-prefix alternative" {
    procedures.resetTrace();
    try parse("axend");
    if (parser.parser.parser_type == .ll) {
        // LL merges both Item alternatives into Item -> "a" <spliced tail>:
        // one hook, suffix children attached directly.
        try expectTrace(&.{ .item, .start });
    } else {
        try expectTrace(&.{ .item, .start });
    }
}

test "factored parser reduces the second shared-prefix alternative" {
    procedures.resetTrace();
    try parse("ayend");
    if (parser.parser.parser_type == .ll) {
        try expectTrace(&.{ .item, .start });
    } else {
        try expectTrace(&.{ .item_second, .start });
    }
}

test "factored parser reduces a two-terminal prefix with a longer suffix" {
    procedures.resetTrace();
    try parse("paxend");
    if (parser.parser.parser_type == .ll) {
        try expectTrace(&.{ .pair, .start });
    } else {
        try expectTrace(&.{ .pair, .start });
    }
}

test "factored parser reduces the empty-suffix alternative" {
    procedures.resetTrace();
    try parse("paend");
    if (parser.parser.parser_type == .ll) {
        try expectTrace(&.{ .pair, .start });
    } else {
        try expectTrace(&.{ .pair_second, .start });
    }
}

const Node = parser.data_structures.Node;

/// Asserts the spliced tree shape by position: the root is Start with two
/// children, the first of which (Item/Pair) holds `first_children`
/// terminals. A visible helper node would add one level and one node, so
/// the total count pins the splice: Start + Item/Pair + terminals.
fn expectShape(input: []const u8, first_children: usize, total_nodes: usize) !void {
    if (comptime !parser.parser.is_ast_enabled) return;
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);

    const root = parsed.result.ast_root orelse return error.MissingAstRoot;
    const allocator = &parsed.session.node_allocator;
    try std.testing.expectEqual(@as(u32, 2), allocator.at(root).children_count);

    var count: usize = 0;
    var stack: std.ArrayList(Node.Pointer) = .empty;
    defer stack.deinit(std.testing.allocator);
    try stack.append(std.testing.allocator, root);
    var first: ?Node.Pointer = null;
    while (stack.pop()) |address| {
        count += 1;
        const node = allocator.at(address);
        if (address == root) {
            first = node.first_child;
        }
        var child = node.first_child;
        while (child != Node.invalid_pointer) {
            try stack.append(std.testing.allocator, child);
            child = allocator.at(child).next;
        }
    }
    try std.testing.expectEqual(total_nodes, count);
    try std.testing.expectEqual(@as(u32, @intCast(first_children)), allocator.at(first.?).children_count);
}

test "factored LL and LR trees hold identical spliced children" {
    // Start -> [Item -> ["a", "x"], "end"]: no helper node anywhere.
    try expectShape("axend", 2, 5);
    try expectShape("ayend", 2, 5);
    // Start -> [Pair -> ["p", "a", "x"], "end"].
    try expectShape("paxend", 3, 6);
    // Empty suffix prong: Pair -> ["p", "a"].
    try expectShape("paend", 2, 5);
}
