const std = @import("std");
const ASTNode = @import("root").data_structures.ASTNode;

const StringSliceFormatter = struct {
    slice: []const []const u8,

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void {
        try writer.writeAll("{ \"");
        for (self.slice, 0..) |str, i| {
            if (i > 0) try writer.writeAll("\", \"");
            try std.zig.stringEscape(str, writer);
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
        try std.zig.stringEscape(self.string, writer);
    }
};

pub fn fmtString(string: []const u8) StringFormatter {
    return .{ .string = string };
}

const ASTNodeFormatter = struct {
    ast_node: ?*const ASTNode,
    indentation: usize = 0,
    indent_status: []bool = &[0]bool{},

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) !void {
        for (self.indent_status, 0..) |is_ended, index| {
            if (is_ended) {
                try writer.writeAll(if (index == self.indentation - 1) " ╰" else "  ");
            } else {
                try writer.writeAll(if (index == self.indentation - 1) " ├" else " │");
            }
        }

        if (self.ast_node) |ast_node| {
            try writer.print("{f} ({d})\n", .{ fmtString(ast_node.label), ast_node.children.len });

            var child_indent_status: [256]bool = undefined;
            @memcpy(child_indent_status[0..self.indentation], self.indent_status);
            child_indent_status[self.indentation] = false;

            var counter: usize = 0;
            for (ast_node.children) |child| {
                counter += 1;
                if (counter == ast_node.children.len) {
                    child_indent_status[self.indentation] = true;
                }
                const f = ASTNodeFormatter{
                    .ast_node = child,
                    .indentation = self.indentation + 1,
                    .indent_status = child_indent_status[0 .. self.indentation + 1],
                };
                try f.format(writer);
            }
        } else {
            try writer.print("NULL\n", .{});
            return;
        }
    }
};

pub fn fmtASTNode(ast_node: ?*const ASTNode) ASTNodeFormatter {
    return .{ .ast_node = ast_node };
}
