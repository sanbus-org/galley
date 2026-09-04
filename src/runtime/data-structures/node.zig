const std = @import("std");
const builtin = @import("builtin");
const root = @import("galley");
const Context = root.data_structures.Context;

pub const ASTMemoryBenchmarkStats = struct {
    reachable_nodes: usize,
    final_counter: usize,
    peak_counter: usize,
    total_create_calls: usize,
    usable_capacity: usize,
    preallocated_vector_items: usize,
};

const ASTMemoryBenchmarkCounters = struct {
    peak_counter: usize = 0,
    total_create_calls: usize = 0,
};

pub fn ASTAllocator(comptime PayloadType: type) type {
    return ASTAllocatorWithPointer(PayloadType, usize);
}

fn ASTAllocatorWithPointer(comptime PayloadType: type, comptime PointerType: type) type {
    return struct {
        const NodeType = NodeWithPointer(PayloadType, PointerType, true);
        pub const max_node_capacity: usize = std.math.maxInt(NodeType.Pointer) - 1;
        const supports_reserved_arena = switch (builtin.os.tag) {
            .linux, .macos, .ios, .tvos, .watchos, .visionos, .freebsd, .openbsd, .netbsd, .dragonfly, .illumos => true,
            else => false,
        };
        const arena_max_nodes: usize = 1 << 28;
        pub const capacity_limit: usize = @min(max_node_capacity, if (supports_reserved_arena) arena_max_nodes else max_node_capacity);
        const segment_size: usize = 1024;
        const segment_shift: std.math.Log2Int(usize) = @intCast(std.math.log2(segment_size));
        const segment_mask: usize = segment_size - 1;
        const invalid_pointer: NodeType.Pointer = std.math.maxInt(NodeType.Pointer);
        const default: NodeType = .{
            .text_start = 0,
            .text_length = 0,
            .first_child = invalid_pointer,
            .last_child = invalid_pointer,
            .parent = invalid_pointer,
            .prior = invalid_pointer,
            .next = invalid_pointer,
            .children_count = 0,
            .variable = NodeType.invalid_variable,
            .payload = undefined,
        };

        allocator: std.mem.Allocator,
        counter: NodeType.Pointer = 0,
        memory: []NodeType = &.{},
        segments: [][]NodeType = &.{},
        memory_benchmark: if (root.ast_memory_benchmark_enabled) ASTMemoryBenchmarkCounters else void =
            if (root.ast_memory_benchmark_enabled) .{} else {},

        const Self = @This();

        fn mapFlags() std.posix.MAP {
            var flags: std.posix.MAP = .{ .TYPE = .PRIVATE, .ANONYMOUS = true };
            if (@hasField(std.posix.MAP, "NORESERVE")) flags.NORESERVE = true;
            return flags;
        }

        fn reserveArena(self: *Self) !void {
            const bytes = std.mem.alignForward(
                usize,
                capacity_limit * @sizeOf(NodeType),
                std.heap.pageSize(),
            );
            const raw = std.posix.mmap(
                null,
                bytes,
                .{ .READ = true, .WRITE = true },
                Self.mapFlags(),
                -1,
                0,
            ) catch return error.OutOfMemory;
            const usable_nodes = @min(raw.len / @sizeOf(NodeType), capacity_limit);
            const base: [*]NodeType = @ptrCast(@alignCast(raw.ptr));
            self.memory = base[0..usable_nodes];
        }

        pub fn initWithCapacity(allocator: std.mem.Allocator, capacity: usize) !ASTAllocatorWithPointer(PayloadType, PointerType) {
            if (capacity > capacity_limit) return error.ASTCapacityTooLarge;
            var self = ASTAllocatorWithPointer(PayloadType, PointerType){ .allocator = allocator };
            if (comptime supports_reserved_arena) {
                if (capacity > 0) try self.reserveArena();
            } else {
                try self.resizeSegments(std.math.divCeil(usize, capacity, segment_size) catch unreachable);
            }
            return self;
        }

        pub fn totalNodeCapacity(self: *const Self) usize {
            if (comptime supports_reserved_arena) {
                return self.memory.len;
            } else {
                return self.segments.len * segment_size;
            }
        }

        pub fn ensureCapacity(self: *Self, required_capacity: usize) !void {
            if (required_capacity <= self.totalNodeCapacity()) return;
            if (required_capacity > capacity_limit) return error.ASTCapacityTooLarge;
            if (comptime supports_reserved_arena) {
                if (self.memory.len == 0) try self.reserveArena();
            } else {
                try self.resizeSegments(std.math.divCeil(usize, required_capacity, segment_size) catch unreachable);
            }
        }

        fn resizeSegments(self: *Self, count: usize) !void {
            if (comptime supports_reserved_arena) unreachable;
            const old_count = self.segments.len;
            if (count <= old_count) return;
            const new_segments = try self.allocator.alloc([]NodeType, count);
            errdefer self.allocator.free(new_segments);
            @memcpy(new_segments[0..old_count], self.segments);
            var appended: usize = 0;
            errdefer for (new_segments[old_count..][0..appended]) |segment| self.allocator.free(segment);
            for (new_segments[old_count..]) |*slot| {
                slot.* = try self.allocator.alloc(NodeType, segment_size);
                @memset(slot.*, default);
                appended += 1;
            }
            if (old_count > 0) self.allocator.free(self.segments);
            self.segments = new_segments;
        }

        fn grow(self: *Self) !void {
            if (comptime supports_reserved_arena) {
                if (self.memory.len == 0) try self.reserveArena();
            } else {
                if (self.counter >= max_node_capacity) return error.ASTCapacityExceeded;
                try self.resizeSegments(self.segments.len + 1);
            }
        }

        pub fn reset(self: *Self) void {
            // Nodes are fully initialized by `create`, so no memory needs
            // clearing here; dropping the counter logically frees them all.
            self.counter = 0;
            if (comptime root.ast_memory_benchmark_enabled) {
                self.memory_benchmark = .{};
            }
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            if (comptime supports_reserved_arena) {
                if (self.memory.len > 0) std.posix.munmap(@ptrCast(@alignCast(self.memory)));
            } else {
                for (self.segments) |segment| allocator.free(segment);
                if (self.segments.len > 0) allocator.free(self.segments);
            }
            self.memory = &.{};
            self.segments = &.{};
            self.counter = 0;
        }

        pub inline fn at(self: *Self, address: NodeType.Pointer) *NodeType {
            @setEvalBranchQuota(100000);
            if (comptime supports_reserved_arena) {
                return &self.memory[address];
            } else {
                return &self.segments[@as(usize, address) >> segment_shift][@as(usize, address) & segment_mask];
            }
        }

        pub inline fn atConst(self: *const Self, address: NodeType.Pointer) *const NodeType {
            @setEvalBranchQuota(100000);
            if (comptime supports_reserved_arena) {
                return &self.memory[address];
            } else {
                return &self.segments[@as(usize, address) >> segment_shift][@as(usize, address) & segment_mask];
            }
        }

        pub inline fn create(self: *Self, start: usize, variable: u16) error{ ASTCapacityExceeded, OutOfMemory }!NodeType.Pointer {
            if (@as(usize, self.counter) >= self.totalNodeCapacity()) {
                @branchHint(.unlikely);
                if (comptime supports_reserved_arena) {
                    if (self.memory.len == 0) {
                        try self.reserveArena();
                    } else {
                        return error.ASTCapacityExceeded;
                    }
                } else {
                    try self.grow();
                }
            }

            const address = self.counter;
            self.counter += 1;

            if (comptime root.ast_memory_benchmark_enabled) {
                self.memory_benchmark.total_create_calls +%= 1;
                self.memory_benchmark.peak_counter = @max(
                    self.memory_benchmark.peak_counter,
                    @as(usize, self.counter),
                );
            }

            const node = self.at(address);
            node.first_child = invalid_pointer;
            node.last_child = invalid_pointer;
            node.parent = invalid_pointer;
            node.prior = invalid_pointer;
            node.next = invalid_pointer;
            node.text_start = start;
            node.text_length = 0;
            node.children_count = 0;
            node.variable = variable;
            node.payload = .{};

            return address;
        }

        pub fn memoryBenchmarkStats(
            self: *const Self,
            scratch_allocator: std.mem.Allocator,
            ast_root: ?NodeType.Pointer,
        ) !ASTMemoryBenchmarkStats {
            if (comptime !root.ast_memory_benchmark_enabled) {
                @compileError("AST memory benchmark instrumentation is disabled; rebuild with -Dast-memory-benchmark=true");
            }

            var visited = try std.DynamicBitSetUnmanaged.initEmpty(scratch_allocator, self.counter);
            defer visited.deinit(scratch_allocator);

            var pending: std.ArrayList(NodeType.Pointer) = .empty;
            defer pending.deinit(scratch_allocator);
            if (ast_root) |address| try pending.append(scratch_allocator, address);

            var reachable_nodes: usize = 0;
            while (pending.pop()) |address| {
                if (address >= self.counter) return error.InvalidASTPointer;
                if (visited.isSet(address)) continue;
                visited.set(address);
                reachable_nodes += 1;

                const node = self.atConst(address);
                if (node.first_child != invalid_pointer) {
                    try pending.append(scratch_allocator, node.first_child);
                }
                if (node.next != invalid_pointer) {
                    try pending.append(scratch_allocator, node.next);
                }
            }

            return .{
                .reachable_nodes = reachable_nodes,
                .final_counter = self.counter,
                .peak_counter = self.memory_benchmark.peak_counter,
                .total_create_calls = self.memory_benchmark.total_create_calls,
                .usable_capacity = self.totalNodeCapacity(),
                .preallocated_vector_items = self.totalNodeCapacity(),
            };
        }

        pub inline fn terminalNode(terminal: u8) NodeType.Pointer {
            return terminal;
        }
    };
}

pub fn Node(comptime PayloadType: type, comptime with_ast: bool) type {
    return NodeWithPointer(PayloadType, usize, with_ast);
}

fn NodeWithPointer(comptime PayloadType: type, comptime PointerType: type, comptime with_ast: bool) type {
    return struct {
        pub const Pointer = PointerType;
        pub const NodeAllocator = if (with_ast) *ASTAllocatorWithPointer(PayloadType, PointerType) else void;
        pub const invalid_pointer: Pointer = ASTAllocatorWithPointer(PayloadType, PointerType).invalid_pointer;
        pub const invalid_variable: u16 = std.math.maxInt(u16);
        pub const ChildLink = if (with_ast) Pointer else ?*@This();

        text_start: usize = 0,
        text_length: usize = 0,

        first_child: ChildLink = if (with_ast) invalid_pointer else null,
        last_child: ChildLink = if (with_ast) invalid_pointer else null,
        parent: if (with_ast) Pointer else void = if (with_ast) invalid_pointer else {},
        prior: if (with_ast) Pointer else void = if (with_ast) invalid_pointer else {},
        next: ChildLink = if (with_ast) invalid_pointer else null,

        children_count: u32 = 0,

        variable: u16 = invalid_variable,
        payload: PayloadType,

        const Self = @This();

        pub const ChildIterator = struct {
            node_allocator: NodeAllocator,
            current: ChildLink,

            pub fn next(self: *@This()) ?*Self {
                if (comptime with_ast) {
                    const current_address = self.current;
                    if (current_address == invalid_pointer) return null;
                    const current = self.node_allocator.at(current_address);
                    self.current = current.next;
                    return current;
                }

                const current = self.current orelse return null;
                self.current = current.next;
                return current;
            }
        };

        pub fn childIterator(self: *Self, context: *Context) ChildIterator {
            return .{
                .node_allocator = if (with_ast) context.node_allocator else {},
                .current = self.first_child,
            };
        }

        pub fn appendTemporaryChild(self: *Self, child: *Self) void {
            if (comptime with_ast) {
                @compileError("temporary Node links are available only when AST construction is disabled");
            }

            child.next = null;
            if (self.last_child) |last_child| {
                last_child.next = child;
            } else {
                self.first_child = child;
            }
            self.last_child = child;
            self.children_count += 1;
        }

        pub fn clearTemporaryChildren(self: *Self) void {
            if (comptime with_ast) {
                @compileError("temporary Node links are available only when AST construction is disabled");
            }

            self.first_child = null;
            self.last_child = null;
            self.children_count = 0;
        }

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
            const added = Self.chainLength(node_allocator, first_node);

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
                parent_node.children_count += added;

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
            const added = Self.chainLength(node_allocator, first_node);

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
                parent_node.children_count += added;

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

        /// Returns source text directly for leaves. For non-leaves, returns text rebuilt in the
        /// session arena from descendant leaves, valid until the session arena is reset.
        pub fn augmentedText(self_address: Pointer, context: *Context) ![]const u8 {
            const node_allocator = context.node_allocator;
            const self = node_allocator.at(self_address);
            if (self.first_child == invalid_pointer) {
                return context.getTextSlice(self.text_start, self.text_length);
            }

            const allocator = context.runtime().arena_allocator;
            var combined_text: std.ArrayList(u8) = .empty;
            var current = self.first_child;

            traversal: while (true) {
                const current_node = node_allocator.at(current);
                if (current_node.first_child != invalid_pointer) {
                    current = current_node.first_child;
                    continue;
                }

                try combined_text.appendSlice(
                    allocator,
                    context.getTextSlice(current_node.text_start, current_node.text_length),
                );

                while (current != self_address) {
                    const completed_node = node_allocator.at(current);
                    if (completed_node.next != invalid_pointer) {
                        current = completed_node.next;
                        continue :traversal;
                    }
                    current = completed_node.parent;
                }

                break;
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
const TestNode = Node(TestPayload, true);
const TestASTAllocator = ASTAllocator(TestPayload);

test "AST memory benchmark counts reachable nodes and allocator usage" {
    if (comptime !root.parser.is_ast_enabled or !root.ast_memory_benchmark_enabled) return;
    var node_allocator = try TestASTAllocator.initWithCapacity(std.testing.allocator, 4);
    defer node_allocator.deinit(std.testing.allocator);

    const ast_root = try node_allocator.create(0, 1);
    const first_child = try node_allocator.create(1, 2);
    const second_child = try node_allocator.create(2, 3);
    _ = try node_allocator.create(3, 4);

    node_allocator.at(ast_root).first_child = first_child;
    node_allocator.at(first_child).next = second_child;
    node_allocator.at(second_child).next = first_child;

    const stats = try node_allocator.memoryBenchmarkStats(std.testing.allocator, ast_root);
    try std.testing.expectEqual(@as(usize, 3), stats.reachable_nodes);
    try std.testing.expectEqual(@as(usize, 4), stats.final_counter);
    try std.testing.expectEqual(@as(usize, 4), stats.peak_counter);
    try std.testing.expectEqual(@as(usize, 4), stats.total_create_calls);
    try std.testing.expect(stats.usable_capacity >= 4);
    try std.testing.expectEqual(stats.usable_capacity, stats.preallocated_vector_items);

    const no_root_stats = try node_allocator.memoryBenchmarkStats(std.testing.allocator, null);
    try std.testing.expectEqual(@as(usize, 0), no_root_stats.reachable_nodes);
    try std.testing.expectError(
        error.InvalidASTPointer,
        node_allocator.memoryBenchmarkStats(std.testing.allocator, TestNode.invalid_pointer),
    );
}

test "AST memory benchmark tracks allocation peak and resets counters" {
    if (comptime !root.parser.is_ast_enabled or !root.ast_memory_benchmark_enabled) return;
    var node_allocator = try TestASTAllocator.initWithCapacity(std.testing.allocator, 2);
    defer node_allocator.deinit(std.testing.allocator);

    _ = try node_allocator.create(0, 1);
    _ = try node_allocator.create(1, 2);

    const stats = try node_allocator.memoryBenchmarkStats(std.testing.allocator, null);
    try std.testing.expectEqual(@as(usize, 2), stats.final_counter);
    try std.testing.expectEqual(@as(usize, 2), stats.peak_counter);
    try std.testing.expectEqual(@as(usize, 2), stats.total_create_calls);

    node_allocator.reset();
    const reset_stats = try node_allocator.memoryBenchmarkStats(std.testing.allocator, null);
    try std.testing.expectEqual(@as(usize, 0), reset_stats.final_counter);
    try std.testing.expectEqual(@as(usize, 0), reset_stats.peak_counter);
    try std.testing.expectEqual(@as(usize, 0), reset_stats.total_create_calls);
}

test "AST allocator preserves nodes across cold-path growth" {
    if (comptime !root.parser.is_ast_enabled) return;
    var node_allocator = try TestASTAllocator.initWithCapacity(std.testing.allocator, 1);
    defer node_allocator.deinit(std.testing.allocator);

    const first = try node_allocator.create(3, 11);
    node_allocator.at(first).text_length = 7;
    const second = try node_allocator.create(5, 13);

    try std.testing.expect(node_allocator.totalNodeCapacity() >= 2);
    try std.testing.expectEqual(@as(TestNode.Pointer, 0), first);
    try std.testing.expectEqual(@as(TestNode.Pointer, 1), second);
    try std.testing.expectEqual(@as(usize, 3), node_allocator.at(first).text_start);
    try std.testing.expectEqual(@as(usize, 7), node_allocator.at(first).text_length);
    try std.testing.expectEqual(@as(u16, 11), node_allocator.at(first).variable);
}

test "AST allocator reports exhaustion without corrupting state" {
    if (comptime !root.parser.is_ast_enabled) return;

    const ExhaustionNode = NodeWithPointer(TestPayload, u8, true);
    const ExhaustionASTAllocator = ASTAllocatorWithPointer(TestPayload, u8);
    var node_allocator = try ExhaustionASTAllocator.initWithCapacity(
        std.testing.allocator,
        ExhaustionASTAllocator.max_node_capacity,
    );
    defer node_allocator.deinit(std.testing.allocator);

    var index: usize = 0;
    while (index < ExhaustionASTAllocator.max_node_capacity) : (index += 1) {
        const address = try node_allocator.create(index, @intCast(index));
        try std.testing.expectEqual(@as(ExhaustionNode.Pointer, @intCast(index)), address);
    }

    const final_node = node_allocator.at(@intCast(ExhaustionASTAllocator.max_node_capacity - 1));
    final_node.text_length = 17;
    try std.testing.expectError(
        error.ASTCapacityExceeded,
        node_allocator.create(index, 99),
    );
    try std.testing.expectEqual(
        @as(ExhaustionNode.Pointer, @intCast(ExhaustionASTAllocator.max_node_capacity)),
        node_allocator.counter,
    );
    try std.testing.expectEqual(@as(usize, 17), final_node.text_length);
}

test "AST allocator keeps resolved node pointers stable across growth" {
    if (comptime !root.parser.is_ast_enabled) return;
    var node_allocator = try TestASTAllocator.initWithCapacity(std.testing.allocator, 1);
    defer node_allocator.deinit(std.testing.allocator);

    const first = try node_allocator.create(0, 1);
    const retained = node_allocator.at(first);
    retained.text_length = 41;

    // Cross many internal storage boundaries; the resolved pointer must
    // address the same live node throughout.
    var index: usize = 1;
    while (index < 5000) : (index += 1) {
        _ = try node_allocator.create(@intCast(index), 1);
    }

    try std.testing.expectEqual(@as(usize, 41), node_allocator.at(0).text_length);
    retained.text_length = 42;
    try std.testing.expectEqual(@as(usize, 42), node_allocator.at(0).text_length);
}

test "procedure hook current node pointer survives node allocation" {
    if (comptime !root.parser.is_ast_enabled) return;
    var node_allocator = try TestASTAllocator.initWithCapacity(std.testing.allocator, 1);
    defer node_allocator.deinit(std.testing.allocator);
    var context = Context{};
    context.node_allocator = &node_allocator;

    const address = try node_allocator.create(0, 1);
    var args = root.data_structures.ProcedureArguments{ .context = &context, .rule = null };
    args.node_address = address;

    // A hook resolves its current node, then allocates through a tree helper
    // across many growth steps before writing through the retained pointer.
    const node = args.currentNode().?;
    var index: usize = 0;
    while (index < 5000) : (index += 1) {
        _ = try node_allocator.create(@intCast(index), 1);
    }

    node.text_length = 7;
    try std.testing.expectEqual(@as(usize, 7), args.currentNode().?.text_length);
}

test "zero length augmented node" {
    if (comptime !root.parser.is_ast_enabled) return;
    var node_allocator = try TestASTAllocator.initWithCapacity(std.testing.allocator, 1);
    defer node_allocator.deinit(std.testing.allocator);

    node_allocator.at(0).* = .{
        .text_start = 0,
        .text_length = 1,
        .payload = .{},
    };

    try std.testing.expectEqual(@as(usize, 0), TestNode.augmentedBackLength(0, &node_allocator));
    try std.testing.expectEqual(@as(usize, 1), TestNode.augmentedLength(0, &node_allocator));
    try std.testing.expectEqual(@as(usize, 0), TestNode.augmentedFrontLength(0, &node_allocator));
}

test "augmented length" {
    if (comptime !root.parser.is_ast_enabled) return;
    var node_allocator = try TestASTAllocator.initWithCapacity(std.testing.allocator, 20);
    defer node_allocator.deinit(std.testing.allocator);

    for (0..20) |index| {
        if (index > 0) {
            node_allocator.at(@intCast(index - 1)).next = @intCast(index);
        }
        node_allocator.at(@intCast(index)).* = .{
            .text_start = 0,
            .text_length = 1,
            .prior = if (index > 0) @intCast(index - 1) else TestNode.invalid_pointer,
            .payload = .{},
        };
    }

    for (0..20) |index| {
        try std.testing.expectEqual(@as(usize, index), TestNode.augmentedBackLength(@intCast(index), &node_allocator));
        try std.testing.expectEqual(@as(usize, 20), TestNode.augmentedLength(@intCast(index), &node_allocator));
        try std.testing.expectEqual(@as(usize, 19 - index), TestNode.augmentedFrontLength(@intCast(index), &node_allocator));
    }
}

test "augmented iterate" {
    if (comptime !root.parser.is_ast_enabled) return;
    var node_allocator = try TestASTAllocator.initWithCapacity(std.testing.allocator, 20);
    defer node_allocator.deinit(std.testing.allocator);

    for (0..20) |index| {
        if (index > 0) {
            node_allocator.at(@intCast(index - 1)).next = @intCast(index);
        }
        node_allocator.at(@intCast(index)).* = .{
            .text_start = 0,
            .text_length = 1,
            .prior = if (index > 0) @intCast(index - 1) else TestNode.invalid_pointer,
            .payload = .{},
        };
    }

    const initial_node: TestNode.Pointer = 10;
    var iterator = TestNode.iterateAugmented(initial_node, &node_allocator);
    var counter: usize = 0;
    while (iterator.next()) |current| {
        try std.testing.expectEqual(@as(TestNode.Pointer, @intCast(counter)), current);
        counter += 1;
    }
}

fn testContext(node_allocator: *TestASTAllocator, text: []u8) Context {
    var context = Context{};
    context.node_allocator = node_allocator;
    if (comptime root.config.indentation_syntax) {
        context.token.resetBuffered();
        @memcpy(context.token.buffer[0..text.len], text);
    } else {
        context.token.resetInput(text);
    }
    context.token.head = @intCast(text.len);
    context.token.len = @intCast(text.len);
    return context;
}

const TestFixture = struct {
    arena: std.heap.ArenaAllocator,
    node_allocator: TestASTAllocator,
    text: []u8,
    nodes: []TestNode,
    root: TestNode.Pointer,
    free_nodes: []TestNode.Pointer,
    runtime_context: *root.data_structures.RuntimeContext = undefined,

    pub fn allocator(self: *TestFixture) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn getContext(self: *TestFixture) Context {
        return testContext(&self.node_allocator, self.text);
    }

    pub fn init() !TestFixture {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        const alloc = arena.allocator();

        var node_allocator = try TestASTAllocator.initWithCapacity(alloc, 30);
        node_allocator.counter = 30;
        const nodes: []TestNode = if (comptime TestASTAllocator.supports_reserved_arena)
            node_allocator.memory[0..30]
        else
            node_allocator.segments[0][0..30];
        for (nodes) |*node| {
            node.* = .{
                .text_start = 0,
                .text_length = 0,
                .payload = .{},
            };
        }

        const text = try alloc.dupe(u8, "ABCDEFGHIJKLMNOPQRSTUVWXYZ");

        const root_node: TestNode.Pointer = 0;
        nodes[root_node] = .{
            .text_start = 0,
            .text_length = 1,
            .payload = .{},
        };

        for (1..5) |index| {
            const child_addr: TestNode.Pointer = @intCast(index);
            nodes[child_addr] = .{
                .text_start = 0,
                .text_length = 1,
                .payload = .{},
            };
            try TestNode.appendChildren(root_node, &node_allocator, child_addr);
        }

        var counter: TestNode.Pointer = 5;
        for (1..5) |parent_index| {
            const parent_addr: TestNode.Pointer = @intCast(parent_index);
            for (0..3) |_| {
                const child_addr = counter;
                counter += 1;
                nodes[child_addr] = .{
                    .text_start = 0,
                    .text_length = 1,
                    .payload = .{},
                };
                try TestNode.appendChildren(parent_addr, &node_allocator, child_addr);
            }
        }

        const free_nodes = try alloc.alloc(TestNode.Pointer, 30 - counter);
        for (free_nodes, 0..) |*fn_addr, idx| {
            fn_addr.* = counter + @as(TestNode.Pointer, @intCast(idx));
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
    fixture.runtime_context = &runtime_context;
    try test_fn(&fixture);
}

fn testRemove(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    const root_node = fixture.root;

    var count: usize = 0;
    var curr = fixture.nodes[root_node].first_child;
    while (curr != TestNode.invalid_pointer) {
        count += 1;
        curr = fixture.nodes[curr].next;
    }
    try std.testing.expectEqual(@as(usize, 4), count);

    const removed_head = try TestNode.remove(2, node_allocator, 2);

    // Parent (root) now has 2 children: 1, 4
    count = 0;
    curr = fixture.nodes[root_node].first_child;
    while (curr != TestNode.invalid_pointer) {
        count += 1;
        curr = fixture.nodes[curr].next;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqual(asSize(1), fixture.nodes[root_node].first_child);
    try std.testing.expectEqual(asSize(4), fixture.nodes[root_node].last_child);

    // Sibling chain updated correctly
    try std.testing.expectEqual(asSize(4), fixture.nodes[1].next);
    try std.testing.expectEqual(asSize(1), fixture.nodes[4].prior);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[1].prior);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[4].next);

    // Removed nodes are detached orphans
    try std.testing.expectEqual(asSize(2), removed_head);
    try std.testing.expectEqual(asSize(3), fixture.nodes[2].next);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[2].parent);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[2].prior);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[3].parent);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[3].next);
}

fn asSize(val: anytype) TestNode.Pointer {
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

    try TestNode.insertBefore(3, node_allocator, new_a);

    // Root should now have 6 children: 1, 2, new_a, new_b, 3, 4
    var count: usize = 0;
    var curr = fixture.nodes[root_node].first_child;
    var children_list: [6]TestNode.Pointer = undefined;
    while (curr != TestNode.invalid_pointer) {
        children_list[count] = curr;
        count += 1;
        curr = fixture.nodes[curr].next;
    }

    try std.testing.expectEqual(@as(usize, 6), count);
    try std.testing.expectEqual(@as(u32, 6), fixture.nodes[root_node].children_count);
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
    try TestNode.insertAfter(2, node_allocator, new_a);

    // Root: 1, 2, new_a, new_b, 3, 4
    var count: usize = 0;
    var curr = fixture.nodes[root_node].first_child;
    var children_list: [6]TestNode.Pointer = undefined;
    while (curr != TestNode.invalid_pointer) {
        children_list[count] = curr;
        count += 1;
        curr = fixture.nodes[curr].next;
    }

    try std.testing.expectEqual(@as(usize, 6), count);
    try std.testing.expectEqual(@as(u32, 6), fixture.nodes[root_node].children_count);
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

    try TestNode.insertChildren(root_node, node_allocator, 2, wrapper);

    const promoted = TestNode.promoteChildrenOverWrapper(wrapper, node_allocator).?;
    try std.testing.expectEqual(child_a, promoted);

    var count: usize = 0;
    var curr = fixture.nodes[root_node].first_child;
    var children_list: [6]TestNode.Pointer = undefined;
    while (curr != TestNode.invalid_pointer) {
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
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[wrapper].first_child);
}

test "promoteChildrenOverWrapper" {
    try runWithContext(testPromoteChildrenOverWrapper);
}

fn testInsertChildren(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    const parent = asSize(1); // child1 (has 3 children: 5, 6, 7)

    const new_node = fixture.free_nodes[0];

    // Insert at the beginning (index 0)
    try TestNode.insertChildren(parent, node_allocator, 0, new_node);

    var count: usize = 0;
    var curr = fixture.nodes[parent].first_child;
    var children_list: [5]TestNode.Pointer = undefined;
    while (curr != TestNode.invalid_pointer) {
        children_list[count] = curr;
        count += 1;
        curr = fixture.nodes[curr].next;
    }

    try std.testing.expectEqual(@as(usize, 4), count);
    try std.testing.expectEqual(new_node, children_list[0]);
    try std.testing.expectEqual(parent, fixture.nodes[new_node].parent);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[new_node].prior);
    try std.testing.expectEqual(asSize(5), fixture.nodes[new_node].next);
    try std.testing.expectEqual(new_node, fixture.nodes[5].prior);

    // Insert at the end (index 4)
    const new_node2 = fixture.free_nodes[1];
    try TestNode.insertChildren(parent, node_allocator, 4, new_node2);

    count = 0;
    curr = fixture.nodes[parent].first_child;
    while (curr != TestNode.invalid_pointer) {
        children_list[count] = curr;
        count += 1;
        curr = fixture.nodes[curr].next;
    }

    try std.testing.expectEqual(@as(usize, 5), count);
    try std.testing.expectEqual(new_node2, children_list[4]);
    try std.testing.expectEqual(parent, fixture.nodes[new_node2].parent);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[new_node2].next);
    try std.testing.expectEqual(asSize(7), fixture.nodes[new_node2].prior);
}

test "insertChildren" {
    try runWithContext(testInsertChildren);
}

fn testAugmentedText(fixture: *TestFixture) !void {
    var context = fixture.getContext();
    const ctx = &context;
    var runtime_registration = root.data_structures.RuntimeContextRegistration.init(ctx, fixture.runtime_context);
    runtime_registration.register();
    defer runtime_registration.unregister();

    // Leaf nodes return their own text
    fixture.nodes[5].text_start = 0;
    fixture.nodes[5].text_length = 1;
    const leaf_text = try TestNode.augmentedText(5, ctx);
    try std.testing.expectEqualStrings("A", leaf_text);

    fixture.nodes[5].text_start = 0;
    fixture.nodes[5].text_length = 1; // "A"
    fixture.nodes[7].text_start = 3;
    fixture.nodes[7].text_length = 1; // "D"

    const nested_b = fixture.free_nodes[0];
    const nested_empty = fixture.free_nodes[1];
    const nested_c = fixture.free_nodes[2];
    fixture.nodes[nested_b].text_start = 1;
    fixture.nodes[nested_b].text_length = 1; // "B"
    fixture.nodes[nested_empty].text_start = 2;
    fixture.nodes[nested_empty].text_length = 0;
    fixture.nodes[nested_c].text_start = 2;
    fixture.nodes[nested_c].text_length = 1; // "C"
    try TestNode.appendChildren(6, &fixture.node_allocator, nested_b);
    try TestNode.appendChildren(6, &fixture.node_allocator, nested_empty);
    try TestNode.appendChildren(6, &fixture.node_allocator, nested_c);

    // Child 2 is child 1's next sibling. Its text must not be included.
    fixture.nodes[8].text_start = 23;
    fixture.nodes[8].text_length = 1; // "X"

    const combined = try TestNode.augmentedText(1, ctx);
    try std.testing.expectEqualStrings("ABCD", combined);

    var output_storage: [1024]u8 = undefined;
    var output_allocator = std.heap.FixedBufferAllocator.init(&output_storage);
    const original_allocator = fixture.runtime_context.arena_allocator;
    fixture.runtime_context.arena_allocator = output_allocator.allocator();
    defer fixture.runtime_context.arena_allocator = original_allocator;

    const compact_combined = try TestNode.augmentedText(1, ctx);
    try std.testing.expectEqualStrings("ABCD", compact_combined);
}

test "augmentedText" {
    try runWithContext(testAugmentedText);
}

test "augmentedText traverses deep trees iteratively" {
    if (comptime !root.parser.is_ast_enabled) return;

    const depth = 16 * 1024;
    var node_allocator = try TestASTAllocator.initWithCapacity(std.testing.allocator, depth);
    defer node_allocator.deinit(std.testing.allocator);

    var input = [_]u8{'Z'};
    var context = testContext(&node_allocator, input[0..]);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var runtime_context = root.data_structures.RuntimeContext{
        .io = undefined,
        .arena_allocator = arena.allocator(),
    };
    var runtime_registration = root.data_structures.RuntimeContextRegistration.init(&context, &runtime_context);
    runtime_registration.register();
    defer runtime_registration.unregister();

    const root_node = try node_allocator.create(0, 0);
    var parent = root_node;
    for (1..depth) |_| {
        const child = try node_allocator.create(0, 0);
        node_allocator.at(parent).immediateInsertChild(parent, child, &node_allocator);
        parent = child;
    }
    node_allocator.at(parent).text_length = 1;

    try std.testing.expectEqualStrings("Z", try TestNode.augmentedText(root_node, &context));
}

fn testRemoveCountExceeds(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    // child 4 (address 4) is the last child of root; asking for 2 beyond it should error
    const result = TestNode.remove(4, node_allocator, 2);
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
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[child1].prior);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[child1].next);

    // Insert second child
    node_allocator.at(parent).immediateInsertChild(parent, child2, node_allocator);
    try std.testing.expectEqual(child1, fixture.nodes[parent].first_child);
    try std.testing.expectEqual(child2, fixture.nodes[parent].last_child);
    try std.testing.expectEqual(parent, fixture.nodes[child2].parent);
    try std.testing.expectEqual(child1, fixture.nodes[child2].prior);
    try std.testing.expectEqual(child2, fixture.nodes[child1].next);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[child2].next);
}

test "immediateInsertChild" {
    try runWithContext(testImmediateInsertChild);
}
