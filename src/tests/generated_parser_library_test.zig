const std = @import("std");
const parser = @import("parser-under-test");
const test_options = @import("test_options");

const case_name = test_options.case_name;
const suite = test_options.suite;
const config_label = test_options.config_label;
const sample_paths = test_options.sample_paths;
const sample_inputs = test_options.sample_inputs;

fn ignoreDiagnostic(_: []const u8) void {}

fn sampleSupportsSessionSafetyTests(sample_len: usize) bool {
    return sample_len <= 1024 * 1024;
}

fn expectParsedAll(
    result: parser.ParseResult,
    sample_path: []const u8,
    sample_input: []const u8,
    comptime test_label: []const u8,
) !void {
    if (result.parsed_bytes != sample_input.len) {
        const line = if (@TypeOf(result.line) == u32) result.line else 0;
        const col = if (@TypeOf(result.column) == u32) result.column else 0;
        std.debug.print(
            \\
            \\=== generated_parser_api failure ===
            \\case: {s}
            \\suite: {s}
            \\config: {s}
            \\parser_type: {s}
            \\ast: {}
            \\procedures: {}
            \\sample: {s}
            \\test: {s}
            \\parsed {d} of {d} bytes (stopped at line {d}, col {d})
            \\===================================
            \\
        ,
            .{
                case_name,
                suite,
                config_label,
                @tagName(parser.parser.parser_type),
                parser.parser.is_ast_enabled,
                parser.parser.are_procedures_enabled,
                sample_path,
                test_label,
                result.parsed_bytes,
                sample_input.len,
                line,
                col,
            },
        );
        return error.ShortParse;
    }
}

fn allocSentinelSample(sample_input: []const u8) ![:0]u8 {
    const input = try std.testing.allocator.allocSentinel(u8, sample_input.len, 0);
    @memcpy(input, sample_input);
    return input;
}

fn isJsonUnicodeCase() bool {
    return std.mem.indexOf(u8, case_name, "-json-unicode-") != null;
}

test "JSON parser accepts valid UTF-8 scalar boundaries" {
    if (comptime !isJsonUnicodeCase()) return error.SkipZigTest;

    const input = "[\"\\u0000\",\"\u{80}\u{7ff}\u{800}\u{ffff}\u{10000}\u{10ffff}\"]";
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
}

test "JSON parser rejects malformed UTF-8 and non-scalars" {
    if (comptime !isJsonUnicodeCase()) return error.SkipZigTest;

    const invalid_inputs = [_][]const u8{
        &.{ '[', '"', 0x80, '"', ']' },
        &.{ '[', '"', 0xc0, 0x80, '"', ']' },
        &.{ '[', '"', 0xe0, 0x80, 0x80, '"', ']' },
        &.{ '[', '"', 0xed, 0xa0, 0x80, '"', ']' },
        &.{ '[', '"', 0xf0, 0x80, 0x80, 0x80, '"', ']' },
        &.{ '[', '"', 0xf4, 0x90, 0x80, 0x80, '"', ']' },
    };
    for (invalid_inputs) |input| {
        try std.testing.expectError(
            parser.ParseError.SyntaxError,
            parser.parseBytes(std.testing.io, std.testing.allocator, input, .{ .syntax_error_reporter = &ignoreDiagnostic }),
        );
    }
}

test "JSON string decoder handles Unicode escapes and surrogate pairs" {
    if (comptime !isJsonUnicodeCase()) return error.SkipZigTest;

    const decoded = try parser.procedures.decodeStringContent(
        std.testing.allocator,
        "سلام 😀\\u0000\\u007f\\u0080\\u07ff\\u0800\\uffff\\ud800\\udc00",
    );
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualSlices(
        u8,
        "سلام 😀\x00\x7f\xc2\x80\xdf\xbf\xe0\xa0\x80\xef\xbf\xbf\xf0\x90\x80\x80",
        decoded,
    );
}

test "JSON string decoder rejects malformed Unicode escapes" {
    if (comptime !isJsonUnicodeCase()) return error.SkipZigTest;

    const cases = .{
        .{ "\\q", error.InvalidJsonEscape },
        .{ "\\u", error.InvalidJsonUnicodeEscape },
        .{ "\\u123", error.InvalidJsonUnicodeEscape },
        .{ "\\uxxxx", error.InvalidJsonUnicodeEscape },
        .{ "\\ud800", error.InvalidJsonSurrogatePair },
        .{ "\\ud800\\u0000", error.InvalidJsonSurrogatePair },
        .{ "\\udc00", error.InvalidJsonSurrogatePair },
    };
    inline for (cases) |case| {
        try std.testing.expectError(
            case[1],
            parser.procedures.decodeStringContent(std.testing.allocator, case[0]),
        );
    }
}

test "generated_parser_api parse bytes" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime sample_inputs.len == 0) return error.SkipZigTest;
    for (sample_paths, sample_inputs) |sample_path, sample_input| {
        var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, sample_input, .{ .input_path = sample_path });
        defer parsed.deinit();

        try expectParsedAll(parsed.result, sample_path, sample_input, "parse bytes");
    }
}

test "generated_parser_api parse sentinel bytes" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime sample_inputs.len == 0) return error.SkipZigTest;
    for (sample_paths, sample_inputs) |sample_path, sample_input| {
        const input = try allocSentinelSample(sample_input);
        defer std.testing.allocator.free(input);

        var parsed = try parser.parseSentinelBytes(std.testing.io, std.testing.allocator, input, .{ .input_path = sample_path });
        defer parsed.deinit();

        try expectParsedAll(parsed.result, sample_path, sample_input, "parse sentinel bytes");
    }
}

test "generated_parser_api grows AST capacity from zero" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime !parser.parser.is_ast_enabled) return error.SkipZigTest;
    if (comptime sample_inputs.len == 0) return error.SkipZigTest;
    for (sample_paths, sample_inputs) |sample_path, sample_input| {
        var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{
            .ast_preallocation_ratio = 0,
            .ast_preallocation_cap = 0,
        });
        defer session.deinit();

        const result = try session.parseBytes(sample_input, sample_path);
        try expectParsedAll(result, sample_path, sample_input, "grow AST capacity from zero");
        try std.testing.expect(session.node_allocator.totalNodeCapacity() > 1);
    }
}

test "generated_parser_api reusable session byte slices" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime sample_inputs.len == 0) return error.SkipZigTest;
    for (sample_paths, sample_inputs) |sample_path, sample_input| {
        var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
        defer session.deinit();

        const first = try session.parseBytes(sample_input, sample_path);
        try expectParsedAll(first, sample_path, sample_input, "reusable session byte slices");

        const second = try session.parseBytes(sample_input, sample_path);
        try expectParsedAll(second, sample_path, sample_input, "reusable session byte slices");
    }
}

test "generated_parser_api reusable session sentinel slices" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime sample_inputs.len == 0) return error.SkipZigTest;
    for (sample_paths, sample_inputs) |sample_path, sample_input| {
        const input = try allocSentinelSample(sample_input);
        defer std.testing.allocator.free(input);

        var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
        defer session.deinit();

        const first = try session.parseSentinelBytes(input, sample_path);
        try expectParsedAll(first, sample_path, sample_input, "reusable session sentinel slices");

        const second = try session.parseSentinelBytes(input, sample_path);
        try expectParsedAll(second, sample_path, sample_input, "reusable session sentinel slices");
    }
}

test "generated_parser_api session readers prevent reuse" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime sample_inputs.len == 0) return error.SkipZigTest;
    for (sample_paths, sample_inputs) |sample_path, sample_input| {
        if (!sampleSupportsSessionSafetyTests(sample_input.len)) continue;

        var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
        defer session.deinit();

        const first = try session.parseBytes(sample_input, sample_path);
        {
            var first_reader = try session.read(first);
            defer first_reader.deinit();
            {
                var second_reader = try session.read(first);
                defer second_reader.deinit();

                try std.testing.expectError(error.SessionInUse, session.parseBytes(sample_input, sample_path));
            }
            try std.testing.expectError(error.SessionInUse, session.parseBytes(sample_input, sample_path));
            try std.testing.expectError(error.SessionInUse, session.tryDeinit());
        }

        const second = try session.parseBytes(sample_input, sample_path);
        try expectParsedAll(second, sample_path, sample_input, "session readers prevent reuse");
        try std.testing.expectError(error.StaleParseResult, session.read(first));

        var latest_reader = try session.read(second);
        defer latest_reader.deinit();

        var other_session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
        defer other_session.deinit();
        const other_result = try other_session.parseBytes(sample_input, sample_path);
        try std.testing.expectError(error.StaleParseResult, session.read(other_result));
    }
}

const ConcurrentParse = struct {
    session: *parser.Session,
    sample_path: []const u8,
    sample_input: []const u8,
    result: ?parser.ParseResult = null,
    parse_error: ?anyerror = null,

    fn run(self: *ConcurrentParse) void {
        self.result = self.session.parseBytes(self.sample_input, self.sample_path) catch |err| {
            self.parse_error = err;
            return;
        };
    }
};

test "generated_parser_api separate sessions parse concurrently" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime sample_inputs.len == 0) return error.SkipZigTest;
    for (sample_paths, sample_inputs) |sample_path, sample_input| {
        if (!sampleSupportsSessionSafetyTests(sample_input.len)) continue;

        var first_session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
        defer first_session.deinit();
        var second_session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
        defer second_session.deinit();

        var first = ConcurrentParse{ .session = &first_session, .sample_path = sample_path, .sample_input = sample_input };
        var second = ConcurrentParse{ .session = &second_session, .sample_path = sample_path, .sample_input = sample_input };
        const first_thread = try std.Thread.spawn(.{}, ConcurrentParse.run, .{&first});
        const second_thread = try std.Thread.spawn(.{}, ConcurrentParse.run, .{&second});
        first_thread.join();
        second_thread.join();

        if (first.parse_error) |err| return err;
        if (second.parse_error) |err| return err;
        try expectParsedAll(first.result orelse return error.MissingConcurrentParseResult, sample_path, sample_input, "concurrent first session");
        try expectParsedAll(second.result orelse return error.MissingConcurrentParseResult, sample_path, sample_input, "concurrent second session");
    }
}

test "generated_parser_api parse files" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime sample_inputs.len == 0) return error.SkipZigTest;
    for (sample_paths, sample_inputs) |sample_path, sample_input| {
        var file = try std.Io.Dir.cwd().openFile(std.testing.io, sample_path, .{
            .mode = .read_only,
        });
        defer file.close(std.testing.io);

        var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
        defer session.deinit();

        const result = try session.parseFile(file, sample_path);
        try expectParsedAll(result, sample_path, sample_input, "parse files");
    }
}
