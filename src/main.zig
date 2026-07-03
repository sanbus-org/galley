const clap = @import("clap");
const builtin = @import("builtin");
const galley = @import("galley");
const std = @import("std");

const config = galley.config;
const parser = galley.parser;
const string_utilities = galley.string_utilities;

fn printHelp() void {
    std.debug.print("\nusage: parser_builder [program_path]\n", .{});
    std.process.exit(1);
}

pub fn main(init: std.process.Init) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help                        Display this help and exit.
        \\-v, --verbosity <VERBOSITY_LEVEL> An option parameter, which takes a value.
        \\-r, --iterations <ITERATIONS>     Repeat the parse process. Useful for benchmarking.
        \\-w, --warmup-iterations <ITERATIONS>
        \\                                  Warmup iterations of the parse process.
        \\                                  Useful for benchmarking.
        \\    --disable-stack-overflow-recovery
        \\                                  Disables the stack overflow recovery mechanism
        \\<FILE>
        \\
    ++ config.params);

    const parsers = comptime .{
        .VERBOSITY_LEVEL = clap.parsers.int(u8, 10),
        .ITERATIONS = clap.parsers.int(u32, 10),
        .INPUT_SIZE = clap.parsers.int(u16, 10),
        .FILE = clap.parsers.string,
    };
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = init.gpa,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(init.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
        const stdout = &stdout_writer.interface;

        try clap.usageToFile(init.io, .stdout(), clap.Help, &params);
        _ = try stdout.writeAll("\n\n");
        try stdout.flush();
        return clap.helpToFile(init.io, .stdout(), clap.Help, &params, .{});
    }

    const verbosity = if (res.args.verbosity) |verbosity| verbosity else 0;
    const iterations = if (res.args.iterations) |iterations| iterations else 1;
    const warmup_iterations = if (@field(res.args, "warmup-iterations")) |warmup_iterations| warmup_iterations else iterations / 10;

    const io = init.io;

    const input_path = res.positionals[0];
    const program_file = if (input_path) |path|
        try std.Io.Dir.cwd().openFile(init.io, path, .{
            .mode = .read_only,
            .lock = .exclusive,
        })
    else
        std.Io.File.stdin();

    var session = try galley.Session.init(io, init.gpa, .{
        .language_options = config.optionsFromArgs(res.args),
        .input_path = input_path,
        .verbosity = verbosity,
    });
    defer session.deinit();

    try run(&session, program_file, input_path, warmup_iterations, iterations);
}

fn run(session: *galley.Session, program_file: std.Io.File, input_path: ?[]const u8, warmup_iterations: usize, iterations: usize) !void {
    for (0..warmup_iterations) |_| {
        _ = try session.parseFile(program_file, input_path);
    }

    var total_parsed_bytes: usize = 0;
    const start = std.Io.Clock.awake.now(session.io);

    for (0..iterations) |_| {
        const result = try session.parseFile(program_file, input_path);
        total_parsed_bytes += result.parsed_bytes;
    }

    if (iterations > 1) {
        const end = std.Io.Clock.awake.now(session.io);
        const duration = start.durationTo(end);
        const elapsed_ns: usize = @intCast(duration.toNanoseconds());
        const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        const mbps = @as(f64, @floatFromInt(total_parsed_bytes)) / duration_secs;

        var buffer: [64]u8 = undefined;
        std.debug.print("Parsed bytes:  {s}\n", .{try string_utilities.formatFileSize(total_parsed_bytes, &buffer)});
        std.debug.print("Duration:      {s} ns\n", .{try string_utilities.formatWithThousands(elapsed_ns, &buffer)});
        std.debug.print("Throughput:    {s}/s\n", .{try string_utilities.formatFileSize(mbps, &buffer)});
        const nodes_allocated = if (comptime parser.is_ast_enabled) session.astAllocator().counter else 0;
        std.debug.print("Nodes allocated:    {s}\n", .{try string_utilities.formatWithThousands(
            nodes_allocated,
            &buffer,
        )});
    }
}
