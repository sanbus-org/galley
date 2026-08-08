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

const Generator = struct {
    allocator: std.mem.Allocator,
    options: Options,
    symbols: std.ArrayList(Symbol),
    variables: std.ArrayList(usize),
    rules: std.ArrayList(Rule),
    plan: *const LLPlan,
    has_occurrence_procedures: bool,
    uses_explicit_recovery: bool,

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
            self.options,
            self.uses_explicit_recovery,
            self.longestTerminalLength(),
        );

        try emitter_common.emitGrammarTables(writer, self.symbols.items, self.variables.items, self.rules.items);
        try writer.writeAll(
            \\const RootReduction = struct {
            \\    ast_root: ?data_structures.Node.Pointer = null,
            \\    semantic_root: if (are_procedures_enabled) ?data_structures.Payload else void = if (are_procedures_enabled) null else {},
            \\};
            \\
        );
        if (self.options.with_error_recovery) {
            if (self.uses_explicit_recovery) {
                try self.emitExplicitRecoverySupport(writer);
            } else {
                try self.emitRecoverySupport(writer);
            }
        }
        if (self.options.with_procedures) try emitter_common.emitProcedureSupport(writer, self.rules.items, self.symbols.items, self.variables.items);
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
        if (self.options.with_error_recovery) {
            try writer.writeAll("    if (context.hasSyntaxErrors()) return root.ParseError.SyntaxError;\n");
        }
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
    }

    fn emitRecoverySupport(self: *Generator, writer: *std.Io.Writer) !void {
        _ = self;
        try emitter_common.emitRecoveryOffsetFunction(writer, "llRecoveryOffset");
    }

    fn emitExplicitRecoverySupport(self: *Generator, writer: *std.Io.Writer) !void {
        try writer.writeAll(
            \\const ExplicitRecoveryScope = struct {
            \\    id: usize,
            \\    target: root.SyntaxRecoveryTarget,
            \\    points: []const root.SyntaxRecoveryPoint,
            \\};
            \\
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
                try self.emitLhsRecoveryScope(writer, variable);
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
                try self.emitProductionRecoveryScope(writer, rule, rule_index);
                try writer.writeAll(")) return true;\n");
            }
            if (self.symbols.items[rule.header].annotations.recovery_points.items.len != 0) {
                try writer.writeAll("    if (try llTryExplicitScope(context, ");
                try self.emitLhsRecoveryScope(writer, rule.header);
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

    fn emitLhsRecoveryScope(self: *Generator, writer: *std.Io.Writer, variable: usize) !void {
        const scope = self.plan.recovery.scopes.findLhs(variable) orelse unreachable;
        try writer.print("&ExplicitRecoveryScope{{ .id = {d}, .target = .{{ .lhs_variable = ", .{scope.id});
        try emitStringLiteral(writer, self.symbols.items[variable].id);
        try writer.writeAll(" }, .points = ");
        try emitter_common.emitRecoveryPoints(writer, self.symbols.items[variable].annotations.recovery_points.items);
        try writer.writeAll(" }");
    }

    fn emitProductionRecoveryScope(self: *Generator, writer: *std.Io.Writer, rule: Rule, rule_index: usize) !void {
        const scope = self.plan.recovery.scopes.findProduction(rule_index) orelse unreachable;
        try writer.print("&ExplicitRecoveryScope{{ .id = {d}, .target = .{{ .production = .{{ .variable = ", .{scope.id});
        try emitStringLiteral(writer, self.symbols.items[rule.header].id);
        try writer.print(", .rhs_index = {s} }} }}, .points = ", .{rule.rhs_index});
        try emitter_common.emitRecoveryPoints(writer, rule.annotations.recovery_points.items);
        try writer.writeAll(" }");
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
        const returns_node = self.symbolReturnsNode(variable, skip_ast_construction);
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
        try writer.print(") anyerror!{s} {{\n", .{self.nodeReturnType(returns_node)});
        if (self.has_occurrence_procedures and !returns_node) {
            try writer.writeAll("    _ = occurrence_procedures;\n");
        }
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
        try writer.writeAll("}\n");
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
        return !skip_ast_construction and self.plan.symbol_returns_node[symbol_index];
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

    fn nodeReturnType(self: *Generator, returns_node: bool) []const u8 {
        if (!returns_node) return "void";
        return if (self.options.with_ast) "data_structures.Node.Pointer" else "?data_structures.Node";
    }

    fn missingNode(self: *Generator) []const u8 {
        return if (self.options.with_ast) "data_structures.Node.invalid_pointer" else "null";
    }

    fn hasParseEntries(self: *Generator, variable: usize) bool {
        return self.plan.has_parse_entries[variable];
    }

    fn emitSelfRepeatingParser(self: *Generator, writer: *std.Io.Writer, variable: usize, rule_index: usize, self_index: usize, skip_ast_construction: bool) !void {
        const rule = self.rules.items[rule_index];
        const name = try self.parserName(variable);
        const returns_node = self.symbolReturnsNode(variable, skip_ast_construction);
        try writer.print("// {s}Self-Repeating Parser for Symbol \"", .{if (skip_ast_construction) "AST-Suppressed " else ""});
        try self.emitSymbolRepr(writer, variable);
        try writer.print("\" at index {d} of its right hand side\n// Right hand side: -> ", .{self_index});
        try self.emitRuleSymbolsForDebug(writer, rule);
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
        try writer.print(") anyerror!{s} {{\n", .{self.nodeReturnType(returns_node)});
        if (self.has_occurrence_procedures and !returns_node) {
            try writer.writeAll("    _ = occurrence_procedures;\n");
        }

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

            const cases = self.plan.selfRepeatingDecision(variable, rule_index, self_index, skip_ast_construction).cases;
            try writer.writeAll("\n    while (true) {\n        switch (context.head(u8, 0)) {\n            ");
            for (cases, 0..) |byte, i| {
                if (i != 0) try writer.writeAll(", ");
                try writer.print("{d}", .{byte});
            }
            try writer.writeAll(" => { // ");
            for (cases, 0..) |byte, i| {
                if (i != 0) try writer.writeAll(", ");
                try writer.writeByte('\'');
                try emitEscapedForComment(writer, &.{byte});
                try writer.writeByte('\'');
            }
            try writer.writeByte('\n');
            try self.emitDebugRuleExpansion(writer, rule, variable, "                ");
            try writer.print(
                \\                const frame = try semantic_allocator.create(SemanticReductionFrame);
                \\                frame.* = .{{
                \\                    .node = .{{ .text_start = context.currentTokenSourceOffset(), .variable = {d}, .payload = .{{}} }},
                \\                    .children = .{{null}} ** {d},
                \\                }};
                \\                try frames.append(semantic_allocator, frame);
                \\
            , .{ self.variableIndex(variable), rule.rhs.items.len });
            const skip_ast_for_children = (self.options.with_ast or self.options.with_procedures) and (skip_ast_construction or !self.symbols.items[variable].ast_enabled);
            for (rule.rhs.items[0..self_index], 0..) |symbol_index, child_index| {
                try self.emitChildParseLine(writer, symbol_index, variable, rule, child_index, "frame.node", "frame.children", "                ", skip_ast_for_children);
            }
            try writer.writeAll("            },\n            else => break,\n        }\n    }\n");

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
            for (rule.rhs.items[self_index + 1 ..], self_index + 1..) |symbol_index, child_index| {
                try self.emitChildParseLine(writer, symbol_index, variable, rule, child_index, "frame.node", "frame.children", "        ", skip_ast_for_children);
            }
            try writer.writeAll("        frame.node.text_length = context.currentTokenSourceOffset() - frame.node.text_start;\n");
            try self.emitDebugReduction(writer, rule, variable, "        ");
            try self.emitProcedureBlock(
                writer,
                rule_index,
                variable,
                "frame.node",
                if (self.has_occurrence_procedures) "if (frame_index == 0) occurrence_procedures else recursive_occurrence_procedures" else "null",
                "        ",
                false,
            );
            try writer.writeAll("        frame.node.clearTemporaryChildren();\n        reduced_node = frame.node;\n    }\n    return reduced_node;\n}\n");
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

        const cases = self.plan.selfRepeatingDecision(variable, rule_index, self_index, skip_ast_construction).cases;

        try writer.writeAll("\n    while (true) {\n        switch (context.head(u8, 0)) {\n            ");
        for (cases, 0..) |byte, i| {
            if (i != 0) try writer.writeAll(", ");
            try writer.print("{d}", .{byte});
        }
        try writer.writeAll(" => { // ");
        for (cases, 0..) |byte, i| {
            if (i != 0) try writer.writeAll(", ");
            try writer.writeByte('\'');
            try emitEscapedForComment(writer, &.{byte});
            try writer.writeByte('\'');
        }
        try writer.writeByte('\n');
        try self.emitDebugRuleExpansion(writer, rule, variable, "                ");

        if (returns_node) {
            try writer.print(
                \\                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), {d});
                \\                if (node_address == data_structures.Node.invalid_pointer) {{
                \\                    node_address = temporary_address;
                \\                }} else {{
                \\                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child {d}
                \\                }}
                \\                repeating_node_address = temporary_address;
                \\
            , .{ self.variableIndex(variable), self_index });
        }

        const skip_ast_for_children = self.options.with_ast and (skip_ast_construction or !self.symbols.items[variable].ast_enabled);
        for (rule.rhs.items[0..self_index], 0..) |symbol_index, child_index| {
            try self.emitChildParseLine(writer, symbol_index, variable, rule, child_index, if (returns_node) "node" else null, if (returns_node) "repeating_node_address" else null, "                ", skip_ast_for_children);
        }
        if (!returns_node and rule.rhs.items.len > self_index + 1) {
            try writer.writeAll("                counter += 1;\n");
        }
        try writer.writeAll("            },\n            else => break,\n        }\n    }\n");

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
            for (rule.rhs.items[self_index + 1 ..], self_index + 1..) |symbol_index, child_index| {
                try self.emitChildParseLine(writer, symbol_index, variable, rule, child_index, "node", "repeating_node_address", "        ", skip_ast_for_children);
            }
            try writer.writeByte('\n');
            try self.emitDebugReduction(writer, rule, variable, "        ");
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
                for (rule.rhs.items[self_index + 1 ..], self_index + 1..) |symbol_index, child_index| {
                    try self.emitChildParseLine(writer, symbol_index, variable, rule, child_index, null, null, "        ", skip_ast_for_children);
                }
                try writer.writeAll("    }\n");
            }
        }

        try writer.writeAll("}\n");
    }

    fn emitTerminalParser(self: *Generator, writer: *std.Io.Writer, terminal_index: usize, skip_ast_construction: bool) !void {
        const name = try self.parserName(terminal_index);
        const returns_node = self.symbolReturnsNode(terminal_index, skip_ast_construction);
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
        try writer.print(") anyerror!{s} {{\n", .{self.nodeReturnType(returns_node)});
        if (self.has_occurrence_procedures and !returns_node) {
            try writer.writeAll("    _ = occurrence_procedures;\n");
        }
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

        try writer.writeAll("}\n");
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
                try self.emitSwitchLeaf(writer, symbol_index, rule_index, prefix_length, indent, skip_ast_construction);
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
                try self.emitSwitchLeaf(writer, symbol_index, group.child.fallback.?, prefix_length + step_length, indent, skip_ast_construction);
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
            try self.emitSwitchLeaf(writer, symbol_index, rule_index, prefix_length, indent, skip_ast_construction);
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
            try writer.print("{s}if (comptime builtin.zig_backend == .stage2_llvm or builtin.zig_backend == .stage2_aarch64) {{\n", .{indent});
            try writer.print("{s}    return @call(.always_tail, {s}, .{{context}});\n", .{ indent, handler_name });
            try writer.print("{s}}}\n", .{indent});
        }
        try writer.print("{s}return {s}(context);\n", .{ indent, handler_name });
    }

    fn emitSyntaxErrorHandlers(self: *Generator, writer: *std.Io.Writer) !void {
        if (!self.options.with_error_recovery) {
            try self.emitFailFastSyntaxErrorSupport(writer);
        }
        for (self.plan.syntax_error_handlers.items, 0..) |spec, site_index| {
            const symbol = self.symbols.items[spec.symbol_index];
            const returns_node = self.symbolReturnsNode(spec.symbol_index, spec.skip_ast_construction);

            try writer.print("\n{s}fn {s}(context: *data_structures.Context", .{
                if (!self.options.with_error_recovery) "noinline " else "",
                spec.name,
            });
            if (self.uses_explicit_recovery) try writer.writeAll(", occurrence_recovery: ?*const ExplicitRecoveryScope");
            try writer.print(") anyerror!{s} {{\n", .{
                self.nodeReturnType(returns_node),
            });
            try writer.writeAll("    @branchHint(.cold);\n");
            if (!self.options.with_error_recovery) {
                try writer.writeAll("    return llFailFastSyntaxError(context, .{ .while_parsing = ");
                try emitStringLiteral(writer, symbol.id);
                try writer.writeAll(" }, ");
                try self.emitRecoveryCandidates(writer, spec.expected_tokens);
                try writer.print(", {s}_message);\n}}\n", .{spec.name});
                try self.emitFailFastSyntaxErrorMessageRenderer(writer, spec);
                continue;
            }
            if (self.uses_explicit_recovery) {
                try writer.writeAll("    try context.recordSyntaxDiagnostic(.{ .while_parsing = ");
                try emitStringLiteral(writer, symbol.id);
                try writer.writeAll(" }, ");
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
                try writer.writeAll("    return error.ExplicitSyntaxRecovery;\n}\n");
                continue;
            }
            const candidates = self.plan.recovery.automatic_candidates.get(spec.symbol_index) orelse unreachable;
            try writer.writeAll("    const report_syntax_error = context.beginSyntaxRecovery();\n");
            try writer.writeAll("    if (report_syntax_error) {\n");
            try writer.writeAll("        try context.recordSyntaxDiagnostic(.{ .while_parsing = ");
            try emitStringLiteral(writer, symbol.id);
            try writer.writeAll(" }, ");
            try self.emitRecoveryCandidates(writer, spec.expected_tokens);
            try writer.writeAll(");\n");
            try writer.writeAll("        if (!builtin.is_test) {\n");
            try self.emitSyntaxErrorMessagePrint(writer, spec.exact_name, spec.symbol_name, "            ");
            try writer.writeAll("        }\n");
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
            try writer.writeAll("}\n");
        }
    }

    fn emitFailFastSyntaxErrorSupport(self: *Generator, writer: *std.Io.Writer) !void {
        _ = self;
        try writer.writeAll(
            \\
            \\const LLFailFastMessageRenderer = *const fn (root.SyntaxErrorMessageArgs) anyerror![]const u8;
            \\
            \\fn llFailFastSyntaxError(
            \\    context: *data_structures.Context,
            \\    diagnostic_context: root.SyntaxDiagnosticContext,
            \\    expected_tokens: []const []const u8,
            \\    render_message: LLFailFastMessageRenderer,
            \\) anyerror {
            \\    @branchHint(.cold);
            \\    context.recordSyntaxDiagnostic(diagnostic_context, expected_tokens) catch |err| return err;
            \\    if (!builtin.is_test) {
            \\        const diagnostic_message = render_message(.{
            \\            .allocator = context.runtime().arena_allocator,
            \\            .context = context,
            \\            .diagnostic = context.runtime().last_diagnostic.?,
            \\            .style = .ansi,
            \\        }) catch "";
            \\        std.debug.print("{s}", .{diagnostic_message});
            \\    }
            \\    return root.ParseError.SyntaxError;
            \\}
            \\
            \\fn llFailFastDefaultMessage(args: root.SyntaxErrorMessageArgs) anyerror![]const u8 {
            \\    if (comptime @hasDecl(error_messages, "syntax_error_ll"))
            \\        return error_messages.syntax_error_ll(args);
            \\    if (comptime @hasDecl(error_messages, "syntax_error"))
            \\        return error_messages.syntax_error(args);
            \\    return root.renderParseDiagnostic(args.allocator, args.diagnostic, args.style);
            \\}
            \\
        );
    }

    fn emitFailFastSyntaxErrorMessageRenderer(
        self: *Generator,
        writer: *std.Io.Writer,
        spec: SyntaxErrorHandlerSpec,
    ) !void {
        _ = self;
        try writer.print(
            \\
            \\fn {s}_message(args: root.SyntaxErrorMessageArgs) anyerror![]const u8 {{
            \\    if (comptime @hasDecl(error_messages, "{s}"))
            \\        return @field(error_messages, "{s}")(args);
            \\    if (comptime @hasDecl(error_messages, "{s}"))
            \\        return @field(error_messages, "{s}")(args);
            \\    return llFailFastDefaultMessage(args);
            \\}}
            \\
        , .{
            spec.name,
            spec.exact_name,
            spec.exact_name,
            spec.symbol_name,
            spec.symbol_name,
        });
    }

    fn emitSyntaxErrorMessagePrint(self: *Generator, writer: *std.Io.Writer, exact_name: []const u8, symbol_name: []const u8, indent: []const u8) !void {
        try writer.print("{s}const diagnostic = context.runtime().last_diagnostic.?;\n", .{indent});
        try writer.print("{s}const diagnostic_message = if (comptime @hasDecl(error_messages, \"{s}\"))\n", .{ indent, exact_name });
        try self.emitSyntaxErrorHookCall(writer, "", exact_name, indent);
        try writer.print("{s}else if (comptime @hasDecl(error_messages, \"{s}\"))\n", .{ indent, symbol_name });
        try self.emitSyntaxErrorHookCall(writer, "", symbol_name, indent);
        try writer.print("{s}else if (comptime @hasDecl(error_messages, \"syntax_error_ll\"))\n", .{indent});
        try self.emitSyntaxErrorHookCall(writer, "error_messages.syntax_error_ll", null, indent);
        try writer.print("{s}else if (comptime @hasDecl(error_messages, \"syntax_error\"))\n", .{indent});
        try self.emitSyntaxErrorHookCall(writer, "error_messages.syntax_error", null, indent);
        try writer.print(
            \\{s}else
            \\{s}    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
            \\{s}if (!builtin.is_test) std.debug.print("{{s}}", .{{diagnostic_message}});
            \\
        , .{ indent, indent, indent });
    }

    fn emitSyntaxErrorHookCall(self: *Generator, writer: *std.Io.Writer, callee_prefix: []const u8, field_name: ?[]const u8, indent: []const u8) !void {
        _ = self;
        if (field_name) |name| {
            try writer.print(
                \\{s}    @field(error_messages, "{s}")(.{{
                \\{s}        .allocator = context.runtime().arena_allocator,
                \\{s}        .context = context,
                \\{s}        .diagnostic = diagnostic,
                \\{s}        .style = .ansi,
                \\{s}    }}) catch ""
                \\
            , .{ indent, name, indent, indent, indent, indent, indent });
        } else {
            try writer.print(
                \\{s}    {s}(.{{
                \\{s}        .allocator = context.runtime().arena_allocator,
                \\{s}        .context = context,
                \\{s}        .diagnostic = diagnostic,
                \\{s}        .style = .ansi,
                \\{s}    }}) catch ""
                \\
            , .{ indent, callee_prefix, indent, indent, indent, indent, indent });
        }
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
                try writer.print("{s}var root_node: {s} = {s};\n", .{ indent, self.nodeReturnType(true), self.missingNode() });
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
        try self.emitDebugReduction(writer, rule, parent_variable, indent);
        if (!self.options.with_ast and parent_returns_node) {
            try writer.print("{s}node.clearTemporaryChildren();\n", .{indent});
        }
    }

    fn emitChildParseLine(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, parent_variable: usize, rule: Rule, child_index: usize, parent: ?[]const u8, parent_address: ?[]const u8, indent: []const u8, skip_ast_construction: bool) !void {
        const name = try self.parserName(symbol_index);
        const child = self.symbols.items[symbol_index];
        const explicit_recovery = self.uses_explicit_recovery;
        const child_skips_ast_construction = (self.options.with_ast or self.options.with_procedures) and (skip_ast_construction or (child.kind == .variable and !child.ast_enabled));
        const child_returns_node = self.symbolReturnsNode(symbol_index, child_skips_ast_construction);
        const call_name = if (symbol_index == parent_variable)
            try std.fmt.allocPrint(self.allocator, "{s}_{s}_{d}", .{ name, rule.rhs_index, child_index })
        else
            name;
        if (parent != null) {
            if (child_returns_node) {
                if (!self.options.with_ast) {
                    try writer.print("{s}{{\n{s}    const child_node = {s}parse_{s}(context", .{ indent, indent, if (explicit_recovery) "" else "try ", call_name });
                    try self.emitChildOccurrenceArgument(writer, rule, child_index, child_returns_node);
                    if (explicit_recovery) {
                        try self.emitExplicitRuleCatch(writer, rule, parent_variable, skip_ast_construction, indent);
                    } else {
                        try writer.writeByte(')');
                    }
                    try writer.print(
                        \\;
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
                try writer.print(
                    \\;
                    \\{s}    if (child_node != data_structures.Node.invalid_pointer) {{
                    \\{s}        context.node_allocator.at({s}).immediateAppendChildren({s}, child_node, context.node_allocator); // child {d} (chain if replaceWithChildren)
                    \\{s}    }}
                    \\{s}}}
                    \\
                , .{ indent, indent, parent_address.?, parent_address.?, child_index, indent, indent });
            } else {
                try writer.print("{s}{s}parse_{s}{s}(context", .{ indent, if (explicit_recovery) "" else "try ", call_name, if (child_skips_ast_construction) "_" else "" });
                try self.emitChildOccurrenceArgument(writer, rule, child_index, false);
                if (explicit_recovery) {
                    try self.emitExplicitRuleCatch(writer, rule, parent_variable, skip_ast_construction, indent);
                } else {
                    try writer.writeByte(')');
                }
                try writer.print("; // child {d}\n", .{child_index});
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
        } else {
            try writer.print("{s}{s}parse_{s}{s}(context", .{ indent, if (explicit_recovery) "" else "try ", call_name, if (child_skips_ast_construction) "_" else "" });
            try self.emitChildOccurrenceArgument(writer, rule, child_index, false);
            if (explicit_recovery) {
                try self.emitExplicitRuleCatch(writer, rule, parent_variable, skip_ast_construction, indent);
            } else {
                try writer.writeByte(')');
            }
            try writer.print("; // child {d}\n", .{child_index});
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
        const rule = self.rules.items[rule_index];
        const variable_index = self.variableIndex(parent_variable);
        if (self.options.with_ast) {
            try writer.print(
                \\{s}var args = data_structures.ProcedureArguments{{
                \\{s}    .context = context,
                \\{s}    .rule = rules[{d}],
                \\{s}    .node_address = {s},
                \\{s}}};
                \\
            , .{ indent, indent, indent, rule_index, indent, node_expr, indent });
        } else {
            try writer.print(
                \\{s}var args = data_structures.ProcedureArguments{{
                \\{s}    .context = context,
                \\{s}    .rule = rules[{d}],
                \\{s}    ._temp_node = &{s},
                \\{s}}};
                \\
            , .{ indent, indent, indent, rule_index, indent, node_expr, indent });
        }
        if (self.has_occurrence_procedures) {
            try writer.print("{s}try runProcedureSequence({s}, &args);\n", .{ indent, occurrence_expr });
        }
        try writer.print("{s}try runProcedureSequence(", .{indent});
        try emitter_common.emitProcedureSequenceExpression(writer, rule.annotations.procedures.items);
        try writer.writeAll(", &args);\n");
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
            indent, rule_index,     indent, indent,          indent,
            indent, variable_index, indent, parent_variable, indent,
            indent, indent,         indent, indent,          indent,
            indent,
        });
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
        try self.emitRuleSymbolsForDebug(writer, rule);
        try writer.print(
            \\\n", .{{}});
            \\{s}    }}
            \\{s}}}
            \\
        , .{ indent, indent });
    }

    fn emitDebugReduction(self: *Generator, writer: *std.Io.Writer, rule: Rule, parent_variable: usize, indent: []const u8) !void {
        try writer.print(
            \\{s}if (comptime builtin.mode == .Debug) {{
            \\{s}    if (context.verbosityLevel() > 1) {{
            \\{s}        std.debug.print("Reduction:
        , .{ indent, indent, indent });
        try writer.writeAll(" ");
        try emitFormatToken(writer, self.symbols.items[parent_variable].id);
        try writer.writeAll(" <~ ");
        try self.emitRuleSymbolsForDebug(writer, rule);
        try writer.print(
            \\\n", .{{}});
            \\{s}    }}
            \\{s}}}
            \\
        , .{ indent, indent });
    }

    fn emitRuleSymbolsForDebug(self: *Generator, writer: *std.Io.Writer, rule: Rule) !void {
        for (rule.rhs.items, 0..) |symbol_index, i| {
            if (i != 0) try writer.writeAll(", ");
            const symbol = self.symbols.items[symbol_index];
            if (symbol.kind == .variable) {
                try emitFormatToken(writer, symbol.id);
            } else {
                try writer.writeByte('\'');
                try emitFormatToken(writer, symbol.id);
                try writer.writeByte('\'');
            }
        }
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
