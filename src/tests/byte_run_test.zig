const std = @import("std");
const parser = @import("parser-under-test");

// `_Run` is a hidden byte run (`letter`, `digit` or `_` repeated), which LL
// emits as one loop. These pin that it consumes the same language.
// The grammar also serves as a small indentation grammar for the lexer's
// read-ahead of the rest of a line.

fn ignoreDiagnostic(_: []const u8) void {}

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

test "an indent jump that fills the position buffers leaves no room to read ahead" {
    // The first indented line sets the indent width to one space; the next
    // line jumps 127 levels, so its block starts and first byte fill the
    // 128-entry line-offset buffer before the rest of the line is read.
    const spaces: [128]u8 = @splat(' ');
    const input = "a:\n b:\n" ++ spaces ++ "cd";
    try std.testing.expectError(error.SyntaxError, parser.parseBytes(std.testing.io, std.testing.allocator, input, .{ .syntax_error_reporter = &ignoreDiagnostic }));
}

fn expectUnexpectedToken(input: []const u8, expected: []const u8) !void {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .max_errors = 1, .syntax_error_reporter = &ignoreDiagnostic });
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes(input, null));
    var read_guard = try session.readLatest();
    defer read_guard.deinit();
    const diagnostic = read_guard.lastDiagnostic() orelse return error.MissingDiagnostic;
    const syntax = switch (diagnostic) {
        .syntax => |syntax| syntax,
        .semantic, .indentation, .hook => return error.ExpectedSyntaxDiagnostic,
    };
    try std.testing.expectEqualStrings(expected, syntax.unexpected_token);
}

test "an unexpected token spans at most the longest terminal, not the rest of the line" {
    try expectUnexpectedToken("ab%cdef", "%");
}

test "an unexpected token still spans a whole UTF-8 character" {
    try expectUnexpectedToken("ab😀cdef", "😀");
}

test "a recovered parse does not count bytes the lexer only read ahead" {
    if (!parser.parser.is_error_recovery_enabled) return error.SkipZigTest;
    // The lexer reads `%abc` at once; LL stops at the `%` having consumed
    // nothing, while LR recovers to the end of the input.
    const input = "%abc\nde";
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .max_errors = 10, .syntax_error_reporter = &ignoreDiagnostic });
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes(input, null));
    var guard = try session.readCurrent();
    defer guard.deinit();
    const stopped_at: usize = if (parser.parser.parser_type == .ll) 0 else input.len;
    try std.testing.expectEqual(stopped_at, guard.result.parsed_bytes);
}
