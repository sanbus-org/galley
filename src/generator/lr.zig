const std = @import("std");
const common = @import("generator_common");

pub const Options = common.Options;
const SymbolKind = common.SymbolKind;
const Symbol = common.Symbol;
const Rule = common.Rule;
const ErrorMessageSpec = common.ErrorMessageSpec;
const bytesToInt = common.bytesToInt;
const emitEscapedForComment = common.emitEscapedForComment;
const emitFormatToken = common.emitFormatToken;
const emitStringLiteral = common.emitStringLiteral;
const indented = common.indented;

const Item = struct {
    variable: usize,
    rule: usize,
    head: usize,
    lookahead: usize,
    occurrence: ?Occurrence = null,
};

const Occurrence = struct {
    rule: usize,
    position: usize,
};

const ActionKind = enum { shift, reduce, accept };

const Action = struct {
    terminal: usize,
    kind: ActionKind,
    state: usize = 0,
    rule: usize = 0,
    occurrence: ?Occurrence = null,
};

const GotoEntry = struct {
    variable: usize,
    state: usize,
};

const State = struct {
    items: std.ArrayList(Item) = .empty,
    actions: std.ArrayList(Action) = .empty,
    gotos: std.ArrayList(GotoEntry) = .empty,
};

const Generator = struct {
    allocator: std.mem.Allocator,
    options: Options,
    symbols: std.ArrayList(Symbol) = .empty,
    variables: std.ArrayList(usize) = .empty,
    rules: std.ArrayList(Rule) = .empty,
    states: std.ArrayList(State) = .empty,
    error_message_specs: std.ArrayList(ErrorMessageSpec) = .empty,
    syntax_error_handlers: std.ArrayList(SyntaxErrorHandlerSpec) = .empty,
    syntax_error_site_index: usize = 0,
    augmented_start: usize = 0,
    eof: usize = 0,
    has_recovery_annotations: bool = false,
    uses_explicit_recovery: bool = false,

    const SyntaxErrorHandlerSpec = struct {
        name: []const u8,
        state_index: usize,
        expected_tokens: []const []const u8,
        error_function_name: []const u8,
        recoverable: bool,
    };

    const SyntaxErrorSite = enum {
        action,
        state,
        goto,
    };

    fn init(allocator: std.mem.Allocator, options: Options) Generator {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }

    fn addSymbol(self: *Generator, id: []const u8, kind: SymbolKind) !usize {
        return common.addSymbol(self.allocator, &self.symbols, &self.variables, id, kind);
    }

    fn fromGrammar(self: *Generator, grammar: anytype) !void {
        try common.validateGrammar(grammar);
        self.has_recovery_annotations = common.grammarHasRecoveryPoints(grammar);
        self.uses_explicit_recovery = self.options.with_error_recovery and self.has_recovery_annotations;
        var rhs_counts = std.AutoHashMap(usize, usize).init(self.allocator);
        defer rhs_counts.deinit();

        for (grammar.rules) |rule| {
            const header = try self.addSymbol(rule.header, .variable);
            try common.appendAnnotations(self.allocator, &self.symbols.items[header].annotations, rule.annotations);
            for (rule.right_hand_sides) |rhs| {
                const rhs_index = rhs_counts.get(header) orelse 0;
                try rhs_counts.put(header, rhs_index + 1);

                var generated_rule = Rule{
                    .header = header,
                    .rhs_index = try std.fmt.allocPrint(self.allocator, "{d}", .{rhs_index}),
                };
                try common.appendAnnotations(self.allocator, &generated_rule.annotations, rhs.annotations);
                for (rhs.symbols) |symbol| {
                    const kind: SymbolKind = switch (symbol.kind) {
                        .variable => .variable,
                        .terminal => .terminal,
                        .generative_terminal => .generative_terminal,
                    };
                    try generated_rule.rhs.append(self.allocator, try self.addSymbol(symbol.id, kind));
                    try generated_rule.rhs_annotations.append(self.allocator, try common.cloneAnnotations(self.allocator, symbol.annotations));
                }
                try self.rules.append(self.allocator, generated_rule);
            }
        }

        const original_start = self.rules.items[0].header;
        self.augmented_start = try self.addSymbol("_AugmentedStart", .variable);
        self.eof = try self.addSymbol("\x00", .end);
        var augmented_rule = Rule{ .header = self.augmented_start, .rhs_index = "0" };
        try augmented_rule.rhs.append(self.allocator, original_start);
        try augmented_rule.rhs_annotations.append(self.allocator, .{});
        try augmented_rule.rhs.append(self.allocator, self.eof);
        try augmented_rule.rhs_annotations.append(self.allocator, .{});
        try self.rules.append(self.allocator, augmented_rule);

        std.mem.sort(Rule, self.rules.items, self, ruleLessThan);
        try self.buildStates();
        try self.buildParseTable();
    }

    fn ruleLessThan(self: *Generator, lhs: Rule, rhs: Rule) bool {
        return common.ruleLessThan(self.symbols.items, lhs, rhs);
    }

    fn buildStates(self: *Generator) !void {
        const augmented_rule = self.ruleForHeader(self.augmented_start).?;
        var initial = State{};
        try initial.items.append(self.allocator, .{
            .variable = self.augmented_start,
            .rule = augmented_rule,
            .head = 0,
            .lookahead = self.eof,
        });
        try self.closeState(&initial);
        try self.states.append(self.allocator, initial);

        var index: usize = 0;
        while (index < self.states.items.len) : (index += 1) {
            for (0..self.symbols.items.len) |symbol_index| {
                const next = try self.gotoState(self.states.items[index], symbol_index);
                if (next.items.items.len == 0) continue;
                const existing = self.stateIndex(next) orelse blk: {
                    const new_index = self.states.items.len;
                    try self.states.append(self.allocator, next);
                    break :blk new_index;
                };
                _ = existing;
            }
        }
    }

    fn buildParseTable(self: *Generator) !void {
        for (self.states.items, 0..) |*state, state_index| {
            for (state.items.items) |item| {
                const rule = self.rules.items[item.rule];
                if (item.variable == self.augmented_start) {
                    try self.addAction(state, .{ .terminal = self.eof, .kind = .accept });
                } else if (item.head < rule.rhs.items.len) {
                    const head_symbol = rule.rhs.items[item.head];
                    if (self.symbols.items[head_symbol].kind != .variable) {
                        const target = (try self.gotoState(state.*, head_symbol));
                        const target_index = self.stateIndex(target) orelse return error.MissingShiftState;
                        try self.addAction(state, .{
                            .terminal = head_symbol,
                            .kind = .shift,
                            .state = target_index,
                            .occurrence = self.procedureOccurrenceFor(item.rule, item.head),
                        });
                    }
                } else {
                    try self.addAction(state, .{
                        .terminal = item.lookahead,
                        .kind = .reduce,
                        .rule = item.rule,
                        .occurrence = item.occurrence,
                    });
                }
            }

            for (self.variables.items) |variable| {
                const target = try self.gotoState(state.*, variable);
                if (target.items.items.len == 0) continue;
                const target_index = self.stateIndex(target) orelse return error.MissingGotoState;
                try state.gotos.append(self.allocator, .{ .variable = variable, .state = target_index });
            }

            _ = state_index;
        }
    }

    fn addAction(self: *Generator, state: *State, action: Action) !void {
        for (state.actions.items) |*existing| {
            if (existing.terminal != action.terminal) continue;
            if (existing.kind == .accept or action.kind == .accept) {
                existing.* = if (existing.kind == .accept) existing.* else action;
                return;
            }
            if (existing.kind == action.kind and existing.state == action.state and existing.rule == action.rule) {
                if (self.occurrencesEquivalent(existing.occurrence, action.occurrence)) return;
                return error.AmbiguousProcedureHooks;
            }
            return error.AmbiguousGrammar;
        }
        try state.actions.append(self.allocator, action);
    }

    fn closeState(self: *Generator, state: *State) !void {
        var index: usize = 0;
        while (index < state.items.items.len) : (index += 1) {
            const item = state.items.items[index];
            const rule = self.rules.items[item.rule];
            if (item.head >= rule.rhs.items.len) continue;
            const head_symbol = rule.rhs.items[item.head];
            if (self.symbols.items[head_symbol].kind != .variable) continue;

            var lookaheads = std.AutoHashMap(usize, void).init(self.allocator);
            defer lookaheads.deinit();
            try self.firstsAfterItem(item, &lookaheads);

            for (self.rules.items, 0..) |candidate_rule, rule_index| {
                if (candidate_rule.header != head_symbol) continue;
                var iterator = lookaheads.keyIterator();
                while (iterator.next()) |lookahead| {
                    try appendItemUnique(&state.items, self.allocator, .{
                        .variable = head_symbol,
                        .rule = rule_index,
                        .head = 0,
                        .lookahead = lookahead.*,
                        .occurrence = self.procedureOccurrenceFor(item.rule, item.head),
                    });
                }
            }
        }
        std.mem.sort(Item, state.items.items, {}, itemLessThan);
    }

    fn firstsAfterItem(self: *Generator, item: Item, out: *std.AutoHashMap(usize, void)) !void {
        const rule = self.rules.items[item.rule];
        var index = item.head + 1;
        while (index < rule.rhs.items.len) : (index += 1) {
            const symbol_index = rule.rhs.items[index];
            const symbol = self.symbols.items[symbol_index];
            if (symbol.kind == .variable) {
                try self.firstsOfVariable(symbol_index, out, null);
                if (self.nullableRule(symbol_index, null) == null) return;
            } else {
                try out.put(symbol_index, {});
                return;
            }
        }
        try out.put(item.lookahead, {});
    }

    fn firstsOfVariable(self: *Generator, variable: usize, out: *std.AutoHashMap(usize, void), visited: ?*std.AutoHashMap(usize, void)) !void {
        if (visited) |set| {
            if (set.contains(variable)) return;
        }
        var local_visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer local_visited.deinit();
        if (visited) |set| {
            var it = set.keyIterator();
            while (it.next()) |entry| try local_visited.put(entry.*, {});
        }
        try local_visited.put(variable, {});

        for (self.rules.items) |rule| {
            if (rule.header != variable) continue;
            for (rule.rhs.items) |symbol_index| {
                const symbol = self.symbols.items[symbol_index];
                if (symbol.kind == .variable) {
                    try self.firstsOfVariable(symbol_index, out, &local_visited);
                    if (self.nullableRule(symbol_index, null) == null) break;
                } else {
                    try out.put(symbol_index, {});
                    break;
                }
            }
        }
    }

    fn nullableRule(self: *Generator, variable: usize, visited: ?*std.AutoHashMap(usize, void)) ?usize {
        if (visited) |set| {
            if (set.contains(variable)) return null;
        }
        var local_visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer local_visited.deinit();
        if (visited) |set| {
            var it = set.keyIterator();
            while (it.next()) |entry| local_visited.put(entry.*, {}) catch unreachable;
        }
        local_visited.put(variable, {}) catch unreachable;

        for (self.rules.items, 0..) |rule, rule_index| {
            if (rule.header != variable) continue;
            for (rule.rhs.items) |symbol_index| {
                if (self.symbols.items[symbol_index].kind != .variable or self.nullableRule(symbol_index, &local_visited) == null) break;
            } else {
                return rule_index;
            }
        }
        return null;
    }

    fn gotoState(self: *Generator, state: State, symbol: usize) !State {
        var next = State{};
        for (state.items.items) |item| {
            const rule = self.rules.items[item.rule];
            if (item.head >= rule.rhs.items.len or rule.rhs.items[item.head] != symbol) continue;
            try appendItemUnique(&next.items, self.allocator, .{
                .variable = item.variable,
                .rule = item.rule,
                .head = item.head + 1,
                .lookahead = item.lookahead,
                .occurrence = item.occurrence,
            });
        }
        if (next.items.items.len > 0) try self.closeState(&next);
        return next;
    }

    fn stateIndex(self: *Generator, state: State) ?usize {
        for (self.states.items, 0..) |candidate, index| {
            if (itemsEqual(candidate.items.items, state.items.items)) return index;
        }
        return null;
    }

    fn ruleForHeader(self: *Generator, header: usize) ?usize {
        for (self.rules.items, 0..) |rule, index| {
            if (rule.header == header) return index;
        }
        return null;
    }

    fn procedureOccurrenceFor(self: *Generator, rule_index: usize, position: usize) ?Occurrence {
        const rule = self.rules.items[rule_index];
        if (position >= rule.rhs.items.len) return null;
        const annotations = rule.rhs_annotations.items[position];
        const needs_procedure_occurrence = self.options.with_ast and self.options.with_procedures and annotations.procedures.items.len != 0;
        if (!needs_procedure_occurrence) return null;

        const symbol = self.symbols.items[rule.rhs.items[position]];
        const has_node = switch (symbol.kind) {
            .variable => symbol.ast_enabled,
            .terminal, .generative_terminal => self.options.ast_for_terminals,
            .end => false,
        };
        return if (has_node) .{ .rule = rule_index, .position = position } else null;
    }

    fn occurrencesEquivalent(self: *Generator, lhs: ?Occurrence, rhs: ?Occurrence) bool {
        if (lhs == null or rhs == null) return lhs == null and rhs == null;
        const lhs_names = self.rules.items[lhs.?.rule].rhs_annotations.items[lhs.?.position].procedures.items;
        const rhs_names = self.rules.items[rhs.?.rule].rhs_annotations.items[rhs.?.position].procedures.items;
        if (lhs_names.len != rhs_names.len) return false;
        for (lhs_names, rhs_names) |lhs_name, rhs_name| {
            if (!std.mem.eql(u8, lhs_name, rhs_name)) return false;
        }
        return true;
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
        try writer.print(
            \\
            \\pub const parser_type = data_structures.ParserType.lr;
            \\pub const ErrorRecoveryMode = enum {{ disabled, automatic, explicit }};
            \\pub const is_ast_enabled = {};
            \\pub const are_procedures_enabled = {};
            \\pub const is_error_recovery_enabled = {};
            \\pub const error_recovery_mode: ErrorRecoveryMode = .{s};
            \\pub const input_size_cap = u{d};
            \\pub const longest_terminal_length = {d};
            \\
            \\
        , .{
            self.options.with_ast,
            self.options.with_procedures,
            self.options.with_error_recovery,
            if (!self.options.with_error_recovery) "disabled" else if (self.uses_explicit_recovery) "explicit" else "automatic",
            self.options.input_size,
            self.longestTerminalLength(),
        });
        try self.emitGrammarTables(writer);
        if (self.options.with_error_recovery and !self.uses_explicit_recovery) try common.emitRecoveryOffsetFunction(writer, "lrRecoveryOffset");
        if (self.options.with_procedures and self.options.with_ast) try self.emitProcedureBoilerplate(writer);

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
            \\    start_pos: data_structures.Context.Size,
            \\    node: data_structures.ASTNode.Pointer = data_structures.ASTNode.invalid_pointer,
            \\};
            \\
            \\const SemanticStack = std.ArrayList(SemanticValue);
            \\
        );
        if (self.uses_explicit_recovery) try self.emitExplicitRecoverySupport(writer);

        for (self.states.items, 0..) |state, index| {
            try self.emitStateFunction(writer, state, index);
            try writer.writeByte('\n');
        }
        if (self.options.with_error_recovery) {
            if (!self.uses_explicit_recovery) try self.emitStateRecoveryCandidateTables(writer);
            try self.emitSyntaxErrorHandlers(writer);
            if (self.uses_explicit_recovery) try self.emitExplicitSyntaxDiagnosticFlusher(writer);
        }

        try writer.writeAll(
            \\pub fn parseWithResult(context: *data_structures.Context) !root.ParseResult {
            \\    var stack: SemanticStack = .empty;
            \\    defer stack.deinit(context.runtime().arena_allocator);
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
            \\    const ast_root = if (comptime is_ast_enabled) root: {
            \\        const node = stack.items[stack.items.len - 1].node;
            \\        break :root if (node != data_structures.ASTNode.invalid_pointer) node else null;
            \\    } else null;
            \\    return .{
            \\        .parsed_bytes = context.pos() - if (comptime config.indentation_syntax) 1 else 0,
            \\        .line = context.line,
            \\        .column = context.column,
            \\        .ast_root = ast_root,
            \\    };
            \\}
            \\
            \\pub fn parse(context: *data_structures.Context) !void {
            \\    _ = try parseWithResult(context);
            \\}
            \\
        );
    }

    fn emitGrammarTables(self: *Generator, writer: *std.Io.Writer) !void {
        try writer.writeAll("pub const symbols = &[_][]const u8{\n");
        for (self.symbols.items, 0..) |symbol, index| {
            try writer.writeAll("    ");
            try emitStringLiteral(writer, symbol.id);
            try writer.print(", // {d}\n", .{index});
        }
        try writer.writeAll("};\n\npub const is_terminal = &[_]bool{\n");
        for (self.symbols.items) |symbol| try writer.print("    {},\n", .{symbol.kind != .variable});
        try writer.writeAll("};\n\npub const is_generative_terminal = &[_]bool{\n");
        for (self.symbols.items) |symbol| try writer.print("    {},\n", .{symbol.kind == .generative_terminal});
        try writer.writeAll("};\n\npub const variables = &[_][]const u8{\n");
        for (self.variables.items) |symbol_index| {
            try writer.writeAll("    ");
            try emitStringLiteral(writer, self.symbols.items[symbol_index].id);
            try writer.writeAll(",\n");
        }
        try writer.writeAll("};\n\npub const symbol_by_variable = &[_]usize{\n");
        for (self.variables.items) |symbol_index| try writer.print("    {d},\n", .{symbol_index});
        try writer.writeAll("};\n\npub const rules = &[_]data_structures.Rule{\n");
        for (self.rules.items) |rule| {
            const variable_index = self.variableIndex(rule.header);
            try writer.print("    data_structures.Rule{{ .header = {d}, .right_hand_side = &[_]u16{{", .{variable_index});
            if (rule.rhs.items.len > 1) try writer.writeByte(' ');
            for (rule.rhs.items, 0..) |symbol_index, i| {
                if (i != 0) try writer.writeAll(", ");
                try writer.print("{d}", .{symbol_index});
            }
            if (rule.rhs.items.len > 1) try writer.writeByte(' ');
            try writer.writeAll("}, .right_hand_side_index = ");
            try emitStringLiteral(writer, rule.rhs_index);
            try writer.writeAll(" }, // ");
            try writer.writeAll(self.symbols.items[rule.header].id);
            try writer.writeByte('\n');
        }
        try writer.writeAll("};\n\n");
    }

    fn emitProcedureBoilerplate(self: *Generator, writer: *std.Io.Writer) !void {
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
        , .{ self.rules.items.len, self.rules.items.len, self.symbols.items.len, self.symbols.items.len });
        for (self.variables.items) |symbol_index| {
            const symbol = self.symbols.items[symbol_index];
            try writer.writeAll("    &[_][]const u8{");
            for (symbol.annotations.procedures.items, 0..) |procedure, i| {
                if (i != 0) try writer.writeAll(", ");
                try emitStringLiteral(writer, procedure);
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
        , .{ self.variables.items.len, self.variables.items.len });
    }

    fn emitProcedureSequenceExpression(self: *Generator, writer: *std.Io.Writer, procedures_: []const []const u8) !void {
        _ = self;
        try writer.writeAll("comptime makeProcedureSequence(&[_][]const u8{");
        for (procedures_, 0..) |procedure, index| {
            if (index != 0) try writer.writeAll(", ");
            try emitStringLiteral(writer, procedure);
        }
        try writer.writeAll("})");
    }

    fn emitStateFunction(self: *Generator, writer: *std.Io.Writer, state: State, state_index: usize) !void {
        if (!self.options.with_error_recovery) return self.emitFailFastStateFunction(writer, state, state_index);

        try self.emitRecoveryStateFunction(writer, state, state_index);
    }

    fn emitFailFastStateFunction(self: *Generator, writer: *std.Io.Writer, state: State, state_index: usize) !void {
        try writer.print("// LR parser state {d}\nfn state_{d}(context: *data_structures.Context, stack: *SemanticStack) anyerror!ReduceResult {{\n", .{ state_index, state_index });
        try writer.writeAll("    var result: ReduceResult = undefined;\n");
        if (!self.stateUsesStack(state)) try writer.writeAll("    _ = stack;\n");

        var entries = std.ArrayList(SwitchEntry).empty;
        for (state.actions.items, 0..) |action, action_index| {
            const terminal = self.symbols.items[action.terminal];
            for (terminal.terminals.items) |terminal_item| {
                try appendSwitchEntry(&entries, self.allocator, terminal_item, action_index);
            }
        }

        if (entries.items.len == 0) {
            try self.emitStateSyntaxError(writer, state_index, &.{}, "    ", .state);
        } else {
            try self.emitActionSwitch(writer, state, entries.items, state_index, 0, "    ");
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
            try self.emitStateSyntaxError(writer, state_index, &.{}, "        ", .goto);
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

        var entries = std.ArrayList(SwitchEntry).empty;
        for (state.actions.items, 0..) |action, action_index| {
            const terminal = self.symbols.items[action.terminal];
            for (terminal.terminals.items) |terminal_item| {
                try appendSwitchEntry(&entries, self.allocator, terminal_item, action_index);
            }
        }

        if (entries.items.len == 0) {
            try self.emitStateSyntaxError(writer, state_index, &.{}, "        ", .state);
        } else {
            try self.emitActionSwitch(writer, state, entries.items, state_index, 0, "        ");
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
            try self.emitStateSyntaxError(writer, state_index, &.{}, "            ", .goto);
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

    const SwitchEntry = struct {
        terminal: []const u8,
        action: usize,
    };

    const SwitchGroup = struct {
        heads: std.ArrayList([]const u8) = .empty,
        payload: std.ArrayList(SwitchEntry) = .empty,
    };

    fn emitActionSwitch(self: *Generator, writer: *std.Io.Writer, state: State, entries: []const SwitchEntry, state_index: usize, prefix_length: usize, indent: []const u8) !void {
        var fallback_action: ?usize = null;
        for (entries) |entry| {
            if (entry.terminal.len != 0) continue;
            if (fallback_action) |existing| std.debug.assert(existing == entry.action);
            fallback_action = entry.action;
        }

        const step_length = switchStepLength(entries);
        try writer.print("{s}switch (context.head(u{d}, {d})) {{\n", .{ indent, step_length * 8, prefix_length });
        const groups = try self.buildSwitchGroups(entries, step_length);
        for (groups.items) |group| {
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

            if (group.payload.items.len == 1 and group.payload.items[0].terminal.len == 0) {
                try self.emitAction(writer, state.actions.items[group.payload.items[0].action], prefix_length + step_length, try indented(self.allocator, indent, 8));
            } else {
                try self.emitActionSwitch(writer, state, group.payload.items, state_index, prefix_length + step_length, try indented(self.allocator, indent, 8));
                try writer.writeByte('\n');
            }
            try writer.print("{s}    }},\n", .{indent});
        }
        if (fallback_action) |action| {
            try writer.print("{s}    else => {{\n", .{indent});
            try self.emitAction(writer, state.actions.items[action], prefix_length, try indented(self.allocator, indent, 8));
            try writer.print("{s}    }},\n", .{indent});
        } else {
            try self.emitSyntaxError(writer, state_index, groups.items, try indented(self.allocator, indent, 4));
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
                if (self.options.with_ast) {
                    try writer.print("{s}const start_pos = context.pos();\n", .{indent});
                    if (self.options.ast_for_terminals) {
                        try writer.print(
                            \\{s}{s} node_address = context.node_allocator.create(start_pos, data_structures.ASTNode.invalid_variable);
                            \\{s}context.node_allocator.at(node_address).text_length = {d};
                            \\
                        , .{ indent, if (self.options.with_procedures) "var" else "const", indent, length });
                    } else {
                        try writer.print("{s}const node_address = data_structures.ASTNode.invalid_pointer;\n", .{indent});
                    }
                }
                try writer.print("{s}context.releaseToken({d});\n", .{ indent, length });
                if (self.options.with_ast and self.options.with_procedures and self.options.ast_for_terminals) {
                    try self.emitTerminalProcedureBlock(writer, action.terminal, action.occurrence, "node_address", indent);
                    try writer.print("{s}node_address = args.node orelse data_structures.ASTNode.invalid_pointer;\n", .{indent});
                }
                if (self.options.with_ast) {
                    try writer.print("{s}try stack.append(context.runtime().arena_allocator, .{{ .start_pos = start_pos, .node = node_address }});\n", .{indent});
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

        if (self.options.with_ast) {
            var i = rhs_len;
            while (i > 0) {
                i -= 1;
                const sym = rule.rhs.items[i];
                const is_linked = self.symbolReturnsStackNode(sym);
                const needed = (is_linked and self.symbols.items[rule.header].ast_enabled) or i == 0;
                if (needed) {
                    try writer.print("{s}const child_{d} = stack.pop().?;\n", .{ indent, i + 1 });
                } else {
                    try writer.print("{s}_ = stack.pop();\n", .{indent});
                }
            }

            if (rhs_len > 0) {
                try writer.print("{s}const start_pos = child_1.start_pos;\n", .{indent});
            } else {
                try writer.print("{s}const start_pos = context.pos();\n", .{indent});
            }

            if (self.symbols.items[rule.header].ast_enabled) {
                try writer.print("{s}const parent_address = context.node_allocator.create(start_pos, {d});\n", .{ indent, variable_index });
                for (rule.rhs.items, 0..) |sym, child_index| {
                    if (self.symbolReturnsStackNode(sym)) {
                        try writer.print(
                            \\{s}if (child_{d}.node != data_structures.ASTNode.invalid_pointer) {{
                            \\{s}    context.node_allocator.at(parent_address).immediateAppendChildren(parent_address, child_{d}.node, context.node_allocator); // child {d}
                            \\{s}}}
                            \\
                        , .{ indent, child_index + 1, indent, child_index + 1, child_index, indent });
                    }
                }
                if (self.options.with_procedures) {
                    try self.emitProcedureBlock(writer, rule_index, rule.header, occurrence, "parent_address", indent);
                }
                const stack_value = if (self.options.with_procedures) "args.node orelse data_structures.ASTNode.invalid_pointer" else "parent_address";
                try writer.print("{s}try stack.append(context.runtime().arena_allocator, .{{ .start_pos = start_pos, .node = {s} }});\n", .{ indent, stack_value });
            } else {
                try writer.print("{s}try stack.append(context.runtime().arena_allocator, .{{ .start_pos = start_pos }});\n", .{indent});
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
        try writer.print(
            \\{s}var args = data_structures.ProcedureArguments{{
            \\{s}    .context = context,
            \\{s}    .rule = rules[{d}],
            \\{s}    .node = {s},
            \\{s}}};
        , .{
            indent, indent, indent, rule_index, indent, node_expr, indent,
        });
        try writer.print("{s}try runProcedureSequence(", .{indent});
        try self.emitOccurrenceExpression(writer, occurrence);
        try writer.writeAll(", &args);\n");
        try writer.print("{s}try runProcedureSequence(", .{indent});
        try self.emitProcedureSequenceExpression(writer, rule.annotations.procedures.items);
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
        try writer.print(
            \\{s}var args = data_structures.ProcedureArguments{{
            \\{s}    .context = context,
            \\{s}    .rule = null,
            \\{s}    .node = {s},
            \\{s}}};
        , .{ indent, indent, indent, indent, node_expr, indent });
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
            try self.emitProcedureSequenceExpression(
                writer,
                self.rules.items[value.rule].rhs_annotations.items[value.position].procedures.items,
            );
        } else {
            try writer.writeAll("null");
        }
    }

    fn emitDebugReduction(self: *Generator, writer: *std.Io.Writer, rule: Rule, indent: []const u8) !void {
        try writer.print(
            \\{s}if (comptime builtin.mode == .Debug) {{
            \\{s}    if (context.verbosityLevel() > 1) {{
            \\{s}        std.debug.print("Reduction: 
        , .{ indent, indent, indent });
        try emitFormatToken(writer, self.symbols.items[rule.header].id);
        try writer.writeAll(" <~ ");
        try self.emitRuleSymbolsForDebug(writer, rule);
        try writer.print(
            \\\n", .{{}});
            \\{s}    }}
            \\{s}}}
        , .{ indent, indent });
    }

    fn emitSyntaxError(self: *Generator, writer: *std.Io.Writer, state_index: usize, groups: []const SwitchGroup, indent: []const u8) !void {
        const error_function_name = try self.nextSyntaxErrorFunctionName(state_index, .action);
        var expected = std.ArrayList([]const u8).empty;
        for (groups) |group| {
            for (group.heads.items) |head| try expected.append(self.allocator, head);
        }
        std.mem.sort([]const u8, expected.items, {}, headLessThan);
        try writer.print("{s}else => {{\n", .{indent});
        try self.emitSyntaxErrorCall(writer, state_index, expected.items, error_function_name, true, try indented(self.allocator, indent, 4));
        try writer.print("{s}}},\n", .{indent});
    }

    fn emitStateSyntaxError(self: *Generator, writer: *std.Io.Writer, state_index: usize, groups: []const SwitchGroup, indent: []const u8, kind: SyntaxErrorSite) !void {
        const error_function_name = try self.nextSyntaxErrorFunctionName(state_index, kind);
        var expected = std.ArrayList([]const u8).empty;
        for (groups) |group| {
            for (group.heads.items) |head| try expected.append(self.allocator, head);
        }
        std.mem.sort([]const u8, expected.items, {}, headLessThan);
        try self.emitSyntaxErrorCall(writer, state_index, expected.items, error_function_name, kind != .goto, indent);
    }

    fn emitSyntaxErrorCall(
        self: *Generator,
        writer: *std.Io.Writer,
        state_index: usize,
        expected_tokens: []const []const u8,
        error_function_name: []const u8,
        recoverable: bool,
        indent: []const u8,
    ) !void {
        if (!self.options.with_error_recovery) {
            try writer.print("{s}try context.recordSyntaxDiagnostic(.{{ .state = {d} }}, &[_][]const u8{{", .{ indent, state_index });
            try self.emitStringSliceItems(writer, expected_tokens);
            try writer.writeAll("});\n");
            try writer.print("{s}if (!builtin.is_test) {{\n", .{indent});
            try self.emitSyntaxErrorMessagePrint(writer, error_function_name, try indented(self.allocator, indent, 4));
            try writer.print("{s}}}\n", .{indent});
            try writer.print("{s}return root.ParseError.SyntaxError;\n", .{indent});
            return;
        }

        const handler_name = try std.fmt.allocPrint(self.allocator, "lr_syntax_error_{d}", .{self.syntax_error_handlers.items.len});
        try self.syntax_error_handlers.append(self.allocator, .{
            .name = handler_name,
            .state_index = state_index,
            .expected_tokens = try self.allocator.dupe([]const u8, expected_tokens),
            .error_function_name = error_function_name,
            .recoverable = recoverable,
        });
        if (self.uses_explicit_recovery) {
            try writer.print("{s}if (try {s}(context, stack, recovery_frame)) |explicit_recovery| {{\n", .{ indent, handler_name });
            try writer.print("{s}    if (explicit_recovery.return_from_state) return explicit_recovery.result;\n", .{indent});
            try writer.print("{s}    result = explicit_recovery.result;\n", .{indent});
            try writer.print("{s}}} else return root.ParseError.SyntaxError;\n", .{indent});
            return;
        }
        try writer.print("{s}if (try {s}(context, stack)) continue :state_recovery;\n", .{ indent, handler_name });
        try writer.print("{s}return ReduceResult{{ .variable = 0, .pops_remaining = 0, .is_accept = false, .is_recovery = true }};\n", .{indent});
    }

    fn emitStateRecoveryCandidateTables(self: *Generator, writer: *std.Io.Writer) !void {
        for (self.states.items, 0..) |state, state_index| {
            const candidates = try self.recoveryTerminalStringsForState(state);
            try writer.print("const lr_recovery_candidates_{d} = &[_][]const u8{{", .{state_index});
            try self.emitStringSliceItems(writer, candidates.items);
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
        if (self.options.with_ast) {
            try writer.writeAll(
                \\    {
                \\        var start_pos: data_structures.Context.Size = @intCast(context.pos());
                \\        for (0..unwind_count) |_| {
                \\            const discarded = stack.pop() orelse unreachable;
                \\            start_pos = discarded.start_pos;
                \\        }
                \\        try stack.append(context.runtime().arena_allocator, .{ .start_pos = start_pos });
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
        const ClosureEdge = struct {
            parent: usize,
            child: usize,
            occurrence: Occurrence,
        };
        for (self.states.items, 0..) |state, state_index| {
            try writer.print("const lr_recovery_items_{d} = &[_]LRRecoveryItem{{\n", .{state_index});
            for (state.items.items) |item| {
                try writer.writeAll("    ");
                try self.emitRecoveryItem(writer, item);
                try writer.writeAll(",\n");
            }
            try writer.writeAll("};\n");

            try writer.print("const lr_recovery_kernel_items_{d} = &[_]usize{{", .{state_index});
            for (state.items.items, 0..) |item, item_index| {
                if (item.head == 0 and item.variable != self.augmented_start) continue;
                try writer.print(" {d},", .{item_index});
            }
            try writer.writeAll(" };\n");

            var closure_edges: std.ArrayList(ClosureEdge) = .empty;
            defer closure_edges.deinit(self.allocator);
            for (state.items.items, 0..) |parent, parent_index| {
                const parent_rule = self.rules.items[parent.rule];
                if (parent.head >= parent_rule.rhs.items.len) continue;
                const child_variable = parent_rule.rhs.items[parent.head];
                if (self.symbols.items[child_variable].kind != .variable) continue;
                var lookaheads = std.AutoHashMap(usize, void).init(self.allocator);
                defer lookaheads.deinit();
                try self.firstsAfterItem(parent, &lookaheads);
                const procedure_occurrence = self.procedureOccurrenceFor(parent.rule, parent.head);
                for (state.items.items, 0..) |child, child_index| {
                    if (child.head != 0 or child.variable != child_variable or !lookaheads.contains(child.lookahead) or
                        !std.meta.eql(child.occurrence, procedure_occurrence)) continue;
                    try closure_edges.append(self.allocator, .{
                        .parent = parent_index,
                        .child = child_index,
                        .occurrence = .{ .rule = parent.rule, .position = parent.head },
                    });
                }
            }

            try writer.print("const lr_recovery_closure_edges_{d} = &[_]LRRecoveryClosureEdge{{\n", .{state_index});
            for (closure_edges.items) |edge| {
                try writer.print(
                    "    .{{ .child = {d}, .parent = {d}, .occurrence = .{{ .rule = {d}, .position = {d} }} }},\n",
                    .{ edge.child, edge.parent, edge.occurrence.rule, edge.occurrence.position },
                );
            }
            try writer.writeAll("};\n");

            try writer.print("const lr_recovery_closure_edge_offsets_{d} = &[_]usize{{ 0,", .{state_index});
            var edge_index: usize = 0;
            for (state.items.items, 0..) |_, parent_index| {
                while (edge_index < closure_edges.items.len and closure_edges.items[edge_index].parent == parent_index) edge_index += 1;
                try writer.print(" {d},", .{edge_index});
            }
            try writer.writeAll(" };\n");

            try writer.print("const lr_recovery_closure_parents_{d} = &[_]usize{{", .{state_index});
            for (state.items.items, 0..) |_, child_index| {
                for (closure_edges.items) |edge| {
                    if (edge.child == child_index) try writer.print(" {d},", .{edge.parent});
                }
            }
            try writer.writeAll(" };\n");
            try writer.print("const lr_recovery_closure_parent_offsets_{d} = &[_]usize{{ 0,", .{state_index});
            var parent_count: usize = 0;
            for (state.items.items, 0..) |_, child_index| {
                for (closure_edges.items) |edge| {
                    if (edge.child == child_index) parent_count += 1;
                }
                try writer.print(" {d},", .{parent_count});
            }
            try writer.writeAll(" };\n");
        }

        try writer.writeAll("const lr_recovery_items = &[_][]const LRRecoveryItem{\n");
        for (self.states.items, 0..) |_, state_index| try writer.print("    lr_recovery_items_{d},\n", .{state_index});
        try writer.writeAll("};\nconst lr_recovery_kernel_items = &[_][]const usize{\n");
        for (self.states.items, 0..) |_, state_index| try writer.print("    lr_recovery_kernel_items_{d},\n", .{state_index});
        try writer.writeAll("};\nconst lr_recovery_closure_edges = &[_][]const LRRecoveryClosureEdge{\n");
        for (self.states.items, 0..) |_, state_index| try writer.print("    lr_recovery_closure_edges_{d},\n", .{state_index});
        try writer.writeAll("};\nconst lr_recovery_closure_edge_offsets = &[_][]const usize{\n");
        for (self.states.items, 0..) |_, state_index| try writer.print("    lr_recovery_closure_edge_offsets_{d},\n", .{state_index});
        try writer.writeAll("};\nconst lr_recovery_closure_parents = &[_][]const usize{\n");
        for (self.states.items, 0..) |_, state_index| try writer.print("    lr_recovery_closure_parents_{d},\n", .{state_index});
        try writer.writeAll("};\nconst lr_recovery_closure_parent_offsets = &[_][]const usize{\n");
        for (self.states.items, 0..) |_, state_index| try writer.print("    lr_recovery_closure_parent_offsets_{d},\n", .{state_index});
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
        try writer.print("    @setEvalBranchQuota({d});\n", .{@max(1000, self.syntax_error_handlers.items.len * 8)});
        try writer.writeAll("    const site = context.pendingSyntaxErrorSite() orelse return;\n");
        try writer.writeAll("    context.clearPendingSyntaxErrorSite();\n");
        try writer.writeAll("    switch (site) {\n");
        for (self.syntax_error_handlers.items, 0..) |spec, site_index| {
            try writer.print("        {d} => {{\n", .{site_index});
            try self.emitSyntaxErrorMessagePrint(writer, spec.error_function_name, "            ");
            try writer.writeAll("        },\n");
        }
        try writer.writeAll("        else => unreachable,\n    }\n}\n\n");
    }

    fn emitRecoveryPoints(self: *Generator, writer: *std.Io.Writer, points: []const common.RecoveryPoint) !void {
        _ = self;
        try writer.writeAll("&[_]root.SyntaxRecoveryPoint{");
        for (points, 0..) |point, index| {
            if (index != 0) try writer.writeAll(", ");
            try writer.writeAll(".{ .terminal = ");
            try emitStringLiteral(writer, point.terminal);
            try writer.print(", .@\"resume\" = .{s} }}", .{@tagName(point.@"resume")});
        }
        try writer.writeByte('}');
    }

    fn emitLhsRecoveryScope(self: *Generator, writer: *std.Io.Writer, variable: usize) !void {
        try writer.print("&ExplicitRecoveryScope{{ .id = {d}, .target = .{{ .lhs_variable = ", .{variable});
        try emitStringLiteral(writer, self.symbols.items[variable].id);
        try writer.writeAll(" }, .points = ");
        try self.emitRecoveryPoints(writer, self.symbols.items[variable].annotations.recovery_points.items);
        try writer.writeAll(" }");
    }

    fn emitProductionRecoveryScope(self: *Generator, writer: *std.Io.Writer, rule: Rule, rule_index: usize) !void {
        try writer.print("&ExplicitRecoveryScope{{ .id = {d}, .target = .{{ .production = .{{ .variable = ", .{self.symbols.items.len + rule_index});
        try emitStringLiteral(writer, self.symbols.items[rule.header].id);
        try writer.print(", .rhs_index = {s} }} }}, .points = ", .{rule.rhs_index});
        try self.emitRecoveryPoints(writer, rule.annotations.recovery_points.items);
        try writer.writeAll(" }");
    }

    fn emitOccurrenceRecoveryScope(self: *Generator, writer: *std.Io.Writer, occurrence: Occurrence) !void {
        const rule = self.rules.items[occurrence.rule];
        const variable = rule.rhs.items[occurrence.position];
        const target_id = common.recoveryOccurrenceTargetId(self.symbols.items.len, self.rules.items, occurrence.rule, occurrence.position);
        try writer.print("&ExplicitRecoveryScope{{ .id = {d}, .target = .{{ .occurrence = .{{ .parent_variable = ", .{target_id});
        try emitStringLiteral(writer, self.symbols.items[rule.header].id);
        try writer.print(", .rhs_index = {s}, .symbol_index = {d}, .variable = ", .{ rule.rhs_index, occurrence.position });
        try emitStringLiteral(writer, self.symbols.items[variable].id);
        try writer.writeAll(" } }, .points = ");
        try self.emitRecoveryPoints(writer, rule.rhs_annotations.items[occurrence.position].recovery_points.items);
        try writer.writeAll(" }");
    }

    fn emitSyntaxErrorHandlers(self: *Generator, writer: *std.Io.Writer) !void {
        for (self.syntax_error_handlers.items, 0..) |spec, site_index| {
            try writer.print("fn {s}(context: *data_structures.Context, stack: *SemanticStack{s}) anyerror!{s} {{\n", .{
                spec.name,
                if (self.uses_explicit_recovery) ", recovery_frame: *const LRRecoveryFrame" else "",
                if (self.uses_explicit_recovery) "?ExplicitRecoveryResult" else "bool",
            });
            try writer.writeAll("    @branchHint(.cold);\n");
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
            if (!spec.recoverable or !self.options.with_ast or spec.state_index == 0) try writer.writeAll("    _ = stack;\n");
            try writer.writeAll("    const report_syntax_error = context.beginSyntaxRecovery();\n");
            try writer.writeAll("    if (report_syntax_error) {\n");
            try writer.print("        try context.recordSyntaxDiagnostic(.{{ .state = {d} }}, &[_][]const u8{{", .{spec.state_index});
            try self.emitStringSliceItems(writer, spec.expected_tokens);
            try writer.writeAll("});\n");
            try writer.writeAll("        if (!builtin.is_test) {\n");
            try self.emitSyntaxErrorMessagePrint(writer, spec.error_function_name, "            ");
            try writer.writeAll("        }\n");
            try writer.writeAll("    }\n");
            try writer.writeAll("    if (report_syntax_error and context.syntaxErrorLimitReached()) return root.ParseError.SyntaxError;\n");
            if (spec.recoverable) {
                try writer.print("    if (try lrRecoveryOffset(context, lr_recovery_candidates_{d}, if (report_syntax_error) 1 else 0)) |recovery_offset| {{\n", .{spec.state_index});
                try writer.writeAll("        context.skipRecoveryInput(recovery_offset);\n");
                try writer.writeAll("        return true;\n");
                try writer.writeAll("    }\n");
                try writer.writeAll("    if (context.head(u8, 0) == 0) return root.ParseError.SyntaxError;\n");
                if (self.options.with_ast and spec.state_index != 0) {
                    try writer.writeAll("    _ = stack.pop() orelse unreachable;\n");
                }
                try writer.writeAll("    return false;\n");
            } else {
                try writer.writeAll("    return root.ParseError.SyntaxError;\n");
            }
            try writer.writeAll("}\n\n");
        }
    }

    fn recoveryTerminalStringsForState(self: *Generator, state: State) !std.ArrayList([]const u8) {
        var result = std.ArrayList([]const u8).empty;
        for (state.actions.items) |action| {
            for (self.symbols.items[action.terminal].terminals.items) |terminal| {
                for (result.items) |existing| {
                    if (std.mem.eql(u8, existing, terminal)) break;
                } else {
                    try result.append(self.allocator, terminal);
                }
            }
        }
        std.mem.sort([]const u8, result.items, {}, headLessThan);
        return result;
    }

    fn emitStringSliceItems(self: *Generator, writer: *std.Io.Writer, items: []const []const u8) !void {
        _ = self;
        for (items, 0..) |item, index| {
            if (index != 0) try writer.writeAll(", ");
            try emitStringLiteral(writer, item);
        }
    }

    fn nextSyntaxErrorFunctionName(self: *Generator, state_index: usize, kind: SyntaxErrorSite) ![]const u8 {
        const stem = try std.fmt.allocPrint(self.allocator, "state_{d}_{s}", .{ state_index, @tagName(kind) });
        const name = try common.syntaxErrorFunctionName(self.allocator, "lr_", stem, self.syntax_error_site_index);
        self.syntax_error_site_index += 1;
        try self.error_message_specs.append(self.allocator, .{ .name = name });
        return name;
    }

    fn emitSyntaxErrorMessagePrint(self: *Generator, writer: *std.Io.Writer, function_name: []const u8, indent: []const u8) !void {
        _ = self;
        try writer.print(
            \\{s}const diagnostic = context.runtime().last_diagnostic.?;
            \\{s}const diagnostic_message = if (comptime @hasDecl(error_messages, "{s}"))
            \\{s}    @field(error_messages, "{s}")(.{{
            \\{s}        .allocator = context.runtime().arena_allocator,
            \\{s}        .context = context,
            \\{s}        .diagnostic = diagnostic,
            \\{s}        .style = .ansi,
            \\{s}    }}) catch ""
            \\{s}else
            \\{s}    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
            \\{s}if (!builtin.is_test) std.debug.print("{{s}}", .{{diagnostic_message}});
            \\
        , .{
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
        const symbol = self.symbols.items[symbol_index];
        return switch (symbol.kind) {
            .variable => symbol.ast_enabled,
            .terminal, .generative_terminal => self.options.ast_for_terminals,
            .end => false,
        };
    }

    fn stateUsesStack(self: *Generator, state: State) bool {
        if (state.gotos.items.len > 0) return true;
        for (state.actions.items) |action| {
            switch (action.kind) {
                .shift => return true,
                .reduce => if (self.options.with_ast) return true,
                .accept => {},
            }
        }
        return false;
    }

    fn variableIndex(self: *Generator, symbol_index: usize) usize {
        for (self.variables.items, 0..) |candidate, index| {
            if (candidate == symbol_index) return index;
        }
        unreachable;
    }

    fn longestTerminalLength(self: *Generator) usize {
        const grammar_longest = common.longestTerminalLength(self.symbols.items);
        if (!self.uses_explicit_recovery) return grammar_longest;
        return @max(grammar_longest, common.longestRecoveryTerminalLength(self.symbols.items, self.rules.items));
    }

    fn appendSwitchEntry(entries: *std.ArrayList(SwitchEntry), allocator: std.mem.Allocator, terminal: []const u8, action: usize) !void {
        for (entries.items) |entry| {
            if (entry.action == action and std.mem.eql(u8, entry.terminal, terminal)) return;
        }
        try entries.append(allocator, .{ .terminal = terminal, .action = action });
    }

    fn switchEntryLessThan(_: void, lhs: SwitchEntry, rhs: SwitchEntry) bool {
        const order = std.mem.order(u8, lhs.terminal, rhs.terminal);
        if (order != .eq) return order == .lt;
        return lhs.action < rhs.action;
    }

    fn buildSwitchGroups(self: *Generator, entries: []const SwitchEntry, step_length: usize) !std.ArrayList(SwitchGroup) {
        var heads = std.ArrayList([]const u8).empty;
        for (entries) |entry| {
            if (entry.terminal.len == 0) continue;
            const head = entry.terminal[0..step_length];
            for (heads.items) |existing| {
                if (std.mem.eql(u8, existing, head)) break;
            } else {
                try heads.append(self.allocator, head);
            }
        }
        std.mem.sort([]const u8, heads.items, {}, headLessThan);

        var groups = std.ArrayList(SwitchGroup).empty;
        for (heads.items) |head| {
            var payload = std.ArrayList(SwitchEntry).empty;
            for (entries) |entry| {
                if (entry.terminal.len == 0) continue;
                if (!std.mem.eql(u8, entry.terminal[0..step_length], head)) continue;
                try appendSwitchEntry(&payload, self.allocator, entry.terminal[step_length..], entry.action);
            }
            std.mem.sort(SwitchEntry, payload.items, {}, switchEntryLessThan);

            var found: ?usize = null;
            for (groups.items, 0..) |group, i| {
                if (switchPayloadEqual(group.payload.items, payload.items)) {
                    found = i;
                    break;
                }
            }
            if (found) |index| {
                try groups.items[index].heads.append(self.allocator, head);
            } else {
                var group = SwitchGroup{ .payload = payload };
                try group.heads.append(self.allocator, head);
                try groups.append(self.allocator, group);
            }
        }

        for (groups.items) |*group| {
            std.mem.sort([]const u8, group.heads.items, {}, headLessThan);
        }
        std.mem.sort(SwitchGroup, groups.items, {}, switchGroupLessThan);
        return groups;
    }
};

pub fn emitParser(allocator: std.mem.Allocator, grammar: anytype, writer: *std.Io.Writer) !void {
    try emitParserWithOptions(allocator, grammar, writer, .{});
}

pub fn emitParserWithOptions(allocator: std.mem.Allocator, grammar: anytype, writer: *std.Io.Writer, options: Options) !void {
    var generator = Generator.init(allocator, options);
    try generator.fromGrammar(grammar);
    if (generator.has_recovery_annotations and !options.with_error_recovery) {
        std.log.warn("grammar recovery annotations are ignored because error recovery is disabled", .{});
    }
    try generator.emit(writer);
}

pub fn emitErrorMessagesWithOptions(allocator: std.mem.Allocator, grammar: anytype, writer: *std.Io.Writer, options: Options) !void {
    var generator = Generator.init(allocator, options);
    try generator.fromGrammar(grammar);

    var generated_parser: std.Io.Writer.Allocating = .init(allocator);
    defer generated_parser.deinit();
    try generator.emit(&generated_parser.writer);

    try common.emitErrorMessageFile(writer, "LR", generator.error_message_specs.items);
}

pub fn canonicalTopologyEqualForTesting(allocator: std.mem.Allocator, lhs_grammar: anytype, rhs_grammar: anytype, options: Options) !bool {
    var lhs = Generator.init(allocator, options);
    try lhs.fromGrammar(lhs_grammar);
    var rhs = Generator.init(allocator, options);
    try rhs.fromGrammar(rhs_grammar);
    if (lhs.states.items.len != rhs.states.items.len) return false;
    for (lhs.states.items, rhs.states.items) |lhs_state, rhs_state| {
        if (!itemsEqual(lhs_state.items.items, rhs_state.items.items)) return false;
        if (lhs_state.actions.items.len != rhs_state.actions.items.len or lhs_state.gotos.items.len != rhs_state.gotos.items.len) return false;
        for (lhs_state.actions.items, rhs_state.actions.items) |lhs_action, rhs_action| {
            if (!std.meta.eql(lhs_action, rhs_action)) return false;
        }
        for (lhs_state.gotos.items, rhs_state.gotos.items) |lhs_goto, rhs_goto| {
            if (!std.meta.eql(lhs_goto, rhs_goto)) return false;
        }
    }
    return true;
}

pub fn canonicalStateCountForTesting(allocator: std.mem.Allocator, grammar: anytype, options: Options) !usize {
    var generator = Generator.init(allocator, options);
    try generator.fromGrammar(grammar);
    return generator.states.items.len;
}

fn appendItemUnique(items: *std.ArrayList(Item), allocator: std.mem.Allocator, item: Item) !void {
    for (items.items) |existing| {
        if (itemEqual(existing, item)) return;
    }
    try items.append(allocator, item);
}

fn itemEqual(lhs: Item, rhs: Item) bool {
    return lhs.variable == rhs.variable and lhs.rule == rhs.rule and lhs.head == rhs.head and lhs.lookahead == rhs.lookahead and std.meta.eql(lhs.occurrence, rhs.occurrence);
}

fn itemLessThan(_: void, lhs: Item, rhs: Item) bool {
    if (lhs.variable != rhs.variable) return lhs.variable < rhs.variable;
    if (lhs.rule != rhs.rule) return lhs.rule < rhs.rule;
    if (lhs.head != rhs.head) return lhs.head < rhs.head;
    if (lhs.lookahead != rhs.lookahead) return lhs.lookahead < rhs.lookahead;
    return occurrenceLessThan(lhs.occurrence, rhs.occurrence);
}

fn occurrenceLessThan(lhs: ?Occurrence, rhs: ?Occurrence) bool {
    if (lhs == null) return rhs != null;
    if (rhs == null) return false;
    if (lhs.?.rule != rhs.?.rule) return lhs.?.rule < rhs.?.rule;
    return lhs.?.position < rhs.?.position;
}

fn itemsEqual(lhs: []const Item, rhs: []const Item) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |a, b| {
        if (!itemEqual(a, b)) return false;
    }
    return true;
}

fn switchStepLength(entries: []const Generator.SwitchEntry) usize {
    var step_length: usize = std.math.maxInt(usize);
    for (entries) |entry| {
        if (entry.terminal.len > 0) step_length = @min(step_length, entry.terminal.len);
    }
    return step_length;
}

fn headLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn switchGroupLessThan(_: void, lhs: Generator.SwitchGroup, rhs: Generator.SwitchGroup) bool {
    return std.mem.order(u8, lhs.heads.items[0], rhs.heads.items[0]) == .lt;
}

fn switchPayloadEqual(lhs: []const Generator.SwitchEntry, rhs: []const Generator.SwitchEntry) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |a, b| {
        if (a.action != b.action or !std.mem.eql(u8, a.terminal, b.terminal)) return false;
    }
    return true;
}
