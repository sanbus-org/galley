const std = @import("std");
const parser = @import("parser-under-test");

const Expected = struct {
    name: []const u8,
    text: []const u8,
};

fn findCapture(name: []const u8) ?parser.procedures.Capture {
    var i: usize = 0;
    const count = parser.procedures.captureCount();
    while (i < count) : (i += 1) {
        const capture = parser.procedures.captureAt(i);
        if (std.mem.eql(u8, name, capture.name[0..capture.name_len])) return capture;
    }
    return null;
}

test "verbatim variable terminator consumes the raw body" {
    const input = "<<<EN\n{raw $ body}\nENtail";
    parser.procedures.resetCaptures();
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, input.len), parsed.result.parsed_bytes);

    const program = findCapture("Program") orelse return error.MissingCapture;
    try std.testing.expectEqual(@as(usize, 0), program.start);
    try std.testing.expectEqual(input.len, program.start + program.length);
    try std.testing.expectEqualStrings(input, program.text[0..program.text_len]);

    const upper_pair = findCapture("UpperPair") orelse return error.MissingCapture;
    try std.testing.expectEqualStrings("EN", upper_pair.text[0..upper_pair.text_len]);

    const tail = findCapture("LowerTail") orelse return error.MissingCapture;
    try std.testing.expectEqualStrings("tail", tail.text[0..tail.text_len]);
}

test "verbatim literal terminal terminator consumes the raw body" {
    const input = "]]]%%%{raw $ body}%%tail";
    parser.procedures.resetCaptures();
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, input.len), parsed.result.parsed_bytes);

    const program = findCapture("Program") orelse return error.MissingCapture;
    try std.testing.expectEqual(@as(usize, 0), program.start);
    try std.testing.expectEqual(input.len, program.start + program.length);
    try std.testing.expectEqualStrings(input, program.text[0..program.text_len]);

    const tail = findCapture("LowerTail") orelse return error.MissingCapture;
    try std.testing.expectEqualStrings("tail", tail.text[0..tail.text_len]);
}

test "verbatim raw body bytes are not lexed" {
    const input = "<<<EN\n$@# %^&*(){}[] 1|2\nENtail";
    parser.procedures.resetCaptures();
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, input.len), parsed.result.parsed_bytes);

    const tail = findCapture("LowerTail") orelse return error.MissingCapture;
    try std.testing.expectEqualStrings("tail", tail.text[0..tail.text_len]);
}

test "verbatim capture stops at the first reappearing terminator" {
    const input = "<<<EN\nbody ENtail";
    parser.procedures.resetCaptures();
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, input.len), parsed.result.parsed_bytes);

    const upper_pair = findCapture("UpperPair") orelse return error.MissingCapture;
    try std.testing.expectEqualStrings("EN", upper_pair.text[0..upper_pair.text_len]);

    const tail = findCapture("LowerTail") orelse return error.MissingCapture;
    try std.testing.expectEqualStrings("tail", tail.text[0..tail.text_len]);
}

test "verbatim terminator matching is case-sensitive" {
    const input = "<<<EN\nen en\nENtail";
    parser.procedures.resetCaptures();
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, input.len), parsed.result.parsed_bytes);

    const tail = findCapture("LowerTail") orelse return error.MissingCapture;
    try std.testing.expectEqualStrings("tail", tail.text[0..tail.text_len]);
}

test "verbatim capture of an empty raw body" {
    const input = "<<<EN\nENtail";
    parser.procedures.resetCaptures();
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, input.len), parsed.result.parsed_bytes);

    const tail = findCapture("LowerTail") orelse return error.MissingCapture;
    try std.testing.expectEqualStrings("tail", tail.text[0..tail.text_len]);
}

test "unterminated verbatim variable terminator reports UnterminatedRawString" {
    try std.testing.expectError(error.UnterminatedRawString, parser.parseBytes(
        std.testing.io,
        std.testing.allocator,
        "<<<EN\nno terminator here",
        .{},
    ));
}

test "unterminated verbatim literal terminator reports UnterminatedRawString" {
    try std.testing.expectError(error.UnterminatedRawString, parser.parseBytes(
        std.testing.io,
        std.testing.allocator,
        "]]]%% no terminator",
        .{},
    ));
}
