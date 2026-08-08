const std = @import("std");
const parser = @import("parser-under-test");

test "verbatim capture with nullable tag tail restores enclosing block indentation" {
    const input =
        \\top
        \\  <<<T
        \\      body
        \\  T
        \\    x
        \\  y
    ;
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, input.len), parsed.result.parsed_bytes);
}
