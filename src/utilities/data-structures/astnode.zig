const builtin = @import("builtin");
const std = @import("std");

pub fn ASTNode(comptime PayloadType: type) type {
    return struct {
        label: []const u8,
        text: []const u8,
        variable: ?u16,

        right_hand_side_children: []const ?*Self,

        children: []*Self,
        parent: ?*Self = null,
        prior: ?*Self = null,
        next: ?*Self = null,

        payload: PayloadType,

        const Self = @This();

        const Iterator = struct {
            current: ?*Self,
            counter: usize = std.math.maxInt(usize),

            pub fn next(self: *Iterator) ?*Self {
                if (self.current) |item| {
                    if (self.counter == std.math.maxInt(usize))
                        self.counter = 0
                    else
                        self.counter += 1;
                    self.current = item.next;
                    return item;
                }
                return null;
            }
        };

        const ConstIterator = struct {
            current: ?*const Self,

            pub fn next(self: *ConstIterator) ?*const Self {
                if (self.current) |item| {
                    self.current = item.next;
                    return item;
                }
                return null;
            }
        };

        /// Pre-order depth-first traversal, calling `visitor` on each node.
        pub fn traverse(self: *Self, visitor: *const fn (node: *Self) void) void {
            visitor(self);
            for (self.children) |child| {
                child.traverse(visitor);
            }
        }

        fn getChainInfo(first_node: *Self) struct { last_node: *Self, count: usize } {
            var current_node: ?*Self = first_node;
            var last_node: *Self = first_node;
            var count: usize = 0;

            while (current_node) |node| {
                last_node = node;
                current_node = node.next;
                count += 1;
            }
            return .{ .last_node = last_node, .count = count };
        }

        /// Insert `first_node` (and any chain attached via `.next`) immediately before `self`.
        /// The inserted nodes must be detached orphans (no parent, no prior).
        pub fn insert_before(self: *Self, allocator: std.mem.Allocator, first_node: *Self) !void {
            // Strict contract: Inserted nodes must already be detached orphans
            std.debug.assert(first_node.parent == null);
            std.debug.assert(first_node.prior == null);

            const chain = getChainInfo(first_node);

            // 1. Unconditionally wire siblings
            first_node.prior = self.prior;
            chain.last_node.next = self;
            if (self.prior) |prior_node| {
                prior_node.next = first_node;
            }
            self.prior = chain.last_node;

            // 2. Conditionally update parent array
            if (self.parent) |parent_node| {
                const old_children = parent_node.children;
                const self_index = std.mem.findScalar(*Self, old_children, self) orelse unreachable;

                const new_children = try allocator.alloc(*Self, old_children.len + chain.count);

                // Cache-friendly bulk splice
                @memcpy(new_children[0..self_index], old_children[0..self_index]);

                var current: ?*Self = first_node;
                var i: usize = 0;
                while (current) |node| : (i += 1) {
                    node.parent = parent_node; // Set parent pointer
                    new_children[self_index + i] = node;
                    if (node == chain.last_node) break;
                    current = node.next;
                }

                @memcpy(new_children[self_index + chain.count ..], old_children[self_index..]);

                parent_node.children = new_children;
                // allocator.free(old_children);
            }
        }

        /// Insert `first_node` (and any chain attached via `.next`) immediately after `self`.
        /// The inserted nodes must be detached orphans (no parent, no prior).
        pub fn insert_after(self: *Self, allocator: std.mem.Allocator, first_node: *Self) !void {
            std.debug.assert(first_node.parent == null);
            std.debug.assert(first_node.prior == null);

            const chain = getChainInfo(first_node);

            // 1. Unconditionally wire siblings
            first_node.prior = self;
            chain.last_node.next = self.next;
            if (self.next) |next_node| {
                next_node.prior = chain.last_node;
            }
            self.next = first_node;

            // 2. Conditionally update parent array
            if (self.parent) |parent_node| {
                const old_children = parent_node.children;
                const self_index = std.mem.findScalar(*Self, old_children, self) orelse unreachable;
                const insert_index = self_index + 1; // Offset by 1 for insert_after

                const new_children = try allocator.alloc(*Self, old_children.len + chain.count);

                @memcpy(new_children[0..insert_index], old_children[0..insert_index]);

                var current: ?*Self = first_node;
                var i: usize = 0;
                while (current) |node| : (i += 1) {
                    node.parent = parent_node;
                    new_children[insert_index + i] = node;
                    if (node == chain.last_node) break;
                    current = node.next;
                }

                @memcpy(new_children[insert_index + chain.count ..], old_children[insert_index..]);

                parent_node.children = new_children;
                // allocator.free(old_children);
            }
        }

        /// Insert `first_node` (and any chain) into `self.children` at position `index`.
        /// The inserted nodes must be detached orphans (no parent, no prior).
        pub fn insert_children(self: *Self, allocator: std.mem.Allocator, index: usize, first_node: *Self) !void {
            std.debug.assert(first_node.parent == null);
            std.debug.assert(first_node.prior == null);
            std.debug.assert(index <= self.children.len);

            const chain = getChainInfo(first_node);
            const old_children = self.children;

            // 1. Wire siblings internally based on index
            const prior_node: ?*Self = if (index > 0) old_children[index - 1] else null;
            const next_node: ?*Self = if (index < old_children.len) old_children[index] else null;

            first_node.prior = prior_node;
            if (prior_node) |p| p.next = first_node;

            chain.last_node.next = next_node;
            if (next_node) |n| n.prior = chain.last_node;

            // 2. Splice parent array
            const new_children = try allocator.alloc(*Self, old_children.len + chain.count);

            @memcpy(new_children[0..index], old_children[0..index]);

            var current: ?*Self = first_node;
            var i: usize = 0;
            while (current) |node| : (i += 1) {
                node.parent = self;
                new_children[index + i] = node;
                if (node == chain.last_node) break;
                current = node.next;
            }

            @memcpy(new_children[index + chain.count ..], old_children[index..]);

            self.children = new_children;
            // Only free if old_children was heap-allocated (len > 0 guarantees it came from
            // a previous alloc call, since we never call free on the initial empty sentinel).
            // if (old_children.len > 0) allocator.free(old_children);
        }

        /// Append `first_node` (and any chain) to `self.children` in the end.
        /// The appended nodes must be detached orphans (no parent, no prior).
        pub fn append_children(self: *Self, allocator: std.mem.Allocator, first_node: *Self) !void {
            try self.insert_children(allocator, self.children.len, first_node);
        }

        /// Remove `count` consecutive siblings starting at `self`, detaching them from parent
        /// and sibling chains. Returns a caller-owned slice of the removed nodes.
        pub fn remove(self: *Self, allocator: std.mem.Allocator, count: usize) ![]*Self {
            if (count == 0) {
                return &[0]*Self{};
            }

            var last_removed = self;
            var i: usize = 1;
            while (i < count) : (i += 1) {
                last_removed = last_removed.next orelse return error.CountExceedsRemainingSiblings;
            }

            const prior_node = self.prior;
            const next_node = last_removed.next;

            if (prior_node) |p| p.next = next_node;
            if (next_node) |n| n.prior = prior_node;

            self.prior = null;
            last_removed.next = null;

            const removed_items = try allocator.alloc(*Self, count);

            if (self.parent) |parent_node| {
                const old_children = parent_node.children;
                const start_index = std.mem.findScalar(*Self, old_children, self) orelse unreachable;

                // Extract to the return slice
                @memcpy(removed_items, old_children[start_index .. start_index + count]);

                const new_children = try allocator.alloc(*Self, old_children.len - count);
                @memcpy(new_children[0..start_index], old_children[0..start_index]);
                @memcpy(new_children[start_index..], old_children[start_index + count ..]);

                parent_node.children = new_children;
            } else {
                var current: ?*Self = self;
                var idx: usize = 0;
                while (current) |node| : (idx += 1) {
                    removed_items[idx] = node;
                    if (node == last_removed) break;
                    current = node.next;
                }
            }

            for (removed_items) |node| {
                node.parent = null;
            }

            return removed_items;
        }

        /// Remove `self`, detaching from parent and sibling chains.
        /// Returns a caller-owned pointer of the removed node.
        pub fn remove_self(self: *Self, allocator: std.mem.Allocator) !*Self {
            return (try self.remove(allocator, 1))[0];
        }

        /// Remove `count` consecutive children starting at `index`, detaching them from parent
        /// and sibling chains. Returns a caller-owned slice of the removed nodes.
        pub fn remove_children(self: *Self, allocator: std.mem.Allocator, index: usize, count: usize) ![]*Self {
            if (count == 0) {
                return &[0]*Self{};
            }
            std.debug.assert(index + count <= self.children.len);

            const old_children = self.children;
            const first_removed = old_children[index];
            const last_removed = old_children[index + count - 1];

            const prior_node: ?*Self = if (index > 0) old_children[index - 1] else null;
            const next_node: ?*Self = if (index + count < old_children.len) old_children[index + count] else null;

            if (prior_node) |p| p.next = next_node;
            if (next_node) |n| n.prior = prior_node;

            first_removed.prior = null;
            last_removed.next = null;

            const removed_items = try allocator.alloc(*Self, count);
            @memcpy(removed_items, old_children[index .. index + count]);

            const new_children = try allocator.alloc(*Self, old_children.len - count);
            @memcpy(new_children[0..index], old_children[0..index]);
            @memcpy(new_children[index..], old_children[index + count ..]);

            self.children = new_children;

            for (removed_items) |node| {
                node.parent = null;
            }

            return removed_items;
        }

        /// Remove one child at `index`, detaching it from parent and sibling chains.
        /// Returns a caller-owned pointer to the removed node.
        pub fn remove_child(self: *Self, allocator: std.mem.Allocator, index: usize) !*Self {
            return (try self.remove_children(allocator, index, 1))[0];
        }

        /// Clean all children detaching them from parent and sibling chains.
        /// Returns a caller-owned slice of the removed nodes.
        pub fn clean_children(self: *Self, allocator: std.mem.Allocator) ![]*Self {
            return try self.remove_children(allocator, 0, self.children.len);
        }

        pub fn augmented_back_length(self: Self) usize {
            if (self.prior) |prior| return 1 + prior.augmented_back_length();

            return 0;
        }

        pub fn augmented_length(self: Self) usize {
            return 1 + self.augmented_back_length() + self.augmented_front_length();
        }

        pub fn augmented_front_length(self: Self) usize {
            if (self.next) |next| return 1 + next.augmented_front_length();

            return 0;
        }

        pub fn augmented_text(self: Self, allocator: std.mem.Allocator) ![]const u8 {
            if (self.children.len == 0) {
                return self.text;
            }

            var combined_text = try std.ArrayList(u8).initCapacity(allocator, 256);
            for (self.children) |child| {
                try combined_text.appendSlice(allocator, try child.augmented_text(allocator));
            }
            return combined_text.items;
        }

        pub fn augmented_first(self: *Self) *Self {
            if (self.prior) |prior| {
                return prior.augmented_first();
            }

            return self;
        }

        pub fn iterate_augmented(self: *Self) Iterator {
            return .{
                .current = self.augmented_first(),
            };
        }

        pub fn const_augmented_first(self: *Self) *const Self {
            if (self.prior) |prior| {
                return prior.augmented_first;
            }

            return self;
        }

        pub fn const_iterate_augmented(self: *const Self) ConstIterator {
            return .{
                .current = self.const_augmented_first(),
            };
        }
    };
}

const TestASTNode = ASTNode(void);

test "zero length augmented node" {
    const node: TestASTNode = .{
        .label = "test",
        .text = "-",
        .variable = 0,
        .right_hand_side_children = &[_]?*TestASTNode{},
        .children = &[_]*TestASTNode{},
        .payload = undefined,
    };

    try std.testing.expectEqual(@as(usize, 0), node.augmented_back_length());
    try std.testing.expectEqual(@as(usize, 1), node.augmented_length());
    try std.testing.expectEqual(@as(usize, 0), node.augmented_front_length());
}

test "augmented length" {
    var nodes: [20]TestASTNode = undefined;

    var previous_node: *TestASTNode = undefined;
    for (&nodes, 0..) |*node, index| {
        if (index > 0) {
            previous_node.next = node;
        }
        nodes[index] = .{
            .label = try std.testing.allocator.dupe(u8, "item " ++ &std.fmt.digits2(@intCast(index))),
            .text = "-",
            .variable = 0,
            .children = &[_]*TestASTNode{},
            .right_hand_side_children = &[_]?*TestASTNode{},
            .prior = if (index > 0) previous_node else null,
            .payload = undefined,
        };
        previous_node = node;
    }
    defer {
        // for (&nodes) |node| {
        // std.testing.allocator.free(node.label);
        // }
    }

    for (nodes, 0..) |node, index| {
        try std.testing.expectEqual(@as(usize, index), node.augmented_back_length());
        try std.testing.expectEqual(@as(usize, 20), node.augmented_length());
        try std.testing.expectEqual(@as(usize, 19 - index), node.augmented_front_length());
    }
}

test "augmented iterate" {
    var nodes: [20]TestASTNode = undefined;

    var previous_node: *TestASTNode = undefined;
    for (&nodes, 0..) |*node, index| {
        if (index > 0) {
            previous_node.next = node;
        }
        nodes[index] = .{
            .label = try std.testing.allocator.dupe(u8, "item " ++ &std.fmt.digits2(@intCast(index))),
            .text = "-",
            .variable = 0,
            .right_hand_side_children = &[_]?*TestASTNode{},
            .children = &[_]*TestASTNode{},
            .prior = if (index > 0) previous_node else null,
            .payload = undefined,
        };
        previous_node = node;
    }
    defer {
        // for (&nodes) |node| {
        // std.testing.allocator.free(node.label);
        // }
    }

    var initial_node = nodes[10];
    var iterator = initial_node.iterate_augmented();
    var counter: usize = 0;
    while (iterator.next()) |current| {
        try std.testing.expectEqual(current, &nodes[counter]);
        counter += 1;
    }
}

// ---------------------------------------------------------------------------
// TestContext — shared fixture for tree-manipulation tests
// ---------------------------------------------------------------------------
//
// Tree shape:
//   root
//   ├── item 01  (children: item 05, item 06, item 07)
//   ├── item 02  (children: item 08, item 09, item 10)
//   ├── item 03  (children: item 11, item 12, item 13)
//   └── item 04  (children: item 14, item 15, item 16)
//
// Nodes item 17..item 29 are kept in `free_nodes` for use as fresh orphans.
//
// IMPORTANT: `allocator()` is derived on-demand from `self.arena` to avoid a
// dangling-pointer bug where capturing `arena.allocator()` before the arena is
// moved into the struct would leave the Allocator holding a stale stack pointer.

const TestContext = struct {
    arena: std.heap.ArenaAllocator,
    root: *TestASTNode,
    free_nodes: []*TestASTNode,

    /// Always derive the allocator from the live arena field.
    pub fn allocator(self: *TestContext) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn init() !TestContext {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        // Derive allocator AFTER arena is on the heap (inside the struct below).
        // We use a temporary here only to build the initial data; the struct's
        // `allocator()` method will re-derive it from `self.arena` each call.
        const alloc = arena.allocator();

        var nodes: []*TestASTNode = try alloc.alloc(*TestASTNode, 30);
        var label_buf: [10]u8 = undefined;

        for (nodes, 0..) |_, index| {
            nodes[index] = try alloc.create(TestASTNode);
            const label = try std.fmt.bufPrint(&label_buf, "item {d:0>2}", .{index});
            nodes[index].* = .{
                .label = try alloc.dupe(u8, label),
                .text = "-",
                .variable = 0,
                .right_hand_side_children = &[_]?*TestASTNode{},
                .children = &[_]*TestASTNode{},
                .payload = undefined,
            };
        }

        var counter: usize = 0;

        const root: *TestASTNode = nodes[counter];
        counter += 1;
        root.*.label = "root";

        // Use alloc.dupe so children slices are independently heap-allocated
        // and can be safely freed/replaced by insert_*/remove operations.
        root.*.children = try alloc.dupe(*TestASTNode, nodes[counter .. counter + 4]);
        counter += 4;

        for (0..root.children.len) |index| {
            const child = root.children[index];

            child.parent = root;
            if (index > 0) child.prior = root.children[index - 1];
            if (index < root.children.len - 1) child.next = root.children[index + 1];

            child.children = try alloc.dupe(*TestASTNode, nodes[counter .. counter + 3]);
            counter += 3;

            for (0..child.children.len) |index_| {
                const child_ = child.children[index_];

                child_.parent = child;
                if (index_ > 0) child_.prior = child.children[index_ - 1];
                if (index_ < child.children.len - 1) child_.next = child.children[index_ + 1];
            }
        }

        return TestContext{
            .arena = arena,
            .root = root,
            .free_nodes = nodes[counter..],
        };
    }

    pub fn deinit(self: *TestContext) void {
        self.arena.deinit();
    }
};

fn run_with_context(test_fn: *const fn (*TestContext) anyerror!void) !void {
    var ctx = try TestContext.init();
    defer ctx.deinit();
    try test_fn(&ctx);
}

// ---------------------------------------------------------------------------
// Test: remove
// ---------------------------------------------------------------------------

fn test_remove(ctx: *TestContext) !void {
    const alloc = ctx.allocator();
    const root = ctx.root;

    // Root initially has 4 children: item01..item04
    try std.testing.expectEqual(@as(usize, 4), root.children.len);

    // Remove 2 children starting at index 1 (item02, item03)
    const removed = try root.children[1].remove(alloc, 2);
    // defer alloc.free(removed);

    // Parent now has 2 children: item01, item04
    try std.testing.expectEqual(@as(usize, 2), root.children.len);
    try std.testing.expectEqualStrings("item 01", root.children[0].label);
    try std.testing.expectEqualStrings("item 04", root.children[1].label);

    // Sibling chain updated correctly
    try std.testing.expectEqual(root.children[1], root.children[0].next);
    try std.testing.expectEqual(root.children[0], root.children[1].prior);
    try std.testing.expectEqual(@as(?*TestASTNode, null), root.children[0].prior);
    try std.testing.expectEqual(@as(?*TestASTNode, null), root.children[1].next);

    // Removed nodes are detached orphans
    try std.testing.expectEqual(@as(usize, 2), removed.len);
    try std.testing.expectEqualStrings("item 02", removed[0].label);
    try std.testing.expectEqualStrings("item 03", removed[1].label);
    try std.testing.expectEqual(@as(?*TestASTNode, null), removed[0].parent);
    try std.testing.expectEqual(@as(?*TestASTNode, null), removed[0].prior);
    try std.testing.expectEqual(@as(?*TestASTNode, null), removed[1].parent);
    try std.testing.expectEqual(@as(?*TestASTNode, null), removed[1].next);
}

test "remove" {
    try run_with_context(test_remove);
}

// ---------------------------------------------------------------------------
// Test: insert_before
// ---------------------------------------------------------------------------

fn test_insert_before(ctx: *TestContext) !void {
    const alloc = ctx.allocator();
    const root = ctx.root;

    // Use two free nodes as fresh orphans, linked into a chain
    const new_a = ctx.free_nodes[0];
    const new_b = ctx.free_nodes[1];
    new_a.next = new_b;
    new_b.prior = new_a;

    // Insert the chain before root.children[2] (item03)
    try root.children[2].insert_before(alloc, new_a);

    // Root should now have 6 children: item01, item02, new_a, new_b, item03, item04
    try std.testing.expectEqual(@as(usize, 6), root.children.len);
    try std.testing.expectEqualStrings("item 01", root.children[0].label);
    try std.testing.expectEqualStrings("item 02", root.children[1].label);
    try std.testing.expectEqual(new_a, root.children[2]);
    try std.testing.expectEqual(new_b, root.children[3]);
    try std.testing.expectEqualStrings("item 03", root.children[4].label);
    try std.testing.expectEqualStrings("item 04", root.children[5].label);

    // Parent pointers set
    try std.testing.expectEqual(root, new_a.parent);
    try std.testing.expectEqual(root, new_b.parent);

    // Sibling chain is contiguous
    try std.testing.expectEqual(new_a, root.children[1].next);
    try std.testing.expectEqual(root.children[1], new_a.prior);
    try std.testing.expectEqual(new_b, new_a.next);
    try std.testing.expectEqual(root.children[4], new_b.next);
    try std.testing.expectEqual(new_b, root.children[4].prior);
}

test "insert_before" {
    try run_with_context(test_insert_before);
}

// ---------------------------------------------------------------------------
// Test: insert_after
// ---------------------------------------------------------------------------

fn test_insert_after(ctx: *TestContext) !void {
    const alloc = ctx.allocator();
    const root = ctx.root;

    const new_a = ctx.free_nodes[0];
    const new_b = ctx.free_nodes[1];
    new_a.next = new_b;
    new_b.prior = new_a;

    // Insert chain after root.children[1] (item02)
    try root.children[1].insert_after(alloc, new_a);

    // Root: item01, item02, new_a, new_b, item03, item04
    try std.testing.expectEqual(@as(usize, 6), root.children.len);
    try std.testing.expectEqualStrings("item 02", root.children[1].label);
    try std.testing.expectEqual(new_a, root.children[2]);
    try std.testing.expectEqual(new_b, root.children[3]);
    try std.testing.expectEqualStrings("item 03", root.children[4].label);

    try std.testing.expectEqual(root, new_a.parent);
    try std.testing.expectEqual(root, new_b.parent);

    try std.testing.expectEqual(new_a, root.children[1].next);
    try std.testing.expectEqual(root.children[1], new_a.prior);
    try std.testing.expectEqual(new_b, new_a.next);
    try std.testing.expectEqual(root.children[4], new_b.next);
}

test "insert_after" {
    try run_with_context(test_insert_after);
}

// ---------------------------------------------------------------------------
// Test: insert_children
// ---------------------------------------------------------------------------

fn test_insert_children(ctx: *TestContext) !void {
    const alloc = ctx.allocator();
    const parent = ctx.root.children[0]; // item01, has 3 children

    const new_node = ctx.free_nodes[0];

    // Insert at the beginning (index 0)
    try parent.insert_children(alloc, 0, new_node);

    try std.testing.expectEqual(@as(usize, 4), parent.children.len);
    try std.testing.expectEqual(new_node, parent.children[0]);
    try std.testing.expectEqual(parent, new_node.parent);
    try std.testing.expectEqual(@as(?*TestASTNode, null), new_node.prior);
    try std.testing.expectEqual(parent.children[1], new_node.next);
    try std.testing.expectEqual(new_node, parent.children[1].prior);

    // Insert at the end
    const new_node2 = ctx.free_nodes[1];
    try parent.insert_children(alloc, parent.children.len, new_node2);

    try std.testing.expectEqual(@as(usize, 5), parent.children.len);
    try std.testing.expectEqual(new_node2, parent.children[4]);
    try std.testing.expectEqual(parent, new_node2.parent);
    try std.testing.expectEqual(@as(?*TestASTNode, null), new_node2.next);
    try std.testing.expectEqual(parent.children[3], new_node2.prior);
}

test "insert_children" {
    try run_with_context(test_insert_children);
}

// ---------------------------------------------------------------------------
// Test: augmented_text
// ---------------------------------------------------------------------------

fn test_augmented_text(ctx: *TestContext) !void {
    const alloc = ctx.allocator();
    const root = ctx.root;

    // Leaf nodes return their own text
    const leaf = root.children[0].children[0];
    const leaf_text = try leaf.augmented_text(alloc);
    try std.testing.expectEqualStrings("-", leaf_text);

    // Set distinguishable leaf texts on item01's children
    root.children[0].children[0].text = "A";
    root.children[0].children[1].text = "B";
    root.children[0].children[2].text = "C";

    const combined = try root.children[0].augmented_text(alloc);
    try std.testing.expectEqualStrings("ABC", combined);
}

test "augmented_text" {
    try run_with_context(test_augmented_text);
}

// ---------------------------------------------------------------------------
// Test: remove — error case
// ---------------------------------------------------------------------------

fn test_remove_count_exceeds(ctx: *TestContext) !void {
    const alloc = ctx.allocator();
    // item04 is the last child; asking for 2 beyond it should error
    const result = ctx.root.children[3].remove(alloc, 2);
    try std.testing.expectError(error.CountExceedsRemainingSiblings, result);
}

test "remove count exceeds remaining siblings" {
    try run_with_context(test_remove_count_exceeds);
}
