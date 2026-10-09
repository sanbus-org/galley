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
        pub const supports_reserved_arena = switch (builtin.os.tag) {
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
            .is_semantic_error = false,
            .is_recovered = false,
            .payload = undefined,
        };

        allocator: std.mem.Allocator,
        counter: NodeType.Pointer = 0,
        /// Change counter for the tree's parent structure: bumped once per
        /// `setParent` or `setChainParent` call (`attachParent` is exempt,
        /// see its doc). Walk cursors stamp it on each step, so a later step
        /// can tell that its position must be re-verified against the live
        /// links before stepping.
        structure_version: u64 = 0,
        /// The parse generation whose nodes this storage holds: the session
        /// stamps it when a parse acquires the session, before `reset`
        /// recycles any address, and never reuses a value. A walk cursor
        /// carries the generation it was created over and `walkNext` refuses a
        /// storage that holds another. Zero belongs to storage no session
        /// ever parsed into, such as a hand-built tree.
        generation: u64 = 0,
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

        fn reserveArena(self: *Self, node_count: usize) !void {
            // Reservations are sized to the request (page-rounded), never the
            // maximum: a session per thread must not cost the full arena in
            // address space. `mmap` failure (cgroup limits, overcommit
            // accounting) surfaces as `OutOfMemory`, the only fallback
            // trigger. Storage never relocates mid-parse; re-reservation
            // happens only between parses via `ensureCapacity`.
            const count = @min(@max(node_count, 1), capacity_limit);
            const wide_product: u128 = @as(u128, count) * @sizeOf(NodeType);
            const product: usize = @intCast(@min(wide_product, std.math.maxInt(usize)));
            const bytes = std.mem.alignForward(
                usize,
                product,
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

        fn unmap(memory: []NodeType) void {
            if (memory.len > 0) std.posix.munmap(@ptrCast(@alignCast(memory)));
        }

        fn unreserveArena(self: *Self) void {
            unmap(self.memory);
            self.memory = &.{};
        }

        /// First-use reservation for parses that skip capacity planning
        /// (they never called `ensureCapacity`). Matches the session floor
        /// (`root.default_ast_preallocation_floor`) so both entry paths
        /// start from the same ready storage; further demand appends
        /// segments incrementally.
        pub fn initWithCapacity(allocator: std.mem.Allocator, capacity: usize) !ASTAllocatorWithPointer(PayloadType, PointerType) {
            if (capacity > capacity_limit) return error.ASTCapacityTooLarge;
            var self = ASTAllocatorWithPointer(PayloadType, PointerType){ .allocator = allocator };
            if (comptime supports_reserved_arena) {
                if (capacity > 0) try self.reserveArena(capacity);
            } else {
                try self.resizeSegments(std.math.divCeil(usize, capacity, segment_size) catch unreachable);
            }
            return self;
        }

        pub fn totalNodeCapacity(self: *const Self) usize {
            if (comptime supports_reserved_arena) {
                return self.memory.len + self.segments.len * segment_size;
            } else {
                return self.segments.len * segment_size;
            }
        }

        pub fn ensureCapacity(self: *Self, required_capacity: usize) !void {
            if (required_capacity <= self.totalNodeCapacity()) return;
            if (required_capacity > capacity_limit) return error.ASTCapacityTooLarge;
            if (comptime supports_reserved_arena) {
                if (self.memory.len == 0) return self.reserveArena(required_capacity);
                if (self.counter == 0) {
                    // Between parses the previous tree is dead by contract,
                    // so re-reserving larger only remaps address space.
                    // Map the new region first: a failed mmap keeps the old
                    // reservation and its segments coherent instead of
                    // leaving addresses able to alias a later mapping.
                    // Demand past this point is covered by appended segments.
                    const old_memory = self.memory;
                    self.memory = &.{};
                    self.reserveArena(required_capacity) catch |err| {
                        self.memory = old_memory;
                        return err;
                    };
                    unmap(old_memory);
                    return;
                }
            }
            // Reserved storage never relocates and segments are never moved,
            // so covering further demand with appended segments keeps every
            // resolved pointer and integer address stable. The early return
            // above guarantees `required_capacity` exceeds the held total,
            // so the subtraction below cannot underflow; segments already
            // held are not counted again.
            const held = self.totalNodeCapacity();
            const needed = required_capacity - held;
            const total_segments = self.segments.len + (std.math.divCeil(usize, needed, segment_size) catch unreachable);
            try self.resizeSegments(total_segments);
        }

        fn resizeSegments(self: *Self, count: usize) !void {
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
                if (self.memory.len == 0) {
                    // First use without a capacity hint reserves a modest
                    // working set; further demand appends segments below.
                    return self.reserveArena(root.default_ast_preallocation_floor);
                }
            }
            // Address exhaustion is the only hard wall: node addresses must
            // never alias `invalid_pointer`.
            if (self.counter >= max_node_capacity) return error.ASTCapacityExceeded;
            // Mid-parse growth appends a segment. Reserved storage is never
            // remapped while nodes are live, so resolved pointers stay put.
            try self.resizeSegments(self.segments.len + 1);
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
                self.unreserveArena();
            }
            for (self.segments) |segment| allocator.free(segment);
            if (self.segments.len > 0) allocator.free(self.segments);
            self.memory = &.{};
            self.segments = &.{};
            self.counter = 0;
        }

        pub inline fn at(self: *Self, address: NodeType.Pointer) *NodeType {
            @setEvalBranchQuota(100000);
            if (comptime supports_reserved_arena) {
                // Overflow segments extend the address space past the
                // reservation. Addresses arrive monotonically within a parse,
                // so the taken branch dominates and resolved storage on
                // either side never moves.
                if (@as(usize, address) < self.memory.len) return &self.memory[address];
                const overflow = @as(usize, address) - self.memory.len;
                return &self.segments[overflow >> segment_shift][overflow & segment_mask];
            } else {
                return &self.segments[@as(usize, address) >> segment_shift][@as(usize, address) & segment_mask];
            }
        }

        /// The write path for changing or clearing one node's parent link:
        /// writes the link and bumps `structure_version`, which walk cursors
        /// stamp so a later step re-verifies its position after any
        /// structural edit. Node initialization (`create`, struct literals)
        /// writes `parent` direct, because a fresh node belongs to no
        /// structure yet. An edit that re-parents a whole sibling chain uses
        /// `setChainParent`, so it bumps once per operation.
        pub inline fn setParent(self: *Self, address: NodeType.Pointer, parent: NodeType.Pointer) void {
            self.at(address).parent = parent;
            self.structure_version += 1;
        }

        /// `setParent` for a sibling chain: writes `parent` on `first` and
        /// every node reached through `next` until the chain ends, and bumps
        /// `structure_version` once for the whole operation. The chain must
        /// end at an invalid `next`, so callers re-parent before they link
        /// the chain's last node to a following sibling.
        pub inline fn setChainParent(self: *Self, first: NodeType.Pointer, parent: NodeType.Pointer) void {
            var current = first;
            while (current != NodeType.invalid_pointer) {
                const node = self.at(current);
                node.parent = parent;
                current = node.next;
            }
            self.structure_version += 1;
        }

        /// Attaches a node that currently has no parent without bumping
        /// `structure_version`. Attaching a parentless node cannot move any
        /// existing walk position: a cursor's position below its root always
        /// has a parent, and the root bounds the climb. Debug builds assert
        /// the old parent is invalid; release builds do not check, so a
        /// caller that attaches a node that already has a parent (for example
        /// a hook that hands back its own first child) leaves it listed under
        /// two parents. Every other parent write (re-parenting, detaching)
        /// goes through `setParent` or `setChainParent`.
        pub inline fn attachParent(self: *Self, address: NodeType.Pointer, parent: NodeType.Pointer) void {
            const node = self.at(address);
            if (comptime builtin.mode == .debug) std.debug.assert(node.parent == invalid_pointer);
            node.parent = parent;
        }

        pub inline fn atConst(self: *const Self, address: NodeType.Pointer) *const NodeType {
            @setEvalBranchQuota(100000);
            if (comptime supports_reserved_arena) {
                if (@as(usize, address) < self.memory.len) return &self.memory[address];
                const overflow = @as(usize, address) - self.memory.len;
                return &self.segments[overflow >> segment_shift][overflow & segment_mask];
            } else {
                return &self.segments[@as(usize, address) >> segment_shift][@as(usize, address) & segment_mask];
            }
        }

        pub inline fn create(self: *Self, start: usize, variable: u16) error{ ASTCapacityExceeded, OutOfMemory }!NodeType.Pointer {
            if (@as(usize, self.counter) >= self.totalNodeCapacity()) {
                @branchHint(.unlikely);
                try self.grow();
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
            node.is_semantic_error = false;
            node.is_recovered = false;
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
        /// Set by the single `reportSemanticError` gate when a hook reports
        /// a semantic error on this node. Parents stay unmarked; use
        /// `hasSemanticErrorSubtree` to query a subtree.
        is_semantic_error: bool = false,
        /// Set on the node syntax-error recovery keeps in place of a
        /// subtree it could not parse: the damaged variable's own node under
        /// LL, a placeholder over the discarded input under LR and explicit
        /// recovery. Its span covers the input recovery skipped. Parents
        /// stay unmarked; use `hasRecoveredSubtree` to query a subtree.
        is_recovered: bool = false,
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

        const ChainSpan = struct {
            last: Pointer,
            count: u32,
        };

        /// The one place that gives a parentless chain its parent: writes the parent link of every
        /// node in the chain starting at `first_node` through `attachParent` (so `structure_version`
        /// does not move) and returns the chain's span. No sibling links change and nothing is checked.
        inline fn attachChain(node_allocator: NodeAllocator, parent_address: Pointer, first_node: Pointer) ChainSpan {
            var current = first_node;
            var count: u32 = 0;
            while (true) {
                node_allocator.attachParent(current, parent_address);
                count += 1;
                const next = node_allocator.at(current).next;
                if (next == invalid_pointer) return .{ .last = current, .count = count };
                current = next;
            }
        }

        pub const InsertionFault = enum {
            chain_head_has_parent,
            chain_head_has_prior,
            /// The chain contains the anchor or one of its ancestors, so linking it would form a cycle.
            chain_contains_anchor_or_ancestor,
            index_out_of_range,
        };

        /// Misuse of an insertion, or null. `anchor_address` is the node the chain is inserted
        /// before, after or under; `index` is the child position for `insertChildren`. Debug builds
        /// assert this is null on entry to the public insertion functions; release builds never run it.
        fn insertionFault(node_allocator: NodeAllocator, anchor_address: Pointer, first_node: Pointer, index: ?usize) ?InsertionFault {
            const first = node_allocator.atConst(first_node);
            if (first.parent != invalid_pointer) return .chain_head_has_parent;
            if (first.prior != invalid_pointer) return .chain_head_has_prior;
            var chain_node = first_node;
            while (chain_node != invalid_pointer) : (chain_node = node_allocator.atConst(chain_node).next) {
                var ancestor = anchor_address;
                while (ancestor != invalid_pointer) : (ancestor = node_allocator.atConst(ancestor).parent) {
                    if (ancestor == chain_node) return .chain_contains_anchor_or_ancestor;
                }
            }
            if (index) |position| return insertionRangeFault(node_allocator, anchor_address, position);
            return null;
        }

        /// The index part of `insertionFault`: `.index_out_of_range` when `index` is past the end of
        /// `parent_address`'s children, else null. The C ABI runs this one check in every build, because
        /// a host-supplied index must never read out of bounds; the other insertion faults stay Debug-only.
        pub fn insertionRangeFault(node_allocator: NodeAllocator, parent_address: Pointer, index: usize) ?InsertionFault {
            if (index > node_allocator.atConst(parent_address).children_count) return .index_out_of_range;
            return null;
        }

        fn debugAssertInsertable(node_allocator: NodeAllocator, anchor_address: Pointer, first_node: Pointer, index: ?usize) void {
            if (comptime builtin.mode == .debug) {
                std.debug.assert(insertionFault(node_allocator, anchor_address, first_node, index) == null);
            }
        }

        pub const RemovalFault = enum {
            /// `index` is not below the parent's child count while `count` is positive.
            index_out_of_range,
            /// Fewer than `count` siblings remain from the first removed node, so the run would end past the last sibling.
            count_exceeds_remaining_siblings,
        };

        /// Misuse of a removal, or null. With `index == null`, `anchor_address` is the first node of the
        /// run of `count` siblings; otherwise it is the parent and the run starts at child `index`. Debug
        /// builds assert this is null on entry to the public removal functions; release builds never run it
        /// (the C ABI runs it in every build, because host-supplied indexes and counts must never read
        /// out of bounds).
        pub fn removalFault(node_allocator: NodeAllocator, anchor_address: Pointer, index: ?usize, count: usize) ?RemovalFault {
            if (count == 0) return null;
            if (index) |position| {
                const children_count = node_allocator.atConst(anchor_address).children_count;
                if (position >= children_count) return .index_out_of_range;
                if (count > children_count - position) return .count_exceeds_remaining_siblings;
                return null;
            }
            var last_removed = anchor_address;
            var i: usize = 1;
            while (i < count) : (i += 1) {
                last_removed = node_allocator.atConst(last_removed).next;
                if (last_removed == invalid_pointer) return .count_exceeds_remaining_siblings;
            }
            return null;
        }

        fn debugAssertRemovable(node_allocator: NodeAllocator, anchor_address: Pointer, index: ?usize, count: usize) void {
            if (comptime builtin.mode == .debug) {
                std.debug.assert(removalFault(node_allocator, anchor_address, index, count) == null);
            }
        }

        /// Insert `first_node` (and any chain attached via `.next`) immediately before `self_address`.
        /// The inserted nodes must be parentless with no prior; Debug builds assert that, and that the
        /// chain does not contain `self_address` or one of its ancestors. Release builds do not check.
        pub fn insertBefore(self_address: Pointer, node_allocator: NodeAllocator, first_node: Pointer) void {
            debugAssertInsertable(node_allocator, self_address, first_node, null);
            const self = node_allocator.at(self_address);
            const first = node_allocator.at(first_node);

            const span = attachChain(node_allocator, self.parent, first_node);

            first.prior = self.prior;
            node_allocator.at(span.last).next = self_address;
            if (self.prior != invalid_pointer) {
                node_allocator.at(self.prior).next = first_node;
            }
            self.prior = span.last;

            if (self.parent != invalid_pointer) {
                const parent_node = node_allocator.at(self.parent);
                parent_node.children_count += span.count;
                if (parent_node.first_child == self_address) {
                    parent_node.first_child = first_node;
                }
            }
        }

        /// Insert `first_node` (and any chain attached via `.next`) immediately after `self_address`.
        /// Same contract as `insertBefore`.
        pub fn insertAfter(self_address: Pointer, node_allocator: NodeAllocator, first_node: Pointer) void {
            debugAssertInsertable(node_allocator, self_address, first_node, null);
            const self = node_allocator.at(self_address);
            const first = node_allocator.at(first_node);

            const span = attachChain(node_allocator, self.parent, first_node);

            first.prior = self_address;
            node_allocator.at(span.last).next = self.next;
            if (self.next != invalid_pointer) {
                node_allocator.at(self.next).prior = span.last;
            }
            self.next = first_node;

            if (self.parent != invalid_pointer) {
                const parent_node = node_allocator.at(self.parent);
                parent_node.children_count += span.count;
                if (parent_node.last_child == self_address) {
                    parent_node.last_child = span.last;
                }
            }
        }

        /// Insert `first_node` (and any chain) into `self.children` at position `index`.
        /// Same contract as `insertBefore`; `index` must be at most `children_count`, which Debug
        /// builds assert. It cannot fail.
        pub fn insertChildren(self_address: Pointer, node_allocator: NodeAllocator, index: usize, first_node: Pointer) void {
            debugAssertInsertable(node_allocator, self_address, first_node, index);
            const self = node_allocator.at(self_address);

            if (self.first_child == invalid_pointer) {
                const span = attachChain(node_allocator, self_address, first_node);
                self.first_child = first_node;
                self.last_child = span.last;
                self.children_count = span.count;
            } else if (index == 0) {
                Self.insertBefore(self.first_child, node_allocator, first_node);
            } else {
                var previous_child = self.first_child;
                var i: usize = 1;
                while (i < index) : (i += 1) {
                    previous_child = node_allocator.at(previous_child).next;
                }
                Self.insertAfter(previous_child, node_allocator, first_node);
            }
        }

        /// Append `first_node` (and any chain) to `self.children` in the end.
        /// Same contract as `insertBefore`; the link itself is `immediateAppendChildren`.
        pub fn appendChildren(self_address: Pointer, node_allocator: NodeAllocator, first_node: Pointer) void {
            debugAssertInsertable(node_allocator, self_address, first_node, null);
            node_allocator.at(self_address).immediateAppendChildren(self_address, first_node, node_allocator);
        }

        /// Appends the parentless chain starting at `first_node` to the children of `self_address`: the
        /// one implementation of linking a chain under a parent (sibling links, parent links through
        /// `attachParent`, counts). Nothing is checked in any build mode and `structure_version` does
        /// not move. Generated parsers call it directly; `appendChildren` is this plus Debug checks.
        /// The chain must have no parent and no prior, which holds for nodes the parser just created
        /// and for chains a hook hands back detached (for example from `replaceWithChildren`). A hook
        /// must not hand back a node that is still attached to a parent.
        pub inline fn immediateAppendChildren(
            self: *Self,
            self_address: Pointer,
            first_node: Pointer,
            node_allocator: NodeAllocator,
        ) void {
            const span = attachChain(node_allocator, self_address, first_node);
            const first = node_allocator.at(first_node);
            if (self.last_child != invalid_pointer) {
                first.prior = self.last_child;
                node_allocator.at(self.last_child).next = first_node;
            } else {
                self.first_child = first_node;
                first.prior = invalid_pointer;
            }
            self.last_child = span.last;
            self.children_count += span.count;
        }

        /// Detaches the sibling run from `first_address` through `last_address` (`count` nodes) from its
        /// parent and from the siblings around it, leaving parent, prior of the first and next of the
        /// last invalid. The run keeps its own subtrees. The one implementation of detaching; it
        /// assumes the run is valid.
        fn detachRun(first_address: Pointer, last_address: Pointer, count: u32, node_allocator: NodeAllocator) void {
            const first = node_allocator.at(first_address);
            const last = node_allocator.at(last_address);
            const prior = first.prior;
            const next = last.next;

            if (prior != invalid_pointer) {
                node_allocator.at(prior).next = next;
            }
            if (next != invalid_pointer) {
                node_allocator.at(next).prior = prior;
            }
            if (first.parent != invalid_pointer) {
                const parent = node_allocator.at(first.parent);
                parent.children_count -= count;
                if (parent.first_child == first_address) parent.first_child = next;
                if (parent.last_child == last_address) parent.last_child = prior;
            }

            first.prior = invalid_pointer;
            last.next = invalid_pointer;

            node_allocator.setChainParent(first_address, invalid_pointer);
        }

        /// Internal, used only by the standard procedure `replaceWithChildren`; not part of the C ABI
        /// or any binding. Splices all children of `wrapper_address` into the wrapper's place among
        /// its siblings and detaches the wrapper, returning the head of the promoted chain, or `null`
        /// when the wrapper has no children (the wrapper is then left untouched). A wrapper without a
        /// parent leaves its children as a parentless chain.
        ///
        /// It is one pass: the sibling and parent links are rewritten once, and each child is
        /// visited once to set its new parent. Composing the public `cleanChildren`, `insertBefore` and
        /// `removeSelf` gives the same tree but visits the children several times, which dominated
        /// list-tail flattening.
        /// The children's parent links go through `setChainParent` (and the wrapper's through
        /// `setParent`), because the edit changes depth and walk cursors must re-verify after it;
        /// the version moves twice however many children are promoted.
        ///
        /// The wrapper ends fully detached (parent, prior, next, children cleared) because a
        /// replaced node stays reachable by user code, which must not see a live parent, sibling or
        /// child through it.
        pub fn immediatePromoteChildrenOverWrapper(wrapper_address: Pointer, node_allocator: NodeAllocator) ?Pointer {
            const wrapper = node_allocator.at(wrapper_address);
            const first = wrapper.first_child;
            if (first == invalid_pointer) return null;
            const last = wrapper.last_child;
            const count = wrapper.children_count;
            const prior = wrapper.prior;
            const next = wrapper.next;
            const parent = wrapper.parent;

            wrapper.first_child = invalid_pointer;
            wrapper.last_child = invalid_pointer;
            wrapper.children_count = 0;
            wrapper.prior = invalid_pointer;
            wrapper.next = invalid_pointer;
            node_allocator.setParent(wrapper_address, invalid_pointer);

            // Re-parent before the last child links to `next`: the chain ends at an invalid `next`.
            node_allocator.setChainParent(first, parent);

            node_allocator.at(first).prior = prior;
            node_allocator.at(last).next = next;
            if (prior != invalid_pointer) node_allocator.at(prior).next = first;
            if (next != invalid_pointer) node_allocator.at(next).prior = last;
            if (parent != invalid_pointer) {
                const parent_node = node_allocator.at(parent);
                if (prior == invalid_pointer) parent_node.first_child = first;
                if (next == invalid_pointer) parent_node.last_child = last;
                parent_node.children_count += count - 1;
            }

            return first;
        }

        /// Remove `count` consecutive siblings starting at `self_address`, detaching them from parent
        /// and sibling chains. Returns the head of the detached chain, or `invalid_pointer` when `count == 0`.
        /// `count` must not exceed the siblings remaining from `self_address`; Debug builds assert that.
        /// Release builds do not check. It cannot fail.
        pub fn remove(self_address: Pointer, node_allocator: NodeAllocator, count: usize) Pointer {
            if (count == 0) {
                return invalid_pointer;
            }
            debugAssertRemovable(node_allocator, self_address, null, count);

            var last_removed_address = self_address;
            var i: usize = 1;
            while (i < count) : (i += 1) {
                last_removed_address = node_allocator.at(last_removed_address).next;
            }

            detachRun(self_address, last_removed_address, @intCast(count), node_allocator);
            return self_address;
        }

        /// Remove `self_address`, detaching it from its parent and siblings. It cannot fail.
        pub fn removeSelf(self_address: Pointer, node_allocator: NodeAllocator) void {
            detachRun(self_address, self_address, 1, node_allocator);
        }

        /// Remove `count` consecutive children starting at `index`, detaching them from parent
        /// and sibling chains. Returns the head of the detached chain, or `invalid_pointer` when `count == 0`.
        /// `index + count` must not exceed the child count; Debug builds assert that. Release builds do
        /// not check. It cannot fail.
        pub fn removeChildren(self_address: Pointer, node_allocator: NodeAllocator, index: usize, count: usize) Pointer {
            if (count == 0) {
                return invalid_pointer;
            }
            debugAssertRemovable(node_allocator, self_address, index, count);

            var first_removed = node_allocator.at(self_address).first_child;
            var i: usize = 0;
            while (i < index) : (i += 1) {
                first_removed = node_allocator.at(first_removed).next;
            }
            return Self.remove(first_removed, node_allocator, count);
        }

        /// Remove one child at `index`, detaching it from parent and sibling chains.
        /// Returns the removed node address. `index` must be below the child count; Debug builds assert that.
        pub fn removeChild(self_address: Pointer, node_allocator: NodeAllocator, index: usize) Pointer {
            return Self.removeChildren(self_address, node_allocator, index, 1);
        }

        /// Clean all children detaching them from parent and sibling chains.
        /// Returns the head of the detached chain, or `invalid_pointer` when there are no children.
        pub fn cleanChildren(self_address: Pointer, node_allocator: NodeAllocator) Pointer {
            const self = node_allocator.at(self_address);
            const first = self.first_child;
            if (first == invalid_pointer) return invalid_pointer;
            const last = self.last_child;

            self.first_child = invalid_pointer;
            self.last_child = invalid_pointer;
            self.children_count = 0;

            node_allocator.at(first).prior = invalid_pointer;
            node_allocator.at(last).next = invalid_pointer;

            node_allocator.setChainParent(first, invalid_pointer);

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

        /// Returns true when `self_address` or any descendant carries a
        /// semantic error mark. Parents are never auto-marked; hooks call
        /// this to avoid cascading diagnostics. AST mode only: no-AST
        /// temporary children are checked directly through their flags.
        pub fn hasSemanticErrorSubtree(self_address: Pointer, node_allocator: NodeAllocator) bool {
            if (comptime !with_ast) {
                @compileError("hasSemanticErrorSubtree requires AST construction; in no-AST mode check child is_semantic_error flags directly");
            }
            return hasMarkedSubtree(self_address, node_allocator, "is_semantic_error");
        }

        /// `hasSemanticErrorSubtree` for the recovery mark: true when
        /// `self_address` or any descendant is a node syntax-error recovery
        /// kept in place of damaged input. AST mode only.
        pub fn hasRecoveredSubtree(self_address: Pointer, node_allocator: NodeAllocator) bool {
            if (comptime !with_ast) {
                @compileError("hasRecoveredSubtree requires AST construction; in no-AST mode check child is_recovered flags directly");
            }
            return hasMarkedSubtree(self_address, node_allocator, "is_recovered");
        }

        fn hasMarkedSubtree(self_address: Pointer, node_allocator: NodeAllocator, comptime flag: []const u8) bool {
            var current = self_address;
            while (true) {
                const node = node_allocator.at(current);
                if (@field(node, flag)) return true;
                if (node.first_child != invalid_pointer) {
                    current = node.first_child;
                    continue;
                }
                var cursor = current;
                while (true) {
                    if (cursor == self_address) return false;
                    const cursor_node = node_allocator.at(cursor);
                    if (cursor_node.next != invalid_pointer) {
                        current = cursor_node.next;
                        break;
                    }
                    if (cursor_node.parent == invalid_pointer) return false;
                    cursor = cursor_node.parent;
                }
            }
        }
    };
}

// Test types
const TestPayload = root.data_structures.Payload;
const TestNode = Node(TestPayload, true);
const TestASTAllocator = ASTAllocator(TestPayload);

test "the recovery mark fits the padding beside the semantic error flag" {
    // Two words of text span, five links, then the count, variable and both
    // flags packed into one word: a second flag must not grow the node.
    const EmptyNode = Node(struct {}, true);
    try std.testing.expectEqual(7 * @sizeOf(usize) + 8, @sizeOf(EmptyNode));
}

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

test "AST reservation tracks the request instead of the maximum" {
    if (comptime !root.parser.is_ast_enabled) return;
    if (comptime !TestASTAllocator.supports_reserved_arena) return;
    var node_allocator = try TestASTAllocator.initWithCapacity(std.testing.allocator, 0);
    defer node_allocator.deinit(std.testing.allocator);

    try node_allocator.ensureCapacity(2048);
    try std.testing.expect(node_allocator.totalNodeCapacity() >= 2048);
    try std.testing.expect(node_allocator.totalNodeCapacity() < TestASTAllocator.capacity_limit);

    // Between parses the counter is rewound, so a larger request re-reserves.
    try node_allocator.ensureCapacity(9000);
    try std.testing.expect(node_allocator.totalNodeCapacity() >= 9000);

    // Demand past the reservation appends segments without relocating
    // anything: the earlier node still reads back.
    _ = try node_allocator.create(0, 1);
    node_allocator.at(0).text_length = 41;
    try node_allocator.ensureCapacity(node_allocator.totalNodeCapacity() + 5000);
    try std.testing.expectEqual(@as(usize, 41), node_allocator.at(0).text_length);
}

test "procedure hook current node pointer survives node allocation" {
    if (comptime !root.parser.is_ast_enabled) return;
    var node_allocator = try TestASTAllocator.initWithCapacity(std.testing.allocator, 1);
    defer node_allocator.deinit(std.testing.allocator);
    var dummy_runtime: root.data_structures.RuntimeContext = .{ .io = std.testing.io, .arena_allocator = std.testing.allocator };
    var context = Context{ .runtime_context = &dummy_runtime };
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

var test_token_buffer: [root.data_structures.Token.Storage.capacity]u8 = undefined;
var test_token_sources: [root.data_structures.Token.Storage.capacity]usize = undefined;

fn testContext(node_allocator: *TestASTAllocator, text: []u8, runtime_context: *root.data_structures.RuntimeContext) Context {
    var context = Context{ .runtime_context = runtime_context };
    context.node_allocator = node_allocator;
    if (comptime root.config.indentation_syntax) {
        context.token.attach(.{ .buffer = &test_token_buffer, .sources = &test_token_sources });
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
        return testContext(&self.node_allocator, self.text, self.runtime_context);
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
            TestNode.appendChildren(root_node, &node_allocator, child_addr);
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
                TestNode.appendChildren(parent_addr, &node_allocator, child_addr);
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

    const removed_head = TestNode.remove(2, node_allocator, 2);

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

    TestNode.insertBefore(3, node_allocator, new_a);

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
    TestNode.insertAfter(2, node_allocator, new_a);

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

fn testInsertChildren(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    const parent = asSize(1); // child1 (has 3 children: 5, 6, 7)

    const new_node = fixture.free_nodes[0];

    // Insert at the beginning (index 0)
    TestNode.insertChildren(parent, node_allocator, 0, new_node);

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
    TestNode.insertChildren(parent, node_allocator, 4, new_node2);

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
    TestNode.appendChildren(6, &fixture.node_allocator, nested_b);
    TestNode.appendChildren(6, &fixture.node_allocator, nested_empty);
    TestNode.appendChildren(6, &fixture.node_allocator, nested_c);

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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var runtime_context = root.data_structures.RuntimeContext{
        .io = undefined,
        .arena_allocator = arena.allocator(),
    };
    var context = testContext(&node_allocator, input[0..], &runtime_context);

    const root_node = try node_allocator.create(0, 0);
    var parent = root_node;
    for (1..depth) |_| {
        const child = try node_allocator.create(0, 0);
        node_allocator.at(parent).immediateAppendChildren(parent, child, &node_allocator);
        parent = child;
    }
    node_allocator.at(parent).text_length = 1;

    try std.testing.expectEqualStrings("Z", try TestNode.augmentedText(root_node, &context));
}

fn expectDetached(fixture: *TestFixture, address: TestNode.Pointer) !void {
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[address].parent);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[address].prior);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[address].next);
}

fn testDetachedNodeInvariant(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;

    // removeSelf: a lone removed node is fully detached.
    TestNode.removeSelf(2, node_allocator);
    try expectDetached(fixture, 2);
    try std.testing.expectEqual(asSize(3), fixture.nodes[1].next);
    try std.testing.expectEqual(asSize(1), fixture.nodes[3].prior);

    // remove(count): the removed chain has no parent and is cut off from
    // the tree at both ends; only the links inside the chain remain.
    const head = TestNode.remove(3, node_allocator, 2);
    try std.testing.expectEqual(asSize(3), head);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[3].parent);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[3].prior);
    try std.testing.expectEqual(asSize(4), fixture.nodes[3].next);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[4].parent);
    try std.testing.expectEqual(asSize(3), fixture.nodes[4].prior);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[4].next);
}

test "removeSelf and remove leave detached nodes without tree links" {
    try runWithContext(testDetachedNodeInvariant);
}

fn testRemoveSelfKeepsSubtreeAndFixesParent(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    const wrapper: TestNode.Pointer = 2; // middle child of root, with children 8, 9, 10

    TestNode.removeSelf(wrapper, node_allocator);

    try expectDetached(fixture, wrapper);
    // Siblings and the former parent skip the wrapper.
    try std.testing.expectEqual(asSize(3), fixture.nodes[1].next);
    try std.testing.expectEqual(asSize(1), fixture.nodes[3].prior);
    try std.testing.expectEqual(@as(u32, 3), fixture.nodes[fixture.root].children_count);
    // The wrapper keeps its own subtree.
    try std.testing.expectEqual(asSize(8), fixture.nodes[wrapper].first_child);
    try std.testing.expectEqual(@as(u32, 3), fixture.nodes[wrapper].children_count);
    try std.testing.expectEqual(wrapper, fixture.nodes[8].parent);

    // Removing the first and the last child moves the parent's ends.
    TestNode.removeSelf(1, node_allocator);
    try std.testing.expectEqual(asSize(3), fixture.nodes[fixture.root].first_child);
    try expectDetached(fixture, 1);
    TestNode.removeSelf(4, node_allocator);
    try std.testing.expectEqual(asSize(3), fixture.nodes[fixture.root].last_child);
    try std.testing.expectEqual(asSize(3), fixture.nodes[fixture.root].first_child);
    try expectDetached(fixture, 4);

    // A node that is already detached stays detached.
    TestNode.removeSelf(wrapper, node_allocator);
    try expectDetached(fixture, wrapper);
}

test "removeSelf detaches the node, keeps its subtree and fixes the parent" {
    try runWithContext(testRemoveSelfKeepsSubtreeAndFixesParent);
}

fn testRemoveBumpsStructureVersion(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    const before = node_allocator.structure_version;
    TestNode.removeSelf(2, node_allocator);
    try std.testing.expect(node_allocator.structure_version != before);
}

test "removeSelf bumps the structure version" {
    try runWithContext(testRemoveBumpsStructureVersion);
}

fn testCleanChildrenBumpsStructureVersion(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    const parent = fixture.free_nodes[0];
    TestNode.appendChildren(parent, node_allocator, fixture.free_nodes[1]);

    const before = node_allocator.structure_version;
    _ = TestNode.cleanChildren(parent, node_allocator);
    try std.testing.expect(node_allocator.structure_version != before);
}

test "cleanChildren bumps the structure version" {
    try runWithContext(testCleanChildrenBumpsStructureVersion);
}

fn testRemovingSeveralSiblingsBumpsStructureVersion(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    const parent = fixture.free_nodes[0];
    const first = fixture.free_nodes[1];
    TestNode.appendChildren(parent, node_allocator, first);
    TestNode.appendChildren(parent, node_allocator, fixture.free_nodes[2]);
    TestNode.appendChildren(parent, node_allocator, fixture.free_nodes[3]);

    const before = node_allocator.structure_version;
    _ = TestNode.remove(first, node_allocator, 2);
    try std.testing.expect(node_allocator.structure_version != before);
}

test "remove of several siblings bumps the structure version" {
    try runWithContext(testRemovingSeveralSiblingsBumpsStructureVersion);
}

fn testChainEditsBumpStructureVersionOnce(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;

    // A parent with four children: cleaning them re-parents four nodes in one bump.
    const parent = fixture.free_nodes[0];
    for (fixture.free_nodes[1..5]) |child| TestNode.appendChildren(parent, node_allocator, child);
    var before = node_allocator.structure_version;
    _ = TestNode.cleanChildren(parent, node_allocator);
    try std.testing.expectEqual(before + 1, node_allocator.structure_version);

    // Detaching a run of three siblings is one bump as well. Cleaning left the four siblings
    // linked as one chain, so appending its head re-attaches all of them.
    TestNode.appendChildren(parent, node_allocator, fixture.free_nodes[1]);
    before = node_allocator.structure_version;
    _ = TestNode.remove(fixture.free_nodes[1], node_allocator, 3);
    try std.testing.expectEqual(before + 1, node_allocator.structure_version);
    // The sibling after the run keeps its parent and stays the parent's only child, unlinked from the run.
    const survivor = fixture.free_nodes[4];
    try std.testing.expectEqual(parent, fixture.nodes[survivor].parent);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[survivor].prior);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[survivor].next);
    try std.testing.expectEqual(survivor, fixture.nodes[parent].first_child);
    try std.testing.expectEqual(survivor, fixture.nodes[parent].last_child);
    try std.testing.expectEqual(@as(u32, 1), fixture.nodes[parent].children_count);
    for (fixture.free_nodes[1..4]) |detached| {
        try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[detached].parent);
    }

    // Promoting children over a wrapper is one bump for the wrapper and one for the whole chain,
    // however many children are promoted.
    const wrapper = fixture.free_nodes[5];
    TestNode.appendChildren(parent, node_allocator, wrapper);
    for (fixture.free_nodes[6..10]) |child| TestNode.appendChildren(wrapper, node_allocator, child);
    const following = fixture.free_nodes[10];
    TestNode.appendChildren(parent, node_allocator, following);
    before = node_allocator.structure_version;
    try std.testing.expectEqual(@as(?TestNode.Pointer, fixture.free_nodes[6]), TestNode.immediatePromoteChildrenOverWrapper(wrapper, node_allocator));
    try std.testing.expectEqual(before + 2, node_allocator.structure_version);
    for (fixture.free_nodes[6..10]) |child| {
        try std.testing.expectEqual(parent, fixture.nodes[child].parent);
    }
    try expectDetached(fixture, wrapper);
    // The promoted chain sits between the survivor and the wrapper's former next sibling.
    try std.testing.expectEqual(parent, fixture.nodes[following].parent);
    try std.testing.expectEqual(fixture.free_nodes[9], fixture.nodes[following].prior);
    try std.testing.expectEqual(following, fixture.nodes[fixture.free_nodes[9]].next);
    try std.testing.expectEqual(survivor, fixture.nodes[fixture.free_nodes[6]].prior);
    try std.testing.expectEqual(following, fixture.nodes[parent].last_child);
}

test "multi-node edits bump the structure version once per operation" {
    try runWithContext(testChainEditsBumpStructureVersionOnce);
}

fn testAttachingKeepsStructureVersion(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;

    const parent = fixture.free_nodes[0];
    const first = fixture.free_nodes[1];
    const second = fixture.free_nodes[2];
    fixture.nodes[first].next = second;
    fixture.nodes[second].prior = first;

    const before = node_allocator.structure_version;
    node_allocator.at(parent).immediateAppendChildren(parent, first, node_allocator);

    // Attaching parentless nodes cannot move a walk position, so the version stays.
    try std.testing.expectEqual(before, node_allocator.structure_version);
    try std.testing.expectEqual(first, fixture.nodes[parent].first_child);
    try std.testing.expectEqual(second, fixture.nodes[parent].last_child);
    try std.testing.expectEqual(@as(u32, 2), fixture.nodes[parent].children_count);
    try std.testing.expectEqual(parent, fixture.nodes[first].parent);
    try std.testing.expectEqual(parent, fixture.nodes[second].parent);

    // Every public way to attach a parentless chain shares that: append after existing children,
    // insert before, insert after and insert at an index.
    const third = fixture.free_nodes[3];
    TestNode.appendChildren(parent, node_allocator, third);
    try std.testing.expectEqual(third, fixture.nodes[parent].last_child);
    try std.testing.expectEqual(second, fixture.nodes[third].prior);
    try std.testing.expectEqual(parent, fixture.nodes[third].parent);

    const fourth = fixture.free_nodes[4];
    TestNode.insertBefore(first, node_allocator, fourth);
    const fifth = fixture.free_nodes[5];
    TestNode.insertAfter(first, node_allocator, fifth);
    const sixth = fixture.free_nodes[6];
    TestNode.insertChildren(parent, node_allocator, 2, sixth);
    try std.testing.expectEqual(before, node_allocator.structure_version);
    try std.testing.expectEqual(@as(u32, 6), fixture.nodes[parent].children_count);
    try std.testing.expectEqual(fourth, fixture.nodes[parent].first_child);
    for ([_]TestNode.Pointer{ fourth, fifth, sixth }) |attached| {
        try std.testing.expectEqual(parent, fixture.nodes[attached].parent);
    }
    // Order: fourth, first, sixth, fifth, second, third.
    const expected = [_]TestNode.Pointer{ fourth, first, sixth, fifth, second, third };
    var current = fixture.nodes[parent].first_child;
    for (expected) |want| {
        try std.testing.expectEqual(want, current);
        current = fixture.nodes[current].next;
    }
    try std.testing.expectEqual(TestNode.invalid_pointer, current);
}

test "attaching a parentless chain leaves the structure version unchanged" {
    try runWithContext(testAttachingKeepsStructureVersion);
}

fn testInsertionFaults(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    // A head that still has a parent or a prior.
    try std.testing.expectEqual(
        @as(?TestFixtureFault, .chain_head_has_parent),
        TestNode.insertionFault(node_allocator, fixture.root, 2, null),
    );
    const detached = fixture.free_nodes[0];
    fixture.nodes[detached].prior = 3;
    try std.testing.expectEqual(
        @as(?TestFixtureFault, .chain_head_has_prior),
        TestNode.insertionFault(node_allocator, fixture.root, detached, null),
    );
    fixture.nodes[detached].prior = TestNode.invalid_pointer;

    // A chain holding the anchor or one of its ancestors: node 8 sits under 2, which sits under the root.
    const subtree_root = TestNode.remove(2, node_allocator, 1);
    try std.testing.expectEqual(asSize(2), subtree_root);
    try std.testing.expectEqual(
        @as(?TestFixtureFault, .chain_contains_anchor_or_ancestor),
        TestNode.insertionFault(node_allocator, 8, subtree_root, null),
    );
    try std.testing.expectEqual(
        @as(?TestFixtureFault, .chain_contains_anchor_or_ancestor),
        TestNode.insertionFault(node_allocator, subtree_root, subtree_root, null),
    );
    // The same chain is fine under an unrelated node.
    try std.testing.expectEqual(@as(?TestFixtureFault, null), TestNode.insertionFault(node_allocator, 3, subtree_root, null));

    // An index past the end of the children.
    const count = fixture.nodes[fixture.root].children_count;
    try std.testing.expectEqual(@as(?TestFixtureFault, null), TestNode.insertionFault(node_allocator, fixture.root, detached, count));
    try std.testing.expectEqual(
        @as(?TestFixtureFault, .index_out_of_range),
        TestNode.insertionFault(node_allocator, fixture.root, detached, count + 1),
    );
}

const TestFixtureFault = TestNode.InsertionFault;

test "insertion misuse is detected by the Debug check" {
    try runWithContext(testInsertionFaults);
}

fn testRemovalFaults(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    const children_count = fixture.nodes[fixture.root].children_count;
    try std.testing.expectEqual(@as(u32, 4), children_count);

    // A run of siblings that ends past the last sibling: node 4 is the last child of the root.
    try std.testing.expectEqual(@as(?TestRemovalFault, null), TestNode.removalFault(node_allocator, 4, null, 1));
    try std.testing.expectEqual(
        @as(?TestRemovalFault, .count_exceeds_remaining_siblings),
        TestNode.removalFault(node_allocator, 4, null, 2),
    );

    // A run of children addressed by index.
    try std.testing.expectEqual(@as(?TestRemovalFault, null), TestNode.removalFault(node_allocator, fixture.root, 1, 3));
    try std.testing.expectEqual(
        @as(?TestRemovalFault, .count_exceeds_remaining_siblings),
        TestNode.removalFault(node_allocator, fixture.root, 1, 4),
    );
    try std.testing.expectEqual(
        @as(?TestRemovalFault, .index_out_of_range),
        TestNode.removalFault(node_allocator, fixture.root, children_count, 1),
    );
    // Removing nothing is never a fault.
    try std.testing.expectEqual(@as(?TestRemovalFault, null), TestNode.removalFault(node_allocator, fixture.root, children_count + 5, 0));
}

const TestRemovalFault = TestNode.RemovalFault;

fn testRemoveChildrenByIndex(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;
    // The root's children are 1, 2, 3, 4: removing two from index 1 detaches 2 and 3.
    const head = TestNode.removeChildren(fixture.root, node_allocator, 1, 2);
    try std.testing.expectEqual(asSize(2), head);
    try std.testing.expectEqual(@as(u32, 2), fixture.nodes[fixture.root].children_count);
    try std.testing.expectEqual(asSize(1), fixture.nodes[fixture.root].first_child);
    try std.testing.expectEqual(asSize(4), fixture.nodes[1].next);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[head].parent);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[head].prior);

    try std.testing.expectEqual(TestNode.invalid_pointer, TestNode.removeChildren(fixture.root, node_allocator, 0, 0));
    try std.testing.expectEqual(asSize(4), TestNode.removeChild(fixture.root, node_allocator, 1));
    try std.testing.expectEqual(@as(u32, 1), fixture.nodes[fixture.root].children_count);
}

test "removeChildren and removeChild detach children by index" {
    try runWithContext(testRemoveChildrenByIndex);
}

test "removal misuse is detected by the Debug check" {
    try runWithContext(testRemovalFaults);
}

fn testImmediateAppendChildren(fixture: *TestFixture) !void {
    const node_allocator = &fixture.node_allocator;

    const parent = fixture.free_nodes[0];
    const child1 = fixture.free_nodes[1];
    const child2 = fixture.free_nodes[2];

    // Append the first child
    node_allocator.at(parent).immediateAppendChildren(parent, child1, node_allocator);
    try std.testing.expectEqual(child1, fixture.nodes[parent].first_child);
    try std.testing.expectEqual(child1, fixture.nodes[parent].last_child);
    try std.testing.expectEqual(parent, fixture.nodes[child1].parent);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[child1].prior);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[child1].next);

    // Append a second child
    node_allocator.at(parent).immediateAppendChildren(parent, child2, node_allocator);
    try std.testing.expectEqual(child1, fixture.nodes[parent].first_child);
    try std.testing.expectEqual(child2, fixture.nodes[parent].last_child);
    try std.testing.expectEqual(parent, fixture.nodes[child2].parent);
    try std.testing.expectEqual(child1, fixture.nodes[child2].prior);
    try std.testing.expectEqual(child2, fixture.nodes[child1].next);
    try std.testing.expectEqual(TestNode.invalid_pointer, fixture.nodes[child2].next);
    try std.testing.expectEqual(@as(u32, 2), fixture.nodes[parent].children_count);
}

test "immediateAppendChildren" {
    try runWithContext(testImmediateAppendChildren);
}
