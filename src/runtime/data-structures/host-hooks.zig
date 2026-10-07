//! Per-session hook state for hosts: the enabled set, the dispatch
//! callback, and (through `Context.user_data`) the host handle.
//!
//! The generated host shim (`host_procedures.zig`) declares
//! `host_hook_names` and forwards every hook through `forward`. A hook
//! that is not enabled on the parsing session returns after one load from
//! the parse `Context`; an enabled one calls the session's dispatch
//! callback with the session's handle. Nothing here is shared between
//! sessions, so independent sessions of one library hook independently.

const builtin = @import("builtin");
const root = @import("galley");
const data_structures = root.data_structures;

/// Hook names in index order, as the linked shim declares them. Empty for
/// builds whose `procedures` module is not a host shim (Zig or extern
/// hooks), where no session carries any enabled hook.
pub const hook_names: []const []const u8 = if (@hasDecl(root.procedures, "host_hook_names"))
    &root.procedures.host_hook_names
else
    &.{};

pub const hook_count = hook_names.len;

/// Host callback for one hook call. `handle` is the session's
/// `Context.user_data`, `index` the position in `hook_names`, and `hook` the
/// ticket of this call: the only way to reach its arguments, through the
/// `galley_procedure_*` functions, and refused once the call has returned.
pub const Dispatch = *const fn (handle: ?*anyopaque, index: u32, hook: u64) callconv(.c) void;

/// The hook state a session copies onto every parse `Context`.
pub const HostHooks = struct {
    enabled: [hook_count]bool = @splat(false),
    /// Unused on WebAssembly, where the host provides `galley_host_dispatch`
    /// as an import instead.
    dispatch: ?Dispatch = null,
};

/// The WebAssembly host's dispatch import. A wasm function pointer is a
/// table index the host cannot mint, so wasm hosts receive hooks through
/// this import and route by handle exactly like the native callback.
const wasm_dispatch = struct {
    extern "env" fn galley_host_dispatch(handle: ?*anyopaque, index: u32, hook: u64) void;
};

/// The one forwarding site of every host shim hook: the call runs under a
/// fresh ticket that names its arguments for exactly as long as it runs.
pub inline fn forward(comptime index: u32, args: *data_structures.ProcedureArguments) void {
    const context = args.context;
    if (!context.host_hooks.enabled[index]) return;
    const runtime = context.runtime();
    const hook = runtime.enterHook(args);
    defer runtime.exitHook();
    if (comptime builtin.cpu.arch.isWasm()) {
        wasm_dispatch.galley_host_dispatch(context.user_data, index, hook);
    } else if (context.host_hooks.dispatch) |dispatch| {
        dispatch(context.user_data, index, hook);
    }
}

/// The one calling site of every hook compiled into the library from C or
/// C++: the hook receives its session and a ticket for this call, exactly
/// what a host's dispatch receives, and nothing that outlives the call.
pub inline fn callCompiled(args: *data_structures.ProcedureArguments, hook_function: *const fn (?*anyopaque, u64) callconv(.c) void) void {
    const runtime = args.context.runtime();
    const hook = runtime.enterHook(args);
    defer runtime.exitHook();
    hook_function(runtime.owner, hook);
}
