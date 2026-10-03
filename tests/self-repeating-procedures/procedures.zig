const data_structures = @import("galley").data_structures;
const standard_procedures = @import("galley").standard_procedures;
const ProcedureArguments = data_structures.ProcedureArguments;

pub const Payload = struct {};

/// What a hook saw on the node it was called for, before it acted.
pub const Call = struct {
    variable: u16,
    has_parent: bool,
    children_count: u32,
    last_child_variable: ?u16,
};

var call_buffer: [32]Call = undefined;
var call_count: usize = 0;

pub fn resetTrace() void {
    call_count = 0;
}

pub fn trace() []const Call {
    return call_buffer[0..call_count];
}

/// Records the call and reports whether the node already has a parent, which
/// in a self-repeating loop means it is an inner wrapper.
fn record(args: *ProcedureArguments) !bool {
    const node = args.currentNode() orelse return error.MissingNode;
    if (call_count == call_buffer.len) return error.TraceOverflow;
    const has_parent = node.parent != data_structures.Node.invalid_pointer;
    call_buffer[call_count] = .{
        .variable = node.variable,
        .has_parent = has_parent,
        .children_count = node.children_count,
        .last_child_variable = if (node.last_child == data_structures.Node.invalid_pointer)
            null
        else
            args.context.node_allocator.at(node.last_child).variable,
    };
    call_count += 1;
    return has_parent;
}

pub fn hook_dropInner(args: *ProcedureArguments) !void {
    if (try record(args)) try standard_procedures.dropSelf(args);
}

pub fn hook_replaceInner(args: *ProcedureArguments) !void {
    if (try record(args)) try standard_procedures.replaceWithChildren(args);
}
