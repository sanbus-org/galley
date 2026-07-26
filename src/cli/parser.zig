const builtin = @import("builtin");
const build_options = @import("build_options");
const galley = @import("galley");
const std = @import("std");

const config = galley.config;
const parser = galley.parser;
const string_utilities = galley.string_utilities;

const LanguageArg = struct {
    name: []const u8,
    value: ?[]const u8,
};

const CliOptions = struct {
    verbosity: u8 = 0,
    iterations: u32 = 1,
    warmup_iterations: ?u32 = null,
    max_errors: usize = 10,
    recovery_window: usize = 500,
    stack_overflow_recovery: bool = false,
    input_path: ?[]const u8 = null,
    language_options: config.Options = .{},
};

pub fn main(init: std.process.Init) !void {
    const options = try parseArgs(init);
    const warmup_iterations = options.warmup_iterations orelse options.iterations / 10;

    const io = init.io;

    const input_path = options.input_path;
    const program_file = if (input_path) |path|
        try std.Io.Dir.cwd().openFile(init.io, path, .{
            .mode = .read_only,
            .lock = .exclusive,
        })
    else
        std.Io.File.stdin();

    var session = try galley.Session.init(io, init.gpa, .{
        .language_options = options.language_options,
        .input_path = input_path,
        .verbosity = options.verbosity,
        .max_errors = options.max_errors,
        .recovery_window = options.recovery_window,
        .stack_overflow_recovery = options.stack_overflow_recovery,
    });
    defer session.deinit();

    try run(&session, program_file, input_path, warmup_iterations, options.iterations);
}

fn parseArgs(init: std.process.Init) !CliOptions {
    var result = CliOptions{};
    var language_args: std.ArrayList(LanguageArg) = .empty;
    defer language_args.deinit(init.gpa);

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();

    _ = args.skip();
    var positional_only = false;
    while (args.next()) |arg| {
        if (!positional_only and (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help"))) {
            try printUsage(init);
            std.process.exit(0);
        } else if (!positional_only and (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbosity"))) {
            result.verbosity = parseInteger(u8, args.next(), "--verbosity");
        } else if (activeLongOptionValue(positional_only, arg, "--verbosity")) |value| {
            result.verbosity = parseInteger(u8, value, "--verbosity");
        } else if (!positional_only and (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--iterations"))) {
            result.iterations = parseInteger(u32, args.next(), "--iterations");
        } else if (activeLongOptionValue(positional_only, arg, "--iterations")) |value| {
            result.iterations = parseInteger(u32, value, "--iterations");
        } else if (!positional_only and (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--warmup-iterations"))) {
            result.warmup_iterations = parseInteger(u32, args.next(), "--warmup-iterations");
        } else if (activeLongOptionValue(positional_only, arg, "--warmup-iterations")) |value| {
            result.warmup_iterations = parseInteger(u32, value, "--warmup-iterations");
        } else if (activeRecoveryOption(positional_only, arg, "--max-errors")) {
            result.max_errors = parseInteger(usize, args.next(), "--max-errors");
        } else if (activeRecoveryLongOptionValue(positional_only, arg, "--max-errors")) |value| {
            result.max_errors = parseInteger(usize, value, "--max-errors");
        } else if (activeRecoveryOption(positional_only, arg, "--recovery-window")) {
            result.recovery_window = parseInteger(usize, args.next(), "--recovery-window");
        } else if (activeRecoveryLongOptionValue(positional_only, arg, "--recovery-window")) |value| {
            result.recovery_window = parseInteger(usize, value, "--recovery-window");
        } else if (!positional_only and std.mem.eql(u8, arg, "--enable-stack-overflow-recovery")) {
            result.stack_overflow_recovery = true;
        } else if (!positional_only and std.mem.eql(u8, arg, "--")) {
            positional_only = true;
        } else if (activeLanguageOption(positional_only, arg)) |language_arg| {
            const value = if (language_arg.takes_value)
                language_arg.value orelse args.next() orelse
                    fatal("error: {s} requires a value\n", .{language_arg.name})
            else if (language_arg.value != null)
                fatal("error: {s} does not take a value\n", .{language_arg.name})
            else
                null;
            try language_args.append(init.gpa, .{ .name = language_arg.name, .value = value });
        } else if (!positional_only and std.mem.startsWith(u8, arg, "-")) {
            fatal("error: unknown argument: {s}\n", .{arg});
        } else if (result.input_path == null) {
            result.input_path = arg;
        } else {
            fatal("error: unexpected positional argument: {s}\n", .{arg});
        }
    }

    if (result.iterations == 0) fatal("error: --iterations must be greater than zero\n", .{});
    if (comptime parser.is_error_recovery_enabled) {
        if (result.max_errors == 0) fatal("error: --max-errors must be greater than zero\n", .{});
        if (result.recovery_window == 0) fatal("error: --recovery-window must be greater than zero\n", .{});
    }
    if (@hasDecl(config, "optionsFromCliArgs")) {
        result.language_options = config.optionsFromCliArgs(language_args.items);
    } else if (language_args.items.len != 0) {
        unreachable;
    }
    return result;
}

const ParsedLanguageOption = struct {
    name: []const u8,
    value: ?[]const u8,
    takes_value: bool,
};

fn languageOption(arg: []const u8) ?ParsedLanguageOption {
    if (!@hasDecl(config, "cli_options")) return null;

    const separator = std.mem.indexOfScalar(u8, arg, '=');
    const name = if (separator) |index| arg[0..index] else arg;
    const value = if (separator) |index| arg[index + 1 ..] else null;
    inline for (config.cli_options) |option| {
        if (std.mem.eql(u8, name, option.name)) {
            return .{
                .name = name,
                .value = value,
                .takes_value = option.takes_value,
            };
        }
    }
    return null;
}

fn activeLanguageOption(positional_only: bool, arg: []const u8) ?ParsedLanguageOption {
    if (positional_only) return null;
    return languageOption(arg);
}

fn longOptionValue(arg: []const u8, name: []const u8) ?[]const u8 {
    if (arg.len <= name.len or arg[name.len] != '=' or !std.mem.eql(u8, arg[0..name.len], name)) return null;
    return arg[name.len + 1 ..];
}

fn activeLongOptionValue(positional_only: bool, arg: []const u8, name: []const u8) ?[]const u8 {
    if (positional_only) return null;
    return longOptionValue(arg, name);
}

fn activeRecoveryLongOptionValue(positional_only: bool, arg: []const u8, name: []const u8) ?[]const u8 {
    if (comptime !parser.is_error_recovery_enabled) return null;
    return activeLongOptionValue(positional_only, arg, name);
}

fn activeRecoveryOption(positional_only: bool, arg: []const u8, name: []const u8) bool {
    if (comptime !parser.is_error_recovery_enabled) return false;
    return !positional_only and std.mem.eql(u8, arg, name);
}

fn parseInteger(comptime T: type, value: ?[]const u8, name: []const u8) T {
    const text = value orelse fatal("error: {s} requires a value\n", .{name});
    return std.fmt.parseInt(T, text, 10) catch fatal("error: invalid {s}: {s}\n", .{ name, text });
}

fn printUsage(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll(
        \\usage: parser [OPTIONS] [FILE]
        \\
        \\Arguments:
        \\  [FILE]                            Input file. Reads stdin when omitted.
        \\
        \\Options:
        \\  -h, --help                        Display this help and exit.
        \\  -v, --verbosity <LEVEL>           Diagnostic verbosity.
        \\  -r, --iterations <COUNT>          Repeat the parse process.
        \\  -w, --warmup-iterations <COUNT>   Warm up before measured iterations.
        \\      --enable-stack-overflow-recovery
        \\                                    Enable native stack-overflow recovery.
        \\
    );
    if (comptime parser.is_error_recovery_enabled) {
        try stdout.writeAll(
            \\      --max-errors <COUNT>          Maximum syntax errors to report.
            \\      --recovery-window <BYTES>     Maximum input bytes considered per recovery attempt.
            \\
        );
    }
    if (@hasDecl(config, "cli_help")) try stdout.writeAll(config.cli_help);
    try stdout.flush();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
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
        std.debug.print("\n\x1b[2;3mParser-only timing: zig build -Doptimize=ReleaseFast {s} -- <file> --iterations <n>\x1b[0m\n", .{build_options.api_benchmark_step});
    }
}
