const std = @import("std");
const galley = @import("galley");
const ProcedureArguments = galley.data_structures.ProcedureArguments;

comptime {
    _ = @import("standard-procedures.zig");
    _ = @import("data-structures/node.zig");
    _ = @import("data-structures/context.zig");
    _ = @import("data-structures/offsets.zig");
    _ = @import("string.zig");
}

var zero_argument_handler_called = false;

fn zeroArgumentHandler() void {
    zero_argument_handler_called = true;
}

fn procedureArgumentsHandler(args: *ProcedureArguments) !void {
    args.node_address = null;
}

test "wrapProcedure invokes a zero-argument handler" {
    zero_argument_handler_called = false;
    const wrapped = galley.data_structures.wrap_procedure(
        fn (*ProcedureArguments) anyerror!void,
        zeroArgumentHandler,
        "zeroArgumentHandler",
    );

    var context: galley.data_structures.Context = .{};
    var args: ProcedureArguments = .{ .context = &context, .rule = null, .node_address = null };
    try wrapped(&args);

    try std.testing.expect(zero_argument_handler_called);
}

test "wrapProcedure forwards ProcedureArguments" {
    const wrapped = galley.data_structures.wrap_procedure(
        fn (*ProcedureArguments) anyerror!void,
        procedureArgumentsHandler,
        "procedureArgumentsHandler",
    );

    var node_allocator = try galley.data_structures.ASTAllocator.initWithCapacity(std.testing.allocator, 1);
    defer node_allocator.deinit(std.testing.allocator);
    const address = try node_allocator.create(0, 1);
    var context: galley.data_structures.Context = .{ .node_allocator = &node_allocator };
    var args: ProcedureArguments = .{ .context = &context, .rule = null, .node_address = address };
    try wrapped(&args);

    try std.testing.expectEqual(@as(?galley.data_structures.Node.Pointer, null), args.node_address);
}
