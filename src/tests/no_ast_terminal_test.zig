const std = @import("std");
const parser = @import("parser-under-test");

test "no-AST pure-terminal productions compile and parse" {
    if (comptime parser.parser.is_ast_enabled) return;
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, "+aa", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 3), parsed.result.parsed_bytes);
    try std.testing.expect(parsed.result.semantic_root != null);
    try std.testing.expectEqual(@as(?parser.data_structures.Node.Pointer, null), parsed.result.ast_root);
}
