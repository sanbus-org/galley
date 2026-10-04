const builtin = @import("builtin");
const std = @import("std");
const runtime_options = @import("runtime_options");
const SessionLock = @import("session-lock.zig");

pub const procedures = @import("procedures");
pub const config = @import("config");
pub const error_messages = @import("error_messages");
pub const parser = @import("parser");
pub const ast_memory_benchmark_enabled = @hasDecl(runtime_options, "ast_memory_benchmark") and runtime_options.ast_memory_benchmark;
pub const syntax_error_stack_depth_build_override = if (@hasDecl(runtime_options, "syntax_error_stack_depth") and
    runtime_options.syntax_error_stack_depth > 0)
    runtime_options.syntax_error_stack_depth
else
    0;
pub const syntax_error_stack_depth: usize = if (syntax_error_stack_depth_build_override > 0)
    syntax_error_stack_depth_build_override
else if (builtin.mode == .Debug) 5 else 1;
pub const position_tracking_enabled = if (@hasDecl(parser, "is_position_tracking_enabled"))
    parser.is_position_tracking_enabled
else
    builtin.mode != .ReleaseFast;
pub const input_streaming_enabled = if (@hasDecl(parser, "is_input_streaming_enabled"))
    parser.is_input_streaming_enabled
else
    false;
pub const procedures_enabled = if (@hasDecl(parser, "are_procedures_enabled")) parser.are_procedures_enabled else true;
pub const uses_verbatim = if (@hasDecl(parser, "uses_verbatim")) parser.uses_verbatim else false;
pub const source_retention_enabled = parser.is_ast_enabled or procedures_enabled or uses_verbatim;
pub const sliding_input_enabled = input_streaming_enabled and !source_retention_enabled;
pub const string_utilities = @import("string.zig");
pub const stack_overflow_utilities = @import("stack-overflow.zig");
pub const data_structures = @import("data-structures/data-structures.zig");
pub const standard_procedures = @import("standard-procedures.zig");
pub const read_chunk_size = 64 * 1024;
pub const input_padding_size = @max(parser.longest_terminal_length, 1);
pub const input_window_size = read_chunk_size;
pub const stack_overflow_recovery_available = stack_overflow_utilities.is_supported;

/// Minimum ready node storage per parse when the caller leaves
/// `ParseOptions.ast_preallocation_cap` at its default. Single source for
/// the session floor (`ParseOptions`) and the allocator's first-use
/// reservation (`data-structures/node.zig`).
pub const default_ast_preallocation_floor: usize = 16_384;

pub const ParseError = error{
    SyntaxError,
    SemanticError,
    IndentationError,
    StackOverflow,
    ASTCapacityExceeded,
    UnterminatedRawString,
};

/// Named contention set for session access. Parse failures arrive through
/// `ParseError` (or generated-parser errors); session misuse and pre-lock
/// parse rejections arrive here. The two channels are distinct:
/// `SessionError` is never a parse failure. `SessionInUse` and
/// `NestedParseDuringStackOverflowRecovery` both run before the lock and
/// consume no session state.
pub const SessionError = error{
    SessionInUse,
    SessionGenerationExhausted,
    StaleParseResult,
    /// No parse on this session has succeeded yet, so there is no published
    /// result to address (`readCurrent`, `editCurrent`).
    NoParseResult,
    /// A parse without stack-overflow recovery attempted while another
    /// parse's recovery scope is active on this thread. An inner fault
    /// would land in the outer scope, skipping this session's cleanup, so
    /// the inner parse must opt into recovery too.
    NestedParseDuringStackOverflowRecovery,
};

pub const SyntaxDiagnosticContext = union(enum) {
    none,
    /// Innermost-first sequence of the variables being parsed at the error.
    while_parsing: []const []const u8,
    state: usize,
};

pub const SyntaxRecoveryResume = enum {
    before,
    after,
};

pub const SyntaxRecoveryTarget = union(enum) {
    lhs_variable: []const u8,
    production: struct {
        variable: []const u8,
        rhs_index: usize,
    },
    occurrence: struct {
        parent_variable: []const u8,
        rhs_index: usize,
        symbol_index: usize,
        variable: []const u8,
    },
};

pub const SyntaxRecovery = struct {
    target: SyntaxRecoveryTarget,
    terminal: []const u8,
    @"resume": SyntaxRecoveryResume,
};

pub const SyntaxRecoveryPoint = struct {
    terminal: []const u8,
    @"resume": SyntaxRecoveryResume,
};

pub const SyntaxDiagnostic = struct {
    line: u32,
    column: u32,
    unexpected_token: []const u8,
    expected_tokens: []const []const u8,
    context: SyntaxDiagnosticContext = .none,
    recovery: ?SyntaxRecovery = null,
};

pub const IndentationDiagnostic = struct {
    line: u32,
    column: u32,
    spaces: u16,
    indentation_width: u16,
};

pub const SemanticDiagnostic = struct {
    line: u32,
    column: u32,
    variable: []const u8,
    message: []const u8,
    text_start: usize = 0,
    text_length: usize = 0,
};

pub const ParseDiagnostic = union(enum) {
    syntax: SyntaxDiagnostic,
    semantic: SemanticDiagnostic,
    indentation: IndentationDiagnostic,
};

pub const DiagnosticStyle = enum {
    plain,
    ansi,
};

pub const SyntaxErrorMessageReporter = *const fn (message: []const u8) void;

/// One message override: when a syntax error's innermost in-progress
/// variable equals `name`, or when `name` is `"*"` and no variable entry
/// matched, the recorded message replaces hooks and the built-in renderer
/// (placeholders expanded against the diagnostic).
pub const MessageOverride = struct {
    name: []const u8,
    message: []const u8,
};

pub const ParseOptions = struct {
    input_path: ?[]const u8 = null,
    verbosity: usize = 0,
    max_errors: usize = 10,
    recovery_window: usize = 500,
    stack_overflow_recovery: bool = false,
    /// Ready node storage as a multiple of input length. On reserved-arena
    /// platforms this reserves address space without committed pages, so a
    /// large estimate is cheap; on segment platforms (Windows, wasm) the
    /// scaled contribution is ignored and only the floor below is prepared
    /// eagerly, with demand past it appending segments mid-parse.
    ast_preallocation_ratio: f64 = 2,
    /// Minimum ready node storage per parse. The reservation covers input
    /// length times the ratio above this floor on reserved-arena platforms;
    /// on segment platforms the floor alone is prepared eagerly. Demand past
    /// the reservation appends segments, so raise the floor through
    /// `ParseOptions.ast_preallocation_cap` (the ratio applies to the
    /// reserved-arena path only) to avoid that slower path for node-dense
    /// grammars.
    ast_preallocation_cap: usize = default_ast_preallocation_floor,
    /// Number of in-progress variables (innermost first) reported in LL syntax
    /// error messages. `0` inherits the generated parser's default
    /// (`syntax_error_stack_depth`); a value above 1 enables the stack. A value
    /// below the parser's compile-time depth never adds instrumentation, so in
    /// release builds the stack stays off unless the build was compiled with
    /// `-Dsyntax-error-stack-depth` above 1.
    syntax_error_stack_depth: usize = 0,
    syntax_error_reporter: ?SyntaxErrorMessageReporter = null,
    /// Message overrides copied into the session at creation. Entries are
    /// matched against syntax-error site names in the same fallback order
    /// the sites use (exact hook name, then family, then general), and take
    /// priority over both grammar hooks and the built-in renderer.
    message_overrides: []const MessageOverride = &.{},
};

pub const SyntaxErrorMessageArgs = struct {
    allocator: std.mem.Allocator,
    context: *data_structures.Context,
    diagnostic: ParseDiagnostic,
    style: DiagnosticStyle,
};

/// Full syntax-message resolution shared by every generated diagnostic site.
/// Chain order: session overrides and `config.zig` `error_messages` entries
/// (via the runtime's template resolver), then each named hook declaration
/// in `hooks_module`, then null — callers append their builtin fallback
/// expression. Hook failures fall through to the next source, matching the
/// historical per-site behavior.
pub fn resolveSyntaxErrorMessage(
    context: *data_structures.Context,
    diagnostic: ParseDiagnostic,
    comptime config_messages: anytype,
    comptime hooks_module: anytype,
    comptime hook_names: anytype,
) ?[]const u8 {
    const runtime_context = context.runtime();
    if (runtime_context.resolveMessageOverride(diagnostic, config_messages)) |message| return message;
    inline for (hook_names) |hook_name| {
        if (@hasDecl(hooks_module, hook_name)) {
            if (@field(hooks_module, hook_name)(.{
                .allocator = runtime_context.arena_allocator,
                .context = context,
                .diagnostic = diagnostic,
                .style = .plain,
            })) |rendered| {
                return rendered;
            } else |_| {}
        }
    }
    return null;
}

pub const ParseResult = struct {
    parsed_bytes: usize,
    line: if (position_tracking_enabled) u32 else void,
    column: if (position_tracking_enabled) u32 else void,
    ast_root: ?data_structures.Node.Pointer = null,
    semantic_root: if (procedures_enabled) ?data_structures.Payload else void = if (procedures_enabled) null else {},
    _session_generation: usize = 0,
    _session_identity: ?*const anyopaque = null,
};

/// One implementation behind both guards' diagnostics accessors. The two
/// guard types differ only in which capabilities they expose: `read` also
/// hands out node storage, `readLatest` does not.
fn guardLastDiagnostic(session: *const Session) ?ParseDiagnostic {
    return session.runtime_context.lastDiagnostic();
}

fn guardLastRenderedMessage(session: *const Session) ?[]const u8 {
    return session.runtime_context.last_rendered_message;
}

fn guardRecordedDiagnostics(session: *const Session) []const ParseDiagnostic {
    return session.runtime_context.recorded_diagnostics.items;
}

fn guardSyntaxErrorCount(session: *const Session) usize {
    return session.runtime_context.syntax_error_count;
}

fn guardSemanticErrorCount(session: *const Session) usize {
    return session.runtime_context.semantic_error_count;
}

pub const SessionReadGuard = struct {
    session: *Session,
    /// The validated result this guard is for: the caller's result in
    /// `read`, the session's published result in `readCurrent`.
    result: ParseResult,

    pub fn deinit(self: *SessionReadGuard) void {
        self.session.releaseSharedGuard();
        self.* = undefined;
    }

    /// The parse generation this guard's result belongs to: the generation
    /// the parse stamped on its context while it ran.
    pub fn generation(self: *const SessionReadGuard) usize {
        return self.result._session_generation;
    }

    pub fn astAllocator(self: *const SessionReadGuard) if (parser.is_ast_enabled) *const data_structures.ASTAllocator else void {
        if (parser.is_ast_enabled) {
            return &self.session.node_allocator;
        }
        return {};
    }

    pub fn lastDiagnostic(self: *const SessionReadGuard) ?ParseDiagnostic {
        return guardLastDiagnostic(self.session);
    }

    pub fn lastRenderedMessage(self: *const SessionReadGuard) ?[]const u8 {
        return guardLastRenderedMessage(self.session);
    }

    pub fn recordedDiagnostics(self: *const SessionReadGuard) []const ParseDiagnostic {
        return guardRecordedDiagnostics(self.session);
    }

    pub fn syntaxErrorCount(self: *const SessionReadGuard) usize {
        return guardSyntaxErrorCount(self.session);
    }

    pub fn semanticErrorCount(self: *const SessionReadGuard) usize {
        return guardSemanticErrorCount(self.session);
    }
};

/// Diagnostics-only guard returned by `readLatest`. Its accessors expose
/// no node storage, so post-failure reads cannot touch a half-built tree
/// through this guard. (Zig has no field privacy: `guard.session` remains
/// reachable, so this is a capability-narrowing convention enforced by the
/// accessors, not a compiler barrier.)
pub const SessionDiagnosticsGuard = struct {
    session: *Session,

    pub fn deinit(self: *SessionDiagnosticsGuard) void {
        self.session.releaseSharedGuard();
        self.* = undefined;
    }

    pub fn lastDiagnostic(self: *const SessionDiagnosticsGuard) ?ParseDiagnostic {
        return guardLastDiagnostic(self.session);
    }

    pub fn lastRenderedMessage(self: *const SessionDiagnosticsGuard) ?[]const u8 {
        return guardLastRenderedMessage(self.session);
    }

    pub fn recordedDiagnostics(self: *const SessionDiagnosticsGuard) []const ParseDiagnostic {
        return guardRecordedDiagnostics(self.session);
    }

    pub fn syntaxErrorCount(self: *const SessionDiagnosticsGuard) usize {
        return guardSyntaxErrorCount(self.session);
    }

    pub fn semanticErrorCount(self: *const SessionDiagnosticsGuard) usize {
        return guardSemanticErrorCount(self.session);
    }
};

/// Exclusive guard returned by `edit`, `editResult`, and `editCurrent`. Its
/// accessors expose only what mutation sites need: node storage for
/// reservations and edits, and the last diagnostic for cache refills. (As
/// with the read guards, narrowing is an accessor convention, not a
/// compiler barrier.)
pub const SessionEditGuard = struct {
    session: *Session,

    pub fn deinit(self: *SessionEditGuard) void {
        self.session.releaseEditGuard();
        self.* = undefined;
    }

    /// The parse generation of the session's live tree, the same source the
    /// read guard reports once its result is validated against it.
    pub fn generation(self: *const SessionEditGuard) usize {
        return self.session.generation;
    }

    /// Mutable node storage: only an exclusive guard reaches it, so
    /// capacity changes and tree edits cannot race readers.
    pub fn mutableAstAllocator(self: *SessionEditGuard) if (parser.is_ast_enabled) *data_structures.ASTAllocator else void {
        if (parser.is_ast_enabled) {
            return &self.session.node_allocator;
        }
        return {};
    }

    pub fn lastDiagnostic(self: *const SessionEditGuard) ?ParseDiagnostic {
        return guardLastDiagnostic(self.session);
    }

    pub fn lastRenderedMessage(self: *const SessionEditGuard) ?[]const u8 {
        return guardLastRenderedMessage(self.session);
    }
};

pub const ParsedInput = struct {
    session: Session,
    result: ParseResult,

    pub fn deinit(self: *ParsedInput) void {
        self.session.deinit();
    }
};

comptime {
    if (builtin.is_test and @hasDecl(runtime_options, "include_tests") and runtime_options.include_tests) {
        _ = @import("runtime_test.zig");
        _ = stack_overflow_utilities;
    }
}

pub fn parseBytes(io: std.Io, allocator: std.mem.Allocator, input: []const u8, options: ParseOptions) !ParsedInput {
    var session = try Session.init(io, allocator, options);
    errdefer session.deinit();
    const result = try session.parseBytes(input, options.input_path);
    return .{
        .session = session,
        .result = result,
    };
}

pub fn parseSentinelBytes(io: std.Io, allocator: std.mem.Allocator, input: [:0]const u8, options: ParseOptions) !ParsedInput {
    var session = try Session.init(io, allocator, options);
    errdefer session.deinit();
    const result = try session.parseSentinelBytes(input, options.input_path);
    return .{
        .session = session,
        .result = result,
    };
}

fn writeExpectedTokens(writer: *std.Io.Writer, expected_tokens: []const []const u8) !void {
    for (expected_tokens, 0..) |expected_token, index| {
        if (index != 0) try writer.writeAll("', '");
        try writer.print("{f}", .{string_utilities.fmtToken(expected_token)});
    }
}

fn writeRecoveryTarget(writer: *std.Io.Writer, target: SyntaxRecoveryTarget) !void {
    switch (target) {
        .lhs_variable => |variable| try writer.print("LHS variable {f}", .{string_utilities.fmtString(variable)}),
        .production => |production| try writer.print("production {f}[{d}]", .{
            string_utilities.fmtString(production.variable),
            production.rhs_index,
        }),
        .occurrence => |occurrence| try writer.print("occurrence {f} at {f}[{d}].{d}", .{
            string_utilities.fmtString(occurrence.variable),
            string_utilities.fmtString(occurrence.parent_variable),
            occurrence.rhs_index,
            occurrence.symbol_index,
        }),
    }
}

pub fn formatSyntaxRecovery(writer: *std.Io.Writer, recovery: SyntaxRecovery) !void {
    try writer.writeAll("Recovery: ");
    try writeRecoveryTarget(writer, recovery.target);
    try writer.print(" resumed {s} \"{f}\".\n", .{
        @tagName(recovery.@"resume"),
        string_utilities.fmtToken(recovery.terminal),
    });
}

pub fn formatParseDiagnostic(writer: *std.Io.Writer, diagnostic: ParseDiagnostic, style: DiagnosticStyle) !void {
    switch (diagnostic) {
        .syntax => |syntax| {
            switch (style) {
                .plain => {
                    try writer.print(
                        \\SyntaxError at {d}:{d}:
                        \\Unexpected token "{f}"
                    , .{
                        syntax.line,
                        syntax.column,
                        string_utilities.fmtToken(syntax.unexpected_token),
                    });
                    switch (syntax.context) {
                        .none, .state => {},
                        .while_parsing => |names| {
                            try writer.writeAll(" while parsing ");
                            for (names, 0..) |name, index| {
                                if (index != 0) try writer.writeAll(" <~ ");
                                try writer.print("{f}", .{string_utilities.fmtString(name)});
                            }
                        },
                    }
                    try writer.writeAll(".\nExpected tokens: '");
                    try writeExpectedTokens(writer, syntax.expected_tokens);
                    try writer.writeAll("'\n");
                    if (syntax.recovery) |recovery| try formatSyntaxRecovery(writer, recovery);
                },
                .ansi => {
                    try writer.print(
                        "\x1b[35mSyntaxError at {d}:{d}:\n" ++
                            "\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m",
                        .{
                            syntax.line,
                            syntax.column,
                            string_utilities.fmtToken(syntax.unexpected_token),
                        },
                    );
                    switch (syntax.context) {
                        .none => try writer.writeAll("."),
                        .while_parsing => |names| {
                            try writer.writeAll(" while parsing ");
                            for (names, 0..) |name, index| {
                                if (index != 0) try writer.writeAll(" <~ ");
                                try writer.writeAll("\x1b[34m");
                                try writer.print("{f}", .{string_utilities.fmtString(name)});
                                try writer.writeAll("\x1b[0m");
                            }
                            try writer.writeAll(".");
                        },
                        .state => |state| try writer.print(" in state {d}.", .{state}),
                    }
                    try writer.writeAll("\nExpected tokens: \x1b[32m'");
                    try writeExpectedTokens(writer, syntax.expected_tokens);
                    try writer.writeAll("'\x1b[0m\n");
                    if (syntax.recovery) |recovery| try formatSyntaxRecovery(writer, recovery);
                },
            }
        },
        .indentation => |indentation| switch (style) {
            .plain => try writer.print(
                \\IndentationError at {d}:{d}:
                \\Invalid indentation: {d} spaces are not divisible by the detected indentation width of {d}.
                \\
            , .{
                indentation.line,
                indentation.column,
                indentation.spaces,
                indentation.indentation_width,
            }),
            .ansi => try writer.print(
                "\x1b[35mIndentationError at {d}:{d}:\n" ++
                    "\x1b[37mInvalid indentation: \x1b[31m{d}\x1b[37m spaces are not divisible by " ++
                    "the detected indentation width of \x1b[31m{d}\x1b[37m.\x1b[0m\n",
                .{
                    indentation.line,
                    indentation.column,
                    indentation.spaces,
                    indentation.indentation_width,
                },
            ),
        },
        .semantic => |semantic| switch (style) {
            .plain => try writer.print(
                \\SemanticError at {d}:{d}:
                \\{s} while parsing {f}.
                \\
            , .{
                semantic.line,
                semantic.column,
                semantic.message,
                string_utilities.fmtString(semantic.variable),
            }),
            .ansi => try writer.print(
                "\x1b[35mSemanticError at {d}:{d}:\n" ++
                    "\x1b[37m{s}\x1b[37m while parsing \x1b[34m{f}\x1b[0m.\n",
                .{
                    semantic.line,
                    semantic.column,
                    semantic.message,
                    string_utilities.fmtString(semantic.variable),
                },
            ),
        },
    }
}

pub fn renderParseDiagnostic(allocator: std.mem.Allocator, diagnostic: ParseDiagnostic, style: DiagnosticStyle) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    try formatParseDiagnostic(&output.writer, diagnostic, style);
    return output.toOwnedSlice();
}

/// The errors a parse reports after publishing its tree: the parse ran to its
/// end and its result carries recorded errors.
pub const ParseFailure = error{ SyntaxError, SemanticError };

/// The parse lease: the exclusive door held from parse acquisition until
/// the caller has finished whatever must land together with the result.
/// Every leased parse entry funnels through `Session.acquireParse`, which
/// stamps the generation, and the session publishes the result itself
/// (`Session.published_result`) inside that same exclusive hold. A host that
/// pairs the result with state of its own — the C ABI retains the parsed
/// input — writes that state before `deinit`, so no reader observes the
/// pair mid-swap and an older parse can never publish over a newer one.
/// A parse that fails after publishing (`failure`) hands back its lease like
/// a success, so that state is paired with the published failure too; a
/// parse that publishes nothing returns its error instead and holds no lease.
/// The caller must `deinit` the lease exactly once.
pub const ParseLease = struct {
    session: *Session,
    result: ParseResult,
    /// Set when the parse published its tree and still failed: syntax
    /// errors the parser recovered from take precedence over semantic ones.
    failure: ?ParseFailure = null,

    /// Single lease-release site: unlocks the write lease.
    pub fn deinit(self: *ParseLease) void {
        self.session.releaseParse();
        self.* = undefined;
    }
};

pub const Session = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    runtime_context: data_structures.RuntimeContext,
    reader_buffer: []u8,
    chunk_buffer: []u8,
    owned_input: ?[]u8 = null,
    node_allocator: if (parser.is_ast_enabled) data_structures.ASTAllocator else void,
    verbosity: if (builtin.mode == .Debug) usize else void,
    stack_overflow_recovery: bool,
    ast_preallocation_ratio: if (parser.is_ast_enabled) f64 else void,
    ast_preallocation_cap: if (parser.is_ast_enabled) usize else void,
    session_lock: SessionLock = .init,
    generation: usize = 0,
    /// Byte length of the latest parse's input, when its entry point knows it
    /// (null for streamed input of unknown length). A parse that fails after
    /// publishing reports `parsed_bytes` as far as the parser consumed, which
    /// can stop short of an input recovery skipped to the end of; hosts that
    /// retain the input of a published failure retain this many bytes.
    input_length: ?usize = null,
    /// The result of the most recent published parse — a success, or a
    /// failure that ran to its end with recorded errors — written only by
    /// `_parseContextUnlocked` under the exclusive lock and read only under
    /// a guard. It goes stale — never null again — the moment a later parse
    /// (published or not) advances `generation`.
    published_result: ?ParseResult = null,
    /// Host-owned pointer copied onto each parse `Context` (`Context.user_data`)
    /// for hooks written in Zig. A host shim build uses it as the dispatch
    /// handle (see `setHostHooks`).
    user_data: ?*anyopaque = null,
    /// Hooks the host enabled on this session and its dispatch callback,
    /// copied onto each parse `Context`. Written only through `setHostHooks`.
    host_hooks: data_structures.HostHooks = .{},
    /// Live parse context, set only inside `_parseContextUnlocked`.
    active_context: ?*data_structures.Context = null,
    /// Message overrides owned by the session (copied from `ParseOptions`
    /// at creation, extendable through the C API's override setter).
    /// Allocated from `allocator`, never from the parse arena, so entries
    /// survive across parses.
    message_overrides: std.StringHashMapUnmanaged([]const u8) = .empty,

    pub fn init(io: std.Io, allocator: std.mem.Allocator, options: ParseOptions) !Session {
        if (options.max_errors == 0) return error.InvalidMaxErrors;
        if (options.recovery_window == 0) return error.InvalidRecoveryWindow;
        if (options.syntax_error_stack_depth > data_structures.max_syntax_error_stack_depth) {
            return error.InvalidSyntaxErrorStackDepth;
        }
        if (options.stack_overflow_recovery and !stack_overflow_recovery_available) {
            return error.StackOverflowRecoveryUnsupported;
        }
        if (parser.is_ast_enabled and
            (!std.math.isFinite(options.ast_preallocation_ratio) or options.ast_preallocation_ratio < 0))
        {
            return error.InvalidASTPreallocationRatio;
        }

        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        const reader_buffer = try allocator.alloc(u8, read_chunk_size * 2);
        errdefer allocator.free(reader_buffer);

        const chunk_buffer_size = if (sliding_input_enabled and !config.indentation_syntax)
            input_window_size + input_padding_size
        else
            read_chunk_size;
        const chunk_buffer = try allocator.alloc(u8, chunk_buffer_size);
        errdefer allocator.free(chunk_buffer);

        var message_overrides: std.StringHashMapUnmanaged([]const u8) = .empty;
        errdefer message_overrides.deinit(allocator);
        for (options.message_overrides) |override| {
            const name = try allocator.dupe(u8, override.name);
            errdefer allocator.free(name);
            const message = try allocator.dupe(u8, override.message);
            errdefer allocator.free(message);
            try message_overrides.put(allocator, name, message);
        }

        var node_allocator = if (parser.is_ast_enabled)
            try data_structures.ASTAllocator.initWithCapacity(allocator, 0)
        else {};
        errdefer if (parser.is_ast_enabled) node_allocator.deinit(allocator);

        return .{
            .io = io,
            .allocator = allocator,
            .arena = arena,
            .runtime_context = .{
                .io = io,
                .input_path = options.input_path,
                .arena_allocator = arena.allocator(),
                .max_errors = options.max_errors,
                .recovery_window = options.recovery_window,
                .syntax_error_stack_depth = if (options.syntax_error_stack_depth > 0)
                    options.syntax_error_stack_depth
                else
                    parser.syntax_error_stack_depth,
                .syntax_error_reporter = options.syntax_error_reporter,
            },
            .reader_buffer = reader_buffer,
            .chunk_buffer = chunk_buffer,
            .node_allocator = node_allocator,
            .message_overrides = message_overrides,
            .verbosity = if (builtin.mode == .Debug) options.verbosity else {},
            .stack_overflow_recovery = options.stack_overflow_recovery,
            .ast_preallocation_ratio = if (parser.is_ast_enabled) options.ast_preallocation_ratio else {},
            .ast_preallocation_cap = if (parser.is_ast_enabled) options.ast_preallocation_cap else {},
        };
    }

    pub fn deinit(self: *Session) void {
        self.tryDeinit() catch @panic("attempted to deinitialize a parser session while it is in use");
    }

    pub fn tryDeinit(self: *Session) error{SessionInUse}!void {
        if (!self.session_lock.tryLock()) return error.SessionInUse;
        defer self.session_lock.unlock();

        if (self.owned_input) |owned_input| {
            self.allocator.free(owned_input);
            self.owned_input = null;
        }
        if (parser.is_ast_enabled) {
            self.node_allocator.deinit(self.allocator);
        }
        self.freeMessageOverrides();
        self.allocator.free(self.chunk_buffer);
        self.allocator.free(self.reader_buffer);
        self.arena.deinit();
    }

    /// Frees every override entry owned by the session. The map itself is a
    /// plain field, so only the copied keys and values need releasing.
    fn freeMessageOverrides(self: *Session) void {
        var iterator = self.message_overrides.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.message_overrides.deinit(self.allocator);
    }

    /// Single result-validation site. A parse result addresses this session
    /// only while its stamped identity and generation still match; every
    /// result-taking guard funnels through `resolveResult`, which calls
    /// this, so a stale result cannot slip through any door.
    fn validateResult(self: *const Session, result: ParseResult) bool {
        return result._session_identity == @as(*const anyopaque, @ptrCast(self.reader_buffer.ptr)) and
            result._session_generation == self.generation;
    }

    /// Where a result-taking guard gets the result it validates.
    const ResultSource = union(enum) {
        /// A result the caller holds.
        given: ParseResult,
        /// The session's own published result, loaded under the lock so a
        /// concurrent publication cannot separate the load from the guard.
        published,
    };

    /// Resolves and validates the result for a guard whose lock the caller
    /// already holds; on failure the caller releases that lock.
    fn resolveResult(self: *const Session, source: ResultSource) SessionError!ParseResult {
        const result = switch (source) {
            .given => |given| given,
            .published => self.published_result orelse return error.NoParseResult,
        };
        if (!self.validateResult(result)) return error.StaleParseResult;
        return result;
    }

    fn readGuard(self: *Session, source: ResultSource) SessionError!SessionReadGuard {
        if (!self.session_lock.tryLockShared()) return error.SessionInUse;
        const result = self.resolveResult(source) catch |err| {
            self.session_lock.unlockShared();
            return err;
        };
        return .{ .session = self, .result = result };
    }

    fn editGuard(self: *Session, source: ResultSource) SessionError!SessionEditGuard {
        if (!self.session_lock.tryLock()) return error.SessionInUse;
        _ = self.resolveResult(source) catch |err| {
            self.session_lock.unlock();
            return err;
        };
        return .{ .session = self };
    }

    /// Shared guard for a result the caller holds. Refuses a result from a
    /// dead parse.
    pub fn read(self: *Session, result: ParseResult) SessionError!SessionReadGuard {
        return self.readGuard(.{ .given = result });
    }

    /// Shared guard for the session's published result: the last parse that
    /// published (a success, or a failure that ran to its end), refused as
    /// stale once any later parse has begun and as absent before the first
    /// publication.
    pub fn readCurrent(self: *Session) SessionError!SessionReadGuard {
        return self.readGuard(.published);
    }

    pub fn readLatest(self: *Session) SessionError!SessionDiagnosticsGuard {
        if (!self.session_lock.tryLockShared()) return error.SessionInUse;
        return .{ .session = self };
    }

    /// Exclusive guard for mutations that must not race readers: the
    /// rendered-diagnostic cache and node-storage reservations. No
    /// result is validated — the caller owns what it writes — so a node
    /// mutation must go through `editResult` or `editCurrent` instead.
    /// Fail-fast: a hook reaching back through a stashed session meets its
    /// own parse's exclusive hold and gets `SessionInUse` rather than
    /// deadlocking.
    pub fn edit(self: *Session) error{SessionInUse}!SessionEditGuard {
        if (!self.session_lock.tryLock()) return error.SessionInUse;
        return .{ .session = self };
    }

    /// The mutation door for tree edits: exclusive like `edit`, plus the
    /// same result validation as `read`, so an address from a dead parse is
    /// refused before it can index storage the next parse reset.
    pub fn editResult(self: *Session, result: ParseResult) SessionError!SessionEditGuard {
        return self.editGuard(.{ .given = result });
    }

    /// Exclusive twin of `readCurrent`: the tree-edit gate over the
    /// session's published result. Fail-fast like `edit`, so a hook reaching
    /// back through a stashed session gets `SessionInUse` rather than
    /// deadlocking.
    pub fn editCurrent(self: *Session) SessionError!SessionEditGuard {
        return self.editGuard(.published);
    }

    /// Replaces the session's host hook state in one step: the enabled set,
    /// the dispatch callback and the handle every dispatched hook receives.
    /// Exclusive and fail-fast like `edit`, so the set a parse runs with is
    /// fixed for that parse and a change during a parse is `SessionInUse`.
    /// Node storage is untouched, so published results stay valid.
    pub fn setHostHooks(self: *Session, hooks: data_structures.HostHooks, handle: ?*anyopaque) error{SessionInUse}!void {
        var guard = try self.edit();
        defer guard.deinit();
        self.host_hooks = hooks;
        self.user_data = handle;
    }

    /// Single parse-acquire site. Every parse entry funnels through here so
    /// the lock and generation cannot disagree. The nested-recovery gate
    /// runs first, before the lock, so a rejected nested parse leaves
    /// generation, node storage, `owned_input`, and
    /// `runtime_context.input_path` untouched.
    fn acquireParse(self: *Session) SessionError!void {
        if (stack_overflow_utilities.isActive() and !self.stack_overflow_recovery) {
            return error.NestedParseDuringStackOverflowRecovery;
        }
        if (!self.session_lock.tryLock()) return error.SessionInUse;
        if (self.generation == std.math.maxInt(usize)) {
            self.session_lock.unlock();
            return error.SessionGenerationExhausted;
        }
        self.generation += 1;
    }

    /// Single parse-release site. Unlocks the write lease held by the parse.
    fn releaseParse(self: *Session) void {
        self.session_lock.unlock();
    }

    /// Single guard-release site. Both guard types delegate here so the
    /// shared-lock release has one implementation; the narrowing (the
    /// diagnostics guard exposes no node storage) lives in the accessors.
    fn releaseSharedGuard(self: *Session) void {
        self.session_lock.unlockShared();
    }

    /// Single edit-release site. The edit guards delegate here so the
    /// exclusive release has one implementation.
    fn releaseEditGuard(self: *Session) void {
        self.session_lock.unlock();
    }

    fn ensureOwnedInputCapacity(self: *Session, required: usize) ![]u8 {
        if (self.owned_input) |owned_input| {
            if (owned_input.len >= required) return owned_input[0..required];
            self.allocator.free(owned_input);
            self.owned_input = null;
        }

        const owned_input = try self.allocator.alloc(u8, required);
        self.owned_input = owned_input;
        return owned_input;
    }

    fn prepareASTCapacity(self: *Session, input_length: usize) !void {
        if (comptime !parser.is_ast_enabled) return;

        // The previous tree is dead by contract and the parse lock is held,
        // so rewinding first lets `ensureCapacity` re-reserve larger between
        // parses instead of mistaking a stale counter for live nodes.
        self.node_allocator.reset();
        const limit = data_structures.ASTAllocator.capacity_limit;
        const floor = @min(self.ast_preallocation_cap, limit);
        if (comptime data_structures.ASTAllocator.supports_reserved_arena) {
            // Reserved path: the reservation is address space without
            // committed pages (MAP_NORESERVE), so the cap stays a floor and
            // the scaled estimate reserves cheaply. Demand past the
            // reservation appends segments; the only wall is the
            // address-space limit. Callers with atypical density raise the
            // ratio or floor through `ParseOptions` to avoid that slower
            // path. Arithmetic: capacity is the floor when the scaled
            // estimate is at or below it, the estimate itself (rounded up)
            // when between floor and limit, and the limit above that — so it
            // stays within [floor, limit] and covers the estimate whenever
            // the limit allows.
            const scaled = @ceil(
                @as(f64, @floatFromInt(input_length)) * self.ast_preallocation_ratio,
            );
            var capacity: usize = floor;
            if (scaled > @as(f64, @floatFromInt(floor))) {
                capacity = if (scaled >= @as(f64, @floatFromInt(limit)))
                    limit
                else
                    @as(usize, @intFromFloat(scaled));
            }
            try self.node_allocator.ensureCapacity(capacity);
        } else {
            // Segment path: every reserved node is heap-allocated and
            // zeroed, so only the floor is prepared eagerly and the scaled
            // estimate is ignored. Demand past the floor appends segments
            // mid-parse; a large input never eagerly allocates length times
            // ratio nodes here.
            try self.node_allocator.ensureCapacity(floor);
        }
    }

    /// The leased entry for byte input: acquires the write lease and runs
    /// the parse under it, returning a lease whose `deinit` releases.
    /// A caller that pairs state of its own with the published result (the
    /// C ABI) holds the lease while it writes that state; one that only
    /// needs the result uses `parseBytes`, which releases on return.
    pub fn parseBytesLeased(self: *Session, input: []const u8, input_path: ?[]const u8) !ParseLease {
        try self.acquireParse();
        errdefer self.releaseParse();
        const completed = try self.parseBytesUnlocked(input, input_path);
        return .{ .session = self, .result = completed.result, .failure = completed.failure };
    }

    pub fn parseBytes(self: *Session, input: []const u8, input_path: ?[]const u8) !ParseResult {
        var lease = try self.parseBytesLeased(input, input_path);
        defer lease.deinit();
        if (lease.failure) |failure| return failure;
        return lease.result;
    }

    fn parseBytesUnlocked(self: *Session, input: []const u8, input_path: ?[]const u8) !Completed {
        self.input_length = input.len;
        try self.prepareASTCapacity(input.len);
        const padding = input_padding_size;
        const owned_input = try self.ensureOwnedInputCapacity(input.len + padding);
        @memcpy(owned_input[0..input.len], input);
        @memset(owned_input[input.len..], 0);

        var context_value = self._makeContext(.{ .bytes = .{ .input = owned_input } }, input_path);
        return try self._parseContextUnlocked(&context_value);
    }

    /// The leased entry for NUL-terminated input; see `parseBytesLeased`.
    pub fn parseSentinelBytesLeased(self: *Session, input: [:0]const u8, input_path: ?[]const u8) !ParseLease {
        try self.acquireParse();
        errdefer self.releaseParse();
        const completed = try self.parseSentinelBytesUnlocked(input, input_path);
        return .{ .session = self, .result = completed.result, .failure = completed.failure };
    }

    pub fn parseSentinelBytes(self: *Session, input: [:0]const u8, input_path: ?[]const u8) !ParseResult {
        var lease = try self.parseSentinelBytesLeased(input, input_path);
        defer lease.deinit();
        if (lease.failure) |failure| return failure;
        return lease.result;
    }

    fn parseSentinelBytesUnlocked(self: *Session, input: [:0]const u8, input_path: ?[]const u8) !Completed {
        self.input_length = input.len;
        try self.prepareASTCapacity(input.len);
        // Retain a session-owned copy of the input (sentinel byte plus zero
        // padding). The caller's buffer may be freed as soon as this call
        // returns, while node text pointers remain valid until the next
        // parse — so parsing must never reference caller memory.
        const retained_length = input.len + 1;
        const owned_input = try self.ensureOwnedInputCapacity(retained_length + input_padding_size);
        @memcpy(owned_input[0..retained_length], input[0..retained_length]);
        @memset(owned_input[retained_length..], 0);

        var context_value = self._makeContext(.{ .bytes = .{ .input = owned_input[0..retained_length] } }, input_path);
        return try self._parseContextUnlocked(&context_value);
    }

    /// The leased entry for file input; see `parseBytesLeased`.
    pub fn parseFileLeased(self: *Session, file: std.Io.File, input_path: ?[]const u8) !ParseLease {
        try self.acquireParse();
        errdefer self.releaseParse();
        const completed = try self.parseFileUnlocked(file, input_path);
        return .{ .session = self, .result = completed.result, .failure = completed.failure };
    }

    pub fn parseFile(self: *Session, file: std.Io.File, input_path: ?[]const u8) !ParseResult {
        var lease = try self.parseFileLeased(file, input_path);
        defer lease.deinit();
        if (lease.failure) |failure| return failure;
        return lease.result;
    }

    fn parseFileUnlocked(self: *Session, file: std.Io.File, input_path: ?[]const u8) !Completed {
        self.input_length = null;
        if (comptime !input_streaming_enabled) {
            if (self.owned_input) |owned_input| {
                self.allocator.free(owned_input);
                self.owned_input = null;
            }

            var reader = file.reader(self.io, self.reader_buffer);
            const input = input: {
                var complete_input = try reader.interface.allocRemaining(self.allocator, .unlimited);
                errdefer self.allocator.free(complete_input);

                const input_length = complete_input.len;
                self.input_length = input_length;
                try self.prepareASTCapacity(input_length);
                complete_input = try self.allocator.realloc(complete_input, input_length + input_padding_size);
                @memset(complete_input[input_length..], 0);
                break :input complete_input;
            };
            self.owned_input = input;

            var context_value = self._makeContext(.{ .bytes = .{ .input = input } }, input_path);
            return try self._parseContextUnlocked(&context_value);
        }

        const known_retained_file_length: ?usize = if (comptime source_retention_enabled) known: {
            const stat = file.stat(self.io) catch break :known null;
            if (stat.kind != .file) break :known null;

            const file_length = std.math.cast(usize, stat.size) orelse return error.InputTooLarge;
            if (comptime parser.is_ast_enabled) try self.prepareASTCapacity(file_length);
            break :known file_length;
        } else null;

        if (comptime input_streaming_enabled and !config.indentation_syntax and source_retention_enabled) {
            const file_length = known_retained_file_length orelse {
                var reader = file.reader(self.io, self.reader_buffer);
                const input = try reader.interface.allocRemaining(self.allocator, .unlimited);
                defer self.allocator.free(input);
                return try self.parseBytesUnlocked(input, input_path);
            };

            self.input_length = file_length;
            const input = try self.ensureOwnedInputCapacity(file_length + input_padding_size);
            @memset(input[file_length..], 0);

            var context_value = self._makeContext(.{ .file = file.reader(self.io, self.reader_buffer) }, input_path);
            context_value.file_input = input;
            context_value.input_end = file_length;
            return try self._parseContextUnlocked(&context_value);
        }
        var context_value = self._makeContext(.{ .file = file.reader(self.io, self.reader_buffer) }, input_path);
        return try self._parseContextUnlocked(&context_value);
    }

    pub fn _makeContext(self: *Session, source: data_structures.Context.Source, input_path: ?[]const u8) data_structures.Context {
        self.runtime_context.input_path = input_path;
        self.runtime_context.arena_allocator = self.arena.allocator();

        var context_value = data_structures.Context{
            .runtime_context = &self.runtime_context,
            .source = source,
            .node_allocator = if (parser.is_ast_enabled) &self.node_allocator else {},
            .chunk_buffer = self.chunk_buffer,
            .user_data = self.user_data,
            .host_hooks = self.host_hooks,
        };
        if (comptime builtin.mode == .Debug) {
            context_value.verbosity = self.verbosity;
        }
        return context_value;
    }

    pub fn _parseContext(self: *Session, context_value: *data_structures.Context) !ParseResult {
        try self.acquireParse();
        defer self.releaseParse();
        const completed = try self._parseContextUnlocked(context_value);
        if (completed.failure) |failure| return failure;
        return completed.result;
    }

    /// A parse that ran to its end: the result it published, and the failure
    /// it reports with that result when the parse recorded errors.
    const Completed = struct { result: ParseResult, failure: ?ParseFailure };

    /// The single publish gate. A parse that ran to its end publishes its
    /// result — the tree is complete even when errors were recorded, since
    /// recovery keeps the damaged region as flagged nodes — and then reports
    /// the failure beside it: recovered syntax errors first, then semantic
    /// ones. A parse that did not run to its end (a read or indentation
    /// failure, an error the parser could not recover from, stack overflow,
    /// out of memory) returns its error and publishes nothing, so its
    /// generation is never live.
    fn _parseContextUnlocked(self: *Session, context_value: *data_structures.Context) !Completed {
        context_value.runtime_context = &self.runtime_context;
        context_value.generation = self.generation;

        _ = self.arena.reset(.retain_capacity);
        self.runtime_context.message_overrides = &self.message_overrides;
        self.runtime_context.recorded_diagnostics = .empty;
        self.runtime_context.last_rendered_message = null;
        self.runtime_context.syntax_error_count = 0;
        self.runtime_context.semantic_error_count = 0;
        self.runtime_context.syntax_recovery_position = null;
        self.runtime_context.explicit_recovery_position = null;
        self.runtime_context.explicit_recovery_target_id = null;
        self.runtime_context.pending_syntax_error_site = null;
        self.runtime_context.recovered_pending = .empty;

        try context_value.reset();
        self.active_context = context_value;
        defer self.active_context = null;
        const result = if (self.stack_overflow_recovery)
            stack_overflow_utilities.protectedParse(context_value)
        else
            parser.parseWithResult(context_value);
        const parsed = result catch |err| {
            if (context_value.input_read_failed) return error.ReadFailed;
            if (comptime config.indentation_syntax) {
                if (context_value.indentation_error) return error.IndentationError;
            }
            return err;
        };
        if (context_value.input_read_failed) {
            @branchHint(.unlikely);
            return error.ReadFailed;
        }
        if (comptime config.indentation_syntax) {
            if (context_value.indentation_error) {
                @branchHint(.unlikely);
                return error.IndentationError;
            }
        }
        var session_result = parsed;
        session_result._session_generation = self.generation;
        session_result._session_identity = @ptrCast(self.reader_buffer.ptr);
        self.published_result = session_result;
        const failure: ?ParseFailure = if (self.runtime_context.syntax_error_count != 0)
            error.SyntaxError
        else if (self.runtime_context.semantic_error_count != 0)
            error.SemanticError
        else
            null;
        return .{ .result = session_result, .failure = failure };
    }
};

test "synthetic terminals render display names in diagnostics" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    try formatParseDiagnostic(&output.writer, .{ .syntax = .{
        .line = 1,
        .column = 10,
        .unexpected_token = "\x00",
        .expected_tokens = &.{ "\x01", "\x02", "{" },
    } }, .plain);

    const rendered = output.written();
    try std.testing.expect(std.mem.indexOf(u8, rendered, "Unexpected token \"End of input\"") != null);
    if (comptime data_structures.indentationSyntaxEnabled()) {
        try std.testing.expect(std.mem.indexOf(u8, rendered, "'Indent', 'Dedent', '{'") != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, "\\x") == null);
    } else {
        try std.testing.expect(std.mem.indexOf(u8, rendered, "'{'") != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, "\\x01") != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, "\\x02") != null);
    }
}

test "message override placeholders show synthetic display names" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    const diagnostic: ParseDiagnostic = .{ .syntax = .{
        .line = 1,
        .column = 10,
        .unexpected_token = "\x00",
        .expected_tokens = &.{ "\x01", "{" },
        .context = .{ .while_parsing = &.{"Value"} },
    } };
    const config_tables = .{
        .Value = "saw {unexpected} want {expected}",
    };

    var runtime = data_structures.RuntimeContext{
        .io = io,
        .arena_allocator = arena_state.allocator(),
    };
    const expected = if (comptime data_structures.indentationSyntaxEnabled())
        "saw End of input want 'Indent', '{'"
    else
        "saw End of input want '\\x01', '{'";
    try std.testing.expectEqualStrings(
        expected,
        runtime.resolveMessageOverride(diagnostic, config_tables).?,
    );
}

test "galley LL grammar error hook returns custom guidance" {
    var dummy_runtime: data_structures.RuntimeContext = .{ .io = std.testing.io, .arena_allocator = std.testing.allocator };
    var context: data_structures.Context = .{ .runtime_context = &dummy_runtime };
    const diagnostic: ParseDiagnostic = .{ .syntax = .{
        .line = 51,
        .column = 1,
        .unexpected_token = "F",
        .expected_tokens = &.{ "\x00", "\n", "#", "|" },
        .context = .{ .while_parsing = &.{"RightHandSidesTail"} },
        .recovery = .{
            .target = .{ .lhs_variable = "RightHandSideLine" },
            .terminal = "\n",
            .@"resume" = .after,
        },
    } };

    const message = try error_messages.syntax_error_ll_RightHandSidesTail__expected_RightHandSideLine_or_end_of_RightHandSidesTail(.{
        .allocator = std.testing.allocator,
        .context = &context,
        .diagnostic = diagnostic,
        .style = .plain,
    });
    defer std.testing.allocator.free(message);

    try std.testing.expect(std.mem.indexOf(u8, message, "Expected another production line, a comment line, or a blank line before the next rule.") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "Production lines start with `|`; comment lines start with `#`.") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "Unexpected token: \"F\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "Recovery: LHS variable RightHandSideLine resumed after \"\\n\".") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "Unexpected token \"F\" while parsing RightHandSidesTail") == null);
}

test "tracked galley LL parser uses explicit recovery" {
    try std.testing.expect(parser.is_error_recovery_enabled);
    try std.testing.expectEqual(parser.ErrorRecoveryMode.explicit, parser.error_recovery_mode);
}

test "syntax error stack activation is gated on build mode and build option" {
    try std.testing.expectEqual(syntax_error_stack_depth, parser.syntax_error_stack_depth);
    try std.testing.expectEqual(syntax_error_stack_depth > 1, parser.is_syntax_error_stack_enabled);
}

test "syntax error stack depth is configurable per session" {
    if (builtin.mode != .Debug) return error.SkipZigTest;

    const malformed =
        \\Start
        \\| ?
        \\
    ;

    for ([_]usize{ 1, 3 }) |depth| {
        var session = try Session.init(std.Io.failing, std.testing.allocator, .{ .syntax_error_stack_depth = depth });
        defer session.deinit();
        var context = session._makeContext(.{ .bytes = .{ .input = malformed[0 .. malformed.len + 1] } }, null);
        if (session._parseContext(&context)) |_| {
            return error.ExpectedSyntaxError;
        } else |err| switch (err) {
            ParseError.SyntaxError => {},
            else => return err,
        }
        var read_guard = try session.readLatest();
        defer read_guard.deinit();
        const diagnostic = read_guard.lastDiagnostic() orelse return error.MissingDiagnostic;
        const syntax = switch (diagnostic) {
            .syntax => |value| value,
            .semantic, .indentation => return error.ExpectedSyntaxDiagnostic,
        };
        try std.testing.expectEqual(depth, syntax.context.while_parsing.len);
    }
}

test "message overrides replace rendered syntax errors and beat hooks" {
    if (builtin.mode != .Debug) return error.SkipZigTest;

    const malformed =
        \\Start
        \\| ?
        \\
    ;

    const run = struct {
        fn parse(overrides: []const MessageOverride, allocator: std.mem.Allocator) ![]u8 {
            var session = try Session.init(std.Io.failing, allocator, .{
                .message_overrides = overrides,
            });
            errdefer session.deinit();
            var context = session._makeContext(.{ .bytes = .{ .input = malformed[0 .. malformed.len + 1] } }, null);
            if (session._parseContext(&context)) |_| {
                return error.ExpectedSyntaxError;
            } else |err| switch (err) {
                ParseError.SyntaxError => {},
                else => return err,
            }
            const rendered = session.runtime_context.last_rendered_message orelse return error.MissingRenderedMessage;
            const copy = try allocator.dupe(u8, rendered);
            session.deinit();
            return copy;
        }
    }.parse;

    const baseline = try run(&.{}, std.testing.allocator);
    defer std.testing.allocator.free(baseline);
    try std.testing.expect(baseline.len > 0);

    const overridden = try run(&.{.{
        .name = "*",
        .message = "override text beats every hook",
    }}, std.testing.allocator);
    defer std.testing.allocator.free(overridden);
    try std.testing.expectEqualStrings("override text beats every hook", overridden);
    try std.testing.expect(!std.mem.eql(u8, baseline, overridden));

    // A variable-scoped entry for a variable this input never fails in
    // falls through to the hooks/builtin chain.
    const scoped = try run(&.{.{
        .name = "Document",
        .message = "unreachable variable override",
    }}, std.testing.allocator);
    defer std.testing.allocator.free(scoped);
    try std.testing.expect(!std.mem.eql(u8, scoped, "unreachable variable override"));
}

test "message templates resolve session overrides then config entries" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();

    var overrides = std.StringHashMapUnmanaged([]const u8){};
    defer overrides.deinit(std.testing.allocator);
    try overrides.put(std.testing.allocator, "*", "session-star {column}");

    const diagnostic: ParseDiagnostic = .{ .syntax = .{
        .line = 4,
        .column = 9,
        .unexpected_token = "?",
        .expected_tokens = &.{"digit"},
        .context = .{ .while_parsing = &.{"Number"} },
    } };

    // Stand-in for a consumer's `config.error_messages` table.
    const config_tables = .{
        .Number = "config-number saw {unexpected}",
        .@"*" = "config-star",
    };

    // A session entry beats both config entries for the same diagnostic.
    var runtime_with_session = data_structures.RuntimeContext{
        .io = io,
        .arena_allocator = arena_state.allocator(),
        .message_overrides = &overrides,
    };
    try std.testing.expectEqualStrings("session-star 9", runtime_with_session.resolveMessageOverride(diagnostic, config_tables).?);

    // Without session entries, the config's variable-specific template wins
    // over its universal entry and expands placeholders.
    var runtime_plain = data_structures.RuntimeContext{
        .io = io,
        .arena_allocator = arena_state.allocator(),
    };
    try std.testing.expectEqualStrings("config-number saw ?", runtime_plain.resolveMessageOverride(diagnostic, config_tables).?);

    // The universal config entry applies to every other variable.
    const other: ParseDiagnostic = .{ .syntax = .{
        .line = 1,
        .column = 2,
        .unexpected_token = "x",
        .expected_tokens = &.{},
        .context = .{ .while_parsing = &.{"String"} },
    } };
    try std.testing.expectEqualStrings("config-star", runtime_plain.resolveMessageOverride(other, config_tables).?);
}

test "duplicate rule headers record a semantic diagnostic" {
    if (builtin.mode != .Debug) return error.SkipZigTest;

    const duplicated =
        \\A
        \\| "x"
        \\
        \\A
        \\| "y"
        \\
    ;

    var session = try Session.init(std.Io.failing, std.testing.allocator, .{
        .syntax_error_reporter = &struct {
            fn ignore(_: []const u8) void {}
        }.ignore,
    });
    defer session.deinit();
    try std.testing.expectError(error.DuplicateRuleHeader, session.parseBytes(duplicated, null));

    var read_guard = try session.readLatest();
    defer read_guard.deinit();
    try std.testing.expectEqual(@as(usize, 1), read_guard.semanticErrorCount());
    try std.testing.expectEqual(@as(usize, 0), read_guard.syntaxErrorCount());
    const diagnostic = read_guard.lastDiagnostic() orelse return error.MissingDiagnostic;
    const semantic = switch (diagnostic) {
        .semantic => |value| value,
        else => return error.ExpectedSemanticDiagnostic,
    };
    try std.testing.expectEqualStrings("Start", semantic.variable);
    try std.testing.expect(std.mem.indexOf(u8, semantic.message, "DuplicateRuleHeader") != null);
}

test "message override placeholders expand against the diagnostic" {
    if (builtin.mode != .Debug) return error.SkipZigTest;

    const malformed =
        \\Start
        \\| ?
        \\
    ;

    var session = try Session.init(std.Io.failing, std.testing.allocator, .{
        .message_overrides = &.{.{
            .name = "*",
            .message = "line {line} col {column} saw '{unexpected}' want {expected} | {context} | keep {unknown}",
        }},
    });
    defer session.deinit();
    var context = session._makeContext(.{ .bytes = .{ .input = malformed[0 .. malformed.len + 1] } }, null);
    if (session._parseContext(&context)) |_| {
        return error.ExpectedSyntaxError;
    } else |err| switch (err) {
        ParseError.SyntaxError => {},
        else => return err,
    }
    const message = session.runtime_context.last_rendered_message orelse return error.MissingRenderedMessage;
    try std.testing.expect(std.mem.startsWith(u8, message, "line 2 col 3 saw '?' want '"));
    try std.testing.expect(std.mem.indexOf(u8, message, " <~ ") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "keep {unknown}") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "{line}") == null);
    try std.testing.expect(std.mem.indexOf(u8, message, "{context}") == null);
}

test "structured syntax recovery renders in plain and ANSI diagnostics" {
    const diagnostic: ParseDiagnostic = .{ .syntax = .{
        .line = 3,
        .column = 7,
        .unexpected_token = "?",
        .expected_tokens = &.{"x"},
        .context = .{ .while_parsing = &.{"Child"} },
        .recovery = .{
            .target = .{ .occurrence = .{
                .parent_variable = "Parent",
                .rhs_index = 2,
                .symbol_index = 1,
                .variable = "Child",
            } },
            .terminal = ";",
            .@"resume" = .after,
        },
    } };

    const plain = try renderParseDiagnostic(std.testing.allocator, diagnostic, .plain);
    defer std.testing.allocator.free(plain);
    try std.testing.expect(std.mem.indexOf(u8, plain, "Unexpected token \"?\" while parsing Child.") != null);
    try std.testing.expect(std.mem.indexOf(u8, plain, "Recovery: occurrence Child at Parent[2].1 resumed after \";\".") != null);

    const ansi = try renderParseDiagnostic(std.testing.allocator, diagnostic, .ansi);
    defer std.testing.allocator.free(ansi);
    try std.testing.expect(std.mem.indexOf(u8, ansi, "Recovery: occurrence Child at Parent[2].1 resumed after \";\".") != null);
}

test "while parsing stack renders with <~ separators, coloring only variables" {
    const diagnostic: ParseDiagnostic = .{ .syntax = .{
        .line = 3,
        .column = 7,
        .unexpected_token = "?",
        .expected_tokens = &.{"x"},
        .context = .{ .while_parsing = &.{ "_OptionalBlank", "OptionalBlank", "Value", "ArrayMembers", "Value" } },
    } };

    const plain = try renderParseDiagnostic(std.testing.allocator, diagnostic, .plain);
    defer std.testing.allocator.free(plain);
    try std.testing.expect(std.mem.indexOf(u8, plain, "Unexpected token \"?\" while parsing _OptionalBlank <~ OptionalBlank <~ Value <~ ArrayMembers <~ Value.") != null);
    try std.testing.expect(std.mem.indexOf(u8, plain, ", ") == null);

    const ansi = try renderParseDiagnostic(std.testing.allocator, diagnostic, .ansi);
    defer std.testing.allocator.free(ansi);
    try std.testing.expect(std.mem.indexOf(u8, ansi, " while parsing ") != null);
    try std.testing.expect(std.mem.indexOf(u8, ansi, "\x1b[34m_OptionalBlank\x1b[0m") != null);
    try std.testing.expect(std.mem.indexOf(u8, ansi, "\x1b[34mOptionalBlank\x1b[0m") != null);
    try std.testing.expect(std.mem.indexOf(u8, ansi, "\x1b[34mArrayMembers\x1b[0m") != null);
    try std.testing.expect(std.mem.indexOf(u8, ansi, "\x1b[34mValue\x1b[0m <~ \x1b[34mArrayMembers\x1b[0m") != null);
    try std.testing.expect(std.mem.indexOf(u8, ansi, "\x1b[34m_OptionalBlank <~") == null);
    try std.testing.expect(std.mem.indexOf(u8, ansi, "<~ \x1b[34m\x1b[34m") == null);
}
