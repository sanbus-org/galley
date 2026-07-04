const std = @import("std");
const parser = @import("parser-under-test");
const test_options = @import("test_options");
const sample_input = test_options.sample_input;

fn sampleFitsParserInputSize() bool {
    const max_input_size = std.math.maxInt(parser.parser.input_size_cap);
    if (sample_input.len > max_input_size) {
        std.debug.print(
            "sample {s} is {d} bytes, exceeding parser input_size_cap {s} max {d}\n",
            .{ test_options.sample_path, sample_input.len, @typeName(parser.parser.input_size_cap), max_input_size },
        );
        return false;
    }
    return true;
}

fn expectParsedAll(result: parser.ParseResult) !void {
    if (result.parsed_bytes != sample_input.len) {
        // var line: usize = 1;
        // var col: usize = 1;
        // for (sample_input[0..result.parsed_bytes]) |char| {
        //     if (char == '\n') {
        //         line += 1;
        //         col = 1;
        //     } else {
        //         col += 1;
        //     }
        // }
        const line = 0;
        const col = 0;
        std.debug.print(
            "sample {s} parsed {d} of {d} bytes (stopped at line {d}, col {d})\n",
            .{ test_options.sample_path, result.parsed_bytes, sample_input.len, line, col },
        );
        return error.ShortParse;
    }
}

test "parse bytes through generated parser library API" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime sample_input.len == 0) return error.SkipZigTest;
    if (!sampleFitsParserInputSize()) return error.SkipZigTest;

    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, sample_input, .{ .input_path = test_options.sample_path });
    defer parsed.deinit();

    try expectParsedAll(parsed.result);
}

test "reusable generated parser session parses multiple byte slices" {
    if (comptime !@hasDecl(parser.parser, "parseWithResult")) return error.SkipZigTest;
    if (comptime sample_input.len == 0) return error.SkipZigTest;
    if (!sampleFitsParserInputSize()) return;

    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    const first = try session.parseBytes(sample_input, test_options.sample_path);
    try expectParsedAll(first);

    const second = try session.parseBytes(sample_input, test_options.sample_path);
    try expectParsedAll(second);
}
