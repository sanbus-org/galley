//! Published failures: a parse that ran to its end with recorded errors
//! raises, publishes its tree, and keeps the damaged regions as flagged
//! nodes. The same corpus runs under every recovery mode (explicit and
//! automatic, LL and LR, with and without AST construction); the build
//! generates one parser per mode.

const std = @import("std");
const parser = @import("parser-under-test");
const test_options = @import("test-options");

const Node = parser.data_structures.Node;
const Walker = parser.data_structures.TreeWalker;
const ASTAllocator = parser.data_structures.ASTAllocator;

const is_automatic = test_options.automatic;
const is_ll = parser.parser.parser_type == .ll;
const has_ast = parser.parser.is_ast_enabled;

fn ignoreDiagnostic(_: []const u8) void {}

fn newSession(max_errors: usize) !parser.Session {
    return parser.Session.init(std.testing.io, std.testing.allocator, .{
        .syntax_error_reporter = &ignoreDiagnostic,
        .max_errors = max_errors,
    });
}

/// A damaged input, and the offset of the byte that damages it: some flagged
/// node must reach it.
const Damaged = struct { input: []const u8, offset: usize };

/// Inputs every recovery mode recovers from with a root to show for it.
const corpus = [_]Damaged{
    .{ .input = "a=1;b=?;a=2", .offset = 6 },
    .{ .input = "a=?;b=1", .offset = 2 },
    .{ .input = "a=1;?;b=2", .offset = 4 },
    .{ .input = "a=1;b==2;a=2", .offset = 6 },
    .{ .input = "a=1;b=2;a=3;b=1", .offset = 10 },
    .{ .input = "a=1;;b=2", .offset = 4 },
    .{ .input = "a=1;b=1;?=?;a=2", .offset = 8 },
};

/// A published failure: the session raised `SyntaxError` and still serves
/// the tree and its input.
const Tree = struct {
    nodes: *ASTAllocator,
    root: Node.Pointer,
    input: []const u8,
};

fn parseRecovered(session: *parser.Session, input: []const u8) !Tree {
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes(input, null));
    var guard = try session.readCurrent();
    defer guard.deinit();
    const root = guard.result.ast_root orelse return error.MissingAstRoot;
    return .{ .nodes = &session.node_allocator, .root = root, .input = input };
}

/// Every child links back to its parent, sibling links agree in both
/// directions, the counts match, and no node is reached twice. Returns the
/// number of nodes reachable from `root`.
fn expectLinkConsistent(tree: Tree) !usize {
    const nodes = tree.nodes;
    const root_node = nodes.atConst(tree.root);
    try std.testing.expectEqual(Node.invalid_pointer, root_node.parent);
    try std.testing.expectEqual(Node.invalid_pointer, root_node.prior);
    try std.testing.expectEqual(Node.invalid_pointer, root_node.next);

    var seen = try std.DynamicBitSetUnmanaged.initEmpty(std.testing.allocator, nodes.counter);
    defer seen.deinit(std.testing.allocator);
    var pending: std.ArrayList(Node.Pointer) = .empty;
    defer pending.deinit(std.testing.allocator);
    try pending.append(std.testing.allocator, tree.root);
    seen.set(tree.root);
    var reachable: usize = 0;
    while (pending.pop()) |address| {
        reachable += 1;
        const node = nodes.atConst(address);
        var count: u32 = 0;
        var prior: Node.Pointer = Node.invalid_pointer;
        var child = node.first_child;
        while (child != Node.invalid_pointer) : (child = nodes.atConst(child).next) {
            try std.testing.expect(child < nodes.counter);
            try std.testing.expect(!seen.isSet(child));
            seen.set(child);
            const child_node = nodes.atConst(child);
            try std.testing.expectEqual(address, child_node.parent);
            try std.testing.expectEqual(prior, child_node.prior);
            try pending.append(std.testing.allocator, child);
            prior = child;
            count += 1;
        }
        try std.testing.expectEqual(prior, node.last_child);
        try std.testing.expectEqual(count, node.children_count);
    }
    return reachable;
}

/// Source order: siblings never start before the one ahead of them, every
/// span lies inside the input, and a recovered node lies inside its parent.
fn expectInPlace(tree: Tree) !void {
    var walker = Walker.init(tree.nodes, tree.root, .{});
    while (try walker.next()) |step| {
        const node = tree.nodes.atConst(step.address);
        try std.testing.expect(node.text_start + node.text_length <= tree.input.len);
        if (node.prior != Node.invalid_pointer) {
            try std.testing.expect(tree.nodes.atConst(node.prior).text_start <= node.text_start);
        }
        if (node.is_recovered and node.parent != Node.invalid_pointer) {
            const parent = tree.nodes.atConst(node.parent);
            try std.testing.expect(parent.text_start <= node.text_start);
            try std.testing.expect(node.text_start + node.text_length <= parent.text_start + parent.text_length);
        }
    }
}

const Recoveries = struct { count: usize, reaches: bool };

/// How many recovered nodes the tree holds, and whether one of them reaches
/// `offset` (its span includes the offset or ends right at it). The walk
/// step must agree with the node on the flag.
fn recoveredReaching(tree: Tree, offset: usize) !Recoveries {
    var walker = Walker.init(tree.nodes, tree.root, .{});
    var found: Recoveries = .{ .count = 0, .reaches = false };
    while (try walker.next()) |step| {
        const node = tree.nodes.atConst(step.address);
        try std.testing.expectEqual(node.is_recovered, step.is_recovered);
        if (!step.is_recovered) continue;
        found.count += 1;
        if (node.text_start <= offset and offset <= node.text_start + node.text_length) found.reaches = true;
    }
    return found;
}

/// Skipping recovered nodes prunes whole subtrees: nothing it yields is
/// flagged or sits under a flagged node. Returns the number of nodes yielded.
fn expectSkipLeavesUndamaged(tree: Tree) !usize {
    var walker = Walker.init(tree.nodes, tree.root, .{ .skip_recovered_subtrees = true });
    var yielded: usize = 0;
    while (try walker.next()) |step| {
        yielded += 1;
        try std.testing.expect(!step.is_recovered);
        var ancestor = step.address;
        while (ancestor != Node.invalid_pointer) : (ancestor = tree.nodes.atConst(ancestor).parent) {
            try std.testing.expect(!tree.nodes.atConst(ancestor).is_recovered);
        }
    }
    return yielded;
}

fn countNodes(tree: Tree) !usize {
    var walker = Walker.init(tree.nodes, tree.root, .{});
    var count: usize = 0;
    while (try walker.next()) |_| count += 1;
    return count;
}

/// The source text of every childless node with text the skipping walk yields.
fn undamagedLeafTexts(tree: Tree, out: *std.ArrayList([]const u8)) !void {
    var walker = Walker.init(tree.nodes, tree.root, .{ .skip_recovered_subtrees = true });
    while (try walker.next()) |step| {
        const node = tree.nodes.atConst(step.address);
        if (node.first_child != Node.invalid_pointer or node.text_length == 0) continue;
        try out.append(std.testing.allocator, tree.input[node.text_start..][0..node.text_length]);
    }
}

test "recovered trees are link consistent in every recovery mode" {
    if (comptime !has_ast) return;
    for (corpus) |damaged| {
        var session = try newSession(10);
        defer session.deinit();
        const tree = try parseRecovered(&session, damaged.input);

        try std.testing.expectEqual(try countNodes(tree), try expectLinkConsistent(tree));
        try expectInPlace(tree);
        const recovered = try recoveredReaching(tree, damaged.offset);
        try std.testing.expect(recovered.count >= 1);
        try std.testing.expect(recovered.reaches);
        try std.testing.expect(Node.hasRecoveredSubtree(tree.root, tree.nodes));
        try std.testing.expect(!tree.nodes.atConst(tree.root).is_recovered);
    }
}

test "skipping recovered nodes leaves only undamaged nodes" {
    if (comptime !has_ast) return;
    for (corpus) |damaged| {
        var session = try newSession(10);
        defer session.deinit();
        const tree = try parseRecovered(&session, damaged.input);
        const undamaged = try expectSkipLeavesUndamaged(tree);
        try std.testing.expect(undamaged >= 1);
        try std.testing.expect(undamaged < try countNodes(tree));
    }
}

test "explicit recovery keeps exactly the damaged entry" {
    if (comptime !has_ast or is_automatic) return;
    var session = try newSession(10);
    defer session.deinit();
    const tree = try parseRecovered(&session, "a=1;b=?;a=2");

    // The damaged entry `b=?` is the one flagged node, from where it began to
    // where the recovery resumed, before the next `;`.
    var walker = Walker.init(tree.nodes, tree.root, .{});
    var damaged: ?Node.Pointer = null;
    while (try walker.next()) |step| {
        if (!step.is_recovered) continue;
        try std.testing.expectEqual(@as(?Node.Pointer, null), damaged);
        damaged = step.address;
    }
    const entry = tree.nodes.atConst(damaged orelse return error.MissingRecoveredNode);
    try std.testing.expectEqualStrings("Entry", parser.parser.variables[entry.variable]);
    try std.testing.expectEqual(@as(usize, 4), entry.text_start);
    try std.testing.expectEqual(@as(usize, 3), entry.text_length);
    // LL keeps what it parsed of the entry (its key); LR builds no node
    // before a rule completes, so its stand-in has no children.
    try std.testing.expectEqual(@as(u32, if (is_ll) 1 else 0), entry.children_count);
    try std.testing.expectEqualStrings("Entries", parser.parser.variables[tree.nodes.atConst(entry.parent).variable]);

    // Skipping the flagged entry removes its region and nothing else.
    var leaves: std.ArrayList([]const u8) = .empty;
    defer leaves.deinit(std.testing.allocator);
    try undamagedLeafTexts(tree, &leaves);
    try std.testing.expectEqual(@as(usize, 4), leaves.items.len);
    for ([_][]const u8{ "a", "1", "a", "2" }, leaves.items) |want, got| try std.testing.expectEqualStrings(want, got);
}

test "a valid parse after a recovered one carries no recovery mark" {
    if (comptime !has_ast) return;
    var session = try newSession(10);
    defer session.deinit();
    _ = try parseRecovered(&session, "a=1;b=?;a=2");

    const result = try session.parseBytes("a=1;b=2", null);
    var guard = try session.readCurrent();
    defer guard.deinit();
    try std.testing.expectEqual(result.ast_root, guard.result.ast_root);
    const root = guard.result.ast_root orelse return error.MissingAstRoot;
    try std.testing.expect(!Node.hasRecoveredSubtree(root, &session.node_allocator));
}

test "a recovered parse publishes even without a tree" {
    if (comptime has_ast) return;
    var session = try newSession(10);
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes("a=1;b=?;a=2", null));
    var guard = try session.readCurrent();
    defer guard.deinit();
    try std.testing.expectEqual(@as(?Node.Pointer, null), guard.result.ast_root);
}

test "the next parse ends the errored tree's validity" {
    var session = try newSession(10);
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes("a=1;b=?;a=2", null));
    const published = blk: {
        var guard = try session.readCurrent();
        defer guard.deinit();
        break :blk guard.result;
    };

    // Every later parse advances the generation, so a result held across it
    // is refused, and the session serves the new parse's.
    _ = try session.parseBytes("a=1", null);
    try std.testing.expectError(error.StaleParseResult, session.read(published));
    var current = try session.readCurrent();
    current.deinit();
}

test "a parse the recovery gave up on publishes nothing" {
    // One error is the limit, so the first recovery is refused: the parse
    // raises without running to its end, and nothing it built is served.
    var session = try newSession(1);
    defer session.deinit();
    try std.testing.expectError(error.NoParseResult, session.readCurrent());
    _ = try session.parseBytes("a=1", null);
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes("a=1;b=?;a=2", null));
    try std.testing.expectError(error.StaleParseResult, session.readCurrent());

    // Nor does it hand back a lease: there is no result to pair state with.
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytesLeased("a=1;b=?;a=2", null));
}

test "damage at the end of the input recovers only where there is something to resynchronize on" {
    var session = try newSession(10);
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes("a=1;b=2;a=?", null));
    if (is_automatic) {
        var guard = try session.readCurrent();
        guard.deinit();
    } else {
        // Explicit recovery invents no synchronization terminal at the end of
        // the input.
        try std.testing.expectError(error.NoParseResult, session.readCurrent());
    }
}

test "a recovered parse that consumed nothing still raises and reports sane bytes" {
    const inputs = [_][]const u8{ "", "?", "=", ";;", "??" };
    for (inputs) |input| {
        var session = try newSession(10);
        defer session.deinit();
        try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes(input, null));
        if (session.readCurrent()) |guard_value| {
            var guard = guard_value;
            defer guard.deinit();
            try std.testing.expect(guard.result.parsed_bytes <= input.len);
        } else |_| {}
    }
}

test "an LR parse that unwinds to its first state publishes nothing" {
    if (is_ll or !is_automatic) return;
    // Automatic LR pops entries until some state can resume; here none can,
    // the parse gives up, and the tree built so far is not published.
    var session = try newSession(10);
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes("a=[?];b=1", null));
    try std.testing.expectError(error.NoParseResult, session.readCurrent());
}

test "the session knows the length of the input of a published failure" {
    // `parsed_bytes` stops where the parser stopped consuming; hosts retain
    // the whole input of a published failure, whose length the session keeps.
    var session = try newSession(10);
    defer session.deinit();
    for (corpus) |damaged| {
        try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes(damaged.input, null));
        try std.testing.expectEqual(@as(?usize, damaged.input.len), session.input_length);
    }
}

test "a published failure hands back its lease with the error" {
    var session = try newSession(10);
    defer session.deinit();
    var lease = try session.parseBytesLeased("a=1;b=?;a=2", null);
    try std.testing.expectEqual(@as(?parser.ParseFailure, error.SyntaxError), lease.failure);
    if (comptime has_ast) try std.testing.expect(lease.result.ast_root != null);
    // The session stays held until the lease is released.
    try std.testing.expectError(error.SessionInUse, session.readCurrent());
    lease.deinit();
    var guard = try session.readCurrent();
    guard.deinit();

    var valid = try session.parseBytesLeased("a=1;b=2", null);
    defer valid.deinit();
    try std.testing.expectEqual(@as(?parser.ParseFailure, null), valid.failure);
}
