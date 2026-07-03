const std = @import("std");
const ll_json_parser = @import("ll-json");
const lr_json_parser = @import("lr-json");

test "parse bytes through generated ll parser library API" {
    var parsed = try ll_json_parser.parseBytes(std.testing.io, std.testing.allocator, "{}", .{});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 2), parsed.result.parsed_bytes);
}

test "reusable generated ll parser session parses multiple byte slices" {
    var session = try ll_json_parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    const first = try session.parseBytes("{}", null);
    try std.testing.expectEqual(@as(usize, 2), first.parsed_bytes);

    const second = try session.parseBytes("[]", null);
    try std.testing.expectEqual(@as(usize, 2), second.parsed_bytes);
}

test "parse bytes through generated lr parser library API" {
    var parsed = try lr_json_parser.parseBytes(std.testing.io, std.testing.allocator, "{}", .{});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 2), parsed.result.parsed_bytes);
}

test "reusable generated lr parser session parses multiple byte slices" {
    var session = try lr_json_parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    const first = try session.parseBytes("{}", null);
    try std.testing.expectEqual(@as(usize, 2), first.parsed_bytes);

    const second = try session.parseBytes("[]", null);
    try std.testing.expectEqual(@as(usize, 2), second.parsed_bytes);
}
