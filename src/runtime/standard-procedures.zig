const std = @import("std");
const root = @import("galley");
const data_structures = root.data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;

fn requireAst() void {
    if (comptime !root.parser.is_ast_enabled and !root.parser.allow_no_ast_tree_procedures) {
        @compileError("standard tree-manipulation procedures require AST construction; generate with --allow-no-ast-tree-procedures to treat them as no-ops");
    }
}

/// Discards the current node itself by setting `args.node_address = null`.
/// This is typically attached to symbols that should not contribute a node
/// to the final AST (e.g. via `@dropSelf` in the grammar).
/// Without AST construction these helpers are no-ops unless generation opted
/// in with `--allow-no-ast-tree-procedures`.
pub fn dropSelf(args: *ProcedureArguments) !void {
    requireAst();
    if (comptime root.parser.is_ast_enabled) {
        args.node_address = null;
    }
}

/// Discards all children of the current node (but keeps the node itself).
/// Useful for symbols whose only purpose was grouping/syntax but whose
/// children should be dropped (e.g. whitespace or certain wrappers).
/// Without AST construction these helpers are no-ops unless generation opted
/// in with `--allow-no-ast-tree-procedures`.
pub fn dropChildren(args: *ProcedureArguments) !void {
    requireAst();
    if (comptime root.parser.is_ast_enabled) {
        if (args.node_address) |node_address| {
            _ = try data_structures.Node.cleanChildren(node_address, args.context.node_allocator);
        }
    }
}

/// Discards the current node when it has no children.
/// Without AST construction these helpers are no-ops unless generation opted
/// in with `--allow-no-ast-tree-procedures`.
pub fn dropIfEmpty(args: *ProcedureArguments) !void {
    requireAst();
    if (comptime root.parser.is_ast_enabled) {
        if (args.node_address) |node_address| {
            const node = args.context.node_allocator.at(node_address);
            if (node.first_child == data_structures.Node.invalid_pointer) {
                args.node_address = null;
            }
        }
    }
}

/// Flattens one level of a right-recursive node when its last child is the
/// same grammar variable.
/// Without AST construction these helpers are no-ops unless generation opted
/// in with `--allow-no-ast-tree-procedures`.
pub fn rightRecursiveReduction(args: *ProcedureArguments) !void {
    requireAst();
    if (comptime root.parser.is_ast_enabled) {
        if (args.node_address) |node_address| {
            const node = args.context.node_allocator.at(node_address);
            if (node.last_child == data_structures.Node.invalid_pointer) return;

            const tail_address = node.last_child;
            const tail = args.context.node_allocator.at(tail_address);
            if (tail.variable != node.variable) return;

            _ = try data_structures.Node.removeSelf(tail_address, args.context.node_allocator);
            const children = try data_structures.Node.cleanChildren(tail_address, args.context.node_allocator);
            if (children != data_structures.Node.invalid_pointer) {
                try data_structures.Node.appendChildren(node_address, args.context.node_allocator, children);
            }
        }
    }
}

/// Flattens one level of a left-recursive node when its first child is the
/// same grammar variable.
/// Without AST construction these helpers are no-ops unless generation opted
/// in with `--allow-no-ast-tree-procedures`.
pub fn leftRecursiveReduction(args: *ProcedureArguments) !void {
    requireAst();
    if (comptime root.parser.is_ast_enabled) {
        if (args.node_address) |node_address| {
            const node = args.context.node_allocator.at(node_address);
            if (node.first_child == data_structures.Node.invalid_pointer) return;

            const head_address = node.first_child;
            const head = args.context.node_allocator.at(head_address);
            if (head.variable != node.variable) return;

            _ = try data_structures.Node.removeSelf(head_address, args.context.node_allocator);
            const children = try data_structures.Node.cleanChildren(head_address, args.context.node_allocator);
            if (children != data_structures.Node.invalid_pointer) {
                try data_structures.Node.insertChildren(node_address, args.context.node_allocator, 0, children);
            }
        }
    }
}

/// Replaces the current node with its first child (if any).
/// The current node's structure is dropped and the first direct child
/// (and its siblings if chained) take its place in the parent.
/// Commonly used with `@replaceWithChildren` on list tails and member containers
/// so that e.g. an `ArrayMembers` node disappears and its `Value` children
/// become direct children of `Array`.
/// Without AST construction these helpers are no-ops unless generation opted
/// in with `--allow-no-ast-tree-procedures`.
pub fn replaceWithChildren(args: *ProcedureArguments) !void {
    requireAst();
    if (comptime root.parser.is_ast_enabled) {
        if (args.node_address) |node_address| {
            args.node_address = data_structures.Node.promoteChildrenOverWrapper(node_address, args.context.node_allocator);
        }
    }
}

test "dropSelf drops the current node" {
    if (comptime !root.parser.is_ast_enabled) return;
    var node_allocator = try data_structures.ASTAllocator.initWithCapacity(std.testing.allocator, 1);
    defer std.testing.allocator.free(node_allocator.memory);
    const address = try node_allocator.create(0, 1);
    var context = data_structures.Context{ .node_allocator = &node_allocator };
    var args = ProcedureArguments{ .context = &context, .rule = null, .node_address = address };
    try dropSelf(&args);
    try std.testing.expectEqual(@as(?data_structures.Node.Pointer, null), args.node_address);
}

test "dropChildren keeps the node and detaches its children" {
    if (comptime !root.parser.is_ast_enabled) return;

    var node_allocator = try data_structures.ASTAllocator.initWithCapacity(std.testing.allocator, 3);
    defer std.testing.allocator.free(node_allocator.memory);

    const parent = try node_allocator.create(0, 1);
    const first = try node_allocator.create(0, 2);
    const last = try node_allocator.create(0, 3);
    try data_structures.Node.appendChildren(parent, &node_allocator, first);
    try data_structures.Node.appendChildren(parent, &node_allocator, last);

    var context = data_structures.Context{ .node_allocator = &node_allocator };
    var args = ProcedureArguments{ .context = &context, .rule = null, .node_address = parent };
    try dropChildren(&args);

    try std.testing.expectEqual(parent, args.node_address.?);
    try std.testing.expectEqual(data_structures.Node.invalid_pointer, node_allocator.at(parent).first_child);
    try std.testing.expectEqual(data_structures.Node.invalid_pointer, node_allocator.at(parent).last_child);
    try std.testing.expectEqual(@as(u32, 0), node_allocator.at(parent).children_count);
    try std.testing.expectEqual(data_structures.Node.invalid_pointer, node_allocator.at(first).parent);
    try std.testing.expectEqual(data_structures.Node.invalid_pointer, node_allocator.at(last).parent);
}

test "dropIfEmpty drops only empty nodes" {
    if (comptime !root.parser.is_ast_enabled) return;

    var node_allocator = try data_structures.ASTAllocator.initWithCapacity(std.testing.allocator, 3);
    defer std.testing.allocator.free(node_allocator.memory);

    const non_empty = try node_allocator.create(0, 1);
    const child = try node_allocator.create(0, 2);
    try data_structures.Node.appendChildren(non_empty, &node_allocator, child);
    var context = data_structures.Context{ .node_allocator = &node_allocator };
    var args = ProcedureArguments{ .context = &context, .rule = null, .node_address = non_empty };
    try dropIfEmpty(&args);
    try std.testing.expectEqual(non_empty, args.node_address.?);

    const empty = try node_allocator.create(0, 3);
    args.node_address = empty;
    try dropIfEmpty(&args);
    try std.testing.expectEqual(@as(?data_structures.Node.Pointer, null), args.node_address);
}

test "replaceWithChildren promotes a wrapper's children" {
    if (comptime !root.parser.is_ast_enabled) return;

    var node_allocator = try data_structures.ASTAllocator.initWithCapacity(std.testing.allocator, 6);
    defer std.testing.allocator.free(node_allocator.memory);

    const parent = try node_allocator.create(0, 1);
    const before = try node_allocator.create(0, 2);
    const wrapper = try node_allocator.create(0, 3);
    const child_first = try node_allocator.create(0, 4);
    const child_last = try node_allocator.create(0, 5);
    const after = try node_allocator.create(0, 6);
    try data_structures.Node.appendChildren(wrapper, &node_allocator, child_first);
    try data_structures.Node.appendChildren(wrapper, &node_allocator, child_last);
    try data_structures.Node.appendChildren(parent, &node_allocator, before);
    try data_structures.Node.appendChildren(parent, &node_allocator, wrapper);
    try data_structures.Node.appendChildren(parent, &node_allocator, after);

    var context = data_structures.Context{ .node_allocator = &node_allocator };
    var args = ProcedureArguments{ .context = &context, .rule = null, .node_address = wrapper };
    try replaceWithChildren(&args);

    try std.testing.expectEqual(child_first, args.node_address.?);
    try std.testing.expectEqual(before, node_allocator.at(parent).first_child);
    try std.testing.expectEqual(after, node_allocator.at(parent).last_child);
    try std.testing.expectEqual(@as(u32, 4), node_allocator.at(parent).children_count);
    try std.testing.expectEqual(child_first, node_allocator.at(before).next);
    try std.testing.expectEqual(child_last, node_allocator.at(child_first).next);
    try std.testing.expectEqual(after, node_allocator.at(child_last).next);
    try std.testing.expectEqual(data_structures.Node.invalid_pointer, node_allocator.at(wrapper).first_child);
    try std.testing.expectEqual(parent, node_allocator.at(child_first).parent);
    try std.testing.expectEqual(parent, node_allocator.at(child_last).parent);
}

test "rightRecursiveReduction flattens a matching tail" {
    if (comptime !root.parser.is_ast_enabled) return;

    var node_allocator = try data_structures.ASTAllocator.initWithCapacity(std.testing.allocator, 5);
    defer std.testing.allocator.free(node_allocator.memory);

    const parent = try node_allocator.create(0, 1);
    const first = try node_allocator.create(0, 2);
    const tail = try node_allocator.create(0, 1);
    const tail_first = try node_allocator.create(0, 3);
    const tail_last = try node_allocator.create(0, 4);
    try data_structures.Node.appendChildren(tail, &node_allocator, tail_first);
    try data_structures.Node.appendChildren(tail, &node_allocator, tail_last);
    try data_structures.Node.appendChildren(parent, &node_allocator, first);
    try data_structures.Node.appendChildren(parent, &node_allocator, tail);

    var context = data_structures.Context{ .node_allocator = &node_allocator };
    var args = ProcedureArguments{ .context = &context, .rule = null, .node_address = parent };
    try rightRecursiveReduction(&args);

    try std.testing.expectEqual(first, node_allocator.at(parent).first_child);
    try std.testing.expectEqual(tail_first, node_allocator.at(first).next);
    try std.testing.expectEqual(tail_last, node_allocator.at(parent).last_child);
    try std.testing.expectEqual(@as(u32, 3), node_allocator.at(parent).children_count);
    try std.testing.expectEqual(data_structures.Node.invalid_pointer, node_allocator.at(tail).parent);
}

test "leftRecursiveReduction flattens a matching head" {
    if (comptime !root.parser.is_ast_enabled) return;

    var node_allocator = try data_structures.ASTAllocator.initWithCapacity(std.testing.allocator, 5);
    defer std.testing.allocator.free(node_allocator.memory);

    const parent = try node_allocator.create(0, 1);
    const head = try node_allocator.create(0, 1);
    const head_first = try node_allocator.create(0, 3);
    const head_last = try node_allocator.create(0, 4);
    const last = try node_allocator.create(0, 2);
    try data_structures.Node.appendChildren(head, &node_allocator, head_first);
    try data_structures.Node.appendChildren(head, &node_allocator, head_last);
    try data_structures.Node.appendChildren(parent, &node_allocator, head);
    try data_structures.Node.appendChildren(parent, &node_allocator, last);

    var context = data_structures.Context{ .node_allocator = &node_allocator };
    var args = ProcedureArguments{ .context = &context, .rule = null, .node_address = parent };
    try leftRecursiveReduction(&args);

    try std.testing.expectEqual(head_first, node_allocator.at(parent).first_child);
    try std.testing.expectEqual(head_last, node_allocator.at(head_first).next);
    try std.testing.expectEqual(last, node_allocator.at(parent).last_child);
    try std.testing.expectEqual(@as(u32, 3), node_allocator.at(parent).children_count);
    try std.testing.expectEqual(data_structures.Node.invalid_pointer, node_allocator.at(head).parent);
}
