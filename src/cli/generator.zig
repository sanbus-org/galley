const std = @import("std");
const generator = @import("galley_generator");
const bootstrap_options = @import("cli_bootstrap_options");
const ctime = @cImport({
    @cInclude("time.h");
});

fn ignoreDiagnostic(_: []const u8) void {}

const max_source_size = 1024 * 1024 * 1024;

/// Option flags materialize as in-place edits to the language's
/// `config.zig`: a flag present on the command line rewrites its constant
/// (surgically, preserving all other bytes); an absent flag leaves the
/// value untouched.
///
/// Generation itself never sees these values — emitted parsers are
/// configuration-independent and read `config.zig` at comptime.
const ConfigEdits = struct {
    ast: ?bool = null,
    procedures: ?bool = null,
    error_recovery: ?bool = null,
    ast_for_terminals: ?bool = null,
    position_tracking: ?bool = null,
    input_streaming: ?bool = null,
    allow_no_ast_tree_procedures: ?bool = null,
    require_reduction_procedures: ?bool = null,
    indentation_syntax: ?bool = null,

    fn apply(self: ConfigEdits, init: std.process.Init, gpa: std.mem.Allocator, language_dir: []const u8) !void {
        const path = try std.fs.path.join(gpa, &.{ language_dir, "config.zig" });
        defer gpa.free(path);
        var cwd = std.Io.Dir.cwd();
        const existing = cwd.readFileAlloc(init.io, path, gpa, .limited(max_source_size)) catch |err| switch (err) {
            error.FileNotFound => fatal("error: {s} not found\n", .{path}),
            else => |e| return e,
        };
        defer gpa.free(existing);

        // Each edit allocates a fresh buffer owned here; the previous one is
        // freed as it is replaced.
        var updated: ?[]const u8 = null;
        defer if (updated) |buffer| gpa.free(buffer);
        inline for (.{
            .{ "ast", self.ast },
            .{ "procedures", self.procedures },
            .{ "error_recovery", self.error_recovery },
            .{ "ast_for_terminals", self.ast_for_terminals },
            .{ "position_tracking", self.position_tracking },
            .{ "input_streaming", self.input_streaming },
            .{ "allow_no_ast_tree_procedures", self.allow_no_ast_tree_procedures },
            .{ "require_reduction_procedures", self.require_reduction_procedures },
            .{ "indentation_syntax", self.indentation_syntax },
        }) |edit| {
            if (edit[1]) |value| {
                const next = try generator.config_file.editedConstantSource(
                    gpa,
                    updated orelse existing,
                    edit[0],
                    if (value) "true" else "false",
                );
                if (updated) |previous| gpa.free(previous);
                updated = next;
            }
        }
        if (updated) |buffer| {
            if (!std.mem.eql(u8, buffer, existing)) {
                var cwd_write = std.Io.Dir.cwd();
                try cwd_write.writeFile(init.io, .{ .sub_path = path, .data = buffer });
            }
        }
    }
};

const CliOptions = struct {
    parser_type: ?generator.ParserType = null,
    language_dir: ?[]const u8 = null,
    edits: ConfigEdits = .{},
    fill_error_messages: bool = false,
    bootstrap_zig_project: bool = false,
    watch: bool = false,
    emit_metadata: bool = false,
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

    if (options.emit_metadata) {
        try writeMetadataAndProcedures(init, language_dir);
    }

    if (options.bootstrap_zig_project) {
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
            result.edits.ast = true;
        } else if (std.mem.eql(u8, arg, "--no-ast")) {
            result.edits.ast = false;
        } else if (std.mem.eql(u8, arg, "--indentation-syntax")) {
            result.edits.indentation_syntax = true;
        } else if (std.mem.eql(u8, arg, "--no-indentation-syntax")) {
            result.edits.indentation_syntax = false;
        } else if (std.mem.eql(u8, arg, "--with-procedures")) {
            result.edits.procedures = true;
        } else if (std.mem.eql(u8, arg, "--no-procedures")) {
            result.edits.procedures = false;
        } else if (std.mem.eql(u8, arg, "--allow-no-ast-tree-procedures")) {
            result.edits.allow_no_ast_tree_procedures = true;
        } else if (std.mem.eql(u8, arg, "--require-reduction-procedures")) {
            result.edits.require_reduction_procedures = true;
        } else if (std.mem.eql(u8, arg, "--no-require-reduction-procedures")) {
            result.edits.require_reduction_procedures = false;
        } else if (std.mem.eql(u8, arg, "--with-error-recovery")) {
            result.edits.error_recovery = true;
        } else if (std.mem.eql(u8, arg, "--no-error-recovery")) {
            result.edits.error_recovery = false;
        } else if (std.mem.eql(u8, arg, "--with-position-tracking")) {
            result.edits.position_tracking = true;
        } else if (std.mem.eql(u8, arg, "--no-position-tracking")) {
            result.edits.position_tracking = false;
        } else if (std.mem.eql(u8, arg, "--with-input-streaming")) {
            result.edits.input_streaming = true;
        } else if (std.mem.eql(u8, arg, "--no-input-streaming")) {
            result.edits.input_streaming = false;
        } else if (std.mem.eql(u8, arg, "--ast-for-terminals")) {
            result.edits.ast_for_terminals = true;
        } else if (std.mem.eql(u8, arg, "--no-ast-for-terminals")) {
            result.edits.ast_for_terminals = false;
        } else if (std.mem.eql(u8, arg, "--fill-error-messages")) {
            result.fill_error_messages = true;
        } else if (std.mem.eql(u8, arg, "--emit-metadata")) {
            result.emit_metadata = true;
        } else if (std.mem.eql(u8, arg, "--bootstrap-zig-project")) {
            result.bootstrap_zig_project = true;
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
        \\
        \\Option flags edit `config.zig` in this directory in place (the file
        \\is created from documented defaults when missing). An explicit flag
        \\rewrites its constant; an absent flag leaves the value untouched.
        \\Generated parsers read these constants at compile time, so changing
        \\configuration requires recompiling consumers, never regenerating.
        \\
        \\      --with-ast             Writes `ast = true`.
        \\      --no-ast               Writes `ast = false`.
        \\      --with-procedures      Writes `procedures = true`.
        \\      --no-procedures        Writes `procedures = false`.
        \\      --allow-no-ast-tree-procedures
        \\                             Writes `allow_no_ast_tree_procedures =
        \\                             true` (standard tree-manipulation
        \\                             helpers become no-ops in no-AST mode).
        \\      --require-reduction-procedures
        \\                             Writes `require_reduction_procedures =
        \\                             true` (missing `reduction_<Var>_<N>`
        \\                             hooks warn at generation and fail
        \\                             compilation).
        \\      --no-require-reduction-procedures
        \\                             Writes `require_reduction_procedures =
        \\                             false` (missing hooks stay silent).
        \\      --with-error-recovery  Writes `error_recovery = true`.
        \\      --no-error-recovery    Writes `error_recovery = false`.
        \\      --with-position-tracking
        \\                             Writes `position_tracking = true`.
        \\      --no-position-tracking Writes `position_tracking = false`.
        \\      --with-input-streaming Writes `input_streaming = true`.
        \\      --no-input-streaming   Writes `input_streaming = false`.
        \\      --ast-for-terminals    Writes `ast_for_terminals = true`.
        \\      --no-ast-for-terminals Writes `ast_for_terminals = false`.
        \\      --indentation-syntax   Writes `indentation_syntax = true`.
        \\      --no-indentation-syntax
        \\                             Writes `indentation_syntax = false`.
        \\      --fill-error-messages  Append missing default syntax error hooks.
        \\      --emit-metadata        Write metadata.json and procedures.zig
        \\                             next to the generated parser(s); the
        \\                             bindings workflow consumes both.
        \\      --bootstrap-zig-project
        \\                             Create a minimal Zig project (build.zig,
        \\                             build.zig.zon, src/main.zig) that parses
        \\                             files via addParserModule. Stub for a new
        \\                             grammar, not a second API; see
        \\                             examples/zig. Off by default.
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

    // The config file is ensured first (created from documented defaults
    // when missing) so that flag edits below always have a target; edits
    // then rewrite constants in place before any parser is emitted.
    var config_source = std.Io.Writer.Allocating.init(init.gpa);
    defer config_source.deinit();
    try generator.config_file.write(&config_source.writer, .{}, false);
    result.created_config = try createFileIfMissing(init.io, init.gpa, language_dir, "config.zig", config_source.written());
    try options.edits.apply(init, init.gpa, language_dir);

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

    result.created_procedures = try createFileIfMissing(init.io, init.gpa, language_dir, "procedures.zig", defaultProceduresSource);

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
            try generateParser(init, language_dir, .ll);
            if (options.fill_error_messages) {
                result.created_ll_error_messages = try fillErrorMessages(init.io, init.gpa, init.arena.allocator(), language_dir, .ll);
            }
            result.generated_ll = true;
        },
        .lr => {
            try generateParser(init, language_dir, .lr);
            if (options.fill_error_messages) {
                result.created_lr_error_messages = try fillErrorMessages(init.io, init.gpa, init.arena.allocator(), language_dir, .lr);
            }
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

    const parser_type_name: []const u8 = if (result.generated_ll) "ll" else "lr";
    const build_zig = try std.mem.replaceOwned(u8, arena_allocator, defaultBuildZigSource, "@@PARSER_TYPE@@", parser_type_name);
    const build_zig_2 = try std.mem.replaceOwned(u8, arena_allocator, build_zig, "@@RUNNER_NAME@@", package_name);

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

fn generateParser(init: std.process.Init, language_dir: []const u8, parser_type: generator.ParserType) !void {
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

    // Emit the correct warning: recovery annotations are inert when `config.error_recovery` is
    // disabled, regardless of generator Options. The CLI is the only place that knows both the
    // grammar fact and the effective config after `--with-` / `--no-` edits, so the check lives
    // here rather than in the generator (which is now config-independent).
    if (sourceHasRecoveryAnnotations(init.arena.allocator(), source) and !isErrorRecoveryEnabled(init, language_dir)) {
        std.log.warn("grammar recovery annotations are ignored because error recovery is disabled", .{});
    }

    if (isRequireReductionProceduresEnabled(init, language_dir)) {
        warnMissingReductionProcedures(init, language_dir, source, parser_type);
    }

    try generator.atomic_file.write(
        init.io,
        .cwd(),
        output_path,
        .replace,
        ParserEmission{
            .allocator = init.arena.allocator(),
            .source = source,
            .parser_type = parser_type,
        },
        ParserEmission.emit,
    );
}

fn isErrorRecoveryEnabled(init: std.process.Init, language_dir: []const u8) bool {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const path = std.fs.path.join(arena.allocator(), &.{ language_dir, "config.zig" }) catch return false;
    const content = std.Io.Dir.cwd().readFileAlloc(init.io, path, arena.allocator(), .limited(max_source_size)) catch return false;
    const prefix = "pub const error_recovery = ";
    const idx = std.mem.indexOf(u8, content, prefix) orelse return false;
    const rest = content[idx + prefix.len ..];
    if (std.mem.startsWith(u8, rest, "true")) return true;
    if (std.mem.startsWith(u8, rest, "false")) return false;
    return false;
}

fn isRequireReductionProceduresEnabled(init: std.process.Init, language_dir: []const u8) bool {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const path = std.fs.path.join(arena.allocator(), &.{ language_dir, "config.zig" }) catch return false;
    const content = std.Io.Dir.cwd().readFileAlloc(init.io, path, arena.allocator(), .limited(max_source_size)) catch return false;
    const prefix = "pub const require_reduction_procedures = ";
    const idx = std.mem.indexOf(u8, content, prefix) orelse return false;
    const rest = content[idx + prefix.len ..];
    if (std.mem.startsWith(u8, rest, "true")) return true;
    if (std.mem.startsWith(u8, rest, "false")) return false;
    return false;
}

/// Best-effort text scan for a `reduction_<Var>_<N>` declaration in
/// `procedures.zig`. Generation-time warnings use this; the generated
/// parser's `@hasDecl` check remains authoritative at compile time.
fn hasProcedureDeclaration(source: []const u8, name: []const u8) bool {
    var offset: usize = 0;
    while (std.mem.indexOfPos(u8, source, offset, name)) |index| {
        const before_ok = index == 0 or !isIdentifierByte(source[index - 1]);
        const after = index + name.len;
        const after_ok = after >= source.len or !isIdentifierByte(source[after]);
        if (before_ok and after_ok) return true;
        offset = index + 1;
    }
    return false;
}

fn warnMissingReductionProcedures(init: std.process.Init, language_dir: []const u8, grammar_source: []const u8, parser_type: generator.ParserType) void {
    const required = switch (parser_type) {
        // The LL emitter plans from auto-factored productions, so warnings
        // must collect from the same factored shapes the generated
        // comptime check enforces; LR plans the grammar as written.
        .ll => generator.requiredLLReductionProceduresFromSource(init.arena.allocator(), grammar_source) catch return,
        .lr => generator.requiredReductionProceduresFromSource(init.arena.allocator(), grammar_source) catch return,
    };
    const procedures_path = std.fs.path.join(init.gpa, &.{ language_dir, "procedures.zig" }) catch return;
    defer init.gpa.free(procedures_path);
    const procedures_source = std.Io.Dir.cwd().readFileAlloc(init.io, procedures_path, init.gpa, .limited(max_source_size)) catch |err| switch (err) {
        error.FileNotFound => {
            std.log.warn("require_reduction_procedures is enabled but procedures.zig was not found", .{});
            return;
        },
        else => return,
    };
    defer init.gpa.free(procedures_source);
    for (required) |item| {
        if (!hasProcedureDeclaration(procedures_source, item.procedure_name)) {
            std.log.warn("missing reduction procedure '{s}' for production {s} (rhs_index {s})", .{ item.procedure_name, item.shape, item.rhs_index });
        }
    }
}

fn sourceHasRecoveryAnnotations(allocator: std.mem.Allocator, source: []const u8) bool {
    // Use the real grammar parser so the check is not a fragile substring search.
    const grammar = generator.parseGrammar(allocator, source) catch return false;
    for (grammar.rules) |rule| {
        if (rule.annotations.recovery_points.len != 0) return true;
        for (rule.right_hand_sides) |rhs| {
            if (rhs.annotations.recovery_points.len != 0) return true;
            for (rhs.symbols) |sym| {
                if (sym.annotations.recovery_points.len != 0) return true;
            }
        }
    }
    return false;
}

const ParserEmission = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    parser_type: generator.ParserType,

    fn emit(self: ParserEmission, writer: *std.Io.Writer) !void {
        try generator.emitParserFromSource(self.allocator, self.source, writer, self.parser_type, .{});
    }
};

fn fillErrorMessages(
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    language_dir: []const u8,
    parser_type: generator.ParserType,
) !bool {
    const basename = errorMessagesFileName(parser_type);

    const grammar_name = switch (parser_type) {
        .ll => "ll.grm",
        .lr => "lr.grm",
    };
    const grammar_path = try std.fs.path.join(gpa, &.{ language_dir, grammar_name });
    defer gpa.free(grammar_path);
    const source = try std.Io.Dir.cwd().readFileAlloc(io, grammar_path, gpa, .limited(max_source_size));
    defer gpa.free(source);

    const filled_source = try generator.generateErrorMessagesAlloc(arena, source, parser_type, .{});

    const path = try std.fs.path.join(gpa, &.{ language_dir, basename });
    defer gpa.free(path);

    generator.atomic_file.writeAll(io, .cwd(), path, .create, filled_source) catch |err| switch (err) {
        error.PathAlreadyExists => {
            try appendMissingErrorMessages(io, gpa, arena, path, filled_source, parser_type);
            return false;
        },
        else => |e| return e,
    };
    return true;
}

fn appendMissingErrorMessages(io: std.Io, gpa: std.mem.Allocator, arena: std.mem.Allocator, path: []const u8, filled_source: []const u8, parser_type: generator.ParserType) !void {
    const existing = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(max_source_size));
    defer gpa.free(existing);

    const merge = try mergeErrorMessages(arena, existing, filled_source, parser_type);

    for (merge.obsolete_names) |existing_name| {
        std.debug.print("warning: obsolete public error message hook in {s}: {s}\n", .{ path, existing_name });
    }

    if (!merge.appended_any) return;

    try generator.atomic_file.writeAll(io, .cwd(), path, .replace, merge.source);
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

test "plain generation does not materialize error message files; fill does" {
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var cwd = std.Io.Dir.cwd();
    const language_dir = try std.fmt.allocPrint(std.testing.allocator, ".galley-test-err-msg-{d}", .{std.Io.Timestamp.now(std.testing.io, .real).nanoseconds});
    defer std.testing.allocator.free(language_dir);
    try cwd.createDirPath(io, language_dir);
    defer cwd.deleteTree(io, language_dir) catch {};

    const grammar_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/ll.grm", .{language_dir});
    defer std.testing.allocator.free(grammar_path);
    try cwd.writeFile(io, .{ .sub_path = grammar_path, .data =
        \\Document
        \\| PairList
        \\|
        \\
        \\PairList
        \\| Pair PairListTail
        \\|
        \\
        \\PairListTail
        \\|
        \\
        \\Pair
        \\| Key ":" Number
        \\|
        \\
        \\Key
        \\| letter KeyTail
        \\
        \\KeyTail
        \\| letter KeyTail
        \\| digit KeyTail
        \\|
        \\
        \\Number
        \\| digit NumberTail
        \\
        \\NumberTail
        \\| digit NumberTail
        \\|
        \\
    });

    // Plain generation never touches error-message files.
    try std.testing.expect(!fileExists(io, std.testing.allocator, cwd, language_dir, "ll_error_messages.zig"));

    // --fill-error-messages creates the scaffold.
    const created = try fillErrorMessages(io, std.testing.allocator, arena, language_dir, .ll);
    try std.testing.expect(created);
    try std.testing.expect(fileExists(io, std.testing.allocator, cwd, language_dir, "ll_error_messages.zig"));

    // A second fill over an existing file appends rather than recreates.
    const recreated = try fillErrorMessages(io, std.testing.allocator, arena, language_dir, .ll);
    try std.testing.expect(!recreated);
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

test "config flag edits rewrite constants and preserve surrounding bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const existing =
        \\// user comment
        \\pub const ast = true;
        \\pub const error_recovery = true;
        \\
    ;
    const edited = try generator.config_file.editedConstantSource(arena.allocator(), existing, "ast", "false");
    try std.testing.expectEqualStrings(
        \\// user comment
        \\pub const ast = false;
        \\pub const error_recovery = true;
        \\
    , edited);

    // Editing a second constant composes on the first edit's output.
    const edited_twice = try generator.config_file.editedConstantSource(arena.allocator(), edited, "error_recovery", "false");
    try std.testing.expectEqualStrings(
        \\// user comment
        \\pub const ast = false;
        \\pub const error_recovery = false;
        \\
    , edited_twice);

    try std.testing.expectError(error.MissingConstant, generator.config_file.editedConstantSource(arena.allocator(), existing, "nonexistent", "true"));

    // Annotated constants keep their type: `write()` emits
    // `pub const position_tracking: ?bool = ...`, and every checked-in
    // language config shares that shape, so the editor must match it.
    // Regression test for `galley languages/json --with-position-tracking`
    // failing with MissingConstant.
    const annotated =
        \\pub const ast = true;
        \\pub const position_tracking: ?bool = null;
        \\
    ;
    const edited_annotated = try generator.config_file.editedConstantSource(arena.allocator(), annotated, "position_tracking", "true");
    try std.testing.expectEqualStrings(
        \\pub const ast = true;
        \\pub const position_tracking: ?bool = true;
        \\
    , edited_annotated);

    // A name that prefixes another constant must not match it.
    const prefixed =
        \\pub const ast = true;
        \\pub const ast_for_terminals = false;
        \\
    ;
    const edited_prefix = try generator.config_file.editedConstantSource(arena.allocator(), prefixed, "ast", "false");
    try std.testing.expectEqualStrings(
        \\pub const ast = false;
        \\pub const ast_for_terminals = false;
        \\
    , edited_prefix);
}

test "every constant written by config_file.write stays editable" {
    // Writer/editor drift guard: `write()` is the single source of truth for
    // the config shape, and both CLIs apply flags through
    // `editedConstantSource`. If either side changes the line layout, this
    // fails instead of a real `galley languages/<lang> --flag` invocation.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var config_buffer = std.Io.Writer.Allocating.init(arena.allocator());
    try generator.config_file.write(&config_buffer.writer, .{}, false);
    const fresh = config_buffer.written();

    inline for (.{
        "ast",
        "procedures",
        "allow_no_ast_tree_procedures",
        "require_reduction_procedures",
        "error_recovery",
        "ast_for_terminals",
        "position_tracking",
        "input_streaming",
        "indentation_syntax",
    }) |name| {
        const edited_true = try generator.config_file.editedConstantSource(arena.allocator(), fresh, name, "true");
        const edited_false = try generator.config_file.editedConstantSource(arena.allocator(), fresh, name, "false");
        _ = edited_true;
        _ = edited_false;
    }

    // The annotated constant keeps its type through the edit.
    const edited_position = try generator.config_file.editedConstantSource(arena.allocator(), fresh, "position_tracking", "true");
    try std.testing.expect(std.mem.indexOf(u8, edited_position, "pub const position_tracking: ?bool = true;") != null);
}

test "hasProcedureDeclaration matches whole hook names only" {
    try std.testing.expect(hasProcedureDeclaration("pub fn reduction_Foo_0(", "reduction_Foo_0"));
    try std.testing.expect(hasProcedureDeclaration("pub const reduction_Foo_0 = helper;", "reduction_Foo_0"));
    try std.testing.expect(!hasProcedureDeclaration("pub fn reduction_Foo_01(", "reduction_Foo_0"));
    try std.testing.expect(!hasProcedureDeclaration("pub fn reduction_Foo_0x(", "reduction_Foo_0"));
    try std.testing.expect(!hasProcedureDeclaration("pub fn other(", "reduction_Foo_0"));
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

test "CLI error_recovery flag does not affect recovery annotation detection (regression for inverted warning)" {
    // Reproduces `galley languages/galley --with-error-recovery` spuriously warning
    // that annotations were ignored. Generation is now config-independent: has_recovery_annotations
    // is a pure grammar fact, and error_recovery is a comptime config gate. This test ensures
    // the flag never influences the grammar fact and that config edits are orthogonal.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const annotated =
        \\Start@!^"sync"
        \\| "a"
        \\
    ;
    for ([_]bool{ true, false }) |flag| {
        const ll = try generator.generateParserAlloc(arena.allocator(), annotated, .ll, .{ .with_error_recovery = flag });
        try std.testing.expect(std.mem.indexOf(u8, ll, "pub const has_recovery_annotations = true;") != null);
        try std.testing.expect(std.mem.indexOf(u8, ll, "pub const is_error_recovery_enabled = config.error_recovery;") != null);
        const lr = try generator.generateParserAlloc(arena.allocator(), annotated, .lr, .{ .with_error_recovery = flag });
        try std.testing.expect(std.mem.indexOf(u8, lr, "pub const has_recovery_annotations = true;") != null);
        try std.testing.expect(std.mem.indexOf(u8, lr, "pub const is_error_recovery_enabled = config.error_recovery;") != null);
    }

    const plain =
        \\Start
        \\| "a"
        \\
    ;
    for ([_]bool{ true, false }) |flag| {
        const ll = try generator.generateParserAlloc(arena.allocator(), plain, .ll, .{ .with_error_recovery = flag });
        try std.testing.expect(std.mem.indexOf(u8, ll, "pub const has_recovery_annotations = false;") != null);
        const lr = try generator.generateParserAlloc(arena.allocator(), plain, .lr, .{ .with_error_recovery = flag });
        try std.testing.expect(std.mem.indexOf(u8, lr, "pub const has_recovery_annotations = false;") != null);
    }

    // Config edits must toggle the file without needing regeneration.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    {
        var buf = std.Io.Writer.Allocating.init(arena.allocator());
        defer buf.deinit();
        try generator.config_file.write(&buf.writer, .{ .with_error_recovery = false }, false);
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "config.zig", .data = buf.written() });
    }
    {
        const content = try tmp.dir.readFileAlloc(std.testing.io, "config.zig", arena.allocator(), .limited(8192));
        const edited = try generator.config_file.editedConstantSource(arena.allocator(), content, "error_recovery", "true");
        try std.testing.expect(std.mem.indexOf(u8, edited, "pub const error_recovery = true;") != null);
        try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "config.zig", .data = edited });
    }
    {
        const content = try tmp.dir.readFileAlloc(std.testing.io, "config.zig", arena.allocator(), .limited(8192));
        const edited = try generator.config_file.editedConstantSource(arena.allocator(), content, "error_recovery", "false");
        try std.testing.expect(std.mem.indexOf(u8, edited, "pub const error_recovery = false;") != null);
    }
}

fn createFileIfMissing(io: std.Io, gpa: std.mem.Allocator, dir_path: []const u8, basename: []const u8, contents: []const u8) !bool {
    const path = try std.fs.path.join(gpa, &.{ dir_path, basename });
    defer gpa.free(path);

    generator.atomic_file.writeAll(io, .cwd(), path, .create, contents) catch |err| switch (err) {
        error.PathAlreadyExists => return false,
        else => |e| return e,
    };
    return true;
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

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}

/// After generating parsers, writes two files into the language directory:
///
/// `metadata.json` — structured description of the generated parser(s):
/// flags, variable names, symbol names. Useful for build tooling and
/// language-binding generators.
///
/// `procedures.zig` — extern declarations for every `reduction_<VariableName>`
/// hook plus the general `reduction` fallback, and for every author-defined
/// grammar hook under its generated `hook_<name>` lookup name. The consumer's
/// C/C++/Rust source implements these functions; the linker resolves them
/// when the shared library is built.
fn writeMetadataAndProcedures(init: std.process.Init, language_dir: []const u8) !void {
    const meta_path = try std.fs.path.join(init.gpa, &.{ language_dir, "metadata.json" });
    defer init.gpa.free(meta_path);
    var file = try std.Io.Dir.cwd().createFile(init.io, meta_path, .{});
    {
        var buffer: [4096]u8 = undefined;
        var fw = file.writer(init.io, &buffer);
        const w = &fw.interface;

        try w.writeAll("{\n");
        var wrote_any = false;

        const parser_types = [_][]const u8{ "ll", "lr" };
        for (parser_types) |pt| {
            const output_name = try std.fmt.allocPrint(init.gpa, "_{s}-parser.zig", .{pt});
            defer init.gpa.free(output_name);
            const path = try std.fs.path.join(init.gpa, &.{ language_dir, output_name });
            defer init.gpa.free(path);

            const exists = blk: {
                std.Io.Dir.cwd().access(init.io, path, .{}) catch break :blk false;
                break :blk true;
            };
            if (!exists) continue;
            if (wrote_any) try w.writeAll(",\n");
            wrote_any = true;
            try w.print("  \"{s}\": {{\n", .{pt});

            const content = std.Io.Dir.cwd().readFileAlloc(
                init.io,
                path,
                init.gpa,
                .limited(max_source_size),
            ) catch continue;
            defer init.gpa.free(content);

            inline for (.{
                .{ "is_ast_enabled", "is_ast_enabled" },
                .{ "are_procedures_enabled", "are_procedures_enabled" },
                .{ "is_error_recovery_enabled", "is_error_recovery_enabled" },
                .{ "is_position_tracking_enabled", "position_tracking" },
                .{ "is_input_streaming_enabled", "input_streaming" },
                .{ "uses_verbatim", "uses_verbatim" },
            }) |entry| {
                const pattern = "pub const " ++ entry[0] ++ " = ";
                if (std.mem.indexOf(u8, content, pattern)) |idx| {
                    const rest = content[idx + pattern.len ..];
                    if (std.mem.startsWith(u8, rest, "true")) {
                        try w.print("    \"{s}\": true,\n", .{entry[1]});
                    } else if (std.mem.startsWith(u8, rest, "false")) {
                        try w.print("    \"{s}\": false,\n", .{entry[1]});
                    }
                }
            }

            if (std.mem.indexOf(u8, content, ".automatic") != null) {
                try w.writeAll("    \"error_recovery_mode\": \"automatic\",\n");
            } else if (std.mem.indexOf(u8, content, ".explicit") != null) {
                try w.writeAll("    \"error_recovery_mode\": \"explicit\",\n");
            } else if (std.mem.indexOf(u8, content, "ErrorRecoveryMode") != null) {
                try w.writeAll("    \"error_recovery_mode\": \"disabled\",\n");
            }

            const table_names = [_][]const u8{ "variables", "symbols" };
            for (table_names) |table| {
                const prefix = try std.fmt.allocPrint(init.gpa, "pub const {s} = &[_][]const u8{{", .{table});
                defer init.gpa.free(prefix);
                const arr_start = std.mem.indexOf(u8, content, prefix) orelse continue;
                const inner_start = arr_start + prefix.len;
                const inner_end = std.mem.indexOfPos(u8, content, inner_start, "}") orelse continue;
                try w.print("    \"{s}\": [", .{table});
                var items = std.mem.splitScalar(u8, content[inner_start..inner_end], ',');
                var first_item = true;
                while (items.next()) |item| {
                    const trimmed = std.mem.trim(u8, item, " \t\r\n");
                    if (trimmed.len < 2 or trimmed[0] != '"') continue;
                    const end_q = std.mem.lastIndexOfScalar(u8, trimmed, '"') orelse continue;
                    if (!first_item) try w.writeAll(", ");
                    try w.writeByte('"');
                    for (trimmed[1..end_q]) |ch| {
                        switch (ch) {
                            '"' => try w.writeAll("\\\""),
                            '\\' => try w.writeAll("\\\\"),
                            else => try w.writeByte(ch),
                        }
                    }
                    try w.writeByte('"');
                    first_item = false;
                }
                try w.writeAll("],\n");
            }

            try w.writeAll("  }");
        }

        try w.writeAll("\n}\n");
        try w.flush();
    }

    // Generate procedures.zig with extern declarations for each hook.
    // No prefix, no wrappers — the consumer's C functions ARE the
    // implementations; the linker resolves them at library build time.
    // Reduction hooks keep their established `reduction_` names; author-
    // defined grammar hooks arrive pre-namespaced as `hook_<name>` (the
    // generated parser's user_hook_names table lists them verbatim).
    const proc_path = try std.fs.path.join(init.gpa, &.{ language_dir, "procedures.zig" });
    defer init.gpa.free(proc_path);
    var proc_file = try std.Io.Dir.cwd().createFile(init.io, proc_path, .{});
    {
        var buffer: [4096]u8 = undefined;
        var fw = proc_file.writer(init.io, &buffer);
        const w = &fw.interface;

        try w.writeAll("// Auto-generated by Galley — edit your procedures C file instead.\n");
        try w.writeAll("// Implement these functions in C; they are called directly.\n");
        try w.writeAll("const root = @import(\"galley\");\n");
        try w.writeAll("pub const Payload = struct {};\n\n");

        const argument_type = "*root.data_structures.ProcedureArguments";
        try w.print("pub extern fn reduction({s}) void;\n", .{argument_type});

        const proc_parser_types = [_][]const u8{ "ll", "lr" };
        for (proc_parser_types) |pt| {
            const output_name = try std.fmt.allocPrint(init.gpa, "_{s}-parser.zig", .{pt});
            defer init.gpa.free(output_name);
            const path = try std.fs.path.join(init.gpa, &.{ language_dir, output_name });
            defer init.gpa.free(path);

            std.Io.Dir.cwd().access(init.io, path, .{}) catch continue;
            const content = std.Io.Dir.cwd().readFileAlloc(
                init.io,
                path,
                init.gpa,
                .limited(max_source_size),
            ) catch continue;
            defer init.gpa.free(content);

            const proc_prefix = "pub const variables = &[_][]const u8{";
            if (std.mem.indexOf(u8, content, proc_prefix)) |arr_start| {
                const inner_start = arr_start + proc_prefix.len;
                const inner_end = std.mem.indexOfPos(u8, content, inner_start, "}") orelse continue;
                var items = std.mem.splitScalar(u8, content[inner_start..inner_end], ',');

                while (items.next()) |item| {
                    const trimmed = std.mem.trim(u8, item, " \t\r\n");
                    if (trimmed.len < 2 or trimmed[0] != '"') continue;
                    const end_q = std.mem.lastIndexOfScalar(u8, trimmed, '"') orelse continue;
                    const variable_name = trimmed[1..end_q];
                    try w.print("pub extern fn reduction_{s}({s}) void;\n", .{ variable_name, argument_type });
                }
            }

            const hooks_prefix = "pub const user_hook_names = [_][]const u8{";
            if (std.mem.indexOf(u8, content, hooks_prefix)) |hooks_start| {
                const hooks_inner_start = hooks_start + hooks_prefix.len;
                const hooks_inner_end = std.mem.indexOfPos(u8, content, hooks_inner_start, "} ;") orelse std.mem.indexOfPos(u8, content, hooks_inner_start, "\n};") orelse continue;
                var hook_items = std.mem.splitScalar(u8, content[hooks_inner_start..hooks_inner_end], ',');
                while (hook_items.next()) |hook_item| {
                    const trimmed = std.mem.trim(u8, hook_item, " \t\r\n");
                    if (trimmed.len < 2 or trimmed[0] != '"') continue;
                    const end_q = std.mem.lastIndexOfScalar(u8, trimmed, '"') orelse continue;
                    const hook_name = trimmed[1..end_q];
                    try w.print("pub extern fn {s}({s}) void;\n", .{ hook_name, argument_type });
                }
            }
        }
        try w.flush();
    }
}
