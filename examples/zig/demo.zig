//! Parses a small key/value document through Galley's native Zig runtime,
//! mirroring examples/c and the other language examples in output.

const std = @import("std");
const parser = @import("parser");

const valid_sample: [:0]const u8 = "alpha:12,beta:3";
const broken_sample: [:0]const u8 = "alpha:";
const multi_error_sample: [:0]const u8 = "alpha:13x,beta:,gamma:q";
const sample_path = "/tmp/galley-zig-example.json";

fn nodeText(session: *parser.Session, node: *const parser.data_structures.Node) []const u8 {
    const input = session.owned_input orelse return "";
    if (node.text_start > input.len) return "";
    if (node.text_length > input.len - node.text_start) return "";
    return input[node.text_start..][0..node.text_length];
}

fn nodeLine(session: *parser.Session, node: *const parser.data_structures.Node) u32 {
    const input = session.owned_input orelse return 1;
    const end = @min(node.text_start, input.len);
    var line: u32 = 1;
    for (input[0..end]) |byte| {
        if (byte == '\n') line += 1;
    }
    return line;
}

fn symbolName(node: *const parser.data_structures.Node) []const u8 {
    if (node.variable == parser.data_structures.Node.invalid_variable) return "";
    return parser.parser.variables[node.variable];
}

fn printTree(
    stdout: *std.Io.Writer,
    session: *parser.Session,
    allocator: *parser.data_structures.ASTAllocator,
    address: parser.data_structures.Node.Pointer,
    depth: u32,
) !void {
    const node = allocator.at(address);
    var i: u32 = 0;
    while (i < depth) : (i += 1) try stdout.writeAll("  ");
    try stdout.print("{s} [line {d}, {d} bytes]\n", .{
        symbolName(node),
        nodeLine(session, node),
        nodeText(session, node).len,
    });
    var child = node.first_child;
    while (child != parser.data_structures.Node.invalid_pointer) {
        try printTree(stdout, session, allocator, child, depth + 1);
        child = allocator.at(child).next;
    }
}

/// Bindings record diagnostics; they do not print them during parse.
fn ignoreDiagnostic(_: []const u8) void {}

fn diagnosticMessage(reader: parser.SessionReadGuard, gpa: std.mem.Allocator, diagnostic: parser.ParseDiagnostic) !struct { []const u8, bool } {
    if (reader.lastRenderedMessage()) |message| return .{ message, false };
    return .{ try parser.renderParseDiagnostic(gpa, diagnostic, .plain), true };
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    try stdout.print("galley version: {s}\n", .{"dev"});

    var session = parser.Session.init(init.io, init.gpa, .{
        .max_errors = 10,
        // C ABI demos compile the parser ReleaseFast (stack depth 1).
        .syntax_error_stack_depth = 1,
        .syntax_error_reporter = &ignoreDiagnostic,
        .message_overrides = &.{
            .{
                .name = "Number",
                .message = "expected a number after ':' (digits only) at line {line}",
            },
        },
    }) catch {
        std.debug.print("failed to create a parser session\n", .{});
        std.process.exit(1);
    };
    defer session.deinit();

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.skip();
    if (args.next()) |input_path| {
        var file = std.Io.Dir.cwd().openFile(init.io, input_path, .{ .mode = .read_only }) catch {
            std.debug.print("failed to open {s}\n", .{input_path});
            std.process.exit(1);
        };
        defer file.close(init.io);
        const parsed = session.parseFile(file, input_path) catch |err| {
            var reader = try session.readLatest();
            defer reader.deinit();
            if (reader.lastDiagnostic()) |diagnostic| {
                const message, const owned = try diagnosticMessage(reader, init.gpa, diagnostic);
                defer if (owned) init.gpa.free(message);
                const line, const column = switch (diagnostic) {
                    .syntax => |syntax| .{ syntax.line, syntax.column },
                    .semantic => |semantic| .{ semantic.line, semantic.column },
                    .indentation => |indentation| .{ indentation.line, indentation.column },
                };
                std.debug.print("{s}:{d}:{d}: {s}\n", .{ input_path, line, column, message });
            } else {
                std.debug.print("{s}: parse failed: {s}\n", .{ input_path, @errorName(err) });
            }
            std.process.exit(1);
        };
        try stdout.print("parsed {d} bytes\n", .{parsed.parsed_bytes});
        return;
    }

    const parsed = session.parseSentinelBytes(valid_sample, null) catch |err| {
        std.debug.print("unexpected failure: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    const node_count: usize = if (comptime parser.parser.is_ast_enabled) session.node_allocator.counter else 0;
    try stdout.print("parsed {d} bytes, {d} AST nodes\n", .{ parsed.parsed_bytes, node_count });
    if (comptime parser.parser.is_ast_enabled) {
        const root = parsed.ast_root orelse {
            std.debug.print("expected a root node\n", .{});
            std.process.exit(1);
        };
        try printTree(stdout, &session, &session.node_allocator, root, 1);
    } else {
        try stdout.writeAll("AST construction disabled; skipping tree walk\n");
    }

    if (session.parseSentinelBytes(broken_sample, null)) |_| {
        std.debug.print("expected the broken sample to fail\n", .{});
        std.process.exit(1);
    } else |_| {
        var reader = try session.readLatest();
        defer reader.deinit();
        const diagnostic = reader.lastDiagnostic() orelse {
            std.debug.print("expected a diagnostic for the broken sample\n", .{});
            std.process.exit(1);
        };
        const message, const owned = try diagnosticMessage(reader, init.gpa, diagnostic);
        defer if (owned) init.gpa.free(message);
        switch (diagnostic) {
            .syntax => |syntax| {
                try stdout.print("diagnostic at {d}:{d}: {s}\n", .{ syntax.line, syntax.column, message });
                try stdout.writeAll("expected one of: ");
                for (syntax.expected_tokens, 0..) |token, index| {
                    if (index != 0) try stdout.writeAll(", ");
                    try stdout.print("'{s}'", .{token});
                }
                try stdout.writeByte('\n');
                try stdout.writeAll("while parsing (innermost first):");
                switch (syntax.context) {
                    .while_parsing => |names| {
                        for (names) |name| try stdout.print(" {s}", .{name});
                    },
                    else => {},
                }
                try stdout.writeByte('\n');
            },
            .indentation => |indentation| {
                try stdout.print("diagnostic at {d}:{d}: {s}\n", .{ indentation.line, indentation.column, message });
            },
            .semantic => |semantic| {
                try stdout.print("diagnostic at {d}:{d}: {s}\n", .{ semantic.line, semantic.column, message });
            },
        }
    }

    if (session.parseSentinelBytes(multi_error_sample, null)) |_| {
        std.debug.print("expected the multi-error sample to fail\n", .{});
        std.process.exit(1);
    } else |_| {
        var reader = try session.readLatest();
        defer reader.deinit();
        const recorded = reader.recordedDiagnostics();
        try stdout.print("recorded diagnostics: {d}\n", .{recorded.len});
        for (recorded, 0..) |diagnostic, index| {
            switch (diagnostic) {
                .syntax => |syntax| {
                    try stdout.print("  [{d}] syntax at {d}:{d} near '{s}'\n", .{
                        index,
                        syntax.line,
                        syntax.column,
                        syntax.unexpected_token,
                    });
                },
                .indentation => |indentation| {
                    try stdout.print("  [{d}] indentation at {d}:{d} near ''\n", .{
                        index,
                        indentation.line,
                        indentation.column,
                    });
                },
                .semantic => |semantic| {
                    try stdout.print("  [{d}] semantic at {d}:{d} in {s}\n", .{
                        index,
                        semantic.line,
                        semantic.column,
                        semantic.variable,
                    });
                },
            }
        }
    }

    {
        var created = std.Io.Dir.cwd().createFile(init.io, sample_path, .{}) catch {
            std.debug.print("failed to write {s}\n", .{sample_path});
            std.process.exit(1);
        };
        {
            defer created.close(init.io);
            var file_buffer: [64]u8 = undefined;
            var file_writer = created.writer(init.io, &file_buffer);
            file_writer.interface.writeAll(valid_sample) catch {
                std.debug.print("failed to write {s}\n", .{sample_path});
                std.process.exit(1);
            };
            file_writer.interface.flush() catch {
                std.debug.print("failed to write {s}\n", .{sample_path});
                std.process.exit(1);
            };
        }

        var file = std.Io.Dir.cwd().openFile(init.io, sample_path, .{ .mode = .read_only }) catch {
            std.debug.print("file parse failed: io\n", .{});
            std.process.exit(1);
        };
        defer file.close(init.io);
        const file_result = session.parseFile(file, sample_path) catch |err| {
            std.debug.print("file parse failed: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        const end_line = if (comptime parser.position_tracking_enabled) file_result.line else @as(u32, 0);
        const end_column = if (comptime parser.position_tracking_enabled) file_result.column else @as(u32, 0);
        try stdout.print("file parse: {d} bytes, ended at {d}:{d}\n", .{
            file_result.parsed_bytes,
            end_line,
            end_column,
        });

        if (comptime parser.parser.is_ast_enabled) {
            const root = file_result.ast_root orelse {
                std.debug.print("expected the root to have children\n", .{});
                std.process.exit(1);
            };
            const Node = parser.data_structures.Node;
            const children_before = session.node_allocator.at(root).children_count;
            const head = Node.cleanChildren(root, &session.node_allocator) catch {
                std.debug.print("expected the root to have children\n", .{});
                std.process.exit(1);
            };
            if (head == Node.invalid_pointer) {
                std.debug.print("expected the root to have children\n", .{});
                std.process.exit(1);
            }
            Node.appendChildren(root, &session.node_allocator, head) catch {
                std.debug.print("failed to reattach children\n", .{});
                std.process.exit(1);
            };
            try stdout.print("tree edit: {d} children before, {d} after reattach\n", .{
                children_before,
                session.node_allocator.at(root).children_count,
            });
        }
    }
}
