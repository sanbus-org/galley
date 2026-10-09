const data_structures = @import("galley").data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;

pub const Payload = struct {};

var lists: usize = 0;
var children_buffer: [8]u32 = undefined;
var marks: usize = 0;
var previous_length: usize = 0;
var innermost_first = true;

pub fn reset() void {
    lists = 0;
    children_buffer = undefined;
    marks = 0;
    previous_length = 0;
    innermost_first = true;
}

/// List reductions so far.
pub fn listCount() usize {
    return lists;
}

/// How many children each of the first List reductions had, in order.
pub fn childCounts() []const u32 {
    return children_buffer[0..@min(lists, children_buffer.len)];
}

/// Reductions of a List continued at the `mark` occurrence so far.
pub fn markCount() usize {
    return marks;
}

/// Whether every List reduction spanned more text than the one before, as
/// reducing a chain innermost first does.
pub fn reducedInnermostFirst() bool {
    return innermost_first;
}

pub fn hook_count(args: *ProcedureArguments) !void {
    const node = args.currentNode() orelse return error.MissingNode;
    if (lists != 0 and node.text_length <= previous_length) innermost_first = false;
    previous_length = node.text_length;
    if (lists < children_buffer.len) children_buffer[lists] = node.children_count;
    lists += 1;
}

pub fn hook_mark(_: *ProcedureArguments) !void {
    marks += 1;
}
