const std = @import("std");

pub const Payload = struct {
    objects: u32 = 0,
    arrays: u32 = 0,
    nulls: u32 = 0,
};

pub fn decodeStringContent(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    var decoded: std.ArrayList(u8) = .empty;
    errdefer decoded.deinit(allocator);

    var index: usize = 0;
    while (index < encoded.len) {
        if (encoded[index] != '\\') {
            try decoded.append(allocator, encoded[index]);
            index += 1;
            continue;
        }

        if (index + 1 >= encoded.len) return error.InvalidJsonEscape;
        switch (encoded[index + 1]) {
            '"' => try decoded.append(allocator, '"'),
            '\\' => try decoded.append(allocator, '\\'),
            '/' => try decoded.append(allocator, '/'),
            'b' => try decoded.append(allocator, 0x08),
            'f' => try decoded.append(allocator, 0x0c),
            'n' => try decoded.append(allocator, '\n'),
            'r' => try decoded.append(allocator, '\r'),
            't' => try decoded.append(allocator, '\t'),
            'u' => {
                const first = try parseHexCodeUnit(encoded, index + 2);
                if (first >= 0xd800 and first <= 0xdbff) {
                    if (index + 12 > encoded.len or
                        encoded[index + 6] != '\\' or
                        encoded[index + 7] != 'u')
                    {
                        return error.InvalidJsonSurrogatePair;
                    }
                    const second = try parseHexCodeUnit(encoded, index + 8);
                    if (second < 0xdc00 or second > 0xdfff) return error.InvalidJsonSurrogatePair;

                    const codepoint: u21 = @intCast(
                        0x10000 +
                            ((@as(u32, first) - 0xd800) << 10) +
                            (@as(u32, second) - 0xdc00),
                    );
                    try appendCodepoint(allocator, &decoded, codepoint);
                    index += 12;
                    continue;
                }
                if (first >= 0xdc00 and first <= 0xdfff) return error.InvalidJsonSurrogatePair;

                try appendCodepoint(allocator, &decoded, @intCast(first));
                index += 6;
                continue;
            },
            else => return error.InvalidJsonEscape,
        }
        index += 2;
    }

    return decoded.toOwnedSlice(allocator);
}

fn parseHexCodeUnit(encoded: []const u8, start: usize) !u16 {
    if (start + 4 > encoded.len) return error.InvalidJsonUnicodeEscape;

    var result: u16 = 0;
    for (encoded[start..][0..4]) |byte| {
        result = (result << 4) | (hexNibble(byte) orelse return error.InvalidJsonUnicodeEscape);
    }
    return result;
}

fn hexNibble(byte: u8) ?u16 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}

fn appendCodepoint(
    allocator: std.mem.Allocator,
    decoded: *std.ArrayList(u8),
    codepoint: u21,
) !void {
    var buffer: [4]u8 = undefined;
    const length = std.unicode.utf8Encode(codepoint, &buffer) catch return error.InvalidJsonUnicodeEscape;
    try decoded.appendSlice(allocator, buffer[0..length]);
}

test "JSON string decoding preserves raw UTF-8 and decodes escapes" {
    const decoded = try decodeStringContent(
        std.testing.allocator,
        "سلام 😀\\u0000\\u007f\\u0080\\u07ff\\u0800\\uffff\\ud800\\udc00",
    );
    defer std.testing.allocator.free(decoded);

    try std.testing.expectEqualSlices(
        u8,
        "سلام 😀\x00\x7f\xc2\x80\xdf\xbf\xe0\xa0\x80\xef\xbf\xbf\xf0\x90\x80\x80",
        decoded,
    );
}

test "JSON string decoding rejects malformed escapes and surrogate pairs" {
    inline for (&.{
        "\\q",
        "\\u",
        "\\u123",
        "\\uxxxx",
        "\\ud800",
        "\\ud800\\u0000",
        "\\udc00",
    }) |encoded| {
        try std.testing.expectError(
            switch (encoded[1]) {
                'u' => if (encoded.len >= 6 and
                    ((encoded[2] == 'd' and encoded[3] >= '8') or
                        (encoded[2] == 'D' and encoded[3] >= '8')))
                    error.InvalidJsonSurrogatePair
                else
                    error.InvalidJsonUnicodeEscape,
                else => error.InvalidJsonEscape,
            },
            decodeStringContent(std.testing.allocator, encoded),
        );
    }
}
