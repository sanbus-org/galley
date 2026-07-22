const root = @import("galley");
const json = @import("error_messages.zig");

pub const renderJsonSyntaxError = json.renderJsonSyntaxError;

pub fn syntax_error_lr(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return renderJsonSyntaxError(args);
}
