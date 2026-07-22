const galley = @import("galley");
const std = @import("std");

const string_utilities = galley.string_utilities;

const Options = struct {
    input_path: ?[]const u8 = null,
    iterations: usize = 1,
    warmup_iterations: usize = 0,
};

pub fn main(init: std.process.Init) !void {
    const options = try parseArgs(init);
    const input_path = options.input_path orelse {
        printUsage();
        return error.MissingInput;
    };

    if (comptime galley.ast_memory_benchmark_enabled and !galley.parser.is_ast_enabled) {
        std.debug.print("error: AST memory benchmarking requires a parser generated with AST support\n", .{});
        return error.ASTMemoryBenchmarkRequiresAST;
    }

    const input = try std.Io.Dir.cwd().readFileAlloc(init.io, input_path, init.gpa, .limited(std.math.maxInt(usize)));
    defer init.gpa.free(input);

    const sentinel_input = try init.gpa.allocSentinel(u8, input.len, 0);
    defer init.gpa.free(sentinel_input);
    @memcpy(sentinel_input, input);

    var session = try galley.Session.init(init.io, init.gpa, .{ .input_path = input_path });
    defer session.deinit();

    if (comptime galley.ast_memory_benchmark_enabled) {
        const result = try session.parseSentinelBytes(sentinel_input, input_path);
        const stats = try session.astAllocator().memoryBenchmarkStats(init.gpa, result.ast_root);
        try printMemoryStats(result.parsed_bytes, stats);
    } else {
        for (0..options.warmup_iterations) |_| {
            _ = try session.parseSentinelBytes(sentinel_input, input_path);
        }

        var total_parsed_bytes: usize = 0;
        const start = std.Io.Clock.awake.now(init.io);
        for (0..options.iterations) |_| {
            const result = try session.parseSentinelBytes(sentinel_input, input_path);
            total_parsed_bytes += result.parsed_bytes;
        }
        const end = std.Io.Clock.awake.now(init.io);

        const elapsed_ns: usize = @intCast(start.durationTo(end).toNanoseconds());
        const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        const mbps = @as(f64, @floatFromInt(total_parsed_bytes)) / duration_secs;

        var buffer: [64]u8 = undefined;
        std.debug.print("Parsed bytes:  {s}\n", .{try string_utilities.formatFileSize(total_parsed_bytes, &buffer)});
        std.debug.print("Duration:      {s} ns\n", .{try string_utilities.formatWithThousands(elapsed_ns, &buffer)});
        std.debug.print("Throughput:    {s}/s\n", .{try string_utilities.formatFileSize(mbps, &buffer)});
        const nodes_allocated = if (comptime galley.parser.is_ast_enabled) session.astAllocator().counter else 0;
        std.debug.print("Nodes allocated:    {s}\n", .{try string_utilities.formatWithThousands(nodes_allocated, &buffer)});
    }
}

fn printMemoryStats(parsed_bytes: usize, stats: galley.data_structures.ASTMemoryBenchmarkStats) !void {
    const unreachable_nodes = stats.final_counter - stats.reachable_nodes;
    const prefix_sparsity = percentage(unreachable_nodes, stats.final_counter);
    const final_pool_utilization = percentage(stats.reachable_nodes, stats.preallocated_vector_items);
    const peak_headroom = stats.usable_capacity - stats.peak_counter;

    var buffer: [64]u8 = undefined;
    std.debug.print("Parsed bytes:                {s}\n", .{try string_utilities.formatFileSize(parsed_bytes, &buffer)});
    std.debug.print("Reachable AST nodes:         {s}\n", .{try string_utilities.formatWithThousands(stats.reachable_nodes, &buffer)});
    std.debug.print("Allocator counter:           {s}\n", .{try string_utilities.formatWithThousands(stats.final_counter, &buffer)});
    std.debug.print("Peak allocator counter:      {s}\n", .{try string_utilities.formatWithThousands(stats.peak_counter, &buffer)});
    std.debug.print("Total node creations:        {s}\n", .{try string_utilities.formatWithThousands(stats.total_create_calls, &buffer)});
    std.debug.print("Unreachable below counter:   {s}\n", .{try string_utilities.formatWithThousands(unreachable_nodes, &buffer)});
    std.debug.print("Prefix sparsity:             {d:.2}%\n", .{prefix_sparsity});
    std.debug.print("Usable node capacity:        {s}\n", .{try string_utilities.formatWithThousands(stats.usable_capacity, &buffer)});
    std.debug.print("Preallocated vector items:   {s}\n", .{try string_utilities.formatWithThousands(stats.preallocated_vector_items, &buffer)});
    std.debug.print("Final pool utilization:      {d:.2}%\n", .{final_pool_utilization});
    std.debug.print("Peak headroom:               {s}\n", .{try string_utilities.formatWithThousands(peak_headroom, &buffer)});
}

fn percentage(numerator: usize, denominator: usize) f64 {
    if (denominator == 0) return 0;
    return 100 * @as(f64, @floatFromInt(numerator)) / @as(f64, @floatFromInt(denominator));
}

fn parseArgs(init: std.process.Init) !Options {
    var options = Options{};
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();

    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printUsage();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--iterations")) {
            if (comptime galley.ast_memory_benchmark_enabled) return incompatibleIterationOption(arg);
            options.iterations = try parseCount(args.next(), arg);
        } else if (std.mem.startsWith(u8, arg, "--iterations=")) {
            if (comptime galley.ast_memory_benchmark_enabled) return incompatibleIterationOption("--iterations");
            options.iterations = try parseCount(arg["--iterations=".len..], "--iterations");
        } else if (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--warmup-iterations")) {
            if (comptime galley.ast_memory_benchmark_enabled) return incompatibleIterationOption(arg);
            options.warmup_iterations = try parseCount(args.next(), arg);
        } else if (std.mem.startsWith(u8, arg, "--warmup-iterations=")) {
            if (comptime galley.ast_memory_benchmark_enabled) return incompatibleIterationOption("--warmup-iterations");
            options.warmup_iterations = try parseCount(arg["--warmup-iterations=".len..], "--warmup-iterations");
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("error: unknown argument: {s}\n", .{arg});
            return error.UnknownArgument;
        } else if (options.input_path == null) {
            options.input_path = arg;
        } else {
            std.debug.print("error: unexpected positional argument: {s}\n", .{arg});
            return error.UnexpectedArgument;
        }
    }

    if (options.iterations == 0) return error.InvalidIterations;
    return options;
}

fn incompatibleIterationOption(name: []const u8) error{IncompatibleIterationOption} {
    std.debug.print("error: {s} cannot be used with -Dast-memory-benchmark=true; memory benchmarking parses once\n", .{name});
    return error.IncompatibleIterationOption;
}

fn parseCount(value: ?[]const u8, name: []const u8) !usize {
    const text = value orelse {
        std.debug.print("error: {s} requires a value\n", .{name});
        return error.MissingValue;
    };
    return std.fmt.parseInt(usize, text, 10) catch {
        std.debug.print("error: invalid {s}: {s}\n", .{ name, text });
        return error.InvalidInteger;
    };
}

fn printUsage() void {
    if (comptime galley.ast_memory_benchmark_enabled) {
        std.debug.print(
            \\usage: api-benchmark <file> [OPTIONS]
            \\
            \\AST memory benchmark mode parses the input once.
            \\
            \\Options:
            \\  -h, --help    Display this help and exit.
            \\
        , .{});
    } else {
        std.debug.print(
            \\usage: api-benchmark <file> [OPTIONS]
            \\
            \\Options:
            \\  -h, --help                         Display this help and exit.
            \\  -r, --iterations <ITERATIONS>      Timed parse iterations.
            \\  -w, --warmup-iterations <COUNT>    Untimed warmup iterations.
            \\
        , .{});
    }
}
