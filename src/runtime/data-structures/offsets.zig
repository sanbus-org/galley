const root = @import("galley");
const std = @import("std");
const Context = @import("context.zig").Context;

pub const Offsets = struct {
    pub const max_length = @max(6, root.parser.longest_terminal_length);
    buffer: [Self.max_length * 2]u32 = undefined,
    head: Context.Size = 0,
    len: Context.Size = 0,

    const Self = @This();

    pub fn reset(self: *Self) void {
        self.head = 0;
        self.len = 0;
    }

    pub inline fn append(self: *Self, offset: u32) void {
        std.debug.assert(self.len < Self.max_length);

        self.buffer[self.head] = offset;
        self.head += 1;
        self.len += 1;
    }

    pub inline fn pop(self: *Self, amount: Context.Size) void {
        std.debug.assert(self.len >= amount);

        self.len -= amount;
        if (self.head - self.len >= Self.max_length) {
            @memcpy(self.buffer[0..self.len], self.buffer[self.head - self.len .. self.head]);
            self.head = self.len;
        }
    }

    pub inline fn sum(self: *const Self, start: Context.Size, end: Context.Size) u32 {
        var sum_: u32 = 0;
        for (self.buffer[self.head - self.len + start .. self.head - self.len + end]) |item| {
            sum_ += item;
        }
        return sum_;
    }
};

test "offsets preserve indentation columns wider than i8" {
    var offsets = Offsets{};
    offsets.append(1);
    offsets.append(512);
    try std.testing.expectEqual(@as(u32, 513), offsets.sum(0, 2));
}
