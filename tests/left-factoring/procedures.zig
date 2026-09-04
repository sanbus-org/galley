const data_structures = @import("galley").data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;

pub const Payload = struct {};

pub const Hook = enum {
    start,
    item,
    item_second,
    pair,
    pair_second,
};

var event_buffer: [16]Hook = undefined;
var event_count: usize = 0;

pub fn resetTrace() void {
    event_count = 0;
}

pub fn trace() []const Hook {
    return event_buffer[0..event_count];
}

fn record(hook: Hook) !void {
    if (event_count == event_buffer.len) return error.ProcedureHookTraceOverflow;
    event_buffer[event_count] = hook;
    event_count += 1;
}

pub fn reduction_Start_0(args: *ProcedureArguments) !void {
    _ = args;
    try record(.start);
}

pub fn reduction_Start_1(args: *ProcedureArguments) !void {
    _ = args;
    try record(.start);
}

pub fn reduction_Item_0(args: *ProcedureArguments) !void {
    _ = args;
    try record(.item);
}

// LR-only: LL merges both Item alternatives into the single factored
// production, so this hook never fires there.
pub fn reduction_Item_1(args: *ProcedureArguments) !void {
    _ = args;
    try record(.item_second);
}

pub fn reduction_Pair_0(args: *ProcedureArguments) !void {
    _ = args;
    try record(.pair);
}

// LR-only, same as above.
pub fn reduction_Pair_1(args: *ProcedureArguments) !void {
    _ = args;
    try record(.pair_second);
}
