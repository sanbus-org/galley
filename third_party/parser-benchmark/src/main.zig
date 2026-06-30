const std = @import("std");
const c = @cImport({
    @cInclude("tree_sitter/api.h");
});
extern fn tree_sitter_json() *c.TSLanguage;

fn benchmarkTreeSitter(source: []const u8) void {
    const parser = c.ts_parser_new();
    defer c.ts_parser_delete(parser);

    _ = c.ts_parser_set_language(parser, tree_sitter_json());

    // Benchmark this loop
    const tree = c.ts_parser_parse_string(
        parser,
        null,
        source.ptr,
        @intCast(source.len),
    );
    defer c.ts_tree_delete(tree);
}

extern fn yy_scan_string(str: [*]const u8) ?*anyopaque;
extern fn yyparse() c_int;
extern fn yylex_destroy() void;

// Import Bison AST control state
extern var bison_build_ast: c_int;
extern var bison_build_advanced_ast: c_int;
extern var bison_build_payload_ast: c_int;
extern var bison_current_arena: ?*anyopaque;
extern var bison_root_node: ?*anyopaque;

// Import C Arena functions
extern fn arena_create(size: usize) ?*anyopaque;
extern fn arena_destroy(arena: ?*anyopaque) void;
extern fn print_ast_summary() void;

extern fn benchmark_lalrpop(ptr: [*]const u8, len: usize) bool;
extern fn benchmark_simdjson_validate(ptr: [*]const u8, len: usize) bool;
extern fn benchmark_simdjson_dom(ptr: [*]const u8, len: usize) bool;
extern fn benchmark_nom(ptr: [*]const u8, len: usize) bool;
extern fn benchmark_rapidjson_dom(ptr: [*]const u8, len: usize) bool;
extern fn benchmark_rapidjson_sax(ptr: [*]const u8, len: usize) bool;

fn benchmarkBison(source: [:0]const u8, build_ast: bool, build_advanced_ast: bool, build_payload_ast: bool) void {
    const buffer_state = yy_scan_string(source.ptr);
    _ = buffer_state;

    if (build_payload_ast) {
        bison_build_ast = 0;
        bison_build_advanced_ast = 0;
        bison_build_payload_ast = 1;
        bison_current_arena = arena_create(128 * 1024 * 1024); // Allocate 128MB Arena for Payload AST Nodes
        bison_root_node = null;
    } else if (build_advanced_ast) {
        bison_build_ast = 0;
        bison_build_advanced_ast = 1;
        bison_build_payload_ast = 0;
        bison_current_arena = arena_create(128 * 1024 * 1024); // Allocate 128MB Arena for Advanced AST Nodes
        bison_root_node = null;
    } else if (build_ast) {
        bison_build_ast = 1;
        bison_build_advanced_ast = 0;
        bison_build_payload_ast = 0;
        bison_current_arena = arena_create(64 * 1024 * 1024); // Allocate 64MB Arena for Simple AST Nodes
        bison_root_node = null;
    } else {
        bison_build_ast = 0;
        bison_build_advanced_ast = 0;
        bison_build_payload_ast = 0;
        bison_current_arena = null;
        bison_root_node = null;
    }

    _ = yyparse();

    if (build_ast or build_advanced_ast or build_payload_ast) {
        arena_destroy(bison_current_arena);
        bison_current_arena = null;
    }

    yylex_destroy();
}

const Result = struct {
    name: []const u8,
    mode: []const u8,
    mbps: f64,
    duration_ns: i96,
    parsed_bytes: usize,
};

fn writeResultsToFile(io: @TypeOf(@as(std.process.Init, undefined).io), input_path: []const u8, results: []const Result) !void {
    var cwd = std.Io.Dir.cwd();
    // Write to the repo root's benchmark_results when run from third_party/parser-benchmark/
    try cwd.createDirPath(io, "../../benchmark_results/third_party/json");

    const filename = std.fs.path.basename(input_path);

    var buf: [512]u8 = undefined;
    const out_path = try std.fmt.bufPrint(&buf, "../../benchmark_results/third_party/json/{s}.txt", .{filename});

    const file = try cwd.createFile(io, out_path, .{});
    defer file.close(io);

    var write_buffer: [4096]u8 = undefined;
    var file_writer = file.writer(io, &write_buffer);
    const writer = &file_writer.interface;

    try writer.print("Language: json\n", .{});
    try writer.print("Input: third_party/parser-benchmark/{s}\n", .{input_path});
    try writer.print("----------------------------------------\n", .{});

    for (results) |r| {
        try writer.print("[{s} - {s}]\n", .{ r.name, r.mode });
        try writer.print("Parsed bytes: {d:.2} MB\n", .{ @as(f64, @floatFromInt(r.parsed_bytes)) / (1024 * 1024) });
        try writer.print("Duration: {d} ns\n", .{ r.duration_ns });
        try writer.print("Throughput: {d:.2} MB/s\n", .{ r.mbps });
        try writer.print("Nodes allocated: 0\n\n", .{});
    }
    try file_writer.flush();
}

pub fn main(init: std.process.Init) !void {
    var file_path: []const u8 = "large_dataset.json";
    if (init.minimal.args.vector.len > 1) {
        file_path = std.mem.span(init.minimal.args.vector[1]);
    }

    const file_content = try std.Io.Dir.cwd().readFileAlloc(init.io, file_path, init.gpa, .unlimited);
    defer init.gpa.free(file_content);

    const SIMDJSON_PADDING = 64;
    const file_content_padded = try init.gpa.alloc(u8, file_content.len + SIMDJSON_PADDING);
    defer init.gpa.free(file_content_padded);
    @memcpy(file_content_padded[0..file_content.len], file_content);
    @memset(file_content_padded[file_content.len..], 0);

    var results: [16]Result = undefined;
    var result_count: usize = 0;

    // 1. Benchmark Tree-sitter (CST mode)
    {
        const start = std.Io.Clock.awake.now(init.io);
        benchmarkTreeSitter(file_content);

        const end = std.Io.Clock.awake.now(init.io);
        const duration = start.durationTo(end);
        const elapsed_ns = duration.toNanoseconds();
        const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        const mbps = @as(f64, @floatFromInt(file_content.len)) / (1024 * 1024) / duration_secs;

        results[result_count] = .{
            .name = "Tree-sitter (C)",
            .mode = "CST",
            .mbps = mbps,
            .duration_ns = elapsed_ns,
            .parsed_bytes = file_content.len,
        };
        result_count += 1;
    }

    // Need null-terminated string for Flex
    const file_content_z = try init.gpa.dupeZ(u8, file_content);
    defer init.gpa.free(file_content_z);

    // 2. Benchmark Bison (Non-AST mode)
    {
        const start = std.Io.Clock.awake.now(init.io);

        benchmarkBison(file_content_z, false, false, false);

        const end = std.Io.Clock.awake.now(init.io);
        const duration = start.durationTo(end);
        const elapsed_ns = duration.toNanoseconds();
        const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        const mbps = @as(f64, @floatFromInt(file_content.len)) / (1024 * 1024) / duration_secs;

        results[result_count] = .{
            .name = "Bison / Flex",
            .mode = "Non-AST",
            .mbps = mbps,
            .duration_ns = elapsed_ns,
            .parsed_bytes = file_content.len,
        };
        result_count += 1;
    }

    // 3. Benchmark Bison (Simple AST-building mode)
    {
        const start = std.Io.Clock.awake.now(init.io);

        benchmarkBison(file_content_z, true, false, false);

        const end = std.Io.Clock.awake.now(init.io);
        const duration = start.durationTo(end);
        const elapsed_ns = duration.toNanoseconds();
        const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        const mbps = @as(f64, @floatFromInt(file_content.len)) / (1024 * 1024) / duration_secs;

        results[result_count] = .{
            .name = "Bison / Flex",
            .mode = "Simple AST",
            .mbps = mbps,
            .duration_ns = elapsed_ns,
            .parsed_bytes = file_content.len,
        };
        result_count += 1;
    }

    // 4. Benchmark Bison (Advanced AST-building mode)
    {
        const start = std.Io.Clock.awake.now(init.io);

        benchmarkBison(file_content_z, false, true, false);

        const end = std.Io.Clock.awake.now(init.io);
        const duration = start.durationTo(end);
        const elapsed_ns = duration.toNanoseconds();
        const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        const mbps = @as(f64, @floatFromInt(file_content.len)) / (1024 * 1024) / duration_secs;

        results[result_count] = .{
            .name = "Bison / Flex",
            .mode = "Adv AST",
            .mbps = mbps,
            .duration_ns = elapsed_ns,
            .parsed_bytes = file_content.len,
        };
        result_count += 1;
    }

    // 5. Benchmark Bison (Advanced AST with Payload mode)
    {
        const start = std.Io.Clock.awake.now(init.io);

        benchmarkBison(file_content_z, false, false, true);

        const end = std.Io.Clock.awake.now(init.io);
        const duration = start.durationTo(end);
        const elapsed_ns = duration.toNanoseconds();
        const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        const mbps = @as(f64, @floatFromInt(file_content.len)) / (1024 * 1024) / duration_secs;

        results[result_count] = .{
            .name = "Bison / Flex",
            .mode = "Payload AST",
            .mbps = mbps,
            .duration_ns = elapsed_ns,
            .parsed_bytes = file_content.len,
        };
        result_count += 1;
    }

    // 6. Benchmark LALRPOP (Non-AST mode)
    {
        const start = std.Io.Clock.awake.now(init.io);

        _ = benchmark_lalrpop(file_content.ptr, file_content.len);

        const end = std.Io.Clock.awake.now(init.io);
        const duration = start.durationTo(end);
        const elapsed_ns = duration.toNanoseconds();
        const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        const mbps = @as(f64, @floatFromInt(file_content.len)) / (1024 * 1024) / duration_secs;

        results[result_count] = .{
            .name = "LALRPOP (Rust)",
            .mode = "Non-AST",
            .mbps = mbps,
            .duration_ns = elapsed_ns,
            .parsed_bytes = file_content.len,
        };
        result_count += 1;
    }

    // 7. Benchmark simdjson Validate (Non-AST mode)
    {
        const start = std.Io.Clock.awake.now(init.io);

        _ = benchmark_simdjson_validate(file_content_padded.ptr, file_content.len);

        const end = std.Io.Clock.awake.now(init.io);
        const duration = start.durationTo(end);
        const elapsed_ns = duration.toNanoseconds();
        const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        const mbps = @as(f64, @floatFromInt(file_content.len)) / (1024 * 1024) / duration_secs;

        results[result_count] = .{
            .name = "simdjson (C++)",
            .mode = "Validate",
            .mbps = mbps,
            .duration_ns = elapsed_ns,
            .parsed_bytes = file_content.len,
        };
        result_count += 1;
    }

    // 8. Benchmark simdjson DOM (AST mode)
    {
        const start = std.Io.Clock.awake.now(init.io);

        _ = benchmark_simdjson_dom(file_content_padded.ptr, file_content.len);

        const end = std.Io.Clock.awake.now(init.io);
        const duration = start.durationTo(end);
        const elapsed_ns = duration.toNanoseconds();
        const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        const mbps = @as(f64, @floatFromInt(file_content.len)) / (1024 * 1024) / duration_secs;

        results[result_count] = .{
            .name = "simdjson (C++)",
            .mode = "DOM (AST)",
            .mbps = mbps,
            .duration_ns = elapsed_ns,
            .parsed_bytes = file_content.len,
        };
        result_count += 1;
    }

    // 9. Benchmark Nom (AST mode)
    {
        const start = std.Io.Clock.awake.now(init.io);

        _ = benchmark_nom(file_content.ptr, file_content.len);

        const end = std.Io.Clock.awake.now(init.io);
        const duration = start.durationTo(end);
        const elapsed_ns = duration.toNanoseconds();
        const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        const mbps = @as(f64, @floatFromInt(file_content.len)) / (1024 * 1024) / duration_secs;

        results[result_count] = .{
            .name = "Nom (Rust)",
            .mode = "AST",
            .mbps = mbps,
            .duration_ns = elapsed_ns,
            .parsed_bytes = file_content.len,
        };
        result_count += 1;
    }

    // 10. Benchmark RapidJSON DOM (AST mode)
    {
        const start = std.Io.Clock.awake.now(init.io);

        _ = benchmark_rapidjson_dom(file_content.ptr, file_content.len);

        const end = std.Io.Clock.awake.now(init.io);
        const duration = start.durationTo(end);
        const elapsed_ns = duration.toNanoseconds();
        const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        const mbps = @as(f64, @floatFromInt(file_content.len)) / (1024 * 1024) / duration_secs;

        results[result_count] = .{
            .name = "RapidJSON (C++ / SIMD)",
            .mode = "DOM (AST)",
            .mbps = mbps,
            .duration_ns = elapsed_ns,
            .parsed_bytes = file_content.len,
        };
        result_count += 1;
    }

    // 11. Benchmark RapidJSON SAX (Non-AST mode)
    {
        const start = std.Io.Clock.awake.now(init.io);

        _ = benchmark_rapidjson_sax(file_content.ptr, file_content.len);

        const end = std.Io.Clock.awake.now(init.io);
        const duration = start.durationTo(end);
        const elapsed_ns = duration.toNanoseconds();
        const duration_secs = @as(f64, @floatFromInt(elapsed_ns)) / 1e9;
        const mbps = @as(f64, @floatFromInt(file_content.len)) / (1024 * 1024) / duration_secs;

        results[result_count] = .{
            .name = "RapidJSON (C++ / SIMD)",
            .mode = "SAX (Validate)",
            .mbps = mbps,
            .duration_ns = elapsed_ns,
            .parsed_bytes = file_content.len,
        };
        result_count += 1;
    }

    // Print the final nice table
    std.debug.print("\n", .{});
    std.debug.print("+------------------------------------+------------------+-----------------+\n", .{});
    std.debug.print("| Parser Benchmark                   | Mode             | Throughput      |\n", .{});
    std.debug.print("+------------------------------------+------------------+-----------------+\n", .{});
    for (results[0..result_count]) |r| {
        std.debug.print("| {s: <34} | {s: <16} | {d: >9.2} MB/s |\n", .{ r.name, r.mode, r.mbps });
    }
    std.debug.print("+------------------------------------+------------------+-----------------+\n\n", .{});

    // Write machine-readable output to file
    writeResultsToFile(init.io, file_path, results[0..result_count]) catch |err| {
        std.debug.print("Failed to write results to file: {}\n", .{err});
    };
}
