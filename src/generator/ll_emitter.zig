const std = @import("std");
const common = @import("generator_common");
const emitter_common = @import("generator_emitter_common");
const planning = @import("ll_plan.zig");
const switch_planning = @import("generator_switch_plan");

pub const Options = common.Options;
pub const atomic_file = common.atomic_file;
const Symbol = common.Symbol;
const Rule = common.Rule;
const bytesToInt = common.bytesToInt;
const emitEscapedForComment = common.emitEscapedForComment;
const emitFormatToken = common.emitFormatToken;
const emitStringLiteral = common.emitStringLiteral;
const indented = common.indented;
const SyntaxErrorHandlerSpec = planning.SyntaxErrorHandler;
const LLPlan = planning.LLPlan;

/// The LL backend tracks the in-progress variable stack whenever the generated
/// parser is compiled with the stack enabled (`syntax_error_stack_depth > 1`).
/// The generated source gates the push/pop instrumentation and the
/// `@call(.always_tail, ...)` error bail-out on the comptime
/// `is_syntax_error_stack_enabled` const: when the stack is enabled, the plain
/// return must be used so the `defer` that pops the stack always runs; when
/// disabled, the whole instrumentation folds away and the tail call returns.
const Generator = struct {
    allocator: std.mem.Allocator,
    options: Options,
    symbols: std.ArrayList(Symbol),
    variables: std.ArrayList(usize),
    rules: std.ArrayList(Rule),
    plan: *const LLPlan,
    has_occurrence_procedures: bool,
    uses_explicit_recovery: bool,
    has_recovery_annotations: bool,
    uses_verbatim: bool,
    end_symbol: usize,
    verbatim_literal: ?[]const u8 = null,
    verbatim_consume: bool = true,

    fn init(allocator: std.mem.Allocator, options: Options, grammar: *const common.PreparedGrammar, plan: *const LLPlan) Generator {
        return .{
            .allocator = allocator,
            .options = options,
            .symbols = grammar.symbols,
            .variables = grammar.variables,
            .rules = grammar.rules,
            .plan = plan,
            .has_occurrence_procedures = grammar.has_occurrence_procedures,
            .uses_explicit_recovery = grammar.uses_explicit_recovery,
            .has_recovery_annotations = grammar.has_recovery_annotations,
            .uses_verbatim = grammar.uses_verbatim,
            .end_symbol = grammar.eof,
        };
    }

    fn emit(self: *Generator, writer: *std.Io.Writer) !void {
        try writer.writeAll(
            \\const builtin = @import("builtin");
            \\const std = @import("std");
            \\const root = @import("galley");
            \\const procedures = root.procedures;
            \\const error_messages = root.error_messages;
            \\const data_structures = root.data_structures;
            \\const string_utilities = root.string_utilities;
            \\
        );
        try emitter_common.emitParserMetadata(
            writer,
            "ll",
            self.has_recovery_annotations,
            self.longestTerminalLength(),
            self.uses_verbatim,
            true,
        );

        try emitter_common.emitGrammarTables(writer, self.symbols.items, self.variables.items, self.rules.items, self.end_symbol);
        try writer.writeAll(
            \\fn symbolReturnsNodeSuppressed(comptime symbol_index: usize, comptime suppress_ast: bool) bool {
            \\    return !suppress_ast and symbolReturnsNode(symbol_index);
            \\}
            \\fn nodeReturnType(comptime symbol_index: usize, comptime suppress_ast: bool) type {
            \\    if (symbolReturnsNodeSuppressed(symbol_index, suppress_ast)) return root.data_structures.VariableResult;
            \\    return void;
            \\}
            \\
            \\fn ruleHasNodeChildren(comptime rule_index: usize, comptime suppress_ast: bool) bool {
            \\    inline for (rules[rule_index].right_hand_side) |child_symbol| {
            \\        if (symbolReturnsNodeSuppressed(child_symbol, suppress_ast)) return true;
            \\    }
            \\    return false;
            \\}
            \\
        );
        try writer.writeAll(
            \\const RootReduction = struct {
            \\    ast_root: ?data_structures.Node.Pointer = null,
            \\    semantic_root: if (are_procedures_enabled) ?data_structures.Payload else void = if (are_procedures_enabled) null else {},
            \\};
            \\
        );
        // Recovery support for every style is emitted unconditionally: the
        // active style is selected at comptime per configuration, and unused
        // support folds away under lazy analysis.
        try self.emitRecoverySupport(writer);
        if (self.uses_explicit_recovery) {
            try self.emitExplicitRecoverySupport(writer);
        }
        try emitter_common.emitProcedureSupport(self.allocator, writer, self.rules.items, self.symbols.items, self.variables.items);
        try self.emitParserFunctions(writer);
        try self.emitAstSuppressedParsers(writer);
        try self.emitSyntaxErrorHandlers(writer);
        if (self.uses_explicit_recovery) try self.emitExplicitSyntaxDiagnosticFlusher(writer);
        try writer.writeAll(
            \\pub fn parseWithResult(context: *data_structures.Context) !root.ParseResult {
            \\    var root_reduction: RootReduction = .{};
            \\    _ = parse__AugmentedStart(context
        );
        if (self.has_occurrence_procedures) try writer.writeAll(", null");
        if (self.uses_explicit_recovery) try writer.writeAll(", null");
        try writer.writeAll(", &root_reduction");
        if (self.uses_explicit_recovery) {
            try writer.writeAll(
                \\) catch |err| switch (err) {
                \\        root.ParseError.SyntaxError, error.ExplicitSyntaxRecovery => {
                \\            try llFlushSyntaxDiagnostic(context);
                \\            return root.ParseError.SyntaxError;
                \\        },
                \\        else => return err,
                \\    };
            );
        } else {
            try writer.writeAll(
                \\) catch |err| switch (err) {
                \\        root.ParseError.SyntaxError => return root.ParseError.SyntaxError,
                \\        else => return err,
                \\    };
            );
        }
        try writer.writeByte('\n');
        try writer.writeAll("if (comptime is_error_recovery_enabled) {\n    if (context.hasSyntaxErrors()) return root.ParseError.SyntaxError;\n}\n");
        try writer.writeAll(
            \\
            \\    if (context.verbosityLevel() > 0) {
            \\        std.log.info("The input file was parsed successfully!", .{});
            \\    }
            \\
        );
        try writer.writeAll(
            \\    return .{
            \\        .parsed_bytes = context.pos() - 1,
            \\        .line = context.line,
            \\        .column = context.column,
            \\        .ast_root = root_reduction.ast_root,
            \\        .semantic_root = root_reduction.semantic_root,
            \\    };
            \\}
            \\
            \\pub fn parse(context: *data_structures.Context) !void {
            \\    _ = try parseWithResult(context);
            \\}
            \\
        );
        // Cold fail-fast support at the very end so the large
        // `llFailFastDefaultMessage` (session → config → hooks chain) does
        // not sit between the hot parser functions and displace them in the
        // final binary layout.
        try self.emitFailFastSyntaxErrorSupport(writer);
    }

    fn emitRecoverySupport(self: *Generator, writer: *std.Io.Writer) !void {
        _ = self;
        try emitter_common.emitRecoveryOffsetFunction(writer, "llRecoveryOffset");
    }

    fn emitExplicitRecoverySupport(self: *Generator, writer: *std.Io.Writer) !void {
        try emitter_common.emitExplicitRecoveryScopeStruct(writer);
        try writer.writeByte('\n');
        try writer.writeAll(
            \\fn llTryExplicitScope(context: *data_structures.Context, scope: *const ExplicitRecoveryScope) !bool {
            \\    if (!try context.tryExplicitRecovery(scope.id, scope.target, scope.points)) return false;
            \\    try llFlushSyntaxDiagnostic(context);
            \\    return true;
            \\}
            \\
        );

        for (self.variables.items) |variable| {
            if (!self.hasParseEntries(variable)) continue;
            try writer.print("fn llTryRecoverySelection_{d}(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {{\n", .{variable});
            try writer.writeAll("    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;\n");
            if (self.symbols.items[variable].annotations.recovery_points.items.len != 0) {
                try writer.writeAll("    if (try llTryExplicitScope(context, ");
                try emitter_common.emitLhsRecoveryScope(writer, &self.plan.recovery.scopes, self.symbols.items, variable);
                try writer.writeAll(")) return true;\n");
            }
            try writer.writeAll("    return false;\n}\n\n");
        }

        for (self.rules.items, 0..) |rule, rule_index| {
            if (self.symbols.items[rule.header].kind != .variable or !self.hasParseEntries(rule.header)) continue;
            try writer.print("fn llTryRecoveryRule_{d}(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {{\n", .{rule_index});
            try writer.writeAll("    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;\n");
            if (rule.annotations.recovery_points.items.len != 0) {
                try writer.writeAll("    if (try llTryExplicitScope(context, ");
                try emitter_common.emitProductionRecoveryScope(writer, &self.plan.recovery.scopes, self.symbols.items, rule, rule_index);
                try writer.writeAll(")) return true;\n");
            }
            if (self.symbols.items[rule.header].annotations.recovery_points.items.len != 0) {
                try writer.writeAll("    if (try llTryExplicitScope(context, ");
                try emitter_common.emitLhsRecoveryScope(writer, &self.plan.recovery.scopes, self.symbols.items, rule.header);
                try writer.writeAll(")) return true;\n");
            }
            try writer.writeAll("    return false;\n}\n\n");
        }
    }

    fn emitExplicitSyntaxDiagnosticFlusher(self: *Generator, writer: *std.Io.Writer) !void {
        try writer.writeAll("fn llFlushSyntaxDiagnostic(context: *data_structures.Context) !void {\n");
        try writer.writeAll("    const site = context.pendingSyntaxErrorSite() orelse return;\n");
        try writer.writeAll("    context.clearPendingSyntaxErrorSite();\n");
        try writer.writeAll("    switch (site) {\n");
        for (self.plan.syntax_error_handlers.items, 0..) |spec, site_index| {
            try writer.print("        {d} => {{\n", .{site_index});
            try self.emitSyntaxErrorMessagePrint(writer, spec.exact_name, spec.symbol_name, "            ");
            try writer.writeAll("        },\n");
        }
        try writer.writeAll("        else => unreachable,\n    }\n}\n\n");
    }

    fn emitOccurrenceRecoveryScope(self: *Generator, writer: *std.Io.Writer, rule: Rule, child_index: usize) !void {
        const rule_index = self.ruleIndex(rule);
        const variable = rule.rhs.items[child_index];
        const target_id = (self.plan.recovery.scopes.findOccurrence(rule_index, child_index) orelse unreachable).id;
        try writer.print("&ExplicitRecoveryScope{{ .id = {d}, .target = .{{ .occurrence = .{{ .parent_variable = ", .{target_id});
        try emitStringLiteral(writer, self.symbols.items[rule.header].id);
        try writer.print(", .rhs_index = {s}, .symbol_index = {d}, .variable = ", .{ rule.rhs_index, child_index });
        try emitStringLiteral(writer, self.symbols.items[variable].id);
        try writer.writeAll(" } }, .points = ");
        try emitter_common.emitRecoveryPoints(writer, rule.rhs_annotations.items[child_index].recovery_points.items);
        try writer.writeAll(" }");
    }

    fn emitParserFunctions(self: *Generator, writer: *std.Io.Writer) !void {
        for (self.plan.emitted_symbols) |symbol_index| {
            const symbol = self.symbols.items[symbol_index];
            if (symbol.kind == .variable) {
                try self.emitVariableParser(writer, symbol_index, false);
            } else {
                try self.emitTerminalParser(writer, symbol_index, false);
            }
            try writer.writeByte('\n');
        }
    }

    fn emitAstSuppressedParsers(self: *Generator, writer: *std.Io.Writer) !void {
        for (self.plan.ast_suppressed_order) |symbol_index| {
            try writer.writeByte('\n');
            const symbol = self.symbols.items[symbol_index];
            if (symbol.kind == .variable) {
                if (!self.hasParseEntries(symbol_index)) continue;
                try self.emitVariableParser(writer, symbol_index, true);
            } else {
                try self.emitTerminalParser(writer, symbol_index, true);
            }
        }
        if (self.plan.ast_suppressed_order.len > 0) try writer.writeByte('\n');
    }

    fn parserName(self: *Generator, symbol_index: usize) ![]const u8 {
        return self.plan.parser_names[symbol_index];
    }

    fn emitVariableParser(self: *Generator, writer: *std.Io.Writer, variable: usize, skip_ast_construction: bool) !void {
        try self.emitSelfRepeatingParsers(writer, variable, skip_ast_construction);
        const name = try self.parserName(variable);
        try writer.print("// {s}Parser for Symbol \"", .{if (skip_ast_construction) "AST-Suppressed " else ""});
        try std.zig.stringEscape(self.symbols.items[variable].id, writer);
        try writer.print("\" with index {d}\n", .{variable});
        try writer.print("fn parse_{s}{s}(context: *data_structures.Context", .{ name, if (skip_ast_construction) "_" else "" });
        if (self.has_occurrence_procedures) {
            try writer.writeAll(", occurrence_procedures: ?*const ProcedureSequenceNode");
        }
        if (self.uses_explicit_recovery) {
            try writer.writeAll(", occurrence_recovery: ?*const ExplicitRecoveryScope");
        }
        if (variable == self.plan.augmented_start) {
            try writer.writeAll(", root_reduction: *RootReduction");
        }
        try writer.print(") anyerror!nodeReturnType({d}, {s}) {{\n", .{ variable, if (skip_ast_construction) "true" else "false" });
        try emitter_common.emitModeGatedBody(Generator, self, writer, VariableParserBody, .{ .variable = variable, .skip_ast_construction = skip_ast_construction }, self.has_occurrence_procedures, renderVariableParserBody);
        try writer.writeAll("}\n");
    }

    const VariableParserBody = struct {
        variable: usize,
        skip_ast_construction: bool,
    };

    fn renderVariableParserBody(self: *Generator, writer: *std.Io.Writer, params: VariableParserBody) !void {
        const variable = params.variable;
        const skip_ast_construction = params.skip_ast_construction;
        const returns_node = self.symbolReturnsNode(variable, skip_ast_construction);
        if (variable == self.plan.augmented_start) {
            try writer.writeAll("    root_reduction.* = .{};\n");
        }
        if (returns_node) {
            const variable_index = self.variableIndex(variable);
            if (self.options.with_ast) {
                const is_var = self.options.with_procedures and !skip_ast_construction;
                try writer.print("    {s} node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), {d});\n\n", .{ if (is_var) "var" else "const", variable_index });
            } else {
                try writer.print("    var node = data_structures.Node{{ .text_start = context.currentTokenSourceOffset(), .variable = {d}, .payload = .{{}} }};\n\n", .{variable_index});
            }
        }
        if (variable != self.plan.augmented_start) {
            try writer.writeAll("    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable(");
            try emitStringLiteral(writer, self.symbols.items[variable].id);
            try writer.writeAll(") else false;\n    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();\n");
        }

        const decision = self.plan.parserDecision(variable, skip_ast_construction);
        if (decision.tree.entries.len == 0) {
            const spec = self.plan.syntax_error_handlers.items[decision.tree.diagnostic.?];
            try writer.writeAll("    switch (context.head(u8, 0)) {\n");
            try writer.writeAll("        else => {\n");
            try writer.writeAll("            @branchHint(.unlikely);\n");
            try self.emitSyntaxErrorCall(writer, spec, "            ");
            try writer.writeAll("        },\n");
            try writer.writeAll("    }\n");
        } else {
            try self.emitRuleSwitch(writer, variable, decision.tree, 0, "    ", skip_ast_construction, false);
            try writer.writeByte('\n');
        }
        if (returns_node) {
            try writer.writeAll(if (self.options.with_ast) "    return node_address;\n" else "    return node;\n");
        }
    }

    fn emitSelfRepeatingParsers(self: *Generator, writer: *std.Io.Writer, variable: usize, skip_ast_construction: bool) !void {
        for (self.rules.items, 0..) |rule, rule_index| {
            if (rule.header != variable) continue;
            for (rule.rhs.items, 0..) |symbol_index, child_index| {
                if (symbol_index != variable) continue;
                try self.emitSelfRepeatingParser(writer, variable, rule_index, child_index, skip_ast_construction);
                try writer.writeByte('\n');
            }
        }
    }

    fn symbolReturnsNode(self: *Generator, symbol_index: usize, skip_ast_construction: bool) bool {
        if (skip_ast_construction) return false;
        return common.symbolReturnsNode(self.symbols.items[symbol_index], self.options);
    }

    const BodyRecoveryMode = emitter_common.BodyRecoveryMode;

    fn bodyRecoveryMode(self: *const Generator) BodyRecoveryMode {
        if (!self.options.with_error_recovery) return .disabled;
        return if (self.uses_explicit_recovery) .explicit else .automatic;
    }

    fn ruleHasNodeChildren(self: *Generator, rule: Rule, skip_ast_construction: bool) bool {
        for (rule.rhs.items) |symbol_index| {
            const child_skips_ast_construction = (self.options.with_ast or self.options.with_procedures) and
                (skip_ast_construction or
                    (self.symbols.items[symbol_index].kind == .variable and !self.symbols.items[symbol_index].ast_enabled));
            if (self.symbolReturnsNode(symbol_index, child_skips_ast_construction)) return true;
        }
        return false;
    }

    /// Emits the neutral node result for the CURRENT configuration: typed by
    /// the runtime façade, so no-AST builds get `null` and AST builds get
    /// the pointer sentinel without any combo-dependent typing.
    fn missingNode(self: *Generator) []const u8 {
        _ = self;
        return "data_structures.invalid_variable_node";
    }

    fn hasParseEntries(self: *Generator, variable: usize) bool {
        return self.plan.has_parse_entries[variable];
    }

    fn emitSelfRepeatingParser(self: *Generator, writer: *std.Io.Writer, variable: usize, rule_index: usize, self_index: usize, skip_ast_construction: bool) !void {
        const rule = self.rules.items[rule_index];
        const name = try self.parserName(variable);
        try writer.print("// {s}Self-Repeating Parser for Symbol \"", .{if (skip_ast_construction) "AST-Suppressed " else ""});
        try self.emitSymbolRepr(writer, variable);
        try writer.print("\" at index {d} of its right hand side\n// Right hand side: -> ", .{self_index});
        try emitter_common.emitRuleSymbolsForDebug(writer, self.symbols.items, rule);
        try writer.print("\nfn parse_{s}_{s}_{d}{s}(context: *data_structures.Context", .{
            name,
            rule.rhs_index,
            self_index,
            if (skip_ast_construction) "_" else "",
        });
        if (self.has_occurrence_procedures) {
            try writer.writeAll(", occurrence_procedures: ?*const ProcedureSequenceNode");
        }
        if (self.uses_explicit_recovery) {
            try writer.writeAll(", occurrence_recovery: ?*const ExplicitRecoveryScope");
        }
        try writer.print(") anyerror!nodeReturnType({d}, {s}) {{\n", .{ variable, if (skip_ast_construction) "true" else "false" });
        try emitter_common.emitModeGatedBody(Generator, self, writer, SelfRepeatingParserBody, .{
            .variable = variable,
            .rule_index = rule_index,
            .self_index = self_index,
            .skip_ast_construction = skip_ast_construction,
        }, self.has_occurrence_procedures, renderSelfRepeatingParserBody);
        try writer.writeAll("}\n");
    }

    const SelfRepeatingParserBody = struct {
        variable: usize,
        rule_index: usize,
        self_index: usize,
        skip_ast_construction: bool,
    };

    fn renderSelfRepeatingParserBody(self: *Generator, writer: *std.Io.Writer, params: SelfRepeatingParserBody) !void {
        const variable = params.variable;
        const rule_index = params.rule_index;
        const self_index = params.self_index;
        const skip_ast_construction = params.skip_ast_construction;
        const rule = self.rules.items[rule_index];
        const name = try self.parserName(variable);
        const returns_node = self.symbolReturnsNode(variable, skip_ast_construction);

        if (returns_node and !self.options.with_ast) {
            try writer.print(
                \\    const SemanticReductionFrame = struct {{
                \\        node: data_structures.Node,
                \\        children: [{d}]?data_structures.Node,
                \\    }};
                \\    const semantic_allocator = context.runtime().arena_allocator;
                \\    var frames: std.ArrayList(*SemanticReductionFrame) = .empty;
                \\    defer frames.deinit(semantic_allocator);
                \\
            , .{rule.rhs.items.len});
            if (self.has_occurrence_procedures) {
                try writer.writeAll("    const recursive_occurrence_procedures = ");
                try emitter_common.emitProcedureSequenceExpression(writer, rule.rhs_annotations.items[self_index].procedures.items);
                try writer.writeAll(";\n");
            }

            try writer.writeAll("\n    while (true) {\n");
            try self.emitSelfRepeatingSwitch(writer, self.plan.selfRepeatingDecision(variable, rule_index, self_index, skip_ast_construction).tree, 0, "        ", .{
                .rule = rule,
                .variable = variable,
                .self_index = self_index,
                .skip_ast_construction = skip_ast_construction,
                .returns_node = returns_node,
                .frames_mode = true,
            });
            try writer.writeByte('\n');
            try writer.writeAll("    }\n");

            const explicit_recovery = self.uses_explicit_recovery;
            try writer.print("    var reduced_node = {s}parse_{s}(context", .{ if (explicit_recovery) "" else "try ", name });
            if (self.has_occurrence_procedures) {
                try writer.writeAll(", if (frames.items.len == 0) occurrence_procedures else recursive_occurrence_procedures");
            }
            if (self.uses_explicit_recovery) try writer.writeAll(", occurrence_recovery");
            if (explicit_recovery) {
                try self.emitExplicitRuleCatch(writer, rule, variable, skip_ast_construction, "");
            } else {
                try writer.writeByte(')');
            }
            try writer.writeAll(";\n    var frame_index = frames.items.len;\n    while (frame_index > 0) {\n        frame_index -= 1;\n        const frame = frames.items[frame_index];\n        if (reduced_node) |value| {\n");
            try writer.print("            frame.children[{d}] = value;\n", .{self_index});
            try writer.print("            frame.node.appendTemporaryChild(&frame.children[{d}].?);\n", .{self_index});
            try writer.writeAll("        }\n");
            // Structural: whether children are called via their suppressed
            // variants follows the enclosing variant's suppression and the
            // parent variable's own AST fact — never the rendered combo
            // (combo-driven node building is decided inside each child line).
            const skip_ast_for_children = skip_ast_construction or !self.symbols.items[variable].ast_enabled;
            for (rule.rhs.items[self_index + 1 ..], self_index + 1..) |symbol_index, child_index| {
                try self.emitChildParseLine(writer, symbol_index, variable, rule, child_index, "frame.node", "frame.children", "        ", skip_ast_for_children);
            }
            try writer.writeAll("        frame.node.text_length = context.currentTokenSourceOffset() - frame.node.text_start;\n");
            try emitter_common.emitDebugReduction(writer, self.symbols.items, rule, "        ");
            try self.emitProcedureBlock(
                writer,
                rule_index,
                variable,
                "frame.node",
                if (self.has_occurrence_procedures) "if (frame_index == 0) occurrence_procedures else recursive_occurrence_procedures" else "null",
                "        ",
                false,
            );
            try writer.writeAll("        frame.node.clearTemporaryChildren();\n        reduced_node = frame.node;\n    }\n    return reduced_node;\n");
            return;
        }

        if (returns_node) {
            try writer.writeAll(
                \\    var node_address = data_structures.Node.invalid_pointer;
                \\    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
                \\    _ = &node_address;
                \\    var repeating_node_address = node_address;
                \\    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
                \\
            );
        } else if (rule.rhs.items.len > self_index + 1) {
            try writer.writeAll(
                \\    var counter: usize = 0;
                \\    counter = counter; // dummy store for 0-repetition paths
                \\
            );
        }

        try writer.writeAll("\n    while (true) {\n");
        try self.emitSelfRepeatingSwitch(writer, self.plan.selfRepeatingDecision(variable, rule_index, self_index, skip_ast_construction).tree, 0, "        ", .{
            .rule = rule,
            .variable = variable,
            .self_index = self_index,
            .skip_ast_construction = skip_ast_construction,
            .returns_node = returns_node,
            .frames_mode = false,
        });
        try writer.writeByte('\n');
        try writer.writeAll("    }\n");

        if (returns_node) {
            const explicit_recovery = self.uses_explicit_recovery;
            try writer.print("    const exit_node = {s}parse_{s}(context", .{ if (explicit_recovery) "" else "try ", name });
            if (self.has_occurrence_procedures) {
                try writer.writeAll(", if (node_address == data_structures.Node.invalid_pointer) occurrence_procedures else ");
                try emitter_common.emitProcedureSequenceExpression(writer, rule.rhs_annotations.items[self_index].procedures.items);
            }
            if (self.uses_explicit_recovery) {
                try writer.writeAll(", occurrence_recovery");
            }
            if (explicit_recovery) {
                try self.emitExplicitRuleCatch(writer, rule, variable, skip_ast_construction, "");
            } else {
                try writer.writeByte(')');
            }
            try writer.print(
                \\;
                \\    if (exit_node != data_structures.Node.invalid_pointer) {{
                \\        if (node_address == data_structures.Node.invalid_pointer) {{
                \\            node_address = exit_node;
                \\        }} else {{
                \\            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child {d} (chain if replaceWithChildren)
                \\        }}
                \\    }}
                \\    while (repeating_node_address != data_structures.Node.invalid_pointer) {{
            , .{self_index});
            try writer.writeByte('\n');
            const skip_ast_for_children = skip_ast_construction or !self.symbols.items[variable].ast_enabled;
            for (rule.rhs.items[self_index + 1 ..], self_index + 1..) |symbol_index, child_index| {
                try self.emitChildParseLine(writer, symbol_index, variable, rule, child_index, "node", "repeating_node_address", "        ", skip_ast_for_children);
            }
            try writer.writeByte('\n');
            try emitter_common.emitDebugReduction(writer, self.symbols.items, rule, "        ");
            if (self.options.with_ast) {
                try writer.writeAll("        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;\n");
            }
            if (self.options.with_procedures and self.options.with_ast) {
                try writer.writeByte('\n');
                if (self.has_occurrence_procedures) {
                    try writer.writeAll("        const reduction_occurrence_procedures = if (context.node_allocator.at(repeating_node_address).parent == data_structures.Node.invalid_pointer) occurrence_procedures else ");
                    try emitter_common.emitProcedureSequenceExpression(writer, rule.rhs_annotations.items[self_index].procedures.items);
                    try writer.writeAll(";\n");
                }
                try self.emitProcedureBlock(
                    writer,
                    rule_index,
                    variable,
                    "repeating_node_address",
                    if (self.has_occurrence_procedures) "reduction_occurrence_procedures" else "null",
                    "        ",
                    true,
                );
                try writer.writeByte('\n');
                try writer.writeAll(
                    \\        if (args.node_address) |effective| {
                    \\            if (node_address == repeating_node_address) {
                    \\                node_address = effective;
                    \\            }
                    \\        } else {
                    \\            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
                    \\            if (node_address == repeating_node_address) {
                    \\                node_address = data_structures.Node.invalid_pointer;
                    \\            }
                    \\        }
                    \\
                );
            }
            try writer.writeAll("        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;\n");
            try writer.writeAll(
                \\    }
                \\    return node_address;
                \\
            );
        } else {
            const explicit_recovery = self.uses_explicit_recovery;
            try writer.print("    {s}parse_{s}{s}(context", .{ if (explicit_recovery) "" else "try ", name, if (skip_ast_construction) "_" else "" });
            if (self.has_occurrence_procedures) try writer.writeAll(", null");
            if (self.uses_explicit_recovery) try writer.writeAll(", occurrence_recovery");
            if (explicit_recovery) {
                try self.emitExplicitRuleCatch(writer, rule, variable, skip_ast_construction, "");
            } else {
                try writer.writeByte(')');
            }
            try writer.writeAll(";\n");
            if (rule.rhs.items.len > self_index + 1) {
                try writer.writeAll("    for (0..counter) |_| {\n");
                const skip_ast_for_children = skip_ast_construction or !self.symbols.items[variable].ast_enabled;
                for (rule.rhs.items[self_index + 1 ..], self_index + 1..) |symbol_index, child_index| {
                    try self.emitChildParseLine(writer, symbol_index, variable, rule, child_index, null, null, "        ", skip_ast_for_children);
                }
                try writer.writeAll("    }\n");
            }
        }
    }

    const SelfRepeatingLeafParams = struct {
        rule: Rule,
        variable: usize,
        self_index: usize,
        skip_ast_construction: bool,
        returns_node: bool,
        frames_mode: bool,
    };

    fn emitSelfRepeatingSwitch(self: *Generator, writer: *std.Io.Writer, node: *const switch_planning.Node, prefix_length: usize, indent: []const u8, params: SelfRepeatingLeafParams) !void {
        if (node.groups.items.len == 0) {
            if (node.fallback != null) {
                try self.emitSelfRepeatingLeafBody(writer, try indented(self.allocator, indent, 8), params);
            } else {
                try writer.print("{s}break;\n", .{indent});
            }
            return;
        }
        const step_length = node.step_length;
        try writer.print("{s}switch (context.head(u{d}, {d})) {{\n", .{ indent, step_length * 8, prefix_length });
        for (node.groups.items) |group| {
            try writer.print("{s}    ", .{indent});
            for (group.heads.items, 0..) |head, i| {
                if (i != 0) try writer.writeAll(", ");
                try writer.print("{d}", .{bytesToInt(head)});
            }
            try writer.writeAll(" => { // ");
            for (group.heads.items, 0..) |head, i| {
                if (i != 0) try writer.writeAll(", ");
                try writer.writeByte('\'');
                try emitEscapedForComment(writer, head);
                try writer.writeByte('\'');
            }
            try writer.writeByte('\n');
            if (group.child.isLeaf()) {
                try self.emitSelfRepeatingLeafBody(writer, try indented(self.allocator, indent, 8), params);
            } else {
                var child_indent = std.ArrayList(u8).empty;
                try child_indent.appendSlice(self.allocator, indent);
                try child_indent.appendSlice(self.allocator, "        ");
                try self.emitSelfRepeatingSwitch(writer, group.child, prefix_length + step_length, child_indent.items, params);
                try writer.writeByte('\n');
            }
            try writer.print("{s}    }},\n", .{indent});
        }
        if (node.fallback != null) {
            try writer.print("{s}    else => {{ // ''\n", .{indent});
            try self.emitSelfRepeatingLeafBody(writer, try indented(self.allocator, indent, 8), params);
            try writer.print("{s}    }},\n", .{indent});
        } else {
            try writer.print("{s}    else => break,\n", .{indent});
        }
        try writer.print("{s}}}", .{indent});
    }

    fn emitSelfRepeatingLeafBody(self: *Generator, writer: *std.Io.Writer, indent: []const u8, params: SelfRepeatingLeafParams) !void {
        try self.emitDebugRuleExpansion(writer, params.rule, params.variable, indent);
        if (params.frames_mode) {
            try writer.print(
                \\{s}const frame = try semantic_allocator.create(SemanticReductionFrame);
                \\{s}frame.* = .{{
                \\{s}    .node = .{{ .text_start = context.currentTokenSourceOffset(), .variable = {d}, .payload = .{{}} }},
                \\{s}    .children = .{{null}} ** {d},
                \\{s}}};
                \\{s}try frames.append(semantic_allocator, frame);
                \\
            , .{ indent, indent, indent, self.variableIndex(params.variable), indent, params.rule.rhs.items.len, indent, indent });
            const skip_ast_for_children = params.skip_ast_construction or !self.symbols.items[params.variable].ast_enabled;
            for (params.rule.rhs.items[0..params.self_index], 0..) |symbol_index, child_index| {
                try self.emitChildParseLine(writer, symbol_index, params.variable, params.rule, child_index, "frame.node", "frame.children", indent, skip_ast_for_children);
            }
        } else {
            if (params.returns_node) {
                try writer.print(
                    \\{s}const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), {d});
                    \\{s}if (node_address == data_structures.Node.invalid_pointer) {{
                    \\{s}    node_address = temporary_address;
                    \\{s}}} else {{
                    \\{s}    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child {d}
                    \\{s}}}
                    \\{s}repeating_node_address = temporary_address;
                    \\
                , .{ indent, self.variableIndex(params.variable), indent, indent, indent, indent, params.self_index, indent, indent });
            }
            const skip_ast_for_children = params.skip_ast_construction or !self.symbols.items[params.variable].ast_enabled;
            for (params.rule.rhs.items[0..params.self_index], 0..) |symbol_index, child_index| {
                try self.emitChildParseLine(writer, symbol_index, params.variable, params.rule, child_index, if (params.returns_node) "node" else null, if (params.returns_node) "repeating_node_address" else null, indent, skip_ast_for_children);
            }
            if (!params.returns_node and params.rule.rhs.items.len > params.self_index + 1) {
                try writer.print("{s}counter += 1;\n", .{indent});
            }
        }
    }

    fn emitTerminalParser(self: *Generator, writer: *std.Io.Writer, terminal_index: usize, skip_ast_construction: bool) !void {
        const name = try self.parserName(terminal_index);
        try writer.print("// {s}Parser for Symbol \"", .{if (skip_ast_construction) "AST-Suppressed " else ""});
        try self.emitSymbolRepr(writer, terminal_index);
        try writer.print("\" with index {d}\n", .{terminal_index});
        try writer.print("inline fn parse_{s}{s}(context: *data_structures.Context", .{ name, if (skip_ast_construction) "_" else "" });
        if (self.has_occurrence_procedures) {
            try writer.writeAll(", occurrence_procedures: ?*const ProcedureSequenceNode");
        }
        if (self.uses_explicit_recovery) {
            try writer.writeAll(", occurrence_recovery: ?*const ExplicitRecoveryScope");
        }
        try writer.print(") anyerror!nodeReturnType({d}, {s}) {{\n", .{ terminal_index, if (skip_ast_construction) "true" else "false" });
        try emitter_common.emitModeGatedBody(Generator, self, writer, TerminalParserBody, .{
            .terminal_index = terminal_index,
            .skip_ast_construction = skip_ast_construction,
        }, self.has_occurrence_procedures, renderTerminalParserBody);
        try writer.writeAll("}\n");
    }

    const TerminalParserBody = struct {
        terminal_index: usize,
        skip_ast_construction: bool,
    };

    fn renderTerminalParserBody(self: *Generator, writer: *std.Io.Writer, params: TerminalParserBody) !void {
        const terminal_index = params.terminal_index;
        const skip_ast_construction = params.skip_ast_construction;
        const returns_node = self.symbolReturnsNode(terminal_index, skip_ast_construction);
        if (returns_node) {
            if (self.options.with_ast) {
                try writer.print("    {s} node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), data_structures.Node.invalid_variable);\n\n", .{
                    if (self.options.with_procedures) "var" else "const",
                });
            } else {
                try writer.writeAll("    var node = data_structures.Node{ .text_start = context.currentTokenSourceOffset(), .payload = .{} };\n\n");
            }
        }

        const decision = self.plan.parserDecision(terminal_index, skip_ast_construction);
        try self.emitRuleSwitch(writer, terminal_index, decision.tree, 0, "    ", skip_ast_construction, false);
        try writer.writeByte('\n');
        if (returns_node) {
            if (self.options.with_ast) {
                try writer.writeAll("    context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;\n");
            } else {
                try writer.writeAll("    node.text_length = context.currentTokenSourceOffset() - node.text_start;\n");
            }
            if (self.options.with_procedures) {
                try self.emitTerminalProcedureBlock(
                    writer,
                    terminal_index,
                    if (self.options.with_ast) "node_address" else "node",
                    if (self.has_occurrence_procedures) "occurrence_procedures" else "null",
                    "    ",
                );
                if (self.options.with_ast) try writer.writeAll("    node_address = args.node_address orelse data_structures.Node.invalid_pointer;\n\n");
            }
            try writer.writeAll(if (self.options.with_ast) "    return node_address;\n" else "    return node;\n");
        }
    }

    fn emitRecoveryCandidates(self: *Generator, writer: *std.Io.Writer, candidates: []const []const u8) !void {
        _ = self;
        try writer.writeAll("&[_][]const u8{");
        for (candidates, 0..) |candidate, index| {
            if (index != 0) try writer.writeAll(", ");
            try emitStringLiteral(writer, candidate);
        }
        try writer.writeAll("}");
    }

    fn emitRuleSwitch(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, node: *const switch_planning.Node, prefix_length: usize, indent: []const u8, skip_ast_construction: bool, is_self_repeating: bool) !void {
        if (node.groups.items.len == 0) {
            if (node.fallback) |rule_index| {
                try self.emitSwitchLeaf(writer, symbol_index, rule_index, node.fallback_length orelse prefix_length, indent, skip_ast_construction);
                return;
            }
        }

        const step_length = node.step_length;
        try writer.print("{s}switch (context.head(u{d}, {d})) {{\n", .{ indent, step_length * 8, prefix_length });
        for (node.groups.items) |group| {
            try writer.print("{s}    ", .{indent});
            for (group.heads.items, 0..) |head, i| {
                if (i != 0) try writer.writeAll(", ");
                try writer.print("{d}", .{bytesToInt(head)});
            }
            try writer.writeAll(" => { // ");
            for (group.heads.items, 0..) |head, i| {
                if (i != 0) try writer.writeAll(", ");
                try writer.writeByte('\'');
                try emitEscapedForComment(writer, head);
                try writer.writeByte('\'');
            }
            try writer.writeByte('\n');

            if (group.child.isLeaf()) {
                try self.emitSwitchLeaf(writer, symbol_index, group.child.fallback.?, group.child.fallback_length orelse prefix_length + step_length, indent, skip_ast_construction);
            } else {
                var child_indent = std.ArrayList(u8).empty;
                try child_indent.appendSlice(self.allocator, indent);
                try child_indent.appendSlice(self.allocator, "        ");
                try self.emitRuleSwitch(writer, symbol_index, group.child, prefix_length + step_length, child_indent.items, skip_ast_construction, is_self_repeating);
                try writer.writeByte('\n');
            }
            try writer.print("{s}    }},\n", .{indent});
        }
        try self.emitSwitchElse(writer, symbol_index, node, prefix_length, indent, skip_ast_construction, is_self_repeating);
        try writer.print("{s}}}", .{indent});
    }

    fn emitSwitchLeaf(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, rule_index: usize, length: usize, indent: []const u8, skip_ast_construction: bool) !void {
        const symbol = self.symbols.items[symbol_index];
        if (symbol.kind == .variable) {
            try self.emitRuleBody(writer, rule_index, symbol_index, try indented(self.allocator, indent, 8), skip_ast_construction);
        } else {
            try writer.print("{s}        context.releaseToken({d});\n", .{ indent, length });
        }
    }

    fn emitSwitchElse(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, node: *const switch_planning.Node, prefix_length: usize, indent: []const u8, skip_ast_construction: bool, is_self_repeating: bool) !void {
        if (node.fallback) |rule_index| {
            try writer.print("{s}    else => {{ // ''\n", .{indent});
            try self.emitSwitchLeaf(writer, symbol_index, rule_index, node.fallback_length orelse prefix_length, indent, skip_ast_construction);
            try writer.print("{s}    }},\n", .{indent});
            return;
        }
        if (is_self_repeating) {
            try writer.print("{s}    else => break,\n", .{indent});
            return;
        }
        const spec = self.plan.syntax_error_handlers.items[node.diagnostic.?];
        try writer.print("{s}    else => {{\n", .{indent});
        try writer.print("{s}        @branchHint(.unlikely);\n", .{indent});
        try self.emitSyntaxErrorCall(writer, spec, try indented(self.allocator, indent, 8));
        try writer.print("{s}    }},\n", .{indent});
    }

    fn emitSyntaxErrorCall(
        self: *Generator,
        writer: *std.Io.Writer,
        spec: SyntaxErrorHandlerSpec,
        indent: []const u8,
    ) !void {
        if (self.uses_explicit_recovery) {
            try writer.print("{s}return {s}(context, occurrence_recovery);\n", .{ indent, spec.name });
            return;
        }
        if (!self.options.with_error_recovery) {
            try writer.print("{s}return {s}(context);\n", .{ indent, spec.name });
            return;
        }
        try self.emitSyntaxErrorHandlerReturn(writer, spec.symbol_index, spec.skip_ast_construction, spec.name, indent);
    }

    fn emitSyntaxErrorHandlerReturn(
        self: *Generator,
        writer: *std.Io.Writer,
        symbol_index: usize,
        skip_ast_construction: bool,
        handler_name: []const u8,
        indent: []const u8,
    ) !void {
        const can_tail_call = symbol_index != self.plan.augmented_start and
            self.symbols.items[symbol_index].kind != .end and
            !self.has_occurrence_procedures and (!self.options.with_ast or
            (self.symbols.items[symbol_index].kind == .variable and !self.symbolReturnsNode(symbol_index, skip_ast_construction)));
        if (can_tail_call) {
            try writer.print("{s}if (comptime !is_syntax_error_stack_enabled and (builtin.zig_backend == .stage2_llvm or builtin.zig_backend == .stage2_aarch64)) {{\n", .{indent});
            try writer.print("{s}    return @call(.always_tail, {s}, .{{context}});\n", .{ indent, handler_name });
            try writer.print("{s}}}\n", .{indent});
        }
        try writer.print("{s}return {s}(context);\n", .{ indent, handler_name });
    }

    const SyntaxErrorHandlerBody = struct {
        spec: SyntaxErrorHandlerSpec,
        site_index: usize,
    };

    fn emitSyntaxErrorHandlers(self: *Generator, writer: *std.Io.Writer) !void {
        // Support functions for every recovery style are emitted unconditionally
        // in emit(); which style a config selects is decided at comptime inside
        // each handler, and unused support folds away.
        for (self.plan.syntax_error_handlers.items, 0..) |spec, site_index| {
            try writer.print("\nnoinline fn {s}(context: *data_structures.Context", .{spec.name});
            if (self.uses_explicit_recovery) try writer.writeAll(", occurrence_recovery: ?*const ExplicitRecoveryScope");
            try writer.print(") linksection(if (builtin.os.tag == .macos) \"__TEXT,__unlikely\" else \".text.unlikely\") anyerror!nodeReturnType({d}, {s}) {{\n", .{ spec.symbol_index, if (spec.skip_ast_construction) "true" else "false" });
            try writer.writeAll("    @branchHint(.cold);\n");
            try emitter_common.emitModeGatedBody(Generator, self, writer, SyntaxErrorHandlerBody, .{ .spec = spec, .site_index = site_index }, false, renderSyntaxErrorHandlerBody);
            try writer.writeAll("}\n");
            try self.emitFailFastSyntaxErrorMessageRenderer(writer, spec);
        }
    }

    fn renderSyntaxErrorHandlerBody(self: *Generator, writer: *std.Io.Writer, params: SyntaxErrorHandlerBody) !void {
        const spec = params.spec;
        const site_index = params.site_index;
        const symbol = self.symbols.items[spec.symbol_index];
        const returns_node = self.symbolReturnsNode(spec.symbol_index, spec.skip_ast_construction);
        // Recovery styles that this grammar can never select (explicit
        // annotations vs automatic) are comptime-unreachable; emit a stub so
        // the gate chain stays exhaustive without touching mode-specific
        // tables that do not exist for this grammar.
        switch (self.bodyRecoveryMode()) {
            .automatic => if (self.uses_explicit_recovery) {
                try writer.writeAll("    unreachable;\n");
                return;
            },
            .explicit => if (!self.uses_explicit_recovery) {
                try writer.writeAll("    unreachable;\n");
                return;
            },
            .disabled => {},
        }
        if (!self.options.with_error_recovery) {
            try writer.writeAll("    return llFailFastSyntaxError(context, .{ .while_parsing = &[_][]const u8{");
            try emitStringLiteral(writer, symbol.id);
            try writer.writeAll("} }, ");
            try self.emitRecoveryCandidates(writer, spec.expected_tokens);
            try writer.print(", {s}_message);\n", .{spec.name});
            return;
        }
        if (self.uses_explicit_recovery) {
            try writer.writeAll("    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{");
            try emitStringLiteral(writer, symbol.id);
            try writer.writeAll("} }, ");
            try self.emitRecoveryCandidates(writer, spec.expected_tokens);
            try writer.writeAll(");\n");
            try writer.print("    context.setPendingSyntaxErrorSite({d});\n", .{site_index});
            if (symbol.kind == .variable) {
                try writer.print("    if (try llTryRecoverySelection_{d}(context, occurrence_recovery)) {{\n", .{spec.symbol_index});
                if (returns_node) {
                    try writer.print("        return {s};\n", .{self.missingNode()});
                } else {
                    try writer.writeAll("        return;\n");
                }
                try writer.writeAll("    }\n");
            } else {
                try writer.writeAll("    _ = occurrence_recovery;\n");
            }
            try writer.writeAll("    return error.ExplicitSyntaxRecovery;\n");
            return;
        }
        const candidates = self.plan.recovery.automatic_candidates.get(spec.symbol_index) orelse unreachable;
        try writer.writeAll("    const report_syntax_error = context.beginSyntaxRecovery();\n");
        try writer.writeAll("    if (report_syntax_error) {\n");
        try writer.writeAll("        try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{");
        try emitStringLiteral(writer, symbol.id);
        try writer.writeAll("} }, ");
        try self.emitRecoveryCandidates(writer, spec.expected_tokens);
        try writer.writeAll(");\n");
        try self.emitSyntaxErrorMessagePrint(writer, spec.exact_name, spec.symbol_name, "        ");
        try writer.writeAll("    }\n");
        try writer.writeAll("    if (report_syntax_error and context.syntaxErrorLimitReached()) return root.ParseError.SyntaxError;\n");
        try writer.writeAll("    if (try llRecoveryOffset(context, ");
        try self.emitRecoveryCandidates(writer, candidates);
        try writer.writeAll(", if (report_syntax_error) 1 else 0)) |recovery_offset| {\n");
        try writer.writeAll("        context.skipRecoveryInput(recovery_offset);\n");
        try writer.writeAll("    }\n");
        if (returns_node) {
            try writer.print("    return {s};\n", .{self.missingNode()});
        }
    }

    fn emitFailFastSyntaxErrorSupport(self: *Generator, writer: *std.Io.Writer) !void {
        _ = self;
        try writer.writeByte('\n');
        try emitter_common.emitFailFastSyntaxErrorSupport(writer, "ll", "LL", "syntax_error_ll");
    }

    fn emitFailFastSyntaxErrorMessageRenderer(
        self: *Generator,
        writer: *std.Io.Writer,
        spec: SyntaxErrorHandlerSpec,
    ) !void {
        _ = self;
        try writer.writeByte('\n');
        try emitter_common.emitFailFastMessageRenderer(writer, spec.name, &.{ spec.exact_name, spec.symbol_name }, "llFailFastDefaultMessage");
    }

    fn emitSyntaxErrorMessagePrint(self: *Generator, writer: *std.Io.Writer, exact_name: []const u8, symbol_name: []const u8, indent: []const u8) !void {
        _ = self;
        try writer.print("{s}const diagnostic = context.runtime().lastDiagnostic().?;\n", .{indent});
        try writer.print(
            "{s}const diagnostic_message = root.resolveSyntaxErrorMessage(context, diagnostic, config.error_messages, error_messages, .{{ \"{s}\", \"{s}\", \"syntax_error_ll\", \"syntax_error\" }}) orelse root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .plain) catch \"\";\n",
            .{ indent, exact_name, symbol_name },
        );
        try writer.print(
            "{s}context.runtime().last_rendered_message = diagnostic_message;\n{s}if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print(\"{{s}}\", .{{diagnostic_message}});\n",
            .{ indent, indent },
        );
    }

    fn emitRuleBody(self: *Generator, writer: *std.Io.Writer, rule_index: usize, parent_variable: usize, indent: []const u8, skip_ast_construction: bool) !void {
        const rule = self.rules.items[rule_index];
        const parent_returns_node = self.symbolReturnsNode(parent_variable, skip_ast_construction);
        const captures_root = if (parent_variable == self.plan.augmented_start) captures: {
            const start_symbol = rule.rhs.items[0];
            const start_skips_ast_construction = (self.options.with_ast or self.options.with_procedures) and
                (skip_ast_construction or !self.symbols.items[start_symbol].ast_enabled);
            break :captures self.symbolReturnsNode(start_symbol, start_skips_ast_construction);
        } else false;
        try self.emitDebugRuleExpansion(writer, rule, parent_variable, indent);

        if (rule.rhs.items.len != 0) {
            if (!self.options.with_ast and parent_returns_node and self.ruleHasNodeChildren(rule, skip_ast_construction)) {
                try writer.print("{s}var child_nodes: [{d}]?data_structures.Node = .{{null}} ** {d};\n", .{ indent, rule.rhs.items.len, rule.rhs.items.len });
            }
            if (captures_root) {
                try writer.print("{s}var root_node: root.data_structures.VariableResult = {s};\n", .{ indent, self.missingNode() });
            }
            for (rule.rhs.items, 0..) |symbol_index, child_index| {
                try self.emitChildParseLine(
                    writer,
                    symbol_index,
                    parent_variable,
                    rule,
                    child_index,
                    if (parent_returns_node) if (self.options.with_ast) "node_address" else "node" else null,
                    if (captures_root and child_index == 0)
                        "root_node"
                    else if (parent_returns_node)
                        if (self.options.with_ast) "node_address" else "child_nodes"
                    else
                        null,
                    indent,
                    skip_ast_construction,
                );
            }
        }

        if (captures_root) {
            if (self.options.with_ast) {
                try writer.print("{s}if (root_node != data_structures.Node.invalid_pointer) {{\n{s}    root_reduction.ast_root = root_node;\n", .{ indent, indent });
                if (self.options.with_procedures) {
                    try writer.print("{s}    root_reduction.semantic_root = context.node_allocator.at(root_node).payload;\n", .{indent});
                }
                try writer.print("{s}}}\n", .{indent});
            } else {
                try writer.print("{s}if (root_node) |node| root_reduction.semantic_root = node.payload;\n", .{indent});
            }
        }
        try self.emitRuleFinalize(writer, rule_index, parent_variable, indent, skip_ast_construction);
    }

    fn emitRuleFinalize(self: *Generator, writer: *std.Io.Writer, rule_index: usize, parent_variable: usize, indent: []const u8, skip_ast_construction: bool) !void {
        const rule = self.rules.items[rule_index];
        const parent_returns_node = self.symbolReturnsNode(parent_variable, skip_ast_construction);

        if (parent_returns_node) {
            if (self.options.with_ast) {
                try writer.print("{s}context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;\n", .{indent});
            } else {
                try writer.print("{s}node.text_length = context.currentTokenSourceOffset() - node.text_start;\n", .{indent});
            }
        }

        if (self.options.with_procedures and parent_returns_node) {
            try self.emitProcedureBlock(
                writer,
                rule_index,
                parent_variable,
                if (self.options.with_ast) "node_address" else "node",
                if (self.has_occurrence_procedures) "occurrence_procedures" else "null",
                indent,
                true,
            );
            if (self.options.with_ast) {
                try writer.print("{s}node_address = args.node_address orelse data_structures.Node.invalid_pointer;\n", .{indent});
            }
        }

        if (self.options.with_procedures and parent_returns_node) try writer.writeByte('\n');
        try emitter_common.emitDebugReduction(writer, self.symbols.items, rule, indent);
        if (!self.options.with_ast and parent_returns_node) {
            try writer.print("{s}node.clearTemporaryChildren();\n", .{indent});
        }
    }

    fn emitChildParseLine(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, parent_variable: usize, rule: Rule, child_index: usize, parent: ?[]const u8, parent_address: ?[]const u8, indent: []const u8, skip_ast_construction: bool) !void {
        const name = try self.parserName(symbol_index);
        const child = self.symbols.items[symbol_index];
        const explicit_recovery = self.uses_explicit_recovery;
        const verbatim = rule.rhs_annotations.items[child_index].verbatim;
        self.verbatim_literal = rule.rhs_annotations.items[child_index].verbatim_literal;
        self.verbatim_consume = rule.rhs_annotations.items[child_index].verbatim_consume;
        // Structural, configuration-independent suppression choice: which
        // callee variant (suppressed or not) matches this call site is a
        // grammar/callgraph fact — never a property of the combo rendered.
        const child_skips_ast_construction = skip_ast_construction or (child.kind == .variable and !child.ast_enabled);
        const child_returns_node = self.symbolReturnsNode(symbol_index, child_skips_ast_construction);
        const call_name = if (symbol_index == parent_variable)
            try std.fmt.allocPrint(self.allocator, "{s}_{s}_{d}", .{ name, rule.rhs_index, child_index })
        else
            name;
        if (verbatim) try self.emitVerbatimTerminatorStart(writer, symbol_index, indent);
        if (parent != null) {
            if (child_returns_node) {
                if (!self.options.with_ast) {
                    try writer.print("{s}{{\n{s}    {s} child_node = {s}parse_{s}(context", .{ indent, indent, if (verbatim) "var" else "const", if (explicit_recovery) "" else "try ", call_name });
                    try self.emitChildOccurrenceArgument(writer, rule, child_index, child_returns_node);
                    if (explicit_recovery) {
                        try self.emitExplicitRuleCatch(writer, rule, parent_variable, skip_ast_construction, indent);
                    } else {
                        try writer.writeByte(')');
                    }
                    try writer.print("; // child {d}\n", .{child_index});
                    if (verbatim) {
                        try self.emitVerbatimCapture(writer, symbol_index, indent);
                        try writer.print("{s}    if (child_node) |*verbatim_node| verbatim_node.text_length = context.currentTokenSourceOffset() - verbatim_node.text_start;\n", .{indent});
                    }
                    try writer.print(
                        \\{s}    if (child_node) |value| {{
                        \\{s}        {s}[{d}] = value;
                        \\{s}        {s}.appendTemporaryChild(&{s}[{d}].?);
                        \\{s}    }}
                        \\{s}}}
                        \\
                    , .{ indent, indent, parent_address.?, child_index, indent, parent.?, parent_address.?, child_index, indent, indent });
                    return;
                }
                try writer.print("{s}{{\n{s}    const child_node = {s}parse_{s}(context", .{ indent, indent, if (explicit_recovery) "" else "try ", call_name });
                try self.emitChildOccurrenceArgument(writer, rule, child_index, child_returns_node);
                if (explicit_recovery) {
                    try self.emitExplicitRuleCatch(writer, rule, parent_variable, skip_ast_construction, indent);
                } else {
                    try writer.writeByte(')');
                }
                try writer.print("; // child {d}\n", .{child_index});
                if (verbatim) {
                    try self.emitVerbatimCapture(writer, symbol_index, indent);
                    try writer.print(
                        \\{s}    if (child_node != data_structures.Node.invalid_pointer) {{
                        \\{s}        context.node_allocator.at(child_node).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(child_node).text_start;
                        \\{s}    }}
                        \\
                    , .{ indent, indent, indent });
                }
                try writer.print(
                    \\{s}    if (child_node != data_structures.Node.invalid_pointer) {{
                    \\{s}        context.node_allocator.at({s}).immediateAppendChildren({s}, child_node, context.node_allocator); // child {d} (chain if replaceWithChildren)
                    \\{s}    }}
                    \\{s}}}
                    \\
                , .{ indent, indent, parent_address.?, parent_address.?, child_index, indent, indent });
            } else {
                try writer.print("{s}_ = {s}parse_{s}{s}(context", .{ indent, if (explicit_recovery) "" else "try ", call_name, if (child_skips_ast_construction) "_" else "" });
                try self.emitChildOccurrenceArgument(writer, rule, child_index, false);
                if (explicit_recovery) {
                    try self.emitExplicitRuleCatch(writer, rule, parent_variable, skip_ast_construction, indent);
                } else {
                    try writer.writeByte(')');
                }
                try writer.print("; // child {d}\n", .{child_index});
                if (verbatim) try self.emitVerbatimCapture(writer, symbol_index, indent);
            }
        } else if (child_returns_node) {
            try writer.print("{s}{s} = {s}parse_{s}(context", .{ indent, parent_address orelse "_", if (explicit_recovery) "" else "try ", call_name });
            try self.emitChildOccurrenceArgument(writer, rule, child_index, true);
            if (explicit_recovery) {
                try self.emitExplicitRuleCatch(writer, rule, parent_variable, skip_ast_construction, indent);
            } else {
                try writer.writeByte(')');
            }
            try writer.print("; // child {d}\n", .{child_index});
            if (verbatim) {
                try self.emitVerbatimCapture(writer, symbol_index, indent);
                if (parent_address) |address| {
                    if (!std.mem.eql(u8, address, "_")) {
                        try writer.print("{s}if ({s}) |*verbatim_node| verbatim_node.text_length = context.currentTokenSourceOffset() - verbatim_node.text_start;\n", .{ indent, address });
                    }
                }
            }
        } else {
            try writer.print("{s}_ = {s}parse_{s}{s}(context", .{ indent, if (explicit_recovery) "" else "try ", call_name, if (child_skips_ast_construction) "_" else "" });
            try self.emitChildOccurrenceArgument(writer, rule, child_index, false);
            if (explicit_recovery) {
                try self.emitExplicitRuleCatch(writer, rule, parent_variable, skip_ast_construction, indent);
            } else {
                try writer.writeByte(')');
            }
            try writer.print("; // child {d}\n", .{child_index});
            if (verbatim) try self.emitVerbatimCapture(writer, symbol_index, indent);
        }
    }

    fn emitVerbatimTerminatorStart(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, indent: []const u8) !void {
        if (self.verbatim_literal != null or self.symbols.items[symbol_index].kind == .terminal) return;
        try writer.print("{s}const verbatim_start = context.currentTokenSourceOffset();\n", .{indent});
    }

    fn emitVerbatimCapture(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, indent: []const u8) !void {
        const child = self.symbols.items[symbol_index];
        if (self.verbatim_literal) |literal| {
            try writer.print("{s}try context.captureVerbatim(", .{indent});
            try common.emitStringLiteral(writer, literal);
            try writer.print(", {s});\n", .{if (self.verbatim_consume) "true" else "false"});
        } else if (child.kind == .terminal) {
            try writer.print("{s}try context.captureVerbatim(", .{indent});
            try common.emitStringLiteral(writer, child.id);
            try writer.writeAll(", true);\n");
        } else {
            try writer.print("{s}const verbatim_terminator = context.getTextSlice(verbatim_start, context.currentTokenSourceOffset() - verbatim_start);\n", .{indent});
            try writer.print("{s}try context.captureVerbatim(verbatim_terminator, true);\n", .{indent});
        }
    }

    fn emitExplicitRuleCatch(self: *Generator, writer: *std.Io.Writer, rule: Rule, parent_variable: usize, skip_ast_construction: bool, indent: []const u8) !void {
        const rule_index = self.ruleIndex(rule);
        try writer.writeAll(") catch |err| switch (err) {\n");
        try writer.print("{s}        error.ExplicitSyntaxRecovery => {{\n", .{indent});
        try writer.print("{s}            if (try llTryRecoveryRule_{d}(context, occurrence_recovery)) {{\n", .{ indent, rule_index });
        if (self.symbolReturnsNode(parent_variable, skip_ast_construction)) {
            try writer.print("{s}                return {s};\n", .{ indent, self.missingNode() });
        } else {
            try writer.print("{s}                return;\n", .{indent});
        }
        try writer.print("{s}            }}\n{s}            return err;\n{s}        }},\n", .{ indent, indent, indent });
        try writer.print("{s}        else => return err,\n{s}    }}", .{ indent, indent });
    }

    fn emitChildOccurrenceArgument(self: *Generator, writer: *std.Io.Writer, rule: Rule, child_index: usize, child_returns_node: bool) !void {
        if (self.has_occurrence_procedures) {
            try writer.writeAll(", ");
            if (child_returns_node) {
                try emitter_common.emitProcedureSequenceExpression(writer, rule.rhs_annotations.items[child_index].procedures.items);
            } else {
                try writer.writeAll("null");
            }
        }
        if (self.uses_explicit_recovery) {
            try writer.writeAll(", ");
            const symbol_index = rule.rhs.items[child_index];
            if (self.symbols.items[symbol_index].kind == .variable and
                rule.rhs_annotations.items[child_index].recovery_points.items.len != 0)
            {
                try self.emitOccurrenceRecoveryScope(writer, rule, child_index);
            } else {
                try writer.writeAll("null");
            }
        }
    }

    fn emitProcedureBlock(self: *Generator, writer: *std.Io.Writer, rule_index: usize, parent_variable: usize, node_expr: []const u8, occurrence_expr: []const u8, indent: []const u8, include_outcome: bool) !void {
        const variable_index = self.variableIndex(parent_variable);
        try emitter_common.emitProcedureArgsStruct(writer, indent, self.options.with_ast, rule_index, node_expr, true);
        if (self.has_occurrence_procedures) {
            try writer.print("{s}try runProcedureSequence({s}, &args);\n", .{ indent, occurrence_expr });
        }
        try emitter_common.emitProcedureRuleSequenceCall(writer, indent, self.rules.items[rule_index].annotations.procedures.items);
        try emitter_common.emitProcedureDispatchTail(writer, indent, rule_index, variable_index, parent_variable, null);
        if (include_outcome and self.options.with_ast) {
            try writer.print(
                \\
                \\{s}if (comptime builtin.mode == .Debug) {{
                \\{s}    if (context.verbosityLevel() > 2) {{
                \\{s}        std.debug.print("Procedure outcome for
            , .{ indent, indent, indent });
            try writer.writeAll(" ");
            try emitFormatToken(writer, self.symbols.items[parent_variable].id);
            try writer.print(
                \\: {{f}}\n", .{{
                \\{s}            string_utilities.fmtNode(args.node_address, context),
                \\{s}        }});
                \\{s}    }}
                \\{s}}}
                \\
            , .{ indent, indent, indent, indent });
        }
    }

    fn emitTerminalProcedureBlock(self: *Generator, writer: *std.Io.Writer, terminal_index: usize, node_expr: []const u8, occurrence_expr: []const u8, indent: []const u8) !void {
        if (self.options.with_ast) {
            try writer.print(
                \\{s}var args = data_structures.ProcedureArguments{{
                \\{s}    .context = context,
                \\{s}    .rule = null,
                \\{s}    .node_address = {s},
                \\{s}}};
            , .{ indent, indent, indent, indent, node_expr, indent });
        } else {
            try writer.print(
                \\{s}var args = data_structures.ProcedureArguments{{
                \\{s}    .context = context,
                \\{s}    .rule = null,
                \\{s}    ._temp_node = &{s},
                \\{s}}};
            , .{ indent, indent, indent, indent, node_expr, indent });
        }
        if (self.has_occurrence_procedures) {
            try writer.print("{s}try runProcedureSequence({s}, &args);\n", .{ indent, occurrence_expr });
        }
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
            indent, terminal_index, indent, indent, indent,
            indent, indent,         indent, indent,
        });
    }

    fn emitDebugRuleExpansion(self: *Generator, writer: *std.Io.Writer, rule: Rule, parent_variable: usize, indent: []const u8) !void {
        try writer.print(
            \\{s}if (comptime builtin.mode == .Debug) {{
            \\{s}    if (context.verbosityLevel() > 1) {{
            \\{s}        std.debug.print("Rule expansion:
        , .{ indent, indent, indent });
        try writer.writeAll(" ");
        try emitFormatToken(writer, self.symbols.items[parent_variable].id);
        try writer.writeAll(" -> ");
        try emitter_common.emitRuleSymbolsForDebug(writer, self.symbols.items, rule);
        try writer.print(
            \\\n", .{{}});
            \\{s}    }}
            \\{s}}}
            \\
        , .{ indent, indent });
    }

    fn emitSymbolRepr(self: *Generator, writer: *std.Io.Writer, symbol_index: usize) !void {
        try writer.writeAll(self.plan.symbol_reprs[symbol_index]);
    }

    fn variableIndex(self: *Generator, symbol_index: usize) usize {
        return self.plan.variable_indices[symbol_index] orelse unreachable;
    }

    fn ruleIndex(self: *Generator, needle: Rule) usize {
        for (self.rules.items, 0..) |rule, index| {
            if (rule.header == needle.header and std.mem.eql(u8, rule.rhs_index, needle.rhs_index)) return index;
        }
        unreachable;
    }

    fn longestTerminalLength(self: *Generator) usize {
        return self.plan.longest_terminal_length;
    }
};

pub fn emit(
    allocator: std.mem.Allocator,
    grammar: *const common.PreparedGrammar,
    plan: *const LLPlan,
    writer: *std.Io.Writer,
    options: Options,
) !void {
    var generator = Generator.init(allocator, options, grammar, plan);
    try generator.emit(writer);
}
