const root = @import("galley");
const ProcedureArguments = root.data_structures.ProcedureArguments;

pub const Payload = struct {
    value: usize = 0,
};

pub const Hook = enum {
    occurrence,
    production,
    automatic_production,
    lhs,
    automatic_symbol,
    terminal_occurrence,
    automatic_terminal,
    general,
    hidden,
};

pub const Event = struct {
    hook: Hook,
    variable: u16,
    text_start: usize,
    text_length: usize,
    children: [3]u16 = .{root.data_structures.Node.invalid_variable} ** 3,
    children_count: usize = 0,
};

var events: [256]Event = undefined;
var event_count: usize = 0;
var fail_production = false;

pub fn reset() void {
    event_count = 0;
    fail_production = false;
}

pub fn trace() []const Event {
    return events[0..event_count];
}

pub fn setFailProduction(value: bool) void {
    fail_production = value;
}

fn record(hook: Hook, args: *ProcedureArguments) !void {
    const node = args.currentNode() orelse return error.MissingProcedureNode;
    if (event_count == events.len) return error.TraceOverflow;
    var event = Event{
        .hook = hook,
        .variable = node.variable,
        .text_start = node.text_start,
        .text_length = node.text_length,
    };
    var iterator = node.childIterator(args.context);
    while (iterator.next()) |child| {
        if (event.children_count < event.children.len) {
            event.children[event.children_count] = child.variable;
        }
        event.children_count += 1;
    }
    events[event_count] = event;
    event_count += 1;
}

pub fn hook_occurrenceHook(args: *ProcedureArguments) !void {
    try record(.occurrence, args);
}

pub fn hook_productionHook(args: *ProcedureArguments) !void {
    try record(.production, args);
    if (fail_production) return error.RequestedProcedureFailure;
}

pub fn reduction_Start_0(args: *ProcedureArguments) !void {
    try record(.automatic_production, args);
}

pub fn hook_lhsHook(args: *ProcedureArguments) !void {
    try record(.lhs, args);
}

pub fn reduction_Start(args: *ProcedureArguments) !void {
    try record(.automatic_symbol, args);
}

pub fn hook_terminalOccurrence(args: *ProcedureArguments) !void {
    const node = args.currentNode() orelse return error.MissingProcedureNode;
    node.payload.value = 1;
    try record(.terminal_occurrence, args);
}

pub fn reduction_a(args: *ProcedureArguments) !void {
    try record(.automatic_terminal, args);
}

pub fn reduction_Empty(args: *ProcedureArguments) !void {
    const node = args.currentNode() orelse return error.MissingProcedureNode;
    node.payload.value = 5;
}

pub fn hook_hiddenHook(args: *ProcedureArguments) !void {
    try record(.hidden, args);
}

pub fn reduction(args: *ProcedureArguments) !void {
    const node = args.currentNode() orelse return error.MissingProcedureNode;
    var iterator = node.childIterator(args.context);
    var sum: usize = 0;
    var count: usize = 0;
    while (iterator.next()) |child| {
        sum += child.payload.value;
        count += 1;
    }
    if (count != 0) node.payload.value = sum;
    try record(.general, args);
}
