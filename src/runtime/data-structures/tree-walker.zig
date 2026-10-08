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
/// A walk belongs to the parse of the tree it was created over: every step,
/// including one on a finished walk, first compares the cursor's generation
/// with the generation the node storage holds and raises `StaleTree` when a
/// later parse has begun, since that parse recycles the very addresses the
/// cursor holds. The check lives in `walkNext`, so no caller can step
/// without it. It cannot close a concurrent parse on another thread: nothing
/// here holds the session lock, so a walk running while a parse recycles the
/// storage is a data race that only a read guard (or the C door's lease)
/// prevents.
///
/// AST-only: there is no persistent tree without AST construction. Calling
/// any function in a no-AST build is a compile error.
pub const Cursor = extern struct {
    /// Parse generation the walk position belongs to: the generation of the
    /// storage when the walk was created (`galley_root_node` and
    /// `galley_hook_generation` report the same value to hosts). `walkNext`
    /// compares it with the storage's generation before every step, and the
    /// C door compares it with the door's live tree before that.
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
    /// `flag_*` bits of `current`; meaningful in the yielded states only.
    flags: u8,
    /// `node_allocator.structure_version` as of the last successful step.
    /// When a later step sees a different value, a parent link was re-pointed
    /// or cleared underneath the walk and the position is re-verified before
    /// stepping. Attaching a parentless chain does not bump it.
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
pub const option_skip_recovered: u8 = 2;
pub const option_mask: u8 = option_skip_semantic_errors | option_skip_recovered;
pub const flag_semantic_error: u8 = 1;
pub const flag_recovered: u8 = 2;

pub const WalkError = error{ InvalidCursor, WalkPositionDetached, StaleTree };

const Node = root.data_structures.Node;

const Position = struct { address: Node.Pointer, depth: u32 };

/// Advances `cursor` to the next node in pre-order, writing the position
/// into the cursor and returning true, or marks it done and returns false.
/// Validates the cursor on every call, first of all its generation: a cursor
/// created over an earlier parse fails with `error.StaleTree`, whether or not
/// its walk had finished. Any other unusable cursor fails with
/// `error.InvalidCursor`. A failed call leaves the cursor unchanged.
pub fn walkNext(node_allocator: Node.NodeAllocator, cursor: *Cursor) WalkError!bool {
    if (comptime !root.parser.is_ast_enabled) {
        @compileError("walkNext requires AST construction; without a persistent tree there is nothing to walk");
    }
    if (cursor.generation != node_allocator.generation) return error.StaleTree;
    const node_count: u64 = node_allocator.counter;
    if (cursor.state > state_done) return error.InvalidCursor;
    if (cursor.options & ~option_mask != 0) return error.InvalidCursor;
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
    const skip_recovered = cursor.options & option_skip_recovered != 0;
    while (candidate) |position| {
        const node = node_allocator.at(position.address);
        if ((skip_semantic_errors and node.is_semantic_error) or (skip_recovered and node.is_recovered)) {
            candidate = try advance(node_allocator, root_address, position.address, position.depth);
            continue;
        }
        cursor.current = position.address;
        cursor.depth = position.depth;
        cursor.state = state_yielded;
        cursor.flags = (if (node.is_semantic_error) flag_semantic_error else 0) |
            (if (node.is_recovered) flag_recovered else 0);
        cursor.structure_version = node_allocator.structure_version;
        return true;
    }
    cursor.state = state_done;
    cursor.flags = 0;
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
///
/// The walker belongs to the parse of the tree it was created over: it
/// captures the storage's generation in `init`, and stepping it after the
/// session parsed again (successfully or not) fails with `error.StaleTree`,
/// also once it had finished. Create a new walker over the current tree.
pub const TreeWalker = struct {
    pub const Step = struct {
        address: Node.Pointer,
        depth: u32,
        is_semantic_error: bool,
        is_recovered: bool,
    };

    pub const Options = struct {
        /// When set, subtrees rooted at semantic-error nodes are pruned
        /// without yielding them, so validation and aggregation passes skip
        /// invalid parts without checking flags themselves.
        skip_semantic_error_subtrees: bool = false,
        /// The same pruning for nodes syntax-error recovery kept in place of
        /// damaged input: the walk then yields only undamaged nodes.
        skip_recovered_subtrees: bool = false,
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
                .generation = node_allocator.generation,
                .root = root_address,
                .current = 0,
                .depth = 0,
                .state = state_not_started,
                .options = (if (options.skip_semantic_error_subtrees) option_skip_semantic_errors else 0) |
                    (if (options.skip_recovered_subtrees) option_skip_recovered else 0),
                .flags = 0,
                .structure_version = 0,
            },
        };
    }

    /// Yields the next node in pre-order, or null when the walk is done.
    /// `error.StaleTree` once the session has parsed again.
    pub fn next(self: *TreeWalker) WalkError!?Step {
        if (comptime !root.parser.is_ast_enabled) {
            @compileError("TreeWalker requires AST construction; without a persistent tree there is nothing to walk");
        }
        if (!try walkNext(self.node_allocator, &self.cursor)) return null;
        return .{
            .address = @intCast(self.cursor.current),
            .depth = self.cursor.depth,
            .is_semantic_error = self.cursor.flags & flag_semantic_error != 0,
            .is_recovered = self.cursor.flags & flag_recovered != 0,
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
