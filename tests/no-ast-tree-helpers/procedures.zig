const root = @import("galley");
const ProcedureArguments = root.data_structures.ProcedureArguments;
const standard_procedures = root.standard_procedures;

pub const Payload = struct {
    value: usize = 0,
};

pub const dropIfEmpty = standard_procedures.dropIfEmpty;
pub const dropSelf = standard_procedures.dropSelf;
pub const dropChildren = standard_procedures.dropChildren;
pub const rightRecursiveReduction = standard_procedures.rightRecursiveReduction;
pub const leftRecursiveReduction = standard_procedures.leftRecursiveReduction;
pub const replaceWithChildren = standard_procedures.replaceWithChildren;

pub const reduction_ItemsTail_0 = rightRecursiveReduction;

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
