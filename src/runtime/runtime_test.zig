const std = @import("std");
const galley = @import("galley");
const ProcedureArguments = galley.data_structures.ProcedureArguments;

comptime {
    _ = @import("standard-procedures.zig");
    _ = @import("data-structures/astnode.zig");
}

var zero_argument_handler_called = false;

fn zeroArgumentHandler() void {
    zero_argument_handler_called = true;
}

fn procedureArgumentsHandler(args: *ProcedureArguments) !void {
    args.node = null;
}

test "wrapProcedure invokes a zero-argument handler" {
    zero_argument_handler_called = false;
    const wrapped = galley.data_structures.wrap_procedure(
        fn (*ProcedureArguments) anyerror!void,
        zeroArgumentHandler,
        "zeroArgumentHandler",
    );

    var context: galley.data_structures.Context = .{};
    var args: ProcedureArguments = .{ .context = &context, .rule = null, .node = null };
    try wrapped(&args);

    try std.testing.expect(zero_argument_handler_called);
}

test "wrapProcedure forwards ProcedureArguments" {
    const wrapped = galley.data_structures.wrap_procedure(
        fn (*ProcedureArguments) anyerror!void,
        procedureArgumentsHandler,
        "procedureArgumentsHandler",
    );

    var context: galley.data_structures.Context = .{};
    var args: ProcedureArguments = .{ .context = &context, .rule = null, .node = 1 };
    try wrapped(&args);

    try std.testing.expectEqual(@as(?galley.data_structures.ASTNode.Pointer, null), args.node);
}
