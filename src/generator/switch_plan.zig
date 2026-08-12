const std = @import("std");
const common = @import("generator_common");

pub const Entry = struct {
    terminal: []const u8,
    target: usize,
};

pub const Group = struct {
    heads: std.ArrayList([]const u8) = .empty,
    child: *Node,
};

pub const Node = struct {
    entries: []const Entry = &.{},
    step_length: usize = 0,
    fallback: ?usize = null,
    fallback_length: ?usize = null,
    groups: std.ArrayList(Group) = .empty,
    diagnostic: ?usize = null,

    pub fn isLeaf(self: Node) bool {
        return self.entries.len == 1 and self.entries[0].terminal.len == 0;
    }
};

pub fn build(allocator: std.mem.Allocator, source_entries: []const Entry) !*Node {
    return buildWithInheritedFallback(allocator, source_entries, 0, null);
}

const InheritedFallback = struct {
    target: usize,
    length: usize,
};

fn buildWithInheritedFallback(allocator: std.mem.Allocator, source_entries: []const Entry, prefix_length: usize, inherited: ?InheritedFallback) !*Node {
    const node = try allocator.create(Node);
    node.* = .{};

    var entries = std.ArrayList(Entry).empty;
    for (source_entries) |entry| try appendUniqueEntry(&entries, allocator, entry);
    node.entries = try allocator.dupe(Entry, entries.items);

    var non_empty_count: usize = 0;
    for (entries.items) |entry| {
        if (entry.terminal.len == 0) {
            node.fallback = entry.target;
            node.fallback_length = prefix_length;
        } else {
            non_empty_count += 1;
        }
    }
    if (non_empty_count == 0) return node;

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

    const child_inherited: ?InheritedFallback = if (node.fallback) |target|
        .{ .target = target, .length = node.fallback_length.? }
    else
        inherited;

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
            var group = Group{ .child = try buildWithInheritedFallback(allocator, payload.items, prefix_length + node.step_length, child_inherited) };
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
    return result;
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

test "switch planning preserves grouped heads fallback and leaf topology" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const node = try build(allocator, &.{
        .{ .terminal = "ab", .target = 1 },
        .{ .terminal = "ac", .target = 1 },
        .{ .terminal = "", .target = 2 },
    });
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
    });

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
