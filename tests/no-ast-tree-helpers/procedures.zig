const root = @import("galley");
const ProcedureArguments = root.data_structures.ProcedureArguments;
const standard_procedures = root.standard_procedures;

pub const Payload = struct {
    value: usize = 0,
};

pub const hook_dropIfEmpty = standard_procedures.dropIfEmpty;
pub const hook_dropSelf = standard_procedures.dropSelf;
pub const hook_dropChildren = standard_procedures.dropChildren;
pub const hook_rightRecursiveReduction = standard_procedures.rightRecursiveReduction;
pub const hook_leftRecursiveReduction = standard_procedures.leftRecursiveReduction;
pub const hook_replaceWithChildren = standard_procedures.replaceWithChildren;

pub const reduction_ItemsTail_0 = hook_rightRecursiveReduction;

pub fn reduction_Item(args: *ProcedureArguments) !void {
    const node = args.currentNode() orelse return;
    node.payload.value = 1;
}

fn sumChildren(node: anytype, context: anytype) usize {
    var iterator = node.childIterator(context);
    var sum: usize = 0;
    while (iterator.next()) |child| sum += child.payload.value;
    return sum;
}

pub fn reduction_ItemsTail(args: *ProcedureArguments) !void {
    const node = args.currentNode() orelse return;
    node.payload.value = sumChildren(node, args.context);
}

pub fn reduction_Items(args: *ProcedureArguments) !void {
    const node = args.currentNode() orelse return;
    node.payload.value = sumChildren(node, args.context);
}

pub fn reduction_Start(args: *ProcedureArguments) !void {
    const node = args.currentNode() orelse return;
    node.payload.value = sumChildren(node, args.context);
}
