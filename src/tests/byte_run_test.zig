const std = @import("std");
const parser = @import("parser-under-test");

// `_Run` is a hidden byte run (`letter`, `digit` or `_` repeated), which LL
// emits as one loop. These pin that it consumes the same language.

fn parseAll(input: []const u8) !void {
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
}

test "byte run: empty run at end of input" {
    try parseAll("a");
}

test "byte run: long run of every member class at end of input" {
    try parseAll("abc_DEF_012_xyz_9");
}

test "byte run: run ended by a terminator" {
    try parseAll("ab1:\n    c\nd");
}

test "byte run: run ended by a dedent and its trailing block-end newline" {
    try parseAll("a:\n    bcd\nef_1");
}

test "byte run: run ended by a double dedent" {
    try parseAll("a:\n    b:\n        cc_2\nd");
}

test "byte run: a byte outside the run is rejected" {
    try std.testing.expectError(error.SyntaxError, parser.parseBytes(std.testing.io, std.testing.allocator, "ab%", .{}));
}
