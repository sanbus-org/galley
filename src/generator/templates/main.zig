const std = @import("std");
const parser = @import("generated_parser");

const Options = struct {
    iterations: u32 = 1,
    warmup_iterations: ?u32 = null,
    verbosity: usize = 0,
};

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const options = try parseArgs(init);
    const warmup_iterations = options.warmup_iterations orelse options.iterations / 10;

    var samples_dir = try std.Io.Dir.cwd().openDir(init.io, "samples", .{ .iterate = true });
    defer samples_dir.close(init.io);

    var walker = try samples_dir.walk(init.gpa);
    defer walker.deinit();

    var session = try parser.Session.init(init.io, init.gpa, .{ .verbosity = options.verbosity });
    defer session.deinit();

    var parsed_count: usize = 0;
    while (try walker.next(init.io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.startsWith(u8, std.fs.path.basename(entry.path), "code-")) continue;

        const sample_path = try std.fs.path.join(init.gpa, &.{ "samples", entry.path });
        defer init.gpa.free(sample_path);

        const file = try std.Io.Dir.cwd().openFile(init.io, sample_path, .{
            .mode = .read_only,
            .lock = .exclusive,
        });
        const result = try runSample(&session, file, sample_path, warmup_iterations, options.iterations);
        parsed_count += 1;
        try stdout.print("parsed {s} ({d} bytes", .{ sample_path, result.parsed_bytes });
        if (result.elapsed_ns) |elapsed_ns| {
            const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
            const mbps = @as(f64, @floatFromInt(result.parsed_bytes)) / duration_secs;
            var buffer: [64]u8 = undefined;
            try stdout.print(", {s} ns, {s}/s", .{
                try parser.string_utilities.formatWithThousands(elapsed_ns, &buffer),
                try parser.string_utilities.formatFileSize(mbps, &buffer),
            });
        }
        try stdout.writeAll(")\n");
        try stdout.flush();
    }

    if (parsed_count == 0) {
        try stdout.writeAll("no samples/code-* files found\n");
    }
    try stdout.flush();
}

const RunResult = struct {
    parsed_bytes: usize,
    elapsed_ns: ?usize = null,
};

fn runSample(session: *parser.Session, file: std.Io.File, sample_path: []const u8, warmup_iterations: u32, iterations: u32) !RunResult {
    for (0..warmup_iterations) |_| {
        _ = try session.parseFile(file, sample_path);
    }

    var total_parsed_bytes: usize = 0;
    const start = std.Io.Clock.awake.now(session.io);
    for (0..iterations) |_| {
        const result = try session.parseFile(file, sample_path);
        total_parsed_bytes += result.parsed_bytes;
    }

    if (iterations > 1) {
        const end = std.Io.Clock.awake.now(session.io);
        return .{
            .parsed_bytes = total_parsed_bytes,
            .elapsed_ns = @intCast(start.durationTo(end).toNanoseconds()),
        };
    }

    return .{ .parsed_bytes = total_parsed_bytes };
}

fn parseArgs(init: std.process.Init) !Options {
    var options = Options{};
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();

    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printUsage(init);
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--iterations")) {
            const value = args.next() orelse return error.MissingIterations;
            options.iterations = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.startsWith(u8, arg, "--iterations=")) {
            options.iterations = try std.fmt.parseInt(u32, arg["--iterations=".len..], 10);
        } else if (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--warmup-iterations")) {
            const value = args.next() orelse return error.MissingWarmupIterations;
            options.warmup_iterations = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.startsWith(u8, arg, "--warmup-iterations=")) {
            options.warmup_iterations = try std.fmt.parseInt(u32, arg["--warmup-iterations=".len..], 10);
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbosity")) {
            const value = args.next() orelse return error.MissingVerbosity;
            options.verbosity = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.startsWith(u8, arg, "--verbosity=")) {
            options.verbosity = try std.fmt.parseInt(usize, arg["--verbosity=".len..], 10);
        } else {
            return error.UnknownArgument;
        }
    }

    if (options.iterations == 0) return error.InvalidIterations;
    return options;
}

fn printUsage(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll(
        \\usage: zig build run-ll -- [OPTIONS]
        \\
        \\Options:
        \\  -h, --help                         Display this help and exit.
        \\  -r, --iterations <ITERATIONS>      Repeat each sample parse.
        \\  -w, --warmup-iterations <COUNT>    Warmup parses before timing.
        \\  -v, --verbosity <LEVEL>            Debug verbosity level.
        \\
    );
    try stdout.flush();
}
