//! Hand-written C ABI bindings for the POSIX signal, thread, and
//! jump interfaces that `signals.zig` uses.
//!
//! Zig 0.17 removed `@cImport`. Rather than translate the system headers
//! at build time, the struct types here alias the platform-verified
//! layouts in `std.c`, and the functions and constants are declared in
//! the exact shapes the call sites use. Only the two platforms with
//! signal support (`is_supported` in `signals.zig`) need constants, and
//! the layouts live in the standard library, which tracks the libcs.
//!
//! Signal-support platforms: Linux (glibc and musl) and macOS.
const builtin = @import("builtin");
const std = @import("std");

// Layouts: std.c switches on the target for every one of these, so the
// glibc/musl/Darwin differences are owned by the standard library.
pub const sigset_t = std.c.sigset_t;
pub const stack_t = std.c.stack_t;
pub const siginfo_t = std.c.siginfo_t;
pub const pthread_attr_t = std.c.pthread_attr_t;
pub const pthread_t = std.c.pthread_t;
pub const struct_sigaction = std.c.Sigaction;

/// The handler union inside `std.c.Sigaction`: one `handler` field whose
/// members are `handler` (simple) and `sigaction` (SA_SIGINFO). Named the
/// same on every supported libc.
pub const sigaction_fn = std.c.Sigaction.sigaction_fn;

/// Opaque jump state: written and read only by `sigsetjmp`/`siglongjmp`,
/// never field-accessed here. Oversized (512 bytes) to hold every
/// supported libc's `sigjmp_buf`; the largest is under 400.
pub const sigjmp_buf = extern struct {
    bytes: [64]u64,
};

// Signal numbers: taken from the per-platform std.c.SIG enum rather than
// hardcoded (SIGBUS differs between Linux and macOS).
pub const SIGSEGV: c_int = @backingInt(std.c.SIG.SEGV);
pub const SIGBUS: c_int = @backingInt(std.c.SIG.BUS);

// SA_* values differ per platform: Linux follows asm-generic
// (`asm-generic/signal.h`, verified against the bundled kernel headers),
// macOS follows its BSD `sys/signal.h`. Typed `c_uint` to match the
// `sa_flags` field on both.
pub const SA_ONSTACK: c_uint = switch (builtin.target.os.tag) {
    .linux => 0x08000000,
    .macos => 0x0001,
    else => @compileError("SA_ONSTACK supports only linux and macos"),
};
pub const SA_SIGINFO: c_uint = switch (builtin.target.os.tag) {
    .linux => 0x00000004,
    .macos => 0x0040,
    else => @compileError("SA_SIGINFO supports only linux and macos"),
};

// `how` values for `sigprocmask`/`pthread_sigmask`. These are NOT
// uniform: Linux (musl `signal.h`) uses 0/1/2, Darwin (`sys/signal.h`)
// 1/2/3, and pthread_sigmask rejects the wrong numbering with EINVAL.
pub const SIG_BLOCK: c_int = switch (builtin.target.os.tag) {
    .linux => 0,
    .macos => 1,
    else => @compileError("SIG_BLOCK supports only linux and macos"),
};
pub const SIG_SETMASK: c_int = switch (builtin.target.os.tag) {
    .linux => 2,
    .macos => 3,
    else => @compileError("SIG_SETMASK supports only linux and macos"),
};

/// musl extension (musl `signal.h`: `(1U << 31)`); glibc does not define
/// it, so `signals.zig` enables it only when targeting musl.
pub const SS_AUTODISARM: u32 = 1 << 31;

pub extern "c" fn sigemptyset(set: ?*sigset_t) c_int;
pub extern "c" fn sigaddset(set: ?*sigset_t, signum: c_int) c_int;
pub extern "c" fn sigismember(set: ?*const sigset_t, signum: c_int) c_int;
pub extern "c" fn sigprocmask(how: c_int, set: ?*const sigset_t, oldset: ?*sigset_t) c_int;
pub extern "c" fn pthread_sigmask(how: c_int, set: ?*const sigset_t, oldset: ?*sigset_t) c_int;
pub extern "c" fn sigaltstack(ss: ?*const stack_t, oss: ?*stack_t) c_int;
pub extern "c" fn sigaction(sig: c_int, act: ?*const struct_sigaction, oact: ?*struct_sigaction) c_int;
// glibc exports no `sigsetjmp` symbol: its `setjmp.h` defines the name as a
// macro over the real symbol (`# define sigsetjmp(env, savemask) __sigsetjmp
// (env, savemask)`), so binding the bare spelling fails to link on glibc.
// musl and Darwin export `sigsetjmp` itself. Selecting the symbol here keeps
// every call site on `sigsetjmp`, mirroring what the system header does.
const glibcSigsetjmp = struct {
    extern "c" fn __sigsetjmp(env: [*c]sigjmp_buf, savemask: c_int) c_int;
}.__sigsetjmp;
const libcSigsetjmp = struct {
    extern "c" fn sigsetjmp(env: [*c]sigjmp_buf, savemask: c_int) c_int;
}.sigsetjmp;
pub const sigsetjmp = if (builtin.target.abi == .gnu) glibcSigsetjmp else libcSigsetjmp;
pub extern "c" fn siglongjmp(env: [*c]sigjmp_buf, val: c_int) noreturn;

pub extern "c" fn pthread_self() pthread_t;
pub extern "c" fn pthread_attr_destroy(attr: ?*pthread_attr_t) c_int;
pub extern "c" fn pthread_attr_getguardsize(attr: ?*const pthread_attr_t, guardsize: ?*usize) c_int;
pub extern "c" fn pthread_attr_getstack(
    attr: ?*const pthread_attr_t,
    stackaddr: ?*?*anyopaque,
    stacksize: ?*usize,
) c_int;
/// Linux (glibc and musl): describes the stack of a running thread.
pub extern "c" fn pthread_getattr_np(thread: pthread_t, attr: ?*pthread_attr_t) c_int;
/// macOS counterparts of `pthread_getattr_np` + `pthread_attr_getstack`.
pub extern "c" fn pthread_get_stackaddr_np(thread: pthread_t) ?*anyopaque;
pub extern "c" fn pthread_get_stacksize_np(thread: pthread_t) usize;

pub extern "c" fn kill(pid: c_int, sig: c_int) c_int;
pub extern "c" fn getpid() c_int;
pub extern "c" fn raise(sig: c_int) c_int;
pub extern "c" fn _exit(code: c_int) noreturn;
