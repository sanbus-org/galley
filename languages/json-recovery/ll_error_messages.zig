const root = @import("galley");
const json = @import("error_messages.zig");

pub const renderJsonSyntaxError = json.renderJsonSyntaxError;

pub fn syntax_error_ll_Value(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return renderJsonSyntaxError(args);
}

pub fn syntax_error_ll_ObjectMembers(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return renderJsonSyntaxError(args);
}

pub fn syntax_error_ll_ObjectMembersTail(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return renderJsonSyntaxError(args);
}

pub fn syntax_error_ll_ArrayMembers(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return renderJsonSyntaxError(args);
}

pub fn syntax_error_ll_ArrayMembersTail(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return renderJsonSyntaxError(args);
}

pub fn syntax_error_ll__ValueSlot(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return renderJsonSyntaxError(args);
}

pub fn syntax_error_ll(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return renderJsonSyntaxError(args);
}
