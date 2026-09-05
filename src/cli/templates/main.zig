const std = @import("std");
const galley = @import("galley_parser");

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();

    _ = args.skip();
    const input_path = args.next() orelse {
        std.debug.print("usage: galley-run <source-file>\n", .{});
        return error.MissingSourceFile;
    };

    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, input_path, init.gpa, .limited(1024 * 1024 * 1024));
    defer init.gpa.free(source);

    var parsed = galley.parseBytes(init.io, init.gpa, source, .{ .input_path = input_path }) catch |err| switch (err) {
        error.SyntaxError, error.SemanticError => std.process.exit(1),
        else => return err,
    };
    defer parsed.deinit();

    std.debug.print("parsed {s}: {d} bytes\n", .{ input_path, parsed.result.parsed_bytes });
}
