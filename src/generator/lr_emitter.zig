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
    has_recovery_annotations: bool,
    uses_verbatim: bool,
    end_symbol: usize,
    augmented_start: usize,
    generative_terminal: ?usize,

    fn init(allocator: std.mem.Allocator, options: Options, grammar: *const common.PreparedGrammar, plan: *const LRPlan) Generator {
        return .{
            .allocator = allocator,
            .options = options,
            .symbols = grammar.symbols,
            .variables = grammar.variables,
            .rules = grammar.rules,
            .plan = plan,
            .uses_explicit_recovery = grammar.uses_explicit_recovery,
            .has_recovery_annotations = grammar.has_recovery_annotations,
            .uses_verbatim = grammar.uses_verbatim,
            .end_symbol = grammar.eof,
            .augmented_start = grammar.augmented_start,
            .generative_terminal = grammar.generative_terminal,
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
            "lr",
            self.has_recovery_annotations,
            self.longestTerminalLength(),
            self.uses_verbatim,
            false,
        );
        try emitter_common.emitGrammarTables(writer, self.symbols.items, self.variables.items, self.rules.items, self.end_symbol);
        // Recovery/procedure support is emitted unconditionally: which style
        // or feature-set is active is selected at comptime per configuration
        // (LL parity), and unused support folds away under lazy analysis.
        try emitter_common.emitRecoveryOffsetFunction(writer, "lrRecoveryOffset");
        try emitter_common.emitProcedureSupport(self.allocator, writer, self.rules.items, self.symbols.items, self.variables.items, self.augmented_start, self.generative_terminal);

        try writer.writeAll(
            \\const ReduceResult = struct {
            \\    variable: u16,
            \\    pops_remaining: u16,
            \\    is_accept: bool,
            \\    // Unconditional with a default: recovery styles that never mark
            \\    // results still construct this type, and omitted fields keep
            \\    // every configuration's constructions valid.
            \\    is_recovery: bool = false,
            \\
            \\};
            \\
            \\// The semantic value's `node` payload is comptime-typed per
            \\// configuration: a tree address under AST builds, an optional
            \\// temporary node under procedure-only builds, and nothing when
            \\// neither feature is enabled. Defaults keep position-only
            \\// constructions legal everywhere.
            \\const NodeFieldType =
            \\    if (is_ast_enabled)
            \\        data_structures.Node.Pointer
            \\    else if (are_procedures_enabled)
            \\        ?data_structures.Node
            \\    else
            \\        void;
            \\const node_field_default: NodeFieldType =
            \\    if (NodeFieldType == data_structures.Node.Pointer)
            \\        data_structures.Node.invalid_pointer
            \\    else if (NodeFieldType == ?data_structures.Node)
            \\        null
            \\    else {};
            \\const SemanticValue = struct {
            \\    start_pos: usize,
            \\    node: NodeFieldType = node_field_default,
            \\};
            \\
            \\// One handler return vocabulary across all recovery styles; each
            \\// style resolves it to its own contract at comptime.
            \\
        );
        if (!self.uses_explicit_recovery) {
            try writer.writeAll("const SyntaxHandlerReturn = if (error_recovery_mode == .disabled) anyerror!ReduceResult else anyerror!bool;\n\n");
        } else {
            try writer.writeAll(
                \\const SyntaxHandlerReturn =
                \\    if (error_recovery_mode == .disabled)
                \\        anyerror!ReduceResult
                \\    else if (error_recovery_mode == .explicit)
                \\        anyerror!?ExplicitRecoveryResult
                \\    else
                \\        anyerror!bool;
                \\
                \\
            );
        }
        try writer.writeAll(
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
        // Fact-gated only: automatic-mode candidate tables exist whenever the
        // grammar uses automatic recovery, independent of configuration.
        if (!self.uses_explicit_recovery) try self.emitStateRecoveryCandidateTables(writer);
        try self.emitSyntaxErrorHandlers(writer);
        if (self.uses_explicit_recovery) try self.emitExplicitSyntaxDiagnosticFlusher(writer);

        try writer.writeAll(
            \\pub fn parseWithResult(context: *data_structures.Context) !root.ParseResult {
            \\    var stack = SemanticStack{ .allocator = context.runtime().arena_allocator };
            \\    defer stack.deinit();
            \\
            \\
        );
        // Under explicit-recovery grammars the unified state-function
        // signature takes a frame argument in every style; only the explicit
        // style has a real frame to thread.
        if (self.uses_explicit_recovery) {
            try writer.writeAll(
                \\    const result = if (comptime error_recovery_mode == .explicit) blk: {
                \\        const recovery_root = LRRecoveryFrame{ .parent = null, .state = 0, .incoming_symbol = null };
                \\        break :blk try state_0(context, &stack, &recovery_root);
                \\    } else try state_0(context, &stack, null);
                \\
            );
        } else {
            try writer.writeAll("    const result = try state_0(context, &stack);\n");
        }
        try writer.writeAll(
            \\    if (comptime error_recovery_mode == .disabled) {
            \\        if (!result.is_accept) {
            \\            return root.ParseError.SyntaxError;
            \\        }
            \\    } else {
            \\        if (result.is_recovery or !result.is_accept) {
            \\            return root.ParseError.SyntaxError;
            \\        }
            \\        if (context.hasSyntaxErrors()) return root.ParseError.SyntaxError;
            \\    }
            \\    if (context.verbosityLevel() > 0) {
            \\        std.log.info("The input file was parsed successfully!", .{});
            \\    }
            \\
            \\    const ast_root = if (comptime is_ast_enabled)
            \\        (if (stack.storage.items[stack.storage.items.len - 1].node != data_structures.Node.invalid_pointer)
            \\            stack.storage.items[stack.storage.items.len - 1].node
            \\        else
            \\            null)
            \\    else
            \\        null;
            \\    const semantic_root =
            \\        if (comptime !is_ast_enabled and are_procedures_enabled)
            \\            (if (stack.storage.items[stack.storage.items.len - 1].node) |node| node.payload else null)
            \\        else if (comptime is_ast_enabled and are_procedures_enabled)
            \\            (if (ast_root) |address| context.node_allocator.at(address).payload else null)
            \\        else {};
            \\
        );
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
        // Cold fail-fast support at the very end so the large
        // `lrFailFastDefaultMessage` (session → config → hooks chain) does
        // not sit between the hot state functions and displace them.
        try self.emitFailFastSyntaxErrorSupport(writer);
    }

    const StateBody = struct {
        state: State,
        state_index: usize,
    };

    /// Emits one state parser with a configuration-unified signature: the
    /// optional recovery-frame parameter exists whenever the grammar carries
    /// explicit-recovery annotations (a grammar fact), typed optional so
    /// every recovery style can supply an argument. Which shape the body
    /// takes is decided at comptime per configuration.
    fn emitStateFunction(self: *Generator, writer: *std.Io.Writer, state: State, state_index: usize) !void {
        try writer.print("// LR parser state {d}\nfn state_{d}(context: *data_structures.Context, stack: *SemanticStack", .{ state_index, state_index });
        if (self.uses_explicit_recovery) try writer.writeAll(", recovery_frame: ?*const LRRecoveryFrame");
        try writer.writeAll(") anyerror!ReduceResult {\n");
        try emitter_common.emitModeGatedBody(Generator, self, writer, StateBody, .{ .state = state, .state_index = state_index }, false, renderStateBody);
        try writer.writeAll("}\n");
    }

    /// Shared goto-dispatch emission for state bodies. `syntax_error_indent`
    /// positions the empty-gotos diagnostic; `line_indent` positions the
    /// switch itself and its arms. Frame threading follows the active
    /// configuration: explicit-style states chain child frames, styles
    /// without frames pass null (the parameter exists by grammar fact).
    fn emitStateGotos(
        self: *Generator,
        writer: *std.Io.Writer,
        state: State,
        diagnostic: ?usize,
        syntax_error_indent: []const u8,
        line_indent: []const u8,
    ) !void {
        if (state.gotos.items.len == 0) {
            try self.emitStateSyntaxError(writer, diagnostic.?, syntax_error_indent);
            return;
        }
        try writer.print("{s}result = switch (result.variable) {{\n", .{line_indent});
        const thread_frames = self.options.with_error_recovery and self.uses_explicit_recovery;
        for (state.gotos.items) |goto| {
            const variable_index = self.variableIndex(goto.variable);
            const symbol_id = self.symbols.items[goto.variable].id;
            if (thread_frames) {
                try writer.print(
                    "{s}{d} => next: {{ const next_recovery_frame = LRRecoveryFrame{{ .parent = recovery_frame, .state = {d}, .incoming_symbol = {d} }}; break :next try state_{d}(context, stack, &next_recovery_frame); }}, // {s}\n",
                    .{ line_indent, variable_index, goto.state, goto.variable, goto.state, symbol_id },
                );
            } else if (self.uses_explicit_recovery) {
                try writer.print("{s}{d} => try state_{d}(context, stack, null), // {s}\n", .{ line_indent, variable_index, goto.state, symbol_id });
            } else {
                try writer.print("{s}{d} => try state_{d}(context, stack), // {s}\n", .{ line_indent, variable_index, goto.state, symbol_id });
            }
        }
        try writer.print("{s}else => unreachable,\n{s}}};\n", .{ line_indent, line_indent });
        // Automatic-style retry loopback exists only where a goto dispatch
        // can produce a marked result; the empty-gotos diagnostic above
        // always diverts control itself.
        if (self.options.with_error_recovery and !self.uses_explicit_recovery) {
            try writer.print("{s}if (result.is_recovery) continue :state_recovery;\n", .{line_indent});
        }
    }

    fn renderStateBody(self: *Generator, writer: *std.Io.Writer, params: StateBody) !void {
        const state = params.state;
        const state_index = params.state_index;
        // Silencer that stays legal whether or not this variant touches the
        // semantic stack.
        try writer.writeAll("    _ = &stack;\n");
        if (self.uses_explicit_recovery and !(self.options.with_error_recovery and self.uses_explicit_recovery)) {
            try writer.writeAll("    _ = &recovery_frame;\n");
        }

        const decision = self.plan.state_decisions.items[state_index];

        if (!self.options.with_error_recovery) {
            try writer.writeAll("    var result: ReduceResult = undefined;\n");
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
            try self.emitStateGotos(writer, state, decision.goto_diagnostic, "        ", "            ");
            try writer.writeAll("    }\n");
            return;
        }

        if (self.uses_explicit_recovery) {
            try writer.writeAll("    while (true) {\n");
        } else {
            try writer.writeAll("    state_recovery: while (true) {\n");
        }
        try writer.writeAll("        var result: ReduceResult = undefined;\n");

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
        try self.emitStateGotos(writer, state, decision.goto_diagnostic, "            ", "                ");
        try writer.writeAll("        }\n    }\n");
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
                try self.emitAction(writer, state.actions.items[group.child.fallback.?], group.child.fallback_length orelse prefix_length + step_length, try indented(self.allocator, indent, 8));
            } else {
                try self.emitActionSwitch(writer, state, group.child, prefix_length + step_length, try indented(self.allocator, indent, 8));
                try writer.writeByte('\n');
            }
            try writer.print("{s}    }},\n", .{indent});
        }
        if (node.fallback) |action| {
            try writer.print("{s}    else => {{\n", .{indent});
            try self.emitAction(writer, state.actions.items[action], node.fallback_length orelse prefix_length, try indented(self.allocator, indent, 8));
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
                    \\{s}return ReduceResult{{ .variable = 0, .pops_remaining = 0, .is_accept = true }};
                    \\
                , .{ indent, indent, indent, indent, indent, indent });
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
                    const verbatim_literal = if (action.occurrence) |o|
                        self.rules.items[o.rule].rhs_annotations.items[o.position].verbatim_literal
                    else
                        null;
                    const verbatim_consume = if (action.occurrence) |o|
                        self.rules.items[o.rule].rhs_annotations.items[o.position].verbatim_consume
                    else
                        true;
                    try self.emitVerbatimShiftCapture(writer, action.terminal, verbatim_literal, verbatim_consume, indent);
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
                if (self.options.with_error_recovery and self.uses_explicit_recovery) {
                    try writer.print("{s}const next_recovery_frame = LRRecoveryFrame{{ .parent = recovery_frame, .state = {d}, .incoming_symbol = {d} }};\n", .{ indent, action.state, action.terminal });
                    try writer.print("{s}result = try state_{d}(context, stack, &next_recovery_frame);\n", .{ indent, action.state });
                } else if (self.uses_explicit_recovery) {
                    try writer.print("{s}result = try state_{d}(context, stack, null);\n", .{ indent, action.state });
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
        try emitter_common.emitRuleSymbolsForDebug(writer, self.symbols.items, rule);
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
                try self.emitVerbatimReduceCapture(writer, occurrence, if (occurrence) |o| self.rules.items[o.rule].rhs_annotations.items[o.position].verbatim_literal else null, if (occurrence) |o| self.rules.items[o.rule].rhs_annotations.items[o.position].verbatim_consume else true, indent);
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

        try emitter_common.emitDebugReduction(writer, self.symbols.items, rule, indent);
        try writer.print("{s}{s} ReduceResult{{ .variable = {d}, .pops_remaining = {d}, .is_accept = false }};\n", .{
            indent,
            if (rhs_len > 0) "return" else "result =",
            variable_index,
            if (rhs_len > 0) rhs_len - 1 else 0,
        });
    }

    fn emitProcedureBlock(self: *Generator, writer: *std.Io.Writer, rule_index: usize, parent_variable: usize, occurrence: ?Occurrence, node_expr: []const u8, indent: []const u8) !void {
        const rule = self.rules.items[rule_index];
        const variable_index = self.variableIndex(parent_variable);
        try emitter_common.emitProcedureArgsStruct(writer, indent, self.options.with_ast, rule_index, node_expr, false);
        try emitter_common.emitProcedureRunCall(writer, indent);
        try self.emitOccurrenceExpression(writer, occurrence);
        try writer.writeAll(", &args);\n");
        try emitter_common.emitProcedureRuleSequenceCall(writer, indent, rule.annotations.procedures.items);
        try emitter_common.emitProcedureDispatchTail(writer, indent, rule_index, variable_index, parent_variable, null);
    }

    fn emitTerminalProcedureBlock(self: *Generator, writer: *std.Io.Writer, terminal_index: usize, occurrence: ?Occurrence, node_expr: []const u8, indent: []const u8) !void {
        try emitter_common.emitProcedureArgsStruct(writer, indent, self.options.with_ast, null, node_expr, false);
        try emitter_common.emitProcedureRunCall(writer, indent);
        try self.emitOccurrenceExpression(writer, occurrence);
        try writer.writeAll(", &args);\n");
        try emitter_common.emitProcedureDispatchTail(writer, indent, null, null, null, terminal_index);
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

    fn emitVerbatimShiftCapture(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, verbatim_literal: ?[]const u8, verbatim_consume: bool, indent: []const u8) !void {
        const symbol = self.symbols.items[symbol_index];
        if (verbatim_literal) |literal| {
            try writer.print("{s}try context.captureVerbatim(", .{indent});
            try common.emitStringLiteral(writer, literal);
            try writer.print(", {s});\n", .{if (verbatim_consume) "true" else "false"});
        } else if (symbol.kind == .terminal) {
            try writer.print("{s}try context.captureVerbatim(", .{indent});
            try common.emitStringLiteral(writer, symbol.id);
            try writer.writeAll(", true);\n");
        } else {
            try writer.print("{s}const verbatim_terminator = context.getTextSlice(start_pos, context.currentTokenSourceOffset() - start_pos);\n", .{indent});
            try writer.print("{s}try context.captureVerbatim(verbatim_terminator, true);\n", .{indent});
        }
    }

    fn emitVerbatimReduceCapture(self: *Generator, writer: *std.Io.Writer, occurrence: ?Occurrence, verbatim_literal: ?[]const u8, verbatim_consume: bool, indent: []const u8) !void {
        const value = occurrence.?;
        const symbol_index = self.rules.items[value.rule].rhs.items[value.position];
        if (self.symbols.items[symbol_index].kind != .variable) return;
        if (verbatim_literal == null) {
            try writer.print("{s}const verbatim_terminator = context.getTextSlice(start_pos, context.currentTokenSourceOffset() - start_pos);\n", .{indent});
        }
        if (self.options.with_ast or self.options.with_procedures) {
            try writer.print("{s}const verbatim_end = context.currentTokenSourceOffset();\n", .{indent});
        }
        if (verbatim_literal) |literal| {
            try writer.print("{s}try context.captureVerbatim(", .{indent});
            try common.emitStringLiteral(writer, literal);
            try writer.print(", {s});\n", .{if (verbatim_consume) "true" else "false"});
        } else {
            try writer.print("{s}try context.captureVerbatim(verbatim_terminator, true);\n", .{indent});
        }
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
            // The unified handler signature always takes the semantic stack
            // (and a null frame under explicit-recovery grammars).
            try writer.print("{s}return {s}(context, stack{s});\n", .{
                indent,
                spec.name,
                if (self.uses_explicit_recovery) ", null" else "",
            });
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
        try emitter_common.emitExplicitRecoveryScopeStruct(writer);
        try writer.writeAll(
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
        // Whether the explicit-recovery unwind tracks captured positions
        // follows from the active configuration, decided at comptime in the
        // generated file; the verbatim half is a grammar fact resolved here.
        const unwind_condition = if (self.uses_verbatim)
            "is_ast_enabled or are_procedures_enabled or uses_verbatim"
        else
            "is_ast_enabled or are_procedures_enabled";
        try writer.print("    if (comptime {s}) {{\n", .{unwind_condition});
        try writer.writeAll(
            \\        var start_pos = context.currentTokenSourceOffset();
            \\        for (0..unwind_count) |_| {
            \\            const discarded = stack.pop() orelse unreachable;
            \\            start_pos = discarded.start_pos;
            \\        }
            \\        try stack.append(.{ .start_pos = start_pos });
            \\    } else {
            \\        // Address-take silencer: sibling gated branches of other
            \\        // functions may use the stack; a plain discard would read
            \\        // as pointless against any such use.
            \\        _ = &stack;
            \\    }
        );
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
            try emitter_common.emitLhsRecoveryScope(writer, &self.plan.recovery.scopes, self.symbols.items, variable);
            try writer.writeAll(" },\n");
        }
        try writer.writeAll("};\nconst lr_production_recovery_scopes = &[_]LRProductionRecoveryScope{\n");
        for (self.rules.items, 0..) |rule, rule_index| {
            if (rule.annotations.recovery_points.items.len == 0) continue;
            try writer.print("    .{{ .rule = {d}, .scope = ", .{rule_index});
            try emitter_common.emitProductionRecoveryScope(writer, &self.plan.recovery.scopes, self.symbols.items, rule, rule_index);
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

    const HandlerBody = struct {
        spec: SyntaxErrorHandlerSpec,
        site_index: usize,
    };

    const BodyRecoveryMode = emitter_common.BodyRecoveryMode;

    fn bodyRecoveryMode(self: *const Generator) BodyRecoveryMode {
        if (!self.options.with_error_recovery) return .disabled;
        return if (self.uses_explicit_recovery) .explicit else .automatic;
    }

    fn emitSyntaxErrorHandlers(self: *Generator, writer: *std.Io.Writer) !void {
        for (self.plan.syntax_error_handlers.items, 0..) |spec, site_index| {
            // One configuration-unified signature: the return vocabulary is
            // resolved per recovery style by `SyntaxHandlerReturn`, and the
            // optional recovery-frame parameter exists by grammar fact so
            // every style can supply an argument.
            try writer.print("\nnoinline fn {s}(context: *data_structures.Context, stack: *SemanticStack", .{spec.name});
            if (self.uses_explicit_recovery) try writer.writeAll(", recovery_frame: ?*const LRRecoveryFrame");
            try writer.writeAll(") linksection(if (builtin.os.tag == .macos) \"__TEXT,__unlikely\" else \".text.unlikely\") SyntaxHandlerReturn {\n");
            try writer.writeAll("    @branchHint(.cold);\n");
            try emitter_common.emitModeGatedBody(Generator, self, writer, HandlerBody, .{ .spec = spec, .site_index = site_index }, false, renderHandlerBody);
            try writer.writeAll("}\n");
            try self.emitFailFastSyntaxErrorMessageRenderer(writer, spec);
        }
    }

    fn renderHandlerBody(self: *Generator, writer: *std.Io.Writer, params: HandlerBody) !void {
        const spec = params.spec;
        const site_index = params.site_index;
        // Recovery styles this grammar can never select are comptime-
        // unreachable; a stub keeps the gate chain exhaustive without
        // touching mode-specific tables that do not exist for this grammar.
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
            try writer.writeAll("    _ = &stack;\n");
            if (self.uses_explicit_recovery) try writer.writeAll("    _ = &recovery_frame;\n");
            try writer.print("    return lrFailFastSyntaxError(context, .{{ .state = {d} }}, &[_][]const u8{{", .{spec.state_index});
            try self.emitStringSliceItems(writer, spec.expected_tokens);
            try writer.print("}}, {s}_message);\n", .{spec.name});
            return;
        }
        if (self.uses_explicit_recovery) {
            try writer.print("    try context.recordSyntaxDiagnostic(.{{ .state = {d} }}, &[_][]const u8{{", .{spec.state_index});
            try self.emitStringSliceItems(writer, spec.expected_tokens);
            try writer.writeAll("});\n");
            try writer.print("    context.setPendingSyntaxErrorSite({d});\n", .{site_index});
            if (spec.recoverable) {
                try writer.writeAll("    if (try lrTryExplicitRecovery(context, stack, recovery_frame.?)) |recovery| return recovery;\n");
            } else {
                try writer.writeAll("    _ = &stack;\n    _ = &recovery_frame;\n");
            }
            try writer.writeAll("    try lrFlushSyntaxDiagnostic(context);\n");
            try writer.writeAll("    return null;\n");
            return;
        }
        const pops_stack = spec.recoverable and spec.state_index != 0 and (self.options.with_ast or self.options.with_procedures or self.uses_verbatim);
        // Address-take silencer: other gated branches of this function may
        // touch the stack, so a plain discard would read as pointless.
        if (!pops_stack) try writer.writeAll("    _ = &stack;\n");
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
    }

    fn emitFailFastSyntaxErrorSupport(self: *Generator, writer: *std.Io.Writer) !void {
        _ = self;
        try emitter_common.emitFailFastSyntaxErrorSupport(writer, "lr", "LR", "syntax_error_lr");
    }

    fn emitFailFastSyntaxErrorMessageRenderer(
        self: *Generator,
        writer: *std.Io.Writer,
        spec: SyntaxErrorHandlerSpec,
    ) !void {
        _ = self;
        try emitter_common.emitFailFastMessageRenderer(writer, spec.name, &.{spec.error_function_name}, "lrFailFastDefaultMessage");
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
        try writer.print("{s}const diagnostic = context.runtime().lastDiagnostic().?;\n", .{indent});
        try writer.print(
            "{s}const diagnostic_message = root.resolveSyntaxErrorMessage(context, diagnostic, config.error_messages, error_messages, .{{ \"{s}\", \"syntax_error_lr\", \"syntax_error\" }}) orelse root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .plain) catch \"\";\n",
            .{ indent, function_name },
        );
        try writer.print(
            "{s}context.runtime().last_rendered_message = diagnostic_message;\n{s}if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print(\"{{s}}\", .{{diagnostic_message}});\n",
            .{ indent, indent },
        );
    }

    fn symbolReturnsStackNode(self: *Generator, symbol_index: usize) bool {
        // Derived per configuration (LL parity): mode-gated renders call this
        // under combo-mutated options, so linkage follows the active config
        // rather than values frozen at plan time.
        return common.symbolReturnsNode(self.symbols.items[symbol_index], self.options);
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
