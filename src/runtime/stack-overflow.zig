const builtin = @import("builtin");
const root = @import("galley");
const signals = @import("signals");
const std = @import("std");

pub const is_supported = signals.is_supported;

pub fn isActive() bool {
    if (comptime !is_supported) return false;
    return signals.Signals.active_scope != null;
}

pub fn protectedParse(context: *root.data_structures.Context) !root.ParseResult {
    if (comptime !is_supported) return error.StackOverflowRecoveryUnsupported;
    return signals.Signals.protectedCall(root.ParseResult, parse, context, root.ParseError.StackOverflow) catch |err| {
        if (err == root.ParseError.StackOverflow) {
            std.debug.print("{f}", .{stackOverflowDiagnostic(context)});
        }
        return err;
    };
}

fn parse(opaque_context: *anyopaque) !root.ParseResult {
    const context: *root.data_structures.Context = @ptrCast(@alignCast(opaque_context));
    return root.parser.parseWithResult(context);
}

const excerpt_radius = 20;

const Excerpt = struct {
    text: []const u8,
    caret_offset: usize,
};

const StackOverflowDiagnostic = struct {
    line: u32,
    column: u32,
    excerpt: Excerpt,
    token: []const u8,

    pub fn format(self: @This(), writer: *std.Io.Writer) !void {
        try writer.print(
            "\x1b[35mStackOverflow at {d}:{d}:\x1b[0m\n" ++
                "Surrounding text: \x1b[37m\"{f}\"\n" ++
                "                  ",
            .{
                self.line,
                self.column,
                root.string_utilities.fmtString(self.excerpt.text),
            },
        );
        try writer.splatByteAll(' ', escapedWidth(self.excerpt.text[0..self.excerpt.caret_offset]));
        try writer.print(
            "^\x1b[0m\n" ++
                "Token content: \x1b[37m\"{f}\"\x1b[34m\x1b[0m\n",
            .{root.string_utilities.fmtString(self.token)},
        );
    }
};

fn stackOverflowDiagnostic(context: *const root.data_structures.Context) StackOverflowDiagnostic {
    const input = context.diagnosticInput();
    const cursor: usize = if (comptime root.config.indentation_syntax)
        context.seek
    else
        context.token.head;

    return .{
        .line = if (comptime root.position_tracking_enabled) context.line else 0,
        .column = if (comptime root.position_tracking_enabled) context.column else 0,
        .excerpt = centeredExcerpt(input, cursor),
        .token = context.token.items(),
    };
}

fn centeredExcerpt(input: []const u8, requested_cursor: usize) Excerpt {
    const input_end = std.mem.indexOfScalar(u8, input, 0) orelse input.len;
    const cursor = @min(requested_cursor, input_end);
    const start = cursor - @min(cursor, excerpt_radius);
    const end = @min(input_end, cursor +| excerpt_radius);
    return .{
        .text = input[start..end],
        .caret_offset = cursor - start,
    };
}

fn escapedWidth(input: []const u8) usize {
    var width: usize = 0;
    for (input) |byte| {
        width += switch (byte) {
            '\n', '\r', '\t', '\\', '"' => 2,
            '\'', ' ', '!', '#'...'&', '('...'[', ']'...'~' => 1,
            else => 4,
        };
    }
    return width;
}

test "protected call restores signal handlers and alternate stack" {
    if (comptime !is_supported) return error.SkipZigTest;

    const c = signals.Signals.c;
    var sigsegv_before: c.struct_sigaction = undefined;
    var sigbus_before: c.struct_sigaction = undefined;
    var alternate_stack_before: c.stack_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), c.sigaction(c.SIGSEGV, null, &sigsegv_before));
    try std.testing.expectEqual(@as(c_int, 0), c.sigaction(c.SIGBUS, null, &sigbus_before));
    try std.testing.expectEqual(@as(c_int, 0), c.sigaltstack(null, &alternate_stack_before));

    var marker: u8 = 0;
    try signals.Signals.protectedCall(void, TestCallbacks.noop, &marker, error.StackOverflow);

    var sigsegv_after: c.struct_sigaction = undefined;
    var sigbus_after: c.struct_sigaction = undefined;
    var alternate_stack_after: c.stack_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), c.sigaction(c.SIGSEGV, null, &sigsegv_after));
    try std.testing.expectEqual(@as(c_int, 0), c.sigaction(c.SIGBUS, null, &sigbus_after));
    try std.testing.expectEqual(@as(c_int, 0), c.sigaltstack(null, &alternate_stack_after));

    try std.testing.expectEqual(actionHandlerAddress(&sigsegv_before), actionHandlerAddress(&sigsegv_after));
    try std.testing.expectEqual(actionHandlerAddress(&sigbus_before), actionHandlerAddress(&sigbus_after));
    try std.testing.expectEqual(sigsegv_before.flags, sigsegv_after.flags);
    try std.testing.expectEqual(sigbus_before.flags, sigbus_after.flags);
    try std.testing.expectEqual(alternate_stack_before.sp, alternate_stack_after.sp);
    try std.testing.expectEqual(alternate_stack_before.size, alternate_stack_after.size);
    try std.testing.expectEqual(alternate_stack_before.flags, alternate_stack_after.flags);
}

test "protected call converts a real guard-page fault to the overflow error" {
    if (comptime !is_supported) return error.SkipZigTest;

    const masks_before = try TestCallbacks.faultSignalMaskState();
    var result: ?anyerror = null;
    const thread = try std.Thread.spawn(
        .{},
        TestCallbacks.overflowThread,
        .{&result},
    );
    thread.join();

    try std.testing.expect(result != null);
    try std.testing.expectEqual(error.StackOverflow, result.?);
    try std.testing.expectEqualDeep(
        masks_before,
        try TestCallbacks.faultSignalMaskState(),
    );
    try expectUnrelatedFaultChained();
}

test "protected call chains unrelated faults to the previous handler" {
    if (comptime !is_supported) return error.SkipZigTest;
    try expectUnrelatedFaultChained();
}

fn expectUnrelatedFaultChained() !void {
    const c = signals.Signals.c;
    var previous: c.struct_sigaction = undefined;
    var action = std.mem.zeroes(c.struct_sigaction);
    signals.Signals.setSiginfoHandler(&action, TestCallbacks.recordSignal);
    try std.testing.expectEqual(@as(c_int, 0), c.sigemptyset(&action.mask));
    action.flags = c.SA_SIGINFO;
    try std.testing.expectEqual(@as(c_int, 0), c.sigaction(c.SIGSEGV, &action, &previous));
    defer _ = c.sigaction(c.SIGSEGV, &previous, null);

    TestCallbacks.signal_count.store(0, .release);
    var marker: u8 = 0;
    try signals.Signals.protectedCall(void, TestCallbacks.raiseSegv, &marker, error.StackOverflow);
    try std.testing.expectEqual(@as(usize, 1), TestCallbacks.signal_count.load(.acquire));

    var current: c.struct_sigaction = undefined;
    try std.testing.expectEqual(@as(c_int, 0), c.sigaction(c.SIGSEGV, null, &current));
    try std.testing.expectEqual(@intFromPtr(&TestCallbacks.recordSignal), actionHandlerAddress(&current));
}

const TestCallbacks = if (is_supported) struct {
    const FaultSignalMaskState = struct {
        thread_sigsegv: c_int,
        thread_sigbus: c_int,
        process_sigsegv: c_int,
        process_sigbus: c_int,
    };

    var signal_count = std.atomic.Value(usize).init(0);

    fn faultSignalMaskState() !FaultSignalMaskState {
        const c = signals.Signals.c;
        var thread_mask: c.sigset_t = undefined;
        if (c.pthread_sigmask(c.SIG_BLOCK, null, &thread_mask) != 0) {
            return error.SignalMaskSetupFailed;
        }

        var process_mask: c.sigset_t = undefined;
        if (c.sigprocmask(c.SIG_BLOCK, null, &process_mask) != 0) {
            return error.SignalMaskSetupFailed;
        }

        return .{
            .thread_sigsegv = c.sigismember(&thread_mask, c.SIGSEGV),
            .thread_sigbus = c.sigismember(&thread_mask, c.SIGBUS),
            .process_sigsegv = c.sigismember(&process_mask, c.SIGSEGV),
            .process_sigbus = c.sigismember(&process_mask, c.SIGBUS),
        };
    }

    fn noop(_: *anyopaque) !void {}

    fn raiseSegv(_: *anyopaque) !void {
        if (signals.Signals.c.raise(signals.Signals.c.SIGSEGV) != 0) return error.SignalRaiseFailed;
    }

    fn recordSignal(_: c_int, _: [*c]signals.Signals.c.siginfo_t, _: ?*anyopaque) callconv(.c) void {
        _ = signal_count.fetchAdd(1, .acq_rel);
    }

    fn overflowThread(result: *?anyerror) void {
        var marker: u8 = 0;
        _ = signals.Signals.protectedCall(void, overflow, &marker, error.StackOverflow) catch |err| {
            result.* = err;
            return;
        };
        result.* = error.ExpectedStackOverflow;
    }

    fn overflow(_: *anyopaque) !void {
        recurse(0);
    }

    noinline fn recurse(depth: usize) void {
        if (depth == std.math.maxInt(usize)) return;
        var padding: [1024]u8 = undefined;
        padding[depth % padding.len] = @truncate(depth);
        std.mem.doNotOptimizeAway(&padding);
        recurse(depth + 1);
        std.mem.doNotOptimizeAway(padding[0]);
    }
} else struct {};

fn actionHandlerAddress(action: *const signals.Signals.c.struct_sigaction) usize {
    // The handler union and its members carry the same names on every
    // supported libc (std.c.Sigaction), so no per-platform probing.
    if ((action.flags & signals.Signals.c.SA_SIGINFO) != 0) {
        const handler = action.handler.sigaction;
        return if (handler) |function| @intFromPtr(function) else 0;
    }
    const handler = action.handler.handler;
    return if (handler) |function| @intFromPtr(function) else 0;
}

const NestedScopes = if (is_supported) struct {
    var inner_ran = false;
    var inner_error: ?anyerror = null;

    fn innerSuccess(_: *anyopaque) !void {
        inner_ran = true;
    }

    fn innerOverflow(_: *anyopaque) !void {
        var marker: u8 = 0;
        try TestCallbacks.overflow(&marker);
    }

    fn outerNesting(_: *anyopaque) !void {
        var marker: u8 = 0;
        _ = signals.Signals.protectedCall(void, innerSuccess, &marker, error.InnerOverflow) catch |err| {
            inner_error = err;
            return;
        };
        inner_ran = true;
    }

    fn outerOverflowing(_: *anyopaque) !void {
        var marker: u8 = 0;
        _ = signals.Signals.protectedCall(void, innerOverflow, &marker, error.InnerOverflow) catch |err| {
            inner_error = err;
            return;
        };
        inner_error = error.ExpectedInnerOverflow;
    }

    fn nestedSuccessThread(outcome: *?anyerror) void {
        var marker: u8 = 0;
        signals.Signals.protectedCall(void, outerNesting, &marker, error.OuterOverflow) catch |err| {
            outcome.* = err;
            return;
        };
        outcome.* = null;
    }

    fn nestedOverflowThread(outcome: *?anyerror) void {
        var marker: u8 = 0;
        signals.Signals.protectedCall(void, outerOverflowing, &marker, error.OuterOverflow) catch |err| {
            outcome.* = err;
            return;
        };
        outcome.* = null;
    }
} else struct {};

test "nested protected calls stack scopes" {
    if (comptime !is_supported) return error.SkipZigTest;

    NestedScopes.inner_ran = false;
    NestedScopes.inner_error = null;
    var outcome: ?anyerror = error.Unrun;
    const thread = try std.Thread.spawn(.{}, NestedScopes.nestedSuccessThread, .{&outcome});
    thread.join();

    if (outcome) |err| return err;
    try std.testing.expect(NestedScopes.inner_ran);
    try std.testing.expect(NestedScopes.inner_error == null);
    try std.testing.expect(!isActive());
}

test "nested protected overflow is caught by the inner scope" {
    if (comptime !is_supported) return error.SkipZigTest;

    NestedScopes.inner_ran = false;
    NestedScopes.inner_error = null;
    var outcome: ?anyerror = error.Unrun;
    const thread = try std.Thread.spawn(.{}, NestedScopes.nestedOverflowThread, .{&outcome});
    thread.join();

    // The outer parse survives: only the inner scope converted its fault.
    if (outcome) |err| return err;
    try std.testing.expectEqual(error.InnerOverflow, NestedScopes.inner_error.?);
    try std.testing.expect(!isActive());
}

test "centered stack overflow excerpt clamps at input boundaries" {
    const input = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

    const beginning = centeredExcerpt(input, 3);
    try std.testing.expectEqualStrings(input[0..23], beginning.text);
    try std.testing.expectEqual(@as(usize, 3), beginning.caret_offset);

    const middle = centeredExcerpt(input, 30);
    try std.testing.expectEqualStrings(input[10..50], middle.text);
    try std.testing.expectEqual(@as(usize, 20), middle.caret_offset);

    const near_end = centeredExcerpt(input, input.len - 3);
    try std.testing.expectEqualStrings(input[input.len - 23 ..], near_end.text);
    try std.testing.expectEqual(@as(usize, 20), near_end.caret_offset);
}

test "centered stack overflow excerpt stops at sentinel and clamps cursor" {
    const input = "0123456789\x00ignored";
    const excerpt = centeredExcerpt(input, std.math.maxInt(usize));

    try std.testing.expectEqualStrings("0123456789", excerpt.text);
    try std.testing.expectEqual(@as(usize, 10), excerpt.caret_offset);
}

var test_token_buffer: [root.data_structures.Token.Storage.capacity]u8 = undefined;
var test_token_sources: [root.data_structures.Token.Storage.capacity]usize = undefined;

test "stack overflow diagnostic captures parser location and token" {
    var input = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 0 };
    var dummy_runtime: root.data_structures.RuntimeContext = .{ .io = std.testing.io, .arena_allocator = std.testing.allocator };
    var context: root.data_structures.Context = .{
        .runtime_context = &dummy_runtime,
        .chunk_buffer = &input,
    };

    const expected_token = if (comptime root.config.indentation_syntax) token: {
        context.token.attach(.{ .buffer = &test_token_buffer, .sources = &test_token_sources });
        context.token.resetBuffered();
        context.seek = 6;
        context.token.append('x');
        context.token.append('y');
        break :token "xy";
    } else token: {
        context.token.resetInput(&input);
        context.token.head = 6;
        context.token.len = 2;
        break :token "45";
    };
    if (comptime builtin.mode != .fast) {
        context.line = 7;
        context.column = 9;
    }

    const diagnostic = stackOverflowDiagnostic(&context);
    try std.testing.expectEqual(
        @as(u32, if (builtin.mode != .fast) 7 else 0),
        diagnostic.line,
    );
    try std.testing.expectEqual(
        @as(u32, if (builtin.mode != .fast) 9 else 0),
        diagnostic.column,
    );
    try std.testing.expectEqualStrings(expected_token, diagnostic.token);
    try std.testing.expectEqual(@as(usize, 6), diagnostic.excerpt.caret_offset);
}

test "stack overflow diagnostic formats old location details" {
    const diagnostic = StackOverflowDiagnostic{
        .line = 7,
        .column = 9,
        .excerpt = .{
            .text = "ab\ncd",
            .caret_offset = 3,
        },
        .token = "token",
    };
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try diagnostic.format(&output.writer);

    try std.testing.expect(std.mem.indexOf(u8, output.written(), "StackOverflow at 7:9:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "Surrounding text: \x1b[37m\"ab\\ncd\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.written(), "Token content: \x1b[37m\"token\"") != null);
    try std.testing.expectEqual(@as(usize, 4), escapedWidth(diagnostic.excerpt.text[0..diagnostic.excerpt.caret_offset]));
}
