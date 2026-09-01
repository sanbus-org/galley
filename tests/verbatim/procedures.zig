const std = @import("std");
const root = @import("galley");
const ProcedureArguments = root.data_structures.ProcedureArguments;

pub const Payload = struct {
    value: usize = 0,
};

pub const Capture = struct {
    name: [32]u8 = undefined,
    name_len: usize = 0,
    start: usize = 0,
    length: usize = 0,
    text: [128]u8 = undefined,
    text_len: usize = 0,
};

var captures: [64]Capture = undefined;
var capture_count: usize = 0;

pub fn resetCaptures() void {
    capture_count = 0;
}

pub fn captureCount() usize {
    return capture_count;
}

pub fn captureAt(index: usize) Capture {
    return captures[index];
}

pub fn reduction(context: *ProcedureArguments) !void {
    const node = context.currentNode() orelse return;
    if (variable_index_out_of_bounds(node.variable)) return;
    if (capture_count >= captures.len) return;

    const name = root.parser.variables[node.variable];
    const capture = &captures[capture_count];
    const name_bytes = name[0..@min(name.len, capture.name.len)];
    @memcpy(capture.name[0..name_bytes.len], name_bytes);
    capture.name_len = name_bytes.len;
    capture.start = node.text_start;
    capture.length = node.text_length;

    const text = context.context.getTextSlice(node.text_start, node.text_length);
    const text_bytes = text[0..@min(text.len, capture.text.len)];
    @memcpy(capture.text[0..text_bytes.len], text_bytes);
    capture.text_len = text_bytes.len;
    capture_count += 1;
}

fn variable_index_out_of_bounds(variable: u16) bool {
    return variable >= root.parser.variables.len;
}
