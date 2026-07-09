const std = @import("std");
const root = @import("galley");
const data_structures = root.data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;

/// Discards the current node itself by setting `args.node = null`.
/// This is typically attached to symbols that should not contribute a node
/// to the final AST (e.g. via `@dropSelf` in the grammar).
pub fn dropSelf(args: *ProcedureArguments) !void {
    args.node = null;
}

/// Discards all children of the current node (but keeps the node itself).
/// Useful for symbols whose only purpose was grouping/syntax but whose
/// children should be dropped (e.g. whitespace or certain wrappers).
pub fn dropChildren(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        _ = try data_structures.ASTNode.cleanChildren(node_address, args.context.node_allocator);
    }
}

/// Replaces the current node with its first child (if any).
/// The current node's structure is dropped and the first direct child
/// (and its siblings if chained) take its place in the parent.
/// Commonly used with `@replaceWithChildren` on list tails and member containers
/// so that e.g. an `ArrayMembers` node disappears and its `Value` children
/// become direct children of `Array`.
pub fn replaceWithChildren(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        args.node = data_structures.ASTNode.promoteChildrenOverWrapper(node_address, args.context.node_allocator);
    }
}
