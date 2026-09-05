const data_structures = @import("galley").data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;

pub const Payload = struct {};

pub fn reduction_Item_1(args: *ProcedureArguments) !void {
    _ = try args.reportSemanticError("unexpected item");
}
