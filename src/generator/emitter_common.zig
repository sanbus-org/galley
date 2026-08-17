const std = @import("std");
const common = @import("generator_common");

pub fn emitRecoveryOffsetFunction(writer: *std.Io.Writer, function_name: []const u8) !void {
    try writer.print(
        \\fn {s}(context: *data_structures.Context, candidates: []const []const u8, start: usize) !?usize {{
        \\    const lookahead = try context.recoveryLookahead();
        \\    if (candidates.len == 0) {{
        \\        if (lookahead[0] == 0) context.finishSyntaxRecovery();
        \\        return null;
        \\    }}
        \\    const upper = @min(context.recoveryWindow(), lookahead.len);
        \\    var offset = start;
        \\    while (offset < upper) : (offset += 1) {{
        \\        for (candidates) |candidate| {{
        \\            if (candidate.len <= lookahead.len - offset and std.mem.eql(u8, lookahead[offset..][0..candidate.len], candidate)) {{
        \\                context.finishSyntaxRecovery();
        \\                return offset;
        \\            }}
        \\        }}
        \\        if (lookahead[offset] == 0) break;
        \\    }}
        \\    if (lookahead[0] == 0) context.finishSyntaxRecovery();
        \\    return null;
        \\}}
        \\
    , .{function_name});
}

pub fn emitRecoveryPoints(writer: *std.Io.Writer, points: []const common.RecoveryPoint) !void {
    try writer.writeAll("&[_]root.SyntaxRecoveryPoint{");
    for (points, 0..) |point, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.writeAll(".{ .terminal = ");
        try common.emitStringLiteral(writer, point.terminal);
        try writer.print(", .@\"resume\" = .{s} }}", .{@tagName(point.@"resume")});
    }
    try writer.writeByte('}');
}

/// Emits the generated `ExplicitRecoveryScope` struct declaration shared
/// verbatim by the LL and LR backends.
pub fn emitExplicitRecoveryScopeStruct(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\const ExplicitRecoveryScope = struct {
        \\    id: usize,
        \\    target: root.SyntaxRecoveryTarget,
        \\    points: []const root.SyntaxRecoveryPoint,
        \\};
        \\
    );
}

/// Emits the `&ExplicitRecoveryScope{...}` literal for a variable's own
/// recovery points, shared verbatim by the LL and LR backends.
pub fn emitLhsRecoveryScope(writer: *std.Io.Writer, scopes: *const common.RecoveryPlan, symbols: []const common.Symbol, variable: usize) !void {
    const scope = scopes.findLhs(variable) orelse unreachable;
    try writer.print("&ExplicitRecoveryScope{{ .id = {d}, .target = .{{ .lhs_variable = ", .{scope.id});
    try common.emitStringLiteral(writer, symbols[variable].id);
    try writer.writeAll(" }, .points = ");
    try emitRecoveryPoints(writer, symbols[variable].annotations.recovery_points.items);
    try writer.writeAll(" }");
}

/// Emits the `&ExplicitRecoveryScope{...}` literal for a rule production's
/// recovery points, shared verbatim by the LL and LR backends.
pub fn emitProductionRecoveryScope(writer: *std.Io.Writer, scopes: *const common.RecoveryPlan, symbols: []const common.Symbol, rule: common.Rule, rule_index: usize) !void {
    const scope = scopes.findProduction(rule_index) orelse unreachable;
    try writer.print("&ExplicitRecoveryScope{{ .id = {d}, .target = .{{ .production = .{{ .variable = ", .{scope.id});
    try common.emitStringLiteral(writer, symbols[rule.header].id);
    try writer.print(", .rhs_index = {s} }} }}, .points = ", .{rule.rhs_index});
    try emitRecoveryPoints(writer, rule.annotations.recovery_points.items);
    try writer.writeAll(" }");
}

/// Emits the fail-fast syntax error support block shared verbatim by the LL
/// and LR backends (emitted when error recovery is disabled). `function_prefix`
/// is the backend lowercase prefix (`ll`/`lr`), `renderer_decl` is the renderer
/// type name prefix (`LL`/`LR`), and `error_messages_decl` is the decl name in
/// the generated error messages namespace (`syntax_error_ll`/`syntax_error_lr`).
pub fn emitFailFastSyntaxErrorSupport(writer: *std.Io.Writer, function_prefix: []const u8, renderer_decl: []const u8, error_messages_decl: []const u8) !void {
    try writer.print(
        \\const {s}FailFastMessageRenderer = *const fn (root.SyntaxErrorMessageArgs) anyerror![]const u8;
        \\
        \\fn {s}FailFastSyntaxError(
        \\    context: *data_structures.Context,
        \\    diagnostic_context: root.SyntaxDiagnosticContext,
        \\    expected_tokens: []const []const u8,
        \\    render_message: {s}FailFastMessageRenderer,
        \\) anyerror {{
        \\    @branchHint(.cold);
        \\    context.recordSyntaxDiagnostic(diagnostic_context, expected_tokens) catch |err| return err;
        \\    const diagnostic_message = render_message(.{{
        \\        .allocator = context.runtime().arena_allocator,
        \\        .context = context,
        \\        .diagnostic = context.runtime().last_diagnostic.?,
        \\        .style = .ansi,
        \\    }}) catch "";
        \\    if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{{s}}", .{{diagnostic_message}});
        \\    return root.ParseError.SyntaxError;
        \\}}
        \\
        \\fn {s}FailFastDefaultMessage(args: root.SyntaxErrorMessageArgs) anyerror![]const u8 {{
        \\    if (comptime @hasDecl(error_messages, "{s}"))
        \\        return error_messages.{s}(args);
        \\    if (comptime @hasDecl(error_messages, "syntax_error"))
        \\        return error_messages.syntax_error(args);
        \\    return root.renderParseDiagnostic(args.allocator, args.diagnostic, args.style);
        \\}}
        \\
    , .{ renderer_decl, function_prefix, renderer_decl, function_prefix, error_messages_decl, error_messages_decl });
}

/// Emits a fail-fast syntax error message renderer function shared by the LL
/// and LR backends. `error_message_fields` is the ordered list of error
/// messages namespace decls to try before `fallback_message_function`.
pub fn emitFailFastMessageRenderer(writer: *std.Io.Writer, function_name: []const u8, error_message_fields: []const []const u8, fallback_message_function: []const u8) !void {
    try writer.print("fn {s}_message(args: root.SyntaxErrorMessageArgs) anyerror![]const u8 {{\n", .{function_name});
    for (error_message_fields) |field| {
        try writer.print("    if (comptime @hasDecl(error_messages, \"{s}\"))\n        return @field(error_messages, \"{s}\")(args);\n", .{ field, field });
    }
    try writer.print("    return {s}(args);\n}}\n\n", .{fallback_message_function});
}

/// Emits the standalone customization file from completed diagnostic plans.
pub fn emitErrorMessageFile(
    writer: *std.Io.Writer,
    parser_label: []const u8,
    specs: []const common.ErrorMessageSpec,
) !void {
    try writer.print(
        \\const root = @import("galley");
        \\
        \\// Default {s} syntax error messages generated by Galley.
        \\// Edit any function body to customize that error site.
        \\
        \\
    , .{parser_label});
    for (specs) |spec| {
        try writer.print(
            \\pub fn {s}(args: root.SyntaxErrorMessageArgs) ![]const u8 {{
            \\    return try root.renderParseDiagnostic(args.allocator, args.diagnostic, args.style);
            \\}}
            \\
            \\
        , .{spec.name});
    }
}

pub fn emitParserMetadata(
    writer: *std.Io.Writer,
    parser_type: []const u8,
    options: common.Options,
    uses_explicit_recovery: bool,
    longest_terminal_length: usize,
    uses_verbatim: bool,
    syntax_error_stack_supported: bool,
) !void {
    try writer.print(
        \\
        \\pub const parser_type = data_structures.ParserType.{s};
        \\pub const ErrorRecoveryMode = enum {{ disabled, automatic, explicit }};
        \\pub const is_ast_enabled = {};
        \\pub const are_procedures_enabled = {};
        \\pub const allow_no_ast_tree_procedures = {};
        \\pub const is_error_recovery_enabled = {};
        \\pub const error_recovery_mode: ErrorRecoveryMode = .{s};
        \\pub const is_position_tracking_enabled = {s};
        \\pub const is_input_streaming_enabled = {};
        \\pub const syntax_error_stack_depth = {s};
        \\pub const is_syntax_error_stack_enabled = {s};
        \\{s}pub const longest_terminal_length = {d};
        \\
        \\
    , .{
        parser_type,
        options.with_ast,
        options.with_procedures,
        options.allow_no_ast_tree_procedures,
        options.with_error_recovery,
        if (!options.with_error_recovery) "disabled" else if (uses_explicit_recovery) "explicit" else "automatic",
        if (options.with_position_tracking) |enabled| if (enabled) "true" else "false" else "builtin.mode != .ReleaseFast",
        options.with_input_streaming,
        if (syntax_error_stack_supported)
            "root.syntax_error_stack_depth"
        else
            "1",
        if (syntax_error_stack_supported) "syntax_error_stack_depth > 1" else "false",
        if (uses_verbatim) "pub const uses_verbatim = true;\n" else "",
        longest_terminal_length,
    });
}

/// Emits the grammar metadata shared by LL and LR generated parsers.
///
/// The function deliberately preserves the existing table order and source
/// spelling; backends provide only their completed, typed grammar plan.
pub fn emitGrammarTables(
    writer: *std.Io.Writer,
    symbols: []const common.Symbol,
    variables: []const usize,
    rules: []const common.Rule,
) !void {
    try writer.writeAll("pub const symbols = &[_][]const u8{\n");
    for (symbols, 0..) |symbol, index| {
        try writer.writeAll("    ");
        try common.emitStringLiteral(writer, symbol.id);
        try writer.print(", // {d}\n", .{index});
    }
    try writer.writeAll("};\n\npub const is_terminal = &[_]bool{\n");
    for (symbols) |symbol| try writer.print("    {},\n", .{symbol.kind != .variable});
    try writer.writeAll("};\n\npub const is_generative_terminal = &[_]bool{\n");
    for (symbols) |symbol| try writer.print("    {},\n", .{symbol.kind == .generative_terminal});
    try writer.writeAll("};\n\npub const variables = &[_][]const u8{\n");
    for (variables) |symbol_index| {
        try writer.writeAll("    ");
        try common.emitStringLiteral(writer, symbols[symbol_index].id);
        try writer.writeAll(",\n");
    }
    try writer.writeAll("};\n\npub const symbol_by_variable = &[_]usize{\n");
    for (variables) |symbol_index| try writer.print("    {d},\n", .{symbol_index});
    try writer.writeAll("};\n\npub const rules = &[_]data_structures.Rule{\n");
    for (rules) |rule| {
        const variable_index = variableIndex(variables, rule.header);
        try writer.print("    data_structures.Rule{{ .header = {d}, .right_hand_side = &[_]u16{{", .{variable_index});
        if (rule.rhs.items.len > 1) try writer.writeByte(' ');
        for (rule.rhs.items, 0..) |symbol_index, i| {
            if (i != 0) try writer.writeAll(", ");
            try writer.print("{d}", .{symbol_index});
        }
        if (rule.rhs.items.len > 1) try writer.writeByte(' ');
        try writer.writeAll("}, .right_hand_side_index = ");
        try common.emitStringLiteral(writer, rule.rhs_index);
        try writer.writeAll(" }, // ");
        try writer.writeAll(symbols[rule.header].id);
        try writer.writeByte('\n');
    }
    try writer.writeAll("};\n\n");
}

fn variableIndex(variables: []const usize, symbol_index: usize) usize {
    for (variables, 0..) |candidate, index| {
        if (candidate == symbol_index) return index;
    }
    unreachable;
}

/// Emits the procedure support declarations shared verbatim by the LL and LR
/// generators. The current node is resolved through the `ProcedureArguments`
/// accessor on each hook phase, so no refresh pass is needed between calls.
pub fn emitProcedureSupport(
    writer: *std.Io.Writer,
    rules: []const common.Rule,
    symbols: []const common.Symbol,
    variables: []const usize,
) !void {
    try writer.print(
        \\const ProcedureSequenceNode = struct {{
        \\    procedure: *const data_structures.Procedure,
        \\    next: ?*const ProcedureSequenceNode,
        \\}};
        \\
        \\fn makeProcedureSequence(comptime procedure_names: []const []const u8) ?*const ProcedureSequenceNode {{
        \\    if (procedure_names.len == 0) return null;
        \\    const procedure_name = procedure_names[0];
        \\    return &ProcedureSequenceNode{{
        \\        .procedure = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), procedure_name),
        \\        .next = makeProcedureSequence(procedure_names[1..]),
        \\    }};
        \\}}
        \\
        \\fn runProcedureSequence(sequence: ?*const ProcedureSequenceNode, args: *data_structures.ProcedureArguments) !void {{
        \\    var current = sequence;
        \\    while (current) |entry| {{
        \\        const procedure = @as(*data_structures.Procedure, @constCast(entry.procedure));
        \\        try procedure(args);
        \\        current = entry.next;
        \\    }}
        \\}}
        \\
        \\pub const rule_procedures = rule_procedures: {{
        \\    var arr: [{d}]?*const data_structures.Procedure = .{{null}} ** {d};
        \\
        \\    for (rules, 0..) |rule, index| {{
        \\        const procedure_name = "reduction_" ++ variables[rule.header] ++ "_" ++ rule.right_hand_side_index;
        \\        if (@hasDecl(procedures, procedure_name)) {{
        \\            arr[index] = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), procedure_name);
        \\        }}
        \\    }}
        \\
        \\    break :rule_procedures arr;
        \\}};
        \\
        \\pub const symbol_procedures = symbol_procedures: {{
        \\    var arr: [{d}]?*const data_structures.Procedure = .{{null}} ** {d};
        \\
        \\    for (symbols, 0..) |symbol, index| {{
        \\        const procedure_name = "reduction_" ++ symbol;
        \\        if (@hasDecl(procedures, procedure_name)) {{
        \\            arr[index] = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), symbol);
        \\        }}
        \\    }}
        \\
        \\    break :symbol_procedures arr;
        \\}};
        \\
        \\const variable_procedure_names = &[_][]const []const u8{{
        \\
    , .{ rules.len, rules.len, symbols.len, symbols.len });
    for (variables) |symbol_index| {
        const symbol = symbols[symbol_index];
        try writer.writeAll("    &[_][]const u8{");
        for (symbol.annotations.procedures.items, 0..) |procedure, i| {
            if (i != 0) try writer.writeAll(", ");
            try common.emitStringLiteral(writer, procedure);
        }
        try writer.writeAll("},\n");
    }
    try writer.print(
        \\}};
        \\
        \\pub const variable_procedures = variable_procedures: {{
        \\    var arr: [{d}]?*const ProcedureSequenceNode = .{{null}} ** {d};
        \\
        \\    for (variable_procedure_names, 0..) |procedure_names, index| {{
        \\        arr[index] = makeProcedureSequence(procedure_names);
        \\    }}
        \\
        \\    break :variable_procedures arr;
        \\}};
        \\
        \\pub const reduction_procedure: ?*const data_structures.Procedure = if (@hasDecl(procedures, "reduction")) data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, "reduction"), "reduction") else null;
        \\
        \\
    , .{ variables.len, variables.len });
}

pub fn emitProcedureSequenceExpression(writer: *std.Io.Writer, procedures_: []const []const u8) !void {
    try writer.writeAll("comptime makeProcedureSequence(&[_][]const u8{");
    for (procedures_, 0..) |procedure, index| {
        if (index != 0) try writer.writeAll(", ");
        try common.emitStringLiteral(writer, procedure);
    }
    try writer.writeAll("})");
}

/// Emits the `var args = data_structures.ProcedureArguments{...};` block shared by
/// the LL and LR backends' procedure call sites. When `rule_index` is present the
/// `.rule` field references the generated rule table; otherwise a `.rule = null`
/// literal is emitted. `trailing_blank` controls an optional blank separator after
/// the closing brace.
pub fn emitProcedureArgsStruct(
    writer: *std.Io.Writer,
    indent: []const u8,
    with_ast: bool,
    rule_index: ?usize,
    node_expr: []const u8,
    trailing_blank: bool,
) !void {
    if (with_ast) {
        if (rule_index) |rule| {
            try writer.print(
                \\{s}var args = data_structures.ProcedureArguments{{
                \\{s}    .context = context,
                \\{s}    .rule = rules[{d}],
                \\{s}    .node_address = {s},
                \\{s}}};
            , .{ indent, indent, indent, rule, indent, node_expr, indent });
        } else {
            try writer.print(
                \\{s}var args = data_structures.ProcedureArguments{{
                \\{s}    .context = context,
                \\{s}    .rule = null,
                \\{s}    .node_address = {s},
                \\{s}}};
            , .{ indent, indent, indent, indent, node_expr, indent });
        }
    } else {
        if (rule_index) |rule| {
            try writer.print(
                \\{s}var args = data_structures.ProcedureArguments{{
                \\{s}    .context = context,
                \\{s}    .rule = rules[{d}],
                \\{s}    ._temp_node = &{s},
                \\{s}}};
            , .{ indent, indent, indent, rule, indent, node_expr, indent });
        } else {
            try writer.print(
                \\{s}var args = data_structures.ProcedureArguments{{
                \\{s}    .context = context,
                \\{s}    .rule = null,
                \\{s}    ._temp_node = &{s},
                \\{s}}};
            , .{ indent, indent, indent, indent, node_expr, indent });
        }
    }
    if (trailing_blank) try writer.writeByte('\n');
}

/// Emits the `{indent}try runProcedureSequence(` prefix of a procedure invocation;
/// the caller writes the procedure/sequence expression, then closes with
/// `, &args);\n`. Shared by the LL and LR backends.
pub fn emitProcedureRunCall(writer: *std.Io.Writer, indent: []const u8) !void {
    try writer.print("{s}try runProcedureSequence(", .{indent});
}

/// Emits a complete `try runProcedureSequence(<rule procedure sequence>, &args);`
/// statement using the rule's own annotation procedures.
pub fn emitProcedureRuleSequenceCall(writer: *std.Io.Writer, indent: []const u8, procedures_: []const []const u8) !void {
    try emitProcedureRunCall(writer, indent);
    try emitProcedureSequenceExpression(writer, procedures_);
    try writer.writeAll(", &args);\n");
}

/// Emits the post-args procedure dispatch tail shared verbatim by the LL and LR
/// backends. The rule variant (all three indices present) is used after a rule
/// reduction; the symbol-only variant is used for terminal procedure blocks.
pub fn emitProcedureDispatchTail(
    writer: *std.Io.Writer,
    indent: []const u8,
    rule_index: ?usize,
    variable_index: ?usize,
    parent_variable: ?usize,
    symbol_index: ?usize,
) !void {
    if (rule_index != null and variable_index != null and parent_variable != null) {
        try writer.print(
            \\{s}if (comptime rule_procedures[{d}]) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\{s}try runProcedureSequence(variable_procedures[{d}], &args);
            \\{s}if (comptime symbol_procedures[{d}]) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\{s}if (comptime reduction_procedure) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\
        , .{
            indent, rule_index.?,     indent, indent,            indent,
            indent, variable_index.?, indent, parent_variable.?, indent,
            indent, indent,           indent, indent,            indent,
            indent,
        });
    } else {
        try writer.print(
            \\{s}if (comptime symbol_procedures[{d}]) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\{s}if (comptime reduction_procedure) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\
        , .{
            indent, symbol_index.?, indent, indent, indent,
            indent, indent,         indent, indent,
        });
    }
}

/// Emits a comma-separated rendering of the rule RHS for Debug-mode reduction
/// output, shared verbatim by the LL and LR backends.
pub fn emitRuleSymbolsForDebug(writer: *std.Io.Writer, symbols: []const common.Symbol, rule: common.Rule) !void {
    for (rule.rhs.items, 0..) |symbol_index, i| {
        if (i != 0) try writer.writeAll(", ");
        const symbol = symbols[symbol_index];
        if (symbol.kind == .variable) {
            try common.emitFormatToken(writer, symbol.id);
        } else {
            try writer.writeByte('\'');
            try common.emitFormatToken(writer, symbol.id);
            try writer.writeByte('\'');
        }
    }
}

/// Emits the verbosity-gated Debug reduction log, shared by the LL and LR
/// backends. The head symbol id is taken from the rule header.
pub fn emitDebugReduction(writer: *std.Io.Writer, symbols: []const common.Symbol, rule: common.Rule, indent: []const u8) !void {
    try writer.print(
        \\{s}if (comptime builtin.mode == .Debug) {{
        \\{s}    if (context.verbosityLevel() > 1) {{
        \\{s}        std.debug.print("Reduction:
    , .{ indent, indent, indent });
    try writer.writeAll(" ");
    try common.emitFormatToken(writer, symbols[rule.header].id);
    try writer.writeAll(" <~ ");
    try emitRuleSymbolsForDebug(writer, symbols, rule);
    try writer.print(
        \\\n", .{{}});
        \\{s}    }}
        \\{s}}}
    , .{ indent, indent });
}
