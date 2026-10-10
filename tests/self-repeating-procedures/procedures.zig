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

/// Puts an inner wrapper's children in its place through the public tree
/// functions and hands back the first of them, so the loop sees a hook replace
/// the node it reduced.
pub fn hook_replaceInner(args: *ProcedureArguments) !void {
    if (!try record(args)) return;
    const node_address = args.node_address orelse return;
    const nodes = args.context.node_allocator;
    const children = data_structures.Node.cleanChildren(node_address, nodes);
    if (children == data_structures.Node.invalid_pointer) {
        args.node_address = null;
        return;
    }
    data_structures.Node.insertBefore(node_address, nodes, children);
    data_structures.Node.removeSelf(node_address, nodes);
    args.node_address = children;
}
