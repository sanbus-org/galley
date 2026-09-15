const std = @import("std");
const parser = @import("parser-under-test");

fn parseAll(input: []const u8) !void {
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
}

fn parseEndColumn(input: []const u8) !u32 {
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
    return parsed.result.column;
}

fn parseFails(input: []const u8) !void {
    try std.testing.expectError(error.SyntaxError, parser.parseBytes(
        std.testing.io,
        std.testing.allocator,
        input,
        .{},
    ));
}

test "newline after block end: one-liner and wrapped one-liner parse" {
    try parseAll("{x}");
    try parseAll("x");
}

test "newline after block end: unwrapped block then sibling uses leftover as separator" {
    try parseAll("x\n>\n  x\nx");
}

test "newline after block end: wrapped block closer skips leftover" {
    try parseAll("{>\n  x\n}");
}

test "newline after block end: leftover does not inflate the end column" {
    const one_character_line = try parseEndColumn("x");
    try std.testing.expectEqual(one_character_line, try parseEndColumn("x\n>\n  x\nx"));
    try std.testing.expectEqual(one_character_line, try parseEndColumn("{>\n  x\n}"));
}

test "newline after block end: optional block after one-liner then sibling" {
    try parseAll("x+>\n  x\nx");
}

test "newline after block end: mix of unwrapped, operator, and wrapped blocks" {
    try parseAll("x\nx\n>\n  x\nx+>\n  x\nx\n{>\n  x\n}");
}

test "newline after block end: jammed one-liners are rejected" {
    try parseFails("xx");
}

test "newline after block end: real newline before closer is not skipped" {
    try parseFails("{x\n}");
}
