const std = @import("std");

const max_seed_size = 256 * 1024 * 1024;

/// Expands a zstd-compressed seed parser: `expand-seed <input.zst> <output>`.
pub fn main(init: std.process.Init) !void {
    var arguments = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer arguments.deinit();
    _ = arguments.skip();
    const input_path = arguments.next() orelse usage();
    const output_path = arguments.next() orelse usage();
    if (arguments.next() != null) usage();

    const compressed = try std.Io.Dir.cwd().readFileAlloc(init.io, input_path, init.gpa, .limited(max_seed_size));
    defer init.gpa.free(compressed);

    var input: std.Io.Reader = .fixed(compressed);
    var decompress: std.compress.zstd.Decompress = .init(&input, &.{}, .{});
    var expanded: std.Io.Writer.Allocating = .init(init.gpa);
    defer expanded.deinit();
    _ = try decompress.reader.streamRemaining(&expanded.writer);

    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = output_path, .data = expanded.written() });
}

fn usage() noreturn {
    std.debug.print("usage: expand-seed <input.zst> <output>\n", .{});
    std.process.exit(1);
}
