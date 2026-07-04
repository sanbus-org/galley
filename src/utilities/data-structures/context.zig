const builtin = @import("builtin");
const root = @import("galley");
const std = @import("std");
const data_structures = root.data_structures;
const string_utilities = root.string_utilities;

fn find_scalar_last(comptime T: type, slice: []const T, value: T) ?Context.Size {
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
};

var active_runtime_context: ?*RuntimeContext = null;

pub fn activate_runtime_context(runtime_context_: *RuntimeContext) void {
    active_runtime_context = runtime_context_;
}

pub fn deactivate_runtime_context(runtime_context_: *RuntimeContext) void {
    std.debug.assert(active_runtime_context == runtime_context_);
    active_runtime_context = null;
}

fn runtime_context() *RuntimeContext {
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
    indent_width: if (root.procedures.indentation_syntax) u16 else void = if (root.procedures.indentation_syntax) 0 else {},
    current_indent: if (root.procedures.indentation_syntax) u16 else void = if (root.procedures.indentation_syntax) 0 else {},
    seek: if (root.procedures.indentation_syntax) Size else void = if (root.procedures.indentation_syntax) 0 else {},
    read_bytes: if (root.procedures.indentation_syntax) Size else void = if (root.procedures.indentation_syntax) 0 else {},

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
        return runtime_context();
    }

    pub inline fn runtimeConst(self: *const Self) *const RuntimeContext {
        _ = self;
        return runtime_context();
    }

    pub inline fn verbosityLevel(self: *const Self) usize {
        if (comptime builtin.mode == .Debug) {
            return self.verbosity;
        }
        return 0;
    }

    pub fn release_token(self: *@This(), length: Size) void {
        if (comptime builtin.mode != .ReleaseFast) {
            if (comptime root.procedures.indentation_syntax) {
                self.line += self.line_offsets.sum(0, length);
            }
            self.column += self.column_offsets.sum(0, length);
            var last_newline: i16 = -1;
            for ("\n\x01\x02") |newline_char| {
                if (find_scalar_last(u8, self.token.items()[0..length], newline_char)) |index| {
                    if (index > last_newline) {
                        self.column = self.column_offsets.sum(index, length);
                        last_newline = @intCast(index);
                    }
                    if (comptime !root.procedures.indentation_syntax) {
                        self.line += 1;
                    }
                }
            }

            if (comptime root.procedures.indentation_syntax) {
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
        if (comptime root.procedures.indentation_syntax) {
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
        if (comptime root.procedures.indentation_syntax) {
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

    pub inline fn advance_input_with_check(self: *@This()) void {
        if (comptime root.procedures.indentation_syntax) {
            if (self.seek == root.read_chunk_size - 1) {
                self.read_bytes += self.seek;
                self.seek = 0;
                self.read();
            }
            self.seek +%= 1;
        }
    }

    pub inline fn advance_input_without_check(self: *@This()) void {
        if (comptime root.procedures.indentation_syntax) {
            self.seek +%= 1;
        }
    }

    pub inline fn advance_input(self: *@This()) void {
        if (comptime root.procedures.indentation_syntax) {
            self.advance_input_without_check();
        }
    }

    pub inline fn advance_lexer(self: *@This()) void {
        if (comptime root.procedures.indentation_syntax) {
            const chunk_buffer = self.chunk_buffer;
            while (chunk_buffer[self.seek] == '\n') {
                self.advance_input();
                var line_spaces: u16 = 0;

                while (chunk_buffer[self.seek] == ' ') {
                    self.advance_input();
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
                if (comptime builtin.mode != .ReleaseFast and root.procedures.indentation_syntax) {
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
                                if (comptime root.procedures.indentation_syntax) {
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
                                if (comptime root.procedures.indentation_syntax) {
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
            if (comptime root.procedures.indentation_syntax) {
                self.line_offsets.append(0);
            }
            self.column_offsets.append(1);
        }
        if (comptime root.procedures.indentation_syntax) {
            self.token.append(self.chunk_buffer[self.seek]);
            self.advance_input();
        } else {
            self.token.append_no_copy();
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
            self.advance_lexer();
        }

        const base_ptr = self.token.items().ptr + offset;

        if (comptime T == u8) {
            return base_ptr[0];
        }

        const array_ptr: *const [bytes_needed]u8 = @ptrCast(base_ptr);
        return std.mem.readInt(T, array_ptr, .big);
    }

    pub inline fn pos(self: *Self) Size {
        return if (comptime root.procedures.indentation_syntax)
            self.read_bytes + self.seek
        else
            self.token.head - self.token.len;
    }

    pub inline fn get_text_slice(self: *const Self, start: Size, length: Size) []const u8 {
        return self.token.buffer[start .. start + length];
    }
};
