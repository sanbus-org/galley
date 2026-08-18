const std = @import("std");
const generator = @import("galley_generator");
const bootstrap_options = @import("cli_bootstrap_options");
const ctime = @cImport({
    @cInclude("time.h");
});

fn ignoreDiagnostic(_: []const u8) void {}

const max_source_size = 1024 * 1024 * 1024;

const CliOptions = struct {
    parser_type: ?generator.ParserType = null,
    language_dir: ?[]const u8 = null,
    generator_options: generator.Options = .{},
    fill_error_messages: bool = false,
    bootstrap_zig_project: ?bool = null,
    watch: bool = false,
};

const GenerationResult = struct {
    generated_ll: bool = false,
    generated_lr: bool = false,
    created_procedures: bool = false,
    created_config: bool = false,
    created_ll_error_messages: bool = false,
    created_lr_error_messages: bool = false,
};

pub fn main(init: std.process.Init) !void {
    const options = try parseArgs(init);
    const language_dir = options.language_dir orelse fatal("error: language directory is required\n", .{});

    printRunSeparator(init);
    const start = std.Io.Timestamp.now(init.io, .real);
    const result = try generateLanguage(init, language_dir, options);
    const elapsed_ms: i64 = @intCast(@divTrunc(std.Io.Timestamp.now(init.io, .real).nanoseconds - start.nanoseconds, std.time.ns_per_ms));
    try printSuccess(init, language_dir, result, elapsed_ms);

    if (options.bootstrap_zig_project orelse shouldBootstrapByDefault(init.io, init.gpa, language_dir)) {
        try bootstrapZigProject(init.io, init.gpa, init.arena.allocator(), .cwd(), language_dir, result);
    }

    if (options.watch) {
        try watchAndRegenerate(init, language_dir, options);
    }
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
        } else if (std.mem.eql(u8, arg, "--allow-no-ast-tree-procedures")) {
            result.generator_options.allow_no_ast_tree_procedures = true;
        } else if (std.mem.eql(u8, arg, "--with-error-recovery")) {
            result.generator_options.with_error_recovery = true;
        } else if (std.mem.eql(u8, arg, "--no-error-recovery")) {
            result.generator_options.with_error_recovery = false;
        } else if (std.mem.eql(u8, arg, "--with-position-tracking")) {
            result.generator_options.with_position_tracking = true;
        } else if (std.mem.eql(u8, arg, "--no-position-tracking")) {
            result.generator_options.with_position_tracking = false;
        } else if (std.mem.eql(u8, arg, "--with-input-streaming")) {
            result.generator_options.with_input_streaming = true;
        } else if (std.mem.eql(u8, arg, "--no-input-streaming")) {
            result.generator_options.with_input_streaming = false;
        } else if (std.mem.eql(u8, arg, "--ast-for-terminals")) {
            result.generator_options.ast_for_terminals = true;
        } else if (std.mem.eql(u8, arg, "--no-ast-for-terminals")) {
            result.generator_options.ast_for_terminals = false;
        } else if (std.mem.eql(u8, arg, "--fill-error-messages")) {
            result.fill_error_messages = true;
        } else if (std.mem.eql(u8, arg, "--bootstrap-zig-project")) {
            result.bootstrap_zig_project = true;
        } else if (std.mem.eql(u8, arg, "--no-bootstrap-zig-project")) {
            result.bootstrap_zig_project = false;
        } else if (std.mem.eql(u8, arg, "--watch")) {
            result.watch = true;
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
        \\      --allow-no-ast-tree-procedures
        \\                             Treats standard tree-manipulation helpers as
        \\                             no-ops in no-AST mode instead of a compile error.
        \\      --with-error-recovery  Enables syntax-error recovery.
        \\      --no-error-recovery    Disables syntax-error recovery.
        \\      --with-position-tracking
        \\                             Enables line and column tracking.
        \\      --no-position-tracking Disables line and column tracking.
        \\      --with-input-streaming Enables incremental file input.
        \\      --no-input-streaming   Loads complete files before parsing.
        \\      --ast-for-terminals    Enables AST nodes for terminals.
        \\      --no-ast-for-terminals Disables AST nodes for terminals.
        \\      --fill-error-messages  Append missing default syntax error hooks.
        \\      --bootstrap-zig-project
        \\                             Create a minimal Zig project (build.zig,
        \\                             build.zig.zon, src/main.zig) that parses
        \\                             files with the generated parser. Enabled
        \\                             by default when the language directory
        \\                             contains no project files and no parent
        \\                             directory has a build.zig.
        \\      --no-bootstrap-zig-project
        \\                             Skip creating a minimal Zig project even
        \\                             when it would be enabled by default
        \\      --watch                Regenerate the parser whenever the grammar
        \\                             file changes. Keep the previous parser
        \\                             output if regeneration fails.
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

    const has_ll = fileExists(init.io, init.gpa, .cwd(), language_dir, "ll.grm");
    const has_lr = fileExists(init.io, init.gpa, .cwd(), language_dir, "lr.grm");

    if (options.parser_type) |parser_type| {
        const has = switch (parser_type) {
            .ll => has_ll,
            .lr => has_lr,
        };
        if (!has) fatal("error: {s} not found in {s}\n", .{ grammarFileName(parser_type), language_dir });
        try generateParserType(init, language_dir, parser_type, options, &result);
    } else {
        if (!has_ll and !has_lr) fatal("error: no ll.grm or lr.grm found in {s}\n", .{language_dir});
        if (has_ll) try generateParserType(init, language_dir, .ll, options, &result);
        if (has_lr) try generateParserType(init, language_dir, .lr, options, &result);
    }

    result.created_procedures = try createFileIfMissing(init, language_dir, "procedures.zig", defaultProceduresSource);
    result.created_config = try createFileIfMissing(init, language_dir, "config.zig", defaultConfigSource);

    return result;
}

fn generateParserType(
    init: std.process.Init,
    language_dir: []const u8,
    parser_type: generator.ParserType,
    options: CliOptions,
    result: *GenerationResult,
) !void {
    switch (parser_type) {
        .ll => {
            try generateParser(init, language_dir, .ll, options.generator_options);
            result.created_ll_error_messages = try ensureErrorMessages(init, language_dir, .ll, options.generator_options, options.fill_error_messages);
            result.generated_ll = true;
        },
        .lr => {
            try generateParser(init, language_dir, .lr, options.generator_options);
            result.created_lr_error_messages = try ensureErrorMessages(init, language_dir, .lr, options.generator_options, options.fill_error_messages);
            result.generated_lr = true;
        },
    }
}

const WatchedGrammar = struct {
    parser_type: generator.ParserType,
    mtime: i96,
    size: u64,
};

fn watchAndRegenerate(init: std.process.Init, language_dir: []const u8, options: CliOptions) !void {
    var watched: [2]WatchedGrammar = undefined;
    var watched_count: usize = 0;

    const has_ll = fileExists(init.io, init.gpa, .cwd(), language_dir, "ll.grm");
    const has_lr = fileExists(init.io, init.gpa, .cwd(), language_dir, "lr.grm");

    if (options.parser_type) |parser_type| {
        const has = switch (parser_type) {
            .ll => has_ll,
            .lr => has_lr,
        };
        if (!has) fatal("error: {s} not found in {s}\n", .{ grammarFileName(parser_type), language_dir });
        watched[watched_count] = .{ .parser_type = parser_type, .mtime = 0, .size = 0 };
        watched_count += 1;
    } else {
        if (has_ll) {
            watched[watched_count] = .{ .parser_type = .ll, .mtime = 0, .size = 0 };
            watched_count += 1;
        }
        if (has_lr) {
            watched[watched_count] = .{ .parser_type = .lr, .mtime = 0, .size = 0 };
            watched_count += 1;
        }
    }

    for (watched[0..watched_count]) |*entry| {
        try refreshGrammarStat(init, language_dir, entry);
    }

    printStatus(init, "watching {s} for changes; press Ctrl-C to stop\n", .{language_dir});

    while (true) {
        std.Io.sleep(init.io, .fromMilliseconds(250), .awake) catch {};

        for (watched[0..watched_count]) |*entry| {
            const changed = blk: {
                const stat = statGrammar(init, language_dir, entry.parser_type) catch continue;
                break :blk stat.mtime != entry.mtime or stat.size != entry.size;
            };
            if (!changed) continue;

            printRunSeparator(init);
            printStatus(init, "change detected in {s}; regenerating {s} parser\n", .{ grammarFileName(entry.parser_type), @tagName(entry.parser_type) });

            const start = std.Io.Timestamp.now(init.io, .real);
            var result = GenerationResult{};
            const failure: ?anyerror = blk: {
                var did_fail: ?anyerror = null;
                generateParserType(init, language_dir, entry.parser_type, options, &result) catch |e| {
                    did_fail = e;
                };
                break :blk did_fail;
            };
            const elapsed_ms: i64 = @intCast(@divTrunc(std.Io.Timestamp.now(init.io, .real).nanoseconds - start.nanoseconds, std.time.ns_per_ms));

            if (failure) |e| {
                printStatus(init, "regeneration failed ({s}, {d}ms); keeping previous parser output\n", .{ @errorName(e), elapsed_ms });
            } else {
                printStatus(init, "regenerated {s} parser in {d}ms\n", .{ @tagName(entry.parser_type), elapsed_ms });
            }

            try refreshGrammarStat(init, language_dir, entry);
        }
    }
}

fn printStatus(init: std.process.Init, comptime fmt: []const u8, args: anytype) void {
    var stdout_buffer: [2048]u8 = undefined;
    const stdout_file = std.Io.File.stdout();
    var stdout_writer = stdout_file.writer(init.io, &stdout_buffer);
    stdout_writer.interface.print(fmt, args) catch {};
    stdout_writer.interface.flush() catch {};
}

fn printRunSeparator(init: std.process.Init) void {
    var buffer: [64]u8 = undefined;
    const timestamp = runTimestamp(init, &buffer);
    printStatus(init, "\n======================================== [{s}] ========================================\n", .{timestamp});
}

fn runTimestamp(init: std.process.Init, buffer: []u8) []const u8 {
    const now = std.Io.Timestamp.now(init.io, .real);
    var seconds: ctime.time_t = @intCast(@divTrunc(now.nanoseconds, std.time.ns_per_s));
    var local: ctime.tm = undefined;
    if (ctime.localtime_r(&seconds, &local) != null) {
        const len = ctime.strftime(buffer.ptr, buffer.len, "%H:%M:%S", &local);
        if (len > 0 and len < buffer.len) return buffer[0..len];
    }
    return "??:??:??";
}

fn grammarFileName(parser_type: generator.ParserType) []const u8 {
    return switch (parser_type) {
        .ll => "ll.grm",
        .lr => "lr.grm",
    };
}

fn statGrammar(init: std.process.Init, language_dir: []const u8, parser_type: generator.ParserType) !struct { mtime: i96, size: u64 } {
    const path = try std.fs.path.join(init.gpa, &.{ language_dir, grammarFileName(parser_type) });
    defer init.gpa.free(path);
    const stat = try std.Io.Dir.cwd().statFile(init.io, path, .{});
    return .{ .mtime = stat.mtime.nanoseconds, .size = stat.size };
}

fn refreshGrammarStat(init: std.process.Init, language_dir: []const u8, entry: *WatchedGrammar) !void {
    const stat = try statGrammar(init, language_dir, entry.parser_type);
    entry.mtime = stat.mtime;
    entry.size = stat.size;
}

fn bootstrapZigProject(io: std.Io, gpa: std.mem.Allocator, arena_allocator: std.mem.Allocator, dir: std.Io.Dir, language_dir: []const u8, result: GenerationResult) !void {
    const bootstrap_files = [_][]const u8{ "build.zig", "build.zig.zon", "src/main.zig" };
    for (bootstrap_files) |basename| {
        if (fileExists(io, gpa, dir, language_dir, basename)) {
            std.debug.print("error: {s} already exists in {s}; refusing to overwrite\n", .{ basename, language_dir });
            return error.BootstrapFileExists;
        }
    }

    const package_name = try sanitizePackageName(arena_allocator, language_dir);

    const fingerprint = try computeFingerprint(io, arena_allocator, package_name);

    const parser_source: []const u8, const error_messages: []const u8 = if (result.generated_ll) .{
        "_ll-parser.zig",
        "ll_error_messages.zig",
    } else .{ "_lr-parser.zig", "lr_error_messages.zig" };

    const build_zig = try std.mem.replaceOwned(u8, arena_allocator, defaultBuildZigSource, "@@PARSER_SOURCE@@", parser_source);
    const build_zig_1 = try std.mem.replaceOwned(u8, arena_allocator, build_zig, "@@ERROR_MESSAGES@@", error_messages);
    const build_zig_2 = try std.mem.replaceOwned(u8, arena_allocator, build_zig_1, "@@RUNNER_NAME@@", package_name);

    const src_dir = try std.fs.path.join(gpa, &.{ language_dir, "src" });
    defer gpa.free(src_dir);
    try dir.createDirPath(io, src_dir);

    const build_zig_path = try std.fs.path.join(gpa, &.{ language_dir, "build.zig" });
    defer gpa.free(build_zig_path);
    try generator.atomic_file.writeAll(io, dir, build_zig_path, .create, build_zig_2);

    const main_zig_path = try std.fs.path.join(gpa, &.{ language_dir, "src", "main.zig" });
    defer gpa.free(main_zig_path);
    try generator.atomic_file.writeAll(io, dir, main_zig_path, .create, defaultMainZigSource);

    const dependency_hash = try fetchGalleyHash(io, gpa, language_dir);
    defer gpa.free(dependency_hash);

    const zon = try std.mem.replaceOwned(u8, arena_allocator, defaultZonSource, "@@NAME@@", package_name);
    const zon_1 = try std.mem.replaceOwned(u8, arena_allocator, zon, "@@FINGERPRINT@@", fingerprint);
    const zon_2 = try std.mem.replaceOwned(u8, arena_allocator, zon_1, "@@COMMIT@@", bootstrap_options.galley_git_commit);
    const zon_3 = try std.mem.replaceOwned(u8, arena_allocator, zon_2, "@@HASH@@", dependency_hash);

    const zon_path = try std.fs.path.join(gpa, &.{ language_dir, "build.zig.zon" });
    defer gpa.free(zon_path);
    try generator.atomic_file.writeAll(io, dir, zon_path, .create, zon_3);

    std.debug.print("Created build.zig, build.zig.zon, and src/main.zig in {s}\n", .{language_dir});
}

fn sanitizePackageName(allocator: std.mem.Allocator, language_dir: []const u8) ![]const u8 {
    var trimmed = language_dir;
    while (trimmed.len > 0 and trimmed[trimmed.len - 1] == std.fs.path.sep) {
        trimmed = trimmed[0 .. trimmed.len - 1];
    }
    const basename = std.fs.path.basename(trimmed);

    var result: std.ArrayList(u8) = .empty;
    if (std.ascii.isDigit(basename[0])) try result.append(allocator, '_');
    for (basename) |byte| {
        try result.append(allocator, switch (byte) {
            'a'...'z', 'A'...'Z', '0'...'9', '_' => byte,
            else => '_',
        });
    }
    return result.toOwnedSlice(allocator);
}

fn computeFingerprint(io: std.Io, allocator: std.mem.Allocator, package_name: []const u8) ![]const u8 {
    const crc32 = std.hash.Crc32.hash(package_name);

    var random_bytes: [4]u8 = undefined;
    io.random(&random_bytes);
    var low: u32 = std.mem.bytesToValue(u32, &random_bytes);
    if (low == 0x00000000 or low == 0xffffffff) low = 1;

    return std.fmt.allocPrint(allocator, "{x:0>16}", .{(@as(u64, crc32) << 32) | low});
}

fn fetchGalleyHash(io: std.Io, gpa: std.mem.Allocator, language_dir: []const u8) ![]const u8 {
    const git_url = try std.fmt.allocPrint(gpa, "git+{s}#{s}", .{ bootstrap_options.galley_git_url, bootstrap_options.galley_git_commit });
    defer gpa.free(git_url);

    const run_result = std.process.run(gpa, io, .{
        .argv = &.{ "zig", "fetch", git_url },
        .cwd = .{ .path = language_dir },
        .stdout_limit = .limited(4096),
    }) catch |err| fatal("error: unable to run `zig fetch`: {any}\n", .{err});
    defer gpa.free(run_result.stdout);
    defer gpa.free(run_result.stderr);

    if (run_result.term != .exited or run_result.term.exited != 0) {
        std.debug.print("error: `zig fetch {s}` failed:\n{s}\n", .{ git_url, run_result.stderr });
        return error.FetchFailed;
    }
    return gpa.dupe(u8, std.mem.trim(u8, run_result.stdout, " \n\r")) catch unreachable;
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

    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, grammar_path, init.gpa, .limited(max_source_size));
    defer init.gpa.free(source);

    try generator.atomic_file.write(
        init.io,
        .cwd(),
        output_path,
        .replace,
        ParserEmission{
            .allocator = init.arena.allocator(),
            .source = source,
            .parser_type = parser_type,
            .options = options,
        },
        ParserEmission.emit,
    );
}

const ParserEmission = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    parser_type: generator.ParserType,
    options: generator.Options,

    fn emit(self: ParserEmission, writer: *std.Io.Writer) !void {
        try generator.emitParserFromSource(self.allocator, self.source, writer, self.parser_type, self.options);
    }
};

fn ensureErrorMessages(
    init: std.process.Init,
    language_dir: []const u8,
    parser_type: generator.ParserType,
    options: generator.Options,
    fill: bool,
) !bool {
    const basename = errorMessagesFileName(parser_type);
    if (!fill) {
        return try createFileIfMissing(init, language_dir, basename, emptyErrorMessagesSource(parser_type));
    }

    const grammar_name = switch (parser_type) {
        .ll => "ll.grm",
        .lr => "lr.grm",
    };
    const grammar_path = try std.fs.path.join(init.gpa, &.{ language_dir, grammar_name });
    defer init.gpa.free(grammar_path);
    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, grammar_path, init.gpa, .limited(max_source_size));
    defer init.gpa.free(source);

    const filled_source = try generator.generateErrorMessagesAlloc(init.arena.allocator(), source, parser_type, options);

    const path = try std.fs.path.join(init.gpa, &.{ language_dir, basename });
    defer init.gpa.free(path);

    generator.atomic_file.writeAll(init.io, .cwd(), path, .create, filled_source) catch |err| switch (err) {
        error.PathAlreadyExists => {
            try appendMissingErrorMessages(init, path, filled_source, parser_type);
            return false;
        },
        else => |e| return e,
    };
    return true;
}

fn appendMissingErrorMessages(init: std.process.Init, path: []const u8, filled_source: []const u8, parser_type: generator.ParserType) !void {
    const existing = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(max_source_size));
    defer init.gpa.free(existing);

    const merge = try mergeErrorMessages(init.arena.allocator(), existing, filled_source, parser_type);

    for (merge.obsolete_names) |existing_name| {
        std.debug.print("warning: obsolete public error message hook in {s}: {s}\n", .{ path, existing_name });
    }

    if (!merge.appended_any) return;

    try generator.atomic_file.writeAll(init.io, .cwd(), path, .replace, merge.source);
}

const ErrorMessageMerge = struct {
    source: []const u8,
    obsolete_names: []const []const u8,
    appended_any: bool,
};

fn mergeErrorMessages(allocator: std.mem.Allocator, existing: []const u8, filled_source: []const u8, parser_type: generator.ParserType) !ErrorMessageMerge {
    const existing_names = try publicSyntaxErrorFunctionNames(allocator, existing);
    const generated_names = try publicSyntaxErrorFunctionNames(allocator, filled_source);

    var obsolete_names: std.ArrayList([]const u8) = .empty;
    for (existing_names) |existing_name| {
        if (!isValidSyntaxErrorHook(existing_name, generated_names, parser_type)) {
            try obsolete_names.append(allocator, existing_name);
        }
    }

    var combined: std.ArrayList(u8) = .empty;
    try combined.appendSlice(allocator, existing);
    var appended_any = false;
    for (generated_names) |generated_name| {
        if (containsString(existing_names, generated_name)) continue;
        if (!appended_any and combined.items.len > 0 and combined.items[combined.items.len - 1] != '\n') {
            try combined.append(allocator, '\n');
        }
        if (!appended_any) {
            try combined.appendSlice(allocator, "\n// Added by `galley --fill-error-messages`.\n\n");
        }
        const block = functionBlock(filled_source, generated_name) orelse continue;
        try combined.appendSlice(allocator, block);
        if (combined.items.len > 0 and combined.items[combined.items.len - 1] != '\n') {
            try combined.append(allocator, '\n');
        }
        appended_any = true;
    }

    return .{
        .source = combined.items,
        .obsolete_names = try obsolete_names.toOwnedSlice(allocator),
        .appended_any = appended_any,
    };
}

fn publicSyntaxErrorFunctionNames(allocator: std.mem.Allocator, source: []const u8) ![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var offset: usize = 0;
    while (std.mem.indexOfPos(u8, source, offset, "pub fn ")) |index| {
        const name_start = index + "pub fn ".len;
        var name_end = name_start;
        while (name_end < source.len and isIdentifierByte(source[name_end])) : (name_end += 1) {}
        offset = name_end;
        const name = source[name_start..name_end];
        if (std.mem.startsWith(u8, name, "syntax_error_")) {
            try names.append(allocator, name);
        }
    }
    return try names.toOwnedSlice(allocator);
}

fn functionBlock(source: []const u8, name: []const u8) ?[]const u8 {
    const start = findPublicFunction(source, name) orelse return null;
    const search_start = @min(source.len, start + 1);
    const end = std.mem.indexOfPos(u8, source, search_start, "\npub fn ") orelse source.len;
    return source[start..end];
}

fn findPublicFunction(source: []const u8, name: []const u8) ?usize {
    var offset: usize = 0;
    while (std.mem.indexOfPos(u8, source, offset, "pub fn ")) |index| {
        const name_start = index + "pub fn ".len;
        var name_end = name_start;
        while (name_end < source.len and isIdentifierByte(source[name_end])) : (name_end += 1) {}
        if (std.mem.eql(u8, source[name_start..name_end], name)) return index;
        offset = name_end;
    }
    return null;
}

fn containsString(items: []const []const u8, needle: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

fn isValidSyntaxErrorHook(name: []const u8, generated_names: []const []const u8, parser_type: generator.ParserType) bool {
    if (containsString(generated_names, name)) return true;
    return switch (parser_type) {
        .ll => isValidLlSyntaxErrorFallback(name, generated_names),
        .lr => std.mem.eql(u8, name, "syntax_error_lr") or std.mem.eql(u8, name, "syntax_error"),
    };
}

fn isValidLlSyntaxErrorFallback(name: []const u8, generated_names: []const []const u8) bool {
    if (std.mem.eql(u8, name, "syntax_error") or std.mem.eql(u8, name, "syntax_error_ll")) return true;
    if (!std.mem.startsWith(u8, name, "syntax_error_ll_")) return false;
    if (std.mem.indexOf(u8, name, "__expected_") != null) return false;

    for (generated_names) |generated_name| {
        const expected_index = std.mem.indexOf(u8, generated_name, "__expected_") orelse continue;
        if (std.mem.eql(u8, name, generated_name[0..expected_index])) return true;
    }
    return false;
}

fn isIdentifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("missing expected text:\n{s}\n", .{needle});
        return error.MissingExpectedText;
    }
}

test "failed parser generation preserves the previous output" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "_ll-parser.zig",
        .data = "previous generated parser",
    });

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.SyntaxError, generator.atomic_file.write(
        std.testing.io,
        tmp.dir,
        "_ll-parser.zig",
        .replace,
        ParserEmission{
            .allocator = arena.allocator(),
            .source = "Start\n| \"unterminated\n",
            .parser_type = .ll,
            .options = .{ .with_procedures = false, .syntax_error_reporter = &ignoreDiagnostic },
        },
        ParserEmission.emit,
    ));

    const output = try tmp.dir.readFileAlloc(
        std.testing.io,
        "_ll-parser.zig",
        std.testing.allocator,
        .limited(1024),
    );
    defer std.testing.allocator.free(output);
    try std.testing.expectEqualStrings("previous generated parser", output);
}

test "mergeErrorMessages accepts LL fallback hooks and appends missing exact hooks" {
    const existing =
        \\const root = @import("galley");
        \\
        \\pub fn syntax_error_ll_ItemsTail(args: root.SyntaxErrorMessageArgs) ![]const u8 {
        \\    return "custom";
        \\}
        \\
        \\pub fn syntax_error_ll_Item__expected_terminal_a(args: root.SyntaxErrorMessageArgs) ![]const u8 {
        \\    return "already customized";
        \\}
        \\
    ;
    const filled =
        \\const root = @import("galley");
        \\
        \\pub fn syntax_error_ll_ItemsTail__expected_Item_or_end_of_ItemsTail(args: root.SyntaxErrorMessageArgs) ![]const u8 {
        \\    return try root.renderParseDiagnostic(args.allocator, args.diagnostic, args.style);
        \\}
        \\
        \\pub fn syntax_error_ll_Item__expected_terminal_a(args: root.SyntaxErrorMessageArgs) ![]const u8 {
        \\    return try root.renderParseDiagnostic(args.allocator, args.diagnostic, args.style);
        \\}
        \\
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const merge = try mergeErrorMessages(arena.allocator(), existing, filled, .ll);
    try std.testing.expectEqual(@as(usize, 0), merge.obsolete_names.len);
    try std.testing.expect(merge.appended_any);
    try expectContains(merge.source, "pub fn syntax_error_ll_ItemsTail(args: root.SyntaxErrorMessageArgs)");
    try expectContains(merge.source, "pub fn syntax_error_ll_ItemsTail__expected_Item_or_end_of_ItemsTail(args: root.SyntaxErrorMessageArgs)");
    try expectContains(merge.source, "pub fn syntax_error_ll_Item__expected_terminal_a(args: root.SyntaxErrorMessageArgs)");
}

test "mergeErrorMessages accepts LR fallback hooks and appends missing exact hooks" {
    const existing =
        \\const root = @import("galley");
        \\
        \\pub fn syntax_error_lr(args: root.SyntaxErrorMessageArgs) ![]const u8 {
        \\    return "custom";
        \\}
        \\
        \\pub fn syntax_error(args: root.SyntaxErrorMessageArgs) ![]const u8 {
        \\    return "shared";
        \\}
        \\
    ;
    const filled =
        \\const root = @import("galley");
        \\
        \\pub fn syntax_error_lr_state_12_action_19(args: root.SyntaxErrorMessageArgs) ![]const u8 {
        \\    return try root.renderParseDiagnostic(args.allocator, args.diagnostic, args.style);
        \\}
        \\
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const merge = try mergeErrorMessages(arena.allocator(), existing, filled, .lr);
    try std.testing.expectEqual(@as(usize, 0), merge.obsolete_names.len);
    try std.testing.expect(merge.appended_any);
    try expectContains(merge.source, "pub fn syntax_error_lr(args: root.SyntaxErrorMessageArgs)");
    try expectContains(merge.source, "pub fn syntax_error(args: root.SyntaxErrorMessageArgs)");
    try expectContains(merge.source, "pub fn syntax_error_lr_state_12_action_19(args: root.SyntaxErrorMessageArgs)");
}

test "default LR error message scaffold documents parser fallback" {
    try expectContains(defaultLrErrorMessagesSource, "pub fn syntax_error_lr(args: root.SyntaxErrorMessageArgs)");
}

test "mergeErrorMessages reports obsolete syntax error hooks" {
    const existing =
        \\const root = @import("galley");
        \\
        \\pub fn syntax_error_ll_ItemsTail_7(args: root.SyntaxErrorMessageArgs) ![]const u8 {
        \\    return "stale";
        \\}
        \\
    ;
    const filled =
        \\const root = @import("galley");
        \\
        \\pub fn syntax_error_ll_ItemsTail__expected_Item_or_end_of_ItemsTail(args: root.SyntaxErrorMessageArgs) ![]const u8 {
        \\    return try root.renderParseDiagnostic(args.allocator, args.diagnostic, args.style);
        \\}
        \\
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const merge = try mergeErrorMessages(arena.allocator(), existing, filled, .ll);
    try std.testing.expectEqual(@as(usize, 1), merge.obsolete_names.len);
    try std.testing.expectEqualStrings("syntax_error_ll_ItemsTail_7", merge.obsolete_names[0]);
    try std.testing.expect(merge.appended_any);
    try expectContains(merge.source, "pub fn syntax_error_ll_ItemsTail__expected_Item_or_end_of_ItemsTail(args: root.SyntaxErrorMessageArgs)");
}

test "sanitizePackageName derives a valid Zig identifier from the directory name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectEqualStrings("my_lang", try sanitizePackageName(arena.allocator(), "my-lang"));
    try std.testing.expectEqualStrings("json", try sanitizePackageName(arena.allocator(), "json"));
    try std.testing.expectEqualStrings("_2lang", try sanitizePackageName(arena.allocator(), "2lang"));
    try std.testing.expectEqualStrings("path", try sanitizePackageName(arena.allocator(), "/a/b/path/"));
}

test "computeFingerprint keeps crc32 of the name in the high bits and formats 16 hex digits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const fingerprint = try computeFingerprint(std.testing.io, arena.allocator(), "zbtest");
    try std.testing.expectEqual(@as(usize, 16), fingerprint.len);
    const expected_high = @as(u64, std.hash.Crc32.hash("zbtest")) << 32;
    const value = try std.fmt.parseUnsigned(u64, fingerprint, 16);
    try std.testing.expectEqual(expected_high, value & 0xffffffff00000000);
}

test "bootstrapZigProject refuses to overwrite an existing build.zig" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "build.zig",
        .data = "existing",
    });

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(
        error.BootstrapFileExists,
        bootstrapZigProject(std.testing.io, std.testing.allocator, arena.allocator(), tmp.dir, ".", .{}),
    );
}

test "isInsideZigProject is true when the language directory already has project files" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "build.zig",
        .data = "",
    });

    try std.testing.expect(isInsideZigProject(std.testing.io, std.testing.allocator, tmp.dir, "."));
}

test "isInsideZigProject is true when a parent directory has a build.zig" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "lang");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "build.zig",
        .data = "",
    });

    try std.testing.expect(isInsideZigProject(std.testing.io, std.testing.allocator, tmp.dir, "lang"));
}

test "isInsideZigProject is false in a bare language directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.createDirPath(std.testing.io, "lang");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "lang/ll.grm",
        .data = "",
    });

    try std.testing.expect(!isInsideZigProject(std.testing.io, std.testing.allocator, tmp.dir, "lang"));
}

fn createFileIfMissing(init: std.process.Init, dir_path: []const u8, basename: []const u8, contents: []const u8) !bool {
    const path = try std.fs.path.join(init.gpa, &.{ dir_path, basename });
    defer init.gpa.free(path);

    generator.atomic_file.writeAll(init.io, .cwd(), path, .create, contents) catch |err| switch (err) {
        error.PathAlreadyExists => return false,
        else => |e| return e,
    };
    return true;
}

fn shouldBootstrapByDefault(io: std.Io, gpa: std.mem.Allocator, language_dir: []const u8) bool {
    return !isInsideZigProject(io, gpa, .cwd(), language_dir);
}

fn isInsideZigProject(io: std.Io, gpa: std.mem.Allocator, dir: std.Io.Dir, language_dir: []const u8) bool {
    const project_files = [_][]const u8{ "build.zig", "build.zig.zon", "src/main.zig" };
    for (project_files) |basename| {
        if (fileExists(io, gpa, dir, language_dir, basename)) return true;
    }

    var current: []const u8 = language_dir;
    while (std.fs.path.dirname(current)) |parent| {
        if (fileExists(io, gpa, dir, parent, "build.zig")) return true;
        current = parent;
    }

    if (!std.fs.path.isAbsolute(language_dir) and fileExists(io, gpa, dir, "", "build.zig")) return true;

    return false;
}

fn fileExists(io: std.Io, gpa: std.mem.Allocator, dir: std.Io.Dir, dir_path: []const u8, basename: []const u8) bool {
    const path = std.fs.path.join(gpa, &.{ dir_path, basename }) catch return false;
    defer gpa.free(path);
    dir.access(io, path, .{}) catch return false;
    return true;
}

fn printSuccess(init: std.process.Init, language_dir: []const u8, result: GenerationResult, elapsed_ms: i64) !void {
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
        @as(usize, @intFromBool(result.created_ll_error_messages)) +
        @as(usize, @intFromBool(result.created_lr_error_messages));

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
    try stdout.print("generated in {d}ms\n", .{elapsed_ms});
    try stdout.flush();
}

const defaultProceduresSource = @embedFile("templates/procedures.zig");

const defaultConfigSource = @embedFile("templates/config.zig");

const defaultLlErrorMessagesSource = @embedFile("templates/ll_error_messages.zig");

const defaultLrErrorMessagesSource = @embedFile("templates/lr_error_messages.zig");

const defaultBuildZigSource = @embedFile("templates/build.zig");

const defaultMainZigSource = @embedFile("templates/main.zig");

const defaultZonSource = @embedFile("templates/build.zig.zon");

fn errorMessagesFileName(parser_type: generator.ParserType) []const u8 {
    return switch (parser_type) {
        .ll => "ll_error_messages.zig",
        .lr => "lr_error_messages.zig",
    };
}

fn emptyErrorMessagesSource(parser_type: generator.ParserType) []const u8 {
    return switch (parser_type) {
        .ll => defaultLlErrorMessagesSource,
        .lr => defaultLrErrorMessagesSource,
    };
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
