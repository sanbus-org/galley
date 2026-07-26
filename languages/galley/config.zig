const std = @import("std");

pub const cli_options = .{
    .{ .name = "--with-ast", .takes_value = false },
    .{ .name = "--no-ast", .takes_value = false },
    .{ .name = "--with-procedures", .takes_value = false },
    .{ .name = "--no-procedures", .takes_value = false },
    .{ .name = "--with-error-recovery", .takes_value = false },
    .{ .name = "--no-error-recovery", .takes_value = false },
    .{ .name = "--ast-for-terminals", .takes_value = false },
    .{ .name = "--no-ast-for-terminals", .takes_value = false },
    .{ .name = "--input-size", .takes_value = true },
};

pub const cli_help =
    \\      --with-ast                     Enable AST construction.
    \\      --no-ast                       Disable AST construction and procedures.
    \\      --with-procedures              Enable procedure hooks.
    \\      --no-procedures                Disable procedure hooks.
    \\      --with-error-recovery           Enable syntax-error recovery.
    \\      --no-error-recovery             Disable syntax-error recovery.
    \\      --ast-for-terminals             Enable AST nodes for terminals.
    \\      --no-ast-for-terminals          Disable AST nodes for terminals.
    \\      --input-size <BITS>             Number of bits required to fit input size.
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

pub fn optionsFromCliArgs(args: anytype) Options {
    var result = Options{};
    var procedures_mode: ?bool = null;

    for (args) |arg| {
        if (std.mem.eql(u8, arg.name, "--with-ast")) {
            result.with_ast = true;
        } else if (std.mem.eql(u8, arg.name, "--no-ast")) {
            result.with_ast = false;
        } else if (std.mem.eql(u8, arg.name, "--with-procedures")) {
            procedures_mode = true;
        } else if (std.mem.eql(u8, arg.name, "--no-procedures")) {
            procedures_mode = false;
        } else if (std.mem.eql(u8, arg.name, "--with-error-recovery")) {
            result.with_error_recovery = true;
        } else if (std.mem.eql(u8, arg.name, "--no-error-recovery")) {
            result.with_error_recovery = false;
        } else if (std.mem.eql(u8, arg.name, "--ast-for-terminals")) {
            result.ast_for_terminals = true;
        } else if (std.mem.eql(u8, arg.name, "--no-ast-for-terminals")) {
            result.ast_for_terminals = false;
        } else if (std.mem.eql(u8, arg.name, "--input-size")) {
            const value = arg.value.?;
            result.input_size = std.fmt.parseInt(u16, value, 10) catch
                fatal("error: invalid --input-size: {s}\n", .{value});
        } else {
            unreachable;
        }
    }

    if (!result.with_ast) {
        if (procedures_mode == true) {
            fatal("error: --no-ast cannot be combined with --with-procedures\n", .{});
        }
        result.with_procedures = false;
    } else {
        result.with_procedures = procedures_mode orelse true;
    }
    return result;
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
