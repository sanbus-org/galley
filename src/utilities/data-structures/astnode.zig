const std = @import("std");
const builtin = @import("builtin");
const root = @import("galley");
const Context = root.data_structures.Context;

pub fn ASTAllocator(comptime PayloadType: type) type {
    return struct {
        const ASTNodeType = ASTNode(PayloadType);
        pub const preallocated_nodes = if (root.parser.is_ast_enabled)
            (std.math.maxInt(std.math.Min(root.data_structures.Context.Size, u27)) - 1)
        else
            0;
        const invalid_pointer = preallocated_nodes;
        const default: ASTNodeType = .{
            .text_start = 0,
            .text_length = 0,
            .first_child = invalid_pointer,
            .last_child = invalid_pointer,
            .parent = invalid_pointer,
            .prior = invalid_pointer,
            .next = invalid_pointer,
            .children_count = 0,
            .variable = ASTNodeType.invalid_variable,
            .payload = undefined,
        };

        counter: ASTNodeType.Pointer = 0,
        memory: []ASTNodeType,

        const Self = @This();

        pub fn initCapacity(allocator: std.mem.Allocator) !ASTAllocator(PayloadType) {
            const memory = try allocator.alloc(ASTNodeType, preallocated_nodes + 1);

            @memset(memory, default);

            return .{ .memory = memory };
        }

        pub fn reset(self: *Self) void {
            @memset(self.memory[0..self.counter], default);
            self.counter = 0;
        }

        pub inline fn at(self: *Self, address: ASTNodeType.Pointer) *ASTNodeType {
            return &self.memory[address];
        }

        pub inline fn create(self: *Self, start: Context.Size, variable: u16) ASTNodeType.Pointer {
            const address = self.counter;
            self.counter +%= 1;

            if (comptime builtin.mode == .Debug) {
                if (self.counter >= self.memory.len) {
                    std.debug.print("Ran out of preallocated ast nodes of {d}.\n", .{self.memory.len});
                    unreachable;
                }
            }

            const node = &self.memory[address];
            node.text_start = start;
            node.variable = variable;
            node.payload = .{};
            node.children_count = 0;

            return address;
        }

        pub inline fn terminalNode(terminal: u8) ASTNodeType.Pointer {
            return terminal;
        }

        pub inline fn index(self: *const Self, node: *const ASTNodeType) ASTNodeType.Pointer {
            return @intCast((node - &self.memory[0]) / @sizeOf(ASTNodeType));
        }
    };
}

pub fn ASTNode(comptime PayloadType: type) type {
    return struct {
        pub const Pointer = Context.Size;
        pub const NodeAllocator = *ASTAllocator(PayloadType);
        pub const invalid_pointer: Context.Size = ASTAllocator(PayloadType).invalid_pointer;
        pub const invalid_variable: u16 = std.math.maxInt(u16);

        text_start: Context.Size = 0,
        text_length: Context.Size = 0,

        first_child: Pointer = invalid_pointer,
        last_child: Pointer = invalid_pointer,
        parent: Pointer = invalid_pointer,
        prior: Pointer = invalid_pointer,
        next: Pointer = invalid_pointer,

        children_count: u32 = 0,

        variable: u16 = invalid_variable,
        payload: PayloadType,

        const Self = @This();

        pub fn Iterator(comptime AllocatorType: type) type {
            return struct {
                node_allocator: AllocatorType,
                current: Pointer,

                pub fn next(self: *@This()) ?Self.Pointer {
                    const current_address = self.current;
                    if (current_address == invalid_pointer) {
                        return null;
                    }
                    const item = self.node_allocator.at(current_address);
                    self.current = item.next;
                    return current_address;
                }
            };
        }

        // Find the last node in the chain. This is extremely fast for single nodes (common case).
        fn getLastNode(node_allocator: NodeAllocator, first_node: Pointer) Pointer {
            const first = node_allocator.at(first_node);
            if (first.next != invalid_pointer) {
                var curr = first.next;
                while (node_allocator.at(curr).next != invalid_pointer) {
                    curr = node_allocator.at(curr).next;
                }
                return curr;
            }
            return first_node;
        }

        fn chainLength(node_allocator: NodeAllocator, first_node: Pointer) u32 {
            var count: u32 = 0;
            var curr = first_node;
            while (curr != invalid_pointer) {
                count += 1;
                curr = node_allocator.at(curr).next;
            }
            return count;
        }

        /// Insert `first_node` (and any chain attached via `.next`) immediately before `self_address`.
        /// The inserted nodes must be detached orphans (no parent, no prior).
        pub fn insertBefore(self_address: Pointer, node_allocator: NodeAllocator, first_node: Pointer) !void {
            const self = node_allocator.at(self_address);
            const first = node_allocator.at(first_node);

            if (comptime builtin.mode == .Debug) {
                std.debug.assert(first.parent == invalid_pointer);
                std.debug.assert(first.prior == invalid_pointer);
            }

            const last_node = getLastNode(node_allocator, first_node);
            const last = node_allocator.at(last_node);

            // 1. Wire siblings
            first.prior = self.prior;
            last.next = self_address;
            if (self.prior != invalid_pointer) {
                node_allocator.at(self.prior).next = first_node;
            }
            self.prior = last_node;

            // 2. Conditionally update parent
            if (self.parent != invalid_pointer) {
                const parent_node = node_allocator.at(self.parent);
                // Update parent pointers on all nodes in the inserted chain
                var current = first_node;
                while (true) {
                    const node = node_allocator.at(current);
                    node.parent = self.parent;
                    if (current == last_node) break;
                    current = node.next;
                }

                // Update children count
                parent_node.children_count += Self.chainLength(node_allocator, first_node);

                // If self_address was the first_child of the parent, update first_child to first_node
                if (parent_node.first_child == self_address) {
                    parent_node.first_child = first_node;
                }
            }
        }

        /// Insert `first_node` (and any chain attached via `.next`) immediately after `self_address`.
        /// The inserted nodes must be detached orphans (no parent, no prior).
        pub fn insertAfter(self_address: Pointer, node_allocator: NodeAllocator, first_node: Pointer) !void {
            const self = node_allocator.at(self_address);
            const first = node_allocator.at(first_node);

            if (comptime builtin.mode == .Debug) {
                std.debug.assert(first.parent == invalid_pointer);
                std.debug.assert(first.prior == invalid_pointer);
            }

            const last_node = getLastNode(node_allocator, first_node);
            const last = node_allocator.at(last_node);

            // 1. Wire siblings
            first.prior = self_address;
            last.next = self.next;
            if (self.next != invalid_pointer) {
                node_allocator.at(self.next).prior = last_node;
            }
            self.next = first_node;

            // 2. Conditionally update parent
            if (self.parent != invalid_pointer) {
                const parent_node = node_allocator.at(self.parent);
                // Update parent pointers on all nodes in the inserted chain
                var current = first_node;
                while (true) {
                    const node = node_allocator.at(current);
                    node.parent = self.parent;
                    if (current == last_node) break;
                    current = node.next;
                }

                // Update children count
                parent_node.children_count += Self.chainLength(node_allocator, first_node);

                // If self_address was the last_child of the parent, update last_child to last_node
                if (parent_node.last_child == self_address) {
                    parent_node.last_child = last_node;
                }
            }
        }

        /// Insert `first_node` (and any chain) into `self.children` at position `index`.
        /// The inserted nodes must be detached orphans (no parent, no prior).
        pub fn insertChildren(self_address: Pointer, node_allocator: NodeAllocator, index: usize, first_node: Pointer) !void {
            const self = node_allocator.at(self_address);
            if (comptime builtin.mode == .Debug) {
                std.debug.assert(node_allocator.at(first_node).parent == invalid_pointer);
                std.debug.assert(node_allocator.at(first_node).prior == invalid_pointer);
            }

            if (self.first_child == invalid_pointer) {
                if (comptime builtin.mode == .Debug) {
                    std.debug.assert(index == 0);
                }
                self.first_child = first_node;
                const last_node = getLastNode(node_allocator, first_node);
                self.last_child = last_node;

                // Update parent pointer on the inserted chain
                var current = first_node;
                while (true) {
                    const node = node_allocator.at(current);
                    node.parent = self_address;
                    if (current == last_node) break;
                    current = node.next;
                }

                self.children_count = Self.chainLength(node_allocator, first_node);
            } else {
                if (comptime builtin.mode == .Debug) {
                    // Ensure index is valid
                    var count: usize = 0;
                    var curr = self.first_child;
                    while (curr != invalid_pointer) {
                        count += 1;
                        curr = node_allocator.at(curr).next;
                    }
                    std.debug.assert(index <= count);
                }

                if (index == 0) {
                    try Self.insertBefore(self.first_child, node_allocator, first_node);
                } else {
                    // Traverse to find the child at index - 1
                    var current_child = self.first_child;
                    var i: usize = 0;
                    while (i < index - 1) : (i += 1) {
                        if (current_child != invalid_pointer) {
                            current_child = node_allocator.at(current_child).next;
                        } else {
                            break;
                        }
                    }
                    if (current_child != invalid_pointer) {
                        try Self.insertAfter(current_child, node_allocator, first_node);
                    } else {
                        return error.IndexOutOfBounds;
                    }
                }
            }
        }

        /// Append `first_node` (and any chain) to `self.children` in the end.
        /// The appended nodes must be detached orphans (no parent, no prior).
        pub fn appendChildren(self_address: Pointer, node_allocator: NodeAllocator, first_node: Pointer) !void {
            const self = node_allocator.at(self_address);
            const first = node_allocator.at(first_node);

            if (comptime builtin.mode == .Debug) {
                std.debug.assert(first.parent == invalid_pointer);
                std.debug.assert(first.prior == invalid_pointer);
            }

            const last_node = getLastNode(node_allocator, first_node);

            // Update parent pointers on all nodes in the appended chain
            var current = first_node;
            var added: u32 = 0;
            while (true) {
                const node = node_allocator.at(current);
                node.parent = self_address;
                added += 1;
                if (current == last_node) break;
                current = node.next;
            }

            if (self.last_child != invalid_pointer) {
                const last_addr = self.last_child;
                const last = node_allocator.at(last_addr);
                // Wire siblings
                first.prior = last_addr;
                node_allocator.at(last_node).next = invalid_pointer; // End of list
                last.next = first_node;
                self.last_child = last_node;
            } else {
                // First child in the parent
                self.first_child = first_node;
                self.last_child = last_node;
                first.prior = invalid_pointer;
                node_allocator.at(last_node).next = invalid_pointer;
            }

            self.children_count += added;
        }

        /// Immediately append a single orphan child node to `self_address` with zero overhead.
        /// This assumes the child is a single node (not a chain) and is already an orphan and the parent has no children.
        pub inline fn immediateInsertChild(
            self: *Self,
            self_address: Pointer,
            child_address: Pointer,
            node_allocator: NodeAllocator,
        ) void {
            const child = node_allocator.at(child_address);

            child.parent = self_address;
            child.prior = self.last_child;
            child.next = invalid_pointer;

            if (self.last_child != invalid_pointer) {
                const last_child_node = node_allocator.at(self.last_child);
                last_child_node.next = child_address;
            } else {
                self.first_child = child_address;
            }
            self.last_child = child_address;
            self.children_count += 1;
        }

        /// Immediately append `first_node` (and its .next chain) to the end of children with zero overhead.
        /// Like immediateInsertChild but for a chain. Focuses on performance, assumes the chain nodes
        /// are detached orphans (no parent, no prior), no debug checks.
        pub inline fn immediateAppendChildren(
            self: *Self,
            self_address: Pointer,
            first_node: Pointer,
            node_allocator: NodeAllocator,
        ) void {
            const first = node_allocator.at(first_node);

            var current = first_node;
            var last_node = first_node;
            var added: u32 = 0;
            while (true) {
                const node = node_allocator.at(current);
                node.parent = self_address;
                added += 1;
                last_node = current;
                if (node.next == invalid_pointer) break;
                current = node.next;
            }

            if (self.last_child != invalid_pointer) {
                const last_addr = self.last_child;
                const last = node_allocator.at(last_addr);
                first.prior = last_addr;
                node_allocator.at(last_node).next = invalid_pointer;
                last.next = first_node;
                self.last_child = last_node;
            } else {
                self.first_child = first_node;
                self.last_child = last_node;
                first.prior = invalid_pointer;
                node_allocator.at(last_node).next = invalid_pointer;
            }

            self.children_count += added;
        }

        /// Removes `wrapper_address` from its parent's child/sibling list without touching its children.
        pub fn unlinkWrapper(wrapper_address: Pointer, node_allocator: NodeAllocator) void {
            const wrapper = node_allocator.at(wrapper_address);
            const p = wrapper.prior;
            const nx = wrapper.next;
            const wparent = wrapper.parent;

            if (p != invalid_pointer) {
                node_allocator.at(p).next = nx;
            }
            if (nx != invalid_pointer) {
                node_allocator.at(nx).prior = p;
            }
            if (wparent != invalid_pointer) {
                const wp = node_allocator.at(wparent);
                if (wp.first_child == wrapper_address) wp.first_child = nx;
                if (wp.last_child == wrapper_address) wp.last_child = p;
                wp.children_count -= 1;
            }
        }

        /// Detaches all children from `wrapper_address` and splices them in place of the wrapper among
        /// its siblings. Returns the head of the promoted chain, or `null` when the wrapper has no children.
        pub fn promoteChildrenOverWrapper(wrapper_address: Pointer, node_allocator: NodeAllocator) ?Pointer {
            const wrapper = node_allocator.at(wrapper_address);
            const first = wrapper.first_child;
            if (first == invalid_pointer) return null;
            const last = wrapper.last_child;
            const count = wrapper.children_count;

            wrapper.first_child = invalid_pointer;
            wrapper.last_child = invalid_pointer;
            wrapper.children_count = 0;

            const p = wrapper.prior;
            const nx = wrapper.next;
            const wparent = wrapper.parent;

            if (p != invalid_pointer) {
                node_allocator.at(p).next = nx;
            }
            if (nx != invalid_pointer) {
                node_allocator.at(nx).prior = p;
            }
            if (wparent != invalid_pointer) {
                const wp = node_allocator.at(wparent);
                if (wp.first_child == wrapper_address) wp.first_child = nx;
                if (wp.last_child == wrapper_address) wp.last_child = p;
            }

            node_allocator.at(first).prior = p;
            node_allocator.at(last).next = nx;
            if (p != invalid_pointer) {
                node_allocator.at(p).next = first;
            }
            if (nx != invalid_pointer) {
                node_allocator.at(nx).prior = last;
            }
            if (wparent != invalid_pointer) {
                const wp = node_allocator.at(wparent);
                if (p == invalid_pointer) wp.first_child = first;
                if (nx == invalid_pointer) wp.last_child = last;
                wp.children_count += count - 1;
            }

            var c = first;
            while (true) {
                node_allocator.at(c).parent = wparent;
                if (c == last) break;
                c = node_allocator.at(c).next;
            }

            return first;
        }

        /// Remove `count` consecutive siblings starting at `self_address`, detaching them from parent
        /// and sibling chains. Returns the head of the detached chain, or `invalid_pointer` when `count == 0`.
        pub fn remove(self_address: Pointer, node_allocator: NodeAllocator, count: usize) !Pointer {
            if (count == 0) {
                return invalid_pointer;
            }

            const self = node_allocator.at(self_address);

            var last_removed_address = self_address;
            var i: usize = 1;
            while (i < count) : (i += 1) {
                const last_removed = node_allocator.at(last_removed_address);
                last_removed_address = last_removed.next;
                if (last_removed_address == invalid_pointer) return error.CountExceedsRemainingSiblings;
            }

            const prior_node_address = self.prior;
            const next_node_address = node_allocator.at(last_removed_address).next;

            if (prior_node_address != invalid_pointer) {
                node_allocator.at(prior_node_address).next = next_node_address;
            }
            if (next_node_address != invalid_pointer) {
                node_allocator.at(next_node_address).prior = prior_node_address;
            }

            self.prior = invalid_pointer;
            node_allocator.at(last_removed_address).next = invalid_pointer;

            if (self.parent != invalid_pointer) {
                const parent_node = node_allocator.at(self.parent);

                parent_node.children_count -= @intCast(count);

                // Update parent's first_child and last_child if they were removed
                if (parent_node.first_child == self_address) {
                    parent_node.first_child = next_node_address;
                }
                if (parent_node.last_child == last_removed_address) {
                    parent_node.last_child = prior_node_address;
                }
            }

            var current = self_address;
            while (true) {
                const node = node_allocator.at(current);
                node.parent = invalid_pointer;
                if (current == last_removed_address) break;
                current = node.next;
            }

            return self_address;
        }

        /// Remove `self_address`, detaching from parent and sibling chains.
        /// Returns the removed node address.
        pub fn removeSelf(self_address: Pointer, node_allocator: NodeAllocator) !Pointer {
            return try Self.remove(self_address, node_allocator, 1);
        }

        /// Remove `count` consecutive children starting at `index`, detaching them from parent
        /// and sibling chains. Returns the head of the detached chain, or `invalid_pointer` when `count == 0`.
        pub fn removeChildren(self_address: Pointer, node_allocator: NodeAllocator, index: usize, count: usize) !Pointer {
            const self = node_allocator.at(self_address);
            if (count == 0) {
                return invalid_pointer;
            }

            // Find the child at index
            var current_child = self.first_child;
            var i: usize = 0;
            while (i < index) : (i += 1) {
                if (current_child != invalid_pointer) {
                    current_child = node_allocator.at(current_child).next;
                } else {
                    break;
                }
            }

            if (current_child != invalid_pointer) {
                return try Self.remove(current_child, node_allocator, count);
            } else {
                return error.IndexOutOfBounds;
            }
        }

        /// Remove one child at `index`, detaching it from parent and sibling chains.
        /// Returns the removed node address.
        pub fn removeChild(self_address: Pointer, node_allocator: NodeAllocator, index: usize) !Pointer {
            return try Self.removeChildren(self_address, node_allocator, index, 1);
        }

        /// Clean all children detaching them from parent and sibling chains.
        /// Returns the head of the detached chain, or `invalid_pointer` when there are no children.
        pub fn cleanChildren(self_address: Pointer, node_allocator: NodeAllocator) !Pointer {
            const self = node_allocator.at(self_address);
            const first = self.first_child;
            if (first == invalid_pointer) return invalid_pointer;
            const last = self.last_child;

            self.first_child = invalid_pointer;
            self.last_child = invalid_pointer;
            self.children_count = 0;

            node_allocator.at(first).prior = invalid_pointer;
            node_allocator.at(last).next = invalid_pointer;

            var c = first;
            while (true) {
                node_allocator.at(c).parent = invalid_pointer;
                if (c == last) break;
                c = node_allocator.at(c).next;
            }

            return first;
        }

        pub fn augmentedBackLength(self_address: Pointer, node_allocator: NodeAllocator) usize {
            var count: usize = 0;
            var current = self_address;
            while (current != invalid_pointer) {
                const node = node_allocator.at(current);
                current = node.prior;
                if (current != invalid_pointer) count += 1;
            }
            return count;
        }

        pub fn augmentedLength(self_address: Pointer, node_allocator: NodeAllocator) usize {
            return Self.augmentedBackLength(self_address, node_allocator) +
                1 +
                Self.augmentedFrontLength(self_address, node_allocator);
        }

        pub fn augmentedFrontLength(self_address: Pointer, node_allocator: NodeAllocator) usize {
            var count: usize = 0;
            var current = self_address;
            while (current != invalid_pointer) {
                const node = node_allocator.at(current);
                current = node.next;
                if (current != invalid_pointer) count += 1;
            }
            return count;
        }

        pub fn augmentedText(self_address: Pointer, context: *Context) ![]const u8 {
            const self = context.node_allocator.at(self_address);
            if (self.first_child == invalid_pointer) {
                return context.getTextSlice(self.text_start, self.text_length);
            }

            var combined_text = try std.ArrayList(u8).initCapacity(context.runtime().arena_allocator, 256 * 256);
            var current_child = self.first_child;
            while (current_child != invalid_pointer) {
                try combined_text.appendSlice(context.runtime().arena_allocator, try Self.augmentedText(current_child, context));
                current_child = context.node_allocator.at(current_child).next;
            }
            return combined_text.items;
        }

        pub fn augmentedFirst(self_address: Pointer, node_allocator: NodeAllocator) Pointer {
            if (self_address != invalid_pointer) {
                const self = node_allocator.at(self_address);
                if (self.prior != invalid_pointer) {
                    return Self.augmentedFirst(self.prior, node_allocator);
                }
            }
            return self_address;
        }

        pub fn iterateAugmented(self_address: Pointer, node_allocator: NodeAllocator) Iterator(NodeAllocator) {
            return .{
                .node_allocator = node_allocator,
                .current = Self.augmentedFirst(self_address, node_allocator),
            };
        }
    };
}

// Test types
const TestPayload = root.data_structures.Payload;
const TestASTNode = ASTNode(TestPayload);
const TestASTAllocator = ASTAllocator(TestPayload);

test "zero length augmented node" {
    if (comptime !root.parser.is_ast_enabled) return;
    var node_allocator = try TestASTAllocator.initCapacity(std.testing.allocator);
    defer std.testing.allocator.free(node_allocator.memory);
    const nodes = node_allocator.memory;

    nodes[0] = .{
        .text_start = 0,
        .text_length = 1,
        .payload = .{},
    };

    try std.testing.expectEqual(@as(usize, 0), TestASTNode.augmentedBackLength(0, &node_allocator));
    try std.testing.expectEqual(@as(usize, 1), TestASTNode.augmentedLength(0, &node_allocator));
    try std.testing.expectEqual(@as(usize, 0), TestASTNode.augmentedFrontLength(0, &node_allocator));
}

test "augmented length" {
    if (comptime !root.parser.is_ast_enabled) return;
    var node_allocator = try TestASTAllocator.initCapacity(std.testing.allocator);
    defer std.testing.allocator.free(node_allocator.memory);
    const nodes = node_allocator.memory[0..20];

    for (nodes, 0..) |*node, index| {
        if (index > 0) {
            nodes[index - 1].next = @intCast(index);
        }
        node.* = .{
            .text_start = 0,
            .text_length = 1,
            .prior = if (index > 0) @intCast(index - 1) else TestASTNode.invalid_pointer,
            .payload = .{},
        };
    }

    for (nodes, 0..) |_, index| {
        try std.testing.expectEqual(@as(usize, index), TestASTNode.augmentedBackLength(@intCast(index), &node_allocator));
        try std.testing.expectEqual(@as(usize, 20), TestASTNode.augmentedLength(@intCast(index), &node_allocator));
        try std.testing.expectEqual(@as(usize, 19 - index), TestASTNode.augmentedFrontLength(@intCast(index), &node_allocator));
    }
}

test "augmented iterate" {
    if (comptime !root.parser.is_ast_enabled) return;
    var node_allocator = try TestASTAllocator.initCapacity(std.testing.allocator);
    defer std.testing.allocator.free(node_allocator.memory);
    const nodes = node_allocator.memory[0..20];

    for (nodes, 0..) |*node, index| {
        if (index > 0) {
            nodes[index - 1].next = @intCast(index);
        }
        node.* = .{
            .text_start = 0,
            .text_length = 1,
            .prior = if (index > 0) @intCast(index - 1) else TestASTNode.invalid_pointer,
            .payload = .{},
        };
    }

    const initial_node: Context.Size = 10;
    var iterator = TestASTNode.iterateAugmented(initial_node, &node_allocator);
    var counter: usize = 0;
    while (iterator.next()) |current| {
        try std.testing.expectEqual(@as(Context.Size, @intCast(counter)), current);
        counter += 1;
    }
}

fn testContext(node_allocator: *TestASTAllocator, text: []u8) Context {
    var context = Context{};
    context.node_allocator = node_allocator;
    context.token.reset(text);
    if (comptime root.procedures.indentation_syntax) {
        @memcpy(context.token.buffer[0..text.len], text);
    }
    context.token.head = @intCast(text.len);
    context.token.len = @intCast(text.len);
    return context;
}

const TestFixture = struct {
    arena: std.heap.ArenaAllocator,
    node_allocator: TestASTAllocator,
    text: []u8,
    nodes: []TestASTNode,
    root: Context.Size,
    free_nodes: []Context.Size,

    pub fn allocator(self: *TestFixture) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn getContext(self: *TestFixture) Context {
        return testContext(&self.node_allocator, self.text);
    }

    pub fn init() !TestFixture {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        const alloc = arena.allocator();

        var node_allocator = try TestASTAllocator.initCapacity(alloc);
        node_allocator.counter = 30;
        const nodes = node_allocator.memory;
        for (nodes[0..30]) |*node| {
            node.* = .{
                .text_start = 0,
                .text_length = 0,
                .payload = .{},
            };
        }

        const text = try alloc.dupe(u8, "ABCDEFGHIJKLMNOPQRSTUVWXYZ");

        const root_node: Context.Size = 0;
        nodes[root_node] = .{
            .text_start = 0,
            .text_length = 1,
            .payload = .{},
        };

        // Append root's children (1..4)
        for (1..5) |index| {
            const child_addr: Context.Size = @intCast(index);
            nodes[child_addr] = .{
                .text_start = 0,
                .text_length = 1,
                .payload = .{},
            };
            try TestASTNode.appendChildren(root_node, &node_allocator, child_addr);
        }

        // For each of root's children, append 3 children
        var counter: Context.Size = 5;
        for (1..5) |parent_index| {
            const parent_addr: Context.Size = @intCast(parent_index);
            for (0..3) |_| {
                const child_addr = counter;
                counter += 1;
                nodes[child_addr] = .{
                    .text_start = 0,
                    .text_length = 1,
                    .payload = .{},
                };
                try TestASTNode.appendChildren(parent_addr, &node_allocator, child_addr);
            }
        }

        // Remaining nodes are free nodes (17..29)
        const free_nodes = try alloc.alloc(Context.Size, 30 - counter);
        for (free_nodes, 0..) |*fn_addr, idx| {
            fn_addr.* = counter + @as(Context.Size, @intCast(idx));
            nodes[fn_addr.*] = .{
                .text_start = 0,
                .text_length = 1,
                .payload = .{},
            };
        }

        return TestFixture{
            .arena = arena,
            .node_allocator = node_allocator,
            .text = text,
            .nodes = nodes,
            .root = root_node,
            .free_nodes = free_nodes,
        };
    }

    pub fn deinit(self: *TestFixture) void {
        self.arena.deinit();
    }
};

fn runWithContext(test_fn: *const fn (*TestFixture) anyerror!void) !void {
    var fixture = try TestFixture.init();
    defer fixture.deinit();
    var runtime_context = root.data_structures.RuntimeContext{
        .io = undefined,
        .arena_allocator = fixture.allocator(),
    };
    root.data_structures.context.activateRuntimeContext(&runtime_context);
    defer root.data_structures.context.deactivateRuntimeContext(&runtime_context);
    try test_fn(&fixture);
}

fn testRemove(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    const root_node = fixture.root;

    // Root initially has 4 children (1, 2, 3, 4)
    var count: usize = 0;
    var curr = fixture.nodes[root_node].first_child;
    while (curr != TestASTNode.invalid_pointer) {
        count += 1;
        curr = fixture.nodes[curr].next;
    }
    try std.testing.expectEqual(@as(usize, 4), count);

    // Remove 2 children starting at index 1 (child2 = 2, child3 = 3)
    const removed_head = try TestASTNode.remove(2, node_allocator, 2);

    // Parent (root) now has 2 children: 1, 4
    count = 0;
    curr = fixture.nodes[root_node].first_child;
    while (curr != TestASTNode.invalid_pointer) {
        count += 1;
        curr = fixture.nodes[curr].next;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqual(asSize(1), fixture.nodes[root_node].first_child);
    try std.testing.expectEqual(asSize(4), fixture.nodes[root_node].last_child);

    // Sibling chain updated correctly
    try std.testing.expectEqual(asSize(4), fixture.nodes[1].next);
    try std.testing.expectEqual(asSize(1), fixture.nodes[4].prior);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[1].prior);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[4].next);

    // Removed nodes are detached orphans
    try std.testing.expectEqual(asSize(2), removed_head);
    try std.testing.expectEqual(asSize(3), fixture.nodes[2].next);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[2].parent);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[2].prior);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[3].parent);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[3].next);
}

fn asSize(val: anytype) Context.Size {
    return @intCast(val);
}

test "remove" {
    try runWithContext(testRemove);
}

fn testInsertBefore(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    const root_node = fixture.root;

    // Use two free nodes as fresh orphans, linked into a chain
    const new_a = fixture.free_nodes[0];
    const new_b = fixture.free_nodes[1];
    fixture.nodes[new_a].next = new_b;
    fixture.nodes[new_b].prior = new_a;

    // Insert the chain before root's children[2] (child3 = 3)
    try TestASTNode.insertBefore(3, node_allocator, new_a);

    // Root should now have 6 children: 1, 2, new_a, new_b, 3, 4
    var count: usize = 0;
    var curr = fixture.nodes[root_node].first_child;
    var children_list: [6]Context.Size = undefined;
    while (curr != TestASTNode.invalid_pointer) {
        children_list[count] = curr;
        count += 1;
        curr = fixture.nodes[curr].next;
    }

    try std.testing.expectEqual(@as(usize, 6), count);
    try std.testing.expectEqual(asSize(1), children_list[0]);
    try std.testing.expectEqual(asSize(2), children_list[1]);
    try std.testing.expectEqual(new_a, children_list[2]);
    try std.testing.expectEqual(new_b, children_list[3]);
    try std.testing.expectEqual(asSize(3), children_list[4]);
    try std.testing.expectEqual(asSize(4), children_list[5]);

    // Parent pointers set
    try std.testing.expectEqual(root_node, fixture.nodes[new_a].parent);
    try std.testing.expectEqual(root_node, fixture.nodes[new_b].parent);

    // Sibling chain is contiguous
    try std.testing.expectEqual(new_a, fixture.nodes[2].next);
    try std.testing.expectEqual(asSize(2), fixture.nodes[new_a].prior);
    try std.testing.expectEqual(new_b, fixture.nodes[new_a].next);
    try std.testing.expectEqual(asSize(3), fixture.nodes[new_b].next);
    try std.testing.expectEqual(new_b, fixture.nodes[3].prior);
}

test "insertBefore" {
    try runWithContext(testInsertBefore);
}

fn testInsertAfter(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    const root_node = fixture.root;

    const new_a = fixture.free_nodes[0];
    const new_b = fixture.free_nodes[1];
    fixture.nodes[new_a].next = new_b;
    fixture.nodes[new_b].prior = new_a;

    // Insert chain after root's children[1] (child2 = 2)
    try TestASTNode.insertAfter(2, node_allocator, new_a);

    // Root: 1, 2, new_a, new_b, 3, 4
    var count: usize = 0;
    var curr = fixture.nodes[root_node].first_child;
    var children_list: [6]Context.Size = undefined;
    while (curr != TestASTNode.invalid_pointer) {
        children_list[count] = curr;
        count += 1;
        curr = fixture.nodes[curr].next;
    }

    try std.testing.expectEqual(@as(usize, 6), count);
    try std.testing.expectEqual(asSize(2), children_list[1]);
    try std.testing.expectEqual(new_a, children_list[2]);
    try std.testing.expectEqual(new_b, children_list[3]);
    try std.testing.expectEqual(asSize(3), children_list[4]);

    try std.testing.expectEqual(root_node, fixture.nodes[new_a].parent);
    try std.testing.expectEqual(root_node, fixture.nodes[new_b].parent);

    try std.testing.expectEqual(new_a, fixture.nodes[2].next);
    try std.testing.expectEqual(asSize(2), fixture.nodes[new_a].prior);
    try std.testing.expectEqual(new_b, fixture.nodes[new_a].next);
    try std.testing.expectEqual(asSize(3), fixture.nodes[new_b].next);
}

test "insertAfter" {
    try runWithContext(testInsertAfter);
}

fn testPromoteChildrenOverWrapper(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    const root_node = fixture.root;

    const wrapper = fixture.free_nodes[0];
    const child_a = fixture.free_nodes[1];
    const child_b = fixture.free_nodes[2];
    fixture.nodes[child_a].next = child_b;
    fixture.nodes[child_b].prior = child_a;
    fixture.nodes[wrapper].first_child = child_a;
    fixture.nodes[wrapper].last_child = child_b;
    fixture.nodes[wrapper].children_count = 2;
    fixture.nodes[child_a].parent = wrapper;
    fixture.nodes[child_b].parent = wrapper;

    try TestASTNode.insertChildren(root_node, node_allocator, 2, wrapper);

    const promoted = TestASTNode.promoteChildrenOverWrapper(wrapper, node_allocator).?;
    try std.testing.expectEqual(child_a, promoted);

    var count: usize = 0;
    var curr = fixture.nodes[root_node].first_child;
    var children_list: [6]Context.Size = undefined;
    while (curr != TestASTNode.invalid_pointer) {
        children_list[count] = curr;
        count += 1;
        curr = fixture.nodes[curr].next;
    }

    try std.testing.expectEqual(@as(usize, 6), count);
    try std.testing.expectEqual(asSize(1), children_list[0]);
    try std.testing.expectEqual(asSize(2), children_list[1]);
    try std.testing.expectEqual(child_a, children_list[2]);
    try std.testing.expectEqual(child_b, children_list[3]);
    try std.testing.expectEqual(asSize(3), children_list[4]);
    try std.testing.expectEqual(asSize(4), children_list[5]);
    try std.testing.expectEqual(root_node, fixture.nodes[child_a].parent);
    try std.testing.expectEqual(root_node, fixture.nodes[child_b].parent);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[wrapper].first_child);
}

test "promoteChildrenOverWrapper" {
    try runWithContext(testPromoteChildrenOverWrapper);
}

fn testInsertChildren(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    const parent = asSize(1); // child1 (has 3 children: 5, 6, 7)

    const new_node = fixture.free_nodes[0];

    // Insert at the beginning (index 0)
    try TestASTNode.insertChildren(parent, node_allocator, 0, new_node);

    var count: usize = 0;
    var curr = fixture.nodes[parent].first_child;
    var children_list: [5]Context.Size = undefined;
    while (curr != TestASTNode.invalid_pointer) {
        children_list[count] = curr;
        count += 1;
        curr = fixture.nodes[curr].next;
    }

    try std.testing.expectEqual(@as(usize, 4), count);
    try std.testing.expectEqual(new_node, children_list[0]);
    try std.testing.expectEqual(parent, fixture.nodes[new_node].parent);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[new_node].prior);
    try std.testing.expectEqual(asSize(5), fixture.nodes[new_node].next);
    try std.testing.expectEqual(new_node, fixture.nodes[5].prior);

    // Insert at the end (index 4)
    const new_node2 = fixture.free_nodes[1];
    try TestASTNode.insertChildren(parent, node_allocator, 4, new_node2);

    count = 0;
    curr = fixture.nodes[parent].first_child;
    while (curr != TestASTNode.invalid_pointer) {
        children_list[count] = curr;
        count += 1;
        curr = fixture.nodes[curr].next;
    }

    try std.testing.expectEqual(@as(usize, 5), count);
    try std.testing.expectEqual(new_node2, children_list[4]);
    try std.testing.expectEqual(parent, fixture.nodes[new_node2].parent);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[new_node2].next);
    try std.testing.expectEqual(asSize(7), fixture.nodes[new_node2].prior);
}

test "insertChildren" {
    try runWithContext(testInsertChildren);
}

fn testAugmentedText(fixture: *TestFixture) !void {
    var ctx_val = fixture.getContext();
    const ctx = &ctx_val;

    // Leaf nodes return their own text
    fixture.nodes[5].text_start = 0;
    fixture.nodes[5].text_length = 1;
    const leaf_text = try TestASTNode.augmentedText(5, ctx);
    try std.testing.expectEqualStrings("A", leaf_text);

    // Set distinguishable leaf texts on child1's children (5, 6, 7)
    fixture.nodes[5].text_start = 0;
    fixture.nodes[5].text_length = 1; // "A"
    fixture.nodes[6].text_start = 1;
    fixture.nodes[6].text_length = 1; // "B"
    fixture.nodes[7].text_start = 2;
    fixture.nodes[7].text_length = 1; // "C"

    const combined = try TestASTNode.augmentedText(1, ctx);
    try std.testing.expectEqualStrings("ABC", combined);
}

test "augmentedText" {
    try runWithContext(testAugmentedText);
}

fn testRemoveCountExceeds(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    // child 4 (address 4) is the last child of root; asking for 2 beyond it should error
    const result = TestASTNode.remove(4, node_allocator, 2);
    try std.testing.expectError(error.CountExceedsRemainingSiblings, result);
}

test "remove count exceeds remaining siblings" {
    try runWithContext(testRemoveCountExceeds);
}

fn testImmediateInsertChild(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;

    const parent = fixture.free_nodes[0];
    const child1 = fixture.free_nodes[1];
    const child2 = fixture.free_nodes[2];

    // Insert first child
    node_allocator.at(parent).immediateInsertChild(parent, child1, node_allocator);
    try std.testing.expectEqual(child1, fixture.nodes[parent].first_child);
    try std.testing.expectEqual(child1, fixture.nodes[parent].last_child);
    try std.testing.expectEqual(parent, fixture.nodes[child1].parent);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[child1].prior);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[child1].next);

    // Insert second child
    node_allocator.at(parent).immediateInsertChild(parent, child2, node_allocator);
    try std.testing.expectEqual(child1, fixture.nodes[parent].first_child);
    try std.testing.expectEqual(child2, fixture.nodes[parent].last_child);
    try std.testing.expectEqual(parent, fixture.nodes[child2].parent);
    try std.testing.expectEqual(child1, fixture.nodes[child2].prior);
    try std.testing.expectEqual(child2, fixture.nodes[child1].next);
    try std.testing.expectEqual(TestASTNode.invalid_pointer, fixture.nodes[child2].next);
}

test "immediateInsertChild" {
    try runWithContext(testImmediateInsertChild);
}
