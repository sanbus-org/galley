const root = @import("galley");

// Optional LL syntax error message hooks.
// Run `galley --fill-error-messages <LANGUAGE_DIR>` to append default hooks
// for the current grammar. Edit any generated function body to customize it.
//
// Example:
//
// pub fn syntax_error_ll_Value__expected_String_or_Number(args: root.SyntaxErrorMessageArgs) ![]const u8 {
//     return try root.renderParseDiagnostic(args.allocator, args.diagnostic, args.style);
// }
//
// Broader LL fallbacks are also supported:
//
// pub fn syntax_error_ll_Value(args: root.SyntaxErrorMessageArgs) ![]const u8 {
//     return try root.renderParseDiagnostic(args.allocator, args.diagnostic, args.style);
// }
//
// pub fn syntax_error_ll(args: root.SyntaxErrorMessageArgs) ![]const u8 {
//     return try root.renderParseDiagnostic(args.allocator, args.diagnostic, args.style);
// }
