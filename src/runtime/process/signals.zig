const builtin = @import("builtin");
const std = @import("std");

/// Process-wide signal registry for stack-overflow recovery.
///
/// This module is intentionally free of Galley parser dependencies: it
/// touches only C signal state, the alternate stack, and thread masks, so a
/// single module instance can be shared by every runtime instantiation in
/// one binary. Sharing is what makes the registry process-wide: one
/// disposition pair, one refcount, one in-flight counter. A second copy of
/// this file in the same process (a separately built language library)
/// reintroduces per-copy registries over one signal disposition; that
/// multi-dylib case stays opt-in (see docs/concurrency.md).
///
/// All mutable state in this file is process scope (see
/// `docs/concurrency.md`). The only thread-local is the active recovery
/// scope, written by the parsing thread around its protected call.
pub const is_supported = switch (builtin.target.os.tag) {
    .linux, .macos => true,
    else => false,
};

pub const Signals = if (is_supported) PosixSignals else UnsupportedSignals;

const UnsupportedSignals = struct {
    pub fn protectedCall(
        comptime T: type,
        callback: *const fn (*anyopaque) anyerror!T,
        opaque_context: *anyopaque,
        overflow_error: anyerror,
    ) anyerror!T {
        _ = callback;
        _ = opaque_context;
        _ = overflow_error;
        return error.StackOverflowRecoveryUnsupported;
    }
};

const PosixSignals = struct {
    // Hand-written POSIX bindings; see c.zig.
    pub const c = @import("c");

    // The handler union (`action.handler`) has the same member names on
    // every supported libc; the casts bridge ABI-compatible signature
    // spellings (the C `int` signal number vs the std.c.SIG enum, C
    // pointers vs C-ABI pointers).
    fn writeSigactionHandler(action: *c.struct_sigaction, handler: SignalHandler) void {
        const function: c.sigaction_fn = @ptrCast(handler);
        action.handler.sigaction = function;
    }

    fn readSigactionHandler(action: *const c.struct_sigaction) ?SignalHandler {
        const function = action.handler.sigaction orelse return null;
        const handler: SignalHandler = @ptrCast(function);
        return handler;
    }

    fn readSimpleHandler(action: *const c.struct_sigaction) ?SimpleSignalHandler {
        const function = action.handler.handler orelse return null;
        const widened: *align(1) const fn (c_int) callconv(.c) void = @ptrCast(function);
        const handler: SimpleSignalHandler = @alignCast(widened);
        return handler;
    }

    pub const SignalHandler = *const fn (c_int, [*c]c.siginfo_t, ?*anyopaque) callconv(.c) void;
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
        thread_previous: c.sigset_t,
        process_previous: if (builtin.target.os.tag == .macos) c.sigset_t else void,

        pub fn block() !SignalMask {
            var faults: c.sigset_t = undefined;
            if (c.sigemptyset(&faults) != 0) return error.SignalMaskSetupFailed;
            if (c.sigaddset(&faults, c.SIGSEGV) != 0) return error.SignalMaskSetupFailed;
            if (c.sigaddset(&faults, c.SIGBUS) != 0) return error.SignalMaskSetupFailed;

            const process_previous = if (comptime builtin.target.os.tag == .macos) previous: {
                var value: c.sigset_t = undefined;
                if (c.sigprocmask(c.SIG_BLOCK, null, &value) != 0) {
                    return error.SignalMaskSetupFailed;
                }
                break :previous value;
            } else {};

            var thread_previous: c.sigset_t = undefined;
            if (c.pthread_sigmask(c.SIG_BLOCK, &faults, &thread_previous) != 0) {
                return error.SignalMaskSetupFailed;
            }
            return .{
                .faults = faults,
                .thread_previous = thread_previous,
                .process_previous = process_previous,
            };
        }

        pub fn restore(self: *const SignalMask, restore_process: bool) !void {
            if (c.pthread_sigmask(c.SIG_SETMASK, &self.thread_previous, null) != 0) {
                return error.SignalMaskRestoreFailed;
            }
            if (restore_process and comptime builtin.target.os.tag == .macos) {
                // Darwin's siglongjmp restores the setup-time mask process-wide.
                // Undo that only after a recovered signal; successful calls never
                // change the process mask.
                if (c.sigprocmask(c.SIG_SETMASK, &self.process_previous, null) != 0) {
                    return error.SignalMaskRestoreFailed;
                }
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

        pub fn install() !AlternateStack {
            const memory = try std.heap.page_allocator.alloc(u8, alternate_stack_size);
            errdefer std.heap.page_allocator.free(memory);

            var previous: c.stack_t = undefined;
            if (c.sigaltstack(null, &previous) != 0) return error.SignalStackSetupFailed;

            var replacement = std.mem.zeroes(c.stack_t);
            replacement.sp = memory.ptr;
            replacement.size = @intCast(memory.len);
            // musl types SS_AUTODISARM as an unsigned bit that does not fit
            // c_int; bit-cast to keep the pattern on every libc. glibc does
            // not define the extension, so it stays off there.
            replacement.flags = if (comptime builtin.target.abi.isMusl())
                @as(@TypeOf(replacement.flags), @bitCast(c.SS_AUTODISARM))
            else
                0;
            if (c.sigaltstack(&replacement, null) != 0) return error.SignalStackSetupFailed;

            return .{ .memory = memory, .previous = previous };
        }

        pub fn restore(self: *AlternateStack) !void {
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

    /// The one thread-local in the registry: the protected call's landing
    /// scope. Written only by the parsing thread around its own protected
    /// call (set before `sigsetjmp`, cleared on the converged path), read
    /// only by the signal handler on the faulting thread.
    pub threadlocal var active_scope: ?*RecoveryScope = null;

    var handler_mutex: std.atomic.Mutex = .unlocked;
    var handler_users: usize = 0;
    var previous_sigsegv: c.struct_sigaction = undefined;
    var previous_sigbus: c.struct_sigaction = undefined;
    var handlers_in_flight = std.atomic.Value(usize).init(0);

    /// Runs `callback` with stack-overflow recovery. `overflow_error` is the
    /// failure value reported for a recovered guard-page fault; it arrives
    /// as a parameter so this shared module never names a parser error.
    /// Scopes stack: a nested protected call pushes a new scope (saving the
    /// previous one) so an inner fault is caught by the inner scope and the
    /// outer parse continues with its own scope intact.
    pub fn protectedCall(
        comptime T: type,
        callback: *const fn (*anyopaque) anyerror!T,
        opaque_context: *anyopaque,
        overflow_error: anyerror,
    ) anyerror!T {
        const previous_scope = active_scope;

        const signal_mask = try SignalMask.block();
        var mask_is_blocked = true;
        errdefer if (mask_is_blocked) signal_mask.restore(false) catch {};

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
            signal_mask.restore(false) catch |err| {
                outcome = .{ .failure = err };
                active_scope = previous_scope;
                return finishProtectedCall(
                    T,
                    outcome,
                    &signal_mask,
                    &mask_is_blocked,
                    &alternate_stack,
                    &alternate_stack_is_installed,
                    &handlers_are_acquired,
                    false,
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
            outcome = .{ .failure = overflow_error };
        }

        active_scope = previous_scope;
        return finishProtectedCall(
            T,
            outcome,
            &signal_mask,
            &mask_is_blocked,
            &alternate_stack,
            &alternate_stack_is_installed,
            &handlers_are_acquired,
            jump_result != 0,
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
        restore_process_mask: bool,
    ) anyerror!T {
        alternate_stack.restore() catch |err| {
            alternate_stack_is_installed.* = false;
            releaseHandlers() catch {};
            handlers_are_acquired.* = false;
            signal_mask.restore(restore_process_mask) catch {};
            mask_is_blocked.* = false;
            return err;
        };
        alternate_stack_is_installed.* = false;

        releaseHandlers() catch |err| {
            handlers_are_acquired.* = false;
            signal_mask.restore(restore_process_mask) catch {};
            mask_is_blocked.* = false;
            return err;
        };
        handlers_are_acquired.* = false;

        try signal_mask.restore(restore_process_mask);
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
        // Linux keeps the fault address in the `sigfault` union of
        // `fields`; Darwin's siginfo_t is flat and names it `addr`.
        if (comptime @hasField(c.siginfo_t, "fields")) {
            return info.*.fields.sigfault.addr;
        } else {
            return info.*.addr;
        }
    }

    fn signalHandler(sig: c_int, info: [*c]c.siginfo_t, ucontext: ?*anyopaque) callconv(.c) void {
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
            if (c.sigemptyset(&action.mask) != 0) return error.SignalHandlerSetupFailed;
            action.flags = c.SA_SIGINFO | c.SA_ONSTACK;

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

    pub fn setSiginfoHandler(action: *c.struct_sigaction, handler: SignalHandler) void {
        writeSigactionHandler(action, handler);
    }

    fn actionUsesOurHandler(action: *const c.struct_sigaction) bool {
        if ((action.flags & c.SA_SIGINFO) == 0) return false;
        const handler = readSigactionHandler(action);
        return handler != null and @intFromPtr(handler.?) == @intFromPtr(&signalHandler);
    }

    fn callPreviousHandler(
        action: c.struct_sigaction,
        sig: c_int,
        info: [*c]c.siginfo_t,
        ucontext: ?*anyopaque,
    ) void {
        if ((action.flags & c.SA_SIGINFO) != 0) {
            const handler: ?SignalHandler = readSigactionHandler(&action);
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

        const handler: ?SimpleSignalHandler = readSimpleHandler(&action);
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
        if (c.sigemptyset(&action.mask) != 0) c._exit(128 + sig);
        if (c.sigaction(sig, &action, null) != 0) c._exit(128 + sig);
        if (c.kill(c.getpid(), sig) != 0) c._exit(128 + sig);
    }
};
