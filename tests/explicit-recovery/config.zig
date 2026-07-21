pub const params = "";
pub const indentation_syntax = false;
pub const Options = struct {};

pub fn optionsFromArgs(args: anytype) Options {
    _ = args;
    return .{};
}
