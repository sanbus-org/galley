const std = @import("std");
const parser = @import("parser-under-test");
const test_options = @import("test_options");

const valid_input = test_options.valid_input;
const malformed_input = test_options.malformed_input;
const multiple_errors_input = test_options.multiple_errors_input;
const small_window_error_count = test_options.small_window_error_count;
const diagnostic_line = test_options.diagnostic_line;
const diagnostic_column = test_options.diagnostic_column;
const unexpected_token_prefix = test_options.unexpected_token_prefix;
const expected_token = test_options.expected_token;
const error_recovery_enabled = test_options.error_recovery_enabled;

fn allocSentinel(input: []const u8) ![:0]u8 {
    const sentinel = try std.testing.allocator.allocSentinel(u8, input.len, 0);
    @memcpy(sentinel, input);
    return sentinel;
}

fn expectParsedAll(result: parser.ParseResult) !void {
    try std.testing.expectEqual(valid_input.len, result.parsed_bytes);
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, haystack, needle) != null);
}

fn expectSyntaxDiagnostic(session: *const parser.Session) !void {
    const diagnostic = session.lastDiagnostic() orelse return error.MissingDiagnostic;
    const syntax = switch (diagnostic) {
        .syntax => |syntax| syntax,
    };

    try std.testing.expectEqual(diagnostic_line, syntax.line);
    try std.testing.expectEqual(diagnostic_column, syntax.column);
    try std.testing.expect(std.mem.startsWith(u8, syntax.unexpected_token, unexpected_token_prefix));

    for (syntax.expected_tokens) |item| {
        if (std.mem.eql(u8, item, expected_token)) break;
    } else {
        return error.MissingExpectedToken;
    }

    const rendered = try parser.renderParseDiagnostic(std.testing.allocator, diagnostic, .plain);
    defer std.testing.allocator.free(rendered);

    const location = try std.fmt.allocPrint(std.testing.allocator, "SyntaxError at {d}:{d}", .{
        diagnostic_line,
        diagnostic_column,
    });
    defer std.testing.allocator.free(location);

    try expectContains(rendered, location);
    try expectContains(rendered, "Unexpected token");
    try expectContains(rendered, "Expected tokens:");
    try expectContains(rendered, expected_token);
}

test "generated_parser_error recovery capability" {
    try std.testing.expectEqual(error_recovery_enabled, parser.parser.is_error_recovery_enabled);
}

test "generated_parser_error parse bytes" {
    try std.testing.expectError(
        parser.ParseError.SyntaxError,
        parser.parseBytes(std.testing.io, std.testing.allocator, malformed_input, .{}),
    );
}

test "generated_parser_error parse sentinel bytes" {
    const input = try allocSentinel(malformed_input);
    defer std.testing.allocator.free(input);

    try std.testing.expectError(
        parser.ParseError.SyntaxError,
        parser.parseSentinelBytes(std.testing.io, std.testing.allocator, input, .{}),
    );
}

test "generated_parser_error reusable byte session recovers" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .max_errors = 1 });
    defer session.deinit();

    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes(malformed_input, null));
    try expectSyntaxDiagnostic(&session);
    try expectParsedAll(try session.parseBytes(valid_input, null));
    try std.testing.expectEqual(null, session.lastDiagnostic());
    try std.testing.expectEqual(@as(usize, 0), session.syntaxErrorCount());
}

test "generated_parser_error reusable sentinel session recovers" {
    const malformed = try allocSentinel(malformed_input);
    defer std.testing.allocator.free(malformed);
    const valid = try allocSentinel(valid_input);
    defer std.testing.allocator.free(valid);

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .max_errors = 1 });
    defer session.deinit();

    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseSentinelBytes(malformed, null));
    try expectSyntaxDiagnostic(&session);
    try expectParsedAll(try session.parseSentinelBytes(valid, null));
    try std.testing.expectEqual(null, session.lastDiagnostic());
    try std.testing.expectEqual(@as(usize, 0), session.syntaxErrorCount());
}

test "generated_parser_error reusable file session recovers" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "malformed", .data = malformed_input });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "valid", .data = valid_input });

    var malformed_file = try tmp.dir.openFile(std.testing.io, "malformed", .{ .mode = .read_only, .lock = .exclusive });
    defer malformed_file.close(std.testing.io);
    var valid_file = try tmp.dir.openFile(std.testing.io, "valid", .{ .mode = .read_only, .lock = .exclusive });
    defer valid_file.close(std.testing.io);

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .max_errors = 1 });
    defer session.deinit();

    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseFile(malformed_file, "malformed"));
    try expectSyntaxDiagnostic(&session);
    try expectParsedAll(try session.parseFile(valid_file, "valid"));
    try std.testing.expectEqual(null, session.lastDiagnostic());
    try std.testing.expectEqual(@as(usize, 0), session.syntaxErrorCount());
}

test "generated_parser_error reports multiple syntax errors" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes(multiple_errors_input, null));
    if (error_recovery_enabled) {
        try std.testing.expect(session.syntaxErrorCount() >= 2);
    } else {
        try std.testing.expectEqual(@as(usize, 1), session.syntaxErrorCount());
    }
}

test "generated_parser_error max errors restores fail fast" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .max_errors = 1 });
    defer session.deinit();

    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes(multiple_errors_input, null));
    try std.testing.expectEqual(@as(usize, 1), session.syntaxErrorCount());
}

test "generated_parser_error recovery window limits resynchronization" {
    if (!error_recovery_enabled) return error.SkipZigTest;

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .recovery_window = 1 });
    defer session.deinit();

    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes(multiple_errors_input, null));
    try std.testing.expectEqual(small_window_error_count, session.syntaxErrorCount());
}

test "generated_parser_error rejects zero recovery options" {
    try std.testing.expectError(
        error.InvalidMaxErrors,
        parser.Session.init(std.testing.io, std.testing.allocator, .{ .max_errors = 0 }),
    );
    try std.testing.expectError(
        error.InvalidRecoveryWindow,
        parser.Session.init(std.testing.io, std.testing.allocator, .{ .recovery_window = 0 }),
    );
}
