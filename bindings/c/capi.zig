//! C application-binary interface for a generated Galley parser.
//!
//! Built as a shared library through `bindings/c/consumer/build.zig` (the
//! external entry point: pass the language directory with `-Dlanguage-dir`
//! (or the generated parser source with `-Dparser-source`) and the library
//! name with `-Dlib-name`). The C header
//! shipped next to the library is `bindings/c/galley.h`; the examples in
//! `examples/c` and `examples/cpp` are reference consumers.
//!
//! Sessions own their IO backend and allocator (the C allocator) and are not
//! thread-safe: use one session per thread, or guard it externally. Node
//! addresses, text pointers, and diagnostics remain valid until the next
//! parse on the same session or session destruction. Every call that reads or
//! edits nodes, on either door, carries the parse generation it addresses
//! (`galley_root_node` and `galley_hook_generation` report it), and one gate
//! refuses a generation that is not live, so a node of a dead parse is never
//! read.
//!
//! Scope notes: semantic payloads are unavailable, procedure hooks and
//! error-message hooks are compiled into the library from the consumer's
//! procedures and error-messages files (see the bindings docs).

const std = @import("std");
const builtin = @import("builtin");
const root = @import("galley");
const parser = root.parser;
const tree_walker = root.data_structures.tree_walker;
const capi_options = @import("capi_options");

/// Opaque session handle owned by the C side.
pub const GalleySession = opaque {};

/// Session creation options; zero/negative fields select defaults. Mirrors
/// `GalleyCOptions` in `galley.h`.
pub const GalleyCOptions = extern struct {
    max_errors: c_int = 0,
    recovery_window: c_int = 0,
    stack_overflow_recovery: c_int = 0,
    syntax_error_stack_depth: c_uint = 0,
    /// Debug-build parse tracing level; ignored in release builds.
    verbosity: c_int = 0,
    /// Nodes preallocated per byte of input. Negative selects the runtime
    /// default (2.0); 0 disables the ratio contribution (the floor still applies).
    /// The scaled contribution reserves address space without committed
    /// pages on reserved-arena platforms; on segment platforms (Windows,
    /// wasm) it is ignored and only the floor below is prepared eagerly.
    ast_preallocation_ratio: f64 = -1.0,
    /// Minimum ready node storage per parse; 0 selects the runtime default.
    /// Demand past the reservation appends segments, so this bounds the
    /// fast path rather than total capacity.
    ast_preallocation_cap: u64 = 0,
};

/// Node addresses are stable indices into the session's node storage.
pub const GalleyNodeAddress = u64;

/// Returned by tree queries when no node exists at that position. Every
/// address and this sentinel are non-negative (`INT64_MAX`), so a
/// value-returning call can report a negative status in the same `long long`.
pub const galley_invalid_node: GalleyNodeAddress = std.math.maxInt(i64);

/// Returned by `galley_node_variable_index` (and written to the snapshot's
/// variable column) for a node that has no variable. Non-negative, like
/// `galley_invalid_node`: only statuses are negative.
pub const galley_no_variable: i64 = std.math.maxInt(i64);

/// Status codes returned by parse and accessor functions. Non-negative
/// values are success; negative values are failures, and
/// `galley_status_string` renders them for diagnostics.
pub const galley_ok: i64 = 0;
pub const galley_error_null_argument: i64 = -1;
pub const galley_error_syntax: i64 = -2;
pub const galley_error_indentation: i64 = -3;
pub const galley_error_stack_overflow: i64 = -4;
pub const galley_error_ast_capacity_exceeded: i64 = -5;
pub const galley_error_unterminated_raw_string: i64 = -6;
pub const galley_error_out_of_memory: i64 = -7;
pub const galley_error_internal: i64 = -8;
pub const galley_error_no_diagnostic: i64 = -9;
pub const galley_error_invalid_node: i64 = -10;
pub const galley_error_io: i64 = -11;
pub const galley_error_semantic: i64 = -12;
/// The session is held by a concurrent operation: a parse while another
/// parse or a gated read/mutation is in flight, or a post-parse call from
/// inside a hook that holds the parse exclusively. Retry after it finishes.
pub const galley_error_session_in_use: i64 = -13;
/// A node, tree, or walk cursor addresses a tree that no longer exists: the
/// generation it carries is not the session's published tree's (the session
/// parsed again, the last parse failed and published nothing, or nothing was
/// ever published), and in a hook the generation is not that parse's.
pub const galley_error_stale_tree: i64 = -14;

/// Diagnostic kinds returned by `galley_diagnostic_kind`.
pub const galley_diagnostic_kind_none: i64 = 0;
pub const galley_diagnostic_kind_syntax: i64 = 1;
pub const galley_diagnostic_kind_indentation: i64 = 2;
pub const galley_diagnostic_kind_semantic: i64 = 3;

/// Recovery target kinds returned by `galley_diagnostic_recovery_kind`.
pub const galley_recovery_target_none: i64 = 0;
pub const galley_recovery_target_lhs_variable: i64 = 1;
pub const galley_recovery_target_production: i64 = 2;
pub const galley_recovery_target_occurrence: i64 = 3;

/// Resume sides returned by `galley_diagnostic_recovery_resume`.
pub const galley_resume_before: i64 = 0;
pub const galley_resume_after: i64 = 1;

/// Parser families returned by `galley_parser_type`.
pub const galley_parser_type_ll: i64 = 0;
pub const galley_parser_type_lr: i64 = 1;

/// Error-recovery modes returned by `galley_error_recovery_mode`.
pub const galley_recovery_mode_disabled: i64 = 0;
pub const galley_recovery_mode_automatic: i64 = 1;
pub const galley_recovery_mode_explicit: i64 = 2;

var version_buffer: [capi_options.version.len + 1]u8 = blk: {
    var buffer: [capi_options.version.len + 1]u8 = undefined;
    @memcpy(buffer[0..capi_options.version.len], capi_options.version);
    buffer[capi_options.version.len] = 0;
    break :blk buffer;
};

/// Returns the build-supplied version string of this library.
export fn galley_version() [*:0]const u8 {
    return @ptrCast(&version_buffer);
}

const Embedded = struct {
    threaded: std.Io.Threaded,
    session: root.Session,
    rendered_diagnostic: ?[:0]u8 = null,
    rendered_ansi_diagnostic: ?[:0]u8 = null,
    /// The parse generation both renderings above belong to. A rendering
    /// is served only while this equals the session's generation, so no
    /// window between a parse's start and its lease can serve a message
    /// from the parse before it.
    rendered_generation: usize = 0,
    /// Input retained for the most recent successful parse; node text
    /// offsets index it. Session-owned so the next parse — which reuses
    /// the session's input buffer, success or failure — cannot destroy
    /// the content spans still point at.
    retained_input: []u8 = &.{},
    /// What node offsets index outside hooks: the retained input of the
    /// most recent successful parse.
    last_input: []const u8 = &.{},

    const RenderingKind = enum { plain, ansi };

    fn renderingSlot(self: *Embedded, comptime kind: RenderingKind) *?[:0]u8 {
        return switch (kind) {
            .plain => &self.rendered_diagnostic,
            .ansi => &self.rendered_ansi_diagnostic,
        };
    }

    /// Single gate for the rendered-diagnostic cache, shared by the plain
    /// and ANSI exports. A cached rendering of the current generation is
    /// served under the shared door, so concurrent readers never collide.
    /// Only a miss takes the exclusive door, drops renderings that belong
    /// to an earlier parse, and fills the slot, re-checking under that
    /// door because another caller may have filled it in between.
    fn renderedDiagnostic(self: *Embedded, comptime kind: RenderingKind, out: *[*:0]const u8) i64 {
        {
            var guard = self.session.readLatest() catch |err| return statusForError(err);
            defer guard.deinit();
            if (self.session.runtime_context.lastDiagnostic() == null) return galley_error_no_diagnostic;
            if (self.rendered_generation == self.session.generation) {
                if (self.renderingSlot(kind).*) |cached| {
                    out.* = cached.ptr;
                    return galley_ok;
                }
            }
        }
        var guard = self.session.edit() catch |err| return statusForError(err);
        defer guard.deinit();
        if (self.rendered_generation != self.session.generation) {
            self.clearRenderedDiagnostic();
            self.rendered_generation = self.session.generation;
        }
        const door = sessionDoor(self);
        const diagnostic = door.runtime_context.lastDiagnostic() orelse return galley_error_no_diagnostic;
        const slot = self.renderingSlot(kind);
        if (slot.*) |cached| {
            out.* = cached.ptr;
            return galley_ok;
        }
        const rendered = (switch (kind) {
            .plain => diagnosticMessageCore(&door, diagnostic, std.heap.c_allocator),
            .ansi => diagnosticMessageAnsiCore(diagnostic, std.heap.c_allocator),
        }) catch return galley_error_out_of_memory;
        slot.* = rendered;
        out.* = rendered.ptr;
        return galley_ok;
    }

    fn clearRenderedDiagnostic(self: *Embedded) void {
        if (self.rendered_diagnostic) |rendered| {
            std.heap.c_allocator.free(rendered);
            self.rendered_diagnostic = null;
        }
        if (self.rendered_ansi_diagnostic) |rendered| {
            std.heap.c_allocator.free(rendered);
            self.rendered_ansi_diagnostic = null;
        }
    }

    /// Takes ownership of the session's just-parsed input buffer on success:
    /// the retained side keeps the parsed bytes while the session receives
    /// a scratch buffer for its next parse (the previous spare, or a fresh
    /// faulted one on the first success, so both buffers are born before
    /// timed code). No bytes move, so steady-state parses allocate only
    /// when input outgrows the spare.
    /// Returns false when the session does not own `source`; the caller
    /// then falls back to copying.
    fn adoptSessionInput(self: *Embedded, source: []const u8, bounded_len: usize) bool {
        const owned = self.session.owned_input orelse return false;
        if (@intFromPtr(source.ptr) != @intFromPtr(owned.ptr)) return false;
        if (bounded_len == 0) {
            self.last_input = self.retained_input[0..0];
            return true;
        }
        const spare = self.retained_input;
        self.retained_input = owned;
        if (spare.len == 0) {
            // First success: allocate the next scratch buffer now, faulted,
            // so both buffers are born in this parse exactly like the
            // pre-existing session buffer. Never store the static empty
            // slice: its capacity helper would later free it.
            const fresh = std.heap.c_allocator.alloc(u8, owned.len) catch null;
            if (fresh) |scratch| {
                @memset(scratch, 0);
                self.session.owned_input = scratch;
            } else {
                self.session.owned_input = null;
            }
        } else {
            self.session.owned_input = spare;
        }
        self.last_input = self.retained_input[0..bounded_len];
        return true;
    }

    /// Copies `input` into the session-owned retained buffer. Only used for
    /// sources the session does not own; session-owned inputs move through
    /// `adoptSessionInput` with no copy. Returns false when growth was
    /// needed and allocation failed; the caller then keeps aliasing the
    /// live source instead.
    fn retainCopiedInput(self: *Embedded, input: []const u8) bool {
        if (input.len == 0) return true;
        if (self.retained_input.len < input.len) {
            // Grow to at least double the current capacity so repeated
            // one-byte-larger inputs stay amortized.
            const target = @max(input.len, self.retained_input.len *| 2);
            self.retained_input = if (self.retained_input.len == 0)
                std.heap.c_allocator.alloc(u8, target) catch return false
            else
                std.heap.c_allocator.realloc(self.retained_input, target) catch return false;
        }
        @memcpy(self.retained_input[0..input.len], input);
        return true;
    }
};

// ---------------------------------------------------------------------------
// The two doors.
//
// Every node, tree, and diagnostic operation has exactly one core that both
// export families call. The parse-time door (`hookDoor`) is the live
// context of one parse, handed out by `galley_procedure_door`: no lock, no
// session — unshared by construction and valid until that parse ends, across
// every hook of it. Per-hook state (current node, rule, drop/replace
// channel) stays on the arguments, which die with their hook. The post-parse
// door (`sessionDoor`) resolves session state of the last successful parse
// under the matching guard. Calls that read or edit nodes enter either door
// through `gate`, which compares the caller's generation once.
// ---------------------------------------------------------------------------

const Door = struct {
    node_allocator: if (parser.is_ast_enabled) *root.data_structures.ASTAllocator else void,
    runtime_context: *root.data_structures.RuntimeContext,
    input: union(enum) {
        /// Parse-time: the live input of the in-flight parse.
        context: *root.data_structures.Context,
        /// Post-parse: the retained input of the last successful parse.
        retained: []const u8,
    },

    fn inputBytes(self: *const Door) []const u8 {
        return switch (self.input) {
            .context => |context| context.diagnosticInput(),
            .retained => |bytes| bytes,
        };
    }

    fn textSlice(self: *const Door, start: usize, length: usize) []const u8 {
        return switch (self.input) {
            .context => |context| context.getTextSlice(start, length),
            .retained => |bytes| bytes[start .. start + length],
        };
    }

    /// Bounds-checks a C-ABI address against this door's live node storage
    /// and narrows it to the runtime pointer width. The C ABI is `u64` on
    /// all platforms while `Node.Pointer` is `usize`, so on 32-bit targets
    /// (wasm32) a direct pass does not compile; every node resolution goes
    /// through here. Null means invalid-node, including
    /// `GALLEY_INVALID_NODE` and any address above the pointer range.
    fn nodeAt(self: *const Door, address: GalleyNodeAddress) ?*root.data_structures.Node {
        if (comptime !parser.is_ast_enabled) return null;
        if (address >= self.node_allocator.counter) return null;
        return self.node_allocator.at(@intCast(address));
    }

    fn livePointer(self: *const Door, address: GalleyNodeAddress) ?root.data_structures.Node.Pointer {
        _ = self.nodeAt(address) orelse return null;
        return @intCast(address);
    }

    /// The source span of `node` in this door's input, or null when the
    /// span falls outside it.
    fn nodeText(self: *const Door, node: *const root.data_structures.Node) ?[]const u8 {
        const input = self.inputBytes();
        if (node.text_start > input.len) return null;
        if (node.text_length > input.len - node.text_start) return null;
        return self.textSlice(node.text_start, node.text_length);
    }
};

/// Parse-time door: the live context of one in-flight parse. Its allocator
/// and runtime belong to that parse, so the door must not outlive it.
fn hookDoor(hook_door: ?*anyopaque) ?Door {
    const context: *root.data_structures.Context = @ptrCast(@alignCast(hook_door orelse return null));
    return .{
        .node_allocator = if (parser.is_ast_enabled) context.node_allocator else {},
        .runtime_context = context.runtime(),
        .input = .{ .context = context },
    };
}

/// Post-parse door over session state. The caller must already hold the
/// guard that makes this state stable (`read`, `readCurrent`,
/// `readLatest`, `edit`, `editResult`, or `editCurrent`).
fn sessionDoor(embedded: *Embedded) Door {
    return .{
        .node_allocator = if (parser.is_ast_enabled) &embedded.session.node_allocator else {},
        .runtime_context = &embedded.session.runtime_context,
        .input = .{ .retained = embedded.last_input },
    };
}

/// Which door a call enters through: the session (post-parse; guard first)
/// or one parse's hook door (live; unshared by construction).
const DoorKind = enum { session, hook };

/// What a call is opened on: the session handle or the parse's hook door.
fn DoorHandle(comptime kind: DoorKind) type {
    return switch (kind) {
        .session => ?*GalleySession,
        .hook => ?*anyopaque,
    };
}

/// Which guard a session-door call needs: a node read takes the shared
/// door, a tree edit the exclusive one. The hook door takes none.
const Tier = enum { read, edit };

fn guardType(comptime tier: Tier) type {
    return switch (tier) {
        .read => root.SessionReadGuard,
        .edit => root.SessionEditGuard,
    };
}

/// A call's way in: the door plus the guard that keeps it stable, released
/// by `deinit`. The hook door's guard is empty.
fn Entry(comptime kind: DoorKind, comptime tier: Tier) type {
    return struct {
        door: Door,
        guard: switch (kind) {
            .session => guardType(tier),
            .hook => void,
        },

        fn deinit(self: *@This()) void {
            if (comptime kind == .session) self.guard.deinit();
        }
    };
}

/// The gate's failure set: a session error, plus `StaleTree` for the two
/// ways the tree a call addresses can be gone, plus `NullArgument` for a
/// null session or hook door.
const GateError = root.SessionError || error{ StaleTree, NullArgument };

/// The single generation gate: the one place the core compares a caller's
/// generation against the tree a door serves, for both doors. The session
/// door's tree is the published one (`readCurrent` / `editCurrent` already
/// refuse a session a parse holds and a published result no longer live);
/// the hook door's is the parse that owns the door. A missing published
/// result and a mismatch are one failure — the tree the caller addressed is
/// gone — reported as `galley_error_stale_tree`, so an address from a dead
/// parse is refused here instead of aliasing whichever node holds that index
/// in the current storage. Generation 0 is never live.
///
/// This runs in every build: it is the lifetime contract memory-safe hosts
/// rely on, not a misuse check, and it costs one integer comparison on a
/// path the parser never takes.
fn gate(comptime kind: DoorKind, comptime tier: Tier, handle: DoorHandle(kind), generation: u64) GateError!Entry(kind, tier) {
    var entry: Entry(kind, tier) = undefined;
    const live: u64 = switch (kind) {
        .session => live: {
            const embedded: *Embedded = @ptrCast(@alignCast(handle orelse return error.NullArgument));
            entry.guard = switch (tier) {
                .read => embedded.session.readCurrent() catch |err| return gateStatusError(err),
                .edit => embedded.session.editCurrent() catch |err| return gateStatusError(err),
            };
            entry.door = sessionDoor(embedded);
            break :live entry.guard.generation();
        },
        .hook => live: {
            entry.door = hookDoor(handle) orelse return error.NullArgument;
            break :live entry.door.input.context.generation;
        },
    };
    if (live != generation) {
        entry.deinit();
        return error.StaleTree;
    }
    return entry;
}

/// Folds "no published result" and "the published result went stale" into
/// the gate's one refusal; every other session error passes through
/// (`SessionInUse` among them).
fn gateStatusError(err: root.SessionError) GateError {
    return switch (err) {
        error.StaleParseResult, error.NoParseResult => error.StaleTree,
        else => err,
    };
}

/// The value shape behind the node count, the five links and the variable
/// index, on either door: the gate, then a core that answers null for an
/// address outside the live storage (`galley_error_invalid_node`). The value
/// is non-negative, so it shares its return with the negative statuses; a
/// link that does not exist is `GALLEY_INVALID_NODE`, a real answer.
fn nodeValue(
    comptime kind: DoorKind,
    handle: DoorHandle(kind),
    generation: u64,
    address: GalleyNodeAddress,
    comptime core: anytype,
    extra: anytype,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_invalid_node;
    var entry = gate(kind, .read, handle, generation) catch |err| return statusForError(err);
    defer entry.deinit();
    const value = @call(.auto, core, .{ &entry.door, address } ++ extra) orelse return galley_error_invalid_node;
    return @intCast(value);
}

/// The read shape behind the byte reads (symbol name, text), the pair reads
/// (span, line and column) and the snapshot, on either door. In order: the
/// answer of a build without AST construction (`no_ast`), the out-parameters
/// the call requires (`required`: indexes into `arguments`, null is
/// `galley_error_null_argument`), the gate, then a core that takes the door
/// and `arguments` (the address and the out-parameters, or the snapshot's
/// columns) and returns a status or count. Argument errors come before the
/// gate, so a stale or contended call with a null output still reports the
/// null.
fn nodeRead(
    comptime kind: DoorKind,
    handle: DoorHandle(kind),
    generation: u64,
    comptime no_ast: i64,
    comptime required: []const usize,
    comptime core: anytype,
    arguments: anytype,
) i64 {
    if (comptime !parser.is_ast_enabled) return no_ast;
    inline for (required) |index| {
        if (arguments[index] == null) return galley_error_null_argument;
    }
    var entry = gate(kind, .read, handle, generation) catch |err| return statusForError(err);
    defer entry.deinit();
    return @call(.auto, core, .{&entry.door} ++ arguments);
}

/// The edit shape behind every `galley_tree_*` / `galley_hook_tree_*` call:
/// the build without AST construction (`galley_error_internal`), the required
/// out-parameters, the gate (the exclusive tier on the session door), then
/// the edit core over `arguments`.
fn treeEdit(
    comptime kind: DoorKind,
    handle: DoorHandle(kind),
    generation: u64,
    comptime required: []const usize,
    comptime core: anytype,
    arguments: anytype,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    inline for (required) |index| {
        if (arguments[index] == null) return galley_error_null_argument;
    }
    var entry = gate(kind, .edit, handle, generation) catch |err| return statusForError(err);
    defer entry.deinit();
    return @call(.auto, core, .{&entry.door} ++ arguments);
}

// --- node reads ----------------------------------------------------------

/// The number of direct children of a node, or null when `address` is not a
/// node of this door's live storage. An unresolvable address is a refusal, not
/// a leaf: only a resolved node can report 0 children.
fn nodeChildCountCore(door: *const Door, address: GalleyNodeAddress) ?u32 {
    if (comptime !parser.is_ast_enabled) return null;
    const node = door.nodeAt(address) orelse return null;
    return node.children_count;
}

const NodeLink = enum { first_child, last_child, next, prior, parent };

/// The single link reader behind the five tree-link queries: resolves
/// `address`, follows the selected link, and maps the internal invalid
/// pointer to `GALLEY_INVALID_NODE`. Null when `address` is not a node of
/// this door's live storage: a link that resolves to nothing is only an
/// answer when the address itself is live.
fn nodeLinkCore(door: *const Door, address: GalleyNodeAddress, comptime link: NodeLink) ?GalleyNodeAddress {
    if (comptime !parser.is_ast_enabled) return null;
    const node = door.nodeAt(address) orelse return null;
    const raw = switch (link) {
        .first_child => node.first_child,
        .last_child => node.last_child,
        .next => node.next,
        .prior => node.prior,
        .parent => node.parent,
    };
    if (raw == root.data_structures.Node.invalid_pointer) return galley_invalid_node;
    return @intCast(raw);
}

fn nodeSymbolNameCore(
    door: *const Door,
    address: GalleyNodeAddress,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_invalid_node;
    const node = door.nodeAt(address) orelse return galley_error_invalid_node;
    if (node.variable == root.data_structures.Node.invalid_variable) {
        out_data.?.* = @ptrCast("");
        out_len.?.* = 0;
        return galley_ok;
    }
    const name = parser.variables[node.variable];
    out_data.?.* = name.ptr;
    out_len.?.* = name.len;
    return galley_ok;
}

fn nodeTextCore(
    door: *const Door,
    address: GalleyNodeAddress,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_invalid_node;
    const node = door.nodeAt(address) orelse return galley_error_invalid_node;
    const slice = door.nodeText(node) orelse return galley_error_internal;
    out_data.?.* = slice.ptr;
    out_len.?.* = slice.len;
    return galley_ok;
}

fn nodeSpanCore(
    door: *const Door,
    address: GalleyNodeAddress,
    out_start: ?*u64,
    out_len: ?*u64,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_invalid_node;
    const node = door.nodeAt(address) orelse return galley_error_invalid_node;
    out_start.?.* = node.text_start;
    out_len.?.* = node.text_length;
    return galley_ok;
}

/// Scans the door's input up to the node's start offset, so cost is linear
/// in the offset.
fn nodeLineColumnCore(
    door: *const Door,
    address: GalleyNodeAddress,
    out_line: ?*u32,
    out_column: ?*u32,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_invalid_node;
    const node = door.nodeAt(address) orelse return galley_error_invalid_node;
    const input = door.inputBytes();
    if (node.text_start > input.len) return galley_error_internal;

    var line: u32 = 1;
    var column: u32 = 1;
    for (input[0..node.text_start]) |byte| {
        if (byte == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    out_line.?.* = line;
    out_column.?.* = column;
    return galley_ok;
}

/// The variable index of a node, or null when the address is not a node of
/// this door's live storage. A node with no variable (a terminal-only node)
/// is a real answer, `galley_no_variable`; only an unresolvable address is
/// null.
fn nodeVariableIndexCore(door: *const Door, address: GalleyNodeAddress) ?i64 {
    if (comptime !parser.is_ast_enabled) return null;
    const node = door.nodeAt(address) orelse return null;
    if (node.variable == root.data_structures.Node.invalid_variable) return galley_no_variable;
    return @intCast(node.variable);
}

fn lastInputCore(door: *const Door, out_data: ?*[*]const u8, out_len: ?*usize) i64 {
    if (out_data == null or out_len == null) return galley_error_null_argument;
    const input = door.inputBytes();
    out_data.?.* = input.ptr;
    out_len.?.* = input.len;
    return galley_ok;
}

// --- tree editing --------------------------------------------------------
// Chains passed to these cores must be detached orphans (no parent, no
// prior). Addresses are stable, so edits never invalidate other node
// addresses.

fn treeAppendChildrenCore(door: *const Door, parent: GalleyNodeAddress, first_node: GalleyNodeAddress) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    const parent_ptr = door.livePointer(parent) orelse return galley_error_invalid_node;
    const first_ptr = door.livePointer(first_node) orelse return galley_error_invalid_node;
    root.data_structures.Node.appendChildren(parent_ptr, door.node_allocator, first_ptr);
    return galley_ok;
}

fn treeInsertBeforeCore(door: *const Door, target: GalleyNodeAddress, first_node: GalleyNodeAddress) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    const target_ptr = door.livePointer(target) orelse return galley_error_invalid_node;
    const first_ptr = door.livePointer(first_node) orelse return galley_error_invalid_node;
    root.data_structures.Node.insertBefore(target_ptr, door.node_allocator, first_ptr);
    return galley_ok;
}

fn treeInsertAfterCore(door: *const Door, target: GalleyNodeAddress, first_node: GalleyNodeAddress) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    const target_ptr = door.livePointer(target) orelse return galley_error_invalid_node;
    const first_ptr = door.livePointer(first_node) orelse return galley_error_invalid_node;
    root.data_structures.Node.insertAfter(target_ptr, door.node_allocator, first_ptr);
    return galley_ok;
}

fn treeRemoveSiblingsCore(door: *const Door, node: GalleyNodeAddress, count: usize, out_head: ?*GalleyNodeAddress) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    const node_ptr = door.livePointer(node) orelse return galley_error_invalid_node;
    // Host-supplied counts must never read out of bounds: this range check runs in every build.
    if (root.data_structures.Node.removalFault(door.node_allocator, node_ptr, null, count) != null) return galley_error_invalid_node;
    const head = root.data_structures.Node.remove(node_ptr, door.node_allocator, count);
    if (head == root.data_structures.Node.invalid_pointer) {
        out_head.?.* = galley_invalid_node;
        return galley_ok;
    }
    out_head.?.* = head;
    return galley_ok;
}

fn treeCleanChildrenCore(door: *const Door, node: GalleyNodeAddress, out_head: ?*GalleyNodeAddress) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    const node_ptr = door.livePointer(node) orelse return galley_error_invalid_node;
    const head = root.data_structures.Node.cleanChildren(node_ptr, door.node_allocator);
    if (head == root.data_structures.Node.invalid_pointer) {
        out_head.?.* = galley_invalid_node;
        return galley_ok;
    }
    out_head.?.* = head;
    return galley_ok;
}

fn treeInsertChildrenAtCore(
    door: *const Door,
    parent: GalleyNodeAddress,
    index: usize,
    first_node: GalleyNodeAddress,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    const parent_ptr = door.livePointer(parent) orelse return galley_error_invalid_node;
    const first_ptr = door.livePointer(first_node) orelse return galley_error_invalid_node;
    // Host-supplied indexes must never read out of bounds: this range check runs in every build.
    if (root.data_structures.Node.insertionRangeFault(door.node_allocator, parent_ptr, index) != null) return galley_error_invalid_node;
    root.data_structures.Node.insertChildren(parent_ptr, door.node_allocator, index, first_ptr);
    return galley_ok;
}

fn treeRemoveChildrenAtCore(
    door: *const Door,
    parent: GalleyNodeAddress,
    index: usize,
    count: usize,
    out_head: ?*GalleyNodeAddress,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    const parent_ptr = door.livePointer(parent) orelse return galley_error_invalid_node;
    // Host-supplied indexes and counts must never read out of bounds: this range check runs in every build.
    if (root.data_structures.Node.removalFault(door.node_allocator, parent_ptr, index, count) != null) return galley_error_invalid_node;
    const head = root.data_structures.Node.removeChildren(parent_ptr, door.node_allocator, index, count);
    if (head == root.data_structures.Node.invalid_pointer) {
        out_head.?.* = galley_invalid_node;
        return galley_ok;
    }
    out_head.?.* = head;
    return galley_ok;
}

fn treeSnapshotCore(
    door: *const Door,
    out_parent: ?[*]GalleyNodeAddress,
    out_first_child: ?[*]GalleyNodeAddress,
    out_next: ?[*]GalleyNodeAddress,
    out_child_count: ?[*]u32,
    out_variable: ?[*]i64,
    out_span_start: ?[*]u64,
    out_span_len: ?[*]u64,
    out_is_semantic_error: ?[*]i32,
    capacity: u64,
) i64 {
    if (comptime !parser.is_ast_enabled) return 0;
    const total: u64 = @intCast(door.node_allocator.counter);
    const writable: usize = @intCast(@min(total, capacity));
    const invalid = root.data_structures.Node.invalid_pointer;
    const no_variable = root.data_structures.Node.invalid_variable;
    var index: usize = 0;
    while (index < writable) : (index += 1) {
        const node = door.node_allocator.at(index);
        if (out_parent) |parent| parent[index] = if (node.parent == invalid) galley_invalid_node else @intCast(node.parent);
        if (out_first_child) |first| first[index] = if (node.first_child == invalid) galley_invalid_node else @intCast(node.first_child);
        if (out_next) |next| next[index] = if (node.next == invalid) galley_invalid_node else @intCast(node.next);
        if (out_child_count) |counts| counts[index] = node.children_count;
        if (out_variable) |variables| variables[index] = if (node.variable == no_variable) galley_no_variable else @intCast(node.variable);
        if (out_span_start) |starts| starts[index] = @intCast(node.text_start);
        if (out_span_len) |lens| lens[index] = @intCast(node.text_length);
        if (out_is_semantic_error) |flag| flag[index] = if (node.is_semantic_error) 1 else 0;
    }
    return @intCast(total);
}

// --- current diagnostics -------------------------------------------------
// Each core fetches the current (or recorded, with `index`) diagnostic
// from a runtime context and hands it to the shared pure writer below.

fn currentSyntaxDiagnostic(door: *const Door) ?root.SyntaxDiagnostic {
    return switch (door.runtime_context.lastDiagnostic() orelse return null) {
        .syntax => |syntax| syntax,
        .semantic, .indentation => null,
    };
}

fn hasDiagnosticCore(door: *const Door) i32 {
    return if (door.runtime_context.lastDiagnostic() != null) 1 else 0;
}

fn diagnosticKindCore(door: *const Door) i64 {
    return diagnosticKindValue(door.runtime_context.lastDiagnostic());
}

fn diagnosticPositionCore(door: *const Door, out_line: ?*u32, out_column: ?*u32) i64 {
    if (out_line == null or out_column == null) return galley_error_null_argument;
    return writeDiagnosticPosition(door.runtime_context.lastDiagnostic(), out_line, out_column);
}

fn diagnosticUnexpectedTokenCore(door: *const Door, out_data: ?*[*]const u8, out_len: ?*usize) i64 {
    if (out_data == null or out_len == null) return galley_error_null_argument;
    return writeUnexpectedToken(door.runtime_context.lastDiagnostic(), out_data, out_len);
}

fn diagnosticExpectedCountCore(door: *const Door) i64 {
    return countExpectedTokens(door.runtime_context.lastDiagnostic());
}

fn diagnosticExpectedAtCore(door: *const Door, index: u64, out_data: ?*[*]const u8, out_len: ?*usize) i64 {
    if (out_data == null or out_len == null) return galley_error_null_argument;
    const diagnostic = door.runtime_context.lastDiagnostic() orelse return galley_error_no_diagnostic;
    return writeExpectedToken(diagnostic, index, out_data, out_len);
}

fn diagnosticContextCountCore(door: *const Door) i64 {
    return countContextNames(door.runtime_context.lastDiagnostic());
}

fn diagnosticContextAtCore(door: *const Door, index: u64, out_data: ?*[*]const u8, out_len: ?*usize) i64 {
    if (out_data == null or out_len == null) return galley_error_null_argument;
    const diagnostic = door.runtime_context.lastDiagnostic() orelse return galley_error_no_diagnostic;
    return writeContextName(diagnostic, index, out_data, out_len);
}

fn diagnosticSemanticCore(
    door: *const Door,
    out_variable: ?*[*]const u8,
    out_variable_len: ?*usize,
    out_message: ?*[*]const u8,
    out_message_len: ?*usize,
) i64 {
    return writeSemanticFields(door.runtime_context.lastDiagnostic(), out_variable, out_variable_len, out_message, out_message_len);
}

fn diagnosticIndentationCore(door: *const Door, out_spaces: ?*u32, out_indentation_width: ?*u32) i64 {
    if (out_spaces == null or out_indentation_width == null) return galley_error_null_argument;
    return writeIndentationFields(door.runtime_context.lastDiagnostic(), out_spaces, out_indentation_width);
}

fn diagnosticRecoveryKindCore(door: *const Door) i64 {
    return recoveryKindValue(currentSyntaxDiagnostic(door));
}

fn diagnosticRecoveryTerminalCore(door: *const Door, out_data: ?*[*]const u8, out_len: ?*usize) i64 {
    if (out_data == null or out_len == null) return galley_error_null_argument;
    return writeRecoveryTerminal(currentSyntaxDiagnostic(door), out_data, out_len);
}

fn diagnosticRecoveryResumeCore(door: *const Door, out: ?*i64) i64 {
    if (out == null) return galley_error_null_argument;
    return writeRecoveryResume(currentSyntaxDiagnostic(door), out);
}

fn diagnosticRecoveryLhsVariableCore(door: *const Door, out_data: ?*[*]const u8, out_len: ?*usize) i64 {
    if (out_data == null or out_len == null) return galley_error_null_argument;
    return writeRecoveryLhsVariable(currentSyntaxDiagnostic(door), out_data, out_len);
}

fn diagnosticRecoveryProductionCore(
    door: *const Door,
    out_variable: ?*[*]const u8,
    out_variable_len: ?*usize,
    out_rhs_index: ?*u32,
) i64 {
    if (out_variable == null or out_variable_len == null or out_rhs_index == null) return galley_error_null_argument;
    return writeRecoveryProduction(currentSyntaxDiagnostic(door), out_variable, out_variable_len, out_rhs_index);
}

fn diagnosticRecoveryOccurrenceCore(
    door: *const Door,
    out_parent_variable: ?*[*]const u8,
    out_parent_variable_len: ?*usize,
    out_rhs_index: ?*u32,
    out_symbol_index: ?*u32,
    out_variable: ?*[*]const u8,
    out_variable_len: ?*usize,
) i64 {
    if (out_parent_variable == null or out_parent_variable_len == null or
        out_rhs_index == null or out_symbol_index == null or
        out_variable == null or out_variable_len == null) return galley_error_null_argument;
    return writeRecoveryOccurrence(currentSyntaxDiagnostic(door), out_parent_variable, out_parent_variable_len, out_rhs_index, out_symbol_index, out_variable, out_variable_len);
}

fn syntaxErrorCountCore(door: *const Door) i64 {
    return @intCast(door.runtime_context.syntax_error_count);
}

fn semanticErrorCountCore(door: *const Door) i64 {
    return @intCast(door.runtime_context.semantic_error_count);
}

fn recordedDiagnosticCountCore(door: *const Door) i64 {
    return @intCast(door.runtime_context.recorded_diagnostics.items.len);
}

fn diagnosticMessageCore(
    door: *const Door,
    diagnostic: root.ParseDiagnostic,
    allocator: std.mem.Allocator,
) error{OutOfMemory}![:0]u8 {
    var transient: ?[]const u8 = null;
    defer if (transient) |rendered| allocator.free(rendered);
    // Prefer the message the grammar's error-message hooks rendered during
    // the parse; fall back to the built-in generic renderer.
    const source = door.runtime_context.last_rendered_message orelse blk: {
        const rendered = root.renderParseDiagnostic(allocator, diagnostic, .plain) catch return error.OutOfMemory;
        transient = rendered;
        break :blk rendered;
    };
    return allocator.dupeZ(u8, source);
}

fn diagnosticMessageAnsiCore(
    diagnostic: root.ParseDiagnostic,
    allocator: std.mem.Allocator,
) error{OutOfMemory}![:0]u8 {
    var transient: ?[]const u8 = null;
    defer if (transient) |rendered| allocator.free(rendered);
    const rendered = root.renderParseDiagnostic(allocator, diagnostic, .ansi) catch return error.OutOfMemory;
    transient = rendered;
    return allocator.dupeZ(u8, rendered);
}

// --- recorded diagnostics ------------------------------------------------
// Session-only: recording happens during a parse, so hook callers read the
// recorded battery through the post-parse door after it completes.

fn recordedDiagnostic(door: *const Door, diag_index: u64) ?root.ParseDiagnostic {
    const records = door.runtime_context.recorded_diagnostics.items;
    if (diag_index >= records.len) return null;
    return records[@intCast(diag_index)];
}

fn recordedSyntaxDiagnostic(door: *const Door, diag_index: u64) ?root.SyntaxDiagnostic {
    return switch (recordedDiagnostic(door, diag_index) orelse return null) {
        .syntax => |syntax| syntax,
        .semantic, .indentation => null,
    };
}

/// Creates a parsing session. Returns null when initialization fails, most
/// commonly on allocation failure. Destroy it with `galley_session_destroy`.
export fn galley_session_create() ?*GalleySession {
    return galley_session_create_ex(null);
}

/// Creates a parsing session with explicit options. Passing null options is
/// equivalent to `galley_session_create`. Zero/negative option fields select
/// the runtime defaults.
export fn galley_session_create_ex(options: ?*const GalleyCOptions) ?*GalleySession {
    var parse_options: root.ParseOptions = .{
        .syntax_error_reporter = &ignoreDiagnosticMessage,
    };
    if (options) |o| {
        if (o.max_errors > 0) parse_options.max_errors = @intCast(o.max_errors);
        if (o.recovery_window > 0) parse_options.recovery_window = @intCast(o.recovery_window);
        parse_options.stack_overflow_recovery = o.stack_overflow_recovery != 0;
        if (o.syntax_error_stack_depth > 0) parse_options.syntax_error_stack_depth = o.syntax_error_stack_depth;
        if (o.verbosity > 0) parse_options.verbosity = @intCast(o.verbosity);
        if (o.ast_preallocation_ratio >= 0.0 and std.math.isFinite(o.ast_preallocation_ratio)) {
            parse_options.ast_preallocation_ratio = o.ast_preallocation_ratio;
        }
        if (o.ast_preallocation_cap > 0) parse_options.ast_preallocation_cap = @intCast(o.ast_preallocation_cap);
    }

    const embedded = std.heap.c_allocator.create(Embedded) catch return null;
    embedded.* = .{ .threaded = undefined, .session = undefined };
    embedded.threaded = std.Io.Threaded.init(std.heap.c_allocator, .{});
    embedded.session = root.Session.init(embedded.threaded.io(), std.heap.c_allocator, parse_options) catch {
        embedded.threaded.deinit();
        std.heap.c_allocator.destroy(embedded);
        return null;
    };
    return @ptrCast(embedded);
}

/// Destroys a session created by `galley_session_create`. Null is ignored,
/// which makes guarded cleanup paths easy to write.
export fn galley_session_destroy(session_ptr: ?*GalleySession) void {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return));
    embedded.clearRenderedDiagnostic();
    if (embedded.retained_input.len != 0) std.heap.c_allocator.free(embedded.retained_input);
    embedded.session.deinit();
    embedded.threaded.deinit();
    std.heap.c_allocator.destroy(embedded);
}

// Host-memory helpers for the WebAssembly build (`bindings/js/wasm`): the
// wasm linear memory is only writable by the host through exported memory,
// so input buffers and out-parameter slots are allocated here. Present (but
// unused) on native targets; the FFI adapters use their own allocators there.
export fn galley_js_malloc(len: usize) ?[*]u8 {
    if (comptime !builtin.cpu.arch.isWasm()) return null;
    const slice = std.heap.c_allocator.alloc(u8, len) catch return null;
    return slice.ptr;
}

/// Releases an allocation from `galley_js_malloc`. The length must match.
export fn galley_js_free(ptr: [*]u8, len: usize) void {
    if (comptime !builtin.cpu.arch.isWasm()) return;
    std.heap.c_allocator.free(ptr[0..len]);
}

/// Registers one message override: when a syntax-error site's resolution
/// chain contains `name`, the site reports `message` verbatim instead of
/// consulting grammar hooks or the built-in renderer. Overrides set here
/// take priority over `ParseOptions.message_overrides` entries and persist
/// for the session's lifetime.
export fn galley_session_set_message_override(
    session_ptr: ?*GalleySession,
    name_ptr: ?[*]const u8,
    name_len: usize,
    message_ptr: ?[*]const u8,
    message_len: usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (name_ptr == null or message_ptr == null) return galley_error_null_argument;
    const allocator = embedded.session.allocator;
    const name = allocator.dupe(u8, name_ptr.?[0..name_len]) catch return galley_error_out_of_memory;
    const message = allocator.dupe(u8, message_ptr.?[0..message_len]) catch {
        allocator.free(name);
        return galley_error_out_of_memory;
    };
    const gop = embedded.session.message_overrides.getOrPut(allocator, name) catch {
        allocator.free(name);
        allocator.free(message);
        return galley_error_out_of_memory;
    };
    if (gop.found_existing) {
        allocator.free(name);
        allocator.free(gop.value_ptr.*);
    }
    gop.value_ptr.* = message;
    return galley_ok;
}

const host_hooks = root.data_structures.host_hooks;

/// Number of hooks the linked host shim forwards; zero for a library built
/// with Zig or extern hooks. Hook indexes run `0 ..< galley_hooks_count()`
/// and are fixed for the library's lifetime.
export fn galley_hooks_count() usize {
    return host_hooks.hook_count;
}

/// Name of hook `index` (the grammar's `reduction`, `reduction_<Variable>`
/// or `hook_<name>`): static storage valid for the process lifetime. A null
/// pointer and a zero length for an out-of-range index. The pointer and the
/// length are two calls so every host, wasm included, reads them as plain
/// scalars.
export fn galley_hooks_name_data(index: usize) ?[*]const u8 {
    if (index >= host_hooks.hook_count) return null;
    return host_hooks.hook_names[index].ptr;
}

export fn galley_hooks_name_length(index: usize) usize {
    if (index >= host_hooks.hook_count) return 0;
    return host_hooks.hook_names[index].len;
}

/// Replaces the session's host hook state in one step. `enabled` holds one
/// byte per hook, `galley_hooks_count()` bytes in all (null with count zero
/// enables none); a nonzero byte routes that hook to `dispatch`, which gets
/// `handle`, the hook's index and its arguments on the parsing thread.
/// Unenabled hooks return before any call. Takes the exclusive lease, so it
/// returns `galley_error_session_in_use` while a parse is in flight and the
/// set a parse runs with is fixed for that parse. A null `enabled` with a
/// nonzero count, or a count other than `galley_hooks_count()`, returns
/// `galley_error_null_argument`. WebAssembly hosts pass a null `dispatch`
/// and provide `env.galley_host_dispatch` instead.
export fn galley_session_set_hooks(
    session_ptr: ?*GalleySession,
    dispatch: ?host_hooks.Dispatch,
    handle: ?*anyopaque,
    enabled: ?[*]const u8,
    enabled_count: usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    var hooks: root.data_structures.HostHooks = .{ .dispatch = dispatch };
    if (enabled_count != 0) {
        const flags = enabled orelse return galley_error_null_argument;
        if (enabled_count != host_hooks.hook_count) return galley_error_null_argument;
        for (&hooks.enabled, flags[0..enabled_count]) |*slot, flag| slot.* = flag != 0;
    }
    embedded.session.setHostHooks(hooks, handle) catch |err| return statusForError(err);
    return galley_ok;
}

fn statusForError(err: anyerror) i64 {
    return switch (err) {
        error.SyntaxError => galley_error_syntax,
        error.SemanticError => galley_error_semantic,
        error.IndentationError => galley_error_indentation,
        error.StackOverflow => galley_error_stack_overflow,
        error.ASTCapacityExceeded => galley_error_ast_capacity_exceeded,
        error.UnterminatedRawString => galley_error_unterminated_raw_string,
        error.OutOfMemory => galley_error_out_of_memory,
        error.SessionInUse => galley_error_session_in_use,
        // A walk cursor or session-door call whose tree is gone (reparsed,
        // failed, or never published).
        error.StaleTree => galley_error_stale_tree,
        error.NullArgument => galley_error_null_argument,
        // A cursor that cannot be trusted (unknown state or option bits,
        // root/current outside the node storage) or a walk position that
        // left the walked subtree: either way there is no live node to step
        // to, same as addressing one.
        error.InvalidCursor, error.WalkPositionDetached => galley_error_invalid_node,
        // No result, or a result from a dead parse: either way there are no
        // live nodes in the session's current storage to address.
        error.StaleParseResult, error.NoParseResult => galley_error_invalid_node,
        else => galley_error_internal,
    };
}

/// Pairs the retained input with the result the session published: the
/// input swap — and the `owned_input` read behind `source` — run under the
/// same exclusive hold that stamped the parse's generation, so an older
/// result can never overwrite a newer one and no reader can observe the pair
/// mid-swap.
fn finishParse(embedded: *Embedded, lease: *const root.ParseLease, source: []const u8) i64 {
    const result = lease.result;
    const parsed: usize = @intCast(result.parsed_bytes);
    // Retain exactly the parsed bytes in a session-owned buffer: the
    // session reuses its input buffer for the next parse (and callers
    // free theirs), so spans and galley_last_input must not alias
    // either. Ownership of the session's buffer moves to the retained
    // side while the session receives the previous spare as its next
    // scratch buffer, so no bytes move in steady state. The owned buffer
    // carries sentinel and zero padding past the input; exposing exactly
    // parsed keeps node spans and galley_last_input in agreement with
    // the count parse reported.
    // Only success paths reach here, so a failed parse can never
    // destroy what the last successful parse retained.
    const bounded = source[0..@min(parsed, source.len)];
    if (embedded.adoptSessionInput(source, bounded.len)) {
        // Ownership transferred (or the parse was empty); last_input is set.
    } else if (embedded.retainCopiedInput(bounded))
        embedded.last_input = embedded.retained_input[0..bounded.len]
    else
        embedded.last_input = bounded; // allocation failure: alias the live source as before
    return @intCast(result.parsed_bytes);
}

fn ignoreDiagnosticMessage(_: []const u8) void {}

/// Parses one NUL-terminated input string. Returns the number of bytes
/// parsed on success, or a negative status code.
export fn galley_parse_sentinel(session_ptr: ?*GalleySession, input: ?[*:0]const u8) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    const text = std.mem.sliceTo(input orelse return galley_error_null_argument, 0);
    var lease = embedded.session.parseSentinelBytesLeased(text, null) catch |err| return statusForError(err);
    defer lease.deinit();
    return finishParse(embedded, &lease, embedded.session.owned_input orelse text);
}

/// Parses a byte buffer that may contain NUL bytes. Same return contract as
/// `galley_parse_sentinel`.
export fn galley_parse(session_ptr: ?*GalleySession, data: ?[*]const u8, len: usize) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    const bytes = if (data) |d|
        d[0..len]
    else if (len == 0)
        @as([]const u8, &.{})
    else
        return galley_error_null_argument;
    var lease = embedded.session.parseBytesLeased(bytes, null) catch |err| return statusForError(err);
    defer lease.deinit();
    return finishParse(embedded, &lease, embedded.session.owned_input orelse bytes);
}

fn nodeCountCore(door: *const Door) i64 {
    return @intCast(door.node_allocator.counter);
}

/// Returns the number of AST nodes allocated by the published parse (0 for a
/// parser built without AST construction), or a negative status.
/// `generation` must be the generation `galley_root_node` reported for that
/// tree; a caller addressing another parse's tree is refused with
/// `galley_error_stale_tree`.
export fn galley_node_count(
    session_ptr: ?*GalleySession,
    generation: u64,
) i64 {
    return nodeRead(.session, session_ptr, generation, 0, &.{}, nodeCountCore, .{});
}

/// Writes the root node of the published tree and the parse generation every
/// node of it carries — the only source of the published generation, and the
/// one probe for "is there a tree here": both values are written under one
/// guard, so a caller never pairs a root with another parse's generation.
/// Returns `galley_ok` with `GALLEY_INVALID_NODE` and 0 when nothing is
/// published (no parse has succeeded yet, a later parse has begun, or the
/// parser was built without AST construction), and
/// `galley_error_session_in_use` while a parse holds the session. Real
/// generations start at 1, so a 0 never matches a live tree.
export fn galley_root_node(
    session_ptr: ?*GalleySession,
    out_root: ?*GalleyNodeAddress,
    out_generation: ?*u64,
) i64 {
    const out_root_value = out_root orelse return galley_error_null_argument;
    const out_generation_value = out_generation orelse return galley_error_null_argument;
    out_root_value.* = galley_invalid_node;
    out_generation_value.* = 0;
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (comptime !parser.is_ast_enabled) return galley_ok;
    var guard = embedded.session.readCurrent() catch |err| switch (err) {
        error.StaleParseResult, error.NoParseResult => return galley_ok,
        else => return statusForError(err),
    };
    defer guard.deinit();
    out_generation_value.* = guard.generation();
    if (guard.result.ast_root) |ast_root| out_root_value.* = @intCast(ast_root);
    return galley_ok;
}

/// Returns the number of direct children of a node (0 for a leaf), or a
/// negative status. Refuses an address outside the live tree's storage with
/// `galley_error_invalid_node`, and `generation` from another parse with
/// `galley_error_stale_tree`.
export fn galley_node_child_count(
    session_ptr: ?*GalleySession,
    generation: u64,
    address: GalleyNodeAddress,
) i64 {
    return nodeValue(.session, session_ptr, generation, address, nodeChildCountCore, .{});
}

/// Hook-time twin of `galley_node_child_count`: same returns, same refusals,
/// over the parse that handed out `hook_door`.
export fn galley_hook_node_child_count(
    hook_door: ?*anyopaque,
    generation: u64,
    address: GalleyNodeAddress,
) i64 {
    return nodeValue(.hook, hook_door, generation, address, nodeChildCountCore, .{});
}

/// Returns the first child's address, or `GALLEY_INVALID_NODE` when the link
/// does not exist — a leaf really has no first child.
/// A link that does not exist is a non-negative answer; an address
/// outside the live tree's storage is `galley_error_invalid_node`, and a
/// `generation` from another parse is `galley_error_stale_tree` (negative
/// statuses).
export fn galley_node_first_child(
    session_ptr: ?*GalleySession,
    generation: u64,
    address: GalleyNodeAddress,
) i64 {
    return nodeValue(.session, session_ptr, generation, address, nodeLinkCore, .{NodeLink.first_child});
}

/// Hook-time twin of `galley_node_first_child`: same returns, same refusals, over the
/// parse that handed out `hook_door`.
export fn galley_hook_node_first_child(
    hook_door: ?*anyopaque,
    generation: u64,
    address: GalleyNodeAddress,
) i64 {
    return nodeValue(.hook, hook_door, generation, address, nodeLinkCore, .{NodeLink.first_child});
}

/// Returns the next sibling's address, or `GALLEY_INVALID_NODE` when there is none.
/// A link that does not exist is a non-negative answer; an address
/// outside the live tree's storage is `galley_error_invalid_node`, and a
/// `generation` from another parse is `galley_error_stale_tree` (negative
/// statuses).
export fn galley_node_next_sibling(
    session_ptr: ?*GalleySession,
    generation: u64,
    address: GalleyNodeAddress,
) i64 {
    return nodeValue(.session, session_ptr, generation, address, nodeLinkCore, .{NodeLink.next});
}

/// Hook-time twin of `galley_node_next_sibling`: same returns, same refusals, over the
/// parse that handed out `hook_door`.
export fn galley_hook_node_next_sibling(
    hook_door: ?*anyopaque,
    generation: u64,
    address: GalleyNodeAddress,
) i64 {
    return nodeValue(.hook, hook_door, generation, address, nodeLinkCore, .{NodeLink.next});
}

/// Returns the parent's address, or `GALLEY_INVALID_NODE` for the root.
/// A link that does not exist is a non-negative answer; an address
/// outside the live tree's storage is `galley_error_invalid_node`, and a
/// `generation` from another parse is `galley_error_stale_tree` (negative
/// statuses).
export fn galley_node_parent(
    session_ptr: ?*GalleySession,
    generation: u64,
    address: GalleyNodeAddress,
) i64 {
    return nodeValue(.session, session_ptr, generation, address, nodeLinkCore, .{NodeLink.parent});
}

/// Hook-time twin of `galley_node_parent`: same returns, same refusals, over the
/// parse that handed out `hook_door`.
export fn galley_hook_node_parent(
    hook_door: ?*anyopaque,
    generation: u64,
    address: GalleyNodeAddress,
) i64 {
    return nodeValue(.hook, hook_door, generation, address, nodeLinkCore, .{NodeLink.parent});
}

/// Writes the grammar symbol name of a node (for example `"ObjectMembers"`)
/// into `out_data`/`out_len`. The pointer references static storage valid for
/// the process lifetime. Terminal-only nodes report length 0. Refuses an
/// address outside the live tree's storage with `galley_error_invalid_node`,
/// and a `generation` from another parse with `galley_error_stale_tree`.
export fn galley_node_symbol_name(
    session_ptr: ?*GalleySession,
    generation: u64,
    address: GalleyNodeAddress,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    return nodeRead(.session, session_ptr, generation, galley_error_invalid_node, &.{ 1, 2 }, nodeSymbolNameCore, .{ address, out_data, out_len });
}

/// Hook-time twin of `galley_node_symbol_name`: same out-parameters and refusals, over the
/// parse that handed out `hook_door`.
export fn galley_hook_node_symbol_name(
    hook_door: ?*anyopaque,
    generation: u64,
    address: GalleyNodeAddress,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    return nodeRead(.hook, hook_door, generation, galley_error_invalid_node, &.{ 1, 2 }, nodeSymbolNameCore, .{ address, out_data, out_len });
}

/// Writes the source text matched by a node into `out_data`/`out_len`. The
/// pointer references the session's retained input and stays valid until the
/// next parse or session destruction. Refuses an address outside the live
/// tree's storage with `galley_error_invalid_node`, and a `generation` from
/// another parse with `galley_error_stale_tree`.
export fn galley_node_text(
    session_ptr: ?*GalleySession,
    generation: u64,
    address: GalleyNodeAddress,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    return nodeRead(.session, session_ptr, generation, galley_error_invalid_node, &.{ 1, 2 }, nodeTextCore, .{ address, out_data, out_len });
}

/// Hook-time twin of `galley_node_text`: same out-parameters and refusals,
/// over the parse that handed out `hook_door`. The pointer references the
/// in-flight parse's input buffer and is valid until the calling hook
/// returns.
export fn galley_hook_node_text(
    hook_door: ?*anyopaque,
    generation: u64,
    address: GalleyNodeAddress,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    return nodeRead(.hook, hook_door, generation, galley_error_invalid_node, &.{ 1, 2 }, nodeTextCore, .{ address, out_data, out_len });
}

/// Writes the retained input of the most recent successful parse into
/// `out_data`/`out_len`: the buffer that snapshot spans and node texts
/// index. Same lifetime as `galley_node_text`; empty before the first
/// parse. Returns `galley_error_session_in_use` while a parse is in flight.
/// Hooks use `galley_hook_last_input` for the live input of their parse.
export fn galley_last_input(
    session_ptr: ?*GalleySession,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_data == null or out_len == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return lastInputCore(&sessionDoor(embedded), out_data, out_len);
}

/// Hook-time door: `galley_last_input` over the live input of the in-flight
/// parse, reached through the parse's hook door. No lock; the pointer is
/// valid until the calling hook returns.
export fn galley_hook_last_input(
    hook_door: ?*anyopaque,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const door = hookDoor(hook_door) orelse return galley_error_null_argument;
    if (out_data == null or out_len == null) return galley_error_null_argument;
    return lastInputCore(&door, out_data, out_len);
}

/// The host-owned walk cursor: 40 bytes, no padding, the same layout every
/// binding hands back to `galley_walk_next` / `galley_hook_walk_next`. See
/// `galley_walk_next` for the field contract.
pub const GalleyWalkCursor = root.data_structures.tree_walker.Cursor;

/// The walk-step shape behind both doors: the finished-walk shortcut, then
/// the gate on the cursor's generation, then one step over the door's node
/// storage.
fn walkNext(comptime kind: DoorKind, handle: DoorHandle(kind), cursor_ptr: ?*GalleyWalkCursor) i64 {
    const cursor = cursor_ptr orelse return galley_error_null_argument;
    // A finished walker stays finished: done reports 0 before any session
    // or generation check, so hosts see the end of the walk rather than a
    // stale or closed-session error.
    if (cursor.state == tree_walker.state_done) return 0;
    if (handle == null) return galley_error_null_argument;
    if (comptime !parser.is_ast_enabled) return galley_error_invalid_node;
    var entry = gate(kind, .read, handle, cursor.generation) catch |err| return statusForError(err);
    defer entry.deinit();
    const yielded = tree_walker.walkNext(entry.door.node_allocator, cursor) catch |err| return statusForError(err);
    return if (yielded) 1 else 0;
}

/// Advances `cursor` to the next node of its subtree in pre-order, writing
/// the position back into the cursor (`current`, `depth`, `state`,
/// `is_semantic_error`, `structure_version`). Returns 1 when a node was
/// yielded, 0 when the walk is done (the cursor stays
/// `GALLEY_WALK_STATE_DONE` and further steps keep returning 0, before any
/// session or generation check), or a negative status:
///
/// - `galley_error_stale_tree`: the cursor's `generation` is not the
///   session's live tree (it was reparsed, or no parse has published that
///   generation). Recreate the walk against the current tree.
/// - `galley_error_session_in_use`: a parse is in flight.
/// - `galley_error_invalid_node`: the cursor bytes are not a walk position
///   (`state` above `GALLEY_WALK_STATE_DONE`, unknown `options` bits,
///   `root`/`current`/`depth` at or above `galley_node_count`), or a
///   structure edit left `current` outside the walk's root — removed, or
///   moved elsewhere.
/// - `galley_error_null_argument`: null session or cursor.
///
/// The cursor is host-owned and no native resource is allocated or freed:
/// zero it (state `GALLEY_WALK_STATE_NOT_STARTED`), set `root`
/// (`galley_root_node` or any node), `generation`
/// (`galley_root_node`) and `options`
/// (`GALLEY_WALK_SKIP_SEMANTIC_ERRORS` to prune semantic-error subtrees),
/// then step. Skipping a yielded node's children is host-side too: write
/// `state = GALLEY_WALK_STATE_YIELDED_SKIP_CHILDREN` and the next step
/// continues with its next sibling. Node storage follows the live links, so
/// edits between steps are visible; a step whose position is no longer
/// inside the walk's root (removed, or moved elsewhere) raises invalid
/// node.
export fn galley_walk_next(session_ptr: ?*GalleySession, cursor_ptr: ?*GalleyWalkCursor) i64 {
    return walkNext(.session, session_ptr, cursor_ptr);
}

/// Hook-time twin of `galley_walk_next`: steps `cursor` over the tree of the
/// parse that handed out `hook_door`, with the same statuses. The cursor's
/// `generation` is checked against that parse's (read it once with
/// `galley_hook_generation` when the walk starts); a cursor of another
/// generation is `galley_error_stale_tree`.
export fn galley_hook_walk_next(hook_door: ?*anyopaque, cursor_ptr: ?*GalleyWalkCursor) i64 {
    return walkNext(.hook, hook_door, cursor_ptr);
}

/// Returns nonzero when the previous parse produced a diagnostic. Refuses
/// with 0 while a parse is in flight.
export fn galley_has_diagnostic(session_ptr: ?*GalleySession) i32 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return 0));
    var guard = embedded.session.readLatest() catch return 0;
    defer guard.deinit();
    return hasDiagnosticCore(&sessionDoor(embedded));
}

/// Hook-time door: `galley_has_diagnostic` over the in-flight parse's runtime
/// context, reached through the parse's hook door. No lock; valid until the
/// parse that produced the door ends.
export fn galley_hook_has_diagnostic(hook_door: ?*anyopaque) i32 {
    const door = hookDoor(hook_door) orelse return 0;
    return hasDiagnosticCore(&door);
}

/// Writes the rendered diagnostic message (plain text, newline-terminated)
/// into `out`. The string is NUL-terminated and remains valid until the next
/// parse or session destruction. Fails with `galley_error_no_diagnostic`
/// when the previous parse succeeded. A cached message is served under the
/// shared door, so concurrent readers do not collide; only the first call
/// after a parse takes the exclusive door to fill the cache. Returns
/// `galley_error_session_in_use` while a parse is in flight or another
/// caller holds the door.
export fn galley_diagnostic_message(session_ptr: ?*GalleySession, out: ?*[*:0]const u8) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out == null) return galley_error_null_argument;
    return embedded.renderedDiagnostic(.plain, out.?);
}

/// Hook-time door: `galley_diagnostic_message` over the in-flight parse's
/// runtime context, reached through the parse's hook door. Renders fresh into
/// the parse arena and never touches the session cache; the string is valid
/// until the next parse.
export fn galley_hook_diagnostic_message(hook_door: ?*anyopaque, out: ?*[*:0]const u8) i64 {
    const door = hookDoor(hook_door) orelse return galley_error_null_argument;
    if (out == null) return galley_error_null_argument;
    const diagnostic = door.runtime_context.lastDiagnostic() orelse return galley_error_no_diagnostic;
    const z = diagnosticMessageCore(&door, diagnostic, door.runtime_context.arena_allocator) catch return galley_error_out_of_memory;
    out.?.* = z.ptr;
    return galley_ok;
}

/// Writes a rendered message (plain text, newline-terminated) for the
/// diagnostic recorded at `diag_index` into `out`. Unlike
/// `galley_diagnostic_message`, which prefers the text the grammar's
/// error-message hooks rendered during the parse, recorded messages always
/// use the built-in generic renderer. The string is NUL-terminated and
/// remains valid until the next parse or session destruction.
export fn galley_recorded_diagnostic_message(
    session_ptr: ?*GalleySession,
    diag_index: u64,
    out: ?*[*:0]const u8,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    const diagnostic = recordedDiagnostic(&sessionDoor(embedded), diag_index) orelse return galley_error_no_diagnostic;
    const arena = embedded.session.arena.allocator();
    const rendered = root.renderParseDiagnostic(arena, diagnostic, .plain) catch return galley_error_out_of_memory;
    const z = arena.dupeZ(u8, rendered) catch return galley_error_out_of_memory;
    out.?.* = z.ptr;
    return galley_ok;
}

/// Writes the 1-based line and column of a diagnostic. Fails with
/// `galley_error_no_diagnostic` when the diagnostic is null.
fn writeDiagnosticPosition(
    diagnostic: ?root.ParseDiagnostic,
    out_line: ?*u32,
    out_column: ?*u32,
) i64 {
    switch (diagnostic orelse return galley_error_no_diagnostic) {
        .syntax => |syntax| {
            out_line.?.* = syntax.line;
            out_column.?.* = syntax.column;
        },
        .semantic => |semantic| {
            out_line.?.* = semantic.line;
            out_column.?.* = semantic.column;
        },
        .indentation => |indentation| {
            out_line.?.* = indentation.line;
            out_column.?.* = indentation.column;
        },
    }
    return galley_ok;
}

/// Writes the 1-based line and column of a diagnostic. Fails with
/// `galley_error_no_diagnostic` when the previous parse succeeded, and
/// `galley_error_session_in_use` while a parse is in flight.
export fn galley_diagnostic_position(
    session_ptr: ?*GalleySession,
    out_line: ?*u32,
    out_column: ?*u32,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_line == null or out_column == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return diagnosticPositionCore(&sessionDoor(embedded), out_line, out_column);
}

/// Hook-time door: `galley_diagnostic_position` over the in-flight parse's
/// runtime context, reached through the parse's hook door. No lock; valid
/// until the parse that produced the door ends.
export fn galley_hook_diagnostic_position(
    hook_door: ?*anyopaque,
    out_line: ?*u32,
    out_column: ?*u32,
) i64 {
    const door = hookDoor(hook_door) orelse return galley_error_null_argument;
    if (out_line == null or out_column == null) return galley_error_null_argument;
    return diagnosticPositionCore(&door, out_line, out_column);
}

/// Writes the 1-based line and column of the diagnostic recorded at
/// `diag_index` during the most recent parse. Fails with
/// `galley_error_no_diagnostic` when the index is out of range.
export fn galley_recorded_diagnostic_position(
    session_ptr: ?*GalleySession,
    diag_index: u64,
    out_line: ?*u32,
    out_column: ?*u32,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_line == null or out_column == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return writeDiagnosticPosition(recordedDiagnostic(&sessionDoor(embedded), diag_index), out_line, out_column);
}

/// Writes the unexpected token bytes of a syntax diagnostic into
/// `out_data`/`out_len`. Fails with `galley_error_no_diagnostic` when the
/// diagnostic is null or not a syntax error.
fn writeUnexpectedToken(diagnostic: ?root.ParseDiagnostic, out_data: ?*[*]const u8, out_len: ?*usize) i64 {
    switch (diagnostic orelse return galley_error_no_diagnostic) {
        .syntax => |syntax| {
            out_data.?.* = syntax.unexpected_token.ptr;
            out_len.?.* = syntax.unexpected_token.len;
            return galley_ok;
        },
        .semantic, .indentation => return galley_error_no_diagnostic,
    }
}

/// Writes the unexpected token bytes of a syntax diagnostic into
/// `out_data`/`out_len`. The pointer references session-retained state valid
/// until the next parse. Fails with `galley_error_no_diagnostic` when there
/// is no diagnostic or the diagnostic is not a syntax error.
export fn galley_diagnostic_unexpected_token(
    session_ptr: ?*GalleySession,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_data == null or out_len == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return diagnosticUnexpectedTokenCore(&sessionDoor(embedded), out_data, out_len);
}

/// Hook-time door: `galley_diagnostic_unexpected_token` over the in-flight
/// parse's runtime context, reached through the parse's hook door. No lock;
/// valid until the parse that produced the door ends.
export fn galley_hook_diagnostic_unexpected_token(
    hook_door: ?*anyopaque,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const door = hookDoor(hook_door) orelse return galley_error_null_argument;
    if (out_data == null or out_len == null) return galley_error_null_argument;
    return diagnosticUnexpectedTokenCore(&door, out_data, out_len);
}

/// Writes the unexpected token bytes of the diagnostic recorded at
/// `diag_index` into `out_data`/`out_len`. Fails with
/// `galley_error_no_diagnostic` when the index is out of range or the record
/// is not a syntax error.
export fn galley_recorded_unexpected_token(
    session_ptr: ?*GalleySession,
    diag_index: u64,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_data == null or out_len == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return writeUnexpectedToken(recordedDiagnostic(&sessionDoor(embedded), diag_index), out_data, out_len);
}

/// Renders a status code as a static, NUL-terminated description, or null
/// when the code is unknown. The returned pointer remains valid for the
/// lifetime of the process.
export fn galley_status_string(status: i64) ?[*:0]const u8 {
    return switch (status) {
        galley_ok => "ok",
        galley_error_null_argument => "null argument",
        galley_error_syntax => "syntax error",
        galley_error_semantic => "semantic error",
        galley_error_indentation => "indentation error",
        galley_error_stack_overflow => "parser stack overflow",
        galley_error_ast_capacity_exceeded => "AST capacity exceeded",
        galley_error_unterminated_raw_string => "unterminated raw string",
        galley_error_out_of_memory => "out of memory",
        galley_error_internal => "internal error",
        galley_error_no_diagnostic => "no diagnostic available",
        galley_error_invalid_node => "invalid node address",
        galley_error_io => "I/O error",
        galley_error_session_in_use => "session in use",
        galley_error_stale_tree => "stale tree",
        else => null,
    };
}

/// Returns the number of expected tokens of a syntax diagnostic, or a
/// negative status when the diagnostic is null or not a syntax error.
fn countExpectedTokens(diagnostic: ?root.ParseDiagnostic) i64 {
    switch (diagnostic orelse return galley_error_no_diagnostic) {
        .syntax => |syntax| return @intCast(syntax.expected_tokens.len),
        .semantic, .indentation => return galley_error_no_diagnostic,
    }
}

/// Returns the number of expected tokens of the current syntax diagnostic,
/// or a negative status when there is no diagnostic or it is not a syntax
/// error.
export fn galley_diagnostic_expected_count(session_ptr: ?*GalleySession) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return diagnosticExpectedCountCore(&sessionDoor(embedded));
}

/// Hook-time door: `galley_diagnostic_expected_count` over the in-flight
/// parse's runtime context, reached through the parse's hook door. No lock;
/// valid until the parse that produced the door ends.
export fn galley_hook_diagnostic_expected_count(hook_door: ?*anyopaque) i64 {
    const door = hookDoor(hook_door) orelse return galley_error_null_argument;
    return diagnosticExpectedCountCore(&door);
}

/// Returns the number of expected tokens of the diagnostic recorded at
/// `diag_index`, or a negative status when the index is out of range or the
/// record is not a syntax error.
export fn galley_recorded_expected_count(session_ptr: ?*GalleySession, diag_index: u64) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return countExpectedTokens(recordedDiagnostic(&sessionDoor(embedded), diag_index));
}

/// Writes the expected token at `index` (see
/// `galley_diagnostic_expected_count`) into `out_data`/`out_len`. The pointer
/// references session-retained state valid until the next parse.
export fn galley_diagnostic_expected_at(
    session_ptr: ?*GalleySession,
    index: u64,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_data == null or out_len == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return diagnosticExpectedAtCore(&sessionDoor(embedded), index, out_data, out_len);
}

/// Hook-time door: `galley_diagnostic_expected_at` over the in-flight parse's
/// runtime context, reached through the parse's hook door. No lock; valid
/// until the parse that produced the door ends.
export fn galley_hook_diagnostic_expected_at(
    hook_door: ?*anyopaque,
    index: u64,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const door = hookDoor(hook_door) orelse return galley_error_null_argument;
    if (out_data == null or out_len == null) return galley_error_null_argument;
    return diagnosticExpectedAtCore(&door, index, out_data, out_len);
}

/// Writes the expected token at `token_index` of the diagnostic recorded at
/// `diag_index` into `out_data`/`out_len`.
export fn galley_recorded_expected_token(
    session_ptr: ?*GalleySession,
    diag_index: u64,
    token_index: u64,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_data == null or out_len == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    const diagnostic = recordedDiagnostic(&sessionDoor(embedded), diag_index) orelse return galley_error_no_diagnostic;
    return writeExpectedToken(diagnostic, token_index, out_data, out_len);
}

fn writeExpectedToken(
    diagnostic: root.ParseDiagnostic,
    index: u64,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    switch (diagnostic) {
        .syntax => |syntax| {
            if (index >= syntax.expected_tokens.len) return galley_error_invalid_node;
            const token = syntax.expected_tokens[@intCast(index)];
            out_data.?.* = token.ptr;
            out_len.?.* = token.len;
            return galley_ok;
        },
        .semantic, .indentation => return galley_error_no_diagnostic,
    }
}

/// Returns the number of variables in the innermost-first "while parsing"
/// context chain of a syntax diagnostic, or a negative status when the
/// diagnostic is null or not a syntax error.
fn countContextNames(diagnostic: ?root.ParseDiagnostic) i64 {
    switch (diagnostic orelse return galley_error_no_diagnostic) {
        .syntax => |syntax| switch (syntax.context) {
            .while_parsing => |names| return @intCast(names.len),
            else => return 0,
        },
        .semantic => return 1,
        .indentation => return galley_error_no_diagnostic,
    }
}

/// Returns the number of variables in the innermost-first "while parsing"
/// context chain of the current syntax diagnostic, or a negative status when
/// there is no diagnostic or it is not a syntax error.
export fn galley_diagnostic_context_count(session_ptr: ?*GalleySession) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return diagnosticContextCountCore(&sessionDoor(embedded));
}

/// Hook-time door: `galley_diagnostic_context_count` over the in-flight
/// parse's runtime context, reached through the parse's hook door. No lock;
/// valid until the parse that produced the door ends.
export fn galley_hook_diagnostic_context_count(hook_door: ?*anyopaque) i64 {
    const door = hookDoor(hook_door) orelse return galley_error_null_argument;
    return diagnosticContextCountCore(&door);
}

/// Returns the number of variables in the context chain of the diagnostic
/// recorded at `diag_index`, or a negative status when the index is out of
/// range or the record is not a syntax error.
export fn galley_recorded_context_count(session_ptr: ?*GalleySession, diag_index: u64) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return countContextNames(recordedDiagnostic(&sessionDoor(embedded), diag_index));
}

/// Writes the variable name at `index` of the context chain (0 is
/// innermost) into `out_data`/`out_len`. The pointer references static
/// grammar storage valid for the process lifetime.
export fn galley_diagnostic_context_at(
    session_ptr: ?*GalleySession,
    index: u64,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_data == null or out_len == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return diagnosticContextAtCore(&sessionDoor(embedded), index, out_data, out_len);
}

/// Hook-time door: `galley_diagnostic_context_at` over the in-flight parse's
/// runtime context, reached through the parse's hook door. No lock; valid
/// until the parse that produced the door ends.
export fn galley_hook_diagnostic_context_at(
    hook_door: ?*anyopaque,
    index: u64,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const door = hookDoor(hook_door) orelse return galley_error_null_argument;
    if (out_data == null or out_len == null) return galley_error_null_argument;
    return diagnosticContextAtCore(&door, index, out_data, out_len);
}

/// Writes the variable name at `context_index` of the context chain of the
/// diagnostic recorded at `diag_index` into `out_data`/`out_len`.
export fn galley_recorded_context_name(
    session_ptr: ?*GalleySession,
    diag_index: u64,
    context_index: u64,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_data == null or out_len == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    const diagnostic = recordedDiagnostic(&sessionDoor(embedded), diag_index) orelse return galley_error_no_diagnostic;
    return writeContextName(diagnostic, context_index, out_data, out_len);
}

fn writeContextName(
    diagnostic: root.ParseDiagnostic,
    index: u64,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    switch (diagnostic) {
        .syntax => |syntax| switch (syntax.context) {
            .while_parsing => |names| {
                if (index >= names.len) return galley_error_invalid_node;
                out_data.?.* = names[@intCast(index)].ptr;
                out_len.?.* = names[@intCast(index)].len;
                return galley_ok;
            },
            else => return galley_error_no_diagnostic,
        },
        .semantic => |semantic| {
            if (index != 0) return galley_error_invalid_node;
            out_data.?.* = semantic.variable.ptr;
            out_len.?.* = semantic.variable.len;
            return galley_ok;
        },
        .indentation => return galley_error_no_diagnostic,
    }
}

/// Writes the 1-based line and column of a node's first byte in the input of
/// the published parse. Scans the retained input, so cost is linear in the
/// offset. Refuses an address outside the live tree's storage with
/// `galley_error_invalid_node`, and a `generation` from another parse with
/// `galley_error_stale_tree`.
export fn galley_node_line_column(
    session_ptr: ?*GalleySession,
    generation: u64,
    address: GalleyNodeAddress,
    out_line: ?*u32,
    out_column: ?*u32,
) i64 {
    return nodeRead(.session, session_ptr, generation, galley_error_invalid_node, &.{ 1, 2 }, nodeLineColumnCore, .{ address, out_line, out_column });
}

/// Hook-time twin of `galley_node_line_column`: same out-parameters and refusals, over the
/// parse that handed out `hook_door`.
export fn galley_hook_node_line_column(
    hook_door: ?*anyopaque,
    generation: u64,
    address: GalleyNodeAddress,
    out_line: ?*u32,
    out_column: ?*u32,
) i64 {
    return nodeRead(.hook, hook_door, generation, galley_error_invalid_node, &.{ 1, 2 }, nodeLineColumnCore, .{ address, out_line, out_column });
}

/// Parses the file at `path`. Returns the number of bytes parsed on success
/// or a negative status code; file access failures report
/// `galley_error_io`.
export fn galley_parse_file(session_ptr: ?*GalleySession, path: ?[*:0]const u8) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    const path_slice = std.mem.sliceTo(path orelse return galley_error_null_argument, 0);

    var file = std.Io.Dir.cwd().openFile(embedded.threaded.io(), path_slice, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return galley_error_io,
        error.AccessDenied => return galley_error_io,
        else => return galley_error_io,
    };
    defer file.close(embedded.threaded.io());

    var lease = embedded.session.parseFileLeased(file, path_slice) catch |err| return statusForError(err);
    defer lease.deinit();
    return finishParse(embedded, &lease, embedded.session.owned_input orelse &.{});
}

/// Writes the end position (1-based line and column) of the most recent
/// successful parse, when the parser was built with position tracking.
/// Otherwise writes zeros.
export fn galley_last_position(
    session_ptr: ?*GalleySession,
    out_line: ?*u32,
    out_column: ?*u32,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_line == null or out_column == null) return galley_error_null_argument;
    if (comptime !parser.is_position_tracking_enabled) {
        out_line.?.* = 0;
        out_column.?.* = 0;
        return galley_ok;
    }
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    const result = embedded.session.published_result orelse return galley_error_no_diagnostic;
    out_line.?.* = result.line;
    out_column.?.* = result.column;
    return galley_ok;
}

/// Writes the rendered diagnostic message with ANSI color escapes into
/// `out`. Lifetime and locking match `galley_diagnostic_message`.
export fn galley_diagnostic_message_ansi(session_ptr: ?*GalleySession, out: ?*[*:0]const u8) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out == null) return galley_error_null_argument;
    return embedded.renderedDiagnostic(.ansi, out.?);
}

/// Hook-time door: `galley_diagnostic_message_ansi` over the in-flight
/// parse's runtime context, reached through the parse's hook door. Renders
/// fresh into the parse arena and never touches the session cache; the string
/// is valid until the next parse.
export fn galley_hook_diagnostic_message_ansi(hook_door: ?*anyopaque, out: ?*[*:0]const u8) i64 {
    const door = hookDoor(hook_door) orelse return galley_error_null_argument;
    if (out == null) return galley_error_null_argument;
    const diagnostic = door.runtime_context.lastDiagnostic() orelse return galley_error_no_diagnostic;
    const z = diagnosticMessageAnsiCore(diagnostic, door.runtime_context.arena_allocator) catch return galley_error_out_of_memory;
    out.?.* = z.ptr;
    return galley_ok;
}

/// Writes the byte offset and length of a node's matched source span into
/// `out_start`/`out_len`. Offsets index the input of the published parse.
/// Refuses an address outside the live tree's storage with
/// `galley_error_invalid_node`, and a `generation` from another parse with
/// `galley_error_stale_tree`.
export fn galley_node_span(
    session_ptr: ?*GalleySession,
    generation: u64,
    address: GalleyNodeAddress,
    out_start: ?*u64,
    out_len: ?*u64,
) i64 {
    return nodeRead(.session, session_ptr, generation, galley_error_invalid_node, &.{ 1, 2 }, nodeSpanCore, .{ address, out_start, out_len });
}

/// Hook-time twin of `galley_node_span`: same out-parameters and refusals, over the
/// parse that handed out `hook_door`.
export fn galley_hook_node_span(
    hook_door: ?*anyopaque,
    generation: u64,
    address: GalleyNodeAddress,
    out_start: ?*u64,
    out_len: ?*u64,
) i64 {
    return nodeRead(.hook, hook_door, generation, galley_error_invalid_node, &.{ 1, 2 }, nodeSpanCore, .{ address, out_start, out_len });
}

/// Returns the last child's address, or `GALLEY_INVALID_NODE` when there is none.
/// A link that does not exist is a non-negative answer; an address
/// outside the live tree's storage is `galley_error_invalid_node`, and a
/// `generation` from another parse is `galley_error_stale_tree` (negative
/// statuses).
export fn galley_node_last_child(
    session_ptr: ?*GalleySession,
    generation: u64,
    address: GalleyNodeAddress,
) i64 {
    return nodeValue(.session, session_ptr, generation, address, nodeLinkCore, .{NodeLink.last_child});
}

/// Hook-time twin of `galley_node_last_child`: same returns, same refusals, over the
/// parse that handed out `hook_door`.
export fn galley_hook_node_last_child(
    hook_door: ?*anyopaque,
    generation: u64,
    address: GalleyNodeAddress,
) i64 {
    return nodeValue(.hook, hook_door, generation, address, nodeLinkCore, .{NodeLink.last_child});
}

/// Returns the previous sibling's address, or `GALLEY_INVALID_NODE` when there is none.
/// A link that does not exist is a non-negative answer; an address
/// outside the live tree's storage is `galley_error_invalid_node`, and a
/// `generation` from another parse is `galley_error_stale_tree` (negative
/// statuses).
export fn galley_node_prior_sibling(
    session_ptr: ?*GalleySession,
    generation: u64,
    address: GalleyNodeAddress,
) i64 {
    return nodeValue(.session, session_ptr, generation, address, nodeLinkCore, .{NodeLink.prior});
}

/// Hook-time twin of `galley_node_prior_sibling`: same returns, same refusals, over the
/// parse that handed out `hook_door`.
export fn galley_hook_node_prior_sibling(
    hook_door: ?*anyopaque,
    generation: u64,
    address: GalleyNodeAddress,
) i64 {
    return nodeValue(.hook, hook_door, generation, address, nodeLinkCore, .{NodeLink.prior});
}

// ---------------------------------------------------------------------------
// Tree editing. Chains passed to these functions must be detached orphans
// (no parent, no prior). Addresses are stable, so edits never invalidate
// other node addresses. Every edit crosses the generation gate on its
// exclusive tier: `galley_error_session_in_use` while a parse is in flight
// (session door only), `galley_error_stale_tree` for a generation that is
// not the door's live tree's — the published tree's on the session door, the
// running parse's on the `galley_hook_tree_*` twin. Both nodes of an edit
// that takes two must belong to that tree: an address carries no generation,
// so the host guarantees it.
// ---------------------------------------------------------------------------

/// Appends `first_node` (and any chain attached via its next links) as the
/// last children of `parent`. Both addresses must belong to the tree
/// `generation` names (an address carries no generation, so the host checks).
export fn galley_tree_append_children(
    session_ptr: ?*GalleySession,
    generation: u64,
    parent: GalleyNodeAddress,
    first_node: GalleyNodeAddress,
) i64 {
    return treeEdit(.session, session_ptr, generation, &.{}, treeAppendChildrenCore, .{ parent, first_node });
}

/// Hook-time twin of `galley_tree_append_children`: same parameters and refusals, over the
/// parse that handed out `hook_door`.
export fn galley_hook_tree_append_children(
    hook_door: ?*anyopaque,
    generation: u64,
    parent: GalleyNodeAddress,
    first_node: GalleyNodeAddress,
) i64 {
    return treeEdit(.hook, hook_door, generation, &.{}, treeAppendChildrenCore, .{ parent, first_node });
}

/// Inserts `first_node` (and its chain) immediately before `target` among
/// its siblings. Both addresses must belong to the tree `generation` names.
export fn galley_tree_insert_before(
    session_ptr: ?*GalleySession,
    generation: u64,
    target: GalleyNodeAddress,
    first_node: GalleyNodeAddress,
) i64 {
    return treeEdit(.session, session_ptr, generation, &.{}, treeInsertBeforeCore, .{ target, first_node });
}

/// Hook-time twin of `galley_tree_insert_before`: same parameters and refusals, over the
/// parse that handed out `hook_door`.
export fn galley_hook_tree_insert_before(
    hook_door: ?*anyopaque,
    generation: u64,
    target: GalleyNodeAddress,
    first_node: GalleyNodeAddress,
) i64 {
    return treeEdit(.hook, hook_door, generation, &.{}, treeInsertBeforeCore, .{ target, first_node });
}

/// Inserts `first_node` (and its chain) immediately after `target` among its
/// siblings. Both addresses must belong to the tree `generation` names.
export fn galley_tree_insert_after(
    session_ptr: ?*GalleySession,
    generation: u64,
    target: GalleyNodeAddress,
    first_node: GalleyNodeAddress,
) i64 {
    return treeEdit(.session, session_ptr, generation, &.{}, treeInsertAfterCore, .{ target, first_node });
}

/// Hook-time twin of `galley_tree_insert_after`: same parameters and refusals, over the
/// parse that handed out `hook_door`.
export fn galley_hook_tree_insert_after(
    hook_door: ?*anyopaque,
    generation: u64,
    target: GalleyNodeAddress,
    first_node: GalleyNodeAddress,
) i64 {
    return treeEdit(.hook, hook_door, generation, &.{}, treeInsertAfterCore, .{ target, first_node });
}

/// Removes `count` consecutive siblings starting at `node`, detaching them
/// from parent and sibling chains. Writes the address of the first removed
/// node to `out_head`; the removed nodes remain allocated and readable but
/// are orphaned. A `count` of 0 is a no-op that returns `galley_ok` with an
/// invalid head; a `count` larger than the siblings remaining from `node`
/// returns `galley_error_invalid_node` in every build. Other misuse is
/// undefined behavior in release builds; Debug builds check it and abort
/// the process on failure.
export fn galley_tree_remove_siblings(
    session_ptr: ?*GalleySession,
    generation: u64,
    node: GalleyNodeAddress,
    count: usize,
    out_head: ?*GalleyNodeAddress,
) i64 {
    return treeEdit(.session, session_ptr, generation, &.{2}, treeRemoveSiblingsCore, .{ node, count, out_head });
}

/// Hook-time twin of `galley_tree_remove_siblings`: same parameters and refusals, over the
/// parse that handed out `hook_door`.
export fn galley_hook_tree_remove_siblings(
    hook_door: ?*anyopaque,
    generation: u64,
    node: GalleyNodeAddress,
    count: usize,
    out_head: ?*GalleyNodeAddress,
) i64 {
    return treeEdit(.hook, hook_door, generation, &.{2}, treeRemoveSiblingsCore, .{ node, count, out_head });
}

/// Detaches `node` itself from its parent and siblings.
export fn galley_tree_remove_self(
    session_ptr: ?*GalleySession,
    generation: u64,
    node: GalleyNodeAddress,
    out_head: ?*GalleyNodeAddress,
) i64 {
    return galley_tree_remove_siblings(session_ptr, generation, node, 1, out_head);
}

/// Hook-time twin of `galley_tree_remove_self`: same parameters and refusals,
/// over the parse that handed out `hook_door`.
export fn galley_hook_tree_remove_self(
    hook_door: ?*anyopaque,
    generation: u64,
    node: GalleyNodeAddress,
    out_head: ?*GalleyNodeAddress,
) i64 {
    return galley_hook_tree_remove_siblings(hook_door, generation, node, 1, out_head);
}

/// Detaches all children of `node`, writing the detached chain head to
/// `out_head`. Returns `galley_error_no_diagnostic` when the node has no
/// children.
export fn galley_tree_clean_children(
    session_ptr: ?*GalleySession,
    generation: u64,
    node: GalleyNodeAddress,
    out_head: ?*GalleyNodeAddress,
) i64 {
    return treeEdit(.session, session_ptr, generation, &.{1}, treeCleanChildrenCore, .{ node, out_head });
}

/// Hook-time twin of `galley_tree_clean_children`: same parameters and refusals, over the
/// parse that handed out `hook_door`.
export fn galley_hook_tree_clean_children(
    hook_door: ?*anyopaque,
    generation: u64,
    node: GalleyNodeAddress,
    out_head: ?*GalleyNodeAddress,
) i64 {
    return treeEdit(.hook, hook_door, generation, &.{1}, treeCleanChildrenCore, .{ node, out_head });
}

// ---------------------------------------------------------------------------
// Diagnostic classification and multi-error state.
// ---------------------------------------------------------------------------

/// Returns the kind of a diagnostic, or `galley_diagnostic_kind_none` when
/// the diagnostic is null.
fn diagnosticKindValue(diagnostic: ?root.ParseDiagnostic) i64 {
    switch (diagnostic orelse return galley_diagnostic_kind_none) {
        .syntax => return galley_diagnostic_kind_syntax,
        .semantic => return galley_diagnostic_kind_semantic,
        .indentation => return galley_diagnostic_kind_indentation,
    }
}

/// Returns the kind of the current diagnostic: `galley_diagnostic_kind_none`,
/// `galley_diagnostic_kind_syntax`, or `galley_diagnostic_kind_indentation`.
/// Returns `galley_error_session_in_use` while a parse is in flight.
export fn galley_diagnostic_kind(session_ptr: ?*GalleySession) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_diagnostic_kind_none));
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return diagnosticKindCore(&sessionDoor(embedded));
}

/// Hook-time door: `galley_diagnostic_kind` over the in-flight parse's
/// runtime context, reached through the parse's hook door. No lock; valid
/// until the parse that produced the door ends.
export fn galley_hook_diagnostic_kind(hook_door: ?*anyopaque) i64 {
    const door = hookDoor(hook_door) orelse return galley_diagnostic_kind_none;
    return diagnosticKindCore(&door);
}

/// Returns the kind of the diagnostic recorded at `diag_index`, or
/// `galley_diagnostic_kind_none` when the index is out of range.
export fn galley_recorded_diagnostic_kind(session_ptr: ?*GalleySession, diag_index: u64) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_diagnostic_kind_none));
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return diagnosticKindValue(recordedDiagnostic(&sessionDoor(embedded), diag_index));
}

/// Returns how many syntax errors the most recent recovery-enabled parse
/// recorded. Fail-fast parses report at most one. Returns
/// `galley_error_session_in_use` while a parse is in flight.
export fn galley_syntax_error_count(session_ptr: ?*GalleySession) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return 0));
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return syntaxErrorCountCore(&sessionDoor(embedded));
}

/// Hook-time door: `galley_syntax_error_count` over the in-flight parse's
/// runtime context, reached through the parse's hook door. No lock; valid
/// until the parse that produced the door ends.
export fn galley_hook_syntax_error_count(hook_door: ?*anyopaque) i64 {
    const door = hookDoor(hook_door) orelse return 0;
    return syntaxErrorCountCore(&door);
}

/// Returns how many diagnostics the most recent parse retained, in recording
/// order. Valid until the next parse begins.
export fn galley_recorded_diagnostic_count(session_ptr: ?*GalleySession) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return 0));
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return recordedDiagnosticCountCore(&sessionDoor(embedded));
}

fn writeSemanticFields(
    diagnostic: ?root.ParseDiagnostic,
    out_variable: ?*[*]const u8,
    out_variable_len: ?*usize,
    out_message: ?*[*]const u8,
    out_message_len: ?*usize,
) i64 {
    switch (diagnostic orelse return galley_error_no_diagnostic) {
        .semantic => |semantic| {
            if (out_variable) |ptr| ptr.* = semantic.variable.ptr;
            if (out_variable_len) |len| len.* = semantic.variable.len;
            if (out_message) |ptr| ptr.* = semantic.message.ptr;
            if (out_message_len) |len| len.* = semantic.message.len;
            return galley_ok;
        },
        .syntax, .indentation => return galley_error_no_diagnostic,
    }
}

/// Writes the variable and message of a semantic diagnostic. Fails with
/// `galley_error_no_diagnostic` when the diagnostic is null or not semantic.
export fn galley_diagnostic_semantic(
    session_ptr: ?*GalleySession,
    out_variable: ?*[*]const u8,
    out_variable_len: ?*usize,
    out_message: ?*[*]const u8,
    out_message_len: ?*usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return diagnosticSemanticCore(&sessionDoor(embedded), out_variable, out_variable_len, out_message, out_message_len);
}

/// Hook-time door: `galley_diagnostic_semantic` over the in-flight parse's
/// runtime context, reached through the parse's hook door. No lock; valid
/// until the parse that produced the door ends.
export fn galley_hook_diagnostic_semantic(
    hook_door: ?*anyopaque,
    out_variable: ?*[*]const u8,
    out_variable_len: ?*usize,
    out_message: ?*[*]const u8,
    out_message_len: ?*usize,
) i64 {
    const door = hookDoor(hook_door) orelse return galley_error_null_argument;
    return diagnosticSemanticCore(&door, out_variable, out_variable_len, out_message, out_message_len);
}

/// Writes the variable and message of the semantic diagnostic recorded at
/// `diag_index`. Fails with `galley_error_no_diagnostic` when the index is
/// out of range or the record is not semantic.
export fn galley_recorded_semantic(
    session_ptr: ?*GalleySession,
    diag_index: u64,
    out_variable: ?*[*]const u8,
    out_variable_len: ?*usize,
    out_message: ?*[*]const u8,
    out_message_len: ?*usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return writeSemanticFields(recordedDiagnostic(&sessionDoor(embedded), diag_index), out_variable, out_variable_len, out_message, out_message_len);
}

/// Writes the indentation width and emitted spaces of an indentation
/// diagnostic. Fails with `galley_error_no_diagnostic` when the diagnostic
/// is null or not an indentation diagnostic.
fn writeIndentationFields(
    diagnostic: ?root.ParseDiagnostic,
    out_spaces: ?*u32,
    out_indentation_width: ?*u32,
) i64 {
    switch (diagnostic orelse return galley_error_no_diagnostic) {
        .indentation => |indentation| {
            out_spaces.?.* = indentation.spaces;
            out_indentation_width.?.* = indentation.indentation_width;
            return galley_ok;
        },
        .syntax, .semantic => return galley_error_no_diagnostic,
    }
}

export fn galley_diagnostic_indentation(
    session_ptr: ?*GalleySession,
    out_spaces: ?*u32,
    out_indentation_width: ?*u32,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_spaces == null or out_indentation_width == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return diagnosticIndentationCore(&sessionDoor(embedded), out_spaces, out_indentation_width);
}

/// Hook-time door: `galley_diagnostic_indentation` over the in-flight parse's
/// runtime context, reached through the parse's hook door. No lock; valid
/// until the parse that produced the door ends.
export fn galley_hook_diagnostic_indentation(
    hook_door: ?*anyopaque,
    out_spaces: ?*u32,
    out_indentation_width: ?*u32,
) i64 {
    const door = hookDoor(hook_door) orelse return galley_error_null_argument;
    if (out_spaces == null or out_indentation_width == null) return galley_error_null_argument;
    return diagnosticIndentationCore(&door, out_spaces, out_indentation_width);
}

/// Writes the indentation width and emitted spaces of the diagnostic
/// recorded at `diag_index`. Fails with `galley_error_no_diagnostic` when
/// the index is out of range or the record is not an indentation diagnostic.
export fn galley_recorded_indentation(
    session_ptr: ?*GalleySession,
    diag_index: u64,
    out_spaces: ?*u32,
    out_indentation_width: ?*u32,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_spaces == null or out_indentation_width == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return writeIndentationFields(recordedDiagnostic(&sessionDoor(embedded), diag_index), out_spaces, out_indentation_width);
}

// ---------------------------------------------------------------------------
// Recovery information of a syntax diagnostic. Each field is exposed for
// the current diagnostic and, with a leading `diag_index`, for any
// diagnostic recorded during the most recent parse.
// ---------------------------------------------------------------------------

/// Returns the recovery target kind of a syntax diagnostic:
/// `galley_recovery_target_none` when there is no syntax diagnostic or no
/// recovery information, otherwise the matching target constant.
fn recoveryKindValue(syntax: ?root.SyntaxDiagnostic) i64 {
    const recovery = (syntax orelse return galley_recovery_target_none).recovery orelse return galley_recovery_target_none;
    return switch (recovery.target) {
        .lhs_variable => galley_recovery_target_lhs_variable,
        .production => galley_recovery_target_production,
        .occurrence => galley_recovery_target_occurrence,
    };
}

/// Returns the recovery target kind of the current syntax diagnostic:
/// `galley_recovery_target_none`, `galley_recovery_target_lhs_variable`,
/// `galley_recovery_target_production`, or
/// `galley_recovery_target_occurrence`.
export fn galley_diagnostic_recovery_kind(session_ptr: ?*GalleySession) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_recovery_target_none));
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return diagnosticRecoveryKindCore(&sessionDoor(embedded));
}

/// Hook-time door: `galley_diagnostic_recovery_kind` over the in-flight
/// parse's runtime context, reached through the parse's hook door. No lock;
/// valid until the parse that produced the door ends.
export fn galley_hook_diagnostic_recovery_kind(hook_door: ?*anyopaque) i64 {
    const door = hookDoor(hook_door) orelse return galley_recovery_target_none;
    return diagnosticRecoveryKindCore(&door);
}

/// Returns the recovery target kind of the diagnostic recorded at
/// `diag_index`.
export fn galley_recorded_diagnostic_recovery_kind(session_ptr: ?*GalleySession, diag_index: u64) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_recovery_target_none));
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return recoveryKindValue(recordedSyntaxDiagnostic(&sessionDoor(embedded), diag_index));
}

/// Writes the recovery terminal bytes of a syntax diagnostic into
/// `out_data`/`out_len`.
fn writeRecoveryTerminal(syntax: ?root.SyntaxDiagnostic, out_data: ?*[*]const u8, out_len: ?*usize) i64 {
    const recovery = (syntax orelse return galley_error_no_diagnostic).recovery orelse return galley_error_no_diagnostic;
    out_data.?.* = recovery.terminal.ptr;
    out_len.?.* = recovery.terminal.len;
    return galley_ok;
}

/// Writes the recovery terminal bytes into `out_data`/`out_len`.
export fn galley_diagnostic_recovery_terminal(
    session_ptr: ?*GalleySession,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_data == null or out_len == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return diagnosticRecoveryTerminalCore(&sessionDoor(embedded), out_data, out_len);
}

/// Hook-time door: `galley_diagnostic_recovery_terminal` over the in-flight
/// parse's runtime context, reached through the parse's hook door. No lock;
/// valid until the parse that produced the door ends.
export fn galley_hook_diagnostic_recovery_terminal(
    hook_door: ?*anyopaque,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const door = hookDoor(hook_door) orelse return galley_error_null_argument;
    if (out_data == null or out_len == null) return galley_error_null_argument;
    return diagnosticRecoveryTerminalCore(&door, out_data, out_len);
}

/// Writes the recovery terminal bytes of the diagnostic recorded at
/// `diag_index` into `out_data`/`out_len`.
export fn galley_recorded_recovery_terminal(
    session_ptr: ?*GalleySession,
    diag_index: u64,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_data == null or out_len == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return writeRecoveryTerminal(recordedSyntaxDiagnostic(&sessionDoor(embedded), diag_index), out_data, out_len);
}

/// Writes the resume side of a syntax diagnostic's recovery into `out`:
/// `galley_resume_before` (the terminal is preserved for the parser to
/// match) or `galley_resume_after` (the terminal is consumed).
fn writeRecoveryResume(syntax: ?root.SyntaxDiagnostic, out: ?*i64) i64 {
    const recovery = (syntax orelse return galley_error_no_diagnostic).recovery orelse return galley_error_no_diagnostic;
    out.?.* = switch (recovery.@"resume") {
        .before => galley_resume_before,
        .after => galley_resume_after,
    };
    return galley_ok;
}

export fn galley_diagnostic_recovery_resume(session_ptr: ?*GalleySession, out: ?*i64) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return diagnosticRecoveryResumeCore(&sessionDoor(embedded), out);
}

/// Hook-time door: `galley_diagnostic_recovery_resume` over the in-flight
/// parse's runtime context, reached through the parse's hook door. No lock;
/// valid until the parse that produced the door ends.
export fn galley_hook_diagnostic_recovery_resume(hook_door: ?*anyopaque, out: ?*i64) i64 {
    const door = hookDoor(hook_door) orelse return galley_error_null_argument;
    if (out == null) return galley_error_null_argument;
    return diagnosticRecoveryResumeCore(&door, out);
}

/// Writes the resume side of the recovery of the diagnostic recorded at
/// `diag_index`.
export fn galley_recorded_recovery_resume(session_ptr: ?*GalleySession, diag_index: u64, out: ?*i64) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return writeRecoveryResume(recordedSyntaxDiagnostic(&sessionDoor(embedded), diag_index), out);
}

/// Writes the LHS variable name of a `lhs_variable` recovery target into
/// `out_data`/`out_len`.
fn writeRecoveryLhsVariable(syntax: ?root.SyntaxDiagnostic, out_data: ?*[*]const u8, out_len: ?*usize) i64 {
    const recovery = (syntax orelse return galley_error_no_diagnostic).recovery orelse return galley_error_no_diagnostic;
    switch (recovery.target) {
        .lhs_variable => |name| {
            out_data.?.* = name.ptr;
            out_len.?.* = name.len;
            return galley_ok;
        },
        else => return galley_error_no_diagnostic,
    }
}

export fn galley_diagnostic_recovery_lhs_variable(
    session_ptr: ?*GalleySession,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_data == null or out_len == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return diagnosticRecoveryLhsVariableCore(&sessionDoor(embedded), out_data, out_len);
}

/// Hook-time door: `galley_diagnostic_recovery_lhs_variable` over the in-
/// flight parse's runtime context, reached through the parse's hook door. No
/// lock; valid until the parse that produced the door ends.
export fn galley_hook_diagnostic_recovery_lhs_variable(
    hook_door: ?*anyopaque,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const door = hookDoor(hook_door) orelse return galley_error_null_argument;
    if (out_data == null or out_len == null) return galley_error_null_argument;
    return diagnosticRecoveryLhsVariableCore(&door, out_data, out_len);
}

/// Writes the LHS variable name of the `lhs_variable` recovery target of the
/// diagnostic recorded at `diag_index`.
export fn galley_recorded_recovery_lhs_variable(
    session_ptr: ?*GalleySession,
    diag_index: u64,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_data == null or out_len == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return writeRecoveryLhsVariable(recordedSyntaxDiagnostic(&sessionDoor(embedded), diag_index), out_data, out_len);
}

/// Writes the variable name and production index of a `production` recovery
/// target into `out_variable`/`out_variable_len` and `out_rhs_index`.
fn writeRecoveryProduction(
    syntax: ?root.SyntaxDiagnostic,
    out_variable: ?*[*]const u8,
    out_variable_len: ?*usize,
    out_rhs_index: ?*u32,
) i64 {
    const recovery = (syntax orelse return galley_error_no_diagnostic).recovery orelse return galley_error_no_diagnostic;
    switch (recovery.target) {
        .production => |production| {
            out_variable.?.* = production.variable.ptr;
            out_variable_len.?.* = production.variable.len;
            out_rhs_index.?.* = @intCast(production.rhs_index);
            return galley_ok;
        },
        else => return galley_error_no_diagnostic,
    }
}

export fn galley_diagnostic_recovery_production(
    session_ptr: ?*GalleySession,
    out_variable: ?*[*]const u8,
    out_variable_len: ?*usize,
    out_rhs_index: ?*u32,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_variable == null or out_variable_len == null or out_rhs_index == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return diagnosticRecoveryProductionCore(&sessionDoor(embedded), out_variable, out_variable_len, out_rhs_index);
}

/// Hook-time door: `galley_diagnostic_recovery_production` over the in-flight
/// parse's runtime context, reached through the parse's hook door. No lock;
/// valid until the parse that produced the door ends.
export fn galley_hook_diagnostic_recovery_production(
    hook_door: ?*anyopaque,
    out_variable: ?*[*]const u8,
    out_variable_len: ?*usize,
    out_rhs_index: ?*u32,
) i64 {
    const door = hookDoor(hook_door) orelse return galley_error_null_argument;
    if (out_variable == null or out_variable_len == null or out_rhs_index == null) return galley_error_null_argument;
    return diagnosticRecoveryProductionCore(&door, out_variable, out_variable_len, out_rhs_index);
}

/// Writes the production recovery coordinates of the diagnostic recorded at
/// `diag_index`.
export fn galley_recorded_recovery_production(
    session_ptr: ?*GalleySession,
    diag_index: u64,
    out_variable: ?*[*]const u8,
    out_variable_len: ?*usize,
    out_rhs_index: ?*u32,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_variable == null or out_variable_len == null or out_rhs_index == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return writeRecoveryProduction(recordedSyntaxDiagnostic(&sessionDoor(embedded), diag_index), out_variable, out_variable_len, out_rhs_index);
}

/// Writes the occurrence coordinates of an `occurrence` recovery target:
/// parent variable name, production index, symbol index within the
/// production, and the occurrence variable name.
fn writeRecoveryOccurrence(
    syntax: ?root.SyntaxDiagnostic,
    out_parent_variable: ?*[*]const u8,
    out_parent_variable_len: ?*usize,
    out_rhs_index: ?*u32,
    out_symbol_index: ?*u32,
    out_variable: ?*[*]const u8,
    out_variable_len: ?*usize,
) i64 {
    const recovery = (syntax orelse return galley_error_no_diagnostic).recovery orelse return galley_error_no_diagnostic;
    switch (recovery.target) {
        .occurrence => |occurrence| {
            out_parent_variable.?.* = occurrence.parent_variable.ptr;
            out_parent_variable_len.?.* = occurrence.parent_variable.len;
            out_rhs_index.?.* = @intCast(occurrence.rhs_index);
            out_symbol_index.?.* = @intCast(occurrence.symbol_index);
            out_variable.?.* = occurrence.variable.ptr;
            out_variable_len.?.* = occurrence.variable.len;
            return galley_ok;
        },
        else => return galley_error_no_diagnostic,
    }
}

export fn galley_diagnostic_recovery_occurrence(
    session_ptr: ?*GalleySession,
    out_parent_variable: ?*[*]const u8,
    out_parent_variable_len: ?*usize,
    out_rhs_index: ?*u32,
    out_symbol_index: ?*u32,
    out_variable: ?*[*]const u8,
    out_variable_len: ?*usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_parent_variable == null or out_parent_variable_len == null or
        out_rhs_index == null or out_symbol_index == null or
        out_variable == null or out_variable_len == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return diagnosticRecoveryOccurrenceCore(&sessionDoor(embedded), out_parent_variable, out_parent_variable_len, out_rhs_index, out_symbol_index, out_variable, out_variable_len);
}

/// Hook-time door: `galley_diagnostic_recovery_occurrence` over the in-flight
/// parse's runtime context, reached through the parse's hook door. No lock;
/// valid until the parse that produced the door ends.
export fn galley_hook_diagnostic_recovery_occurrence(
    hook_door: ?*anyopaque,
    out_parent_variable: ?*[*]const u8,
    out_parent_variable_len: ?*usize,
    out_rhs_index: ?*u32,
    out_symbol_index: ?*u32,
    out_variable: ?*[*]const u8,
    out_variable_len: ?*usize,
) i64 {
    const door = hookDoor(hook_door) orelse return galley_error_null_argument;
    if (out_parent_variable == null or out_parent_variable_len == null or
        out_rhs_index == null or out_symbol_index == null or
        out_variable == null or out_variable_len == null) return galley_error_null_argument;
    return diagnosticRecoveryOccurrenceCore(&door, out_parent_variable, out_parent_variable_len, out_rhs_index, out_symbol_index, out_variable, out_variable_len);
}

/// Writes the occurrence recovery coordinates of the diagnostic recorded at
/// `diag_index`.
export fn galley_recorded_recovery_occurrence(
    session_ptr: ?*GalleySession,
    diag_index: u64,
    out_parent_variable: ?*[*]const u8,
    out_parent_variable_len: ?*usize,
    out_rhs_index: ?*u32,
    out_symbol_index: ?*u32,
    out_variable: ?*[*]const u8,
    out_variable_len: ?*usize,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_parent_variable == null or out_parent_variable_len == null or
        out_rhs_index == null or out_symbol_index == null or
        out_variable == null or out_variable_len == null) return galley_error_null_argument;
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return writeRecoveryOccurrence(recordedSyntaxDiagnostic(&sessionDoor(embedded), diag_index), out_parent_variable, out_parent_variable_len, out_rhs_index, out_symbol_index, out_variable, out_variable_len);
}

// ---------------------------------------------------------------------------
// Node and storage extras.
// ---------------------------------------------------------------------------

/// Returns a node's raw variable index into the parser's variable list (see
/// `galley_variable_name`), or `GALLEY_NO_VARIABLE` when the node has no
/// variable (for example a terminal-only node). Refuses an address outside
/// the live tree's storage with `galley_error_invalid_node`, and a
/// `generation` from another parse with `galley_error_stale_tree`.
export fn galley_node_variable_index(
    session_ptr: ?*GalleySession,
    generation: u64,
    address: GalleyNodeAddress,
) i64 {
    return nodeValue(.session, session_ptr, generation, address, nodeVariableIndexCore, .{});
}

/// Hook-time twin of `galley_node_variable_index`: same returns, same
/// refusals, over the parse that handed out `hook_door`.
export fn galley_hook_node_variable_index(
    hook_door: ?*anyopaque,
    generation: u64,
    address: GalleyNodeAddress,
) i64 {
    return nodeValue(.hook, hook_door, generation, address, nodeVariableIndexCore, .{});
}

/// Bulk-reads the published tree into caller-owned flat arrays in a single
/// crossing: address `i` fills slot `i` of each non-null out array. Returns
/// the total node count (the value `galley_node_count` reports for the same
/// `generation`; 0 without AST construction) or a negative status. When
/// `capacity` is smaller than the count only the `[0, capacity)` prefix is
/// written. Null arrays skip that column. `generation` must be the one
/// `galley_root_node` reported: a caller whose parse ran in between gets
/// `galley_error_stale_tree` instead of columns mixing two trees. The
/// `out_is_semantic_error` column carries 1 where the node carries a semantic
/// error, else 0 — the flag `galley_walk_next` records in the cursor.
export fn galley_tree_snapshot(
    session_ptr: ?*GalleySession,
    generation: u64,
    out_parent: ?[*]GalleyNodeAddress,
    out_first_child: ?[*]GalleyNodeAddress,
    out_next: ?[*]GalleyNodeAddress,
    out_child_count: ?[*]u32,
    out_variable: ?[*]i64,
    out_span_start: ?[*]u64,
    out_span_len: ?[*]u64,
    out_is_semantic_error: ?[*]i32,
    capacity: u64,
) i64 {
    if (session_ptr == null) return galley_error_null_argument;
    return nodeRead(.session, session_ptr, generation, 0, &.{}, treeSnapshotCore, .{ out_parent, out_first_child, out_next, out_child_count, out_variable, out_span_start, out_span_len, out_is_semantic_error, capacity });
}

/// Hook-time twin of `galley_tree_snapshot`: same columns and refusals, over
/// the parse that handed out `hook_door`.
export fn galley_hook_tree_snapshot(
    hook_door: ?*anyopaque,
    generation: u64,
    out_parent: ?[*]GalleyNodeAddress,
    out_first_child: ?[*]GalleyNodeAddress,
    out_next: ?[*]GalleyNodeAddress,
    out_child_count: ?[*]u32,
    out_variable: ?[*]i64,
    out_span_start: ?[*]u64,
    out_span_len: ?[*]u64,
    out_is_semantic_error: ?[*]i32,
    capacity: u64,
) i64 {
    return nodeRead(.hook, hook_door, generation, 0, &.{}, treeSnapshotCore, .{ out_parent, out_first_child, out_next, out_child_count, out_variable, out_span_start, out_span_len, out_is_semantic_error, capacity });
}

/// Inserts `first_node` (and its chain) into the children of `parent` at
/// `index`. An index equal to the child count appends; a larger index returns
/// `galley_error_invalid_node` in every build. Other misuse (a chain that is
/// still attached, or that contains `parent` or one of its ancestors) is
/// undefined behavior in release builds; Debug builds check it and abort the
/// process on failure.
export fn galley_tree_insert_children_at(
    session_ptr: ?*GalleySession,
    generation: u64,
    parent: GalleyNodeAddress,
    index: usize,
    first_node: GalleyNodeAddress,
) i64 {
    return treeEdit(.session, session_ptr, generation, &.{}, treeInsertChildrenAtCore, .{ parent, index, first_node });
}

/// Hook-time twin of `galley_tree_insert_children_at`: same parameters and refusals, over the
/// parse that handed out `hook_door`.
export fn galley_hook_tree_insert_children_at(
    hook_door: ?*anyopaque,
    generation: u64,
    parent: GalleyNodeAddress,
    index: usize,
    first_node: GalleyNodeAddress,
) i64 {
    return treeEdit(.hook, hook_door, generation, &.{}, treeInsertChildrenAtCore, .{ parent, index, first_node });
}

/// Removes `count` consecutive children of `parent` starting at child
/// `index`, writing the detached chain head to `out_head`. A `count` of 0 is
/// a no-op that returns `galley_ok` with an invalid head, whatever the
/// `index`; an `index` and `count` that reach past the last child return
/// `galley_error_invalid_node` in every build.
export fn galley_tree_remove_children_at(
    session_ptr: ?*GalleySession,
    generation: u64,
    parent: GalleyNodeAddress,
    index: usize,
    count: usize,
    out_head: ?*GalleyNodeAddress,
) i64 {
    return treeEdit(.session, session_ptr, generation, &.{3}, treeRemoveChildrenAtCore, .{ parent, index, count, out_head });
}

/// Hook-time twin of `galley_tree_remove_children_at`: same parameters and refusals, over the
/// parse that handed out `hook_door`.
export fn galley_hook_tree_remove_children_at(
    hook_door: ?*anyopaque,
    generation: u64,
    parent: GalleyNodeAddress,
    index: usize,
    count: usize,
    out_head: ?*GalleyNodeAddress,
) i64 {
    return treeEdit(.hook, hook_door, generation, &.{3}, treeRemoveChildrenAtCore, .{ parent, index, count, out_head });
}

/// Preallocates node storage for at least `capacity` nodes, avoiding
/// growth during subsequent parses. Fails with
/// `galley_error_ast_capacity_exceeded` when the request exceeds the
/// build's node limit. Takes the exclusive door: returns
/// `galley_error_session_in_use` while a parse is in flight.
export fn galley_reserve_nodes(session_ptr: ?*GalleySession, capacity: u64) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (comptime !parser.is_ast_enabled) return galley_ok;
    if (capacity > std.math.maxInt(usize)) return galley_error_ast_capacity_exceeded;
    var guard = embedded.session.edit() catch |err| return statusForError(err);
    defer guard.deinit();
    guard.mutableAstAllocator().ensureCapacity(@intCast(capacity)) catch |err| switch (err) {
        error.OutOfMemory => return galley_error_out_of_memory,
        error.ASTCapacityTooLarge => return galley_error_ast_capacity_exceeded,
    };
    return galley_ok;
}

/// Returns the current node storage capacity in nodes. Refuses with 0 while
/// a parse is in flight.
export fn galley_node_capacity(session_ptr: ?*GalleySession) u64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return 0));
    if (comptime !parser.is_ast_enabled) return 0;
    var guard = embedded.session.readLatest() catch return 0;
    defer guard.deinit();
    return embedded.session.node_allocator.totalNodeCapacity();
}

// ---------------------------------------------------------------------------
// Generated-parser metadata.
// ---------------------------------------------------------------------------

/// Returns nonzero when the library was built with AST construction.
export fn galley_has_ast() i32 {
    return if (parser.is_ast_enabled) 1 else 0;
}

/// Returns nonzero when the library was built with procedure hooks enabled.
export fn galley_has_procedures() i32 {
    return if (root.procedures_enabled) 1 else 0;
}

/// Returns nonzero when no-AST parsers allow tree-helper procedures.
export fn galley_allows_no_ast_tree_procedures() i32 {
    return if (@hasDecl(parser, "allow_no_ast_tree_procedures"))
        (if (parser.allow_no_ast_tree_procedures) 1 else 0)
    else
        0;
}

/// Returns nonzero when the session retains source text (required for
/// `galley_node_text`).
export fn galley_source_retention_enabled() i32 {
    return if (root.source_retention_enabled) 1 else 0;
}

/// Returns nonzero when the platform supports stack-overflow recovery.
export fn galley_stack_overflow_recovery_available() i32 {
    return if (root.stack_overflow_utilities.is_supported) 1 else 0;
}

/// Returns the parser family of this library: `galley_parser_type_ll` or
/// `galley_parser_type_lr`.
export fn galley_parser_type() i64 {
    return switch (parser.parser_type) {
        .ll => galley_parser_type_ll,
        .lr => galley_parser_type_lr,
    };
}

/// Returns the generated error-recovery mode:
/// `galley_recovery_mode_disabled`, `galley_recovery_mode_automatic`, or
/// `galley_recovery_mode_explicit`.
export fn galley_error_recovery_mode() i64 {
    return switch (parser.error_recovery_mode) {
        .disabled => galley_recovery_mode_disabled,
        .automatic => galley_recovery_mode_automatic,
        .explicit => galley_recovery_mode_explicit,
    };
}

/// Returns nonzero when the grammar uses verbatim raw capture.
export fn galley_uses_verbatim() i32 {
    return if (@hasDecl(parser, "uses_verbatim")) (if (parser.uses_verbatim) 1 else 0) else 0;
}

/// Returns nonzero when the parser tracks positions (line/column data is
/// meaningful).
export fn galley_has_position_tracking() i32 {
    return if (root.position_tracking_enabled) 1 else 0;
}

/// Returns nonzero when the parser supports incremental input streaming.
export fn galley_has_input_streaming() i32 {
    return if (root.input_streaming_enabled) 1 else 0;
}

/// Returns the number of grammar symbols (variables and terminals).
export fn galley_symbol_count() u64 {
    return @intCast(parser.symbols.len);
}

/// Writes the name of the symbol at `index` into `out_data`/`out_len`. The
/// pointer references static grammar storage.
export fn galley_symbol_name(session_ptr: ?*GalleySession, index: u64, out_data: ?*[*]const u8, out_len: ?*usize) i64 {
    _ = session_ptr;
    if (out_data == null or out_len == null) return galley_error_null_argument;
    if (index >= parser.symbols.len) return galley_error_invalid_node;
    out_data.?.* = parser.symbols[@intCast(index)].ptr;
    out_len.?.* = parser.symbols[@intCast(index)].len;
    return galley_ok;
}

/// Returns nonzero when the symbol at `index` is a terminal (or generative
/// terminal) rather than a variable.
export fn galley_symbol_is_terminal(session_ptr: ?*GalleySession, index: u64) i32 {
    _ = session_ptr;
    if (index >= parser.is_terminal.len) return 0;
    return if (parser.is_terminal[@intCast(index)]) 1 else 0;
}

/// Returns the number of grammar variables.
export fn galley_variable_count() u64 {
    return @intCast(parser.variables.len);
}

/// Writes the name of the variable at `index` into `out_data`/`out_len`.
export fn galley_variable_name(session_ptr: ?*GalleySession, index: u64, out_data: ?*[*]const u8, out_len: ?*usize) i64 {
    _ = session_ptr;
    if (out_data == null or out_len == null) return galley_error_null_argument;
    if (index >= parser.variables.len) return galley_error_invalid_node;
    out_data.?.* = parser.variables[@intCast(index)].ptr;
    out_len.?.* = parser.variables[@intCast(index)].len;
    return galley_ok;
}

// ---------------------------------------------------------------------------
// ProcedureArguments: per-hook state (current node, rule, drop/replace
// channel, position), valid only while its hook runs. Tree queries and
// edits use the `galley_hook_node_*` / `galley_hook_tree_*` twins over the
// parse's door (`galley_procedure_door`); the session-door `galley_node_*` /
// `galley_tree_*` functions belong to post-parse access and refuse during a
// parse.
// ---------------------------------------------------------------------------

inline fn allowsNoAstTreeProcedures() bool {
    return @hasDecl(parser, "allow_no_ast_tree_procedures") and parser.allow_no_ast_tree_procedures;
}

inline fn procedureArguments(args: ?*anyopaque) ?*root.data_structures.ProcedureArguments {
    return @ptrCast(@alignCast(args orelse return null));
}

/// Returns the parse-time door of the parse that is calling this hook: the
/// handle the `galley_hook_*` twins take. It is the same pointer for every
/// hook of one parse and dies when that parse ends, so a host may keep it for
/// the parse and must drop it after. Returns null for null `args`.
export fn galley_procedure_door(args: ?*anyopaque) ?*anyopaque {
    const procedure_arguments = procedureArguments(args) orelse return null;
    return procedure_arguments.context;
}

/// Returns the session whose parse is calling this hook, or null for null
/// `args`. A host that keeps per-session state outside the core (the Go
/// binding's door lifetime) finds it from a hook's arguments through this.
export fn galley_procedure_session(args: ?*anyopaque) ?*GalleySession {
    const procedure_arguments = procedureArguments(args) orelse return null;
    // The parent pointers are only as aligned as the fields they come from
    // (2 on wasm32), but the session really is an aligned `Embedded`.
    const session: *root.Session = @alignCast(@fieldParentPtr("runtime_context", procedure_arguments.context.runtime()));
    const embedded: *Embedded = @alignCast(@fieldParentPtr("session", session));
    return @ptrCast(embedded);
}

/// Writes the parse generation of the parse that owns `hook_door` to
/// `out_generation`: the generation of every node its hooks see, and of the
/// tree it publishes if it succeeds (`galley_root_node` reports it afterwards).
/// Constant for the whole parse and takes no lock, so a host may read it once
/// per hook. Returns `galley_error_null_argument` for a null door or output.
export fn galley_hook_generation(hook_door: ?*anyopaque, out_generation: ?*u64) i64 {
    const out = out_generation orelse return galley_error_null_argument;
    const context: *root.data_structures.Context = @ptrCast(@alignCast(hook_door orelse return galley_error_null_argument));
    out.* = context.generation;
    return galley_ok;
}

export fn galley_procedure_current_node(args: ?*anyopaque) GalleyNodeAddress {
    const procedure_arguments = procedureArguments(args) orelse return galley_invalid_node;
    if (comptime !parser.is_ast_enabled) return galley_invalid_node;
    const addr = procedure_arguments.node_address orelse return galley_invalid_node;
    return @intCast(addr);
}

/// The body behind `galley_procedure_set_current_node`, run through the hook
/// door's gate: the node must be a live node of this parse's storage.
fn setCurrentNodeCore(
    door: *const Door,
    procedure_arguments: *root.data_structures.ProcedureArguments,
    node: GalleyNodeAddress,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_invalid_node;
    procedure_arguments.node_address = door.livePointer(node) orelse return galley_error_invalid_node;
    return galley_ok;
}

/// Sets the current node of this hook to `node`, a node of the parse that
/// owns `args`, or clears it when `node` is `GALLEY_INVALID_NODE` (which
/// needs no generation). The node goes through the hook door's gate like any
/// other: `galley_error_stale_tree` when `generation` is not this parse's
/// (generation 0 never is), `galley_error_invalid_node` for an address
/// outside the parse's node storage, `galley_error_null_argument` for null
/// `args`. A refused call leaves the current node as it was.
export fn galley_procedure_set_current_node(args: ?*anyopaque, generation: u64, node: GalleyNodeAddress) i64 {
    const procedure_arguments = procedureArguments(args) orelse return galley_error_null_argument;
    if (node == galley_invalid_node) {
        if (comptime parser.is_ast_enabled) procedure_arguments.node_address = null;
        return galley_ok;
    }
    return nodeRead(.hook, procedure_arguments.context, generation, galley_error_invalid_node, &.{}, setCurrentNodeCore, .{ procedure_arguments, node });
}

export fn galley_procedure_rule_present(args: ?*anyopaque) i32 {
    const procedure_arguments = procedureArguments(args) orelse return 0;
    return if (procedure_arguments.rule != null) 1 else 0;
}

export fn galley_procedure_rule_header(args: ?*anyopaque) i64 {
    const procedure_arguments = procedureArguments(args) orelse return -1;
    const rule = procedure_arguments.rule orelse return -1;
    return @intCast(rule.header);
}

export fn galley_procedure_rule_rhs_index(args: ?*anyopaque) i64 {
    const procedure_arguments = procedureArguments(args) orelse return -1;
    const rule = procedure_arguments.rule orelse return -1;
    return std.fmt.parseInt(i64, rule.right_hand_side_index, 10) catch -1;
}

export fn galley_procedure_rule_right_hand_side(args: ?*anyopaque, out_data: ?*[*]const u16, out_len: ?*usize) i64 {
    const procedure_arguments = procedureArguments(args) orelse return galley_error_null_argument;
    if (out_data == null or out_len == null) return galley_error_null_argument;
    const rule = procedure_arguments.rule orelse return -1;
    out_data.?.* = rule.right_hand_side.ptr;
    out_len.?.* = rule.right_hand_side.len;
    return galley_ok;
}

export fn galley_procedure_rule_rhs_index_slice(args: ?*anyopaque, out_data: ?*[*]const u8, out_len: ?*usize) i64 {
    const procedure_arguments = procedureArguments(args) orelse return galley_error_null_argument;
    if (out_data == null or out_len == null) return galley_error_null_argument;
    const rule = procedure_arguments.rule orelse return -1;
    out_data.?.* = rule.right_hand_side_index.ptr;
    out_len.?.* = rule.right_hand_side_index.len;
    return galley_ok;
}

export fn galley_procedure_context_line(args: ?*anyopaque) u32 {
    const procedure_arguments = procedureArguments(args) orelse return 0;
    if (comptime !root.position_tracking_enabled) return 0;
    return procedure_arguments.context.line;
}

export fn galley_procedure_context_column(args: ?*anyopaque) u32 {
    const procedure_arguments = procedureArguments(args) orelse return 0;
    if (comptime !root.position_tracking_enabled) return 0;
    return procedure_arguments.context.column;
}

export fn galley_procedure_drop_self(args: ?*anyopaque) i64 {
    const procedure_arguments = procedureArguments(args) orelse return galley_error_null_argument;
    if (comptime parser.is_ast_enabled or allowsNoAstTreeProcedures()) {
        root.standard_procedures.dropSelf(procedure_arguments) catch |e| return statusForError(e);
        return galley_ok;
    }
    return galley_error_internal;
}

export fn galley_procedure_drop_children(args: ?*anyopaque) i64 {
    const procedure_arguments = procedureArguments(args) orelse return galley_error_null_argument;
    if (comptime parser.is_ast_enabled or allowsNoAstTreeProcedures()) {
        root.standard_procedures.dropChildren(procedure_arguments) catch |e| return statusForError(e);
        return galley_ok;
    }
    return galley_error_internal;
}

export fn galley_procedure_drop_if_empty(args: ?*anyopaque) i64 {
    const procedure_arguments = procedureArguments(args) orelse return galley_error_null_argument;
    if (comptime parser.is_ast_enabled or allowsNoAstTreeProcedures()) {
        root.standard_procedures.dropIfEmpty(procedure_arguments) catch |e| return statusForError(e);
        return galley_ok;
    }
    return galley_error_internal;
}

export fn galley_procedure_replace_with_children(args: ?*anyopaque) i64 {
    const procedure_arguments = procedureArguments(args) orelse return galley_error_null_argument;
    if (comptime parser.is_ast_enabled or allowsNoAstTreeProcedures()) {
        root.standard_procedures.replaceWithChildren(procedure_arguments) catch |e| return statusForError(e);
        return galley_ok;
    }
    return galley_error_internal;
}

export fn galley_procedure_left_recursive_reduction(args: ?*anyopaque) i64 {
    const procedure_arguments = procedureArguments(args) orelse return galley_error_null_argument;
    if (comptime parser.is_ast_enabled or allowsNoAstTreeProcedures()) {
        root.standard_procedures.leftRecursiveReduction(procedure_arguments) catch |e| return statusForError(e);
        return galley_ok;
    }
    return galley_error_internal;
}

export fn galley_procedure_right_recursive_reduction(args: ?*anyopaque) i64 {
    const procedure_arguments = procedureArguments(args) orelse return galley_error_null_argument;
    if (comptime parser.is_ast_enabled or allowsNoAstTreeProcedures()) {
        root.standard_procedures.rightRecursiveReduction(procedure_arguments) catch |e| return statusForError(e);
        return galley_ok;
    }
    return galley_error_internal;
}

/// Reports a semantic error on the current node and returns the total
/// semantic error count, or a negative status. Parsing continues; a
/// syntax-clean parse with any semantic error returns `SemanticError`.
export fn galley_procedure_report_semantic_error(args: ?*anyopaque, message_ptr: ?[*]const u8, message_len: usize) i64 {
    const procedure_arguments = procedureArguments(args) orelse return galley_error_null_argument;
    const message = if (message_ptr) |ptr| ptr[0..message_len] else if (message_len == 0) @as([]const u8, &.{}) else return galley_error_null_argument;
    const count = procedure_arguments.reportSemanticError(message) catch |e| return statusForError(e);
    return @intCast(count);
}

/// Returns how many semantic errors the most recent parse recorded.
/// Returns `galley_error_session_in_use` while a parse is in flight.
export fn galley_semantic_error_count(session_ptr: ?*GalleySession) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return 0));
    var guard = embedded.session.readLatest() catch |err| return statusForError(err);
    defer guard.deinit();
    return semanticErrorCountCore(&sessionDoor(embedded));
}

/// Hook-time door: `galley_semantic_error_count` over the in-flight parse's
/// runtime context, reached through the parse's hook door. No lock; valid
/// until the parse that produced the door ends.
export fn galley_hook_semantic_error_count(hook_door: ?*anyopaque) i64 {
    const door = hookDoor(hook_door) orelse return 0;
    return semanticErrorCountCore(&door);
}
