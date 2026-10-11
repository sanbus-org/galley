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

    var session = try galley.Session.init(init.io, init.gpa, .{});
    defer session.deinit();

    const result = session.parseBytes(source, input_path) catch |err| {
        var guard = session.readLatest() catch return err;
        defer guard.deinit();
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(init.io, &stderr_buffer);
        galley.writeDiagnostics(&stderr_writer.interface, guard.recordedDiagnostics()) catch {};
        stderr_writer.interface.flush() catch {};
        switch (err) {
            error.SyntaxError, error.SemanticError => std.process.exit(1),
            else => return err,
        }
    };

    std.debug.print("parsed {s}: {d} bytes\n", .{ input_path, result.parsed_bytes });
}
