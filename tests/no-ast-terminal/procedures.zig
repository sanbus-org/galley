const root = @import("galley");
const ProcedureArguments = root.data_structures.ProcedureArguments;

pub const Payload = struct {
    value: usize = 0,
};

pub fn reduction_Item(args: *ProcedureArguments) !void {
    const node = args.currentNode() orelse return;
    node.payload.value = 1;
}
