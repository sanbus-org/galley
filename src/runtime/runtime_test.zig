const std = @import("std");
const galley = @import("galley");
const ProcedureArguments = galley.data_structures.ProcedureArguments;

comptime {
    _ = @import("standard-procedures.zig");
    _ = @import("data-structures/node.zig");
    _ = @import("data-structures/context.zig");
    _ = @import("data-structures/offsets.zig");
    _ = @import("string.zig");
    _ = @import("session-lock.zig");
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

    var dummy_runtime: galley.data_structures.RuntimeContext = .{ .io = std.testing.io, .arena_allocator = std.testing.allocator };
    var context: galley.data_structures.Context = .{ .runtime_context = &dummy_runtime };
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
    var dummy_runtime: galley.data_structures.RuntimeContext = .{ .io = std.testing.io, .arena_allocator = std.testing.allocator };
    var context: galley.data_structures.Context = .{ .runtime_context = &dummy_runtime, .node_allocator = &node_allocator };
    var args: ProcedureArguments = .{ .context = &context, .rule = null, .node_address = address };
    try wrapped(&args);

    try std.testing.expectEqual(@as(?galley.data_structures.Node.Pointer, null), args.node_address);
}

test "a hook ticket names its arguments only while its hook runs" {
    var runtime: galley.data_structures.RuntimeContext = .{ .io = std.testing.io, .arena_allocator = std.testing.allocator };
    var other: galley.data_structures.RuntimeContext = .{ .io = std.testing.io, .arena_allocator = std.testing.allocator };
    var context: galley.data_structures.Context = .{ .runtime_context = &runtime };
    var first_args: ProcedureArguments = .{ .context = &context, .rule = null, .node_address = null };
    var second_args: ProcedureArguments = .{ .context = &context, .rule = null, .node_address = null };

    // Nothing runs yet: no ticket, not even 0, names anything.
    try std.testing.expectError(error.StaleHook, runtime.hookArguments(0));
    try std.testing.expectError(error.StaleHook, runtime.hookArguments(1));

    const first = runtime.enterHook(&first_args);
    try std.testing.expect(first != 0);
    try std.testing.expectEqual(&first_args, try runtime.hookArguments(first));
    // Another session never accepts a live ticket of this one.
    try std.testing.expectError(error.StaleHook, other.hookArguments(first));
    runtime.exitHook();
    try std.testing.expectError(error.StaleHook, runtime.hookArguments(first));

    // A later hook gets a new ticket even when its arguments sit where the
    // first hook's did, so the returned hook's ticket stays refused.
    const second = runtime.enterHook(&first_args);
    try std.testing.expect(second != first);
    try std.testing.expectEqual(&first_args, try runtime.hookArguments(second));
    try std.testing.expectError(error.StaleHook, runtime.hookArguments(first));
    runtime.exitHook();

    // Tickets are unique across sessions: a second session's hook never
    // collides with the first's.
    const third = other.enterHook(&second_args);
    try std.testing.expect(third != first and third != second);
    try std.testing.expectError(error.StaleHook, runtime.hookArguments(third));
    try std.testing.expectEqual(&second_args, try other.hookArguments(third));
    other.exitHook();
}

test "a live hook ticket is refused on any thread but the dispatching one" {
    if (comptime @import("builtin").single_threaded) return error.SkipZigTest;
    var runtime: galley.data_structures.RuntimeContext = .{ .io = std.testing.io, .arena_allocator = std.testing.allocator };
    var context: galley.data_structures.Context = .{ .runtime_context = &runtime };
    var args: ProcedureArguments = .{ .context = &context, .rule = null, .node_address = null };
    const ticket = runtime.enterHook(&args);
    defer runtime.exitHook();
    const Probe = struct {
        fn run(target: *galley.data_structures.RuntimeContext, hook: u64, result: *?anyerror) void {
            result.* = if (target.hookArguments(hook)) |_| null else |err| err;
        }
    };
    var result: ?anyerror = null;
    const thread = try std.Thread.spawn(.{}, Probe.run, .{ &runtime, ticket, &result });
    thread.join();
    try std.testing.expectEqual(@as(?anyerror, error.OtherThread), result);
    try std.testing.expectEqual(&args, try runtime.hookArguments(ticket));
}

test "a foreign thread overlapping a running parse is refused before its ticket is read" {
    if (comptime @import("builtin").single_threaded) return error.SkipZigTest;
    var runtime: galley.data_structures.RuntimeContext = .{ .io = std.testing.io, .arena_allocator = std.testing.allocator };
    var context: galley.data_structures.Context = .{ .runtime_context = &runtime };
    var args: ProcedureArguments = .{ .context = &context, .rule = null, .node_address = null };
    const Probe = struct {
        fn run(target: *galley.data_structures.RuntimeContext, hook: u64, result: *?anyerror) void {
            result.* = if (target.hookArguments(hook)) |_| null else |err| err;
        }
        fn from(target: *galley.data_structures.RuntimeContext, hook: u64) !?anyerror {
            var result: ?anyerror = null;
            const thread = try std.Thread.spawn(.{}, run, .{ target, hook, &result });
            thread.join();
            return result;
        }
    };

    // No parse runs: a stale ticket is stale on every thread.
    const returned = runtime.enterHook(&args);
    runtime.exitHook();
    try std.testing.expectEqual(@as(?anyerror, error.StaleHook), try Probe.from(&runtime, returned));

    runtime.beginParse();
    // Between hooks of a running parse, another thread overlaps the parse.
    try std.testing.expectEqual(@as(?anyerror, error.OtherThread), try Probe.from(&runtime, returned));
    try std.testing.expectEqual(@as(?anyerror, error.OtherThread), try Probe.from(&runtime, 0));

    // While a different hook runs, a stale or invented ticket is still an
    // overlap first; the dispatching thread's own stale ticket stays stale.
    const running = runtime.enterHook(&args);
    try std.testing.expectEqual(@as(?anyerror, error.OtherThread), try Probe.from(&runtime, returned));
    try std.testing.expectEqual(@as(?anyerror, error.OtherThread), try Probe.from(&runtime, running));
    try std.testing.expectError(error.StaleHook, runtime.hookArguments(returned));
    try std.testing.expectEqual(&args, try runtime.hookArguments(running));
    runtime.exitHook();

    // Once the parse ends the overlap is gone and the ticket decides again.
    runtime.endParse();
    try std.testing.expectEqual(@as(?anyerror, error.StaleHook), try Probe.from(&runtime, returned));
}
