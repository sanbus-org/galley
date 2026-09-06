const std = @import("std");
const parser = @import("parser-under-test");

const Node = parser.data_structures.Node;
const Walker = parser.data_structures.TreeWalker;
const TestAllocator = parser.data_structures.ASTAllocator;

const Visit = struct {
    address: Node.Pointer,
    depth: u32,
};

fn collectRecursive(
    node_allocator: *TestAllocator,
    address: Node.Pointer,
    depth: u32,
    out: *std.ArrayList(Visit),
) !void {
    try out.append(std.testing.allocator, .{ .address = address, .depth = depth });
    var child = node_allocator.at(address).first_child;
    while (child != Node.invalid_pointer) {
        try collectRecursive(node_allocator, child, depth + 1, out);
        child = node_allocator.at(child).next;
    }
}

fn findRoot(session: *parser.Session, name: []const u8) !Node.Pointer {
    var index: usize = 0;
    while (index < session.node_allocator.counter) : (index += 1) {
        const node = session.node_allocator.at(index);
        if (node.variable != Node.invalid_variable and
            std.mem.eql(u8, parser.parser.variables[node.variable], name))
        {
            return @intCast(index);
        }
    }
    return error.MissingAstRoot;
}

test "walker matches hand-rolled recursion on a parsed tree" {
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, "aa", .{});
    defer parsed.deinit();
    const tree_root = parsed.result.ast_root orelse return error.MissingAstRoot;

    var walker = Walker.init(std.testing.allocator, &parsed.session.node_allocator, tree_root, .{});
    defer walker.deinit();
    var walked: std.ArrayList(Visit) = .empty;
    defer walked.deinit(std.testing.allocator);
    while (walker.next()) |step| {
        try walked.append(std.testing.allocator, .{ .address = step.address, .depth = step.depth });
        try std.testing.expect(!step.is_semantic_error);
    }

    var recursive: std.ArrayList(Visit) = .empty;
    defer recursive.deinit(std.testing.allocator);
    try collectRecursive(&parsed.session.node_allocator, tree_root, 0, &recursive);

    try std.testing.expect(walked.items.len > 1);
    try std.testing.expectEqual(recursive.items.len, walked.items.len);
    for (recursive.items, walked.items) |want, got| {
        try std.testing.expectEqual(want.address, got.address);
        try std.testing.expectEqual(want.depth, got.depth);
    }
    try std.testing.expectEqual(tree_root, walked.items[0].address);
    try std.testing.expectEqual(@as(u32, 0), walked.items[0].depth);
    for (walked.items[1..]) |visit| try std.testing.expect(visit.depth >= 1);
}

test "walker yields depths on a nested synthetic tree" {
    var node_allocator = try TestAllocator.initWithCapacity(std.testing.allocator, 8);
    defer node_allocator.deinit(std.testing.allocator);
    // root(0) -> 1 -> 2, 3; 2 -> 4. Pre-order: 0, 1, 2, 4, 3.
    var addresses: [5]Node.Pointer = undefined;
    for (&addresses) |*slot| slot.* = try node_allocator.create(0, 0);
    try Node.appendChildren(addresses[0], &node_allocator, addresses[1]);
    try Node.appendChildren(addresses[1], &node_allocator, addresses[2]);
    try Node.appendChildren(addresses[1], &node_allocator, addresses[3]);
    try Node.appendChildren(addresses[2], &node_allocator, addresses[4]);

    var walker = Walker.init(std.testing.allocator, &node_allocator, addresses[0], .{});
    defer walker.deinit();
    const expected = [_]struct { usize, u32 }{
        .{ 0, 0 }, .{ 1, 1 }, .{ 2, 2 }, .{ 4, 3 }, .{ 3, 2 },
    };
    for (expected) |want| {
        const step = walker.next() orelse return error.TooFewSteps;
        try std.testing.expectEqual(addresses[want[0]], step.address);
        try std.testing.expectEqual(want[1], step.depth);
    }
    try std.testing.expect(walker.next() == null);
}

test "walker skipChildren prunes the yielded subtree" {
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, "aa", .{});
    defer parsed.deinit();
    const tree_root = parsed.result.ast_root orelse return error.MissingAstRoot;

    var full = Walker.init(std.testing.allocator, &parsed.session.node_allocator, tree_root, .{});
    defer full.deinit();
    var total: usize = 0;
    while (full.next()) |_| total += 1;
    try std.testing.expect(total > 1);

    var pruned = Walker.init(std.testing.allocator, &parsed.session.node_allocator, tree_root, .{});
    defer pruned.deinit();
    const first = pruned.next() orelse return error.TooFewSteps;
    try std.testing.expectEqual(tree_root, first.address);
    pruned.skipChildren();
    try std.testing.expect(pruned.next() == null);
}

test "walker flags and prunes semantic error subtrees" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SemanticError, session.parseBytes("bb", null));
    const tree_root = try findRoot(&session, "Start");

    var flagging = Walker.init(std.testing.allocator, &session.node_allocator, tree_root, .{});
    defer flagging.deinit();
    var flagged: usize = 0;
    while (flagging.next()) |step| {
        const node = session.node_allocator.at(step.address);
        if (node.variable == Node.invalid_variable) continue;
        if (std.mem.eql(u8, parser.parser.variables[node.variable], "Item")) {
            try std.testing.expect(step.is_semantic_error);
            flagged += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), flagged);

    var pruning = Walker.init(std.testing.allocator, &session.node_allocator, tree_root, .{
        .skip_semantic_error_subtrees = true,
    });
    defer pruning.deinit();
    var saw_start = false;
    while (pruning.next()) |step| {
        const node = session.node_allocator.at(step.address);
        if (node.variable == Node.invalid_variable) continue;
        const name = parser.parser.variables[node.variable];
        try std.testing.expect(!std.mem.eql(u8, name, "Item"));
        if (std.mem.eql(u8, name, "Start")) saw_start = true;
    }
    try std.testing.expect(saw_start);
}

test "walker visits a childless synthetic root exactly once" {
    var node_allocator = try TestAllocator.initWithCapacity(std.testing.allocator, 2);
    defer node_allocator.deinit(std.testing.allocator);
    const tree_root = try node_allocator.create(0, 0);

    var walker = Walker.init(std.testing.allocator, &node_allocator, tree_root, .{});
    defer walker.deinit();
    const step = walker.next() orelse return error.TooFewSteps;
    try std.testing.expectEqual(tree_root, step.address);
    try std.testing.expectEqual(@as(u32, 0), step.depth);
    try std.testing.expect(walker.next() == null);
}
