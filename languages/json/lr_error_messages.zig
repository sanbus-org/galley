const root = @import("galley");

// Optional LR syntax error message hooks.
// Run `galley --fill-error-messages <LANGUAGE_DIR>` to append default hooks
// for the current grammar. Edit any generated function body to customize it.
//
// Example:
//
// pub fn syntax_error_lr_example_0(args: root.SyntaxErrorMessageArgs) ![]const u8 {
//     return try root.renderParseDiagnostic(args.allocator, args.diagnostic, args.style);
// }
