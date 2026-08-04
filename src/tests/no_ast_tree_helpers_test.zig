const std = @import("std");
const parser = @import("parser-under-test");

test "no-AST tree helpers compile and run as no-ops" {
    if (comptime parser.parser.is_ast_enabled) return;
    const cases = [_]struct {
        input: []const u8,
        expected: usize,
    }{
        .{ .input = "a", .expected = 1 },
        .{ .input = "a,a", .expected = 2 },
    };
    for (cases) |case| {
        var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, case.input, .{});
        defer parsed.deinit();
        try std.testing.expectEqual(@as(usize, case.expected), parsed.result.semantic_root.?.value);
    }
}
