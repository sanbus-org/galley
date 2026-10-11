const builtin = @import("builtin");
const std = @import("std");
const root = @import("galley");

fn ByteAlignedUnsigned(comptime maximum: usize) type {
    var bits: u16 = 8;
    while (maximum > (@as(comptime_int, 1) << @intCast(bits)) - 1) {
        bits += 8;
    }
    return @Int(.unsigned, bits);
}

/// Counts bytes of one terminal: lookahead offsets and released lengths.
const TerminalLength = ByteAlignedUnsigned(root.parser.longest_terminal_length);

/// The parser's view of the input. Indentation grammars lex into a buffer of
/// cleaned bytes; every other grammar reads the input itself through a cursor.
pub const Token = if (root.config.indentation_syntax) LexedToken else InputCursor;

/// The parser position in the input itself, for grammars without indentation
/// syntax. There is no lexing layer, so nothing is buffered ahead: lookahead
/// reads `buffer` past `cursor` directly, relying on the zero padding after the
/// input.
pub const InputCursor = struct {
    pub const Length = TerminalLength;

    buffer: []u8 = undefined,
    /// Index in `buffer` of the first byte the parser has not consumed.
    cursor: usize = 0,

    const Self = @This();

    pub inline fn reset(self: *Self, buffer: []u8) void {
        self.buffer = buffer;
        self.cursor = 0;
    }

    pub inline fn advance(self: *Self, amount: Length) void {
        self.cursor += amount;
    }

    /// The `length` bytes at the cursor.
    pub inline fn upcoming(self: *const Self, length: Length) []const u8 {
        return self.buffer[self.cursor..][0..length];
    }

    /// The character at the cursor within `buffer[cursor..end]`: one whole
    /// UTF-8 character when those bytes hold one, otherwise the first byte.
    pub fn character(self: *const Self, end: usize) []const u8 {
        const available = self.buffer[self.cursor..end];
        if (available.len == 0 or available[0] < 0x80) return available[0..@min(available.len, 1)];

        const sequence_length = std.unicode.utf8ByteSequenceLength(available[0]) catch return available[0..1];
        if (sequence_length > available.len) return available[0..1];
        _ = std.unicode.utf8Decode(available[0..sequence_length]) catch return available[0..1];
        return available[0..sequence_length];
    }
};

/// The indentation lexer's output: cleaned bytes, with the source offset each
/// was lexed from, buffered ahead of the parser.
pub const LexedToken = struct {
    pub const Length = TerminalLength;
    /// The most bytes buffered ahead of the parser at once.
    pub const max_length = 65500;
    comptime {
        std.debug.assert(root.parser.longest_terminal_length <= LexedToken.max_length);
    }

    /// The lexed bytes, in a `Storage` the session owns.
    buffer: []u8 = undefined,
    /// Parallel to `buffer`: the source offset each buffered byte was lexed
    /// from. Source offsets are independent of the cleaned/rewritten token
    /// stream, so node text spans can be resolved back to the original input.
    sources: []usize = &.{},
    /// Index in `buffer` of the first byte the parser has not consumed.
    start: usize = 0,
    /// Index in `buffer` past the last lexed byte.
    head: usize = 0,

    const Self = @This();

    /// How many lexed bytes the parser has not consumed.
    pub inline fn len(self: *const Self) usize {
        return self.head - self.start;
    }

    /// The indentation lexer's buffers, allocated once per session and
    /// attached to each parse's token. They are large (twice the longest
    /// token), so they must not live inline in the per-parse context.
    pub const Storage = struct {
        pub const capacity = LexedToken.max_length * 2;

        buffer: []u8,
        sources: []usize,

        pub fn init(allocator: std.mem.Allocator) !Storage {
            const buffer = try allocator.alloc(u8, capacity);
            errdefer allocator.free(buffer);
            return .{ .buffer = buffer, .sources = try allocator.alloc(usize, capacity) };
        }

        pub fn deinit(self: Storage, allocator: std.mem.Allocator) void {
            allocator.free(self.buffer);
            allocator.free(self.sources);
        }
    };

    pub inline fn attach(self: *Self, storage: Storage) void {
        self.buffer = storage.buffer;
        self.sources = storage.sources;
    }

    pub inline fn resetBuffered(self: *Self) void {
        self.head = 0;
        self.start = 0;
    }

    pub inline fn append(self: *Self, char: u8) void {
        std.debug.assert(self.len() < Self.max_length);
        self.buffer[self.head] = char;
        self.head += 1;
    }

    /// Appends a token together with the source offset it was lexed from.
    pub inline fn appendSource(self: *Self, char: u8, source: usize) void {
        std.debug.assert(self.len() < Self.max_length);
        self.buffer[self.head] = char;
        self.sources[self.head] = source;
        self.head += 1;
    }

    pub inline fn pop(self: *Self, amount: Length) void {
        std.debug.assert(self.len() >= amount);
        self.start += amount;
    }

    /// Moves the buffered bytes to the front once the consumed prefix reaches
    /// `max_length`. The lexer calls this before it appends, so `pop` is a
    /// single add and `start` stays below `max_length` while bytes are added.
    pub inline fn compact(self: *Self) void {
        if (self.start >= Self.max_length) {
            const remaining = self.len();
            std.mem.copyForwards(u8, self.buffer[0..remaining], self.items());
            std.mem.copyForwards(usize, self.sources[0..remaining], self.sources[self.start..self.head]);
            self.start = 0;
            self.head = remaining;
        }
    }

    /// How many more bytes can be appended.
    pub inline fn room(self: *const Self) usize {
        return max_length - self.len();
    }

    pub inline fn items(self: *const Self) []const u8 {
        return self.buffer[self.start..self.head];
    }

    /// Source offset of the first un-released token, i.e. the offset the next
    /// released token begins at.
    pub inline fn firstSourceOffset(self: *const Self) usize {
        return self.sources[self.start];
    }

    pub inline fn at(self: *const Self, offset: Length) u8 {
        std.debug.assert(offset < self.len());
        return self.buffer[self.start + offset];
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

test "input cursor character is one whole UTF-8 character or one byte" {
    var input = "a\xF0\x9F\x98\x80\xF0\x9F\x00".*;
    var cursor: InputCursor = .{};
    cursor.reset(&input);
    try std.testing.expectEqualStrings("a", cursor.character(input.len));
    cursor.advance(1);
    try std.testing.expectEqualStrings("\xF0\x9F\x98\x80", cursor.character(input.len));
    cursor.advance(4);
    // A truncated sequence reports its lead byte alone.
    try std.testing.expectEqualStrings("\xF0", cursor.character(input.len));
    cursor.advance(2);
    try std.testing.expectEqualStrings("\x00", cursor.character(input.len));
    try std.testing.expectEqualStrings("", cursor.character(cursor.cursor));
}
