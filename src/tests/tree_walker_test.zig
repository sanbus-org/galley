const std = @import("std");
const parser = @import("parser-under-test");

const Node = parser.data_structures.Node;
const Walker = parser.data_structures.TreeWalker;
const tree_walker = parser.data_structures.tree_walker;
const walkNext = tree_walker.walkNext;
const TestAllocator = parser.data_structures.ASTAllocator;

const Visit = struct {
    address: Node.Pointer,
    depth: u32,
};

fn newCursor(root_address: Node.Pointer) tree_walker.Cursor {
    return .{
        .generation = 0,
        .root = root_address,
        .current = 0,
        .depth = 0,
        .state = tree_walker.state_not_started,
        .options = 0,
        .flags = 0,
        .structure_version = 0,
    };
}

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
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, "aa", null, .{});
    defer parsed.deinit();
    const tree_root = parsed.result.ast_root orelse return error.MissingAstRoot;

    var walker = Walker.init(&parsed.session.node_allocator, tree_root, .{});
    var walked: std.ArrayList(Visit) = .empty;
    defer walked.deinit(std.testing.allocator);
    while (try walker.next()) |step| {
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
    Node.appendChildren(addresses[0], &node_allocator, addresses[1]);
    Node.appendChildren(addresses[1], &node_allocator, addresses[2]);
    Node.appendChildren(addresses[1], &node_allocator, addresses[3]);
    Node.appendChildren(addresses[2], &node_allocator, addresses[4]);

    var walker = Walker.init(&node_allocator, addresses[0], .{});
    const expected = [_]struct { usize, u32 }{
        .{ 0, 0 }, .{ 1, 1 }, .{ 2, 2 }, .{ 4, 3 }, .{ 3, 2 },
    };
    for (expected) |want| {
        const step = (try walker.next()) orelse return error.TooFewSteps;
        try std.testing.expectEqual(addresses[want[0]], step.address);
        try std.testing.expectEqual(want[1], step.depth);
    }
    try std.testing.expect((try walker.next()) == null);
}

test "walker skipChildren prunes the yielded subtree" {
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, "aa", null, .{});
    defer parsed.deinit();
    const tree_root = parsed.result.ast_root orelse return error.MissingAstRoot;

    var full = Walker.init(&parsed.session.node_allocator, tree_root, .{});
    var total: usize = 0;
    while (try full.next()) |_| total += 1;
    try std.testing.expect(total > 1);

    var pruned = Walker.init(&parsed.session.node_allocator, tree_root, .{});
    const first = (try pruned.next()) orelse return error.TooFewSteps;
    try std.testing.expectEqual(tree_root, first.address);
    pruned.skipChildren();
    try std.testing.expect((try pruned.next()) == null);
}

test "walker skipChildren continues with the next sibling" {
    var node_allocator = try TestAllocator.initWithCapacity(std.testing.allocator, 8);
    defer node_allocator.deinit(std.testing.allocator);
    // root(0) -> 1 -> 2, 3; 2 -> 4. Pre-order: 0, 1, 2, 4, 3.
    var addresses: [5]Node.Pointer = undefined;
    for (&addresses) |*slot| slot.* = try node_allocator.create(0, 0);
    Node.appendChildren(addresses[0], &node_allocator, addresses[1]);
    Node.appendChildren(addresses[1], &node_allocator, addresses[2]);
    Node.appendChildren(addresses[1], &node_allocator, addresses[3]);
    Node.appendChildren(addresses[2], &node_allocator, addresses[4]);

    var walker = Walker.init(&node_allocator, addresses[0], .{});
    var visited: std.ArrayList(Visit) = .empty;
    defer visited.deinit(std.testing.allocator);
    while (try walker.next()) |step| {
        if (step.address == addresses[2]) walker.skipChildren();
        try visited.append(std.testing.allocator, .{ .address = step.address, .depth = step.depth });
    }

    const want = [_]struct { usize, u32 }{
        .{ 0, 0 }, .{ 1, 1 }, .{ 2, 2 }, .{ 3, 2 },
    };
    try std.testing.expectEqual(want.len, visited.items.len);
    for (want, visited.items) |expected, got| {
        try std.testing.expectEqual(addresses[expected[0]], got.address);
        try std.testing.expectEqual(expected[1], got.depth);
    }
}

test "walker flags and prunes semantic error subtrees" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SemanticError, session.parseBytes("bb", null));
    const tree_root = try findRoot(&session, "Start");

    var flagging = Walker.init(&session.node_allocator, tree_root, .{});
    var flagged: usize = 0;
    while (try flagging.next()) |step| {
        const node = session.node_allocator.at(step.address);
        if (node.variable == Node.invalid_variable) continue;
        if (std.mem.eql(u8, parser.parser.variables[node.variable], "Item")) {
            try std.testing.expect(step.is_semantic_error);
            flagged += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 2), flagged);

    var pruning = Walker.init(&session.node_allocator, tree_root, .{
        .skip_semantic_error_subtrees = true,
    });
    var saw_start = false;
    while (try pruning.next()) |step| {
        const node = session.node_allocator.at(step.address);
        if (node.variable == Node.invalid_variable) continue;
        const name = parser.parser.variables[node.variable];
        try std.testing.expect(!std.mem.eql(u8, name, "Item"));
        if (std.mem.eql(u8, name, "Start")) saw_start = true;
    }
    try std.testing.expect(saw_start);
}

test "walker flags and prunes recovered subtrees independently of semantic errors" {
    var node_allocator = try TestAllocator.initWithCapacity(std.testing.allocator, 8);
    defer node_allocator.deinit(std.testing.allocator);
    // root(0) -> 1 (recovered) -> 2; root -> 3 (semantic error); root -> 4 (both flags).
    var addresses: [5]Node.Pointer = undefined;
    for (&addresses) |*slot| slot.* = try node_allocator.create(0, 0);
    Node.appendChildren(addresses[0], &node_allocator, addresses[1]);
    Node.appendChildren(addresses[1], &node_allocator, addresses[2]);
    Node.appendChildren(addresses[0], &node_allocator, addresses[3]);
    Node.appendChildren(addresses[0], &node_allocator, addresses[4]);
    node_allocator.at(addresses[1]).is_recovered = true;
    node_allocator.at(addresses[3]).is_semantic_error = true;
    node_allocator.at(addresses[4]).is_recovered = true;
    node_allocator.at(addresses[4]).is_semantic_error = true;

    // Without a skip option every node is yielded, each with its own flags.
    var walker = Walker.init(&node_allocator, addresses[0], .{});
    const flags = [_]struct { recovered: bool, semantic: bool }{
        .{ .recovered = false, .semantic = false },
        .{ .recovered = true, .semantic = false },
        .{ .recovered = false, .semantic = false },
        .{ .recovered = false, .semantic = true },
        .{ .recovered = true, .semantic = true },
    };
    for (flags, addresses) |want, address| {
        const step = (try walker.next()) orelse return error.TooFewSteps;
        try std.testing.expectEqual(address, step.address);
        try std.testing.expectEqual(want.recovered, step.is_recovered);
        try std.testing.expectEqual(want.semantic, step.is_semantic_error);
    }
    try std.testing.expect((try walker.next()) == null);

    // Each option prunes only its own nodes; both together keep the rest.
    const cases = [_]struct { Walker.Options, []const usize }{
        .{ .{ .skip_recovered_subtrees = true }, &.{ 0, 3 } },
        .{ .{ .skip_semantic_error_subtrees = true }, &.{ 0, 1, 2 } },
        .{ .{ .skip_recovered_subtrees = true, .skip_semantic_error_subtrees = true }, &.{0} },
    };
    for (cases) |case| {
        var pruning = Walker.init(&node_allocator, addresses[0], case[0]);
        for (case[1]) |index| {
            const step = (try pruning.next()) orelse return error.TooFewSteps;
            try std.testing.expectEqual(addresses[index], step.address);
        }
        try std.testing.expect((try pruning.next()) == null);
    }

    // The cursor carries both flags in its one byte.
    var cursor = newCursor(addresses[0]);
    cursor.options = tree_walker.option_skip_recovered;
    try std.testing.expect(try walkNext(&node_allocator, &cursor));
    try std.testing.expectEqual(@as(u8, 0), cursor.flags);
    cursor = newCursor(addresses[0]);
    try std.testing.expect(try walkNext(&node_allocator, &cursor));
    try std.testing.expect(try walkNext(&node_allocator, &cursor));
    try std.testing.expectEqual(tree_walker.flag_recovered, cursor.flags);
    try std.testing.expect(try walkNext(&node_allocator, &cursor));
    try std.testing.expect(try walkNext(&node_allocator, &cursor));
    try std.testing.expectEqual(tree_walker.flag_semantic_error, cursor.flags);
    try std.testing.expect(try walkNext(&node_allocator, &cursor));
    try std.testing.expectEqual(tree_walker.flag_semantic_error | tree_walker.flag_recovered, cursor.flags);
}

test "walker visits a childless synthetic root exactly once" {
    var node_allocator = try TestAllocator.initWithCapacity(std.testing.allocator, 2);
    defer node_allocator.deinit(std.testing.allocator);
    const tree_root = try node_allocator.create(0, 0);

    var walker = Walker.init(&node_allocator, tree_root, .{});
    const step = (try walker.next()) orelse return error.TooFewSteps;
    try std.testing.expectEqual(tree_root, step.address);
    try std.testing.expectEqual(@as(u32, 0), step.depth);
    try std.testing.expect((try walker.next()) == null);
}

test "walk raises WalkPositionDetached when the current node was removed" {
    var node_allocator = try TestAllocator.initWithCapacity(std.testing.allocator, 8);
    defer node_allocator.deinit(std.testing.allocator);
    // root(0) -> 1, 2: node 1 is a childless first child.
    var addresses: [3]Node.Pointer = undefined;
    for (&addresses) |*slot| slot.* = try node_allocator.create(0, 0);
    Node.appendChildren(addresses[0], &node_allocator, addresses[1]);
    Node.appendChildren(addresses[0], &node_allocator, addresses[2]);

    var cursor = newCursor(addresses[0]);
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // root
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // addresses[1]
    try std.testing.expectEqual(addresses[1], cursor.current);

    Node.removeSelf(addresses[1], &node_allocator);
    try std.testing.expectError(error.WalkPositionDetached, walkNext(&node_allocator, &cursor));
    // The failure is stable: stepping again reports the same detached position.
    try std.testing.expectError(error.WalkPositionDetached, walkNext(&node_allocator, &cursor));
}

test "walk detects a removed interior node with children on the next step" {
    var node_allocator = try TestAllocator.initWithCapacity(std.testing.allocator, 8);
    defer node_allocator.deinit(std.testing.allocator);
    // root(0) -> 1 -> 2, 3: node 1 is yielded with children beneath it.
    var addresses: [4]Node.Pointer = undefined;
    for (&addresses) |*slot| slot.* = try node_allocator.create(0, 0);
    Node.appendChildren(addresses[0], &node_allocator, addresses[1]);
    Node.appendChildren(addresses[1], &node_allocator, addresses[2]);
    Node.appendChildren(addresses[1], &node_allocator, addresses[3]);

    var cursor = newCursor(addresses[0]);
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // root
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // addresses[1]
    try std.testing.expectEqual(addresses[1], cursor.current);

    Node.removeSelf(addresses[1], &node_allocator);
    // The very next step raises instead of descending through the
    // first_child link that removal leaves in place, and the cursor never
    // yields anything of the detached subtree.
    try std.testing.expectError(error.WalkPositionDetached, walkNext(&node_allocator, &cursor));
    try std.testing.expectEqual(addresses[1], cursor.current);
    try std.testing.expectError(error.WalkPositionDetached, walkNext(&node_allocator, &cursor));
    try std.testing.expectEqual(addresses[1], cursor.current);
}

test "a walk rooted at a parentless subtree finishes after the root is attached mid-walk" {
    var node_allocator = try TestAllocator.initWithCapacity(std.testing.allocator, 8);
    defer node_allocator.deinit(std.testing.allocator);
    // subtree root(0) -> a(1) -> b(2); c(3) is a sibling of a. The anchor (4) is an unrelated tree.
    var addresses: [5]Node.Pointer = undefined;
    for (&addresses) |*slot| slot.* = try node_allocator.create(0, 0);
    Node.appendChildren(addresses[0], &node_allocator, addresses[1]);
    Node.appendChildren(addresses[0], &node_allocator, addresses[3]);
    Node.appendChildren(addresses[1], &node_allocator, addresses[2]);

    var cursor = newCursor(addresses[0]);
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // 0
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // 1
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // 2

    // Attach the parentless walk root under another node; attaching moves no walk position.
    const version = node_allocator.structure_version;
    Node.appendChildren(addresses[4], &node_allocator, addresses[0]);
    try std.testing.expectEqual(version, node_allocator.structure_version);

    var walked: std.ArrayList(Node.Pointer) = .empty;
    defer walked.deinit(std.testing.allocator);
    while (try walkNext(&node_allocator, &cursor)) {
        try walked.append(std.testing.allocator, cursor.current);
    }
    // The rest of the walk stays inside the old root: it neither climbs into the new parent nor stops early.
    try std.testing.expectEqualSlices(Node.Pointer, &.{addresses[3]}, walked.items);
    try std.testing.expect(!(try walkNext(&node_allocator, &cursor)));
}

test "walk rejects cursors with unknown state, options, or out-of-range positions" {
    var node_allocator = try TestAllocator.initWithCapacity(std.testing.allocator, 8);
    defer node_allocator.deinit(std.testing.allocator);
    const tree_root = try node_allocator.create(0, 0);

    var cursor = newCursor(tree_root);

    cursor.state = 99;
    try std.testing.expectError(error.InvalidCursor, walkNext(&node_allocator, &cursor));

    cursor.state = tree_walker.state_not_started;
    cursor.options = 0x04;
    try std.testing.expectError(error.InvalidCursor, walkNext(&node_allocator, &cursor));

    cursor.options = 0;
    cursor.root = @as(u64, node_allocator.counter);
    try std.testing.expectError(error.InvalidCursor, walkNext(&node_allocator, &cursor));

    cursor.root = tree_root;
    cursor.state = tree_walker.state_yielded;
    cursor.current = @as(u64, node_allocator.counter);
    try std.testing.expectError(error.InvalidCursor, walkNext(&node_allocator, &cursor));

    // Depth beyond the node count is a malformed position: rejected before
    // `depth + 1` could overflow and before any climb could run away.
    cursor.current = tree_root;
    cursor.depth = @intCast(node_allocator.counter);
    try std.testing.expectError(error.InvalidCursor, walkNext(&node_allocator, &cursor));
    cursor.depth = std.math.maxInt(u32);
    try std.testing.expectError(error.InvalidCursor, walkNext(&node_allocator, &cursor));
    cursor.depth = 0;

    // A done cursor reports completion rather than an error, repeatedly.
    cursor.state = tree_walker.state_done;
    try std.testing.expect(!(try walkNext(&node_allocator, &cursor)));
    try std.testing.expect(!(try walkNext(&node_allocator, &cursor)));
}

test "walk steps see edits made between steps" {
    var node_allocator = try TestAllocator.initWithCapacity(std.testing.allocator, 8);
    defer node_allocator.deinit(std.testing.allocator);
    var addresses: [3]Node.Pointer = undefined;
    for (&addresses) |*slot| slot.* = try node_allocator.create(0, 0);
    Node.appendChildren(addresses[0], &node_allocator, addresses[1]);

    var cursor = newCursor(addresses[0]);
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // root
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // addresses[1]
    try std.testing.expectEqual(addresses[1], cursor.current);

    // A sibling appended between steps joins the walk in place.
    Node.appendChildren(addresses[0], &node_allocator, addresses[2]);
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // addresses[2]
    try std.testing.expectEqual(addresses[2], cursor.current);
    try std.testing.expect(!(try walkNext(&node_allocator, &cursor)));
}

test "walk raises WalkPositionDetached when flattening a wrapper lowers the cursor's depth" {
    var node_allocator = try TestAllocator.initWithCapacity(std.testing.allocator, 8);
    defer node_allocator.deinit(std.testing.allocator);
    // root(0) -> wrapper(1) -> first(2), second(3).
    var addresses: [4]Node.Pointer = undefined;
    for (&addresses) |*slot| slot.* = try node_allocator.create(0, 0);
    Node.appendChildren(addresses[0], &node_allocator, addresses[1]);
    Node.appendChildren(addresses[1], &node_allocator, addresses[2]);
    Node.appendChildren(addresses[1], &node_allocator, addresses[3]);

    var cursor = newCursor(addresses[0]);
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // root
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // wrapper
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // first
    try std.testing.expectEqual(addresses[2], cursor.current);
    try std.testing.expectEqual(@as(u32, 2), cursor.depth);

    // The children now sit directly under the root, one level higher than
    // the cursor believes: the public tier composes the same edit the
    // `@<` flatten makes (detach the children, splice them in, drop the wrapper).
    const children = Node.cleanChildren(addresses[1], &node_allocator);
    Node.insertBefore(addresses[1], &node_allocator, children);
    Node.removeSelf(addresses[1], &node_allocator);
    try std.testing.expectEqual(addresses[2], children);
    try std.testing.expectError(error.WalkPositionDetached, walkNext(&node_allocator, &cursor));
    try std.testing.expectEqual(addresses[2], cursor.current);
}

test "walk detects an ancestor moved under the walk root between steps" {
    var node_allocator = try TestAllocator.initWithCapacity(std.testing.allocator, 8);
    defer node_allocator.deinit(std.testing.allocator);
    // parent(0) -> walk_root(1) -> sibling(2); walk_root(1) -> a(3) -> b(4) -> c(5).
    var addresses: [6]Node.Pointer = undefined;
    for (&addresses) |*slot| slot.* = try node_allocator.create(0, 0);
    const walk_root = addresses[1];
    const sibling = addresses[2];
    const node_a = addresses[3];
    const node_b = addresses[4];
    const node_c = addresses[5];
    Node.appendChildren(addresses[0], &node_allocator, walk_root);
    Node.appendChildren(addresses[0], &node_allocator, sibling);
    Node.appendChildren(walk_root, &node_allocator, node_a);
    Node.appendChildren(node_a, &node_allocator, node_b);
    Node.appendChildren(node_b, &node_allocator, node_c);

    var cursor = newCursor(walk_root);
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // walk_root 0
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // a 1
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // b 2
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // c 3
    try std.testing.expectEqual(@as(u32, 3), cursor.depth);
    try std.testing.expectEqual(node_c, cursor.current);

    // Move b directly under the walk root: the climb from c now passes
    // through the root one level early and would steer the walk onto the
    // root's next sibling. The step raises instead.
    Node.removeSelf(node_b, &node_allocator);
    Node.appendChildren(walk_root, &node_allocator, node_b);
    try std.testing.expectError(error.WalkPositionDetached, walkNext(&node_allocator, &cursor));
    try std.testing.expectEqual(node_c, cursor.current);
    try std.testing.expectError(error.WalkPositionDetached, walkNext(&node_allocator, &cursor));
}

test "walk detects an ancestor moved under a foreign node" {
    var node_allocator = try TestAllocator.initWithCapacity(std.testing.allocator, 8);
    defer node_allocator.deinit(std.testing.allocator);
    // walk_root(0) -> a(1) -> b(2), and a foreign node(3) outside the walk
    // whose children are foreign_before(4) and foreign_after(5).
    var addresses: [6]Node.Pointer = undefined;
    for (&addresses) |*slot| slot.* = try node_allocator.create(0, 0);
    const walk_root = addresses[0];
    const node_a = addresses[1];
    const node_b = addresses[2];
    const foreign = addresses[3];
    const foreign_before = addresses[4];
    const foreign_after = addresses[5];
    Node.appendChildren(walk_root, &node_allocator, node_a);
    Node.appendChildren(node_a, &node_allocator, node_b);
    Node.appendChildren(foreign, &node_allocator, foreign_before);

    var cursor = newCursor(walk_root);
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // walk_root 0
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // a 1
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // b 2

    // Reparent the ancestor a between two foreign children. Without
    // verification the climb from b would step onto a's new next sibling,
    // foreign_after, and yield a node outside the walk; the step raises
    // instead.
    Node.removeSelf(node_a, &node_allocator);
    Node.appendChildren(foreign, &node_allocator, node_a);
    Node.appendChildren(foreign, &node_allocator, foreign_after);
    try std.testing.expectError(error.WalkPositionDetached, walkNext(&node_allocator, &cursor));
    try std.testing.expectEqual(node_b, cursor.current);
    try std.testing.expectError(error.WalkPositionDetached, walkNext(&node_allocator, &cursor));
}

test "walk sees a child inserted under a not-yet-visited node" {
    var node_allocator = try TestAllocator.initWithCapacity(std.testing.allocator, 8);
    defer node_allocator.deinit(std.testing.allocator);
    // walk_root(0) -> first(1), later(2).
    var addresses: [4]Node.Pointer = undefined;
    for (&addresses) |*slot| slot.* = try node_allocator.create(0, 0);
    const walk_root = addresses[0];
    const first = addresses[1];
    const later = addresses[2];
    Node.appendChildren(walk_root, &node_allocator, first);
    Node.appendChildren(walk_root, &node_allocator, later);

    var cursor = newCursor(walk_root);
    try std.testing.expect(try walkNext(&node_allocator, &cursor)); // walk_root

    // An edit the walk has not reached yet: verification passes (the
    // position is unchanged) and the new child appears when reached.
    const inserted = addresses[3];
    Node.appendChildren(later, &node_allocator, inserted);

    var walked: std.ArrayList(Visit) = .empty;
    defer walked.deinit(std.testing.allocator);
    while (try walkNext(&node_allocator, &cursor)) {
        try walked.append(std.testing.allocator, .{ .address = cursor.current, .depth = cursor.depth });
    }
    const expected = [_]struct { usize, u32 }{
        .{ 1, 1 }, .{ 2, 1 }, .{ 3, 2 },
    };
    try std.testing.expectEqual(expected.len, walked.items.len);
    for (expected, walked.items) |want, got| {
        try std.testing.expectEqual(addresses[want[0]], got.address);
        try std.testing.expectEqual(want[1], got.depth);
    }
}

test "a walk with no edits leaves the structure version unchanged and matches recursion" {
    var node_allocator = try TestAllocator.initWithCapacity(std.testing.allocator, 8);
    defer node_allocator.deinit(std.testing.allocator);
    // root(0) -> a(1) -> b(2), c(3).
    var addresses: [4]Node.Pointer = undefined;
    for (&addresses) |*slot| slot.* = try node_allocator.create(0, 0);
    Node.appendChildren(addresses[0], &node_allocator, addresses[1]);
    Node.appendChildren(addresses[0], &node_allocator, addresses[3]);
    Node.appendChildren(addresses[1], &node_allocator, addresses[2]);

    const structure_version = node_allocator.structure_version;

    var cursor = newCursor(addresses[0]);
    var walked: std.ArrayList(Visit) = .empty;
    defer walked.deinit(std.testing.allocator);
    while (try walkNext(&node_allocator, &cursor)) {
        try walked.append(std.testing.allocator, .{ .address = cursor.current, .depth = cursor.depth });
        // No parent write happened, so the stamped version never moves.
        try std.testing.expectEqual(structure_version, cursor.structure_version);
    }
    try std.testing.expectEqual(structure_version, node_allocator.structure_version);

    // The unedited walk matches a recursive first_child/next traversal node
    // for node.
    var recursive: std.ArrayList(Visit) = .empty;
    defer recursive.deinit(std.testing.allocator);
    try collectRecursive(&node_allocator, addresses[0], 0, &recursive);
    try std.testing.expectEqual(recursive.items.len, walked.items.len);
    for (recursive.items, walked.items) |want, got| {
        try std.testing.expectEqual(want.address, got.address);
        try std.testing.expectEqual(want.depth, got.depth);
    }
}

test "walker stepped after the session parses again fails with StaleTree" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    const first = try session.parseBytes("aa", null);
    var walker = Walker.init(&session.node_allocator, first.ast_root orelse return error.MissingAstRoot, .{});
    _ = (try walker.next()) orelse return error.TooFewSteps;

    _ = try session.parseBytes("aa", null);
    const cursor_before = walker.cursor;
    try std.testing.expectError(error.StaleTree, walker.next());
    // A refused step leaves the cursor as it was, so the refusal repeats.
    try std.testing.expectEqual(cursor_before, walker.cursor);
    try std.testing.expectError(error.StaleTree, walker.next());
}

test "walker that had already finished fails with StaleTree after a re-parse" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    const first = try session.parseBytes("aa", null);
    var walker = Walker.init(&session.node_allocator, first.ast_root orelse return error.MissingAstRoot, .{});
    while (try walker.next()) |_| {}
    // A finished walker keeps answering null while its parse is live.
    try std.testing.expect((try walker.next()) == null);

    _ = try session.parseBytes("aa", null);
    try std.testing.expectError(error.StaleTree, walker.next());
}

test "walker that never started fails with StaleTree after a re-parse" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    const first = try session.parseBytes("aa", null);
    var walker = Walker.init(&session.node_allocator, first.ast_root orelse return error.MissingAstRoot, .{});

    try std.testing.expectError(parser.ParseError.SemanticError, session.parseBytes("bb", null));
    try std.testing.expectError(error.StaleTree, walker.next());
}

test "a parse that fails still retires the walkers of the previous tree" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    const first = try session.parseBytes("aa", null);
    var walker = Walker.init(&session.node_allocator, first.ast_root orelse return error.MissingAstRoot, .{});
    _ = (try walker.next()) orelse return error.TooFewSteps;

    if (session.parseBytes("x", null)) |_| return error.ExpectedParseFailure else |_| {}
    try std.testing.expectError(error.StaleTree, walker.next());
}

test "a walker created over the new tree works and the old one stays stale" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    const first = try session.parseBytes("aa", null);
    const first_root = first.ast_root orelse return error.MissingAstRoot;
    var old_walker = Walker.init(&session.node_allocator, first_root, .{});

    const second = try session.parseBytes("aa", null);
    var new_walker = Walker.init(&session.node_allocator, second.ast_root orelse return error.MissingAstRoot, .{});
    var visited: usize = 0;
    while (try new_walker.next()) |_| visited += 1;
    try std.testing.expect(visited > 1);
    try std.testing.expectError(error.StaleTree, old_walker.next());
}

test "raw walkNext refuses a cursor of an earlier parse" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    const first = try session.parseBytes("aa", null);
    var cursor = newCursor(first.ast_root orelse return error.MissingAstRoot);
    cursor.generation = session.node_allocator.generation;
    try std.testing.expect(try walkNext(&session.node_allocator, &cursor));

    _ = try session.parseBytes("aa", null);
    try std.testing.expectError(error.StaleTree, walkNext(&session.node_allocator, &cursor));
    cursor.state = tree_walker.state_done;
    try std.testing.expectError(error.StaleTree, walkNext(&session.node_allocator, &cursor));
}

test "walker storage generation follows the session generation" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    _ = try session.parseBytes("aa", null);
    try std.testing.expectEqual(@as(u64, session.generation), session.node_allocator.generation);
    _ = try session.parseBytes("aa", null);
    try std.testing.expectEqual(@as(u64, session.generation), session.node_allocator.generation);
}

test "a parse that fails before rewinding the storage still retires the walkers of the previous tree" {
    // The non-streaming file path frees the previous input and reads the new
    // one before it prepares node storage, so a read failure leaves the old
    // nodes in place over freed text. The session still considers that tree
    // dead, and so must its walkers.
    if (parser.input_streaming_enabled) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var directory = try tmp.dir.openFile(std.testing.io, ".", .{ .mode = .read_only });
    defer directory.close(std.testing.io);

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    const first = try session.parseBytes("aa", null);
    const node_count = session.node_allocator.counter;
    var walker = Walker.init(&session.node_allocator, first.ast_root orelse return error.MissingAstRoot, .{});
    _ = (try walker.next()) orelse return error.TooFewSteps;

    try std.testing.expectError(error.ReadFailed, session.parseFile(directory, null));
    // The storage was never rewound: only the generation retired the walker.
    try std.testing.expectEqual(node_count, session.node_allocator.counter);
    try std.testing.expectError(error.StaleTree, walker.next());
}

test "a refused parse leaves the walkers of the live tree valid" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    const first = try session.parseBytes("aa", null);
    var walker = Walker.init(&session.node_allocator, first.ast_root orelse return error.MissingAstRoot, .{});
    _ = (try walker.next()) orelse return error.TooFewSteps;

    {
        var guard = try session.readCurrent();
        defer guard.deinit();
        try std.testing.expectError(error.SessionInUse, session.parseBytes("aa", null));
    }
    var visited: usize = 1;
    while (try walker.next()) |_| visited += 1;
    try std.testing.expect(visited > 1);
}
