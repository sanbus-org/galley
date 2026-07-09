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

test "generated_parser_api parse files" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime sample_input.len == 0) return error.SkipZigTest;
    if (!sampleFitsParserInputSize()) return;

    var file = try std.Io.Dir.cwd().openFile(std.testing.io, test_options.sample_path, .{
        .mode = .read_only,
        .lock = .exclusive,
    });
    defer file.close(std.testing.io);

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    const result = try session.parseFile(file, test_options.sample_path);
    try expectParsedAll(result, "parse files");
}