const data_structures = @import("galley").data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;

pub const Payload = struct {};

var totals: usize = 0;
var last_children: u32 = 0;

pub fn reset() void {
    totals = 0;
    last_children = 0;
}

/// Sum reductions that ran the `total` hook so far.
pub fn totalCount() usize {
    return totals;
}

/// How many children the last Sum that ran `total` had.
pub fn lastTotalChildren() u32 {
    return last_children;
}

pub fn hook_total(args: *ProcedureArguments) !void {
    const node = args.currentNode() orelse return error.MissingNode;
    totals += 1;
    last_children = node.children_count;
}
