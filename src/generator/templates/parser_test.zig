const std = @import("std");
const parser = @import("generated_parser");

const placeholder = "Write a sample code here";

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const sample = try std.Io.Dir.cwd().readFileAlloc(init.io, "samples/code-01", init.gpa, .limited(1024 * 1024));
    defer init.gpa.free(sample);

    if (std.mem.eql(u8, sample, placeholder)) {
        try stdout.writeAll(
            "\x1b[33m\x1b[1mGalley test skipped\x1b[0m\n" ++
                "  \x1b[36msamples/code-01\x1b[0m still contains the generated placeholder.\n" ++
                "  Replace it with valid source for this language, then run \x1b[1mzig build test\x1b[0m again.\n",
        );
        try stdout.flush();
        return;
    }

    var parsed = try parser.parseBytes(init.io, init.gpa, sample, .{ .input_path = "samples/code-01" });
    defer parsed.deinit();
    if (parsed.result.parsed_bytes != sample.len) return error.ShortParse;

    var session = try parser.Session.init(init.io, init.gpa, .{});
    defer session.deinit();

    const first = try session.parseBytes(sample, "samples/code-01");
    if (first.parsed_bytes != sample.len) return error.ShortParse;

    const second = try session.parseBytes(sample, "samples/code-01");
    if (second.parsed_bytes != sample.len) return error.ShortParse;

    try stdout.writeAll("samples/code-01 parsed\n");
    try stdout.flush();
}
