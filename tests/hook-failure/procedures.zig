const data_structures = @import("galley").data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;

pub const Payload = struct {};

/// Where the test makes a hook fail the way a host shim does: record the
/// failure, then return `error.HookFailed`.
pub const FailAt = enum { nowhere, entry, document };
pub var fail_at: FailAt = .nowhere;

fn fail(args: *ProcedureArguments, hook_name: []const u8) !void {
    args.recordHookFailure(hook_name);
    return error.HookFailed;
}

pub fn reduction_Entry(args: *ProcedureArguments) !void {
    if (fail_at == .entry) try fail(args, "reduction_Entry");
}

pub fn reduction_Document(args: *ProcedureArguments) !void {
    if (fail_at == .document) try fail(args, "reduction_Document");
}
