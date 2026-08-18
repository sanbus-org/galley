const std = @import("std");
const parser = @import("parser-under-test");

test "self-repeating loop stops on a follow token sharing the terminal prefix" {
    const input = "1 + 2 < 3";
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
}

test "self-repeating loop consumes consecutive repetitions" {
    const input = "1 + 2 - 1 < 3";
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
}
