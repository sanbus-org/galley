const std = @import("std");

pub const indentation_syntax = false;
pub const Payload = struct {};

pub fn reduction_Start() void {
    std.debug.print("Parsed Lua successfully.\n", .{});
}
