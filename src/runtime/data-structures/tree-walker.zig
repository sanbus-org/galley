const std = @import("std");
const root = @import("galley");

/// Shared post-parse tree walker: the single gate for depth-first traversal
/// of an AST. Every consumer (examples, language bindings) delegates to this
/// instead of hand-rolling first_child/next_sibling recursion, so traversal
/// order, depth bookkeeping, and semantic-error pruning stay identical
/// everywhere.
///
/// AST-only: there is no persistent tree without AST construction. Calling
/// any method in a no-AST build is a compile error.
pub const TreeWalker = struct {
    const Node = root.data_structures.Node;

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

    const StackEntry = struct {
        address: Node.Pointer,
        depth: u32,
    };

    allocator: std.mem.Allocator,
    node_allocator: Node.NodeAllocator,
    stack: std.ArrayList(StackEntry),
    options: Options,
    last_depth: u32 = 0,
    has_last: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        node_allocator: Node.NodeAllocator,
        root_address: Node.Pointer,
        options: Options,
    ) TreeWalker {
        if (comptime !root.parser.is_ast_enabled) {
            @compileError("TreeWalker requires AST construction; without a persistent tree there is nothing to walk");
        }
        var stack: std.ArrayList(StackEntry) = .empty;
        stack.append(allocator, .{ .address = root_address, .depth = 0 }) catch unreachable;
        return .{
            .allocator = allocator,
            .node_allocator = node_allocator,
            .stack = stack,
            .options = options,
        };
    }

    pub fn deinit(self: *TreeWalker) void {
        if (comptime !root.parser.is_ast_enabled) {
            @compileError("TreeWalker requires AST construction; without a persistent tree there is nothing to walk");
        }
        self.stack.deinit(self.allocator);
    }

    /// Yields the next node in pre-order, or null when the walk is done.
    pub fn next(self: *TreeWalker) ?Step {
        if (comptime !root.parser.is_ast_enabled) {
            @compileError("TreeWalker requires AST construction; without a persistent tree there is nothing to walk");
        }
        while (self.stack.pop()) |entry| {
            const node = self.node_allocator.at(entry.address);
            if (self.options.skip_semantic_error_subtrees and node.is_semantic_error) {
                continue;
            }
            self.pushChildren(entry);
            self.last_depth = entry.depth;
            self.has_last = true;
            return .{
                .address = entry.address,
                .depth = entry.depth,
                .is_semantic_error = node.is_semantic_error,
            };
        }
        self.has_last = false;
        return null;
    }

    /// Prunes the children of the last yielded node: the following `next`
    /// call continues with its next sibling. No effect without a last step.
    pub fn skipChildren(self: *TreeWalker) void {
        if (comptime !root.parser.is_ast_enabled) {
            @compileError("TreeWalker requires AST construction; without a persistent tree there is nothing to walk");
        }
        if (!self.has_last) return;
        while (self.stack.items.len > 0) {
            if (self.stack.items[self.stack.items.len - 1].depth <= self.last_depth) break;
            _ = self.stack.pop();
        }
    }

    fn pushChildren(self: *TreeWalker, entry: StackEntry) void {
        const first = self.node_allocator.at(entry.address).first_child;
        if (first == Node.invalid_pointer) return;
        const base = self.stack.items.len;
        var child = first;
        while (child != Node.invalid_pointer) {
            self.stack.append(self.allocator, .{ .address = child, .depth = entry.depth + 1 }) catch unreachable;
            child = self.node_allocator.at(child).next;
        }
        std.mem.reverse(StackEntry, self.stack.items[base..]);
    }
};
