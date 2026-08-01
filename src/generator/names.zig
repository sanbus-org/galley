const std = @import("std");

/// Converts a grammar symbol's byte spelling into the readable stem used in
/// generated parser identifiers and diagnostics.
pub fn readableSymbolName(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    for (bytes) |byte| {
        switch (byte) {
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            0x0b => try out.appendSlice(allocator, "\\x0b"),
            0x0c => try out.appendSlice(allocator, "\\x0c"),
            0x00...0x08, 0x0e...0x1f, 0x7f...0xff => {
                const escaped = try std.fmt.allocPrint(allocator, "\\x{x:0>2}", .{byte});
                defer allocator.free(escaped);
                try out.appendSlice(allocator, escaped);
            },
            else => try out.append(allocator, byte),
        }
    }
    return out.toOwnedSlice(allocator);
}

/// Escapes arbitrary bytes into a stable Zig identifier fragment.
pub fn safeIdentifier(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    for (bytes) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '_') {
            try out.append(allocator, byte);
        } else {
            const escaped = try std.fmt.allocPrint(allocator, "_x{d}", .{byte});
            defer allocator.free(escaped);
            try out.appendSlice(allocator, escaped);
        }
    }
    return out.toOwnedSlice(allocator);
}

pub fn syntaxErrorFunctionName(
    allocator: std.mem.Allocator,
    comptime prefix: []const u8,
    stem: []const u8,
    site_index: usize,
) ![]const u8 {
    return std.fmt.allocPrint(allocator, "syntax_error_" ++ prefix ++ "{s}_{d}", .{ stem, site_index });
}

pub fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

test "readable symbol names preserve identifier-safe spellings" {
    const allocator = std.testing.allocator;
    const name = try readableSymbolName(allocator, "line\n\\");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("line\\n\\\\", name);
}

test "safe identifiers escape non identifier bytes" {
    const allocator = std.testing.allocator;
    const name = try safeIdentifier(allocator, "a-b");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("a_x45b", name);
}
