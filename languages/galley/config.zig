pub const params =
    \\    --with-ast
    \\                                  Enables AST construction.
    \\    --no-ast
    \\                                  Disables AST construction.
    \\    --with-procedures
    \\                                  Enables procedure hooks.
    \\    --no-procedures
    \\                                  Disables procedure hooks.
    \\    --with-error-recovery
    \\                                  Enables syntax-error recovery.
    \\    --no-error-recovery
    \\                                  Disables syntax-error recovery.
    \\    --ast-for-terminals
    \\                                  Enables AST nodes for terminals.
    \\    --no-ast-for-terminals
    \\                                  Disables AST nodes for terminals.
    \\    --input-size <INPUT_SIZE>
    \\                                  Number of bits required to fit input size.
    \\
;

pub const indentation_syntax = false;

pub const Options = struct {
    with_ast: bool = true,
    with_procedures: bool = true,
    with_error_recovery: bool = false,
    ast_for_terminals: bool = false,
    input_size: u16 = 16,
};

pub fn optionsFromArgs(args: anytype) Options {
    return .{
        .with_ast = if (@field(args, "no-ast") > 0) false else true,
        .with_procedures = if (@field(args, "no-procedures") > 0) false else true,
        .with_error_recovery = @field(args, "with-error-recovery") > 0 and @field(args, "no-error-recovery") == 0,
        .ast_for_terminals = @field(args, "ast-for-terminals") > 0,
        .input_size = if (@field(args, "input-size")) |input_size| input_size else 16,
    };
}
