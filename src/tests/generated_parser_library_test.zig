const std = @import("std");
const parser = @import("parser-under-test");
const test_options = @import("test_options");
const sample_input = test_options.sample_input;

const case_name = test_options.case_name;
const suite = test_options.suite;
const config_label = test_options.config_label;

fn sampleFitsParserInputSize() bool {
    const max_input_size = std.math.maxInt(parser.parser.input_size_cap);
    if (sample_input.len > max_input_size) {
        return false;
    }
    return true;
}

fn sampleSupportsSessionSafetyTests() bool {
    return @bitSizeOf(parser.parser.input_size_cap) <= 16 and
        sampleFitsParserInputSize() and
        sample_input.len <= 1024 * 1024;
}

fn expectParsedAll(result: parser.ParseResult, comptime test_label: []const u8) !void {
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
            \\input_size_cap: {s}
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
                @typeName(parser.parser.input_size_cap),
                test_options.sample_path,
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

fn allocSentinelSample() ![:0]u8 {
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
            parser.parseBytes(std.testing.io, std.testing.allocator, input, .{}),
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
    if (comptime sample_input.len == 0) return error.SkipZigTest;
    if (!sampleFitsParserInputSize()) return error.SkipZigTest;

    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, sample_input, .{ .input_path = test_options.sample_path });
    defer parsed.deinit();

    try expectParsedAll(parsed.result, "parse bytes");
}

test "generated_parser_api parse sentinel bytes" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime sample_input.len == 0) return error.SkipZigTest;
    if (!sampleFitsParserInputSize()) return error.SkipZigTest;

    const input = try allocSentinelSample();
    defer std.testing.allocator.free(input);

    var parsed = try parser.parseSentinelBytes(std.testing.io, std.testing.allocator, input, .{ .input_path = test_options.sample_path });
    defer parsed.deinit();

    try expectParsedAll(parsed.result, "parse sentinel bytes");
}

test "generated_parser_api reports AST capacity exhaustion" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime !parser.parser.is_ast_enabled) return error.SkipZigTest;
    if (comptime sample_input.len == 0) return error.SkipZigTest;
    if (!sampleFitsParserInputSize()) return error.SkipZigTest;

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    const limited_allocator = try parser.data_structures.ASTAllocator.initWithCapacity(std.testing.allocator, 0);
    std.testing.allocator.free(session.node_allocator.memory);
    session.node_allocator = limited_allocator;

    try std.testing.expectError(
        error.ASTCapacityExceeded,
        session.parseBytes(sample_input, test_options.sample_path),
    );
    try std.testing.expectEqual(@as(parser.data_structures.ASTNode.Pointer, 0), session.node_allocator.counter);
}

test "generated_parser_api reusable session byte slices" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime sample_input.len == 0) return error.SkipZigTest;
    if (!sampleFitsParserInputSize()) return;

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    const first = try session.parseBytes(sample_input, test_options.sample_path);
    try expectParsedAll(first, "reusable session byte slices");

    const second = try session.parseBytes(sample_input, test_options.sample_path);
    try expectParsedAll(second, "reusable session byte slices");
}

test "generated_parser_api reusable session sentinel slices" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime sample_input.len == 0) return error.SkipZigTest;
    if (!sampleFitsParserInputSize()) return;

    const input = try allocSentinelSample();
    defer std.testing.allocator.free(input);

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    const first = try session.parseSentinelBytes(input, test_options.sample_path);
    try expectParsedAll(first, "reusable session sentinel slices");

    const second = try session.parseSentinelBytes(input, test_options.sample_path);
    try expectParsedAll(second, "reusable session sentinel slices");
}

test "generated_parser_api session readers prevent reuse" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime sample_input.len == 0) return error.SkipZigTest;
    if (!sampleSupportsSessionSafetyTests()) return error.SkipZigTest;

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    const first = try session.parseBytes(sample_input, test_options.sample_path);
    {
        var first_reader = try session.read(first);
        defer first_reader.deinit();
        {
            var second_reader = try session.read(first);
            defer second_reader.deinit();

            try std.testing.expectError(error.SessionInUse, session.parseBytes(sample_input, test_options.sample_path));
        }
        try std.testing.expectError(error.SessionInUse, session.parseBytes(sample_input, test_options.sample_path));
        try std.testing.expectError(error.SessionInUse, session.tryDeinit());
    }

    const second = try session.parseBytes(sample_input, test_options.sample_path);
    try expectParsedAll(second, "session readers prevent reuse");
    try std.testing.expectError(error.StaleParseResult, session.read(first));

    var latest_reader = try session.read(second);
    defer latest_reader.deinit();

    var other_session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer other_session.deinit();
    const other_result = try other_session.parseBytes(sample_input, test_options.sample_path);
    try std.testing.expectError(error.StaleParseResult, session.read(other_result));
}

const ConcurrentParse = struct {
    session: *parser.Session,
    result: ?parser.ParseResult = null,
    parse_error: ?anyerror = null,

    fn run(self: *ConcurrentParse) void {
        self.result = self.session.parseBytes(sample_input, test_options.sample_path) catch |err| {
            self.parse_error = err;
            return;
        };
    }
};

test "generated_parser_api separate sessions parse concurrently" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime sample_input.len == 0) return error.SkipZigTest;
    if (!sampleSupportsSessionSafetyTests()) return error.SkipZigTest;

    var first_session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer first_session.deinit();
    var second_session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer second_session.deinit();

    var first = ConcurrentParse{ .session = &first_session };
    var second = ConcurrentParse{ .session = &second_session };
    const first_thread = try std.Thread.spawn(.{}, ConcurrentParse.run, .{&first});
    const second_thread = try std.Thread.spawn(.{}, ConcurrentParse.run, .{&second});
    first_thread.join();
    second_thread.join();

    if (first.parse_error) |err| return err;
    if (second.parse_error) |err| return err;
    try expectParsedAll(first.result orelse return error.MissingConcurrentParseResult, "concurrent first session");
    try expectParsedAll(second.result orelse return error.MissingConcurrentParseResult, "concurrent second session");
}

test "generated_parser_api parse files" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime sample_input.len == 0) return error.SkipZigTest;
    if (!sampleFitsParserInputSize()) return;

    var file = try std.Io.Dir.cwd().openFile(std.testing.io, test_options.sample_path, .{
        .mode = .read_only,
    });
    defer file.close(std.testing.io);

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    const result = try session.parseFile(file, test_options.sample_path);
    try expectParsedAll(result, "parse files");
}
