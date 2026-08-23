const root = @import("galley");

// Syntax error message hooks for the keyvalue grammar.
// Filled by `galley --fill-error-messages examples/c`; every hook falls back
// to the built-in renderer until you customize its body. Hook names encode
// the parse state: `syntax_error_ll_<Variable>__expected_<symbols>`.

/// Showcase customization: a friendlier message than the generic renderer.
pub fn syntax_error_ll_Number__expected_generative_terminal_digit(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    _ = args;
    return "expected a number after ':' (digits only, for example \"alpha:42\")";
}
