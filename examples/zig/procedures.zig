//! Procedure hooks for the keyvalue grammar.
//!
//! Shows ProcedureArguments in action: the current node, its text, children,
//! and source position, plus dropIfEmpty on empty tails. Author-defined
//! grammar hooks arrive as hook_<name> — Key is annotated @print.

const std = @import("std");
const galley = @import("galley");

pub const Payload = struct {};

const ProcedureArguments = galley.data_structures.ProcedureArguments;
const Node = galley.data_structures.Node;

fn symbolName(node: *const Node) []const u8 {
    if (node.variable == Node.invalid_variable) return "";
    return galley.parser.variables[node.variable];
}

fn nodeText(context: *galley.data_structures.Context, node: *const Node) []const u8 {
    return context.getTextSlice(node.text_start, node.text_length);
}

fn nodeLineColumn(context: *galley.data_structures.Context, node: *const Node) struct { u32, u32 } {
    const input = context.diagnosticInput();
    var line: u32 = 1;
    var column: u32 = 1;
    const end = @min(node.text_start, input.len);
    for (input[0..end]) |byte| {
        if (byte == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }
    return .{ line, column };
}

fn parseU(bytes: []const u8) u32 {
    var value: u32 = 0;
    for (bytes) |byte| {
        if (byte >= '0' and byte <= '9') {
            value = value * 10 + (byte - '0');
        }
    }
    return value;
}

fn countPairs(args: *ProcedureArguments, node: *Node, count: *u32, sum: *u32) void {
    if (std.mem.eql(u8, symbolName(node), "Pair")) {
        count.* += 1;
        const text = nodeText(args.context, node);
        if (std.mem.indexOfScalar(u8, text, ':')) |colon| {
            sum.* += parseU(text[colon + 1 ..]);
        }
        return;
    }
    var iterator = node.childIterator(args.context);
    while (iterator.next()) |child| {
        countPairs(args, child, count, sum);
    }
}

pub fn reduction(_: *ProcedureArguments) void {}

pub fn reduction_KeyTail(args: *ProcedureArguments) !void {
    try galley.standard_procedures.dropIfEmpty(args);
}

pub fn reduction_NumberTail(args: *ProcedureArguments) !void {
    try galley.standard_procedures.dropIfEmpty(args);
}

pub fn reduction_PairListTail(args: *ProcedureArguments) !void {
    try galley.standard_procedures.dropIfEmpty(args);
}

pub fn reduction_PairList(_: *ProcedureArguments) void {}

pub fn reduction_Key(_: *ProcedureArguments) void {}

pub fn hook_print(args: *ProcedureArguments) void {
    const node = args.currentNode() orelse return;
    const line, const column = nodeLineColumn(args.context, node);
    std.debug.print("@print \"{s}\" at {d}:{d}\n", .{ nodeText(args.context, node), line, column });
}

pub fn reduction_Number(args: *ProcedureArguments) void {
    const node = args.currentNode() orelse return;
    const line, const column = nodeLineColumn(args.context, node);
    std.debug.print("Number {s} at {d}:{d}\n", .{ nodeText(args.context, node), line, column });
}

pub fn reduction_Pair(args: *ProcedureArguments) void {
    const node = args.currentNode() orelse return;
    const line, const column = nodeLineColumn(args.context, node);
    const text = nodeText(args.context, node);
    const colon = std.mem.indexOfScalar(u8, text, ':') orelse text.len;
    const key = text[0..colon];
    const number = if (colon < text.len) text[colon + 1 ..] else "";
    std.debug.print("Pair {s}={s} ({d} children) at {d}:{d}\n", .{
        key,
        number,
        node.children_count,
        line,
        column,
    });
}

pub fn reduction_Document(args: *ProcedureArguments) void {
    const node = args.currentNode() orelse return;
    var count: u32 = 0;
    var sum: u32 = 0;
    countPairs(args, node, &count, &sum);
    std.debug.print("Document {d} pairs, sum={d}\n", .{ count, sum });
}
