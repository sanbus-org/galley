const std = @import("std");
const parser = @import("parser-under-test");
const procedures = parser.procedures;
const Node = parser.data_structures.Node;

fn variableName(address: Node.Pointer, parsed: anytype) []const u8 {
    return parser.parser.variables[parsed.session.node_allocator.at(address).variable];
}

fn expectChildren(parsed: anytype, address: Node.Pointer, expected: []const []const u8) !void {
    const node = parsed.session.node_allocator.at(address);
    try std.testing.expectEqual(@as(u32, @intCast(expected.len)), node.children_count);
    var child = node.first_child;
    var prior: Node.Pointer = Node.invalid_pointer;
    for (expected) |name| {
        try std.testing.expect(child != Node.invalid_pointer);
        try std.testing.expectEqualStrings(name, variableName(child, parsed));
        try std.testing.expectEqual(address, parsed.session.node_allocator.at(child).parent);
        try std.testing.expectEqual(prior, parsed.session.node_allocator.at(child).prior);
        prior = child;
        child = parsed.session.node_allocator.at(child).next;
    }
    try std.testing.expectEqual(Node.invalid_pointer, child);
    try std.testing.expectEqual(prior, node.last_child);
}

fn expectCall(call: procedures.Call, name: []const u8, has_parent: bool, children_count: u32, last_child: ?[]const u8) !void {
    try std.testing.expectEqualStrings(name, parser.parser.variables[call.variable]);
    try std.testing.expectEqual(has_parent, call.has_parent);
    try std.testing.expectEqual(children_count, call.children_count);
    if (last_child) |expected| {
        const variable = call.last_child_variable orelse return error.ExpectedLastChild;
        try std.testing.expectEqualStrings(expected, parser.parser.variables[variable]);
    } else {
        try std.testing.expectEqual(@as(?u16, null), call.last_child_variable);
    }
}

// The wrappers of "(((((x)))))" are the rule function's own wrapper (the first
// "(") plus four wrappers made by the self-repeating loop. The loop's
// outermost wrapper has no parent while its procedures run, as does the rule
// function's wrapper, so a hook that acts only on wrappers with a parent acts
// on the three innermost loop wrappers and leaves the two outer ones alone.

test "self-repeating loop with procedures: dropping inner wrappers keeps every outer procedure and trailing child" {
    procedures.resetTrace();
    const input = "d(((((x)))))";
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, null, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);

    // The base node, the three inner wrappers, then both outer wrappers. Each
    // procedure sees its trailing Close child; a dropped wrapper takes its
    // subtree with it, so the wrapper above starts from no children.
    const calls = procedures.trace();
    try std.testing.expectEqual(@as(usize, 6), calls.len);
    try expectCall(calls[0], "DropChain", false, 0, null);
    try expectCall(calls[1], "DropChain", true, 2, "Close");
    try expectCall(calls[2], "DropChain", true, 1, "Close");
    try expectCall(calls[3], "DropChain", true, 1, "Close");
    try expectCall(calls[4], "DropChain", false, 1, "Close");
    try expectCall(calls[5], "DropChain", false, 2, "Close");

    const start = parsed.result.ast_root orelse return error.MissingAstRoot;
    try expectChildren(&parsed, start, &.{"DropChain"});
    const outer = parsed.session.node_allocator.at(start).first_child;
    try expectChildren(&parsed, outer, &.{ "DropChain", "Close" });
    try expectChildren(&parsed, parsed.session.node_allocator.at(outer).first_child, &.{"Close"});
}

test "self-repeating loop with procedures: replacing inner wrappers keeps every outer procedure and trailing child" {
    procedures.resetTrace();
    const input = "r(((((x)))))";
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, null, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);

    // Each inner wrapper hands its children to the wrapper above it, so the
    // loop's outermost wrapper sees the base node and all four Close children.
    const calls = procedures.trace();
    try std.testing.expectEqual(@as(usize, 6), calls.len);
    try expectCall(calls[0], "ReplaceChain", false, 0, null);
    try expectCall(calls[1], "ReplaceChain", true, 2, "Close");
    try expectCall(calls[2], "ReplaceChain", true, 3, "Close");
    try expectCall(calls[3], "ReplaceChain", true, 4, "Close");
    try expectCall(calls[4], "ReplaceChain", false, 5, "Close");
    try expectCall(calls[5], "ReplaceChain", false, 2, "Close");

    const start = parsed.result.ast_root orelse return error.MissingAstRoot;
    try expectChildren(&parsed, start, &.{"ReplaceChain"});
    const outer = parsed.session.node_allocator.at(start).first_child;
    try expectChildren(&parsed, outer, &.{ "ReplaceChain", "Close" });
    try expectChildren(
        &parsed,
        parsed.session.node_allocator.at(outer).first_child,
        &.{ "ReplaceChain", "Close", "Close", "Close", "Close" },
    );
}

test "self-repeating loop with procedures: a single wrapper is not part of the loop" {
    procedures.resetTrace();
    const input = "r(x)";
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, null, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);

    const calls = procedures.trace();
    try std.testing.expectEqual(@as(usize, 2), calls.len);
    try expectCall(calls[1], "ReplaceChain", false, 2, "Close");

    const start = parsed.result.ast_root orelse return error.MissingAstRoot;
    try expectChildren(&parsed, parsed.session.node_allocator.at(start).first_child, &.{ "ReplaceChain", "Close" });
}
