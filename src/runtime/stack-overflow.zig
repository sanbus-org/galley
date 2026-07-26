const builtin = @import("builtin");
const root = @import("galley");
const std = @import("std");

pub const is_supported = switch (builtin.target.os.tag) {
    .linux, .macos => true,
    else => false,
};

pub fn isActive() bool {
    if (comptime !is_supported) return false;
    return Posix.active_scope != null;
}

pub fn protectedParse(context: *root.data_structures.Context) !root.ParseResult {
    if (comptime !is_supported) return error.StackOverflowRecoveryUnsupported;
    return Posix.protectedCall(root.ParseResult, parse, context) catch |err| {
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
    const input = if (comptime root.config.indentation_syntax)
        context.chunk_buffer
    else
        context.token.buffer;
    const cursor: usize = if (comptime root.config.indentation_syntax)
        context.seek
    else
        context.token.head;

    return .{
        .line = if (comptime builtin.mode != .ReleaseFast) context.line else 0,
        .column = if (comptime builtin.mode != .ReleaseFast) context.column else 0,
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

const Posix = if (is_supported) struct {
    const c = @cImport({
        @cDefine("_GNU_SOURCE", "1");
        @cInclude("pthread.h");
        @cInclude("setjmp.h");
        @cInclude("signal.h");
        @cInclude("unistd.h");
    });

    const SignalHandler = *const fn (c_int, [*c]c.siginfo_t, ?*anyopaque) callconv(.c) void;
    const SimpleSignalHandler = *const fn (c_int) callconv(.c) void;
    const guard_slack = @max(std.heap.page_size_max, 64 * 1024);
    const alternate_stack_size = 64 * 1024;

    const StackBounds = struct {
        low: usize,
        high: usize,
        guard_size: usize,
    };

    const RecoveryScope = struct {
        jump_environment: c.sigjmp_buf,
        bounds: StackBounds,
    };

    const SignalMask = struct {
        faults: c.sigset_t,
        previous: c.sigset_t,

        fn block() !SignalMask {
            var faults: c.sigset_t = undefined;
            if (c.sigemptyset(&faults) != 0) return error.SignalMaskSetupFailed;
            if (c.sigaddset(&faults, c.SIGSEGV) != 0) return error.SignalMaskSetupFailed;
            if (c.sigaddset(&faults, c.SIGBUS) != 0) return error.SignalMaskSetupFailed;

            var previous: c.sigset_t = undefined;
            if (c.pthread_sigmask(c.SIG_BLOCK, &faults, &previous) != 0) {
                return error.SignalMaskSetupFailed;
            }
            return .{ .faults = faults, .previous = previous };
        }

        fn restore(self: *const SignalMask) !void {
            if (c.pthread_sigmask(c.SIG_SETMASK, &self.previous, null) != 0) {
                return error.SignalMaskRestoreFailed;
            }
        }

        fn blockFaults(self: *const SignalMask) !void {
            if (c.pthread_sigmask(c.SIG_BLOCK, &self.faults, null) != 0) {
                return error.SignalMaskSetupFailed;
            }
        }
    };

    const AlternateStack = struct {
        memory: []u8,
        previous: c.stack_t,

        fn install() !AlternateStack {
            const memory = try std.heap.page_allocator.alloc(u8, alternate_stack_size);
            errdefer std.heap.page_allocator.free(memory);

            var previous: c.stack_t = undefined;
            if (c.sigaltstack(null, &previous) != 0) return error.SignalStackSetupFailed;

            var replacement = std.mem.zeroes(c.stack_t);
            replacement.ss_sp = memory.ptr;
            replacement.ss_size = memory.len;
            replacement.ss_flags = if (comptime @hasDecl(c, "SS_AUTODISARM"))
                c.SS_AUTODISARM
            else
                0;
            if (c.sigaltstack(&replacement, null) != 0) return error.SignalStackSetupFailed;

            return .{ .memory = memory, .previous = previous };
        }

        fn restore(self: *AlternateStack) !void {
            if (c.sigaltstack(&self.previous, null) != 0) {
                // The replacement may still be registered. Leaking is safer
                // than freeing memory that a later signal could use.
                return error.SignalStackRestoreFailed;
            }
            std.heap.page_allocator.free(self.memory);
            self.memory = &.{};
        }
    };

    const OutcomeTag = enum { success, failure };

    fn Outcome(comptime T: type) type {
        return union(OutcomeTag) {
            success: T,
            failure: anyerror,
        };
    }

    threadlocal var active_scope: ?*RecoveryScope = null;

    var handler_mutex: std.atomic.Mutex = .unlocked;
    var handler_users: usize = 0;
    var previous_sigsegv: c.struct_sigaction = undefined;
    var previous_sigbus: c.struct_sigaction = undefined;
    var handlers_in_flight = std.atomic.Value(usize).init(0);

    fn protectedCall(
        comptime T: type,
        callback: *const fn (*anyopaque) anyerror!T,
        opaque_context: *anyopaque,
    ) anyerror!T {
        if (active_scope != null) return callback(opaque_context);

        const signal_mask = try SignalMask.block();
        var mask_is_blocked = true;
        errdefer if (mask_is_blocked) signal_mask.restore() catch {};

        try acquireHandlers();
        var handlers_are_acquired = true;
        errdefer if (handlers_are_acquired) releaseHandlers() catch {};

        var alternate_stack = try AlternateStack.install();
        var alternate_stack_is_installed = true;
        errdefer if (alternate_stack_is_installed) alternate_stack.restore() catch {};

        var scope = RecoveryScope{
            .jump_environment = undefined,
            .bounds = try currentStackBounds(),
        };
        active_scope = &scope;

        var outcome: Outcome(T) = undefined;
        const jump_result = c.sigsetjmp(&scope.jump_environment, 1);
        if (jump_result == 0) {
            signal_mask.restore() catch |err| {
                outcome = .{ .failure = err };
                active_scope = null;
                return finishProtectedCall(
                    T,
                    outcome,
                    &signal_mask,
                    &mask_is_blocked,
                    &alternate_stack,
                    &alternate_stack_is_installed,
                    &handlers_are_acquired,
                );
            };
            mask_is_blocked = false;

            outcome = if (callback(opaque_context)) |result|
                .{ .success = result }
            else |err|
                .{ .failure = err };

            reblock: {
                signal_mask.blockFaults() catch |err| {
                    outcome = .{ .failure = err };
                    mask_is_blocked = false;
                    break :reblock;
                };
                mask_is_blocked = true;
            }
        } else {
            // sigsetjmp saved the setup-time mask, so fault signals are
            // blocked again after siglongjmp.
            outcome = .{ .failure = root.ParseError.StackOverflow };
        }

        active_scope = null;
        return finishProtectedCall(
            T,
            outcome,
            &signal_mask,
            &mask_is_blocked,
            &alternate_stack,
            &alternate_stack_is_installed,
            &handlers_are_acquired,
        );
    }

    fn finishProtectedCall(
        comptime T: type,
        outcome: Outcome(T),
        signal_mask: *const SignalMask,
        mask_is_blocked: *bool,
        alternate_stack: *AlternateStack,
        alternate_stack_is_installed: *bool,
        handlers_are_acquired: *bool,
    ) anyerror!T {
        alternate_stack.restore() catch |err| {
            alternate_stack_is_installed.* = false;
            releaseHandlers() catch {};
            handlers_are_acquired.* = false;
            signal_mask.restore() catch {};
            mask_is_blocked.* = false;
            return err;
        };
        alternate_stack_is_installed.* = false;

        releaseHandlers() catch |err| {
            handlers_are_acquired.* = false;
            signal_mask.restore() catch {};
            mask_is_blocked.* = false;
            return err;
        };
        handlers_are_acquired.* = false;

        try signal_mask.restore();
        mask_is_blocked.* = false;

        return switch (outcome) {
            .success => |result| result,
            .failure => |err| err,
        };
    }

    fn currentStackBounds() !StackBounds {
        if (comptime builtin.target.os.tag == .macos) {
            const thread = c.pthread_self();
            const high_pointer = c.pthread_get_stackaddr_np(thread) orelse
                return error.StackBoundsUnavailable;
            const stack_size = c.pthread_get_stacksize_np(thread);
            if (stack_size == 0) return error.StackBoundsUnavailable;

            const high = @intFromPtr(high_pointer);
            if (stack_size > high) return error.StackBoundsUnavailable;
            return .{
                .low = high - stack_size,
                .high = high,
                .guard_size = guard_slack,
            };
        }

        var attributes: c.pthread_attr_t = undefined;
        if (c.pthread_getattr_np(c.pthread_self(), &attributes) != 0) {
            return error.StackBoundsUnavailable;
        }
        defer _ = c.pthread_attr_destroy(&attributes);

        var stack_pointer: ?*anyopaque = null;
        var stack_size: usize = 0;
        if (c.pthread_attr_getstack(&attributes, &stack_pointer, &stack_size) != 0) {
            return error.StackBoundsUnavailable;
        }
        const low = @intFromPtr(stack_pointer orelse return error.StackBoundsUnavailable);
        if (stack_size == 0 or low > std.math.maxInt(usize) - stack_size) {
            return error.StackBoundsUnavailable;
        }

        var guard_size: usize = 0;
        if (c.pthread_attr_getguardsize(&attributes, &guard_size) != 0) {
            return error.StackBoundsUnavailable;
        }
        return .{
            .low = low,
            .high = low + stack_size,
            .guard_size = guard_size,
        };
    }

    fn isStackGuardFault(scope: *const RecoveryScope, info: [*c]c.siginfo_t) bool {
        const fault_address = faultAddress(info) orelse return false;
        const address = @intFromPtr(fault_address);
        const guard_low = scope.bounds.low -| guard_slack;
        const guard_high = @min(
            scope.bounds.high,
            scope.bounds.low +| @max(scope.bounds.guard_size, guard_slack),
        );
        return address >= guard_low and address < guard_high;
    }

    fn faultAddress(info: [*c]c.siginfo_t) ?*anyopaque {
        if (info == null) return null;
        if (comptime @hasField(c.siginfo_t, "si_addr")) {
            return info.*.si_addr;
        }
        if (comptime @hasField(c.siginfo_t, "_sifields")) {
            return info.*._sifields._sigfault.si_addr;
        }
        return info.*.__si_fields.__sigfault.si_addr;
    }

    export fn signalHandler(sig: c_int, info: [*c]c.siginfo_t, ucontext: ?*anyopaque) callconv(.c) void {
        _ = handlers_in_flight.fetchAdd(1, .acq_rel);

        if (active_scope) |scope| {
            if (isStackGuardFault(scope, info)) {
                _ = handlers_in_flight.fetchSub(1, .acq_rel);
                c.siglongjmp(&scope.jump_environment, 1);
            }
        }

        const previous = if (sig == c.SIGSEGV) previous_sigsegv else previous_sigbus;
        _ = handlers_in_flight.fetchSub(1, .acq_rel);
        callPreviousHandler(previous, sig, info, ucontext);
    }

    fn acquireHandlers() !void {
        lockHandlerMutex();
        defer handler_mutex.unlock();

        if (handler_users == 0) {
            var action = std.mem.zeroes(c.struct_sigaction);
            setSiginfoHandler(&action, signalHandler);
            if (c.sigemptyset(&action.sa_mask) != 0) return error.SignalHandlerSetupFailed;
            action.sa_flags = c.SA_SIGINFO | c.SA_ONSTACK;

            if (c.sigaction(c.SIGSEGV, &action, &previous_sigsegv) != 0) {
                return error.SignalHandlerSetupFailed;
            }
            if (c.sigaction(c.SIGBUS, &action, &previous_sigbus) != 0) {
                _ = c.sigaction(c.SIGSEGV, &previous_sigsegv, null);
                return error.SignalHandlerSetupFailed;
            }
        }
        handler_users += 1;
    }

    fn releaseHandlers() !void {
        lockHandlerMutex();
        defer handler_mutex.unlock();

        std.debug.assert(handler_users > 0);
        handler_users -= 1;
        if (handler_users != 0) return;

        var restore_failed = false;
        restoreActionIfOwned(c.SIGSEGV, &previous_sigsegv) catch {
            restore_failed = true;
        };
        restoreActionIfOwned(c.SIGBUS, &previous_sigbus) catch {
            restore_failed = true;
        };

        while (handlers_in_flight.load(.acquire) != 0) {
            std.atomic.spinLoopHint();
        }
        if (restore_failed) return error.SignalHandlerRestoreFailed;
    }

    fn lockHandlerMutex() void {
        while (!handler_mutex.tryLock()) std.atomic.spinLoopHint();
    }

    fn restoreActionIfOwned(sig: c_int, previous: *const c.struct_sigaction) !void {
        var current: c.struct_sigaction = undefined;
        if (c.sigaction(sig, null, &current) != 0) return error.SignalHandlerRestoreFailed;
        if (!actionUsesOurHandler(&current)) return;
        if (c.sigaction(sig, previous, null) != 0) return error.SignalHandlerRestoreFailed;
    }

    fn setSiginfoHandler(action: *c.struct_sigaction, handler: SignalHandler) void {
        if (comptime builtin.target.os.tag == .macos) {
            action.__sigaction_u.__sa_sigaction = handler;
        } else {
            action.__sigaction_handler.sa_sigaction = handler;
        }
    }

    fn actionUsesOurHandler(action: *const c.struct_sigaction) bool {
        if ((action.sa_flags & c.SA_SIGINFO) == 0) return false;
        const handler = if (comptime builtin.target.os.tag == .macos)
            action.__sigaction_u.__sa_sigaction
        else
            action.__sigaction_handler.sa_sigaction;
        return handler != null and @intFromPtr(handler.?) == @intFromPtr(&signalHandler);
    }

    fn callPreviousHandler(
        action: c.struct_sigaction,
        sig: c_int,
        info: [*c]c.siginfo_t,
        ucontext: ?*anyopaque,
    ) void {
        if ((action.sa_flags & c.SA_SIGINFO) != 0) {
            const handler: ?SignalHandler = if (comptime builtin.target.os.tag == .macos)
                action.__sigaction_u.__sa_sigaction
            else
                action.__sigaction_handler.sa_sigaction;
            if (handler) |function| {
                const address = @intFromPtr(function);
                if (address == 1) return; // SIG_IGN
                if (address != @intFromPtr(&signalHandler)) {
                    function(sig, info, ucontext);
                    return;
                }
            }
            restoreDefaultAndReraise(sig);
            return;
        }

        const handler: ?SimpleSignalHandler = if (comptime builtin.target.os.tag == .macos)
            action.__sigaction_u.__sa_handler
        else
            action.__sigaction_handler.sa_handler;
        if (handler) |function| {
            const address = @intFromPtr(function);
            if (address == 1) return; // SIG_IGN
            function(sig);
            return;
        }
        restoreDefaultAndReraise(sig);
    }

    fn restoreDefaultAndReraise(sig: c_int) void {
        var action = std.mem.zeroes(c.struct_sigaction);
        if (c.sigemptyset(&action.sa_mask) != 0) c._exit(128 + sig);
        if (c.sigaction(sig, &action, null) != 0) c._exit(128 + sig);
        if (c.kill(c.getpid(), sig) != 0) c._exit(128 + sig);
    }
} else struct {};

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

test "stack overflow diagnostic captures parser location and token" {
    var input = [_]u8{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 0 };
    var context: root.data_structures.Context = .{
        .chunk_buffer = &input,
    };
    context.token.reset(&input);

    const expected_token = if (comptime root.config.indentation_syntax) token: {
        context.seek = 6;
        context.token.append('x');
        context.token.append('y');
        break :token "xy";
    } else token: {
        context.token.head = 6;
        context.token.len = 2;
        break :token "45";
    };
    if (comptime builtin.mode != .ReleaseFast) {
        context.line = 7;
        context.column = 9;
    }

    const diagnostic = stackOverflowDiagnostic(&context);
    try std.testing.expectEqual(
        @as(u32, if (builtin.mode != .ReleaseFast) 7 else 0),
        diagnostic.line,
    );
    try std.testing.expectEqual(
        @as(u32, if (builtin.mode != .ReleaseFast) 9 else 0),
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

test "protected call restores signal handlers and alternate stack" {
    if (comptime !is_supported) return error.SkipZigTest;

    const c = Posix.c;
    var sigsegv_before: c.struct_sigaction = undefined;
    var sigbus_before: c.struct_sigaction = undefined;
    var alternate_stack_before: c.stack_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), c.sigaction(c.SIGSEGV, null, &sigsegv_before));
    try std.testing.expectEqual(@as(c_int, 0), c.sigaction(c.SIGBUS, null, &sigbus_before));
    try std.testing.expectEqual(@as(c_int, 0), c.sigaltstack(null, &alternate_stack_before));

    var marker: u8 = 0;
    try Posix.protectedCall(void, TestCallbacks.noop, &marker);

    var sigsegv_after: c.struct_sigaction = undefined;
    var sigbus_after: c.struct_sigaction = undefined;
    var alternate_stack_after: c.stack_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), c.sigaction(c.SIGSEGV, null, &sigsegv_after));
    try std.testing.expectEqual(@as(c_int, 0), c.sigaction(c.SIGBUS, null, &sigbus_after));
    try std.testing.expectEqual(@as(c_int, 0), c.sigaltstack(null, &alternate_stack_after));

    try std.testing.expectEqual(actionHandlerAddress(&sigsegv_before), actionHandlerAddress(&sigsegv_after));
    try std.testing.expectEqual(actionHandlerAddress(&sigbus_before), actionHandlerAddress(&sigbus_after));
    try std.testing.expectEqual(sigsegv_before.sa_flags, sigsegv_after.sa_flags);
    try std.testing.expectEqual(sigbus_before.sa_flags, sigbus_after.sa_flags);
    try std.testing.expectEqual(alternate_stack_before.ss_sp, alternate_stack_after.ss_sp);
    try std.testing.expectEqual(alternate_stack_before.ss_size, alternate_stack_after.ss_size);
    try std.testing.expectEqual(alternate_stack_before.ss_flags, alternate_stack_after.ss_flags);
}

test "protected call converts a real guard-page fault to StackOverflow" {
    if (comptime !is_supported) return error.SkipZigTest;

    var result: ?anyerror = null;
    const thread = try std.Thread.spawn(
        .{},
        TestCallbacks.overflowThread,
        .{&result},
    );
    thread.join();

    try std.testing.expect(result != null);
    try std.testing.expectEqual(root.ParseError.StackOverflow, result.?);
}

test "protected call chains unrelated faults to the previous handler" {
    if (comptime !is_supported) return error.SkipZigTest;

    const c = Posix.c;
    var previous: c.struct_sigaction = undefined;
    var action = std.mem.zeroes(c.struct_sigaction);
    Posix.setSiginfoHandler(&action, TestCallbacks.recordSignal);
    try std.testing.expectEqual(@as(c_int, 0), c.sigemptyset(&action.sa_mask));
    action.sa_flags = c.SA_SIGINFO;
    try std.testing.expectEqual(@as(c_int, 0), c.sigaction(c.SIGSEGV, &action, &previous));
    defer _ = c.sigaction(c.SIGSEGV, &previous, null);

    TestCallbacks.signal_count.store(0, .release);
    var marker: u8 = 0;
    try Posix.protectedCall(void, TestCallbacks.raiseSegv, &marker);
    try std.testing.expectEqual(@as(usize, 1), TestCallbacks.signal_count.load(.acquire));

    var current: c.struct_sigaction = undefined;
    try std.testing.expectEqual(@as(c_int, 0), c.sigaction(c.SIGSEGV, null, &current));
    try std.testing.expectEqual(@intFromPtr(&TestCallbacks.recordSignal), actionHandlerAddress(&current));
}

const TestCallbacks = if (is_supported) struct {
    var signal_count = std.atomic.Value(usize).init(0);

    fn noop(_: *anyopaque) !void {}

    fn raiseSegv(_: *anyopaque) !void {
        if (Posix.c.raise(Posix.c.SIGSEGV) != 0) return error.SignalRaiseFailed;
    }

    fn recordSignal(_: c_int, _: [*c]Posix.c.siginfo_t, _: ?*anyopaque) callconv(.c) void {
        _ = signal_count.fetchAdd(1, .acq_rel);
    }

    fn overflowThread(result: *?anyerror) void {
        var marker: u8 = 0;
        _ = Posix.protectedCall(void, overflow, &marker) catch |err| {
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

fn actionHandlerAddress(action: *const Posix.c.struct_sigaction) usize {
    if ((action.sa_flags & Posix.c.SA_SIGINFO) != 0) {
        const handler = if (comptime builtin.target.os.tag == .macos)
            action.__sigaction_u.__sa_sigaction
        else
            action.__sigaction_handler.sa_sigaction;
        return if (handler) |function| @intFromPtr(function) else 0;
    }
    const handler = if (comptime builtin.target.os.tag == .macos)
        action.__sigaction_u.__sa_handler
    else
        action.__sigaction_handler.sa_handler;
    return if (handler) |function| @intFromPtr(function) else 0;
}
