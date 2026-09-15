const std = @import("std");
const parser = @import("parser-under-test");

fn parseAll(input: []const u8) !void {
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
}

fn parseFails(input: []const u8) !void {
    try std.testing.expectError(error.SyntaxError, parser.parseBytes(
        std.testing.io,
        std.testing.allocator,
        input,
        .{},
    ));
}

test "newline after block end off: wrapped block still closes" {
    try parseAll("{>\n  x\n}");
}

test "newline after block end off: sibling after block is not a new_line row" {
    try parseFails("x\n>\n  x\nx");
}
