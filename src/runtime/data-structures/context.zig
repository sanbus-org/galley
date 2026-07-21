const builtin = @import("builtin");
const root = @import("galley");
const std = @import("std");
const data_structures = root.data_structures;
const string_utilities = root.string_utilities;

fn findScalarLast(comptime T: type, slice: []const T, value: T) ?Context.Size {
    var i = slice.len;
    while (i > 0) {
        i -= 1;
        if (slice[i] == value) {
            if (comptime builtin.mode == .Debug) {
                std.debug.assert(i <= std.math.maxInt(Context.Size));
            }
            return @intCast(i);
        }
    }
    return null;
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
};

var active_runtime_context: ?*RuntimeContext = null;

pub fn activateRuntimeContext(runtime_context_: *RuntimeContext) void {
    active_runtime_context = runtime_context_;
}

pub fn deactivateRuntimeContext(runtime_context_: *RuntimeContext) void {
    std.debug.assert(active_runtime_context == runtime_context_);
    active_runtime_context = null;
}

fn runtimeContext() *RuntimeContext {
    return active_runtime_context orelse unreachable;
}

pub const Context = struct {
    pub const Size = root.parser.input_size_cap;

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

    // These fields are defined only when indentation syntax is enabled
    indent_width: if (root.config.indentation_syntax) u16 else void = if (root.config.indentation_syntax) 0 else {},
    current_indent: if (root.config.indentation_syntax) u16 else void = if (root.config.indentation_syntax) 0 else {},
    seek: if (root.config.indentation_syntax) Size else void = if (root.config.indentation_syntax) 0 else {},
    read_bytes: if (root.config.indentation_syntax) Size else void = if (root.config.indentation_syntax) 0 else {},

    // These fields are defined only when ast is enabled
    node_allocator: if (root.parser.is_ast_enabled) *data_structures.ASTAllocator else void = if (root.parser.is_ast_enabled) undefined else {},

    // These fields are defined based on `builtin.mode`
    verbosity: if (builtin.mode == .Debug) usize else void = if (builtin.mode == .Debug) 0 else {},

    line: if (builtin.mode != .ReleaseFast) u32 else void = if (builtin.mode != .ReleaseFast) 1 else {},
    column: if (builtin.mode != .ReleaseFast) u32 else void = if (builtin.mode != .ReleaseFast) 1 else {},

    line_offsets: if (builtin.mode != .ReleaseFast)
        data_structures.Offsets
    else
        void = if (builtin.mode != .ReleaseFast) .{} else {},
    column_offsets: if (builtin.mode != .ReleaseFast)
        data_structures.Offsets
    else
        void = if (builtin.mode != .ReleaseFast) .{} else {},

    const Self = @This();

    pub inline fn runtime(self: *Self) *RuntimeContext {
        _ = self;
        return runtimeContext();
    }

    pub inline fn runtimeConst(self: *const Self) *const RuntimeContext {
        _ = self;
        return runtimeContext();
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
        const unexpected_token = try self.runtime().arena_allocator.dupe(u8, self.token.items());
        self.runtime().last_diagnostic = .{
            .syntax = .{
                .line = if (comptime builtin.mode != .ReleaseFast) self.line else 0,
                .column = if (comptime builtin.mode != .ReleaseFast) self.column else 0,
                .unexpected_token = unexpected_token,
                .expected_tokens = expected_tokens,
                .context = diagnostic_context,
            },
        };
        self.runtime().syntax_error_count += 1;
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

    pub fn recoveryLookahead(self: *Self) ![]const u8 {
        const required = @min(
            self.runtime().recovery_window +| root.parser.longest_terminal_length,
            std.math.maxInt(Size),
        );

        if (comptime !root.config.indentation_syntax) {
            const start: usize = self.token.head - self.token.len;
            const available = self.token.buffer[start..];
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

    pub fn releaseToken(self: *@This(), length: Size) void {
        if (comptime builtin.mode != .ReleaseFast) {
            if (comptime root.config.indentation_syntax) {
                self.line += self.line_offsets.sum(0, length);
            }
            self.column += self.column_offsets.sum(0, length);
            var last_newline: i16 = -1;
            for ("\n\x01\x02") |newline_char| {
                if (findScalarLast(u8, self.token.items()[0..length], newline_char)) |index| {
                    if (index > last_newline) {
                        self.column = self.column_offsets.sum(index, length);
                        last_newline = @intCast(index);
                    }
                    if (comptime !root.config.indentation_syntax) {
                        self.line += 1;
                    }
                }
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
                error.ReadFailed => return,
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
        switch (self.source) {
            .file => |*reader| try reader.seekTo(0),
            .bytes => |*bytes| bytes.offset = 0,
        }
        if (comptime root.config.indentation_syntax) {
            self.read_bytes = 0;
            self.seek = 0;
            self.indent_width = 0;
            self.current_indent = 0;
        }
        if (comptime builtin.mode != .ReleaseFast) {
            self.line = 1;
            self.column = 1;
            self.line_offsets.reset();
            self.column_offsets.reset();
        }
        if (comptime root.parser.is_ast_enabled) {
            self.node_allocator.reset();
        }
        if (comptime root.config.indentation_syntax) {
            self.token.reset(self.chunk_buffer);
            self.read();
        } else switch (self.source) {
            .file => {
                self.token.reset(self.chunk_buffer);
                self.read();
            },
            .bytes => |bytes| self.token.reset(@constCast(bytes.input)),
        }
    }

    pub inline fn advanceInputWithCheck(self: *@This()) void {
        if (comptime root.config.indentation_syntax) {
            if (self.seek == root.read_chunk_size - 1) {
                self.read_bytes += self.seek;
                self.seek = 0;
                self.read();
            }
            self.seek +%= 1;
        }
    }

    pub inline fn advanceInputWithoutCheck(self: *@This()) void {
        if (comptime root.config.indentation_syntax) {
            self.seek +%= 1;
        }
    }

    pub inline fn advanceInput(self: *@This()) void {
        if (comptime root.config.indentation_syntax) {
            self.advanceInputWithoutCheck();
        }
    }

    pub inline fn advanceLexer(self: *@This()) void {
        if (comptime root.config.indentation_syntax) {
            const chunk_buffer = self.chunk_buffer;
            while (chunk_buffer[self.seek] == '\n') {
                self.advanceInput();
                var line_spaces: u16 = 0;

                while (chunk_buffer[self.seek] == ' ') {
                    self.advanceInput();
                    line_spaces += 1;
                }

                if (self.indent_width == 0) {
                    self.indent_width = line_spaces;
                } else if (line_spaces % self.indent_width != 0) {
                    std.log.err("\x1b[35mIndentationError at line {d}:\n\x1b[0mInvalid number of spaces {d} which is not divisible by previousely detected indentation width of \x1b[31m\"{d}\"\x1b[0m.", .{
                        if (comptime builtin.mode != .ReleaseFast) self.line + 1 else 0,
                        line_spaces,
                        self.indent_width,
                    });

                    unreachable;
                }
                const new_indent = if (self.indent_width == 0) 0 else line_spaces / self.indent_width;
                if (comptime builtin.mode != .ReleaseFast and root.config.indentation_syntax) {
                    self.line_offsets.append(1);
                }
                if (new_indent == self.current_indent) {
                    if (comptime builtin.mode != .ReleaseFast) {
                        self.column_offsets.append(@intCast(line_spaces + 1));
                    }
                    self.token.append('\n');
                } else {
                    if (new_indent > self.current_indent) {
                        for (0..new_indent - self.current_indent) |index| {
                            if (comptime builtin.mode != .ReleaseFast) {
                                if (comptime root.config.indentation_syntax) {
                                    if (index != 0) {
                                        self.line_offsets.append(0);
                                    }
                                }
                                self.column_offsets.append(@intCast(new_indent * self.indent_width + 1));
                            }
                            self.token.append('\x01');
                        }
                    } else if (new_indent < self.current_indent) {
                        for (0..self.current_indent - new_indent) |index| {
                            if (comptime builtin.mode != .ReleaseFast) {
                                if (comptime root.config.indentation_syntax) {
                                    if (index != 0) {
                                        self.line_offsets.append(0);
                                    }
                                }
                                self.column_offsets.append(@intCast(new_indent * self.indent_width + 1));
                            }
                            self.token.append('\x02');
                        }
                    }
                    self.current_indent = new_indent;
                }
            }
        }

        if (comptime builtin.mode != .ReleaseFast) {
            if (comptime root.config.indentation_syntax) {
                self.line_offsets.append(0);
            }
            self.column_offsets.append(1);
        }
        if (comptime root.config.indentation_syntax) {
            self.token.append(self.chunk_buffer[self.seek]);
            self.advanceInput();
        } else {
            self.token.appendNoCopy();
        }

        if (comptime builtin.mode == .Debug) {
            if (self.verbosityLevel() > 1) {
                std.debug.print("\n{d}:{d}:\"{f}\"\n", .{
                    if (comptime builtin.mode != .ReleaseFast) self.line else 0,
                    if (comptime builtin.mode != .ReleaseFast) self.column else 0,
                    string_utilities.fmtString(self.token.items()),
                });
            }
        }
    }

    pub fn head(self: *@This(), comptime T: type, offset: Size) T {
        const bytes_needed = comptime @divExact(@bitSizeOf(T), 8);
        const needed_len = offset + bytes_needed;
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

    pub inline fn pos(self: *Self) Size {
        return if (comptime root.config.indentation_syntax)
            self.read_bytes + self.seek
        else
            self.token.head - self.token.len;
    }

    pub inline fn getTextSlice(self: *const Self, start: Size, length: Size) []const u8 {
        return self.token.buffer[start .. start + length];
    }
};
