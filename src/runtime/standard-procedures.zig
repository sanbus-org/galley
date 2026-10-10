const std = @import("std");
const root = @import("galley");
const data_structures = root.data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;

/// Implements the standard tree-manipulation procedures. Grammar
/// annotations reach these through consumer re-exports under the generated
/// `hook_` namespace (for example `pub const hook_dropChildren =
/// standard_procedures.dropChildren;`), so this module's function names are
/// an implementation detail of the runtime, not a lookup contract.
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
            _ = data_structures.Node.cleanChildren(node_address, args.context.node_allocator);
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

test "dropSelf drops the current node" {
    if (comptime !root.parser.is_ast_enabled) return;
    var node_allocator = try data_structures.ASTAllocator.initWithCapacity(std.testing.allocator, 1);
    defer node_allocator.deinit(std.testing.allocator);
    const address = try node_allocator.create(0, 1);
    var dummy_runtime: data_structures.RuntimeContext = .{ .io = std.testing.io, .arena_allocator = std.testing.allocator };
    var context = data_structures.Context{ .runtime_context = &dummy_runtime, .node_allocator = &node_allocator };
    var args = ProcedureArguments{ .context = &context, .rule = null, .node_address = address };
    try dropSelf(&args);
    try std.testing.expectEqual(@as(?data_structures.Node.Pointer, null), args.node_address);
}

test "dropChildren keeps the node and detaches its children" {
    if (comptime !root.parser.is_ast_enabled) return;

    var node_allocator = try data_structures.ASTAllocator.initWithCapacity(std.testing.allocator, 3);
    defer node_allocator.deinit(std.testing.allocator);

    const parent = try node_allocator.create(0, 1);
    const first = try node_allocator.create(0, 2);
    const last = try node_allocator.create(0, 3);
    data_structures.Node.appendChildren(parent, &node_allocator, first);
    data_structures.Node.appendChildren(parent, &node_allocator, last);

    var dummy_runtime: data_structures.RuntimeContext = .{ .io = std.testing.io, .arena_allocator = std.testing.allocator };
    var context = data_structures.Context{ .runtime_context = &dummy_runtime, .node_allocator = &node_allocator };
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
    defer node_allocator.deinit(std.testing.allocator);

    const non_empty = try node_allocator.create(0, 1);
    const child = try node_allocator.create(0, 2);
    data_structures.Node.appendChildren(non_empty, &node_allocator, child);
    var dummy_runtime: data_structures.RuntimeContext = .{ .io = std.testing.io, .arena_allocator = std.testing.allocator };
    var context = data_structures.Context{ .runtime_context = &dummy_runtime, .node_allocator = &node_allocator };
    var args = ProcedureArguments{ .context = &context, .rule = null, .node_address = non_empty };
    try dropIfEmpty(&args);
    try std.testing.expectEqual(non_empty, args.node_address.?);

    const empty = try node_allocator.create(0, 3);
    args.node_address = empty;
    try dropIfEmpty(&args);
    try std.testing.expectEqual(@as(?data_structures.Node.Pointer, null), args.node_address);
}
