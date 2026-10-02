const std = @import("std");
const root = @import("galley");

/// Shared post-parse tree walking: the single gate for depth-first traversal
/// of an AST. Every consumer (examples, language bindings) drives `walkNext`
/// with a host-owned cursor instead of allocating a native walker: the
/// cursor is a 40-byte value the host keeps between steps, each step is one
/// call, and no native memory is allocated for the walk.
///
/// The cursor follows the live links in the node storage on every step, so
/// edits between steps are visible; a step whose position is no longer
/// inside the walk's root (removed, or moved elsewhere) raises
/// `WalkPositionDetached` (surfaced as invalid node through the C ABI).
///
/// AST-only: there is no persistent tree without AST construction. Calling
/// any function in a no-AST build is a compile error.
pub const Cursor = extern struct {
    /// Parse generation the walk position belongs to. The C door checks it
    /// against the live parse before every step; the walker itself never
    /// reads it.
    generation: u64,
    /// Address the walk is rooted at: stepping never yields a node outside
    /// this node's subtree.
    root: u64,
    /// Last yielded node; meaningful in the yielded states only.
    current: u64,
    /// Depth of `current` below `root`.
    depth: u32,
    state: u16,
    options: u8,
    is_semantic_error: u8,
    /// `node_allocator.structure_version` as of the last successful step.
    /// When a later step sees a different value, a parent link was written
    /// underneath the walk and the position is re-verified before stepping.
    structure_version: u64,
};

comptime {
    std.debug.assert(@sizeOf(Cursor) == 40);
}

pub const state_not_started: u16 = 0;
pub const state_yielded: u16 = 1;
pub const state_yielded_skip_children: u16 = 2;
pub const state_done: u16 = 3;
pub const option_skip_semantic_errors: u8 = 1;

pub const WalkError = error{ InvalidCursor, WalkPositionDetached };

const Node = root.data_structures.Node;

const Position = struct { address: Node.Pointer, depth: u32 };

/// Advances `cursor` to the next node in pre-order, writing the position
/// into the cursor and returning true, or marks it done and returns false.
/// Validates the cursor on every call: an unusable cursor fails with
/// `error.InvalidCursor` and is left unchanged.
pub fn walkNext(node_allocator: Node.NodeAllocator, cursor: *Cursor) WalkError!bool {
    if (comptime !root.parser.is_ast_enabled) {
        @compileError("walkNext requires AST construction; without a persistent tree there is nothing to walk");
    }
    const node_count: u64 = node_allocator.counter;
    if (cursor.state > state_done) return error.InvalidCursor;
    if (cursor.options & ~option_skip_semantic_errors != 0) return error.InvalidCursor;
    if (cursor.root >= node_count) return error.InvalidCursor;
    const has_current = cursor.state == state_yielded or cursor.state == state_yielded_skip_children;
    if (has_current) {
        if (cursor.current >= node_count) return error.InvalidCursor;
        // Depth is host-held: bound it before `depth + 1` could overflow
        // and before any climb could run away.
        if (cursor.depth >= node_count) return error.InvalidCursor;
        // A parent write since the last stamped step may have moved this
        // position out of the walk's subtree (a removed node, or one
        // reparented elsewhere). Re-derive the position from its parent
        // chain before reading any other link of current.
        if (cursor.structure_version != node_allocator.structure_version) {
            try verifyPosition(node_allocator, cursor);
        }
    }

    const root_address: Node.Pointer = @intCast(cursor.root);
    var candidate: ?Position = switch (cursor.state) {
        state_done => return false,
        state_not_started => .{ .address = root_address, .depth = 0 },
        state_yielded => try descendOrAdvance(node_allocator, root_address, @intCast(cursor.current), cursor.depth),
        state_yielded_skip_children => try advance(node_allocator, root_address, @intCast(cursor.current), cursor.depth),
        else => unreachable, // validated above
    };
    const skip_semantic_errors = cursor.options & option_skip_semantic_errors != 0;
    while (candidate) |position| {
        const node = node_allocator.at(position.address);
        if (skip_semantic_errors and node.is_semantic_error) {
            candidate = try advance(node_allocator, root_address, position.address, position.depth);
            continue;
        }
        cursor.current = position.address;
        cursor.depth = position.depth;
        cursor.state = state_yielded;
        cursor.is_semantic_error = @intFromBool(node.is_semantic_error);
        cursor.structure_version = node_allocator.structure_version;
        return true;
    }
    cursor.state = state_done;
    cursor.is_semantic_error = 0;
    cursor.structure_version = node_allocator.structure_version;
    return false;
}

/// Re-derives that `current` still sits exactly `cursor.depth` parent links
/// below `root`, run when the structure changed since the cursor was
/// stamped. The climb must find a live parent at every link — a cleared
/// parent means the node was removed — and land on `root` exactly, so a
/// position moved elsewhere also fails instead of steering the walk out of
/// its subtree.
fn verifyPosition(node_allocator: Node.NodeAllocator, cursor: *const Cursor) WalkError!void {
    if (comptime !root.parser.is_ast_enabled) {
        @compileError("walkNext requires AST construction; without a persistent tree there is nothing to walk");
    }
    var address: Node.Pointer = @intCast(cursor.current);
    var remaining = cursor.depth;
    while (remaining > 0) {
        const parent = node_allocator.at(address).parent;
        if (parent == Node.invalid_pointer) return error.WalkPositionDetached;
        address = parent;
        remaining -= 1;
    }
    if (address != cursor.root) return error.WalkPositionDetached;
}

fn descendOrAdvance(node_allocator: Node.NodeAllocator, root_address: Node.Pointer, current: Node.Pointer, depth: u32) WalkError!?Position {
    if (comptime !root.parser.is_ast_enabled) {
        @compileError("walkNext requires AST construction; without a persistent tree there is nothing to walk");
    }
    const first_child = node_allocator.at(current).first_child;
    if (first_child != Node.invalid_pointer) return .{ .address = first_child, .depth = depth + 1 };
    return advance(node_allocator, root_address, current, depth);
}

/// Next pre-order position after `start`'s subtree, or null when the walk
/// is done. Climbs the live parent links: a start whose parent and next
/// were cleared (a removed node) raises `WalkPositionDetached`, as does a
/// climb that reaches `start_depth` levels above a node that is not the
/// walk's root.
fn advance(node_allocator: Node.NodeAllocator, root_address: Node.Pointer, start: Node.Pointer, start_depth: u32) WalkError!?Position {
    if (comptime !root.parser.is_ast_enabled) {
        @compileError("walkNext requires AST construction; without a persistent tree there is nothing to walk");
    }
    var address = start;
    var depth = start_depth;
    while (depth > 0) {
        const node = node_allocator.at(address);
        if (node.next != Node.invalid_pointer) return .{ .address = node.next, .depth = depth };
        if (node.parent == Node.invalid_pointer) return error.WalkPositionDetached;
        address = node.parent;
        depth -= 1;
    }
    if (address != root_address) return error.WalkPositionDetached;
    return null;
}

/// Depth-first walk over one subtree, as a plain value: the node allocator
/// plus the 40-byte cursor, no allocation and nothing to deinit. This is the
/// in-process convenience wrapper over `walkNext`; bindings drive the cursor
/// through the C ABI instead.
pub const TreeWalker = struct {
    pub const Step = struct {
        address: Node.Pointer,
        depth: u32,
        is_semantic_error: bool,
    };

    pub const Options = struct {
        /// When set, subtrees rooted at semantic-error nodes are pruned
        /// without yielding them, so validation and aggregation passes skip
        /// invalid parts without checking flags themselves.
        skip_semantic_error_subtrees: bool = false,
    };

    node_allocator: Node.NodeAllocator,
    cursor: Cursor,

    pub fn init(node_allocator: Node.NodeAllocator, root_address: Node.Pointer, options: Options) TreeWalker {
        if (comptime !root.parser.is_ast_enabled) {
            @compileError("TreeWalker requires AST construction; without a persistent tree there is nothing to walk");
        }
        return .{
            .node_allocator = node_allocator,
            .cursor = .{
                .generation = 0,
                .root = root_address,
                .current = 0,
                .depth = 0,
                .state = state_not_started,
                .options = if (options.skip_semantic_error_subtrees) option_skip_semantic_errors else 0,
                .is_semantic_error = 0,
                .structure_version = 0,
            },
        };
    }

    /// Yields the next node in pre-order, or null when the walk is done.
    pub fn next(self: *TreeWalker) WalkError!?Step {
        if (comptime !root.parser.is_ast_enabled) {
            @compileError("TreeWalker requires AST construction; without a persistent tree there is nothing to walk");
        }
        if (!try walkNext(self.node_allocator, &self.cursor)) return null;
        return .{
            .address = @intCast(self.cursor.current),
            .depth = self.cursor.depth,
            .is_semantic_error = self.cursor.is_semantic_error != 0,
        };
    }

    /// Prunes the children of the last yielded node: the following `next`
    /// continues with its next sibling. No effect without a last step.
    pub fn skipChildren(self: *TreeWalker) void {
        if (comptime !root.parser.is_ast_enabled) {
            @compileError("TreeWalker requires AST construction; without a persistent tree there is nothing to walk");
        }
        if (self.cursor.state == state_yielded) self.cursor.state = state_yielded_skip_children;
    }
};
