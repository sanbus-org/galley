const std = @import("std");
const parser = @import("parser-under-test");

const Expected = struct {
    name: []const u8,
    start: usize,
    end: usize,
};

test "no-AST indentation node text spans are exact source offsets" {
    if (comptime parser.parser.is_ast_enabled) return;
    if (comptime !parser.config.indentation_syntax) return;

    parser.procedures.resetCaptures();
    const input = "State\n  Value\nFinal";
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, input.len), parsed.result.parsed_bytes);

    const expected = [_]Expected{
        .{ .name = "Program", .start = 0, .end = input.len },
        .{ .name = "UppercaseId", .start = 0, .end = 5 },
        .{ .name = "UppercaseId", .start = 8, .end = 13 },
        .{ .name = "UppercaseId", .start = 14, .end = input.len },
    };

    var matches: usize = 0;
    var i: usize = 0;
    const count = parser.procedures.captureCount();
    while (i < count) : (i += 1) {
        const capture = parser.procedures.captureAt(i);
        const name = capture.name[0..capture.name_len];
        for (expected) |exp| {
            if (std.mem.eql(u8, name, exp.name) and capture.start == exp.start and capture.start + capture.length == exp.end) {
                const text = capture.text[0..capture.text_len];
                try std.testing.expectEqualStrings(input[exp.start..exp.end], text);
                matches += 1;
            }
        }
    }
    try std.testing.expectEqual(expected.len, matches);
}
