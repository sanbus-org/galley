const std = @import("std");
const build_options = @import("build_options");
const generator = @import("galley_generator");

const max_input_size = 1024 * 1024 * 1024;

const CliOptions = struct {
    parser_type: ?generator.ParserType = null,
    language_dir: ?[]const u8 = null,
    generator_options: generator.Options = .{},
};

const GenerationResult = struct {
    generated_ll: bool = false,
    generated_lr: bool = false,
    created_procedures: bool = false,
    created_config: bool = false,
    created_build_zig: bool = false,
    created_main_zig: bool = false,
    created_tests_dir: bool = false,
    created_parser_test: bool = false,
    created_samples_dir: bool = false,
    created_sample: bool = false,
    standalone: bool = false,
    in_repo_language_name: ?[]const u8 = null,
};

pub fn main(init: std.process.Init) !void {
    const options = try parseArgs(init);
    const language_dir = options.language_dir orelse fatal("error: language directory is required\n", .{});

    const result = try generateLanguage(init, language_dir, options);
    try printSuccess(init, language_dir, result);
}

fn parseArgs(init: std.process.Init) !CliOptions {
    var result = CliOptions{};

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();

    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printUsage(init);
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--parser-type")) {
            const value = args.next() orelse fatal("error: --parser-type requires ll or lr\n", .{});
            result.parser_type = generator.ParserType.parse(value) orelse fatal("error: unsupported parser type: {s}\n", .{value});
        } else if (std.mem.startsWith(u8, arg, "--parser-type=")) {
            const value = arg["--parser-type=".len..];
            result.parser_type = generator.ParserType.parse(value) orelse fatal("error: unsupported parser type: {s}\n", .{value});
        } else if (std.mem.eql(u8, arg, "--with-ast")) {
            result.generator_options.with_ast = true;
        } else if (std.mem.eql(u8, arg, "--no-ast")) {
            result.generator_options.with_ast = false;
        } else if (std.mem.eql(u8, arg, "--with-procedures")) {
            result.generator_options.with_procedures = true;
        } else if (std.mem.eql(u8, arg, "--no-procedures")) {
            result.generator_options.with_procedures = false;
        } else if (std.mem.eql(u8, arg, "--ast-for-terminals")) {
            result.generator_options.ast_for_terminals = true;
        } else if (std.mem.eql(u8, arg, "--no-ast-for-terminals")) {
            result.generator_options.ast_for_terminals = false;
        } else if (std.mem.eql(u8, arg, "--input-size")) {
            const value = args.next() orelse fatal("error: --input-size requires a bit width\n", .{});
            result.generator_options.input_size = std.fmt.parseInt(u16, value, 10) catch fatal("error: invalid --input-size: {s}\n", .{value});
        } else if (std.mem.startsWith(u8, arg, "--input-size=")) {
            const value = arg["--input-size=".len..];
            result.generator_options.input_size = std.fmt.parseInt(u16, value, 10) catch fatal("error: invalid --input-size: {s}\n", .{value});
        } else if (std.mem.startsWith(u8, arg, "-")) {
            fatal("error: unknown argument: {s}\n", .{arg});
        } else if (result.language_dir == null) {
            result.language_dir = arg;
        } else {
            fatal("error: unexpected positional argument: {s}\n", .{arg});
        }
    }

    return result;
}

fn printUsage(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.writeAll(
        \\usage: galley [OPTIONS] <LANGUAGE_DIR>
        \\
        \\Arguments:
        \\  <LANGUAGE_DIR>             Directory containing ll.grm and/or lr.grm.
        \\
        \\Options:
        \\  -h, --help                 Display this help and exit.
        \\      --parser-type ll|lr    Generate only one parser type.
        \\      --with-ast             Enables AST construction.
        \\      --no-ast               Disables AST construction.
        \\      --with-procedures      Enables procedure hooks.
        \\      --no-procedures        Disables procedure hooks.
        \\      --ast-for-terminals    Enables AST nodes for terminals.
        \\      --no-ast-for-terminals Disables AST nodes for terminals.
        \\      --input-size <BITS>    Number of bits required to fit input size.
        \\
    );
    try stdout.flush();
}

fn generateLanguage(init: std.process.Init, language_dir: []const u8, options: CliOptions) !GenerationResult {
    var cwd = std.Io.Dir.cwd();
    var dir = cwd.openDir(init.io, language_dir, .{}) catch |err| switch (err) {
        error.FileNotFound => fatal("error: language directory not found: {s}\n", .{language_dir}),
        error.NotDir => fatal("error: not a directory: {s}\n", .{language_dir}),
        else => |e| return e,
    };
    defer dir.close(init.io);

    var result = GenerationResult{};
    result.in_repo_language_name = try inRepoLanguageName(init, language_dir);
    result.standalone = result.in_repo_language_name == null;

    const has_ll = fileExists(init, language_dir, "ll.grm");
    const has_lr = fileExists(init, language_dir, "lr.grm");

    if (options.parser_type) |parser_type| {
        switch (parser_type) {
            .ll => {
                if (!has_ll) fatal("error: ll.grm not found in {s}\n", .{language_dir});
                try generateParser(init, language_dir, .ll, options.generator_options);
                result.generated_ll = true;
            },
            .lr => {
                if (!has_lr) fatal("error: lr.grm not found in {s}\n", .{language_dir});
                try generateParser(init, language_dir, .lr, options.generator_options);
                result.generated_lr = true;
            },
        }
    } else {
        if (!has_ll and !has_lr) fatal("error: no ll.grm or lr.grm found in {s}\n", .{language_dir});
        if (has_ll) {
            try generateParser(init, language_dir, .ll, options.generator_options);
            result.generated_ll = true;
        }
        if (has_lr) {
            try generateParser(init, language_dir, .lr, options.generator_options);
            result.generated_lr = true;
        }
    }

    result.created_procedures = try createFileIfMissing(init, language_dir, "procedures.zig", defaultProceduresSource);
    result.created_config = try createFileIfMissing(init, language_dir, "config.zig", defaultConfigSource);

    if (result.standalone) {
        const build_source = try standaloneBuildSource(init);
        result.created_build_zig = try createFileIfMissing(init, language_dir, "build.zig", build_source);
        result.created_main_zig = try createFileIfMissing(init, language_dir, "main.zig", standaloneMainSource);
        result.created_tests_dir = try createDirectoryIfMissing(init, language_dir, "tests");
        result.created_parser_test = try createFileIfMissing(init, language_dir, "tests/parser_test.zig", standaloneParserTestSource);
        result.created_samples_dir = try createDirectoryIfMissing(init, language_dir, "samples");
        result.created_sample = try createFileIfMissing(init, language_dir, "samples/code-01", defaultSampleSource);
    }

    return result;
}

fn generateParser(init: std.process.Init, language_dir: []const u8, parser_type: generator.ParserType, options: generator.Options) !void {
    const grammar_name = switch (parser_type) {
        .ll => "ll.grm",
        .lr => "lr.grm",
    };
    const output_name = switch (parser_type) {
        .ll => "_ll-parser.zig",
        .lr => "_lr-parser.zig",
    };

    const grammar_path = try std.fs.path.join(init.gpa, &.{ language_dir, grammar_name });
    defer init.gpa.free(grammar_path);
    const output_path = try std.fs.path.join(init.gpa, &.{ language_dir, output_name });
    defer init.gpa.free(output_path);

    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, grammar_path, init.gpa, .limited(max_input_size));
    defer init.gpa.free(source);

    var output = try std.Io.Dir.cwd().createFile(init.io, output_path, .{ .truncate = true });
    defer output.close(init.io);

    var file_buffer: [8192]u8 = undefined;
    var file_writer = output.writer(init.io, &file_buffer);
    try generator.emitParserFromSource(init.arena.allocator(), source, &file_writer.interface, parser_type, options);
    try file_writer.interface.flush();
}

fn createFileIfMissing(init: std.process.Init, dir_path: []const u8, basename: []const u8, contents: []const u8) !bool {
    const path = try std.fs.path.join(init.gpa, &.{ dir_path, basename });
    defer init.gpa.free(path);

    var file = std.Io.Dir.cwd().createFile(init.io, path, .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => return false,
        else => |e| return e,
    };
    defer file.close(init.io);
    try file.writeStreamingAll(init.io, contents);
    return true;
}

fn createDirectoryIfMissing(init: std.process.Init, dir_path: []const u8, basename: []const u8) !bool {
    const path = try std.fs.path.join(init.gpa, &.{ dir_path, basename });
    defer init.gpa.free(path);

    const status = try std.Io.Dir.cwd().createDirPathStatus(init.io, path, .default_dir);
    return status == .created;
}

fn fileExists(init: std.process.Init, dir_path: []const u8, basename: []const u8) bool {
    const path = std.fs.path.join(init.gpa, &.{ dir_path, basename }) catch return false;
    defer init.gpa.free(path);
    std.Io.Dir.cwd().access(init.io, path, .{}) catch return false;
    return true;
}

fn inRepoLanguageName(init: std.process.Init, language_dir: []const u8) !?[]const u8 {
    const target_abs_z = std.Io.Dir.cwd().realPathFileAlloc(init.io, language_dir, init.gpa) catch return null;
    defer init.gpa.free(target_abs_z);
    const target_abs = target_abs_z[0..target_abs_z.len];

    const languages_abs = try std.fs.path.join(init.gpa, &.{ build_options.galley_root, "languages" });
    defer init.gpa.free(languages_abs);

    const parent = std.fs.path.dirname(target_abs) orelse return null;
    if (!std.mem.eql(u8, parent, languages_abs)) return null;
    return try init.arena.allocator().dupe(u8, std.fs.path.basename(target_abs));
}

fn printSuccess(init: std.process.Init, language_dir: []const u8, result: GenerationResult) !void {
    var stdout_buffer: [2048]u8 = undefined;
    const stdout_file = std.Io.File.stdout();
    const color = stdout_file.supportsAnsiEscapeCodes(init.io) catch false;
    var stdout_writer = stdout_file.writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const green = if (color) "\x1b[32m" else "";
    const cyan = if (color) "\x1b[36m" else "";
    const bold = if (color) "\x1b[1m" else "";
    const reset = if (color) "\x1b[0m" else "";

    const generated_count: usize = @as(usize, @intFromBool(result.generated_ll)) + @as(usize, @intFromBool(result.generated_lr));
    const created_count: usize =
        @as(usize, @intFromBool(result.created_procedures)) +
        @as(usize, @intFromBool(result.created_config)) +
        @as(usize, @intFromBool(result.created_build_zig)) +
        @as(usize, @intFromBool(result.created_main_zig)) +
        @as(usize, @intFromBool(result.created_tests_dir)) +
        @as(usize, @intFromBool(result.created_parser_test)) +
        @as(usize, @intFromBool(result.created_samples_dir)) +
        @as(usize, @intFromBool(result.created_sample));

    try stdout.print("{s}{s}Galley{s} generated {d} parser{s} in {s}{s}{s}\n", .{
        green,
        bold,
        reset,
        generated_count,
        if (generated_count == 1) "" else "s",
        cyan,
        language_dir,
        reset,
    });

    if (created_count > 0) {
        try stdout.print("Created {d} support file{s}.\n", .{ created_count, if (created_count == 1) "" else "s" });
    }

    try stdout.writeAll("Run it with:\n  ");
    if (result.in_repo_language_name) |language_name| {
        if (result.generated_ll) {
            try stdout.print("zig build -Doptimize=ReleaseFast ll-{s} && ./zig-out/bin/ll-{s} <input_path>\n", .{ language_name, language_name });
        } else {
            try stdout.print("zig build -Doptimize=ReleaseFast lr-{s} && ./zig-out/bin/lr-{s} <input_path>\n", .{ language_name, language_name });
        }
    } else {
        if (result.generated_ll) {
            try stdout.print("cd {s} && zig build run-ll\n", .{language_dir});
        } else {
            try stdout.print("cd {s} && zig build run-lr\n", .{language_dir});
        }
        try stdout.print("Test it with:\n  cd {s} && zig build test\n", .{language_dir});
    }
    try stdout.flush();
}

const defaultProceduresSource =
    \\pub const indentation_syntax = false;
    \\pub const Payload = struct {};
    \\
;

const defaultConfigSource =
    \\pub const params = "";
    \\
    \\pub const Options = struct {};
    \\
    \\pub fn optionsFromArgs(args: anytype) Options {
    \\    _ = args;
    \\    return .{};
    \\}
    \\
;

const defaultSampleSource = "Write a sample code here";

const standaloneMainSource =
    \\const std = @import("std");
    \\const parser = @import("generated_parser");
    \\
    \\const Options = struct {
    \\    iterations: u32 = 1,
    \\    warmup_iterations: ?u32 = null,
    \\    verbosity: usize = 0,
    \\};
    \\
    \\pub fn main(init: std.process.Init) !void {
    \\    var stdout_buffer: [1024]u8 = undefined;
    \\    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    \\    const stdout = &stdout_writer.interface;
    \\
    \\    const options = try parseArgs(init);
    \\    const warmup_iterations = options.warmup_iterations orelse options.iterations / 10;
    \\
    \\    var samples_dir = try std.Io.Dir.cwd().openDir(init.io, "samples", .{ .iterate = true });
    \\    defer samples_dir.close(init.io);
    \\
    \\    var walker = try samples_dir.walk(init.gpa);
    \\    defer walker.deinit();
    \\
    \\    var session = try parser.Session.init(init.io, init.gpa, .{ .verbosity = options.verbosity });
    \\    defer session.deinit();
    \\
    \\    var parsed_count: usize = 0;
    \\    while (try walker.next(init.io)) |entry| {
    \\        if (entry.kind != .file) continue;
    \\        if (!std.mem.startsWith(u8, std.fs.path.basename(entry.path), "code-")) continue;
    \\
    \\        const sample_path = try std.fs.path.join(init.gpa, &.{ "samples", entry.path });
    \\        defer init.gpa.free(sample_path);
    \\
    \\        const file = try std.Io.Dir.cwd().openFile(init.io, sample_path, .{
    \\            .mode = .read_only,
    \\            .lock = .exclusive,
    \\        });
    \\        const result = try runSample(&session, file, sample_path, warmup_iterations, options.iterations);
    \\        parsed_count += 1;
    \\        try stdout.print("parsed {s} ({d} bytes", .{ sample_path, result.parsed_bytes });
    \\        if (result.elapsed_ns) |elapsed_ns| {
    \\            const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
    \\            const mbps = @as(f64, @floatFromInt(result.parsed_bytes)) / duration_secs;
    \\            var buffer: [64]u8 = undefined;
    \\            try stdout.print(", {s} ns, {s}/s", .{
    \\                try parser.string_utilities.formatWithThousands(elapsed_ns, &buffer),
    \\                try parser.string_utilities.formatFileSize(mbps, &buffer),
    \\            });
    \\        }
    \\        try stdout.writeAll(")\n");
    \\        try stdout.flush();
    \\    }
    \\
    \\    if (parsed_count == 0) {
    \\        try stdout.writeAll("no samples/code-* files found\n");
    \\    }
    \\    try stdout.flush();
    \\}
    \\
    \\const RunResult = struct {
    \\    parsed_bytes: usize,
    \\    elapsed_ns: ?usize = null,
    \\};
    \\
    \\fn runSample(session: *parser.Session, file: std.Io.File, sample_path: []const u8, warmup_iterations: u32, iterations: u32) !RunResult {
    \\    for (0..warmup_iterations) |_| {
    \\        _ = try session.parseFile(file, sample_path);
    \\    }
    \\
    \\    var total_parsed_bytes: usize = 0;
    \\    const start = std.Io.Clock.awake.now(session.io);
    \\    for (0..iterations) |_| {
    \\        const result = try session.parseFile(file, sample_path);
    \\        total_parsed_bytes += result.parsed_bytes;
    \\    }
    \\
    \\    if (iterations > 1) {
    \\        const end = std.Io.Clock.awake.now(session.io);
    \\        return .{
    \\            .parsed_bytes = total_parsed_bytes,
    \\            .elapsed_ns = @intCast(start.durationTo(end).toNanoseconds()),
    \\        };
    \\    }
    \\
    \\    return .{ .parsed_bytes = total_parsed_bytes };
    \\}
    \\
    \\fn parseArgs(init: std.process.Init) !Options {
    \\    var options = Options{};
    \\    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    \\    defer args.deinit();
    \\
    \\    _ = args.skip();
    \\    while (args.next()) |arg| {
    \\        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
    \\            try printUsage(init);
    \\            std.process.exit(0);
    \\        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--iterations")) {
    \\            const value = args.next() orelse return error.MissingIterations;
    \\            options.iterations = try std.fmt.parseInt(u32, value, 10);
    \\        } else if (std.mem.startsWith(u8, arg, "--iterations=")) {
    \\            options.iterations = try std.fmt.parseInt(u32, arg["--iterations=".len..], 10);
    \\        } else if (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--warmup-iterations")) {
    \\            const value = args.next() orelse return error.MissingWarmupIterations;
    \\            options.warmup_iterations = try std.fmt.parseInt(u32, value, 10);
    \\        } else if (std.mem.startsWith(u8, arg, "--warmup-iterations=")) {
    \\            options.warmup_iterations = try std.fmt.parseInt(u32, arg["--warmup-iterations=".len..], 10);
    \\        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbosity")) {
    \\            const value = args.next() orelse return error.MissingVerbosity;
    \\            options.verbosity = try std.fmt.parseInt(usize, value, 10);
    \\        } else if (std.mem.startsWith(u8, arg, "--verbosity=")) {
    \\            options.verbosity = try std.fmt.parseInt(usize, arg["--verbosity=".len..], 10);
    \\        } else {
    \\            return error.UnknownArgument;
    \\        }
    \\    }
    \\
    \\    if (options.iterations == 0) return error.InvalidIterations;
    \\    return options;
    \\}
    \\
    \\fn printUsage(init: std.process.Init) !void {
    \\    var stdout_buffer: [1024]u8 = undefined;
    \\    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    \\    const stdout = &stdout_writer.interface;
    \\    try stdout.writeAll(
    \\        \\usage: zig build run-ll -- [OPTIONS]
    \\        \\
    \\        \\Options:
    \\        \\  -h, --help                         Display this help and exit.
    \\        \\  -r, --iterations <ITERATIONS>      Repeat each sample parse.
    \\        \\  -w, --warmup-iterations <COUNT>    Warmup parses before timing.
    \\        \\  -v, --verbosity <LEVEL>            Debug verbosity level.
    \\        \\
    \\    );
    \\    try stdout.flush();
    \\}
    \\
;

const standaloneParserTestSource =
    \\const std = @import("std");
    \\const parser = @import("generated_parser");
    \\
    \\const placeholder = "Write a sample code here";
    \\
    \\pub fn main(init: std.process.Init) !void {
    \\    var stdout_buffer: [1024]u8 = undefined;
    \\    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    \\    const stdout = &stdout_writer.interface;
    \\
    \\    const sample = try std.Io.Dir.cwd().readFileAlloc(init.io, "samples/code-01", init.gpa, .limited(1024 * 1024));
    \\    defer init.gpa.free(sample);
    \\
    \\    if (std.mem.eql(u8, sample, placeholder)) {
    \\        try stdout.writeAll(
    \\            "\x1b[33m\x1b[1mGalley test skipped\x1b[0m\n" ++
    \\                "  \x1b[36msamples/code-01\x1b[0m still contains the generated placeholder.\n" ++
    \\                "  Replace it with valid source for this language, then run \x1b[1mzig build test\x1b[0m again.\n",
    \\        );
    \\        try stdout.flush();
    \\        return;
    \\    }
    \\
    \\    var parsed = try parser.parseBytes(init.io, init.gpa, sample, .{ .input_path = "samples/code-01" });
    \\    defer parsed.deinit();
    \\    if (parsed.result.parsed_bytes != sample.len) return error.ShortParse;
    \\
    \\    var session = try parser.Session.init(init.io, init.gpa, .{});
    \\    defer session.deinit();
    \\
    \\    const first = try session.parseBytes(sample, "samples/code-01");
    \\    if (first.parsed_bytes != sample.len) return error.ShortParse;
    \\
    \\    const second = try session.parseBytes(sample, "samples/code-01");
    \\    if (second.parsed_bytes != sample.len) return error.ShortParse;
    \\
    \\    try stdout.writeAll("samples/code-01 parsed\n");
    \\    try stdout.flush();
    \\}
    \\
;

fn standaloneBuildSource(init: std.process.Init) ![]const u8 {
    return try std.fmt.allocPrint(init.arena.allocator(),
        \\const std = @import("std");
        \\
        \\const galley_root = "{s}";
        \\
        \\pub fn build(b: *std.Build) !void {{
        \\    const target = b.standardTargetOptions(.{{}});
        \\    const optimize = b.standardOptimizeOption(.{{}});
        \\
        \\    const generator_common_mod = b.createModule(.{{
        \\        .root_source_file = .{{ .cwd_relative = galley_root ++ "/src/generator/common.zig" }},
        \\        .target = target,
        \\        .optimize = optimize,
        \\    }});
        \\    const ll_generator_mod = b.createModule(.{{
        \\        .root_source_file = .{{ .cwd_relative = galley_root ++ "/src/generator/ll.zig" }},
        \\        .target = target,
        \\        .optimize = optimize,
        \\    }});
        \\    ll_generator_mod.addImport("generator_common", generator_common_mod);
        \\    const lr_generator_mod = b.createModule(.{{
        \\        .root_source_file = .{{ .cwd_relative = galley_root ++ "/src/generator/lr.zig" }},
        \\        .target = target,
        \\        .optimize = optimize,
        \\    }});
        \\    lr_generator_mod.addImport("generator_common", generator_common_mod);
        \\
        \\    const procedures_mod = b.addModule("procedures", .{{
        \\        .root_source_file = b.path("procedures.zig"),
        \\        .target = target,
        \\    }});
        \\    const config_mod = b.addModule("config", .{{
        \\        .root_source_file = b.path("config.zig"),
        \\        .target = target,
        \\    }});
        \\
        \\    const ll_mod = try addParser(b, target, optimize, procedures_mod, config_mod, ll_generator_mod, lr_generator_mod, "ll", "_ll-parser.zig");
        \\    const lr_mod = try addParser(b, target, optimize, procedures_mod, config_mod, ll_generator_mod, lr_generator_mod, "lr", "_lr-parser.zig");
        \\    const preferred_mod = ll_mod orelse lr_mod;
        \\    if (preferred_mod) |parser_mod| {{
        \\        addTests(b, target, optimize, parser_mod);
        \\    }}
        \\}}
        \\
        \\fn addParser(
        \\    b: *std.Build,
        \\    target: std.Build.ResolvedTarget,
        \\    optimize: std.builtin.OptimizeMode,
        \\    procedures_mod: *std.Build.Module,
        \\    config_mod: *std.Build.Module,
        \\    ll_generator_mod: *std.Build.Module,
        \\    lr_generator_mod: *std.Build.Module,
        \\    parser_type: []const u8,
        \\    parser_path: []const u8,
        \\) !?*std.Build.Module {{
        \\    b.build_root.handle.access(b.graph.io, parser_path, .{{}}) catch |err| switch (err) {{
        \\        error.FileNotFound => return null,
        \\        else => |e| return e,
        \\    }};
        \\
        \\    const parser_mod = b.addModule("parser", .{{
        \\        .root_source_file = b.path(parser_path),
        \\        .target = target,
        \\    }});
        \\
        \\    const exe_name = try std.mem.concat(b.allocator, u8, &.{{ parser_type, "-parser" }});
        \\    const galley_mod = b.addModule(exe_name, .{{
        \\        .root_source_file = .{{ .cwd_relative = galley_root ++ "/src/parser_library.zig" }},
        \\        .target = target,
        \\        .optimize = optimize,
        \\        .imports = &.{{
        \\            .{{ .name = "procedures", .module = procedures_mod }},
        \\            .{{ .name = "config", .module = config_mod }},
        \\            .{{ .name = "parser", .module = parser_mod }},
        \\        }},
        \\    }});
        \\    galley_mod.addImport("galley", galley_mod);
        \\    procedures_mod.addImport("galley", galley_mod);
        \\    procedures_mod.addImport("ll_generator", ll_generator_mod);
        \\    procedures_mod.addImport("lr_generator", lr_generator_mod);
        \\    config_mod.addImport("galley", galley_mod);
        \\    parser_mod.addImport("galley", galley_mod);
        \\
        \\    const exe_mod = b.createModule(.{{
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\        .link_libc = true,
        \\        .imports = &.{{
        \\            .{{ .name = "generated_parser", .module = galley_mod }},
        \\        }},
        \\    }});
        \\
        \\    const exe = b.addExecutable(.{{
        \\        .name = exe_name,
        \\        .root_module = exe_mod,
        \\    }});
        \\    const install_artifact = b.addInstallArtifact(exe, .{{}});
        \\    const build_step = b.step(parser_type, "Build the generated parser");
        \\    build_step.dependOn(&install_artifact.step);
        \\
        \\    const run_step_name = try std.mem.concat(b.allocator, u8, &.{{ "run-", parser_type }});
        \\    const run_step = b.step(run_step_name, "Run the generated parser");
        \\    const run_cmd = b.addRunArtifact(exe);
        \\    run_step.dependOn(&run_cmd.step);
        \\    run_cmd.step.dependOn(&install_artifact.step);
        \\    if (b.args) |args| {{
        \\        run_cmd.addArgs(args);
        \\    }}
        \\
        \\    return galley_mod;
        \\}}
        \\
        \\fn addTests(
        \\    b: *std.Build,
        \\    target: std.Build.ResolvedTarget,
        \\    optimize: std.builtin.OptimizeMode,
        \\    parser_mod: *std.Build.Module,
        \\) void {{
        \\    const test_mod = b.createModule(.{{
        \\        .root_source_file = b.path("tests/parser_test.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\        .link_libc = true,
        \\        .imports = &.{{
        \\            .{{ .name = "generated_parser", .module = parser_mod }},
        \\        }},
        \\    }});
        \\    const tests = b.addExecutable(.{{ .name = "parser-tests", .root_module = test_mod }});
        \\    const run_tests = b.addRunArtifact(tests);
        \\    const test_step = b.step("test", "Run parser tests");
        \\    test_step.dependOn(&run_tests.step);
        \\}}
        \\
    , .{build_options.galley_root});
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
