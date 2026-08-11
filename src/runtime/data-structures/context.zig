const builtin = @import("builtin");
const root = @import("galley");
const std = @import("std");
const data_structures = root.data_structures;
const string_utilities = root.string_utilities;

const NewlineSummary = struct {
    count: u32 = 0,
    last: ?usize = null,
};

fn summarizeNewlines(input: []const u8) NewlineSummary {
    var summary = NewlineSummary{};
    for (input, 0..) |byte, index| {
        switch (byte) {
            '\n', '\x01', '\x02' => {
                summary.count += 1;
                summary.last = index;
            },
            else => {},
        }
    }
    return summary;
}

pub const RuntimeContext = struct {
    io: std.Io,
    input_path: ?[]const u8 = null,
    language_options: root.config.Options = .{},
    arena_allocator: std.mem.Allocator,
    last_diagnostic: ?root.ParseDiagnostic = null,
    max_errors: usize = 10,
    recovery_window: usize = 500,
    syntax_error_count: usize = 0,
    syntax_recovery_position: ?usize = null,
    explicit_recovery_position: ?usize = null,
    explicit_recovery_target_id: ?usize = null,
    pending_syntax_error_site: ?usize = null,
    syntax_error_reporter: ?root.SyntaxErrorMessageReporter = null,
};

var runtime_registry_mutex: std.atomic.Mutex = .unlocked;
var runtime_registry_head: ?*RuntimeContextRegistration = null;

fn lockRuntimeRegistry() void {
    while (!runtime_registry_mutex.tryLock()) std.atomic.spinLoopHint();
}

pub const Context = struct {
    pub const BytesSource = struct {
        input: []const u8,
        offset: usize = 0,
    };

    pub const Source = union(enum) {
        file: std.Io.File.Reader,
        bytes: BytesSource,
    };

    token: data_structures.Token = .{},
    source: Source = .{ .bytes = .{ .input = &[_]u8{0} } },
    chunk_buffer: []u8 = undefined,
    input_read_failed: bool = false,

    // These fields are defined only when non-indentation input streaming is enabled.
    file_input: if (root.input_streaming_enabled and !root.config.indentation_syntax and root.source_retention_enabled) []u8 else void = if (root.input_streaming_enabled and !root.config.indentation_syntax and root.source_retention_enabled) &.{} else {},
    input_end: if (root.input_streaming_enabled and !root.config.indentation_syntax) usize else void = if (root.input_streaming_enabled and !root.config.indentation_syntax) 0 else {},
    loaded_end: if (root.input_streaming_enabled and !root.config.indentation_syntax) usize else void = if (root.input_streaming_enabled and !root.config.indentation_syntax) 0 else {},
    window_base: if (root.sliding_input_enabled and !root.config.indentation_syntax) usize else void = if (root.sliding_input_enabled and !root.config.indentation_syntax) 0 else {},
    input_eof: if (root.sliding_input_enabled and !root.config.indentation_syntax) bool else void = if (root.sliding_input_enabled and !root.config.indentation_syntax) false else {},

    // These fields are defined only when indentation syntax is enabled
    indent_width: if (root.config.indentation_syntax) u16 else void = if (root.config.indentation_syntax) 0 else {},
    current_indent: if (root.config.indentation_syntax) u16 else void = if (root.config.indentation_syntax) 0 else {},
    indentation_error: if (root.config.indentation_syntax) bool else void = if (root.config.indentation_syntax) false else {},
    seek: if (root.config.indentation_syntax) usize else void = if (root.config.indentation_syntax) 0 else {},
    read_bytes: if (root.config.indentation_syntax) usize else void = if (root.config.indentation_syntax) 0 else {},

    // These fields are defined only when ast is enabled
    node_allocator: if (root.parser.is_ast_enabled) *data_structures.ASTAllocator else void = if (root.parser.is_ast_enabled) undefined else {},

    // These fields are defined based on build mode and generated-parser options.
    verbosity: if (builtin.mode == .Debug) usize else void = if (builtin.mode == .Debug) 0 else {},

    line: if (root.position_tracking_enabled) u32 else void = if (root.position_tracking_enabled) 1 else {},
    column: if (root.position_tracking_enabled) u32 else void = if (root.position_tracking_enabled) 1 else {},

    line_offsets: if (root.position_tracking_enabled)
        data_structures.Offsets
    else
        void = if (root.position_tracking_enabled) .{} else {},
    column_offsets: if (root.position_tracking_enabled)
        data_structures.Offsets
    else
        void = if (root.position_tracking_enabled) .{} else {},

    const Self = @This();

    pub noinline fn runtime(self: *Self) *RuntimeContext {
        return registeredRuntimeContext(self);
    }

    pub noinline fn runtimeConst(self: *const Self) *const RuntimeContext {
        return registeredRuntimeContext(self);
    }

    pub inline fn verbosityLevel(self: *const Self) usize {
        if (comptime builtin.mode == .Debug) {
            return self.verbosity;
        }
        return 0;
    }

    pub fn recordSyntaxDiagnostic(
        self: *@This(),
        diagnostic_context: root.SyntaxDiagnosticContext,
        expected_tokens: []const []const u8,
    ) !void {
        if (self.input_read_failed) return error.ReadFailed;
        if (comptime root.config.indentation_syntax) {
            if (self.indentation_error) return error.IndentationError;
        }
        const unexpected_token = try self.runtime().arena_allocator.dupe(u8, self.diagnosticTokenItems());
        self.runtime().last_diagnostic = .{
            .syntax = .{
                .line = if (comptime root.position_tracking_enabled) self.line else 0,
                .column = if (comptime root.position_tracking_enabled) self.column else 0,
                .unexpected_token = unexpected_token,
                .expected_tokens = expected_tokens,
                .context = diagnostic_context,
            },
        };
        self.runtime().syntax_error_count += 1;
    }

    fn diagnosticTokenItems(self: *Self) []const u8 {
        const original = self.token.items();
        if (original.len == 0 or original[0] < 0x80) return original;

        const sequence_length = std.unicode.utf8ByteSequenceLength(original[0]) catch return original;
        if (sequence_length > original.len) {
            _ = self.head(u8, @intCast(sequence_length - 1));
        }

        const loaded = self.token.items();
        if (sequence_length > loaded.len) return original;
        _ = std.unicode.utf8Decode(loaded[0..sequence_length]) catch return original;
        return loaded[0..@max(original.len, sequence_length)];
    }

    pub inline fn syntaxErrorLimitReached(self: *const Self) bool {
        return self.runtimeConst().syntax_error_count >= self.runtimeConst().max_errors;
    }

    pub inline fn hasSyntaxErrors(self: *const Self) bool {
        return self.runtimeConst().syntax_error_count != 0;
    }

    pub inline fn recoveryWindow(self: *const Self) usize {
        return self.runtimeConst().recovery_window;
    }

    pub inline fn beginSyntaxRecovery(self: *Self) bool {
        const runtime_context = self.runtime();
        const position: usize = self.pos();
        if (runtime_context.syntax_recovery_position == position) return false;
        runtime_context.syntax_recovery_position = position;
        return true;
    }

    pub inline fn finishSyntaxRecovery(self: *Self) void {
        self.runtime().syntax_recovery_position = null;
    }

    pub fn tryExplicitRecovery(
        self: *Self,
        target_id: usize,
        target: root.SyntaxRecoveryTarget,
        points: []const root.SyntaxRecoveryPoint,
    ) !bool {
        if (self.syntaxErrorLimitReached() or points.len == 0) return false;

        const runtime_context = self.runtime();
        const position: usize = self.pos();
        if (runtime_context.explicit_recovery_position == position and
            runtime_context.explicit_recovery_target_id == target_id)
        {
            return false;
        }

        const lookahead = try self.recoveryLookahead();
        if (lookahead.len == 0 or lookahead[0] == 0) return false;
        const upper = @min(runtime_context.recovery_window, lookahead.len);
        var winning_point: ?usize = null;
        var winning_offset: usize = 0;
        var offset: usize = 0;
        while (offset < upper) : (offset += 1) {
            if (lookahead[offset] == 0) break;
            for (points, 0..) |point, point_index| {
                if (point.terminal.len > lookahead.len - offset or
                    !std.mem.eql(u8, lookahead[offset..][0..point.terminal.len], point.terminal))
                {
                    continue;
                }
                if (winning_point == null or point.terminal.len > points[winning_point.?].terminal.len) {
                    winning_point = point_index;
                    winning_offset = offset;
                }
            }
            if (winning_point != null) break;
        }

        const point = if (winning_point) |index| points[index] else return false;
        runtime_context.explicit_recovery_position = position;
        runtime_context.explicit_recovery_target_id = target_id;
        const skip_amount = winning_offset + if (point.@"resume" == .after) point.terminal.len else 0;
        self.skipRecoveryInput(skip_amount);
        try self.attachSyntaxRecovery(.{
            .target = target,
            .terminal = point.terminal,
            .@"resume" = point.@"resume",
        });
        return true;
    }

    pub fn attachSyntaxRecovery(self: *Self, recovery: root.SyntaxRecovery) !void {
        const diagnostic = &(self.runtime().last_diagnostic orelse return error.MissingSyntaxDiagnostic);
        switch (diagnostic.*) {
            .syntax => |*syntax| syntax.recovery = recovery,
            .indentation => return error.MissingSyntaxDiagnostic,
        }
    }

    pub inline fn setPendingSyntaxErrorSite(self: *Self, site: usize) void {
        self.runtime().pending_syntax_error_site = site;
    }

    pub inline fn pendingSyntaxErrorSite(self: *const Self) ?usize {
        return self.runtimeConst().pending_syntax_error_site;
    }

    pub inline fn clearPendingSyntaxErrorSite(self: *Self) void {
        self.runtime().pending_syntax_error_site = null;
    }

    pub fn skipRecoveryInput(self: *Self, amount: usize) void {
        for (0..amount) |_| {
            _ = self.head(u8, 0);
            self.releaseToken(1);
        }
    }

    /// Captures raw source bytes from the current source position through the
    /// next occurrence of `terminator`, consuming them without lexing,
    /// indentation processing, or escape decoding. On success the parser
    /// resumes immediately after the terminator with line and column advanced
    /// over the captured bytes. When `terminator` never reappears the parse
    /// fails with `error.UnterminatedRawString`, mirroring recovery points by
    /// carrying the expected terminator bytes in the recorded diagnostic.
    ///
    /// `!verbatim` capture requires retained source, so the generated parser
    /// disables input streaming and every token buffer already holds the
    /// complete input.
    pub fn captureVerbatim(self: *Self, terminator: []const u8) !void {
        const body_start = self.currentTokenSourceOffset();
        const body_end = if (comptime root.config.indentation_syntax)
            findVerbatimTerminatorEnd(self.chunk_buffer, body_start, terminator) orelse {
                try self.recordUnterminatedVerbatim(terminator);
                return error.UnterminatedRawString;
            }
        else
            findVerbatimTerminatorEnd(self.token.buffer, body_start, terminator) orelse {
                try self.recordUnterminatedVerbatim(terminator);
                return error.UnterminatedRawString;
            };

        if (comptime root.config.indentation_syntax) {
            // Any cleaned tokens already buffered from the captured region are
            // part of the opaque raw body; discard them (together with their
            // line/column offsets) and resume lexing from the terminator end.
            self.indentation_error = false;
            if (comptime root.position_tracking_enabled) {
                const discard = @min(self.token.len, self.line_offsets.len);
                if (discard != 0) {
                    self.line_offsets.pop(@intCast(discard));
                    self.column_offsets.pop(@intCast(discard));
                }
            }
            self.token.resetBuffered();
            self.seek = body_end;
            self.current_indent = @intCast(lineIndentOf(self.chunk_buffer, body_start) / @max(self.indent_width, 1));
            if (comptime root.position_tracking_enabled) {
                advanceVerbatimPositions(&self.line, &self.column, self.chunk_buffer[body_start..body_end]);
            }
        } else {
            const discard = self.token.len;
            self.token.head = body_end;
            self.token.len = 0;
            if (comptime root.position_tracking_enabled) {
                if (discard != 0) self.column_offsets.pop(discard);
                advanceVerbatimPositions(&self.line, &self.column, self.token.buffer[body_start..body_end]);
            }
        }
    }

    /// Reports an unterminated `!verbatim` capture with the expected terminator
    /// bytes as the diagnostic's expected tokens.
    fn recordUnterminatedVerbatim(self: *Self, terminator: []const u8) !void {
        if (self.input_read_failed) return error.ReadFailed;
        if (comptime root.config.indentation_syntax) {
            if (self.indentation_error) return error.IndentationError;
        }
        const arena = self.runtime().arena_allocator;
        const unexpected_token = try arena.dupe(u8, self.diagnosticTokenItems());
        const expected_tokens = try arena.alloc([]const u8, 1);
        expected_tokens[0] = try arena.dupe(u8, terminator);
        self.runtime().last_diagnostic = .{
            .syntax = .{
                .line = if (comptime root.position_tracking_enabled) self.line else 0,
                .column = if (comptime root.position_tracking_enabled) self.column else 0,
                .unexpected_token = unexpected_token,
                .expected_tokens = expected_tokens,
                .context = .none,
            },
        };
        self.runtime().syntax_error_count += 1;
    }

    fn advanceVerbatimPositions(line: *u32, column: *u32, captured: []const u8) void {
        var newlines: u32 = 0;
        var last_newline: ?usize = null;
        for (captured, 0..) |byte, index| {
            if (byte == '\n') {
                newlines += 1;
                last_newline = index;
            }
        }
        line.* += newlines;
        if (last_newline) |suffix_start| {
            column.* = @intCast(captured.len - suffix_start);
        } else {
            column.* += @intCast(captured.len);
        }
    }

    fn findVerbatimTerminatorEnd(buffer: []const u8, start: usize, terminator: []const u8) ?usize {
        const region_end = std.mem.indexOfScalarPos(u8, buffer, start, 0) orelse buffer.len;
        const terminator_at = std.mem.indexOf(u8, buffer[start..region_end], terminator) orelse return null;
        return start + terminator_at + terminator.len;
    }

    /// Number of leading spaces on the line containing `offset`.
    fn lineIndentOf(buffer: []const u8, offset: usize) usize {
        var line_start = offset;
        while (line_start > 0 and buffer[line_start - 1] != '\n' and buffer[line_start - 1] != 0) : (line_start -= 1) {}
        var indent: usize = 0;
        while (line_start + indent < buffer.len and buffer[line_start + indent] == ' ') : (indent += 1) {}
        return indent;
    }

    pub fn recoveryLookahead(self: *Self) ![]const u8 {
        const required = self.runtime().recovery_window +| root.parser.longest_terminal_length;

        if (comptime !root.config.indentation_syntax) {
            if (comptime root.input_streaming_enabled) {
                self.loadInputUpTo(if (comptime root.sliding_input_enabled)
                    @min(required, root.input_window_size)
                else
                    required);
            }
            const start: usize = self.token.head - self.token.len;
            const available_end = if (comptime root.input_streaming_enabled)
                @min(self.loaded_end, self.input_end + 1)
            else
                self.token.buffer.len;
            const available = self.token.buffer[start..available_end];
            const sentinel = std.mem.indexOfScalar(u8, available, 0) orelse available.len - 1;
            return available[0..@min(available.len, @min(required, sentinel + 1))];
        }

        var output = std.ArrayList(u8).empty;
        try output.ensureTotalCapacity(self.runtime().arena_allocator, required);
        try output.appendSlice(self.runtime().arena_allocator, self.token.items());
        if (std.mem.indexOfScalar(u8, output.items, 0) != null) return output.items;

        var seek = self.seek;
        var current_indent = self.current_indent;
        var indent_width = self.indent_width;
        while (output.items.len < required) {
            while (self.chunk_buffer[seek] == '\n') {
                seek += 1;
                var line_spaces: u16 = 0;
                while (self.chunk_buffer[seek] == ' ') {
                    seek += 1;
                    line_spaces += 1;
                }

                if (indent_width == 0) {
                    indent_width = line_spaces;
                } else if (line_spaces % indent_width != 0) {
                    break;
                }
                const new_indent = if (indent_width == 0) 0 else line_spaces / indent_width;
                if (new_indent == current_indent) {
                    try output.append(self.runtime().arena_allocator, '\n');
                } else if (new_indent > current_indent) {
                    try output.appendNTimes(self.runtime().arena_allocator, '\x01', new_indent - current_indent);
                } else {
                    try output.appendNTimes(self.runtime().arena_allocator, '\x02', current_indent - new_indent);
                }
                current_indent = new_indent;
                if (output.items.len >= required) break;
            }
            if (output.items.len >= required) break;

            const byte = self.chunk_buffer[seek];
            try output.append(self.runtime().arena_allocator, byte);
            if (byte == 0) break;
            seek += 1;
        }
        return output.items;
    }

    pub fn releaseToken(self: *@This(), length: data_structures.Token.Length) void {
        if (comptime root.position_tracking_enabled) {
            if (comptime root.config.indentation_syntax) {
                self.line += self.line_offsets.sum(0, length);
            }
            self.column += self.column_offsets.sum(0, length);
            const newlines = summarizeNewlines(self.token.items()[0..length]);
            if (newlines.last) |last_newline| {
                self.column = self.column_offsets.sum(@intCast(last_newline), length);
            }
            if (comptime !root.config.indentation_syntax) {
                self.line += newlines.count;
            }

            if (comptime root.config.indentation_syntax) {
                self.line_offsets.pop(length);
            }
            self.column_offsets.pop(length);
        }
        self.token.pop(length);
    }

    pub fn read(self: *@This()) void {
        const bytes_read = switch (self.source) {
            .file => |*reader| reader.interface.readSliceShort(self.chunk_buffer) catch |err| switch (err) {
                error.ReadFailed => failed: {
                    self.input_read_failed = true;
                    break :failed 0;
                },
            },
            .bytes => |*bytes| bytes_read: {
                if (bytes.offset >= bytes.input.len) {
                    break :bytes_read 0;
                }
                const remaining = bytes.input.len - bytes.offset;
                const amount = @min(remaining, self.chunk_buffer.len);
                @memcpy(self.chunk_buffer[0..amount], bytes.input[bytes.offset..][0..amount]);
                bytes.offset += amount;
                break :bytes_read amount;
            },
        };

        if (bytes_read < self.chunk_buffer.len) {
            self.chunk_buffer[bytes_read] = '\x00';
        }
    }

    pub fn reset(self: *@This()) !void {
        self.input_read_failed = false;
        switch (self.source) {
            .file => |*reader| try reader.seekTo(0),
            .bytes => |*bytes| bytes.offset = 0,
        }
        if (comptime root.config.indentation_syntax) {
            self.read_bytes = 0;
            self.seek = 0;
            self.indent_width = 0;
            self.current_indent = 0;
            self.indentation_error = false;
        }
        if (comptime root.position_tracking_enabled) {
            self.line = 1;
            self.column = 1;
            self.line_offsets.reset();
            self.column_offsets.reset();
        }
        if (comptime root.parser.is_ast_enabled) {
            self.node_allocator.reset();
        }
        if (comptime root.config.indentation_syntax) {
            self.token.resetBuffered();
            if (comptime root.input_streaming_enabled) {
                self.read();
            } else switch (self.source) {
                .file => self.read(),
                .bytes => |bytes| self.chunk_buffer = @constCast(bytes.input),
            }
        } else if (comptime root.sliding_input_enabled) {
            self.input_end = 0;
            self.loaded_end = 0;
            self.window_base = 0;
            self.input_eof = false;
            self.token.resetInput(self.chunk_buffer);
        } else if (comptime root.input_streaming_enabled) switch (self.source) {
            .file => {
                self.loaded_end = 0;
                self.token.resetInput(self.file_input);
            },
            .bytes => |bytes| {
                self.input_end = bytes.input.len - 1;
                self.loaded_end = bytes.input.len;
                self.token.resetInput(@constCast(bytes.input));
            },
        } else switch (self.source) {
            .file => {
                self.token.resetInput(self.chunk_buffer);
                self.read();
            },
            .bytes => |bytes| self.token.resetInput(@constCast(bytes.input)),
        }
    }

    pub inline fn advanceInputWithCheck(self: *@This()) void {
        comptime std.debug.assert(root.config.indentation_syntax);

        if (self.seek == self.chunk_buffer.len - 1) {
            self.read_bytes += @intCast(self.chunk_buffer.len);
            self.seek = 0;
            self.read();
        } else {
            self.seek += 1;
        }
    }

    pub inline fn advanceInputWithoutCheck(self: *@This()) void {
        comptime std.debug.assert(root.config.indentation_syntax);

        self.seek +%= 1;
    }

    pub inline fn advanceInput(self: *@This()) void {
        comptime std.debug.assert(root.config.indentation_syntax);

        if (comptime root.input_streaming_enabled) {
            self.advanceInputWithCheck();
        } else {
            self.advanceInputWithoutCheck();
        }
    }

    /// Appends a token to the indentation-mode token stream, recording the
    /// source offset the token was lexed from.
    inline fn appendToken(self: *@This(), char: u8, source_offset: usize) void {
        self.token.appendSource(char, source_offset);
    }

    pub inline fn advanceLexer(self: *@This()) void {
        if (comptime root.config.indentation_syntax) {
            const chunk_buffer = self.chunk_buffer;
            while (chunk_buffer[self.seek] == '\n') {
                const boundary_source = self.read_bytes + self.seek;
                self.advanceInput();
                var line_spaces: u16 = 0;

                while (chunk_buffer[self.seek] == ' ') {
                    self.advanceInput();
                    line_spaces += 1;
                }

                if (self.indent_width == 0) {
                    self.indent_width = line_spaces;
                } else if (line_spaces % self.indent_width != 0) {
                    self.recordIndentationDiagnostic(line_spaces);
                    while (self.token.len < @max(root.parser.longest_terminal_length, 1)) {
                        self.appendToken(0, self.read_bytes + self.seek);
                    }
                    return;
                }
                const new_indent = if (self.indent_width == 0) 0 else line_spaces / self.indent_width;
                if (comptime root.position_tracking_enabled and root.config.indentation_syntax) {
                    self.line_offsets.append(1);
                }
                if (new_indent == self.current_indent) {
                    if (comptime root.position_tracking_enabled) {
                        self.column_offsets.append(@as(u32, line_spaces) + 1);
                    }
                    self.appendToken('\n', boundary_source);
                } else {
                    if (new_indent > self.current_indent) {
                        for (0..new_indent - self.current_indent) |index| {
                            if (comptime root.position_tracking_enabled) {
                                if (comptime root.config.indentation_syntax) {
                                    if (index != 0) {
                                        self.line_offsets.append(0);
                                    }
                                }
                                self.column_offsets.append(@as(u32, new_indent) * @as(u32, self.indent_width) + 1);
                            }
                            self.appendToken('\x01', boundary_source);
                        }
                    } else if (new_indent < self.current_indent) {
                        for (0..self.current_indent - new_indent) |index| {
                            if (comptime root.position_tracking_enabled) {
                                if (comptime root.config.indentation_syntax) {
                                    if (index != 0) {
                                        self.line_offsets.append(0);
                                    }
                                }
                                self.column_offsets.append(@as(u32, new_indent) * @as(u32, self.indent_width) + 1);
                            }
                            self.appendToken('\x02', boundary_source);
                        }
                    }
                    self.current_indent = new_indent;
                }
            }
        }

        if (comptime root.position_tracking_enabled) {
            if (comptime root.config.indentation_syntax) {
                self.line_offsets.append(0);
            }
            self.column_offsets.append(1);
        }
        if (comptime root.config.indentation_syntax) {
            self.appendToken(self.chunk_buffer[self.seek], self.read_bytes + self.seek);
            self.advanceInput();
        } else {
            self.token.appendNoCopy();
        }

        if (comptime builtin.mode == .Debug) {
            if (self.verbosityLevel() > 1) {
                std.debug.print("\n{d}:{d}:\"{f}\"\n", .{
                    if (comptime root.position_tracking_enabled) self.line else 0,
                    if (comptime root.position_tracking_enabled) self.column else 0,
                    string_utilities.fmtString(self.token.items()),
                });
            }
        }
    }

    fn recordIndentationDiagnostic(self: *Self, line_spaces: u16) void {
        comptime std.debug.assert(root.config.indentation_syntax);

        self.indentation_error = true;
        const runtime_context = self.runtime();
        const diagnostic: root.ParseDiagnostic = .{ .indentation = .{
            .line = if (comptime root.position_tracking_enabled) self.line + 1 else 0,
            .column = if (comptime root.position_tracking_enabled) 1 else 0,
            .spaces = line_spaces,
            .indentation_width = self.indent_width,
        } };
        runtime_context.last_diagnostic = diagnostic;
    }

    inline fn ensureInputLoaded(self: *@This(), needed_len: usize) void {
        comptime std.debug.assert(root.input_streaming_enabled and !root.config.indentation_syntax);

        self.loadInputUpTo(needed_len);
        const token_start: usize = self.token.head - self.token.len;
        std.debug.assert(token_start + needed_len <= self.loaded_end);
    }

    inline fn loadInputUpTo(self: *@This(), needed_len: usize) void {
        comptime std.debug.assert(root.input_streaming_enabled and !root.config.indentation_syntax);

        const token_start: usize = self.token.head - self.token.len;
        const required_end = token_start + needed_len;
        if (required_end > self.loaded_end) {
            @branchHint(.unlikely);
            self.refillInput(needed_len);
        }
    }

    fn readInput(self: *@This(), destination: []u8) usize {
        return switch (self.source) {
            .file => |*reader| reader.interface.readSliceShort(destination) catch |err| switch (err) {
                error.ReadFailed => failed: {
                    self.input_read_failed = true;
                    break :failed 0;
                },
            },
            .bytes => |*bytes| bytes_read: {
                if (bytes.offset >= bytes.input.len) break :bytes_read 0;
                const amount = @min(destination.len, bytes.input.len - bytes.offset);
                @memcpy(destination[0..amount], bytes.input[bytes.offset..][0..amount]);
                bytes.offset += amount;
                break :bytes_read amount;
            },
        };
    }

    noinline fn refillInput(self: *@This(), needed_len: usize) void {
        @branchHint(.cold);
        comptime std.debug.assert(root.input_streaming_enabled and !root.config.indentation_syntax);

        if (comptime root.sliding_input_enabled) {
            const token_start: usize = self.token.head - self.token.len;
            if (token_start != 0) {
                std.debug.assert(token_start <= self.input_end);
                const remaining = self.input_end - token_start;
                std.mem.copyForwards(
                    u8,
                    self.token.buffer[0..remaining],
                    self.token.buffer[token_start..self.input_end],
                );
                self.window_base += token_start;
                self.token.head -= @intCast(token_start);
                self.input_end = remaining;
                self.loaded_end = remaining;
            }

            while (needed_len > self.loaded_end and !self.input_eof) {
                std.debug.assert(self.input_end < root.input_window_size);
                const bytes_read = self.readInput(self.token.buffer[self.input_end..root.input_window_size]);
                if (bytes_read == 0) {
                    self.input_eof = true;
                    const padded_end = self.input_end + root.input_padding_size;
                    @memset(self.token.buffer[self.input_end..padded_end], 0);
                    self.loaded_end = padded_end;
                    break;
                }
                self.input_end += bytes_read;
                self.loaded_end = self.input_end;
            }
            return;
        }

        const required_end = @as(usize, self.token.head - self.token.len) + needed_len;
        const reader = switch (self.source) {
            .file => |*reader| reader,
            .bytes => unreachable,
        };

        while (self.loaded_end < required_end and self.loaded_end < self.input_end) {
            const target_end = @min(
                self.input_end,
                @max(required_end, self.loaded_end +| root.read_chunk_size),
            );
            const bytes_read = reader.interface.readSliceShort(self.token.buffer[self.loaded_end..target_end]) catch |err| switch (err) {
                error.ReadFailed => failed: {
                    self.input_read_failed = true;
                    break :failed 0;
                },
            };
            if (bytes_read == 0) {
                self.input_end = self.loaded_end;
                break;
            }
            self.loaded_end += bytes_read;
        }

        if (self.loaded_end == self.input_end) {
            const padded_end = @min(self.token.buffer.len, self.input_end + root.input_padding_size);
            @memset(self.token.buffer[self.input_end..padded_end], 0);
            self.loaded_end = padded_end;
        }
    }

    pub fn head(self: *@This(), comptime T: type, offset: data_structures.Token.Length) T {
        const bytes_needed = comptime @divExact(@bitSizeOf(T), 8);
        const needed_len = offset + bytes_needed;
        if (comptime root.input_streaming_enabled and !root.config.indentation_syntax) {
            self.ensureInputLoaded(needed_len);
        }
        while (self.token.len < needed_len) {
            self.advanceLexer();
        }

        const base_ptr = self.token.items().ptr + offset;

        if (comptime T == u8) {
            return base_ptr[0];
        }

        const array_ptr: *const [bytes_needed]u8 = @ptrCast(base_ptr);
        return std.mem.readInt(T, array_ptr, .big);
    }

    pub inline fn pos(self: *const Self) usize {
        if (comptime root.config.indentation_syntax) {
            return self.read_bytes + self.seek;
        }
        if (comptime root.sliding_input_enabled) {
            return self.window_base + self.token.head - self.token.len;
        }
        return self.token.head - self.token.len;
    }

    /// Source offset of the token the parser is about to consume, or of the
    /// byte it is about to lex when no front-run token is buffered. This is the
    /// source position where the next consumed token begins (equivalently, where
    /// the previously consumed token ended), and is the coordinate space node
    /// text spans should be captured in.
    pub inline fn currentTokenSourceOffset(self: *const Self) usize {
        if (comptime root.config.indentation_syntax) {
            if (self.token.len == 0) return self.read_bytes + self.seek;
            return self.token.firstSourceOffset();
        }
        return self.pos();
    }

    /// Reads the raw source bytes of a source-coordinate span. In indentation
    /// mode the token stream is a cleaned/rewritten view of the input, so node
    /// text spans cannot be resolved against it; this reads the original
    /// source instead.
    fn readSourceSlice(self: *const Self, start: usize, length: usize) []const u8 {
        const end = start + length;
        switch (self.source) {
            .bytes => |bytes| return bytes.input[start..end],
            .file => {
                if (comptime !root.input_streaming_enabled) {
                    return self.chunk_buffer[start..end];
                }
                const mutable = @constCast(self);
                const span = self.runtimeConst().arena_allocator.alloc(u8, length) catch return &[_]u8{};
                const frontier = self.read_bytes + self.seek;
                mutable.source.file.interface.seekTo(start) catch return span[0..0];
                var filled: usize = 0;
                while (filled < length) {
                    const n = mutable.source.file.interface.readSliceShort(span[filled..]) catch break;
                    if (n == 0) break;
                    filled += n;
                }
                mutable.source.file.interface.seekTo(frontier) catch {};
                return span[0..filled];
            },
        }
    }

    pub inline fn getTextSlice(self: *const Self, start: usize, length: usize) []const u8 {
        if (comptime root.config.indentation_syntax) {
            return self.readSourceSlice(start, length);
        }
        return self.token.buffer[start .. start + length];
    }

    pub inline fn diagnosticInput(self: *const Self) []const u8 {
        if (comptime root.config.indentation_syntax) return self.chunk_buffer;
        if (comptime root.input_streaming_enabled) {
            return self.token.buffer[0..@min(self.loaded_end, self.input_end + 1)];
        }
        return self.token.buffer;
    }
};

test "newline summary counts every marker and retains the final position" {
    const summary = summarizeNewlines("a\n\nb\x01c\x02\x02d");
    try std.testing.expectEqual(@as(u32, 5), summary.count);
    try std.testing.expectEqual(@as(?usize, 7), summary.last);
}

pub const RuntimeContextRegistration = struct {
    context_address: usize,
    runtime_context: *RuntimeContext,
    next: ?*RuntimeContextRegistration = null,
    is_registered: bool = false,

    pub fn init(context: *Context, runtime_context: *RuntimeContext) RuntimeContextRegistration {
        return .{
            .context_address = @intFromPtr(context),
            .runtime_context = runtime_context,
        };
    }

    pub fn register(self: *RuntimeContextRegistration) void {
        lockRuntimeRegistry();
        defer runtime_registry_mutex.unlock();

        std.debug.assert(!self.is_registered);
        self.next = runtime_registry_head;
        runtime_registry_head = self;
        self.is_registered = true;
    }

    pub fn unregister(self: *RuntimeContextRegistration) void {
        lockRuntimeRegistry();
        defer runtime_registry_mutex.unlock();

        var link = &runtime_registry_head;
        while (link.*) |registration| {
            if (registration == self) {
                link.* = registration.next;
                self.next = null;
                self.is_registered = false;
                return;
            }
            link = &registration.next;
        }
        unreachable;
    }
};

fn registeredRuntimeContext(context: *const Context) *RuntimeContext {
    const context_address = @intFromPtr(context);

    lockRuntimeRegistry();
    defer runtime_registry_mutex.unlock();

    var registration = runtime_registry_head;
    while (registration) |entry| : (registration = entry.next) {
        if (entry.context_address == context_address) return entry.runtime_context;
    }
    @panic("parser context has no active runtime registration");
}
