const builtin = @import("builtin");
const std = @import("std");
const runtime_options = @import("runtime_options");

pub const procedures = @import("procedures");
pub const config = @import("config");
pub const error_messages = @import("error_messages");
pub const parser = @import("parser");
pub const ast_memory_benchmark_enabled = runtime_options.ast_memory_benchmark;
pub const string_utilities = @import("string.zig");
pub const stack_overflow_utilities = @import("stack-overflow.zig");
pub const data_structures = @import("data-structures/data-structures.zig");
pub const standard_procedures = @import("standard-procedures.zig");
pub const read_chunk_size = std.math.maxInt(std.math.Min(data_structures.Context.Size, u28));

pub const ParseError = error{
    SyntaxError,
    IndentationError,
    StackOverflow,
};

pub const SyntaxDiagnosticContext = union(enum) {
    none,
    while_parsing: []const u8,
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

pub const ParseDiagnostic = union(enum) {
    syntax: SyntaxDiagnostic,
};

pub const DiagnosticStyle = enum {
    plain,
    ansi,
};

pub const ParseOptions = struct {
    language_options: config.Options = .{},
    input_path: ?[]const u8 = null,
    verbosity: usize = 0,
    max_errors: usize = 10,
    recovery_window: usize = 500,
};

pub const SyntaxErrorMessageArgs = struct {
    allocator: std.mem.Allocator,
    context: *data_structures.Context,
    diagnostic: ParseDiagnostic,
    style: DiagnosticStyle,
};

pub const ParseResult = struct {
    parsed_bytes: usize,
    line: if (builtin.mode != .ReleaseFast) u32 else void,
    column: if (builtin.mode != .ReleaseFast) u32 else void,
    ast_root: ?data_structures.ASTNode.Pointer = null,
};

pub const ParsedInput = struct {
    session: Session,
    result: ParseResult,

    pub fn deinit(self: *ParsedInput) void {
        self.session.deinit();
    }
};

comptime {
    if (builtin.is_test and runtime_options.include_tests) {
        _ = @import("runtime_test.zig");
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
                        .while_parsing => |name| try writer.print(" while parsing {f}", .{string_utilities.fmtString(name)}),
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
                        .while_parsing => |name| try writer.print(" while parsing \x1b[34m{f}\x1b[0m.", .{string_utilities.fmtString(name)}),
                        .state => |state| try writer.print(" in state {d}.", .{state}),
                    }
                    try writer.writeAll("\nExpected tokens: \x1b[32m'");
                    try writeExpectedTokens(writer, syntax.expected_tokens);
                    try writer.writeAll("'\x1b[0m\n");
                    if (syntax.recovery) |recovery| try formatSyntaxRecovery(writer, recovery);
                },
            }
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

    pub fn init(io: std.Io, allocator: std.mem.Allocator, options: ParseOptions) !Session {
        if (options.max_errors == 0) return error.InvalidMaxErrors;
        if (options.recovery_window == 0) return error.InvalidRecoveryWindow;

        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        const reader_buffer = try allocator.alloc(u8, read_chunk_size * 2);
        errdefer allocator.free(reader_buffer);

        const chunk_buffer = try allocator.alloc(u8, read_chunk_size);
        errdefer allocator.free(chunk_buffer);

        const node_allocator = if (parser.is_ast_enabled)
            try data_structures.ASTAllocator.initCapacity(allocator)
        else {};
        errdefer if (parser.is_ast_enabled) allocator.free(node_allocator.memory);

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
            },
            .reader_buffer = reader_buffer,
            .chunk_buffer = chunk_buffer,
            .node_allocator = node_allocator,
            .verbosity = if (builtin.mode == .Debug) options.verbosity else {},
        };
    }

    pub fn deinit(self: *Session) void {
        if (self.owned_input) |owned_input| {
            self.allocator.free(owned_input);
            self.owned_input = null;
        }
        if (parser.is_ast_enabled) {
            self.allocator.free(self.node_allocator.memory);
        }
        self.allocator.free(self.chunk_buffer);
        self.allocator.free(self.reader_buffer);
        self.arena.deinit();
    }

    pub fn parseBytes(self: *Session, input: []const u8, input_path: ?[]const u8) !ParseResult {
        if (self.owned_input) |owned_input| {
            self.allocator.free(owned_input);
            self.owned_input = null;
        }

        const owned_input = try self.allocator.alloc(u8, input.len + 1);
        @memcpy(owned_input[0..input.len], input);
        owned_input[input.len] = 0;
        self.owned_input = owned_input;

        var context_value = self._makeContext(.{ .bytes = .{ .input = owned_input } }, input_path);
        return try self._parseContext(&context_value);
    }

    pub fn parseSentinelBytes(self: *Session, input: [:0]const u8, input_path: ?[]const u8) !ParseResult {
        if (self.owned_input) |owned_input| {
            self.allocator.free(owned_input);
            self.owned_input = null;
        }

        var context_value = self._makeContext(.{ .bytes = .{ .input = input[0 .. input.len + 1] } }, input_path);
        return try self._parseContext(&context_value);
    }

    pub fn parseFile(self: *Session, file: std.Io.File, input_path: ?[]const u8) !ParseResult {
        var context_value = self._makeContext(.{ .file = file.reader(self.io, self.reader_buffer) }, input_path);
        return try self._parseContext(&context_value);
    }

    pub fn astAllocator(self: *Session) if (parser.is_ast_enabled) *data_structures.ASTAllocator else void {
        if (parser.is_ast_enabled) {
            return &self.node_allocator;
        }
        return {};
    }

    pub fn lastDiagnostic(self: *const Session) ?ParseDiagnostic {
        return self.runtime_context.last_diagnostic;
    }

    pub fn syntaxErrorCount(self: *const Session) usize {
        return self.runtime_context.syntax_error_count;
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
        _ = self.arena.reset(.retain_capacity);
        self.runtime_context.last_diagnostic = null;
        self.runtime_context.syntax_error_count = 0;
        self.runtime_context.syntax_recovery_position = null;
        self.runtime_context.explicit_recovery_position = null;
        self.runtime_context.explicit_recovery_target_id = null;
        self.runtime_context.pending_syntax_error_site = null;
        data_structures.context.activateRuntimeContext(&self.runtime_context);
        defer data_structures.context.deactivateRuntimeContext(&self.runtime_context);

        try context_value.reset();
        return try parser.parseWithResult(context_value);
    }
};

test "galley LL grammar error hook returns custom guidance" {
    var context: data_structures.Context = undefined;
    const diagnostic: ParseDiagnostic = .{ .syntax = .{
        .line = 51,
        .column = 1,
        .unexpected_token = "F",
        .expected_tokens = &.{ "\x00", "\n", "#", "|" },
        .context = .{ .while_parsing = "RightHandSidesTail" },
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

test "structured syntax recovery renders in plain and ANSI diagnostics" {
    const diagnostic: ParseDiagnostic = .{ .syntax = .{
        .line = 3,
        .column = 7,
        .unexpected_token = "?",
        .expected_tokens = &.{"x"},
        .context = .{ .while_parsing = "Child" },
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
