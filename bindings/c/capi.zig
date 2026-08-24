//! C application-binary interface for a generated Galley parser.
//!
//! Built as a shared library through `bindings/c/consumer/build.zig` (the
//! external entry point: pass the generated parser source with
//! `-Dparser-source` and the library name with `-Dlib-name`). The C header
//! shipped next to the library is `bindings/c/galley.h`; the examples in
//! `examples/c` and `examples/cpp` are reference consumers.
//!
//! Sessions own their IO backend and allocator (the C allocator) and are not
//! thread-safe: use one session per thread, or guard it externally. Node
//! addresses, text pointers, and diagnostics remain valid until the next
//! parse on the same session or session destruction.
//!
//! Scope notes: semantic payloads are unavailable, procedure hooks and
//! error-message hooks are compiled into the library from the consumer's
//! procedures and error-messages files (see the bindings docs).

const std = @import("std");
const root = @import("galley");
const parser = root.parser;
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
    /// default (2.0); 0 disables preallocation.
    ast_preallocation_ratio: f64 = -1.0,
    /// Upper bound on preallocation in nodes; 0 selects the runtime default.
    ast_preallocation_cap: u64 = 0,
};

/// Node addresses are stable indices into the session's node storage.
pub const GalleyNodeAddress = u64;

/// Returned by tree queries when no node exists at that position.
pub const galley_invalid_node: GalleyNodeAddress = std.math.maxInt(u64);

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

/// Diagnostic kinds returned by `galley_diagnostic_kind`.
pub const galley_diagnostic_kind_none: i64 = 0;
pub const galley_diagnostic_kind_syntax: i64 = 1;
pub const galley_diagnostic_kind_indentation: i64 = 2;

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
    last_result: ?root.ParseResult = null,
    rendered_diagnostic: ?[:0]u8 = null,
    rendered_ansi_diagnostic: ?[:0]u8 = null,
    /// Input of the most recent parse; node text offsets index it.
    last_input: []const u8 = &.{},

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

    fn nodeAt(self: *Embedded, address: GalleyNodeAddress) ?*root.data_structures.Node {
        if (comptime !parser.is_ast_enabled) return null;
        if (address >= self.session.node_allocator.counter) return null;
        return self.session.node_allocator.at(@intCast(address));
    }
};

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
    embedded.session.deinit();
    embedded.threaded.deinit();
    std.heap.c_allocator.destroy(embedded);
}

fn statusForError(err: anyerror) i64 {
    return switch (err) {
        error.SyntaxError => galley_error_syntax,
        error.IndentationError => galley_error_indentation,
        error.StackOverflow => galley_error_stack_overflow,
        error.ASTCapacityExceeded => galley_error_ast_capacity_exceeded,
        error.UnterminatedRawString => galley_error_unterminated_raw_string,
        error.OutOfMemory => galley_error_out_of_memory,
        else => galley_error_internal,
    };
}

fn finishParse(embedded: *Embedded, result: root.ParseResult) i64 {
    embedded.last_result = result;
    return @intCast(result.parsed_bytes);
}

fn ignoreDiagnosticMessage(_: []const u8) void {}

/// Parses one NUL-terminated input string. Returns the number of bytes
/// parsed on success, or a negative status code.
export fn galley_parse_sentinel(session_ptr: ?*GalleySession, input: ?[*:0]const u8) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    const text = std.mem.sliceTo(input orelse return galley_error_null_argument, 0);
    embedded.clearRenderedDiagnostic();
    const result = embedded.session.parseSentinelBytes(text, null) catch |err| return statusForError(err);
    embedded.last_input = embedded.session.owned_input orelse text;
    return finishParse(embedded, result);
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
    embedded.clearRenderedDiagnostic();
    const result = embedded.session.parseBytes(bytes, null) catch |err| return statusForError(err);
    embedded.last_input = embedded.session.owned_input orelse bytes;
    return finishParse(embedded, result);
}

/// Returns the number of AST nodes allocated by the most recent successful
/// parse. Always 0 when the generated parser was built without AST
/// construction.
export fn galley_node_count(session_ptr: ?*GalleySession) u64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return 0));
    if (comptime !parser.is_ast_enabled) return 0;
    return @intCast(embedded.session.node_allocator.counter);
}

/// Returns the address of the root node of the most recent successful parse,
/// or `GALLEY_INVALID_NODE` when there is none (failed parse, or a parser
/// built without AST construction).
export fn galley_root_node(session_ptr: ?*GalleySession) GalleyNodeAddress {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_invalid_node));
    if (comptime !parser.is_ast_enabled) return galley_invalid_node;
    if (embedded.last_result) |result| {
        if (result.ast_root) |ast_root| return @intCast(ast_root);
    }
    return galley_invalid_node;
}

/// Returns nonzero when `address` refers to a live node of the most recent
/// parse.
export fn galley_node_is_valid(session_ptr: ?*GalleySession, address: GalleyNodeAddress) i32 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return 0));
    return if (embedded.nodeAt(address) != null) 1 else 0;
}

/// Returns the number of direct children of a node, or 0 for invalid nodes.
export fn galley_node_child_count(session_ptr: ?*GalleySession, address: GalleyNodeAddress) u32 {
    if (comptime !parser.is_ast_enabled) return 0;
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return 0));
    const node = embedded.nodeAt(address) orelse return 0;
    return node.children_count;
}

/// Returns the first child address, or `GALLEY_INVALID_NODE`.
export fn galley_node_first_child(session_ptr: ?*GalleySession, address: GalleyNodeAddress) GalleyNodeAddress {
    if (comptime !parser.is_ast_enabled) return galley_invalid_node;
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_invalid_node));
    const node = embedded.nodeAt(address) orelse return galley_invalid_node;
    if (node.first_child == root.data_structures.Node.invalid_pointer) return galley_invalid_node;
    return @intCast(node.first_child);
}

/// Returns the next sibling address, or `GALLEY_INVALID_NODE`.
export fn galley_node_next_sibling(session_ptr: ?*GalleySession, address: GalleyNodeAddress) GalleyNodeAddress {
    if (comptime !parser.is_ast_enabled) return galley_invalid_node;
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_invalid_node));
    const node = embedded.nodeAt(address) orelse return galley_invalid_node;
    if (node.next == root.data_structures.Node.invalid_pointer) return galley_invalid_node;
    return @intCast(node.next);
}

/// Returns the parent address, or `GALLEY_INVALID_NODE` for the root.
export fn galley_node_parent(session_ptr: ?*GalleySession, address: GalleyNodeAddress) GalleyNodeAddress {
    if (comptime !parser.is_ast_enabled) return galley_invalid_node;
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_invalid_node));
    const node = embedded.nodeAt(address) orelse return galley_invalid_node;
    if (node.parent == root.data_structures.Node.invalid_pointer) return galley_invalid_node;
    return @intCast(node.parent);
}

/// Writes the grammar symbol name of a node (for example `"ObjectMembers"`)
/// into `out_data`/`out_len`. The pointer references static storage valid for
/// the process lifetime. Terminal-only nodes report length 0.
export fn galley_node_symbol_name(
    session_ptr: ?*GalleySession,
    address: GalleyNodeAddress,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_invalid_node;
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_data == null or out_len == null) return galley_error_null_argument;
    const node = embedded.nodeAt(address) orelse return galley_error_invalid_node;
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

/// Writes the source text matched by a node into `out_data`/`out_len`. The
/// pointer references the session's retained input and stays valid until the
/// next parse or session destruction.
export fn galley_node_text(
    session_ptr: ?*GalleySession,
    address: GalleyNodeAddress,
    out_data: ?*[*]const u8,
    out_len: ?*usize,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_invalid_node;
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_data == null or out_len == null) return galley_error_null_argument;
    const node = embedded.nodeAt(address) orelse return galley_error_invalid_node;
    if (node.text_start + node.text_length > embedded.last_input.len) return galley_error_internal;
    out_data.?.* = embedded.last_input.ptr + node.text_start;
    out_len.?.* = node.text_length;
    return galley_ok;
}

/// Returns nonzero when the previous parse produced a diagnostic.
export fn galley_has_diagnostic(session_ptr: ?*GalleySession) i32 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return 0));
    return if (embedded.session.runtime_context.lastDiagnostic() != null) 1 else 0;
}

/// Returns the diagnostic recorded at `diag_index` during the most recent
/// parse (0-based, in recording order), or null when the index is out of
/// range.
fn recordedDiagnostic(embedded: *Embedded, diag_index: u64) ?root.ParseDiagnostic {
    const records = embedded.session.runtime_context.recorded_diagnostics.items;
    if (diag_index >= records.len) return null;
    return records[@intCast(diag_index)];
}

/// Returns the syntax diagnostic recorded at `diag_index`, or null when the
/// index is out of range or the record is an indentation diagnostic.
fn recordedSyntaxDiagnostic(embedded: *Embedded, diag_index: u64) ?root.SyntaxDiagnostic {
    return switch (recordedDiagnostic(embedded, diag_index) orelse return null) {
        .syntax => |syntax| syntax,
        .indentation => null,
    };
}

/// Writes the rendered diagnostic message (plain text, newline-terminated)
/// into `out`. The string is NUL-terminated and remains valid until the next
/// parse or session destruction. Fails with `galley_error_no_diagnostic`
/// when the previous parse succeeded.
export fn galley_diagnostic_message(session_ptr: ?*GalleySession, out: ?*[*:0]const u8) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out == null) return galley_error_null_argument;
    const diagnostic = embedded.session.runtime_context.lastDiagnostic() orelse return galley_error_no_diagnostic;
    if (embedded.rendered_diagnostic) |cached| {
        out.?.* = cached.ptr;
        return galley_ok;
    }
    // Prefer the message the grammar's error-message hooks rendered during
    // the parse; fall back to the built-in generic renderer.
    var owned: ?[]const u8 = null;
    defer if (owned) |rendered| std.heap.c_allocator.free(rendered);
    const source = embedded.session.runtime_context.last_rendered_message orelse blk: {
        const rendered = root.renderParseDiagnostic(std.heap.c_allocator, diagnostic, .plain) catch return galley_error_out_of_memory;
        owned = rendered;
        break :blk rendered;
    };
    const z = std.heap.c_allocator.dupeZ(u8, source) catch return galley_error_out_of_memory;
    embedded.rendered_diagnostic = z;
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
    const diagnostic = recordedDiagnostic(embedded, diag_index) orelse return galley_error_no_diagnostic;
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
        .indentation => |indentation| {
            out_line.?.* = indentation.line;
            out_column.?.* = indentation.column;
        },
    }
    return galley_ok;
}

/// Writes the 1-based line and column of a diagnostic. Fails with
/// `galley_error_no_diagnostic` when the previous parse succeeded.
export fn galley_diagnostic_position(
    session_ptr: ?*GalleySession,
    out_line: ?*u32,
    out_column: ?*u32,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_line == null or out_column == null) return galley_error_null_argument;
    return writeDiagnosticPosition(embedded.session.runtime_context.lastDiagnostic(), out_line, out_column);
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
    return writeDiagnosticPosition(recordedDiagnostic(embedded, diag_index), out_line, out_column);
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
        .indentation => return galley_error_no_diagnostic,
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
    return writeUnexpectedToken(embedded.session.runtime_context.lastDiagnostic(), out_data, out_len);
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
    return writeUnexpectedToken(recordedDiagnostic(embedded, diag_index), out_data, out_len);
}

/// Renders a status code as a static, NUL-terminated description, or null
/// when the code is unknown. The returned pointer remains valid for the
/// lifetime of the process.
export fn galley_status_string(status: i64) ?[*:0]const u8 {
    return switch (status) {
        galley_ok => "ok",
        galley_error_null_argument => "null argument",
        galley_error_syntax => "syntax error",
        galley_error_indentation => "indentation error",
        galley_error_stack_overflow => "parser stack overflow",
        galley_error_ast_capacity_exceeded => "AST capacity exceeded",
        galley_error_unterminated_raw_string => "unterminated raw string",
        galley_error_out_of_memory => "out of memory",
        galley_error_internal => "internal error",
        galley_error_no_diagnostic => "no diagnostic available",
        galley_error_invalid_node => "invalid node address",
        galley_error_io => "I/O error",
        else => null,
    };
}

/// Returns the number of expected tokens of a syntax diagnostic, or a
/// negative status when the diagnostic is null or not a syntax error.
fn countExpectedTokens(diagnostic: ?root.ParseDiagnostic) i64 {
    switch (diagnostic orelse return galley_error_no_diagnostic) {
        .syntax => |syntax| return @intCast(syntax.expected_tokens.len),
        .indentation => return galley_error_no_diagnostic,
    }
}

/// Returns the number of expected tokens of the current syntax diagnostic,
/// or a negative status when there is no diagnostic or it is not a syntax
/// error.
export fn galley_diagnostic_expected_count(session_ptr: ?*GalleySession) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    return countExpectedTokens(embedded.session.runtime_context.lastDiagnostic());
}

/// Returns the number of expected tokens of the diagnostic recorded at
/// `diag_index`, or a negative status when the index is out of range or the
/// record is not a syntax error.
export fn galley_recorded_expected_count(session_ptr: ?*GalleySession, diag_index: u64) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    return countExpectedTokens(recordedDiagnostic(embedded, diag_index));
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
    const diagnostic = embedded.session.runtime_context.lastDiagnostic() orelse return galley_error_no_diagnostic;
    return writeExpectedToken(diagnostic, index, out_data, out_len);
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
    const diagnostic = recordedDiagnostic(embedded, diag_index) orelse return galley_error_no_diagnostic;
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
        .indentation => return galley_error_no_diagnostic,
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
        .indentation => return galley_error_no_diagnostic,
    }
}

/// Returns the number of variables in the innermost-first "while parsing"
/// context chain of the current syntax diagnostic, or a negative status when
/// there is no diagnostic or it is not a syntax error.
export fn galley_diagnostic_context_count(session_ptr: ?*GalleySession) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    return countContextNames(embedded.session.runtime_context.lastDiagnostic());
}

/// Returns the number of variables in the context chain of the diagnostic
/// recorded at `diag_index`, or a negative status when the index is out of
/// range or the record is not a syntax error.
export fn galley_recorded_context_count(session_ptr: ?*GalleySession, diag_index: u64) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    return countContextNames(recordedDiagnostic(embedded, diag_index));
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
    const diagnostic = embedded.session.runtime_context.lastDiagnostic() orelse return galley_error_no_diagnostic;
    return writeContextName(diagnostic, index, out_data, out_len);
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
    const diagnostic = recordedDiagnostic(embedded, diag_index) orelse return galley_error_no_diagnostic;
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
        .indentation => return galley_error_no_diagnostic,
    }
}

/// Writes the 1-based line and column of a node's first byte in the input of
/// the most recent parse. Scans the retained input, so cost is linear in the
/// offset.
export fn galley_node_line_column(
    session_ptr: ?*GalleySession,
    address: GalleyNodeAddress,
    out_line: ?*u32,
    out_column: ?*u32,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_invalid_node;
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_line == null or out_column == null) return galley_error_null_argument;
    const node = embedded.nodeAt(address) orelse return galley_error_invalid_node;
    if (node.text_start > embedded.last_input.len) return galley_error_internal;

    var line: u32 = 1;
    var column: u32 = 1;
    for (embedded.last_input[0..node.text_start]) |byte| {
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

/// Parses the file at `path`. Returns the number of bytes parsed on success
/// or a negative status code; file access failures report
/// `galley_error_io`.
export fn galley_parse_file(session_ptr: ?*GalleySession, path: ?[*:0]const u8) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    const path_slice = std.mem.sliceTo(path orelse return galley_error_null_argument, 0);
    embedded.clearRenderedDiagnostic();

    var file = std.Io.Dir.cwd().openFile(embedded.threaded.io(), path_slice, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => return galley_error_io,
        error.AccessDenied => return galley_error_io,
        else => return galley_error_io,
    };
    defer file.close(embedded.threaded.io());

    const result = embedded.session.parseFile(file, path_slice) catch |err| return statusForError(err);
    embedded.last_input = embedded.session.owned_input orelse &.{};
    return finishParse(embedded, result);
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
    const result = embedded.last_result orelse return galley_error_no_diagnostic;
    out_line.?.* = result.line;
    out_column.?.* = result.column;
    return galley_ok;
}

/// Writes the rendered diagnostic message with ANSI color escapes into
/// `out`. Lifetime matches `galley_diagnostic_message`.
export fn galley_diagnostic_message_ansi(session_ptr: ?*GalleySession, out: ?*[*:0]const u8) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out == null) return galley_error_null_argument;
    const diagnostic = embedded.session.runtime_context.lastDiagnostic() orelse return galley_error_no_diagnostic;
    const rendered = root.renderParseDiagnostic(std.heap.c_allocator, diagnostic, .ansi) catch return galley_error_out_of_memory;
    const z = std.heap.c_allocator.dupeZ(u8, rendered) catch {
        std.heap.c_allocator.free(rendered);
        return galley_error_out_of_memory;
    };
    std.heap.c_allocator.free(rendered);
    embedded.clearRenderedDiagnostic();
    embedded.rendered_ansi_diagnostic = z;
    out.?.* = z.ptr;
    return galley_ok;
}

/// Writes the byte offset and length of a node's matched source span into
/// `out_start`/`out_len`. Offsets index the input of the most recent parse.
export fn galley_node_span(
    session_ptr: ?*GalleySession,
    address: GalleyNodeAddress,
    out_start: ?*u64,
    out_len: ?*u64,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_invalid_node;
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_start == null or out_len == null) return galley_error_null_argument;
    const node = embedded.nodeAt(address) orelse return galley_error_invalid_node;
    out_start.?.* = node.text_start;
    out_len.?.* = node.text_length;
    return galley_ok;
}

/// Returns the last child address, or `GALLEY_INVALID_NODE`.
export fn galley_node_last_child(session_ptr: ?*GalleySession, address: GalleyNodeAddress) GalleyNodeAddress {
    if (comptime !parser.is_ast_enabled) return galley_invalid_node;
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_invalid_node));
    const node = embedded.nodeAt(address) orelse return galley_invalid_node;
    if (node.last_child == root.data_structures.Node.invalid_pointer) return galley_invalid_node;
    return @intCast(node.last_child);
}

/// Returns the previous sibling address, or `GALLEY_INVALID_NODE`.
export fn galley_node_prior_sibling(session_ptr: ?*GalleySession, address: GalleyNodeAddress) GalleyNodeAddress {
    if (comptime !parser.is_ast_enabled) return galley_invalid_node;
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_invalid_node));
    const node = embedded.nodeAt(address) orelse return galley_invalid_node;
    if (node.prior == root.data_structures.Node.invalid_pointer) return galley_invalid_node;
    return @intCast(node.prior);
}

// ---------------------------------------------------------------------------
// Tree editing. Chains passed to these functions must be detached orphans
// (no parent, no prior). Addresses are stable, so edits never invalidate
// other node addresses.
// ---------------------------------------------------------------------------

fn mutableAllocator(session_ptr: ?*GalleySession) ?struct { embedded: *Embedded, allocator: *root.data_structures.ASTAllocator } {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return null));
    if (comptime !parser.is_ast_enabled) return null;
    return .{ .embedded = embedded, .allocator = &embedded.session.node_allocator };
}

/// Appends `first_node` (and any chain attached via its next links) as the
/// last children of `parent`.
export fn galley_tree_append_children(
    session_ptr: ?*GalleySession,
    parent: GalleyNodeAddress,
    first_node: GalleyNodeAddress,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    const ctx = mutableAllocator(session_ptr) orelse return galley_error_internal;
    _ = ctx.embedded.nodeAt(parent) orelse return galley_error_invalid_node;
    _ = ctx.embedded.nodeAt(first_node) orelse return galley_error_invalid_node;
    root.data_structures.Node.appendChildren(parent, ctx.allocator, first_node) catch |err| switch (err) {
        error.IndexOutOfBounds => return galley_error_invalid_node,
        else => return galley_error_internal,
    };
    return galley_ok;
}

/// Inserts `first_node` (and its chain) immediately before `target` among
/// its siblings.
export fn galley_tree_insert_before(
    session_ptr: ?*GalleySession,
    target: GalleyNodeAddress,
    first_node: GalleyNodeAddress,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    const ctx = mutableAllocator(session_ptr) orelse return galley_error_internal;
    _ = ctx.embedded.nodeAt(target) orelse return galley_error_invalid_node;
    _ = ctx.embedded.nodeAt(first_node) orelse return galley_error_invalid_node;
    root.data_structures.Node.insertBefore(target, ctx.allocator, first_node) catch |err| switch (err) {
        error.IndexOutOfBounds => return galley_error_invalid_node,
        else => return galley_error_internal,
    };
    return galley_ok;
}

/// Inserts `first_node` (and its chain) immediately after `target` among its
/// siblings.
export fn galley_tree_insert_after(
    session_ptr: ?*GalleySession,
    target: GalleyNodeAddress,
    first_node: GalleyNodeAddress,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    const ctx = mutableAllocator(session_ptr) orelse return galley_error_internal;
    _ = ctx.embedded.nodeAt(target) orelse return galley_error_invalid_node;
    _ = ctx.embedded.nodeAt(first_node) orelse return galley_error_invalid_node;
    root.data_structures.Node.insertAfter(target, ctx.allocator, first_node) catch |err| switch (err) {
        error.IndexOutOfBounds => return galley_error_invalid_node,
        else => return galley_error_internal,
    };
    return galley_ok;
}

/// Removes `count` consecutive siblings starting at `node`, detaching them
/// from parent and sibling chains. Writes the address of the first removed
/// node to `out_head`; the removed nodes remain allocated and readable but
/// are orphaned.
export fn galley_tree_remove_siblings(
    session_ptr: ?*GalleySession,
    node: GalleyNodeAddress,
    count: usize,
    out_head: ?*GalleyNodeAddress,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    const ctx = mutableAllocator(session_ptr) orelse return galley_error_internal;
    if (out_head == null) return galley_error_null_argument;
    _ = ctx.embedded.nodeAt(node) orelse return galley_error_invalid_node;
    const head = root.data_structures.Node.remove(node, ctx.allocator, count) catch |err| switch (err) {
        error.CountExceedsRemainingSiblings => return galley_error_invalid_node,
    };
    out_head.?.* = head;
    return galley_ok;
}

/// Detaches `node` itself from its parent and siblings.
export fn galley_tree_remove_self(
    session_ptr: ?*GalleySession,
    node: GalleyNodeAddress,
    out_head: ?*GalleyNodeAddress,
) i64 {
    return galley_tree_remove_siblings(session_ptr, node, 1, out_head);
}

/// Splices the children of `wrapper` in place of the wrapper among its
/// siblings, writing the promoted chain head to `out_head`. The wrapper is
/// left detached with no children.
export fn galley_tree_promote_children_over_wrapper(
    session_ptr: ?*GalleySession,
    wrapper: GalleyNodeAddress,
    out_head: ?*GalleyNodeAddress,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    const ctx = mutableAllocator(session_ptr) orelse return galley_error_internal;
    _ = ctx.embedded.nodeAt(wrapper) orelse return galley_error_invalid_node;
    const head = root.data_structures.Node.promoteChildrenOverWrapper(wrapper, ctx.allocator) orelse {
        out_head.?.* = galley_invalid_node;
        return galley_ok;
    };
    out_head.?.* = head;
    return galley_ok;
}

/// Detaches all children of `node`, writing the detached chain head to
/// `out_head`. Returns `galley_error_no_diagnostic` when the node has no
/// children.
export fn galley_tree_clean_children(
    session_ptr: ?*GalleySession,
    node: GalleyNodeAddress,
    out_head: ?*GalleyNodeAddress,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    const ctx = mutableAllocator(session_ptr) orelse return galley_error_internal;
    _ = ctx.embedded.nodeAt(node) orelse return galley_error_invalid_node;
    const head = root.data_structures.Node.cleanChildren(node, ctx.allocator) catch |err| switch (err) {
        error.IndexOutOfBounds => return galley_error_invalid_node,
    };
    if (head == root.data_structures.Node.invalid_pointer) {
        out_head.?.* = galley_invalid_node;
        return galley_ok;
    }
    out_head.?.* = head;
    return galley_ok;
}

// ---------------------------------------------------------------------------
// Diagnostic classification and multi-error state.
// ---------------------------------------------------------------------------

/// Returns the kind of a diagnostic, or `galley_diagnostic_kind_none` when
/// the diagnostic is null.
fn diagnosticKindValue(diagnostic: ?root.ParseDiagnostic) i64 {
    switch (diagnostic orelse return galley_diagnostic_kind_none) {
        .syntax => return galley_diagnostic_kind_syntax,
        .indentation => return galley_diagnostic_kind_indentation,
    }
}

/// Returns the kind of the current diagnostic: `galley_diagnostic_kind_none`,
/// `galley_diagnostic_kind_syntax`, or `galley_diagnostic_kind_indentation`.
export fn galley_diagnostic_kind(session_ptr: ?*GalleySession) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_diagnostic_kind_none));
    return diagnosticKindValue(embedded.session.runtime_context.lastDiagnostic());
}

/// Returns the kind of the diagnostic recorded at `diag_index`, or
/// `galley_diagnostic_kind_none` when the index is out of range.
export fn galley_recorded_diagnostic_kind(session_ptr: ?*GalleySession, diag_index: u64) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_diagnostic_kind_none));
    return diagnosticKindValue(recordedDiagnostic(embedded, diag_index));
}

/// Returns how many syntax errors the most recent recovery-enabled parse
/// recorded. Fail-fast parses report at most one.
export fn galley_syntax_error_count(session_ptr: ?*GalleySession) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return 0));
    return @intCast(embedded.session.runtime_context.syntax_error_count);
}

/// Returns how many diagnostics the most recent parse retained, in recording
/// order. Valid until the next parse begins.
export fn galley_recorded_diagnostic_count(session_ptr: ?*GalleySession) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return 0));
    return @intCast(embedded.session.runtime_context.recorded_diagnostics.items.len);
}

fn currentSyntaxDiagnostic(embedded: *Embedded) ?root.SyntaxDiagnostic {
    return switch (embedded.session.runtime_context.lastDiagnostic() orelse return null) {
        .syntax => |syntax| syntax,
        .indentation => null,
    };
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
        .syntax => return galley_error_no_diagnostic,
    }
}

export fn galley_diagnostic_indentation(
    session_ptr: ?*GalleySession,
    out_spaces: ?*u32,
    out_indentation_width: ?*u32,
) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out_spaces == null or out_indentation_width == null) return galley_error_null_argument;
    return writeIndentationFields(embedded.session.runtime_context.lastDiagnostic(), out_spaces, out_indentation_width);
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
    return writeIndentationFields(recordedDiagnostic(embedded, diag_index), out_spaces, out_indentation_width);
}

// ---------------------------------------------------------------------------
// Recovery information of a syntax diagnostic. Each field is exposed for
// the current diagnostic and, with a leading `diag_index`, for any
// diagnostic recorded during the most recent parse.
// ---------------------------------------------------------------------------

fn recordedRecovery(
    embedded: *Embedded,
    diag_index: u64,
) ?root.SyntaxRecovery {
    const syntax = recordedSyntaxDiagnostic(embedded, diag_index) orelse return null;
    return syntax.recovery;
}

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
    return recoveryKindValue(currentSyntaxDiagnostic(embedded));
}

/// Returns the recovery target kind of the diagnostic recorded at
/// `diag_index`.
export fn galley_recorded_diagnostic_recovery_kind(session_ptr: ?*GalleySession, diag_index: u64) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_recovery_target_none));
    return recoveryKindValue(recordedSyntaxDiagnostic(embedded, diag_index));
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
    return writeRecoveryTerminal(currentSyntaxDiagnostic(embedded), out_data, out_len);
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
    return writeRecoveryTerminal(recordedSyntaxDiagnostic(embedded, diag_index), out_data, out_len);
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
    return writeRecoveryResume(currentSyntaxDiagnostic(embedded), out);
}

/// Writes the resume side of the recovery of the diagnostic recorded at
/// `diag_index`.
export fn galley_recorded_recovery_resume(session_ptr: ?*GalleySession, diag_index: u64, out: ?*i64) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (out == null) return galley_error_null_argument;
    return writeRecoveryResume(recordedSyntaxDiagnostic(embedded, diag_index), out);
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
    return writeRecoveryLhsVariable(currentSyntaxDiagnostic(embedded), out_data, out_len);
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
    return writeRecoveryLhsVariable(recordedSyntaxDiagnostic(embedded, diag_index), out_data, out_len);
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
    return writeRecoveryProduction(currentSyntaxDiagnostic(embedded), out_variable, out_variable_len, out_rhs_index);
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
    return writeRecoveryProduction(recordedSyntaxDiagnostic(embedded, diag_index), out_variable, out_variable_len, out_rhs_index);
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
    return writeRecoveryOccurrence(currentSyntaxDiagnostic(embedded), out_parent_variable, out_parent_variable_len, out_rhs_index, out_symbol_index, out_variable, out_variable_len);
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
    return writeRecoveryOccurrence(recordedSyntaxDiagnostic(embedded, diag_index), out_parent_variable, out_parent_variable_len, out_rhs_index, out_symbol_index, out_variable, out_variable_len);
}

// ---------------------------------------------------------------------------
// Node and storage extras.
// ---------------------------------------------------------------------------

/// Returns the raw variable index of a node into the parser's variable list
/// (see `galley_variable_name`), or -1 when the node has no variable (for
/// example a terminal-only node) or the address is invalid.
export fn galley_node_variable_index(session_ptr: ?*GalleySession, address: GalleyNodeAddress) i64 {
    if (comptime !parser.is_ast_enabled) return -1;
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return -1));
    const node = embedded.nodeAt(address) orelse return -1;
    if (node.variable == root.data_structures.Node.invalid_variable) return -1;
    return @intCast(node.variable);
}

/// Inserts `first_node` (and its chain) into the children of `parent` at
/// `index`. An index equal to the child count appends.
export fn galley_tree_insert_children_at(
    session_ptr: ?*GalleySession,
    parent: GalleyNodeAddress,
    index: usize,
    first_node: GalleyNodeAddress,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    const ctx = mutableAllocator(session_ptr) orelse return galley_error_internal;
    _ = ctx.embedded.nodeAt(parent) orelse return galley_error_invalid_node;
    _ = ctx.embedded.nodeAt(first_node) orelse return galley_error_invalid_node;
    root.data_structures.Node.insertChildren(parent, ctx.allocator, index, first_node) catch |err| switch (err) {
        error.IndexOutOfBounds => return galley_error_invalid_node,
    };
    return galley_ok;
}

/// Removes `count` consecutive children of `parent` starting at child
/// `index`, writing the detached chain head to `out_head`.
export fn galley_tree_remove_children_at(
    session_ptr: ?*GalleySession,
    parent: GalleyNodeAddress,
    index: usize,
    count: usize,
    out_head: ?*GalleyNodeAddress,
) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    const ctx = mutableAllocator(session_ptr) orelse return galley_error_internal;
    if (out_head == null) return galley_error_null_argument;
    _ = ctx.embedded.nodeAt(parent) orelse return galley_error_invalid_node;
    const head = root.data_structures.Node.removeChildren(parent, ctx.allocator, index, count) catch |err| switch (err) {
        error.IndexOutOfBounds => return galley_error_invalid_node,
        error.CountExceedsRemainingSiblings => return galley_error_invalid_node,
    };
    if (head == root.data_structures.Node.invalid_pointer) {
        out_head.?.* = galley_invalid_node;
        return galley_ok;
    }
    out_head.?.* = head;
    return galley_ok;
}

/// Detaches `wrapper` from its parent and sibling chains without touching
/// its children.
export fn galley_tree_unlink_wrapper(session_ptr: ?*GalleySession, wrapper: GalleyNodeAddress) i64 {
    if (comptime !parser.is_ast_enabled) return galley_error_internal;
    const ctx = mutableAllocator(session_ptr) orelse return galley_error_internal;
    _ = ctx.embedded.nodeAt(wrapper) orelse return galley_error_invalid_node;
    root.data_structures.Node.unlinkWrapper(wrapper, ctx.allocator);
    return galley_ok;
}

/// Preallocates node storage for at least `capacity` nodes, avoiding
/// growth during subsequent parses. Fails with
/// `galley_error_ast_capacity_exceeded` when the request exceeds the
/// build's node limit.
export fn galley_reserve_nodes(session_ptr: ?*GalleySession, capacity: u64) i64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return galley_error_null_argument));
    if (comptime !parser.is_ast_enabled) return galley_ok;
    embedded.session.node_allocator.ensureCapacity(@intCast(capacity)) catch |err| switch (err) {
        error.OutOfMemory => return galley_error_out_of_memory,
        error.ASTCapacityTooLarge => return galley_error_ast_capacity_exceeded,
    };
    return galley_ok;
}

/// Returns the current node storage capacity in nodes.
export fn galley_node_capacity(session_ptr: ?*GalleySession) u64 {
    const embedded: *Embedded = @ptrCast(@alignCast(session_ptr orelse return 0));
    if (comptime !parser.is_ast_enabled) return 0;
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
