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
    groups: std.ArrayList(Group) = .empty,
    diagnostic: ?usize = null,

    pub fn isLeaf(self: Node) bool {
        return self.entries.len == 1 and self.entries[0].terminal.len == 0;
    }
};

pub fn build(allocator: std.mem.Allocator, source_entries: []const Entry) !*Node {
    const node = try allocator.create(Node);
    node.* = .{};

    var entries = std.ArrayList(Entry).empty;
    for (source_entries) |entry| try appendUniqueEntry(&entries, allocator, entry);
    node.entries = try allocator.dupe(Entry, entries.items);

    var non_empty_count: usize = 0;
    for (entries.items) |entry| {
        if (entry.terminal.len == 0) {
            node.fallback = entry.target;
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
            var group = Group{ .child = try build(allocator, payload.items) };
            try group.heads.append(allocator, head);
            try node.groups.append(allocator, group);
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
