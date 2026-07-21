const root = @import("galley");

pub const Payload = struct {};

var mark_count: usize = 0;
var captured_root = root.data_structures.ASTNode.invalid_pointer;

pub fn reset() void {
    mark_count = 0;
    captured_root = root.data_structures.ASTNode.invalid_pointer;
}

pub fn marks() usize {
    return mark_count;
}

pub fn capturedRoot() root.data_structures.ASTNode.Pointer {
    return captured_root;
}

pub fn mark(args: *root.data_structures.ProcedureArguments) void {
    _ = args;
    mark_count += 1;
}

pub fn capture(args: *root.data_structures.ProcedureArguments) void {
    captured_root = args.node orelse root.data_structures.ASTNode.invalid_pointer;
}
