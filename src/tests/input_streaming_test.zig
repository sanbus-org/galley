const std = @import("std");
const parser = @import("parser-under-test");
const test_options = @import("test_options");

const window_crossing_padding = 1024;

fn allocSentinel(input: []const u8) ![:0]u8 {
    const sentinel = try std.testing.allocator.allocSentinel(u8, input.len, 0);
    @memcpy(sentinel, input);
    return sentinel;
}

fn makeWindowCrossingJson() ![]u8 {
    const spaces = parser.input_window_size - 512;
    const string_length = window_crossing_padding;
    const input = try std.testing.allocator.alloc(u8, 1 + spaces + 1 + string_length + 2);
    input[0] = '[';
    @memset(input[1 .. 1 + spaces], ' ');
    input[1 + spaces] = '"';
    @memset(input[2 + spaces .. 2 + spaces + string_length], 'a');
    input[input.len - 2] = '"';
    input[input.len - 1] = ']';
    return input;
}

fn makePositionJson(spaces: usize) ![]u8 {
    const suffix = "\n\"abc\"]";
    const input = try std.testing.allocator.alloc(u8, 1 + spaces + suffix.len);
    input[0] = '[';
    @memset(input[1 .. 1 + spaces], ' ');
    @memcpy(input[1 + spaces ..], suffix);
    return input;
}

fn makeRecoveryEofJson() ![]u8 {
    const input = try std.testing.allocator.alloc(u8, parser.input_window_size + window_crossing_padding);
    input[0] = '[';
    @memset(input[1..], ' ');
    return input;
}

fn makeIndentationInput(rule_count: usize) ![]u8 {
    const rule = "Rule:\n  - field: int\n";
    const input = try std.testing.allocator.alloc(u8, rule.len * rule_count);
    var offset: usize = 0;
    for (0..rule_count) |_| {
        @memcpy(input[offset..][0..rule.len], rule);
        offset += rule.len;
    }
    return input;
}

fn expectParsedAll(result: parser.ParseResult, input: []const u8) !void {
    try std.testing.expectEqual(input.len, result.parsed_bytes);
}

fn parseFile(input: []const u8) !parser.ParseResult {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "input", .data = input });
    var file = try tmp.dir.openFile(std.testing.io, "input", .{
        .mode = .read_only,
    });
    defer file.close(std.testing.io);

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    return try session.parseFile(file, "input");
}

test "input streaming generated capability" {
    try std.testing.expectEqual(test_options.streaming_enabled, parser.input_streaming_enabled);
    try std.testing.expectEqual(test_options.ast_large_input, parser.parser.is_ast_enabled);
    try std.testing.expectEqual(
        test_options.streaming_enabled and !test_options.ast_large_input,
        parser.sliding_input_enabled,
    );
    try std.testing.expectEqual(test_options.indentation, parser.config.indentation_syntax);
    try std.testing.expect(parser.position_tracking_enabled);
}

test "file read failures propagate through the parser API" {
    if (!test_options.read_error) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var directory = try tmp.dir.openFile(std.testing.io, ".", .{
        .mode = .read_only,
    });
    defer directory.close(std.testing.io);

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    try std.testing.expectError(error.ReadFailed, session.parseFile(directory, "directory"));
    var read_guard = try session.readLatest();
    defer read_guard.deinit();
    try std.testing.expectEqual(null, read_guard.lastDiagnostic());
}

test "non-streaming file parsing loads the complete input" {
    if (!test_options.non_streaming) return error.SkipZigTest;

    const input = try makeWindowCrossingJson();
    defer std.testing.allocator.free(input);
    try std.testing.expect(input.len > parser.read_chunk_size);

    try expectParsedAll(try parseFile(input), input);
}

test "input streaming sliding parses bytes, sentinel bytes, and files" {
    if (!test_options.sliding) return error.SkipZigTest;

    const input = try makeWindowCrossingJson();
    defer std.testing.allocator.free(input);
    try std.testing.expect(input.len > std.math.maxInt(u16));

    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try expectParsedAll(parsed.result, input);

    const sentinel = try allocSentinel(input);
    defer std.testing.allocator.free(sentinel);
    var parsed_sentinel = try parser.parseSentinelBytes(std.testing.io, std.testing.allocator, sentinel, .{});
    defer parsed_sentinel.deinit();
    try expectParsedAll(parsed_sentinel.result, input);

    try expectParsedAll(try parseFile(input), input);
}

test "input streaming sliding preserves position across a boundary" {
    if (!test_options.sliding) return error.SkipZigTest;

    const short_input = try makePositionJson(4);
    defer std.testing.allocator.free(short_input);
    var short = try parser.parseBytes(std.testing.io, std.testing.allocator, short_input, .{});
    defer short.deinit();

    const long_input = try makePositionJson(parser.input_window_size - 2);
    defer std.testing.allocator.free(long_input);
    var long = try parser.parseBytes(std.testing.io, std.testing.allocator, long_input, .{});
    defer long.deinit();

    try expectParsedAll(long.result, long_input);
    try std.testing.expectEqual(short.result.line, long.result.line);
    try std.testing.expectEqual(short.result.column, long.result.column);
}

test "input streaming sliding session is reusable" {
    if (!test_options.sliding) return error.SkipZigTest;

    const input = try makeWindowCrossingJson();
    defer std.testing.allocator.free(input);
    const sentinel = try allocSentinel(input);
    defer std.testing.allocator.free(sentinel);

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    try expectParsedAll(try session.parseBytes(input, "bytes-1"), input);
    try expectParsedAll(try session.parseSentinelBytes(sentinel, "sentinel"), input);
    try expectParsedAll(try session.parseBytes(input, "bytes-2"), input);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "input", .data = input });
    for (0..2) |_| {
        var file = try tmp.dir.openFile(std.testing.io, "input", .{
            .mode = .read_only,
        });
        defer file.close(std.testing.io);
        try expectParsedAll(try session.parseFile(file, "file"), input);
    }
}

test "indentation parsing accepts input beyond a fixed chunk" {
    if (!test_options.indentation) return error.SkipZigTest;

    const input = try makeIndentationInput(4000);
    defer std.testing.allocator.free(input);
    try std.testing.expect(input.len > std.math.maxInt(u16));

    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try expectParsedAll(parsed.result, input);

    const sentinel = try allocSentinel(input);
    defer std.testing.allocator.free(sentinel);
    var parsed_sentinel = try parser.parseSentinelBytes(std.testing.io, std.testing.allocator, sentinel, .{});
    defer parsed_sentinel.deinit();
    try expectParsedAll(parsed_sentinel.result, input);

    try expectParsedAll(try parseFile(input), input);
}

test "input streaming invalid indentation returns a structured diagnostic" {
    if (!test_options.indentation) return error.SkipZigTest;

    const invalid = "Rule:\n  - field: int\n   - broken: int\n";
    const valid = "Rule:\n  - field: int\n";

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    try std.testing.expectError(
        parser.ParseError.IndentationError,
        session.parseBytes(invalid, "invalid-bytes"),
    );
    {
        var read_guard = try session.readLatest();
        defer read_guard.deinit();
        const diagnostic = read_guard.lastDiagnostic() orelse return error.MissingDiagnostic;
        const indentation = switch (diagnostic) {
            .indentation => |indentation| indentation,
            .syntax => return error.ExpectedIndentationDiagnostic,
        };
        try std.testing.expectEqual(@as(u32, 3), indentation.line);
        try std.testing.expectEqual(@as(u32, 1), indentation.column);
        try std.testing.expectEqual(@as(u16, 3), indentation.spaces);
        try std.testing.expectEqual(@as(u16, 2), indentation.indentation_width);

        const rendered = try parser.renderParseDiagnostic(
            std.testing.allocator,
            diagnostic,
            .plain,
        );
        defer std.testing.allocator.free(rendered);
        try std.testing.expect(std.mem.indexOf(u8, rendered, "IndentationError at 3:1") != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, "3 spaces") != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, "width of 2") != null);
    }

    try expectParsedAll(try session.parseBytes(valid, "valid-after-error"), valid);

    const sentinel = try allocSentinel(invalid);
    defer std.testing.allocator.free(sentinel);
    try std.testing.expectError(
        parser.ParseError.IndentationError,
        session.parseSentinelBytes(sentinel, "invalid-sentinel"),
    );

    try std.testing.expectError(parser.ParseError.IndentationError, parseFile(invalid));
}

test "input streaming recovery handles EOF without reading beyond the window" {
    if (!test_options.recovery_eof) return error.SkipZigTest;

    const input = try makeRecoveryEofJson();
    defer std.testing.allocator.free(input);
    try std.testing.expect(input.len > std.math.maxInt(u16));

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes(input, "eof"));

    var read_guard = try session.readLatest();
    defer read_guard.deinit();
    const diagnostic = read_guard.lastDiagnostic() orelse return error.MissingDiagnostic;
    const syntax = switch (diagnostic) {
        .syntax => |syntax| syntax,
        .indentation => return error.ExpectedSyntaxDiagnostic,
    };
    try std.testing.expect(syntax.line >= 1);
    try std.testing.expect(syntax.column >= 1);
}

test "input streaming AST mode accepts input beyond the former offset limit" {
    if (!test_options.ast_large_input) return error.SkipZigTest;

    const small_input = "[]";
    var small = try parser.parseBytes(std.testing.io, std.testing.allocator, small_input, .{});
    defer small.deinit();
    try expectParsedAll(small.result, small_input);

    const oversized = try makeWindowCrossingJson();
    defer std.testing.allocator.free(oversized);
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, oversized, .{});
    defer parsed.deinit();
    try expectParsedAll(parsed.result, oversized);

    const sentinel = try allocSentinel(oversized);
    defer std.testing.allocator.free(sentinel);
    var parsed_sentinel = try parser.parseSentinelBytes(std.testing.io, std.testing.allocator, sentinel, .{});
    defer parsed_sentinel.deinit();
    try expectParsedAll(parsed_sentinel.result, oversized);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "oversized", .data = oversized });
    var file = try tmp.dir.openFile(std.testing.io, "oversized", .{
        .mode = .read_only,
    });
    defer file.close(std.testing.io);
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    const result = try session.parseFile(file, "oversized");
    try expectParsedAll(result, oversized);
}
