const std = @import("std");
const common = @import("generator_common");

pub const Entry = struct {
    terminal: []const u8,
    target: usize,
};

/// The target of a blocker entry: bytes a terminal may not be followed by.
/// Never reaches an emitter; the builder resolves it to the next-shorter
/// match, or to a dead end.
pub const blocked_target = std.math.maxInt(usize);

pub const Group = struct {
    heads: std.ArrayList([]const u8) = .empty,
    child: *Node,
    /// Whether every entry below this head is a blocker, so the head is not
    /// something the decision accepts or expects.
    blocked: bool = false,
};

pub const Node = struct {
    entries: []const Entry = &.{},
    step_length: usize = 0,
    fallback: ?usize = null,
    fallback_length: ?usize = null,
    groups: std.ArrayList(Group) = .empty,
    diagnostic: ?usize = null,
    /// Whether the decision accepts `\n`, including through a default target
    /// whose terminals are not heads (see `appendDefault`). The leftover 0x03
    /// of `newline_after_block_end` reads as `\n` exactly where it is
    /// accepted. Null means the heads tell.
    accepts_newline: ?bool = null,

    pub fn isLeaf(self: Node) bool {
        return self.entries.len == 1 and self.entries[0].terminal.len == 0 and self.fallback != null;
    }
};

/// Appends `terminal` as an entry for `target`, followed by one blocker per
/// byte string in `forbidden_followers`: input that continues `terminal`
/// with one of them does not match it, and the decision falls back to the
/// next-shorter match, or reports an error when there is none. Longest match
/// decides this exactly as it decides `=` against `==`.
pub fn appendTerminal(allocator: std.mem.Allocator, entries: *std.ArrayList(Entry), terminal: []const u8, target: usize, forbidden_followers: []const []const u8) !void {
    try entries.append(allocator, .{ .terminal = terminal, .target = target });
    for (forbidden_followers) |follower| {
        try entries.append(allocator, .{ .terminal = try std.mem.concat(allocator, u8, &.{ terminal, follower }), .target = blocked_target });
    }
}

/// Makes `target` the decision's `else`: input that no other entry matches
/// selects it, and the parser that consumes that input next reports any error.
/// Of `target_terminals`, only those another entry's terminal is a proper
/// prefix of stay as entries, so longest match can still choose `target`.
pub fn appendDefault(allocator: std.mem.Allocator, entries: *std.ArrayList(Entry), target_terminals: []const []const u8, target: usize) !void {
    const other_count = entries.items.len;
    for (target_terminals) |terminal| {
        for (entries.items[0..other_count]) |other| {
            if (other.terminal.len < terminal.len and std.mem.startsWith(u8, terminal, other.terminal)) {
                try entries.append(allocator, .{ .terminal = terminal, .target = target });
                break;
            }
        }
    }
    try entries.append(allocator, .{ .terminal = "", .target = target });
}

pub fn build(allocator: std.mem.Allocator, source_entries: []const Entry, reporter: common.ErrorReporter) !*Node {
    try diagnoseEqualBytes(allocator, source_entries, reporter);
    return buildWithInheritedFallback(allocator, source_entries, 0, null, null);
}

/// Rejects identical byte strings bound to different targets. Checking the
/// top-level entries suffices: equal full strings are equal here, and equal
/// suffixes deeper in the tree imply equal full strings. Prefix-related
/// entries differ and pass through to longest-match planning.
fn diagnoseEqualBytes(allocator: std.mem.Allocator, entries: []const Entry, reporter: common.ErrorReporter) !void {
    for (entries, 0..) |lhs, i| {
        for (entries[i + 1 ..]) |rhs| {
            if (lhs.target == rhs.target) continue;
            if (lhs.target == blocked_target or rhs.target == blocked_target) continue;
            if (!std.mem.eql(u8, lhs.terminal, rhs.terminal)) continue;
            var message = std.Io.Writer.Allocating.init(allocator);
            defer message.deinit();
            const writer = &message.writer;
            try writer.print("ambiguous token: byte sequence ", .{});
            try common.emitStringLiteral(writer, lhs.terminal);
            try writer.print(" matches two alternatives with identical bytes and no longest match, so give one side an exception or merge the targets", .{});
            common.reportError(reporter, message.written());
            return error.AmbiguousGrammar;
        }
    }
}

const InheritedFallback = struct {
    target: usize,
    length: usize,
};

/// `inherited` is what a node falls back to when nothing below it matches.
/// `blocked_fallback` is what a blocked terminal falls back to: the match
/// that was inherited where that terminal itself ended.
fn buildWithInheritedFallback(allocator: std.mem.Allocator, source_entries: []const Entry, prefix_length: usize, inherited: ?InheritedFallback, blocked_fallback: ?InheritedFallback) !*Node {
    const node = try allocator.create(Node);
    node.* = .{};

    var entries = std.ArrayList(Entry).empty;
    for (source_entries) |entry| try appendUniqueEntry(&entries, allocator, entry);
    node.entries = try allocator.dupe(Entry, entries.items);

    var non_empty_count: usize = 0;
    var blocked_here = false;
    for (entries.items) |entry| {
        if (entry.terminal.len == 0) {
            if (entry.target == blocked_target) {
                blocked_here = true;
            } else {
                node.fallback = entry.target;
                node.fallback_length = prefix_length;
            }
        } else {
            non_empty_count += 1;
        }
    }
    // A real match here wins over a blocker for the same bytes. Otherwise the
    // terminal is blocked: fall back past it, or end in an error.
    if (blocked_here and node.fallback == null) {
        if (blocked_fallback) |fallback| {
            node.fallback = fallback.target;
            node.fallback_length = fallback.length;
        }
    }
    if (non_empty_count == 0) {
        // A dead end still switches on the byte, so its error names a position.
        if (node.fallback == null and blocked_here) node.step_length = 1;
        return node;
    }

    node.step_length = stepLength(entries.items);
    var heads = std.ArrayList([]const u8).empty;
    for (entries.items) |entry| {
        if (entry.terminal.len == 0) continue;
        const head = entry.terminal[0..node.step_length];
        for (heads.items) |existing| {
            if (std.mem.eql(u8, existing, head)) break;
        } else {
            try heads.append(allocator, head);
        }
    }
    std.mem.sort([]const u8, heads.items, {}, common.headLessThan);

    const own_fallback = blocked_here == false and node.fallback != null;
    const child_inherited: ?InheritedFallback = if (node.fallback) |target|
        .{ .target = target, .length = node.fallback_length.? }
    else
        inherited;
    // Blockers below this node belong to the terminal that ends here, so they
    // escape to what this node inherited.
    const child_blocked: ?InheritedFallback = if (own_fallback) inherited else blocked_fallback;

    for (heads.items) |head| {
        var payload = std.ArrayList(Entry).empty;
        for (entries.items) |entry| {
            if (entry.terminal.len == 0) continue;
            if (!std.mem.eql(u8, entry.terminal[0..node.step_length], head)) continue;
            try appendUniqueEntry(&payload, allocator, .{
                .terminal = entry.terminal[node.step_length..],
                .target = entry.target,
            });
        }
        std.mem.sort(Entry, payload.items, {}, entryLessThan);

        for (node.groups.items) |*group| {
            if (!entriesEqualPayload(group.child, payload.items)) continue;
            try group.heads.append(allocator, head);
            break;
        } else {
            var all_blocked = true;
            for (payload.items) |entry| {
                if (entry.target != blocked_target) all_blocked = false;
            }
            var group = Group{
                .child = try buildWithInheritedFallback(allocator, payload.items, prefix_length + node.step_length, child_inherited, child_blocked),
                .blocked = all_blocked,
            };
            try group.heads.append(allocator, head);
            try node.groups.append(allocator, group);
        }
    }

    if (node.fallback == null) {
        if (inherited) |fallback| {
            node.fallback = fallback.target;
            node.fallback_length = fallback.length;
        }
    }

    for (node.groups.items) |*group| {
        std.mem.sort([]const u8, group.heads.items, {}, common.headLessThan);
    }
    std.mem.sort(Group, node.groups.items, {}, groupLessThan);
    return node;
}

pub fn expectedHeads(allocator: std.mem.Allocator, node: Node) ![]const []const u8 {
    var result = std.ArrayList([]const u8).empty;
    for (node.groups.items) |group| {
        if (group.blocked) continue;
        for (group.heads.items) |head| try result.append(allocator, head);
    }
    std.mem.sort([]const u8, result.items, {}, common.headLessThan);
    return result.toOwnedSlice(allocator);
}

fn appendUniqueEntry(entries: *std.ArrayList(Entry), allocator: std.mem.Allocator, value: Entry) !void {
    for (entries.items) |entry| {
        if (entry.target == value.target and std.mem.eql(u8, entry.terminal, value.terminal)) return;
    }
    try entries.append(allocator, value);
}

fn entryLessThan(_: void, lhs: Entry, rhs: Entry) bool {
    const order = std.mem.order(u8, lhs.terminal, rhs.terminal);
    if (order != .eq) return order == .lt;
    return lhs.target < rhs.target;
}

fn stepLength(entries: []const Entry) usize {
    var result: usize = std.math.maxInt(usize);
    for (entries) |entry| {
        if (entry.terminal.len > 0) result = @min(result, entry.terminal.len);
    }
    // Case values are u128, so a switch compares at most 16 bytes. Longer
    // heads continue in a child node instead of truncating through bytesToInt.
    return @min(result, 16);
}

fn groupLessThan(_: void, lhs: Group, rhs: Group) bool {
    return std.mem.order(u8, lhs.heads.items[0], rhs.heads.items[0]) == .lt;
}

// The historical grouping combines heads whose remaining payloads are equal.
// Reconstruct that payload from a completed child node for comparison.
fn entriesEqualPayload(node: *const Node, entries: []const Entry) bool {
    if (node.entries.len != entries.len) return false;
    for (node.entries, entries) |lhs, rhs| {
        if (lhs.target != rhs.target or !std.mem.eql(u8, lhs.terminal, rhs.terminal)) return false;
    }
    return true;
}

test "switch planning rejects identical bytes with different targets" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // digit vs "1": same byte, different targets. No longest match exists.
    try std.testing.expectError(error.AmbiguousGrammar, build(allocator, &.{
        .{ .terminal = "1", .target = 0 },
        .{ .terminal = "1", .target = 1 },
    }, null));
    // NUL terminal vs EOF: same byte, different targets.
    try std.testing.expectError(error.AmbiguousGrammar, build(allocator, &.{
        .{ .terminal = "\x00", .target = 0 },
        .{ .terminal = "\x00", .target = 1 },
    }, null));
    // Verbatim-style empty match on two targets is the same conflict.
    try std.testing.expectError(error.AmbiguousGrammar, build(allocator, &.{
        .{ .terminal = "", .target = 0 },
        .{ .terminal = "", .target = 1 },
    }, null));
}

test "switch planning keeps identical bytes with one target and prefix families" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Same bytes, same target: dedup, no conflict. Heads with equal
    // payloads still group together.
    const shared = try build(allocator, &.{
        .{ .terminal = "1", .target = 0 },
        .{ .terminal = "1", .target = 0 },
        .{ .terminal = "2", .target = 0 },
    }, null);
    try std.testing.expect(shared.fallback == null);
    try std.testing.expectEqual(@as(usize, 1), shared.groups.items.len);
    try std.testing.expectEqual(@as(usize, 2), shared.groups.items[0].heads.items.len);

    // Prefix family: short terminal is the fallback, continuation is the
    // child group. Deterministic longest-match, not a conflict.
    const prefixed = try build(allocator, &.{
        .{ .terminal = "=", .target = 0 },
        .{ .terminal = "==", .target = 1 },
    }, null);
    try std.testing.expectEqual(@as(?usize, 0), prefixed.groups.items[0].child.fallback);
    try std.testing.expectEqual(@as(usize, 1), prefixed.groups.items[0].child.fallback_length);
}

test "switch planning preserves grouped heads fallback and leaf topology" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const node = try build(allocator, &.{
        .{ .terminal = "ab", .target = 1 },
        .{ .terminal = "ac", .target = 1 },
        .{ .terminal = "", .target = 2 },
    }, null);
    try std.testing.expectEqual(@as(?usize, 2), node.fallback);
    try std.testing.expectEqual(@as(usize, 2), node.step_length);
    try std.testing.expectEqual(@as(usize, 1), node.groups.items.len);
    try std.testing.expectEqual(@as(usize, 2), node.groups.items[0].heads.items.len);
    try std.testing.expectEqualStrings("ab", node.groups.items[0].heads.items[0]);
}

test "switch planning inherits ancestor fallback length" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const node = try build(allocator, &.{
        .{ .terminal = ".", .target = 1 },
        .{ .terminal = "..", .target = 2 },
        .{ .terminal = ".length", .target = 3 },
    }, null);

    // The node below "." holds ["", ".", "length"]; its empty entry is the "." terminal.
    const tail = node.groups.items[0].child;
    try std.testing.expectEqual(@as(?usize, 1), tail.fallback);
    try std.testing.expectEqual(@as(usize, 1), tail.fallback_length);

    // The "l" node holds ["ength"] only. It inherits the "." fallback and its length.
    const l = tail.groups.items[1].child;
    try std.testing.expectEqual(@as(?usize, 1), l.fallback);
    try std.testing.expectEqual(@as(usize, 1), l.fallback_length);

    // The leaf below the "l" node holds the ".length" terminal at its own prefix.
    const length_leaf = l.groups.items[0].child;
    try std.testing.expectEqual(@as(?usize, 3), length_leaf.fallback);
    try std.testing.expectEqual(@as(usize, 7), length_leaf.fallback_length);
}

test "switch planning caps steps at 16 bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Unique 17-byte terminal: root compares the first 16 bytes, the final
    // byte continues in the child.
    const single = try build(allocator, &.{
        .{ .terminal = "abcdefghijklmnopq", .target = 0 },
    }, null);
    try std.testing.expectEqual(@as(usize, 16), single.step_length);
    try std.testing.expectEqual(@as(usize, 16), single.groups.items[0].heads.items[0].len);
    try std.testing.expectEqual(@as(usize, 1), single.groups.items[0].child.step_length);

    // Two 17-byte terminals differing in the first byte stay distinct: with
    // 16-byte heads their case values differ instead of truncating to equal.
    const colliding = try build(allocator, &.{
        .{ .terminal = "A1234567890123456", .target = 0 },
        .{ .terminal = "B1234567890123456", .target = 1 },
    }, null);
    try std.testing.expectEqual(@as(usize, 16), colliding.step_length);
    try std.testing.expectEqual(@as(usize, 2), colliding.groups.items.len);
    const case_a = common.bytesToInt(colliding.groups.items[0].heads.items[0]);
    const case_b = common.bytesToInt(colliding.groups.items[1].heads.items[0]);
    try std.testing.expect(case_a != case_b);

    // Remaining suffixes longer than 16 bytes cap the child step as well.
    const suffixes = try build(allocator, &.{
        .{ .terminal = "Q", .target = 0 },
        .{ .terminal = "Qaaaaaaaaaaaaaaaaa", .target = 1 },
        .{ .terminal = "Qbbbbbbbbbbbbbbbbb", .target = 2 },
    }, null);
    const tail = suffixes.groups.items[0].child;
    try std.testing.expectEqual(@as(usize, 16), tail.step_length);
}

test "a blocked terminal with nothing shorter ends in an error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var entries = std.ArrayList(Entry).empty;
    try appendTerminal(allocator, &entries, "or", 0, &.{ "a", "b" });
    const root = try build(allocator, entries.items, null);

    // "or" is a step; below it the terminal matches, and "a"/"b" are dead ends.
    const after = root.groups.items[0].child;
    try std.testing.expectEqual(@as(?usize, 0), after.fallback);
    try std.testing.expectEqual(@as(usize, 1), after.groups.items.len);
    const blocked = after.groups.items[0];
    try std.testing.expect(blocked.blocked);
    try std.testing.expectEqual(@as(usize, 2), blocked.heads.items.len);
    try std.testing.expectEqual(@as(?usize, null), blocked.child.fallback);
    try std.testing.expect(!blocked.child.isLeaf());
    try std.testing.expectEqual(@as(usize, 1), blocked.child.step_length);

    // A blocked head is not an expected token.
    try std.testing.expectEqual(@as(usize, 0), (try expectedHeads(allocator, after.*)).len);
}

test "a blocked terminal falls back to the next-shorter match" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Target 1 is the identifier byte "o", target 0 the keyword "or".
    var entries = std.ArrayList(Entry).empty;
    try entries.append(allocator, .{ .terminal = "o", .target = 1 });
    try appendTerminal(allocator, &entries, "or", 0, &.{"b"});
    const root = try build(allocator, entries.items, null);

    const after_o = root.groups.items[0].child;
    const after_or = after_o.groups.items[0].child;
    try std.testing.expectEqual(@as(?usize, 0), after_or.fallback);
    const blocked = after_or.groups.items[0];
    try std.testing.expect(blocked.blocked);
    // "orb" is not the keyword: it is "o" followed by more input.
    try std.testing.expectEqual(@as(?usize, 1), blocked.child.fallback);
    try std.testing.expectEqual(@as(?usize, 1), blocked.child.fallback_length);
    try std.testing.expect(blocked.child.isLeaf());
}

test "a longer real terminal wins over a blocker for the same bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var entries = std.ArrayList(Entry).empty;
    try appendTerminal(allocator, &entries, "in", 0, &.{ "t", "x" });
    try entries.append(allocator, .{ .terminal = "int", .target = 1 });
    const root = try build(allocator, entries.items, null);

    const after = root.groups.items[0].child;
    for (after.groups.items) |group| {
        const is_t = std.mem.eql(u8, group.heads.items[0], "t");
        try std.testing.expectEqual(!is_t, group.blocked);
        if (is_t) try std.testing.expectEqual(@as(?usize, 1), group.child.fallback);
    }
}

test "a partial blocker match keeps the terminal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // "or" may not be followed by "==", but "or=" alone is fine.
    var entries = std.ArrayList(Entry).empty;
    try appendTerminal(allocator, &entries, "or", 0, &.{"=="});
    const root = try build(allocator, entries.items, null);

    // The step below "or" compares both bytes at once, so "or=x" matches no
    // head and keeps the terminal; only "or==" is blocked.
    const after = root.groups.items[0].child;
    try std.testing.expectEqual(@as(?usize, 0), after.fallback);
    try std.testing.expectEqual(@as(usize, 2), after.step_length);
    try std.testing.expectEqualStrings("==", after.groups.items[0].heads.items[0]);
    try std.testing.expect(after.groups.items[0].blocked);
}
