const builtin = @import("builtin");
const std = @import("std");
const root = @import("galley");

fn ByteAlignedUnsigned(comptime maximum: usize) type {
    var bits: u16 = 8;
    while (maximum > (@as(comptime_int, 1) << @intCast(bits)) - 1) {
        bits += 8;
    }
    return std.meta.Int(.unsigned, bits);
}

pub const Token = struct {
    pub const max_length = 65500;
    pub const Length = ByteAlignedUnsigned(root.parser.longest_terminal_length);
    comptime {
        std.debug.assert(root.parser.longest_terminal_length <= Token.max_length);
    }

    buffer: if (root.config.indentation_syntax) [Token.max_length * 2]u8 else []u8 = undefined,
    head: usize = 0,
    len: Length = 0,

    const Self = @This();

    pub inline fn resetBuffered(self: *Self) void {
        comptime std.debug.assert(root.config.indentation_syntax);
        self.head = 0;
        self.len = 0;
    }

    pub inline fn resetInput(self: *Self, buffer: []u8) void {
        comptime std.debug.assert(!root.config.indentation_syntax);
        self.buffer = buffer;
        self.head = 0;
        self.len = 0;
    }

    pub inline fn append(self: *Self, char: u8) void {
        std.debug.assert(self.len < Self.max_length);
        self.buffer[self.head] = char;
        self.head += 1;
        self.len += 1;
    }

    pub inline fn appendNoCopy(self: *Self) void {
        std.debug.assert(self.len < Self.max_length);
        self.head += 1;
        self.len += 1;
    }

    pub inline fn pop(self: *Self, amount: Length) void {
        std.debug.assert(self.len >= amount);

        self.len -= amount;
        if (comptime root.config.indentation_syntax) {
            if (self.head - self.len >= Self.max_length) {
                const remaining = self.len;
                @memcpy(self.buffer[0..remaining], self.items());
                self.head = remaining;
            }
        }
    }

    pub inline fn items(self: *const Self) []const u8 {
        return self.buffer[self.head - self.len .. self.head];
    }

    pub inline fn at(self: *const Self, offset: Length) u8 {
        std.debug.assert(offset < self.len);
        return self.buffer[self.head + offset - self.len];
    }
};

test "token length type is byte-aligned and fits the longest terminal" {
    try std.testing.expectEqual(@as(usize, 8), @bitSizeOf(ByteAlignedUnsigned(0)));
    try std.testing.expectEqual(@as(usize, 8), @bitSizeOf(ByteAlignedUnsigned(255)));
    try std.testing.expectEqual(@as(usize, 16), @bitSizeOf(ByteAlignedUnsigned(256)));
    try std.testing.expectEqual(@as(usize, 16), @bitSizeOf(ByteAlignedUnsigned(65500)));
    try std.testing.expectEqual(@as(usize, 24), @bitSizeOf(ByteAlignedUnsigned(65536)));
    try std.testing.expect(std.math.maxInt(Token.Length) >= root.parser.longest_terminal_length);
}
