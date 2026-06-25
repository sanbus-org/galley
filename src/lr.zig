const clap = @import("clap");
const root = @import("root");
const std = @import("std");

pub const procedures = @import("procedures");
pub const parse_table = @import("parse-table");

const data_structures = root.data_structures;

pub fn parse(init: std.process.Init) !void {
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
    );

    const parsers = comptime .{
        .VERBOSITY_LEVEL = clap.parsers.int(u8, 10),
        .ITERATIONS = clap.parsers.int(u32, 10),
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
    // const warmup_iterations = if (@field(res.args, "warmup-iterations")) |warmup_iterations| warmup_iterations else iterations / 10;

    const io = init.io;

    const program_file = if (res.positionals[0]) |path|
        try std.Io.Dir.cwd().openFile(init.io, path, .{
            .mode = .read_only,
            .lock = .exclusive,
        })
    else
        std.Io.File.stdin();

    const arena_allocator = init.arena.allocator();

    const reader_buffer = try init.gpa.alloc(u8, root.read_chunk_size * 2);
    defer init.gpa.free(reader_buffer);

    var allocator = try data_structures.ASTAllocator.init_capacity(arena_allocator);

    const context = data_structures.Context{
        .node_allocator = &allocator,
        .arena_allocator = arena_allocator,
        .verbosity = verbosity,
        .io = io,
        .reader = program_file.reader(io, reader_buffer),
        .chunk_buffer = try init.gpa.alloc(u8, root.read_chunk_size),
    };
    defer init.gpa.free(context.chunk_buffer);

    if (@field(res.args, "disable-stack-overflow-recovery") > 0)
        try run(&context, warmup_iterations, iterations)
    else
        try root.stack_overflow_utilities.protected_run(&context, warmup_iterations, iterations);
}
