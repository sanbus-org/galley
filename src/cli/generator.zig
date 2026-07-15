const std = @import("std");
const build_options = @import("build_options");
const generator = @import("galley_generator");

const max_input_size = 1024 * 1024 * 1024;

const CliOptions = struct {
    parser_type: ?generator.ParserType = null,
    language_dir: ?[]const u8 = null,
    generator_options: generator.Options = .{},
    fill_error_messages: bool = false,
};

const GenerationResult = struct {
    generated_ll: bool = false,
    generated_lr: bool = false,
    created_procedures: bool = false,
    created_config: bool = false,
    created_ll_error_messages: bool = false,
    created_lr_error_messages: bool = false,
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
        } else if (std.mem.eql(u8, arg, "--fill-error-messages")) {
            result.fill_error_messages = true;
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
        \\      --fill-error-messages  Append missing default syntax error hooks.
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
                result.created_ll_error_messages = try ensureErrorMessages(init, language_dir, .ll, options.generator_options, options.fill_error_messages);
                result.generated_ll = true;
            },
            .lr => {
                if (!has_lr) fatal("error: lr.grm not found in {s}\n", .{language_dir});
                try generateParser(init, language_dir, .lr, options.generator_options);
                result.created_lr_error_messages = try ensureErrorMessages(init, language_dir, .lr, options.generator_options, options.fill_error_messages);
                result.generated_lr = true;
            },
        }
    } else {
        if (!has_ll and !has_lr) fatal("error: no ll.grm or lr.grm found in {s}\n", .{language_dir});
        if (has_ll) {
            try generateParser(init, language_dir, .ll, options.generator_options);
            result.created_ll_error_messages = try ensureErrorMessages(init, language_dir, .ll, options.generator_options, options.fill_error_messages);
            result.generated_ll = true;
        }
        if (has_lr) {
            try generateParser(init, language_dir, .lr, options.generator_options);
            result.created_lr_error_messages = try ensureErrorMessages(init, language_dir, .lr, options.generator_options, options.fill_error_messages);
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
    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, grammar_path, init.gpa, .limited(max_input_size));
    defer init.gpa.free(source);

    const filled_source = try generator.generateErrorMessagesAlloc(init.arena.allocator(), source, parser_type, options);

    const path = try std.fs.path.join(init.gpa, &.{ language_dir, basename });
    defer init.gpa.free(path);

    var created_file = std.Io.Dir.cwd().createFile(init.io, path, .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => {
            try appendMissingErrorMessages(init, path, filled_source, parser_type);
            return false;
        },
        else => |e| return e,
    };
    defer created_file.close(init.io);
    try created_file.writeStreamingAll(init.io, filled_source);
    return true;
}

fn appendMissingErrorMessages(init: std.process.Init, path: []const u8, filled_source: []const u8, parser_type: generator.ParserType) !void {
    const existing = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(max_input_size));
    defer init.gpa.free(existing);

    const merge = try mergeErrorMessages(init.arena.allocator(), existing, filled_source, parser_type);

    for (merge.obsolete_names) |existing_name| {
        std.debug.print("warning: obsolete public error message hook in {s}: {s}\n", .{ path, existing_name });
    }

    if (!merge.appended_any) return;

    var file = try std.Io.Dir.cwd().createFile(init.io, path, .{ .truncate = true });
    defer file.close(init.io);
    try file.writeStreamingAll(init.io, merge.source);
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
        .lr => false,
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
        @as(usize, @intFromBool(result.created_ll_error_messages)) +
        @as(usize, @intFromBool(result.created_lr_error_messages)) +
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

const defaultProceduresSource = @embedFile("templates/procedures.zig");

const defaultConfigSource = @embedFile("templates/config.zig");

const defaultLlErrorMessagesSource = @embedFile("templates/ll_error_messages.zig");

const defaultLrErrorMessagesSource = @embedFile("templates/lr_error_messages.zig");

const defaultSampleSource = "Write a sample code here";

const standaloneMainSource = @embedFile("templates/main.zig");

const standaloneParserTestSource = @embedFile("templates/parser_test.zig");

fn standaloneBuildSource(init: std.process.Init) ![]const u8 {
    return try std.fmt.allocPrint(
        init.arena.allocator(),
        @embedFile("templates/build.zig.template"),
        .{build_options.galley_root},
    );
}

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
