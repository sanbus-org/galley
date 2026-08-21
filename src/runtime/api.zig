const builtin = @import("builtin");
const std = @import("std");
const runtime_options = @import("runtime_options");

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

pub const ParseError = error{
    SyntaxError,
    IndentationError,
    StackOverflow,
    ASTCapacityExceeded,
    UnterminatedRawString,
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

pub const ParseDiagnostic = union(enum) {
    syntax: SyntaxDiagnostic,
    indentation: IndentationDiagnostic,
};

pub const DiagnosticStyle = enum {
    plain,
    ansi,
};

pub const SyntaxErrorMessageReporter = *const fn (message: []const u8) void;

pub const ParseOptions = struct {
    language_options: config.Options = .{},
    input_path: ?[]const u8 = null,
    verbosity: usize = 0,
    max_errors: usize = 10,
    recovery_window: usize = 500,
    stack_overflow_recovery: bool = false,
    ast_preallocation_ratio: f64 = 2,
    ast_preallocation_cap: usize = 16_384,
    /// Number of in-progress variables (innermost first) reported in LL syntax
    /// error messages. `0` inherits the generated parser's default
    /// (`syntax_error_stack_depth`); a value above 1 enables the stack. A value
    /// below the parser's compile-time depth never adds instrumentation, so in
    /// release builds the stack stays off unless the build was compiled with
    /// `-Dsyntax-error-stack-depth` above 1.
    syntax_error_stack_depth: usize = 0,
    syntax_error_reporter: ?SyntaxErrorMessageReporter = null,
};

pub const SyntaxErrorMessageArgs = struct {
    allocator: std.mem.Allocator,
    context: *data_structures.Context,
    diagnostic: ParseDiagnostic,
    style: DiagnosticStyle,
};

pub const ParseResult = struct {
    parsed_bytes: usize,
    line: if (position_tracking_enabled) u32 else void,
    column: if (position_tracking_enabled) u32 else void,
    ast_root: ?data_structures.Node.Pointer = null,
    semantic_root: if (procedures_enabled) ?data_structures.Payload else void = if (procedures_enabled) null else {},
    _session_generation: usize = 0,
    _session_identity: ?*const anyopaque = null,
};

pub const SessionReadGuard = struct {
    session: *Session,

    pub fn deinit(self: *SessionReadGuard) void {
        self.session.session_lock.unlockShared(self.session.io);
        self.* = undefined;
    }

    pub fn astAllocator(self: *const SessionReadGuard) if (parser.is_ast_enabled) *const data_structures.ASTAllocator else void {
        if (parser.is_ast_enabled) {
            return &self.session.node_allocator;
        }
        return {};
    }

    pub fn lastDiagnostic(self: *const SessionReadGuard) ?ParseDiagnostic {
        return self.session.runtime_context.last_diagnostic;
    }

    pub fn syntaxErrorCount(self: *const SessionReadGuard) usize {
        return self.session.runtime_context.syntax_error_count;
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
        try writer.print("{f}", .{string_utilities.fmtString(expected_token)});
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
        string_utilities.fmtString(recovery.terminal),
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
                        string_utilities.fmtString(syntax.unexpected_token),
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
                            string_utilities.fmtString(syntax.unexpected_token),
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
    }
}

pub fn renderParseDiagnostic(allocator: std.mem.Allocator, diagnostic: ParseDiagnostic, style: DiagnosticStyle) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    try formatParseDiagnostic(&output.writer, diagnostic, style);
    return output.toOwnedSlice();
}

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
    session_lock: std.Io.RwLock = .init,
    generation: usize = 0,

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

        const node_allocator = if (parser.is_ast_enabled)
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
                .language_options = options.language_options,
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
        if (!self.session_lock.tryLock(self.io)) return error.SessionInUse;
        defer self.session_lock.unlock(self.io);

        if (self.owned_input) |owned_input| {
            self.allocator.free(owned_input);
            self.owned_input = null;
        }
        if (parser.is_ast_enabled) {
            self.node_allocator.deinit(self.allocator);
        }
        self.allocator.free(self.chunk_buffer);
        self.allocator.free(self.reader_buffer);
        self.arena.deinit();
    }

    pub fn read(self: *Session, result: ParseResult) error{ SessionInUse, StaleParseResult }!SessionReadGuard {
        if (!self.session_lock.tryLockShared(self.io)) return error.SessionInUse;
        if (result._session_identity != @as(*const anyopaque, @ptrCast(self.reader_buffer.ptr)) or
            result._session_generation != self.generation)
        {
            self.session_lock.unlockShared(self.io);
            return error.StaleParseResult;
        }
        return .{ .session = self };
    }

    pub fn readLatest(self: *Session) error{SessionInUse}!SessionReadGuard {
        if (!self.session_lock.tryLockShared(self.io)) return error.SessionInUse;
        return .{ .session = self };
    }

    fn beginParse(self: *Session) error{ SessionInUse, SessionGenerationExhausted }!void {
        if (!self.session_lock.tryLock(self.io)) return error.SessionInUse;
        if (self.generation == std.math.maxInt(usize)) {
            self.session_lock.unlock(self.io);
            return error.SessionGenerationExhausted;
        }
        self.generation += 1;
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

        const scaled_capacity = @ceil(
            @as(f64, @floatFromInt(input_length)) * self.ast_preallocation_ratio,
        );
        const maximum_capacity = data_structures.ASTAllocator.capacity_limit;
        const capped_capacity = @min(maximum_capacity, self.ast_preallocation_cap);
        const capacity = if (scaled_capacity >= @as(f64, @floatFromInt(capped_capacity)))
            capped_capacity
        else
            @as(usize, @intFromFloat(scaled_capacity));
        try self.node_allocator.ensureCapacity(capacity);
    }

    pub fn parseBytes(self: *Session, input: []const u8, input_path: ?[]const u8) !ParseResult {
        try self.beginParse();
        defer self.session_lock.unlock(self.io);
        return try self.parseBytesUnlocked(input, input_path);
    }

    fn parseBytesUnlocked(self: *Session, input: []const u8, input_path: ?[]const u8) !ParseResult {
        try self.prepareASTCapacity(input.len);
        const padding = input_padding_size;
        const owned_input = try self.ensureOwnedInputCapacity(input.len + padding);
        @memcpy(owned_input[0..input.len], input);
        @memset(owned_input[input.len..], 0);

        var context_value = self._makeContext(.{ .bytes = .{ .input = owned_input } }, input_path);
        return try self._parseContextUnlocked(&context_value);
    }

    pub fn parseSentinelBytes(self: *Session, input: [:0]const u8, input_path: ?[]const u8) !ParseResult {
        try self.beginParse();
        defer self.session_lock.unlock(self.io);
        return try self.parseSentinelBytesUnlocked(input, input_path);
    }

    fn parseSentinelBytesUnlocked(self: *Session, input: [:0]const u8, input_path: ?[]const u8) !ParseResult {
        try self.prepareASTCapacity(input.len);
        if (self.owned_input) |owned_input| {
            self.allocator.free(owned_input);
            self.owned_input = null;
        }

        var context_value = self._makeContext(.{ .bytes = .{ .input = input[0 .. input.len + 1] } }, input_path);
        return try self._parseContextUnlocked(&context_value);
    }

    pub fn parseFile(self: *Session, file: std.Io.File, input_path: ?[]const u8) !ParseResult {
        try self.beginParse();
        defer self.session_lock.unlock(self.io);
        return try self.parseFileUnlocked(file, input_path);
    }

    fn parseFileUnlocked(self: *Session, file: std.Io.File, input_path: ?[]const u8) !ParseResult {
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
            .source = source,
            .node_allocator = if (parser.is_ast_enabled) &self.node_allocator else {},
            .chunk_buffer = self.chunk_buffer,
        };
        if (comptime builtin.mode == .Debug) {
            context_value.verbosity = self.verbosity;
        }
        return context_value;
    }

    pub fn _parseContext(self: *Session, context_value: *data_structures.Context) !ParseResult {
        try self.beginParse();
        defer self.session_lock.unlock(self.io);
        return try self._parseContextUnlocked(context_value);
    }

    fn _parseContextUnlocked(self: *Session, context_value: *data_structures.Context) !ParseResult {
        var runtime_registration = data_structures.RuntimeContextRegistration.init(context_value, &self.runtime_context);
        runtime_registration.register();
        defer runtime_registration.unregister();

        _ = self.arena.reset(.retain_capacity);
        self.runtime_context.last_diagnostic = null;
        self.runtime_context.syntax_error_count = 0;
        self.runtime_context.syntax_recovery_position = null;
        self.runtime_context.explicit_recovery_position = null;
        self.runtime_context.explicit_recovery_target_id = null;
        self.runtime_context.pending_syntax_error_site = null;

        try context_value.reset();
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
        return session_result;
    }
};

test "galley LL grammar error hook returns custom guidance" {
    var context: data_structures.Context = undefined;
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
            .indentation => return error.ExpectedSyntaxDiagnostic,
        };
        try std.testing.expectEqual(depth, syntax.context.while_parsing.len);
    }
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
