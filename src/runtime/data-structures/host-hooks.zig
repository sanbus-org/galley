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
/// `Context.user_data`, `index` the position in `hook_names`, and `args` a
/// `ProcedureArguments` valid only until the call returns.
pub const Dispatch = *const fn (handle: ?*anyopaque, index: u32, args: ?*anyopaque) callconv(.c) void;

/// The hook state a session copies onto every parse `Context`.
pub const HostHooks = struct {
    enabled: [hook_count]bool = .{false} ** hook_count,
    /// Unused on WebAssembly, where the host provides `galley_host_dispatch`
    /// as an import instead.
    dispatch: ?Dispatch = null,
};

/// The WebAssembly host's dispatch import. A wasm function pointer is a
/// table index the host cannot mint, so wasm hosts receive hooks through
/// this import and route by handle exactly like the native callback.
const wasm_dispatch = struct {
    extern "env" fn galley_host_dispatch(handle: ?*anyopaque, index: u32, args: ?*anyopaque) void;
};

/// The one forwarding site of every host shim hook.
pub inline fn forward(comptime index: u32, args: *data_structures.ProcedureArguments) void {
    const context = args.context;
    if (!context.host_hooks.enabled[index]) return;
    if (comptime builtin.cpu.arch.isWasm()) {
        wasm_dispatch.galley_host_dispatch(context.user_data, index, @ptrCast(args));
    } else if (context.host_hooks.dispatch) |dispatch| {
        dispatch(context.user_data, index, @ptrCast(args));
    }
}
