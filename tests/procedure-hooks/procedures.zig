const data_structures = @import("galley").data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;

pub const Payload = struct {};

pub const Hook = enum {
    lhs,
    rhs,
    production,
    chain_first,
    chain_second,
    rhs_first,
    rhs_second,
    production_first,
    production_second,
    automatic_production,
    lhs_first,
    lhs_second,
    automatic_symbol,
    automatic_auto_target,
    recursive_occurrence,
    hidden,
    drop_occurrence,
    after_drop_production,
    after_drop_automatic_production,
    after_drop_lhs,
    after_drop_automatic_symbol,
    terminal_first,
    terminal_second,
    automatic_terminal,
    automatic_repeated_production,
    general,
};

pub const Event = struct {
    hook: Hook,
    node_variable: ?u16,
    node_text_start: ?usize,
    has_rule: bool,
};

var event_buffer: [128]Event = undefined;
var event_count: usize = 0;

pub fn resetTrace() void {
    event_count = 0;
}

pub fn trace() []const Event {
    return event_buffer[0..event_count];
}

fn record(hook: Hook, args: *ProcedureArguments) !void {
    if (event_count == event_buffer.len) return error.ProcedureHookTraceOverflow;

    const node = if (args.node) |node_address| args.context.node_allocator.at(node_address) else null;
    event_buffer[event_count] = .{
        .hook = hook,
        .node_variable = if (node) |value| value.variable else null,
        .node_text_start = if (node) |value| value.text_start else null,
        .has_rule = args.rule != null,
    };
    event_count += 1;
}

pub fn lhsHook(args: *ProcedureArguments) !void {
    try record(.lhs, args);
}

pub fn rhsHook(args: *ProcedureArguments) !void {
    try record(.rhs, args);
}

pub fn productionHook(args: *ProcedureArguments) !void {
    try record(.production, args);
}

pub fn chainFirst(args: *ProcedureArguments) !void {
    try record(.chain_first, args);
}

pub fn chainSecond(args: *ProcedureArguments) !void {
    try record(.chain_second, args);
}

pub fn rhsFirst(args: *ProcedureArguments) !void {
    try record(.rhs_first, args);
}

pub fn rhsSecond(args: *ProcedureArguments) !void {
    try record(.rhs_second, args);
}

pub fn productionFirst(args: *ProcedureArguments) !void {
    try record(.production_first, args);
}

pub fn productionSecond(args: *ProcedureArguments) !void {
    try record(.production_second, args);
}

pub fn lhsFirst(args: *ProcedureArguments) !void {
    try record(.lhs_first, args);
}

pub fn lhsSecond(args: *ProcedureArguments) !void {
    try record(.lhs_second, args);
}

pub fn reduction_Ordered_0(args: *ProcedureArguments) !void {
    try record(.automatic_production, args);
}

pub fn reduction_Ordered(args: *ProcedureArguments) !void {
    try record(.automatic_symbol, args);
}

pub fn reduction_AutoTarget(args: *ProcedureArguments) !void {
    try record(.automatic_auto_target, args);
}

pub fn recursiveOccurrence(args: *ProcedureArguments) !void {
    try record(.recursive_occurrence, args);
}

pub fn hiddenHook(args: *ProcedureArguments) !void {
    try record(.hidden, args);
}

pub fn dropOccurrence(args: *ProcedureArguments) !void {
    try record(.drop_occurrence, args);
    args.node = null;
}

pub fn afterDropProduction(args: *ProcedureArguments) !void {
    try record(.after_drop_production, args);
}

pub fn reduction_DropTarget_0(args: *ProcedureArguments) !void {
    try record(.after_drop_automatic_production, args);
}

pub fn afterDropLhs(args: *ProcedureArguments) !void {
    try record(.after_drop_lhs, args);
}

pub fn reduction_DropTarget(args: *ProcedureArguments) !void {
    try record(.after_drop_automatic_symbol, args);
}

pub fn terminalFirst(args: *ProcedureArguments) !void {
    try record(.terminal_first, args);
}

pub fn terminalSecond(args: *ProcedureArguments) !void {
    try record(.terminal_second, args);
}

pub fn reduction_j(args: *ProcedureArguments) !void {
    try record(.automatic_terminal, args);
}

pub fn reduction_IndexedTarget_1(args: *ProcedureArguments) !void {
    try record(.automatic_repeated_production, args);
}

pub fn reduction(args: *ProcedureArguments) !void {
    try record(.general, args);
}
