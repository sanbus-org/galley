const std = @import("std");
const root = @import("galley");
const ProcedureArguments = root.data_structures.ProcedureArguments;

pub const Payload = struct {
    value: usize = 0,
};

pub fn reduction(context: *ProcedureArguments) !void {
    _ = context;
}

pub const unused = {};
