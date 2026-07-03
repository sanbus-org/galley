const std = @import("std");
const json_parser = @import("json_parser");

test "parse bytes through generated parser library API" {
    var parsed = try json_parser.parseBytes(std.testing.io, std.testing.allocator, "{}", .{});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 2), parsed.result.parsed_bytes);
}

test "reusable generated parser session parses multiple byte slices" {
    var session = try json_parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    const first = try session.parseBytes("{}", null);
    try std.testing.expectEqual(@as(usize, 2), first.parsed_bytes);

    const second = try session.parseBytes("[]", null);
    try std.testing.expectEqual(@as(usize, 2), second.parsed_bytes);
}
