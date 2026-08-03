const std = @import("std");
const root = @import("galley");
const parser = root.parser;
const Node = root.data_structures.Node;
const Context = root.data_structures.Context;

const StringSliceFormatter = struct {
    slice: []const []const u8,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void {
        try writer.writeAll("{ \"");
        for (self.slice, 0..) |str, i| {
            if (i > 0) try writer.writeAll("\", \"");
            try writeHumanReadableString(str, writer);
        }
        try writer.writeAll("\" }");
    }
};

pub fn fmtStringSlice(slice: []const []const u8) StringSliceFormatter {
    return .{ .slice = slice };
}

const StringFormatter = struct {
    string: []const u8,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void {
        try writeHumanReadableString(self.string, writer);
    }
};

pub fn fmtString(string: []const u8) StringFormatter {
    return .{ .string = string };
}

test "string formatter preserves valid Unicode and escapes unsafe bytes" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    try output.writer.print("{f}", .{fmtString("سلام 😀\n\xff\u{2028}")});
    try std.testing.expectEqualStrings(
        "سلام 😀\\n\\xff\\u{2028}",
        output.written(),
    );
}

fn writeHumanReadableString(string: []const u8, writer: *std.Io.Writer) !void {
    var index: usize = 0;
    while (index < string.len) {
        const byte = string[index];
        switch (byte) {
            '\n' => try writer.writeAll("\\n"),
            '\t' => try writer.writeAll("\\t"),
            '\r' => try writer.writeAll("\\r"),
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            0x20...0x21, 0x23...0x5b, 0x5d...0x7e => try writer.writeByte(byte),
            0x00...0x08, 0x0b...0x0c, 0x0e...0x1f, 0x7f => try writer.print("\\x{x:0>2}", .{byte}),
            else => {
                const sequence_length = std.unicode.utf8ByteSequenceLength(byte) catch {
                    try writer.print("\\x{x:0>2}", .{byte});
                    index += 1;
                    continue;
                };
                if (sequence_length > string.len - index) {
                    try writer.print("\\x{x:0>2}", .{byte});
                    index += 1;
                    continue;
                }

                const sequence = string[index..][0..sequence_length];
                const codepoint = std.unicode.utf8Decode(sequence) catch {
                    try writer.print("\\x{x:0>2}", .{byte});
                    index += 1;
                    continue;
                };
                if ((codepoint >= 0x80 and codepoint <= 0x9f) or
                    codepoint == 0x2028 or
                    codepoint == 0x2029)
                {
                    try writer.print("\\u{{{x}}}", .{codepoint});
                } else {
                    try writer.writeAll(sequence);
                }
                index += sequence_length;
                continue;
            },
        }
        index += 1;
    }
}

const NodeFormatter = struct {
    ast_node_address: ?Node.Pointer,
    context: *Context,
    indentation: usize = 0,
    indent_status: []bool = &[0]bool{},

    const Frame = struct {
        node: Node.Pointer,
        depth: usize,
        is_last: bool,
    };

    const Child = struct {
        node: Node.Pointer,
        is_last: bool,
    };

    fn writeIndent(indent: []const bool, depth: usize, writer: *std.Io.Writer) !void {
        for (indent, 0..) |is_ended, index| {
            if (is_ended) {
                try writer.writeAll(if (index == depth - 1) " ╰" else "  ");
            } else {
                try writer.writeAll(if (index == depth - 1) " ├" else " │");
            }
        }
    }

    fn syncIndent(indent: *std.ArrayList(bool), allocator: std.mem.Allocator, depth: usize, is_last: bool) error{WriteFailed}!void {
        if (indent.items.len > depth) {
            indent.shrinkRetainingCapacity(depth);
        }
        if (indent.items.len < depth) {
            const old_len = indent.items.len;
            indent.resize(allocator, depth) catch return error.WriteFailed;
            for (old_len..depth) |index| {
                indent.items[index] = false;
            }
        }
        if (depth > 0) {
            indent.items[depth - 1] = is_last;
        }
    }

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void {
        const allocator = self.context.runtime().arena_allocator;

        const root_node = self.ast_node_address orelse {
            try writer.print("NULL\n", .{});
            return;
        };

        var stack: std.ArrayList(Frame) = .empty;
        var indent: std.ArrayList(bool) = .empty;
        var children: std.ArrayList(Child) = .empty;

        stack.append(allocator, .{
            .node = root_node,
            .depth = 0,
            .is_last = true,
        }) catch return error.WriteFailed;

        while (stack.pop()) |frame| {
            try syncIndent(&indent, allocator, frame.depth, frame.is_last);
            try writeIndent(indent.items, frame.depth, writer);

            const ast_node = self.context.node_allocator.at(frame.node);
            try writer.print(" {s} \"{f}\" ({d})\n", .{
                if (ast_node.variable == std.math.maxInt(u16))
                    "-"
                else
                    parser.variables[ast_node.variable],
                fmtString(self.context.getTextSlice(ast_node.text_start, ast_node.text_length)),
                formattedChildrenCount(ast_node),
            });

            children.items.len = 0;
            var iterator = Node.iterateAugmented(ast_node.first_child, self.context.node_allocator);
            while (iterator.next()) |node_address| {
                const node = self.context.node_allocator.at(node_address);
                children.append(allocator, .{
                    .node = node_address,
                    .is_last = node.next == Node.invalid_pointer,
                }) catch return error.WriteFailed;
            }

            var child_index = children.items.len;
            while (child_index > 0) {
                child_index -= 1;
                const child = children.items[child_index];
                stack.append(allocator, .{
                    .node = child.node,
                    .depth = frame.depth + 1,
                    .is_last = child.is_last,
                }) catch return error.WriteFailed;
            }
        }
    }
};

fn formattedChildrenCount(ast_node: *const Node) u32 {
    return ast_node.children_count;
}

pub fn fmtNode(ast_node_address: ?Node.Pointer, context: *Context) NodeFormatter {
    return .{
        .ast_node_address = ast_node_address,
        .context = context,
    };
}

test "AST formatter reports the current node child count" {
    if (comptime !parser.is_ast_enabled) return;

    var node_allocator = try root.data_structures.ASTAllocator.initWithCapacity(std.testing.allocator, 4);
    defer std.testing.allocator.free(node_allocator.memory);

    const parent = try node_allocator.create(0, 0);
    const first_child = try node_allocator.create(0, 0);
    const second_child = try node_allocator.create(0, 0);
    const grandchild = try node_allocator.create(0, 0);
    try Node.appendChildren(parent, &node_allocator, first_child);
    try Node.appendChildren(parent, &node_allocator, second_child);
    try Node.appendChildren(first_child, &node_allocator, grandchild);

    try std.testing.expectEqual(@as(u32, 2), formattedChildrenCount(node_allocator.at(parent)));
    try std.testing.expectEqual(@as(u32, 1), node_allocator.at(first_child).children_count);
}

pub fn formatWithThousands(value: anytype, buf: []u8) ![]u8 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    const n: u64 = switch (info) {
        .int, .comptime_int => @intCast(value),
        .float, .comptime_float => @intFromFloat(value),
        else => @compileError("formatWithThousands: expected int or float, got " ++ @typeName(T)),
    };

    var tmp: [32]u8 = undefined;
    const digits = std.fmt.bufPrint(&tmp, "{d}", .{n}) catch unreachable;

    var out_pos: usize = 0;
    const len = digits.len;
    for (digits, 0..) |ch, i| {
        const remaining = len - i;
        if (i > 0 and remaining % 3 == 0) {
            buf[out_pos] = ',';
            out_pos += 1;
        }
        buf[out_pos] = ch;
        out_pos += 1;
    }

    return buf[0..out_pos];
}

const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB", "PB" };

pub fn formatFileSize(size: anytype, buf: []u8) ![]u8 {
    const T = @TypeOf(size);
    const info = @typeInfo(T);

    const fsize: f64 = switch (info) {
        .int, .comptime_int => @floatFromInt(size),
        .float, .comptime_float => @floatCast(size),
        else => @compileError("formatFileSize: expected int or float, got " ++ @typeName(T)),
    };

    var value = fsize;
    var unit_index: usize = 0;

    while (value >= 1024.0 and unit_index < units.len - 1) {
        value /= 1024.0;
        unit_index += 1;
    }

    if (unit_index == 0) {
        return std.fmt.bufPrint(buf, "{d} {s}", .{ @as(u64, @intFromFloat(value)), units[unit_index] });
    } else {
        return std.fmt.bufPrint(buf, "{d:.2} {s}", .{ value, units[unit_index] });
    }
}
