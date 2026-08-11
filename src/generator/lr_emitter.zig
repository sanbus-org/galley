const std = @import("std");
const common = @import("generator_common");
const emitter_common = @import("generator_emitter_common");
const planning = @import("lr_plan.zig");
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
const Item = planning.Item;
const Occurrence = planning.Occurrence;
const ActionKind = planning.ActionKind;
const Action = planning.Action;
const GotoEntry = planning.GotoEntry;
const State = planning.State;
const RecoveryStateMetadata = planning.RecoveryStateMetadata;
const SyntaxErrorHandlerSpec = planning.SyntaxErrorHandler;
const LRPlan = planning.LRPlan;

const Generator = struct {
    allocator: std.mem.Allocator,
    options: Options,
    symbols: std.ArrayList(Symbol),
    variables: std.ArrayList(usize),
    rules: std.ArrayList(Rule),
    plan: *const LRPlan,
    uses_explicit_recovery: bool,
    uses_verbatim: bool,

    fn init(allocator: std.mem.Allocator, options: Options, grammar: *const common.PreparedGrammar, plan: *const LRPlan) Generator {
        return .{
            .allocator = allocator,
            .options = options,
            .symbols = grammar.symbols,
            .variables = grammar.variables,
            .rules = grammar.rules,
            .plan = plan,
            .uses_explicit_recovery = grammar.uses_explicit_recovery,
            .uses_verbatim = grammar.uses_verbatim,
        };
    }

    fn emit(self: *Generator, writer: *std.Io.Writer) !void {
        try writer.writeAll(
            \\const builtin = @import("builtin");
            \\const std = @import("std");
            \\const root = @import("galley");
            \\const config = root.config;
            \\const procedures = root.procedures;
            \\const error_messages = root.error_messages;
            \\const data_structures = root.data_structures;
            \\const string_utilities = root.string_utilities;
            \\
        );
        try emitter_common.emitParserMetadata(
            writer,
            "lr",
            self.options,
            self.uses_explicit_recovery,
            self.longestTerminalLength(),
            self.uses_verbatim,
        );
        try emitter_common.emitGrammarTables(writer, self.symbols.items, self.variables.items, self.rules.items);
        if (self.options.with_error_recovery and !self.uses_explicit_recovery) try emitter_common.emitRecoveryOffsetFunction(writer, "lrRecoveryOffset");
        if (self.options.with_procedures) try emitter_common.emitProcedureSupport(writer, self.rules.items, self.symbols.items, self.variables.items);

        try writer.writeAll(
            \\const ReduceResult = struct {
            \\    variable: u16,
            \\    pops_remaining: u16,
            \\    is_accept: bool,
        );
        if (self.options.with_error_recovery) try writer.writeAll("    is_recovery: bool,\n");
        try writer.writeAll(
            \\};
            \\
            \\const SemanticValue = struct {
            \\    start_pos: usize,
        );
        if (self.options.with_ast) {
            try writer.writeAll("    node: data_structures.Node.Pointer = data_structures.Node.invalid_pointer,\n");
        } else if (self.options.with_procedures) {
            try writer.writeAll("    node: ?data_structures.Node = null,\n");
        }
        try writer.writeAll(
            \\};
            \\
            \\const SemanticStack = struct {
            \\    storage: std.ArrayList(SemanticValue) = .empty,
            \\    allocator: std.mem.Allocator,
            \\
            \\    inline fn append(self: *SemanticStack, value: SemanticValue) !void {
            \\        if (self.storage.items.len == self.storage.capacity) {
            \\            @branchHint(.unlikely);
            \\            try self.storage.ensureUnusedCapacity(self.allocator, 1);
            \\        }
            \\        self.storage.appendAssumeCapacity(value);
            \\    }
            \\
            \\    inline fn pop(self: *SemanticStack) ?SemanticValue {
            \\        return self.storage.pop();
            \\    }
            \\
            \\    fn deinit(self: *SemanticStack) void {
            \\        self.storage.deinit(self.allocator);
            \\    }
            \\};
            \\
        );
        if (self.uses_explicit_recovery) try self.emitExplicitRecoverySupport(writer);

        for (self.plan.states.items, 0..) |state, index| {
            try self.emitStateFunction(writer, state, index);
            try writer.writeByte('\n');
        }
        if (self.options.with_error_recovery and !self.uses_explicit_recovery) try self.emitStateRecoveryCandidateTables(writer);
        try self.emitSyntaxErrorHandlers(writer);
        if (self.uses_explicit_recovery) try self.emitExplicitSyntaxDiagnosticFlusher(writer);

        try writer.writeAll(
            \\pub fn parseWithResult(context: *data_structures.Context) !root.ParseResult {
            \\    var stack = SemanticStack{ .allocator = context.runtime().arena_allocator };
            \\    defer stack.deinit();
            \\
        );
        if (self.uses_explicit_recovery) {
            try writer.writeAll(
                \\    const recovery_root = LRRecoveryFrame{ .parent = null, .state = 0, .incoming_symbol = null };
                \\    const result = try state_0(context, &stack, &recovery_root);
            );
        } else {
            try writer.writeAll("    const result = try state_0(context, &stack);\n");
        }
        if (self.options.with_error_recovery) {
            try writer.writeAll(
                \\    if (result.is_recovery or !result.is_accept) {
                \\        return root.ParseError.SyntaxError;
                \\    }
                \\    if (context.hasSyntaxErrors()) return root.ParseError.SyntaxError;
                \\
            );
        } else {
            try writer.writeAll(
                \\    if (!result.is_accept) {
                \\        return root.ParseError.SyntaxError;
                \\    }
                \\
            );
        }
        try writer.writeAll(
            \\    if (context.verbosityLevel() > 0) {
            \\        std.log.info("The input file was parsed successfully!", .{});
            \\    }
            \\
        );
        if (self.options.with_ast) {
            try writer.writeAll(
                \\    const root_node = stack.storage.items[stack.storage.items.len - 1].node;
                \\    const ast_root = if (root_node != data_structures.Node.invalid_pointer) root_node else null;
            );
        } else {
            try writer.writeAll("    const ast_root = null;\n");
        }
        if (!self.options.with_ast and self.options.with_procedures) {
            try writer.writeAll("    const semantic_root = if (stack.storage.items[stack.storage.items.len - 1].node) |node| node.payload else null;\n");
        } else if (self.options.with_ast and self.options.with_procedures) {
            try writer.writeAll("    const semantic_root = if (ast_root) |address| context.node_allocator.at(address).payload else null;\n");
        } else {
            try writer.writeAll("    const semantic_root = {};\n");
        }
        try writer.writeAll(
            \\    return .{
            \\        .parsed_bytes = context.pos() - if (comptime config.indentation_syntax) 1 else 0,
            \\        .line = context.line,
            \\        .column = context.column,
            \\        .ast_root = ast_root,
            \\        .semantic_root = semantic_root,
            \\    };
            \\}
            \\
            \\pub fn parse(context: *data_structures.Context) !void {
            \\    _ = try parseWithResult(context);
            \\}
            \\
        );
    }

    fn emitStateFunction(self: *Generator, writer: *std.Io.Writer, state: State, state_index: usize) !void {
        if (!self.options.with_error_recovery) return self.emitFailFastStateFunction(writer, state, state_index);

        try self.emitRecoveryStateFunction(writer, state, state_index);
    }

    fn emitFailFastStateFunction(self: *Generator, writer: *std.Io.Writer, state: State, state_index: usize) !void {
        try writer.print("// LR parser state {d}\nfn state_{d}(context: *data_structures.Context, stack: *SemanticStack) anyerror!ReduceResult {{\n", .{ state_index, state_index });
        try writer.writeAll("    var result: ReduceResult = undefined;\n");
        if (!state.uses_semantic_stack) try writer.writeAll("    _ = stack;\n");

        const decision = self.plan.state_decisions.items[state_index];
        if (decision.action_tree.entries.len == 0) {
            try self.emitStateSyntaxError(writer, decision.action_tree.diagnostic.?, "    ");
        } else {
            try self.emitActionSwitch(writer, state, decision.action_tree, 0, "    ");
            try writer.writeByte('\n');
        }

        try writer.writeAll(
            \\    while (true) {
            \\        if (result.is_accept) return result;
            \\        if (result.pops_remaining > 0) {
            \\            result.pops_remaining -= 1;
            \\            return result;
            \\        }
            \\
        );
        if (state.gotos.items.len == 0) {
            try self.emitStateSyntaxError(writer, decision.goto_diagnostic.?, "        ");
        } else {
            try writer.writeAll("        result = switch (result.variable) {\n");
            for (state.gotos.items) |goto| {
                try writer.print("            {d} => try state_{d}(context, stack), // {s}\n", .{ self.variableIndex(goto.variable), goto.state, self.symbols.items[goto.variable].id });
            }
            try writer.writeAll("            else => unreachable,\n        };\n");
        }
        try writer.writeAll("    }\n}\n");
    }

    fn emitRecoveryStateFunction(self: *Generator, writer: *std.Io.Writer, state: State, state_index: usize) !void {
        try writer.print("// LR parser state {d}\nfn state_{d}(context: *data_structures.Context, stack: *SemanticStack{s}) anyerror!ReduceResult {{\n", .{
            state_index,
            state_index,
            if (self.uses_explicit_recovery) ", recovery_frame: *const LRRecoveryFrame" else "",
        });
        try writer.writeAll(if (self.uses_explicit_recovery) "    while (true) {\n" else "    state_recovery: while (true) {\n");
        try writer.writeAll("        var result: ReduceResult = undefined;\n");

        const decision = self.plan.state_decisions.items[state_index];
        if (decision.action_tree.entries.len == 0) {
            try self.emitStateSyntaxError(writer, decision.action_tree.diagnostic.?, "        ");
        } else {
            try self.emitActionSwitch(writer, state, decision.action_tree, 0, "        ");
            try writer.writeByte('\n');
        }

        try writer.writeAll(
            \\        while (true) {
            \\            if (result.is_accept) return result;
            \\            if (result.pops_remaining > 0) {
            \\                result.pops_remaining -= 1;
            \\                return result;
            \\            }
            \\
        );
        if (state.gotos.items.len == 0) {
            try self.emitStateSyntaxError(writer, decision.goto_diagnostic.?, "            ");
        } else {
            try writer.writeAll("            result = switch (result.variable) {\n");
            for (state.gotos.items) |goto| {
                if (self.uses_explicit_recovery) {
                    try writer.print(
                        "                {d} => next: {{ const next_recovery_frame = LRRecoveryFrame{{ .parent = recovery_frame, .state = {d}, .incoming_symbol = {d} }}; break :next try state_{d}(context, stack, &next_recovery_frame); }}, // {s}\n",
                        .{ self.variableIndex(goto.variable), goto.state, goto.variable, goto.state, self.symbols.items[goto.variable].id },
                    );
                } else {
                    try writer.print("                {d} => try state_{d}(context, stack), // {s}\n", .{ self.variableIndex(goto.variable), goto.state, self.symbols.items[goto.variable].id });
                }
            }
            try writer.writeAll("                else => unreachable,\n            };\n");
            if (!self.uses_explicit_recovery) try writer.writeAll("            if (result.is_recovery) continue :state_recovery;\n");
        }
        try writer.writeAll("        }\n    }\n}\n");
    }

    fn emitActionSwitch(self: *Generator, writer: *std.Io.Writer, state: State, node: *const switch_planning.Node, prefix_length: usize, indent: []const u8) !void {
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
                try self.emitAction(writer, state.actions.items[group.child.fallback.?], prefix_length + step_length, try indented(self.allocator, indent, 8));
            } else {
                try self.emitActionSwitch(writer, state, group.child, prefix_length + step_length, try indented(self.allocator, indent, 8));
                try writer.writeByte('\n');
            }
            try writer.print("{s}    }},\n", .{indent});
        }
        if (node.fallback) |action| {
            try writer.print("{s}    else => {{\n", .{indent});
            try self.emitAction(writer, state.actions.items[action], prefix_length, try indented(self.allocator, indent, 8));
            try writer.print("{s}    }},\n", .{indent});
        } else {
            try self.emitSyntaxError(writer, node.diagnostic.?, try indented(self.allocator, indent, 4));
        }
        try writer.print("{s}}}", .{indent});
    }

    fn emitAction(self: *Generator, writer: *std.Io.Writer, action: Action, length: usize, indent: []const u8) !void {
        switch (action.kind) {
            .accept => {
                try writer.print(
                    \\{s}if (comptime builtin.mode == .Debug) {{
                    \\{s}    if (context.verbosityLevel() > 1) {{
                    \\{s}        std.debug.print("Accept!\n", .{{}});
                    \\{s}    }}
                    \\{s}}}
                    \\{s}return ReduceResult{{ .variable = 0, .pops_remaining = 0, .is_accept = true{s} }};
                    \\
                , .{ indent, indent, indent, indent, indent, indent, if (self.options.with_error_recovery) ", .is_recovery = false" else "" });
            },
            .shift => {
                if (self.options.with_ast or self.options.with_procedures or self.uses_verbatim) {
                    try writer.print("{s}const start_pos = context.currentTokenSourceOffset();\n", .{indent});
                }
                if (self.options.with_ast and self.options.ast_for_terminals) {
                    try writer.print(
                        \\{s}{s} node_address = try context.node_allocator.create(start_pos, data_structures.Node.invalid_variable);
                        \\{s}context.node_allocator.at(node_address).text_length = {d};
                        \\
                    , .{ indent, if (self.options.with_procedures) "var" else "const", indent, length });
                } else if (self.options.with_ast) {
                    try writer.print("{s}const node_address = data_structures.Node.invalid_pointer;\n", .{indent});
                } else if (self.options.with_procedures and self.options.ast_for_terminals) {
                    try writer.print("{s}var terminal_node = data_structures.Node{{ .text_start = start_pos, .text_length = {d}, .payload = .{{}} }};\n", .{ indent, length });
                }
                try writer.print("{s}context.releaseToken({d});\n", .{ indent, length });
                if (self.occurrenceIsVerbatim(action.occurrence)) {
                    try self.emitVerbatimShiftCapture(writer, action.terminal, indent);
                }
                if (self.options.with_procedures and self.options.ast_for_terminals) {
                    try self.emitTerminalProcedureBlock(writer, action.terminal, action.occurrence, if (self.options.with_ast) "node_address" else "terminal_node", indent);
                    if (self.options.with_ast) try writer.print("{s}node_address = args.node_address orelse data_structures.Node.invalid_pointer;\n", .{indent});
                }
                if (self.options.with_ast) {
                    try writer.print("{s}try stack.append(.{{ .start_pos = start_pos, .node = node_address }});\n", .{indent});
                } else if (self.options.with_procedures) {
                    try writer.print("{s}try stack.append(.{{ .start_pos = start_pos, .node = {s} }});\n", .{ indent, if (self.options.ast_for_terminals) "terminal_node" else "null" });
                } else if (self.uses_verbatim) {
                    try writer.print("{s}try stack.append(.{{ .start_pos = start_pos }});\n", .{indent});
                }
                try writer.print(
                    \\{s}if (comptime builtin.mode == .Debug) {{
                    \\{s}    if (context.verbosityLevel() > 1) {{
                    \\{s}        std.debug.print("Shift: matched '{{s}}', transitioning to state_{d}\n", .{{
                , .{ indent, indent, indent, action.state });
                try emitStringLiteral(writer, self.symbols.items[action.terminal].id);
                try writer.print(
                    \\}});
                    \\{s}    }}
                    \\{s}}}
                    \\
                , .{ indent, indent });
                if (self.uses_explicit_recovery) {
                    try writer.print("{s}const next_recovery_frame = LRRecoveryFrame{{ .parent = recovery_frame, .state = {d}, .incoming_symbol = {d} }};\n", .{ indent, action.state, action.terminal });
                    try writer.print("{s}result = try state_{d}(context, stack, &next_recovery_frame);\n", .{ indent, action.state });
                } else {
                    try writer.print("{s}result = try state_{d}(context, stack);\n", .{ indent, action.state });
                }
                if (self.options.with_error_recovery and !self.uses_explicit_recovery) {
                    try writer.print("{s}if (result.is_recovery) continue :state_recovery;\n", .{indent});
                }
            },
            .reduce => try self.emitReduceAction(writer, action.rule, action.occurrence, indent),
        }
    }

    fn emitReduceAction(self: *Generator, writer: *std.Io.Writer, rule_index: usize, occurrence: ?Occurrence, indent: []const u8) !void {
        const rule = self.rules.items[rule_index];
        const variable_index = self.variableIndex(rule.header);
        const rhs_len = rule.rhs.items.len;

        try writer.print("{s}// Reduce: {s} <- ", .{ indent, self.symbols.items[rule.header].id });
        try self.emitRuleSymbolsForDebug(writer, rule);
        try writer.writeByte('\n');

        if (self.options.with_ast or self.options.with_procedures or self.uses_verbatim) {
            var i = rhs_len;
            while (i > 0) {
                i -= 1;
                const sym = rule.rhs.items[i];
                const is_linked = self.symbolReturnsStackNode(sym);
                const needed = (is_linked and self.symbols.items[rule.header].ast_enabled) or i == 0;
                if (needed) {
                    try writer.print("{s}{s} child_{d} = stack.pop().?;\n", .{ indent, if (!self.options.with_ast and self.options.with_procedures and is_linked and self.symbols.items[rule.header].ast_enabled) "var" else "const", i + 1 });
                } else {
                    try writer.print("{s}_ = stack.pop();\n", .{indent});
                }
            }

            if (rhs_len > 0) {
                try writer.print("{s}const start_pos = child_1.start_pos;\n", .{indent});
            } else {
                try writer.print("{s}const start_pos = context.currentTokenSourceOffset();\n", .{indent});
            }
            if (self.occurrenceIsVerbatim(occurrence)) {
                try self.emitVerbatimReduceCapture(writer, occurrence, indent);
            }

            if ((self.options.with_ast or self.options.with_procedures) and self.symbols.items[rule.header].ast_enabled) {
                if (self.options.with_ast) {
                    try writer.print("{s}const parent_address = try context.node_allocator.create(start_pos, {d});\n", .{ indent, variable_index });
                    for (rule.rhs.items, 0..) |sym, child_index| {
                        if (self.symbolReturnsStackNode(sym)) {
                            try writer.print(
                                \\{s}if (child_{d}.node != data_structures.Node.invalid_pointer) {{
                                \\{s}    context.node_allocator.at(parent_address).immediateAppendChildren(parent_address, child_{d}.node, context.node_allocator); // child {d}
                                \\{s}}}
                                \\
                            , .{ indent, child_index + 1, indent, child_index + 1, child_index, indent });
                        }
                    }
                    try writer.print("{s}context.node_allocator.at(parent_address).text_length = {s} - start_pos;\n", .{ indent, if (self.occurrenceIsVerbatim(occurrence)) "verbatim_end" else "context.currentTokenSourceOffset()" });
                    if (self.options.with_procedures) try self.emitProcedureBlock(writer, rule_index, rule.header, occurrence, "parent_address", indent);
                    const stack_value = if (self.options.with_procedures) "args.node_address orelse data_structures.Node.invalid_pointer" else "parent_address";
                    try writer.print("{s}try stack.append(.{{ .start_pos = start_pos, .node = {s} }});\n", .{ indent, stack_value });
                } else {
                    try writer.print("{s}var parent_node = data_structures.Node{{ .text_start = start_pos, .text_length = {s} - start_pos, .variable = {d}, .payload = .{{}} }};\n", .{ indent, if (self.occurrenceIsVerbatim(occurrence)) "verbatim_end" else "context.currentTokenSourceOffset()", variable_index });
                    for (rule.rhs.items, 0..) |sym, child_index| {
                        if (self.symbolReturnsStackNode(sym)) {
                            try writer.print(
                                \\{s}if (child_{d}.node) |*child_node| {{
                                \\{s}    parent_node.appendTemporaryChild(child_node);
                                \\{s}}}
                                \\
                            , .{ indent, child_index + 1, indent, indent });
                        }
                    }
                    try self.emitProcedureBlock(writer, rule_index, rule.header, occurrence, "parent_node", indent);
                    try writer.print("{s}parent_node.clearTemporaryChildren();\n", .{indent});
                    try writer.print("{s}try stack.append(.{{ .start_pos = start_pos, .node = parent_node }});\n", .{indent});
                }
            } else {
                try writer.print("{s}try stack.append(.{{ .start_pos = start_pos }});\n", .{indent});
            }
        }

        try self.emitDebugReduction(writer, rule, indent);
        try writer.print("{s}{s} ReduceResult{{ .variable = {d}, .pops_remaining = {d}, .is_accept = false{s} }};\n", .{
            indent,
            if (rhs_len > 0) "return" else "result =",
            variable_index,
            if (rhs_len > 0) rhs_len - 1 else 0,
            if (self.options.with_error_recovery) ", .is_recovery = false" else "",
        });
    }

    fn emitProcedureBlock(self: *Generator, writer: *std.Io.Writer, rule_index: usize, parent_variable: usize, occurrence: ?Occurrence, node_expr: []const u8, indent: []const u8) !void {
        const rule = self.rules.items[rule_index];
        const variable_index = self.variableIndex(parent_variable);
        if (self.options.with_ast) {
            try writer.print(
                \\{s}var args = data_structures.ProcedureArguments{{
                \\{s}    .context = context,
                \\{s}    .rule = rules[{d}],
                \\{s}    .node_address = {s},
                \\{s}}};
            , .{ indent, indent, indent, rule_index, indent, node_expr, indent });
        } else {
            try writer.print(
                \\{s}var args = data_structures.ProcedureArguments{{
                \\{s}    .context = context,
                \\{s}    .rule = rules[{d}],
                \\{s}    ._temp_node = &{s},
                \\{s}}};
            , .{ indent, indent, indent, rule_index, indent, node_expr, indent });
        }
        try writer.print("{s}try runProcedureSequence(", .{indent});
        try self.emitOccurrenceExpression(writer, occurrence);
        try writer.writeAll(", &args);\n");
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
    }

    fn emitTerminalProcedureBlock(self: *Generator, writer: *std.Io.Writer, terminal_index: usize, occurrence: ?Occurrence, node_expr: []const u8, indent: []const u8) !void {
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
        try writer.print("{s}try runProcedureSequence(", .{indent});
        try self.emitOccurrenceExpression(writer, occurrence);
        try writer.writeAll(", &args);\n");
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

    fn emitOccurrenceExpression(self: *Generator, writer: *std.Io.Writer, occurrence: ?Occurrence) !void {
        if (occurrence) |value| {
            try emitter_common.emitProcedureSequenceExpression(
                writer,
                self.rules.items[value.rule].rhs_annotations.items[value.position].procedures.items,
            );
        } else {
            try writer.writeAll("null");
        }
    }

    fn occurrenceIsVerbatim(self: *Generator, occurrence: ?Occurrence) bool {
        if (occurrence) |value| {
            return self.rules.items[value.rule].rhs_annotations.items[value.position].verbatim;
        }
        return false;
    }

    fn emitVerbatimShiftCapture(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, indent: []const u8) !void {
        const symbol = self.symbols.items[symbol_index];
        if (symbol.kind == .terminal) {
            try writer.print("{s}try context.captureVerbatim(", .{indent});
            try common.emitStringLiteral(writer, symbol.id);
            try writer.writeAll(");\n");
        } else {
            try writer.print("{s}const verbatim_terminator = context.getTextSlice(start_pos, context.currentTokenSourceOffset() - start_pos);\n", .{indent});
            try writer.print("{s}try context.captureVerbatim(verbatim_terminator);\n", .{indent});
        }
    }

    fn emitVerbatimReduceCapture(self: *Generator, writer: *std.Io.Writer, occurrence: ?Occurrence, indent: []const u8) !void {
        const value = occurrence.?;
        const symbol_index = self.rules.items[value.rule].rhs.items[value.position];
        if (self.symbols.items[symbol_index].kind != .variable) return;
        try writer.print("{s}const verbatim_terminator = context.getTextSlice(start_pos, context.currentTokenSourceOffset() - start_pos);\n", .{indent});
        if (self.options.with_ast or self.options.with_procedures) {
            try writer.print("{s}const verbatim_end = context.currentTokenSourceOffset();\n", .{indent});
        }
        try writer.print("{s}try context.captureVerbatim(verbatim_terminator);\n", .{indent});
    }

    fn emitDebugReduction(self: *Generator, writer: *std.Io.Writer, rule: Rule, indent: []const u8) !void {
        try writer.print(
            \\{s}if (comptime builtin.mode == .Debug) {{
            \\{s}    if (context.verbosityLevel() > 1) {{
            \\{s}        std.debug.print("Reduction:
        , .{ indent, indent, indent });
        try writer.writeAll(" ");
        try emitFormatToken(writer, self.symbols.items[rule.header].id);
        try writer.writeAll(" <~ ");
        try self.emitRuleSymbolsForDebug(writer, rule);
        try writer.print(
            \\\n", .{{}});
            \\{s}    }}
            \\{s}}}
        , .{ indent, indent });
    }

    fn emitSyntaxError(self: *Generator, writer: *std.Io.Writer, diagnostic: usize, indent: []const u8) !void {
        const spec = self.plan.syntax_error_handlers.items[diagnostic];
        try writer.print("{s}else => {{\n", .{indent});
        try self.emitSyntaxErrorCall(writer, spec, try indented(self.allocator, indent, 4));
        try writer.print("{s}}},\n", .{indent});
    }

    fn emitStateSyntaxError(self: *Generator, writer: *std.Io.Writer, diagnostic: usize, indent: []const u8) !void {
        const spec = self.plan.syntax_error_handlers.items[diagnostic];
        try self.emitSyntaxErrorCall(writer, spec, indent);
    }

    fn emitSyntaxErrorCall(
        self: *Generator,
        writer: *std.Io.Writer,
        spec: SyntaxErrorHandlerSpec,
        indent: []const u8,
    ) !void {
        if (!self.options.with_error_recovery) {
            try writer.print("{s}return {s}(context);\n", .{ indent, spec.name });
            return;
        }
        if (self.uses_explicit_recovery) {
            try writer.print("{s}if (try {s}(context, stack, recovery_frame)) |explicit_recovery| {{\n", .{ indent, spec.name });
            try writer.print("{s}    if (explicit_recovery.return_from_state) return explicit_recovery.result;\n", .{indent});
            try writer.print("{s}    result = explicit_recovery.result;\n", .{indent});
            try writer.print("{s}}} else return root.ParseError.SyntaxError;\n", .{indent});
            return;
        }
        try writer.print("{s}if (try {s}(context, stack)) continue :state_recovery;\n", .{ indent, spec.name });
        try writer.print("{s}return ReduceResult{{ .variable = 0, .pops_remaining = 0, .is_accept = false, .is_recovery = true }};\n", .{indent});
    }

    fn emitStateRecoveryCandidateTables(self: *Generator, writer: *std.Io.Writer) !void {
        for (self.plan.recovery.automatic_candidates.items, 0..) |candidates, state_index| {
            try writer.print("const lr_recovery_candidates_{d} = &[_][]const u8{{", .{state_index});
            try self.emitStringSliceItems(writer, candidates);
            try writer.writeAll("};\n");
        }
        try writer.writeByte('\n');
    }

    fn emitExplicitRecoverySupport(self: *Generator, writer: *std.Io.Writer) !void {
        try writer.writeAll(
            \\const ExplicitRecoveryScope = struct {
            \\    id: usize,
            \\    target: root.SyntaxRecoveryTarget,
            \\    points: []const root.SyntaxRecoveryPoint,
            \\};
            \\
            \\const LRRecoveryOccurrence = struct {
            \\    rule: usize,
            \\    position: usize,
            \\};
            \\
            \\const LRRecoveryItem = struct {
            \\    rule: usize,
            \\    head: usize,
            \\    lookahead: usize,
            \\    procedure_occurrence: ?LRRecoveryOccurrence,
            \\};
            \\
            \\const LRRecoveryClosureEdge = struct {
            \\    child: usize,
            \\    parent: usize,
            \\    occurrence: LRRecoveryOccurrence,
            \\};
            \\
            \\const LRRecoveryFrame = struct {
            \\    parent: ?*const LRRecoveryFrame,
            \\    state: usize,
            \\    incoming_symbol: ?usize,
            \\};
            \\
            \\const LRRecoveryLineageNode = struct {
            \\    end_index: usize,
            \\    item: LRRecoveryItem,
            \\    unwind_count: usize,
            \\    first_edge: usize = 0,
            \\    edge_count: usize = 0,
            \\    is_exit: bool = false,
            \\};
            \\
            \\const LRRecoveryLineageEdge = struct {
            \\    outer: usize,
            \\    occurrence: LRRecoveryOccurrence,
            \\};
            \\
            \\const LRRecoveryLineageScopeKind = enum {
            \\    occurrence,
            \\    production,
            \\    lhs,
            \\};
            \\
            \\const LRRecoveryLineageCandidate = struct {
            \\    kind: LRRecoveryLineageScopeKind,
            \\    target: usize,
            \\    position: usize = 0,
            \\    scope: *const ExplicitRecoveryScope,
            \\    variable: u16,
            \\    unwind_count: usize,
            \\    depth: usize = 0,
            \\    source_order: usize,
            \\};
            \\
            \\const LRRecoveryClosureCandidate = struct {
            \\    occurrence: LRRecoveryOccurrence,
            \\    depth: usize,
            \\    source_order: usize,
            \\};
            \\
            \\const LRLhsRecoveryScope = struct { variable: usize, scope: *const ExplicitRecoveryScope };
            \\const LRProductionRecoveryScope = struct { rule: usize, scope: *const ExplicitRecoveryScope };
            \\const LROccurrenceRecoveryScope = struct { occurrence: LRRecoveryOccurrence, scope: *const ExplicitRecoveryScope };
            \\
            \\const ExplicitRecoveryResult = struct {
            \\    result: ReduceResult,
            \\    return_from_state: bool,
            \\};
            \\
            \\fn lrTryExplicitScope(
            \\    context: *data_structures.Context,
            \\    stack: *SemanticStack,
            \\    scope: *const ExplicitRecoveryScope,
            \\    variable: u16,
            \\    unwind_count: usize,
            \\) !?ExplicitRecoveryResult {
            \\    if (!try context.tryExplicitRecovery(scope.id, scope.target, scope.points)) return null;
        );
        if (self.options.with_ast or self.options.with_procedures or self.uses_verbatim) {
            try writer.writeAll(
                \\    {
                \\        var start_pos = context.currentTokenSourceOffset();
                \\        for (0..unwind_count) |_| {
                \\            const discarded = stack.pop() orelse unreachable;
                \\            start_pos = discarded.start_pos;
                \\        }
                \\        try stack.append(.{ .start_pos = start_pos });
                \\    }
            );
        } else {
            try writer.writeAll("    _ = stack;\n");
        }
        try writer.writeAll(
            \\    try lrFlushSyntaxDiagnostic(context);
            \\    return .{
            \\        .result = .{
            \\            .variable = variable,
            \\            .pops_remaining = @intCast(if (unwind_count == 0) 0 else unwind_count - 1),
            \\            .is_accept = false,
            \\            .is_recovery = false,
            \\        },
            \\        .return_from_state = unwind_count != 0,
            \\    };
            \\}
            \\
            \\fn lrRecoveryOccurrencesEqual(lhs: ?LRRecoveryOccurrence, rhs: ?LRRecoveryOccurrence) bool {
            \\    if (lhs == null or rhs == null) return lhs == null and rhs == null;
            \\    return lhs.?.rule == rhs.?.rule and lhs.?.position == rhs.?.position;
            \\}
            \\
            \\fn lrRecoveryItemsEqual(lhs: LRRecoveryItem, rhs: LRRecoveryItem) bool {
            \\    return lhs.rule == rhs.rule and lhs.head == rhs.head and lhs.lookahead == rhs.lookahead and
            \\        lrRecoveryOccurrencesEqual(lhs.procedure_occurrence, rhs.procedure_occurrence);
            \\}
            \\
            \\fn lrRecoveryReductionsEqual(lhs: LRRecoveryItem, rhs: LRRecoveryItem) bool {
            \\    return lhs.rule == rhs.rule and lhs.lookahead == rhs.lookahead and
            \\        lrRecoveryOccurrencesEqual(lhs.procedure_occurrence, rhs.procedure_occurrence);
            \\}
            \\
            \\fn lrRecoveryBaseIndex(frames: []const *const LRRecoveryFrame, end_index: usize, item: LRRecoveryItem) ?usize {
            \\    if (end_index + item.head >= frames.len) return null;
            \\    var offset: usize = 0;
            \\    while (offset < item.head) : (offset += 1) {
            \\        const expected = rules[item.rule].right_hand_side[item.head - 1 - offset];
            \\        if (frames[end_index + offset].incoming_symbol != expected) return null;
            \\    }
            \\    return end_index + item.head;
            \\}
            \\
            \\fn lrRecoveryLineageNodeIndex(
            \\    nodes: []const LRRecoveryLineageNode,
            \\    end_index: usize,
            \\    item: LRRecoveryItem,
            \\) ?usize {
            \\    for (nodes, 0..) |node, node_index| {
            \\        if (node.end_index == end_index and lrRecoveryItemsEqual(node.item, item)) return node_index;
            \\    }
            \\    return null;
            \\}
            \\
            \\fn lrAppendRecoveryLineageNode(
            \\    allocator: std.mem.Allocator,
            \\    frames: []const *const LRRecoveryFrame,
            \\    end_index: usize,
            \\    item: LRRecoveryItem,
            \\    nodes: *std.ArrayList(LRRecoveryLineageNode),
            \\) !?usize {
            \\    if (lrRecoveryLineageNodeIndex(nodes.items, end_index, item)) |node_index| return node_index;
            \\    const unwind_count = lrRecoveryBaseIndex(frames, end_index, item) orelse return null;
            \\    const node_index = nodes.items.len;
            \\    try nodes.append(allocator, .{
            \\        .end_index = end_index,
            \\        .item = item,
            \\        .unwind_count = unwind_count,
            \\    });
            \\    return node_index;
            \\}
            \\
            \\fn lrBuildRecoveryLineage(
            \\    allocator: std.mem.Allocator,
            \\    frames: []const *const LRRecoveryFrame,
            \\    nodes: *std.ArrayList(LRRecoveryLineageNode),
            \\    edges: *std.ArrayList(LRRecoveryLineageEdge),
            \\) !void {
            \\    var inner: usize = 0;
            \\    while (inner < nodes.items.len) : (inner += 1) {
            \\        const node = nodes.items[inner];
            \\        const state = frames[node.unwind_count].state;
            \\        const first_edge = edges.items.len;
            \\        for (lr_recovery_closure_edges[state]) |edge| {
            \\            const child = lr_recovery_items[state][edge.child];
            \\            if (!lrRecoveryReductionsEqual(node.item, child)) continue;
            \\            const parent = lr_recovery_items[state][edge.parent];
            \\            const outer = try lrAppendRecoveryLineageNode(allocator, frames, node.unwind_count, parent, nodes) orelse continue;
            \\            try edges.append(allocator, .{ .outer = outer, .occurrence = edge.occurrence });
            \\    }
            \\        nodes.items[inner].first_edge = first_edge;
            \\        nodes.items[inner].edge_count = edges.items.len - first_edge;
            \\        nodes.items[inner].is_exit = edges.items.len == first_edge;
            \\    }
            \\}
            \\
            \\fn lrMarkRecoveryLineageProductive(
            \\    allocator: std.mem.Allocator,
            \\    nodes: []const LRRecoveryLineageNode,
            \\    edges: []const LRRecoveryLineageEdge,
            \\    productive: []bool,
            \\) !void {
            \\    @memset(productive, false);
            \\    const inward = try allocator.alloc(std.ArrayList(usize), nodes.len);
            \\    defer allocator.free(inward);
            \\    for (inward) |*entries| entries.* = .empty;
            \\    defer for (inward) |*entries| entries.deinit(allocator);
            \\    var work: std.ArrayList(usize) = .empty;
            \\    defer work.deinit(allocator);
            \\    for (nodes, 0..) |node, inner| {
            \\        for (edges[node.first_edge..][0..node.edge_count]) |edge| {
            \\            try inward[edge.outer].append(allocator, inner);
            \\        }
            \\        if (!node.is_exit) continue;
            \\        productive[inner] = true;
            \\        try work.append(allocator, inner);
            \\    }
            \\    var cursor: usize = 0;
            \\    while (cursor < work.items.len) : (cursor += 1) {
            \\        for (inward[work.items[cursor]].items) |inner| {
            \\            if (productive[inner]) continue;
            \\            productive[inner] = true;
            \\            try work.append(allocator, inner);
            \\        }
            \\    }
            \\}
            \\
            \\fn lrRecoveryLineageCandidatesEqual(lhs: LRRecoveryLineageCandidate, rhs: LRRecoveryLineageCandidate) bool {
            \\    return lhs.kind == rhs.kind and lhs.target == rhs.target and lhs.position == rhs.position and
            \\        lhs.unwind_count == rhs.unwind_count;
            \\}
            \\
            \\fn lrAppendRecoveryLineageCandidate(
            \\    allocator: std.mem.Allocator,
            \\    candidates: *std.ArrayList(LRRecoveryLineageCandidate),
            \\    candidate: LRRecoveryLineageCandidate,
            \\) !void {
            \\    for (candidates.items) |existing| {
            \\        if (lrRecoveryLineageCandidatesEqual(existing, candidate)) return;
            \\    }
            \\    try candidates.append(allocator, candidate);
            \\}
            \\
            \\fn lrRecoveryLineageCandidateMatchesNode(
            \\    candidate: LRRecoveryLineageCandidate,
            \\    node: LRRecoveryLineageNode,
            \\) bool {
            \\    if (candidate.unwind_count != node.unwind_count) return false;
            \\    return switch (candidate.kind) {
            \\        .occurrence => false,
            \\        .production => node.item.head != 0 and candidate.target == node.item.rule,
            \\        .lhs => candidate.target == rules[node.item.rule].header,
            \\    };
            \\}
            \\
            \\fn lrRecoveryLineageCandidateMatchesEdge(
            \\    candidate: LRRecoveryLineageCandidate,
            \\    node: LRRecoveryLineageNode,
            \\    edge: LRRecoveryLineageEdge,
            \\) bool {
            \\    return candidate.kind == .occurrence and candidate.unwind_count == node.unwind_count and
            \\        candidate.target == edge.occurrence.rule and candidate.position == edge.occurrence.position;
            \\}
            \\
            \\fn lrRecoveryLineageHasAvoidingPath(
            \\    nodes: []const LRRecoveryLineageNode,
            \\    edges: []const LRRecoveryLineageEdge,
            \\    productive: []const bool,
            \\    inner: usize,
            \\    candidate: LRRecoveryLineageCandidate,
            \\    visited: []bool,
            \\) bool {
            \\    if (visited[inner]) return false;
            \\    visited[inner] = true;
            \\    const node = nodes[inner];
            \\    if (lrRecoveryLineageCandidateMatchesNode(candidate, node)) return false;
            \\    if (node.is_exit) return true;
            \\    for (edges[node.first_edge..][0..node.edge_count]) |edge| {
            \\        if (!productive[edge.outer] or lrRecoveryLineageCandidateMatchesEdge(candidate, node, edge)) continue;
            \\        if (lrRecoveryLineageHasAvoidingPath(nodes, edges, productive, edge.outer, candidate, visited)) return true;
            \\    }
            \\    return false;
            \\}
            \\
            \\fn lrRecoveryLineageCandidateDepth(
            \\    allocator: std.mem.Allocator,
            \\    nodes: []const LRRecoveryLineageNode,
            \\    edges: []const LRRecoveryLineageEdge,
            \\    productive: []const bool,
            \\    roots: []const usize,
            \\    candidate: LRRecoveryLineageCandidate,
            \\) !?usize {
            \\    const distances = try allocator.alloc(usize, nodes.len);
            \\    defer allocator.free(distances);
            \\    @memset(distances, std.math.maxInt(usize));
            \\    var work: std.ArrayList(usize) = .empty;
            \\    defer work.deinit(allocator);
            \\    for (roots) |root_index| {
            \\        if (!productive[root_index] or distances[root_index] == 0) continue;
            \\        distances[root_index] = 0;
            \\        try work.append(allocator, root_index);
            \\    }
            \\    var minimum_depth: usize = std.math.maxInt(usize);
            \\    var cursor: usize = 0;
            \\    while (cursor < work.items.len) : (cursor += 1) {
            \\        const inner = work.items[cursor];
            \\        const node = nodes[inner];
            \\        if (lrRecoveryLineageCandidateMatchesNode(candidate, node)) minimum_depth = @min(minimum_depth, distances[inner]);
            \\        for (edges[node.first_edge..][0..node.edge_count]) |edge| {
            \\            if (!productive[edge.outer]) continue;
            \\            if (lrRecoveryLineageCandidateMatchesEdge(candidate, node, edge)) minimum_depth = @min(minimum_depth, distances[inner]);
            \\            const outer_depth = distances[inner] + 1;
            \\            if (distances[edge.outer] <= outer_depth) continue;
            \\            distances[edge.outer] = outer_depth;
            \\            try work.append(allocator, edge.outer);
            \\        }
            \\    }
            \\    return if (minimum_depth == std.math.maxInt(usize)) null else minimum_depth;
            \\}
            \\
            \\fn lrRecoveryLineageCandidateLessThan(_: void, lhs: LRRecoveryLineageCandidate, rhs: LRRecoveryLineageCandidate) bool {
            \\    if (lhs.depth != rhs.depth) return lhs.depth < rhs.depth;
            \\    if (lhs.kind != rhs.kind) return @intFromEnum(lhs.kind) < @intFromEnum(rhs.kind);
            \\    return lhs.source_order < rhs.source_order;
            \\}
            \\
            \\fn lrClosureMarkProductiveItems(
            \\    allocator: std.mem.Allocator,
            \\    state: usize,
            \\    productive: []bool,
            \\) !void {
            \\    @memset(productive, false);
            \\    var work: std.ArrayList(usize) = .empty;
            \\    defer work.deinit(allocator);
            \\    const edge_offsets = lr_recovery_closure_edge_offsets[state];
            \\    for (productive, 0..) |*is_productive, item| {
            \\        if (edge_offsets[item] != edge_offsets[item + 1]) continue;
            \\        is_productive.* = true;
            \\        try work.append(allocator, item);
            \\    }
            \\    const parent_offsets = lr_recovery_closure_parent_offsets[state];
            \\    const parents = lr_recovery_closure_parents[state];
            \\    var cursor: usize = 0;
            \\    while (cursor < work.items.len) : (cursor += 1) {
            \\        const child = work.items[cursor];
            \\        for (parents[parent_offsets[child]..parent_offsets[child + 1]]) |parent| {
            \\            if (productive[parent]) continue;
            \\            productive[parent] = true;
            \\            try work.append(allocator, parent);
            \\        }
            \\    }
            \\}
            \\
            \\fn lrClosureHasProductivePathAvoidingOccurrence(
            \\    state: usize,
            \\    item: usize,
            \\    occurrence: LRRecoveryOccurrence,
            \\    visited: []bool,
            \\) bool {
            \\    if (visited[item]) return false;
            \\    visited[item] = true;
            \\    const edge_offsets = lr_recovery_closure_edge_offsets[state];
            \\    const edges = lr_recovery_closure_edges[state];
            \\    const outgoing = edges[edge_offsets[item]..edge_offsets[item + 1]];
            \\    if (outgoing.len == 0) return true;
            \\    for (outgoing) |edge| {
            \\        if (lrRecoveryOccurrencesEqual(edge.occurrence, occurrence)) continue;
            \\        if (lrClosureHasProductivePathAvoidingOccurrence(state, edge.child, occurrence, visited)) return true;
            \\    }
            \\    return false;
            \\}
            \\
            \\fn lrClosureOccurrenceDepth(
            \\    allocator: std.mem.Allocator,
            \\    state: usize,
            \\    frames: []const *const LRRecoveryFrame,
            \\    productive: []const bool,
            \\    occurrence: LRRecoveryOccurrence,
            \\) !?usize {
            \\    const items = lr_recovery_items[state];
            \\    const distances = try allocator.alloc(usize, items.len);
            \\    defer allocator.free(distances);
            \\    @memset(distances, std.math.maxInt(usize));
            \\    var work: std.ArrayList(usize) = .empty;
            \\    defer work.deinit(allocator);
            \\    for (lr_recovery_kernel_items[state]) |item| {
            \\        if (!productive[item] or lrRecoveryBaseIndex(frames, 0, items[item]) == null or distances[item] == 0) continue;
            \\        distances[item] = 0;
            \\        try work.append(allocator, item);
            \\    }
            \\    const edge_offsets = lr_recovery_closure_edge_offsets[state];
            \\    const edges = lr_recovery_closure_edges[state];
            \\    var minimum_depth: usize = std.math.maxInt(usize);
            \\    var cursor: usize = 0;
            \\    while (cursor < work.items.len) : (cursor += 1) {
            \\        const parent = work.items[cursor];
            \\        const child_depth = distances[parent] + 1;
            \\        for (edges[edge_offsets[parent]..edge_offsets[parent + 1]]) |edge| {
            \\            if (!productive[edge.child]) continue;
            \\            if (lrRecoveryOccurrencesEqual(edge.occurrence, occurrence)) minimum_depth = @min(minimum_depth, child_depth);
            \\            if (distances[edge.child] <= child_depth) continue;
            \\            distances[edge.child] = child_depth;
            \\            try work.append(allocator, edge.child);
            \\        }
            \\    }
            \\    return if (minimum_depth == std.math.maxInt(usize)) null else minimum_depth;
            \\}
            \\
            \\fn lrRecoveryClosureCandidateLessThan(_: void, lhs: LRRecoveryClosureCandidate, rhs: LRRecoveryClosureCandidate) bool {
            \\    if (lhs.depth != rhs.depth) return lhs.depth > rhs.depth;
            \\    return lhs.source_order < rhs.source_order;
            \\}
            \\
            \\fn lrLhsRecoveryScope(variable: usize) ?*const ExplicitRecoveryScope {
            \\    for (lr_lhs_recovery_scopes) |entry| if (entry.variable == variable) return entry.scope;
            \\    return null;
            \\}
            \\
            \\fn lrProductionRecoveryScope(rule: usize) ?*const ExplicitRecoveryScope {
            \\    for (lr_production_recovery_scopes) |entry| if (entry.rule == rule) return entry.scope;
            \\    return null;
            \\}
            \\
            \\fn lrOccurrenceRecoveryScope(occurrence: LRRecoveryOccurrence) ?*const ExplicitRecoveryScope {
            \\    for (lr_occurrence_recovery_scopes) |entry| {
            \\        if (entry.occurrence.rule == occurrence.rule and entry.occurrence.position == occurrence.position) return entry.scope;
            \\    }
            \\    return null;
            \\}
            \\
            \\fn lrVariableForSymbol(symbol: usize) u16 {
            \\    for (symbol_by_variable, 0..) |candidate, variable| {
            \\        if (candidate == symbol) return @intCast(variable);
            \\    }
            \\    unreachable;
            \\}
            \\
            \\fn lrTryExplicitRecovery(
            \\    context: *data_structures.Context,
            \\    stack: *SemanticStack,
            \\    recovery_frame: *const LRRecoveryFrame,
            \\) !?ExplicitRecoveryResult {
            \\    const allocator = context.runtime().arena_allocator;
            \\    var frames: std.ArrayList(*const LRRecoveryFrame) = .empty;
            \\    defer frames.deinit(allocator);
            \\    var cursor: ?*const LRRecoveryFrame = recovery_frame;
            \\    while (cursor) |frame| {
            \\        try frames.append(allocator, frame);
            \\        cursor = frame.parent;
            \\    }
            \\
            \\    const recovery_state = recovery_frame.state;
            \\    const recovery_items = lr_recovery_items[recovery_state];
            \\    var lineage_nodes: std.ArrayList(LRRecoveryLineageNode) = .empty;
            \\    defer lineage_nodes.deinit(allocator);
            \\    var lineage_edges: std.ArrayList(LRRecoveryLineageEdge) = .empty;
            \\    defer lineage_edges.deinit(allocator);
            \\    var lineage_roots: std.ArrayList(usize) = .empty;
            \\    defer lineage_roots.deinit(allocator);
            \\    for (lr_recovery_kernel_items[recovery_state]) |item| {
            \\        const root_index = try lrAppendRecoveryLineageNode(
            \\            allocator,
            \\            frames.items,
            \\            0,
            \\            recovery_items[item],
            \\            &lineage_nodes,
            \\        ) orelse continue;
            \\        try lineage_roots.append(allocator, root_index);
            \\    }
            \\    if (lineage_roots.items.len == 0) return null;
            \\    try lrBuildRecoveryLineage(allocator, frames.items, &lineage_nodes, &lineage_edges);
            \\    const lineage_productive = try allocator.alloc(bool, lineage_nodes.items.len);
            \\    defer allocator.free(lineage_productive);
            \\    try lrMarkRecoveryLineageProductive(allocator, lineage_nodes.items, lineage_edges.items, lineage_productive);
            \\    var saw_productive_lineage = false;
            \\    for (lineage_roots.items) |root_index| saw_productive_lineage = saw_productive_lineage or lineage_productive[root_index];
            \\    if (!saw_productive_lineage) return null;
            \\
            \\    var closure_candidates: std.ArrayList(LRRecoveryClosureCandidate) = .empty;
            \\    defer closure_candidates.deinit(allocator);
            \\    const closure_productive = try allocator.alloc(bool, recovery_items.len);
            \\    defer allocator.free(closure_productive);
            \\    try lrClosureMarkProductiveItems(allocator, recovery_state, closure_productive);
            \\    const closure_visits = try allocator.alloc(bool, recovery_items.len);
            \\    defer allocator.free(closure_visits);
            \\    for (lr_occurrence_recovery_scopes, 0..) |entry, source_order| {
            \\        var common = true;
            \\        var saw_productive_path = false;
            \\        @memset(closure_visits, false);
            \\        for (lr_recovery_kernel_items[recovery_state]) |item| {
            \\            const root_index = lrRecoveryLineageNodeIndex(lineage_nodes.items, 0, recovery_items[item]) orelse continue;
            \\            if (!lineage_productive[root_index] or !closure_productive[item]) continue;
            \\            saw_productive_path = true;
            \\            if (lrClosureHasProductivePathAvoidingOccurrence(
            \\                recovery_state,
            \\                item,
            \\                entry.occurrence,
            \\                closure_visits,
            \\            )) {
            \\                common = false;
            \\                break;
            \\            }
            \\        }
            \\        if (common and saw_productive_path) {
            \\            const depth = try lrClosureOccurrenceDepth(
            \\                allocator,
            \\                recovery_state,
            \\                frames.items,
            \\                closure_productive,
            \\                entry.occurrence,
            \\            ) orelse {
            \\                continue;
            \\            };
            \\            try closure_candidates.append(allocator, .{
            \\                .occurrence = entry.occurrence,
            \\                .depth = depth,
            \\                .source_order = source_order,
            \\            });
            \\        }
            \\    }
            \\    std.mem.sort(LRRecoveryClosureCandidate, closure_candidates.items, {}, lrRecoveryClosureCandidateLessThan);
            \\    for (closure_candidates.items) |candidate| {
            \\        const scope = lrOccurrenceRecoveryScope(candidate.occurrence) orelse unreachable;
            \\        const symbol = rules[candidate.occurrence.rule].right_hand_side[candidate.occurrence.position];
            \\        if (try lrTryExplicitScope(context, stack, scope, lrVariableForSymbol(symbol), 0)) |recovery| return recovery;
            \\    }
            \\
            \\    var lineage_candidates: std.ArrayList(LRRecoveryLineageCandidate) = .empty;
            \\    defer lineage_candidates.deinit(allocator);
            \\    var source_order: usize = 0;
            \\    for (lineage_nodes.items, 0..) |node, inner| {
            \\        if (!lineage_productive[inner]) continue;
            \\        const variable = rules[node.item.rule].header;
            \\        for (lineage_edges.items[node.first_edge..][0..node.edge_count]) |edge| {
            \\            if (!lineage_productive[edge.outer]) continue;
            \\            if (lrOccurrenceRecoveryScope(edge.occurrence)) |scope| {
            \\                try lrAppendRecoveryLineageCandidate(allocator, &lineage_candidates, .{
            \\                    .kind = .occurrence,
            \\                    .target = edge.occurrence.rule,
            \\                    .position = edge.occurrence.position,
            \\                    .scope = scope,
            \\                    .variable = variable,
            \\                    .unwind_count = node.unwind_count,
            \\                    .source_order = source_order,
            \\                });
            \\                source_order += 1;
            \\            }
            \\        }
            \\        if (node.item.head != 0) {
            \\            if (lrProductionRecoveryScope(node.item.rule)) |scope| {
            \\                try lrAppendRecoveryLineageCandidate(allocator, &lineage_candidates, .{
            \\                    .kind = .production,
            \\                    .target = node.item.rule,
            \\                    .scope = scope,
            \\                    .variable = variable,
            \\                    .unwind_count = node.unwind_count,
            \\                    .source_order = source_order,
            \\                });
            \\                source_order += 1;
            \\            }
            \\        }
            \\        if (lrLhsRecoveryScope(variable)) |scope| {
            \\            try lrAppendRecoveryLineageCandidate(allocator, &lineage_candidates, .{
            \\                .kind = .lhs,
            \\                .target = variable,
            \\                .scope = scope,
            \\                .variable = variable,
            \\                .unwind_count = node.unwind_count,
            \\                .source_order = source_order,
            \\            });
            \\            source_order += 1;
            \\        }
            \\    }
            \\
            \\    var committed_candidates: std.ArrayList(LRRecoveryLineageCandidate) = .empty;
            \\    defer committed_candidates.deinit(allocator);
            \\    const lineage_visits = try allocator.alloc(bool, lineage_nodes.items.len);
            \\    defer allocator.free(lineage_visits);
            \\    for (lineage_candidates.items) |candidate| {
            \\        @memset(lineage_visits, false);
            \\        var has_avoiding_path = false;
            \\        for (lineage_roots.items) |root_index| {
            \\            if (!lineage_productive[root_index]) continue;
            \\            if (lrRecoveryLineageHasAvoidingPath(
            \\                lineage_nodes.items,
            \\                lineage_edges.items,
            \\                lineage_productive,
            \\                root_index,
            \\                candidate,
            \\                lineage_visits,
            \\            )) {
            \\                has_avoiding_path = true;
            \\                break;
            \\            }
            \\        }
            \\        if (has_avoiding_path) continue;
            \\        var committed = candidate;
            \\        committed.depth = try lrRecoveryLineageCandidateDepth(
            \\            allocator,
            \\            lineage_nodes.items,
            \\            lineage_edges.items,
            \\            lineage_productive,
            \\            lineage_roots.items,
            \\            candidate,
            \\        ) orelse continue;
            \\        try committed_candidates.append(allocator, committed);
            \\    }
            \\    std.mem.sort(LRRecoveryLineageCandidate, committed_candidates.items, {}, lrRecoveryLineageCandidateLessThan);
            \\    for (committed_candidates.items) |candidate| {
            \\        if (try lrTryExplicitScope(
            \\            context,
            \\            stack,
            \\            candidate.scope,
            \\            candidate.variable,
            \\            candidate.unwind_count,
            \\        )) |recovery| return recovery;
            \\    }
            \\    return null;
            \\}
            \\
        );
        try self.emitExplicitRecoveryMetadata(writer);
    }

    fn emitExplicitRecoveryMetadata(self: *Generator, writer: *std.Io.Writer) !void {
        for (self.plan.states.items, 0..) |state, state_index| {
            const metadata = self.plan.recovery.explicit_metadata.items[state_index];
            try writer.print("const lr_recovery_items_{d} = &[_]LRRecoveryItem{{\n", .{state_index});
            for (state.items.items) |item| {
                try writer.writeAll("    ");
                try self.emitRecoveryItem(writer, item);
                try writer.writeAll(",\n");
            }
            try writer.writeAll("};\n");

            try writer.print("const lr_recovery_kernel_items_{d} = &[_]usize{{", .{state_index});
            for (metadata.kernel_items.items) |item_index| try writer.print(" {d},", .{item_index});
            try writer.writeAll(" };\n");

            try writer.print("const lr_recovery_closure_edges_{d} = &[_]LRRecoveryClosureEdge{{\n", .{state_index});
            for (metadata.closure_edges.items) |edge| {
                try writer.print(
                    "    .{{ .child = {d}, .parent = {d}, .occurrence = .{{ .rule = {d}, .position = {d} }} }},\n",
                    .{ edge.child, edge.parent, edge.occurrence.rule, edge.occurrence.position },
                );
            }
            try writer.writeAll("};\n");

            try writer.print("const lr_recovery_closure_edge_offsets_{d} = &[_]usize{{ 0,", .{state_index});
            var edge_index: usize = 0;
            for (state.items.items, 0..) |_, parent_index| {
                while (edge_index < metadata.closure_edges.items.len and metadata.closure_edges.items[edge_index].parent == parent_index) edge_index += 1;
                try writer.print(" {d},", .{edge_index});
            }
            try writer.writeAll(" };\n");

            try writer.print("const lr_recovery_closure_parents_{d} = &[_]usize{{", .{state_index});
            for (state.items.items, 0..) |_, child_index| {
                for (metadata.closure_edges.items) |edge| {
                    if (edge.child == child_index) try writer.print(" {d},", .{edge.parent});
                }
            }
            try writer.writeAll(" };\n");
            try writer.print("const lr_recovery_closure_parent_offsets_{d} = &[_]usize{{ 0,", .{state_index});
            var parent_count: usize = 0;
            for (state.items.items, 0..) |_, child_index| {
                for (metadata.closure_edges.items) |edge| {
                    if (edge.child == child_index) parent_count += 1;
                }
                try writer.print(" {d},", .{parent_count});
            }
            try writer.writeAll(" };\n");
        }

        try writer.writeAll("const lr_recovery_items = &[_][]const LRRecoveryItem{\n");
        for (self.plan.states.items, 0..) |_, state_index| try writer.print("    lr_recovery_items_{d},\n", .{state_index});
        try writer.writeAll("};\nconst lr_recovery_kernel_items = &[_][]const usize{\n");
        for (self.plan.states.items, 0..) |_, state_index| try writer.print("    lr_recovery_kernel_items_{d},\n", .{state_index});
        try writer.writeAll("};\nconst lr_recovery_closure_edges = &[_][]const LRRecoveryClosureEdge{\n");
        for (self.plan.states.items, 0..) |_, state_index| try writer.print("    lr_recovery_closure_edges_{d},\n", .{state_index});
        try writer.writeAll("};\nconst lr_recovery_closure_edge_offsets = &[_][]const usize{\n");
        for (self.plan.states.items, 0..) |_, state_index| try writer.print("    lr_recovery_closure_edge_offsets_{d},\n", .{state_index});
        try writer.writeAll("};\nconst lr_recovery_closure_parents = &[_][]const usize{\n");
        for (self.plan.states.items, 0..) |_, state_index| try writer.print("    lr_recovery_closure_parents_{d},\n", .{state_index});
        try writer.writeAll("};\nconst lr_recovery_closure_parent_offsets = &[_][]const usize{\n");
        for (self.plan.states.items, 0..) |_, state_index| try writer.print("    lr_recovery_closure_parent_offsets_{d},\n", .{state_index});
        try writer.writeAll("};\n\nconst lr_lhs_recovery_scopes = &[_]LRLhsRecoveryScope{\n");
        for (self.variables.items) |variable| {
            if (self.symbols.items[variable].annotations.recovery_points.items.len == 0) continue;
            try writer.print("    .{{ .variable = {d}, .scope = ", .{self.variableIndex(variable)});
            try self.emitLhsRecoveryScope(writer, variable);
            try writer.writeAll(" },\n");
        }
        try writer.writeAll("};\nconst lr_production_recovery_scopes = &[_]LRProductionRecoveryScope{\n");
        for (self.rules.items, 0..) |rule, rule_index| {
            if (rule.annotations.recovery_points.items.len == 0) continue;
            try writer.print("    .{{ .rule = {d}, .scope = ", .{rule_index});
            try self.emitProductionRecoveryScope(writer, rule, rule_index);
            try writer.writeAll(" },\n");
        }
        try writer.writeAll("};\nconst lr_occurrence_recovery_scopes = &[_]LROccurrenceRecoveryScope{\n");
        for (self.rules.items, 0..) |rule, rule_index| {
            for (rule.rhs_annotations.items, 0..) |annotations, position| {
                if (annotations.recovery_points.items.len == 0) continue;
                const occurrence: Occurrence = .{ .rule = rule_index, .position = position };
                try writer.print("    .{{ .occurrence = .{{ .rule = {d}, .position = {d} }}, .scope = ", .{ rule_index, position });
                try self.emitOccurrenceRecoveryScope(writer, occurrence);
                try writer.writeAll(" },\n");
            }
        }
        try writer.writeAll("};\n\n");
    }

    fn emitRecoveryItem(self: *Generator, writer: *std.Io.Writer, item: Item) !void {
        _ = self;
        try writer.print(".{{ .rule = {d}, .head = {d}, .lookahead = {d}, .procedure_occurrence = ", .{ item.rule, item.head, item.lookahead });
        if (item.occurrence) |occurrence| {
            try writer.print(".{{ .rule = {d}, .position = {d} }}", .{ occurrence.rule, occurrence.position });
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(" }");
    }

    fn emitExplicitSyntaxDiagnosticFlusher(self: *Generator, writer: *std.Io.Writer) !void {
        try writer.writeAll("fn lrFlushSyntaxDiagnostic(context: *data_structures.Context) !void {\n");
        try writer.print("    @setEvalBranchQuota({d});\n", .{@max(1000, self.plan.syntax_error_handlers.items.len * 8)});
        try writer.writeAll("    const site = context.pendingSyntaxErrorSite() orelse return;\n");
        try writer.writeAll("    context.clearPendingSyntaxErrorSite();\n");
        try writer.writeAll("    switch (site) {\n");
        for (self.plan.syntax_error_handlers.items, 0..) |spec, site_index| {
            try writer.print("        {d} => {{\n", .{site_index});
            try self.emitSyntaxErrorMessagePrint(writer, spec.error_function_name, "            ");
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

    fn emitOccurrenceRecoveryScope(self: *Generator, writer: *std.Io.Writer, occurrence: Occurrence) !void {
        const rule = self.rules.items[occurrence.rule];
        const variable = rule.rhs.items[occurrence.position];
        const target_id = (self.plan.recovery.scopes.findOccurrence(occurrence.rule, occurrence.position) orelse unreachable).id;
        try writer.print("&ExplicitRecoveryScope{{ .id = {d}, .target = .{{ .occurrence = .{{ .parent_variable = ", .{target_id});
        try emitStringLiteral(writer, self.symbols.items[rule.header].id);
        try writer.print(", .rhs_index = {s}, .symbol_index = {d}, .variable = ", .{ rule.rhs_index, occurrence.position });
        try emitStringLiteral(writer, self.symbols.items[variable].id);
        try writer.writeAll(" } }, .points = ");
        try emitter_common.emitRecoveryPoints(writer, rule.rhs_annotations.items[occurrence.position].recovery_points.items);
        try writer.writeAll(" }");
    }

    fn emitSyntaxErrorHandlers(self: *Generator, writer: *std.Io.Writer) !void {
        if (!self.options.with_error_recovery) {
            try self.emitFailFastSyntaxErrorSupport(writer);
        }
        for (self.plan.syntax_error_handlers.items, 0..) |spec, site_index| {
            const parameters = if (!self.options.with_error_recovery)
                ""
            else if (self.uses_explicit_recovery)
                ", stack: *SemanticStack, recovery_frame: *const LRRecoveryFrame"
            else
                ", stack: *SemanticStack";
            const return_type = if (!self.options.with_error_recovery)
                "ReduceResult"
            else if (self.uses_explicit_recovery)
                "?ExplicitRecoveryResult"
            else
                "bool";
            try writer.print("{s}fn {s}(context: *data_structures.Context{s}) anyerror!{s} {{\n", .{
                if (!self.options.with_error_recovery) "noinline " else "",
                spec.name,
                parameters,
                return_type,
            });
            try writer.writeAll("    @branchHint(.cold);\n");
            if (!self.options.with_error_recovery) {
                try writer.print("    return lrFailFastSyntaxError(context, .{{ .state = {d} }}, &[_][]const u8{{", .{spec.state_index});
                try self.emitStringSliceItems(writer, spec.expected_tokens);
                try writer.print("}}, {s}_message);\n}}\n", .{spec.name});
                try self.emitFailFastSyntaxErrorMessageRenderer(writer, spec);
                continue;
            }
            if (self.uses_explicit_recovery) {
                try writer.print("    try context.recordSyntaxDiagnostic(.{{ .state = {d} }}, &[_][]const u8{{", .{spec.state_index});
                try self.emitStringSliceItems(writer, spec.expected_tokens);
                try writer.writeAll("});\n");
                try writer.print("    context.setPendingSyntaxErrorSite({d});\n", .{site_index});
                if (spec.recoverable) {
                    try writer.writeAll("    if (try lrTryExplicitRecovery(context, stack, recovery_frame)) |recovery| return recovery;\n");
                } else {
                    try writer.writeAll("    _ = stack;\n    _ = recovery_frame;\n");
                }
                try writer.writeAll("    try lrFlushSyntaxDiagnostic(context);\n");
                try writer.writeAll("    return null;\n}\n\n");
                continue;
            }
            if (!spec.recoverable or (!self.options.with_ast and !self.options.with_procedures) or spec.state_index == 0) try writer.writeAll("    _ = stack;\n");
            try writer.writeAll("    const report_syntax_error = context.beginSyntaxRecovery();\n");
            try writer.writeAll("    if (report_syntax_error) {\n");
            try writer.print("        try context.recordSyntaxDiagnostic(.{{ .state = {d} }}, &[_][]const u8{{", .{spec.state_index});
            try self.emitStringSliceItems(writer, spec.expected_tokens);
            try writer.writeAll("});\n");
            try self.emitSyntaxErrorMessagePrint(writer, spec.error_function_name, "        ");
            try writer.writeAll("    }\n");
            try writer.writeAll("    if (report_syntax_error and context.syntaxErrorLimitReached()) return root.ParseError.SyntaxError;\n");
            if (spec.recoverable) {
                try writer.print("    if (try lrRecoveryOffset(context, lr_recovery_candidates_{d}, if (report_syntax_error) 1 else 0)) |recovery_offset| {{\n", .{spec.state_index});
                try writer.writeAll("        context.skipRecoveryInput(recovery_offset);\n");
                try writer.writeAll("        return true;\n");
                try writer.writeAll("    }\n");
                try writer.writeAll("    if (context.head(u8, 0) == 0) return root.ParseError.SyntaxError;\n");
                if ((self.options.with_ast or self.options.with_procedures or self.uses_verbatim) and spec.state_index != 0) {
                    try writer.writeAll("    _ = stack.pop() orelse unreachable;\n");
                }
                try writer.writeAll("    return false;\n");
            } else {
                try writer.writeAll("    return root.ParseError.SyntaxError;\n");
            }
            try writer.writeAll("}\n\n");
        }
    }

    fn emitFailFastSyntaxErrorSupport(self: *Generator, writer: *std.Io.Writer) !void {
        _ = self;
        try writer.writeAll(
            \\const LRFailFastMessageRenderer = *const fn (root.SyntaxErrorMessageArgs) anyerror![]const u8;
            \\
            \\fn lrFailFastSyntaxError(
            \\    context: *data_structures.Context,
            \\    diagnostic_context: root.SyntaxDiagnosticContext,
            \\    expected_tokens: []const []const u8,
            \\    render_message: LRFailFastMessageRenderer,
            \\) anyerror {
            \\    @branchHint(.cold);
            \\    context.recordSyntaxDiagnostic(diagnostic_context, expected_tokens) catch |err| return err;
            \\    const diagnostic_message = render_message(.{
            \\        .allocator = context.runtime().arena_allocator,
            \\        .context = context,
            \\        .diagnostic = context.runtime().last_diagnostic.?,
            \\        .style = .ansi,
            \\    }) catch "";
            \\    if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
            \\    return root.ParseError.SyntaxError;
            \\}
            \\
            \\fn lrFailFastDefaultMessage(args: root.SyntaxErrorMessageArgs) anyerror![]const u8 {
            \\    if (comptime @hasDecl(error_messages, "syntax_error_lr"))
            \\        return error_messages.syntax_error_lr(args);
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
            \\fn {s}_message(args: root.SyntaxErrorMessageArgs) anyerror![]const u8 {{
            \\    if (comptime @hasDecl(error_messages, "{s}"))
            \\        return @field(error_messages, "{s}")(args);
            \\    return lrFailFastDefaultMessage(args);
            \\}}
            \\
        , .{
            spec.name,
            spec.error_function_name,
            spec.error_function_name,
        });
    }

    fn emitStringSliceItems(self: *Generator, writer: *std.Io.Writer, items: []const []const u8) !void {
        _ = self;
        for (items, 0..) |item, index| {
            if (index != 0) try writer.writeAll(", ");
            try emitStringLiteral(writer, item);
        }
    }

    fn emitSyntaxErrorMessagePrint(self: *Generator, writer: *std.Io.Writer, function_name: []const u8, indent: []const u8) !void {
        _ = self;
        try writer.print(
            \\{s}const diagnostic = context.runtime().last_diagnostic.?;
            \\{s}const message_args = root.SyntaxErrorMessageArgs{{
            \\{s}    .allocator = context.runtime().arena_allocator,
            \\{s}    .context = context,
            \\{s}    .diagnostic = diagnostic,
            \\{s}    .style = .ansi,
            \\{s}}};
            \\{s}const diagnostic_message = if (comptime @hasDecl(error_messages, "{s}"))
            \\{s}    @field(error_messages, "{s}")(message_args) catch ""
            \\{s}else if (comptime @hasDecl(error_messages, "syntax_error_lr"))
            \\{s}    error_messages.syntax_error_lr(message_args) catch ""
            \\{s}else if (comptime @hasDecl(error_messages, "syntax_error"))
            \\{s}    error_messages.syntax_error(message_args) catch ""
            \\{s}else
            \\{s}    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
            \\{s}if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{{s}}", .{{diagnostic_message}});
            \\
        , .{
            indent,
            indent,
            indent,
            indent,
            indent,
            indent,
            indent,
            indent,
            function_name,
            indent,
            function_name,
            indent,
            indent,
            indent,
            indent,
            indent,
            indent,
            indent,
        });
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

    fn symbolReturnsStackNode(self: *Generator, symbol_index: usize) bool {
        return self.plan.symbol_returns_stack_node[symbol_index];
    }

    fn variableIndex(self: *Generator, symbol_index: usize) usize {
        return self.plan.variable_indices[symbol_index] orelse unreachable;
    }

    fn longestTerminalLength(self: *Generator) usize {
        return self.plan.longest_terminal_length;
    }
};

pub fn emit(
    allocator: std.mem.Allocator,
    grammar: *const common.PreparedGrammar,
    plan: *const LRPlan,
    writer: *std.Io.Writer,
    options: Options,
) !void {
    var generator = Generator.init(allocator, options, grammar, plan);
    try generator.emit(writer);
}
