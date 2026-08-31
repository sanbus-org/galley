//! JSON throughput through Galley's native Zig runtime: no AST, no procedures,
//! no error recovery. Parses languages/json/samples/code-01.json 50,000 times
//! on one session and reports bytes/s.

const std = @import("std");
const parser = @import("parser");

const logical_input = "languages/json/samples/code-01.json";
const default_iterations: usize = 50_000;

fn resolveInput(
    io: std.Io,
    gpa: std.mem.Allocator,
    environ_map: *std.process.Environ.Map,
    explicit: ?[]const u8,
) ![]u8 {
    if (explicit) |path| return gpa.dupe(u8, path);

    if (environ_map.get("GALLEY_CHECKOUT")) |checkout| {
        if (checkout.len > 0) {
            const candidate = try std.fs.path.join(gpa, &.{ checkout, logical_input });
            if (fileExists(io, candidate)) return candidate;
            gpa.free(candidate);
        }
    }

    const from_example = try std.fs.path.join(gpa, &.{ "..", "..", logical_input });
    if (fileExists(io, from_example)) return from_example;
    gpa.free(from_example);
    return error.MissingInput;
}

fn fileExists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn printLabeled(stdout: *std.Io.Writer, label: []const u8, value: u64) !void {
    var buffer: [32]u8 = undefined;
    try stdout.print("{s}: {s}\n", .{ label, try parser.string_utilities.formatWithThousands(value, &buffer) });
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.skip();
    const explicit = args.next();
    var iterations: usize = default_iterations;
    if (args.next()) |text| {
        iterations = std.fmt.parseInt(usize, text, 10) catch 0;
        if (iterations < 1) {
            std.debug.print("iterations must be >= 1\n", .{});
            std.process.exit(1);
        }
    }

    const path = resolveInput(init.io, init.gpa, init.environ_map, explicit) catch {
        std.debug.print("failed to read {s}\n", .{logical_input});
        std.process.exit(1);
    };
    defer init.gpa.free(path);

    const input = std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(std.math.maxInt(usize))) catch {
        std.debug.print("failed to read {s}\n", .{logical_input});
        std.process.exit(1);
    };
    defer init.gpa.free(input);

    const sentinel = try init.gpa.allocSentinel(u8, input.len, 0);
    defer init.gpa.free(sentinel);
    @memcpy(sentinel, input);

    var session = parser.Session.init(init.io, init.gpa, .{}) catch {
        std.debug.print("failed to create a parser session\n", .{});
        std.process.exit(1);
    };
    defer session.deinit();

    const warmup = session.parseSentinelBytes(sentinel, null) catch |err| {
        std.debug.print("warmup parse failed: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    if (warmup.parsed_bytes != input.len) {
        std.debug.print("warmup parse failed: parsed {d} of {d} bytes\n", .{ warmup.parsed_bytes, input.len });
        std.process.exit(1);
    }

    const start = std.Io.Clock.awake.now(init.io);
    for (0..iterations) |index| {
        const result = session.parseSentinelBytes(sentinel, null) catch |err| {
            std.debug.print("parse failed at iteration {d}: {s}\n", .{ index, @errorName(err) });
            std.process.exit(1);
        };
        if (result.parsed_bytes != input.len) {
            std.debug.print("parse failed at iteration {d}: parsed {d} of {d} bytes\n", .{
                index,
                result.parsed_bytes,
                input.len,
            });
            std.process.exit(1);
        }
    }
    const elapsed_ns: u64 = @intCast(start.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds());
    const total: u64 = input.len * iterations;
    const bps: u64 = if (elapsed_ns == 0) 0 else total * 1_000_000_000 / elapsed_ns;

    try stdout.print("input: {s}\n", .{logical_input});
    try printLabeled(stdout, "bytes", input.len);
    try printLabeled(stdout, "iterations", iterations);
    try printLabeled(stdout, "parsed_bytes", total);
    try printLabeled(stdout, "duration_ns", elapsed_ns);
    try printLabeled(stdout, "bytes_per_second", bps);
}
