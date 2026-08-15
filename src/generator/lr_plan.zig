const std = @import("std");
const common = @import("generator_common");
const recovery_planning = @import("lr_recovery.zig");
const switch_planning = @import("generator_switch_plan");

pub const Occurrence = recovery_planning.Occurrence;

pub const Item = struct {
    variable: usize,
    rule: usize,
    head: usize,
    lookahead: usize,
    occurrence: ?Occurrence = null,
};

pub const ActionKind = enum { shift, reduce, accept };

pub const Action = struct {
    terminal: usize,
    kind: ActionKind,
    state: usize = 0,
    rule: usize = 0,
    occurrence: ?Occurrence = null,
};

pub const GotoEntry = struct { variable: usize, state: usize };

pub const State = struct {
    items: std.ArrayList(Item) = .empty,
    actions: std.ArrayList(Action) = .empty,
    gotos: std.ArrayList(GotoEntry) = .empty,
    uses_semantic_stack: bool = false,
};

pub const RecoveryClosureEdge = recovery_planning.RecoveryClosureEdge;
pub const RecoveryStateMetadata = recovery_planning.StateMetadata;

pub const SyntaxErrorHandler = struct {
    name: []const u8,
    state_index: usize,
    expected_tokens: []const []const u8,
    error_function_name: []const u8,
    recoverable: bool,
};

pub const StateDecision = struct {
    action_tree: *switch_planning.Node,
    goto_diagnostic: ?usize = null,
};

pub const LRPlan = struct {
    states: std.ArrayList(State) = .empty,
    state_decisions: std.ArrayList(StateDecision) = .empty,
    error_message_specs: std.ArrayList(common.ErrorMessageSpec) = .empty,
    syntax_error_handlers: std.ArrayList(SyntaxErrorHandler) = .empty,
    variable_indices: []?usize = &.{},
    symbol_returns_stack_node: []bool = &.{},
    longest_terminal_length: usize = 0,
    augmented_start: usize = 0,
    eof: usize = 0,
    recovery: recovery_planning.Plan = .{},

    pub fn build(allocator: std.mem.Allocator, grammar: *const common.PreparedGrammar, options: common.Options) !LRPlan {
        var builder = Builder{
            .allocator = allocator,
            .grammar = grammar,
            .options = options,
            .plan = .{ .augmented_start = grammar.augmented_start, .eof = grammar.eof },
        };
        try builder.buildStates();
        try builder.buildParseTable();
        try common.validateVerbatimSymbols(allocator, grammar);
        builder.planSemanticStackRequirements();
        builder.plan.recovery = try recovery_planning.build(allocator, grammar, options, builder.plan.states.items);
        try builder.planStateDecisionsAndDiagnostics();
        try builder.planMetadata();
        return builder.plan;
    }

    pub fn topologyEqual(lhs: *const LRPlan, rhs: *const LRPlan) bool {
        if (lhs.states.items.len != rhs.states.items.len) return false;
        for (lhs.states.items, rhs.states.items) |lhs_state, rhs_state| {
            if (!itemsEqual(lhs_state.items.items, rhs_state.items.items)) return false;
            if (lhs_state.actions.items.len != rhs_state.actions.items.len or lhs_state.gotos.items.len != rhs_state.gotos.items.len) return false;
            for (lhs_state.actions.items, rhs_state.actions.items) |lhs_action, rhs_action| if (!std.meta.eql(lhs_action, rhs_action)) return false;
            for (lhs_state.gotos.items, rhs_state.gotos.items) |lhs_goto, rhs_goto| if (!std.meta.eql(lhs_goto, rhs_goto)) return false;
        }
        return true;
    }
};

const SyntaxErrorSite = enum { action, state, goto };

const Builder = struct {
    allocator: std.mem.Allocator,
    grammar: *const common.PreparedGrammar,
    options: common.Options,
    plan: LRPlan,

    fn buildStates(self: *Builder) !void {
        const augmented_rule = self.ruleForHeader(self.plan.augmented_start).?;
        var initial = State{};
        try initial.items.append(self.allocator, .{
            .variable = self.plan.augmented_start,
            .rule = augmented_rule,
            .head = 0,
            .lookahead = self.plan.eof,
        });
        try self.closeState(&initial);
        try self.plan.states.append(self.allocator, initial);

        var index: usize = 0;
        while (index < self.plan.states.items.len) : (index += 1) {
            for (0..self.grammar.symbols.items.len) |symbol_index| {
                const next = try self.gotoState(self.plan.states.items[index], symbol_index);
                if (next.items.items.len == 0) continue;
                _ = self.stateIndex(next) orelse blk: {
                    const new_index = self.plan.states.items.len;
                    try self.plan.states.append(self.allocator, next);
                    break :blk new_index;
                };
            }
        }
    }

    fn buildParseTable(self: *Builder) !void {
        for (self.plan.states.items) |*state| {
            for (state.items.items) |item| {
                const rule = self.grammar.rules.items[item.rule];
                if (item.variable == self.plan.augmented_start) {
                    try self.addAction(state, .{ .terminal = self.plan.eof, .kind = .accept });
                } else if (item.head < rule.rhs.items.len) {
                    const head_symbol = rule.rhs.items[item.head];
                    if (self.grammar.symbols.items[head_symbol].kind != .variable) {
                        const target = try self.gotoState(state.*, head_symbol);
                        const target_index = self.stateIndex(target) orelse return error.MissingShiftState;
                        try self.addAction(state, .{
                            .terminal = head_symbol,
                            .kind = .shift,
                            .state = target_index,
                            .occurrence = common.procedureOccurrenceFor(self.grammar, self.options, item.rule, item.head),
                        });
                    }
                } else try self.addAction(state, .{
                    .terminal = item.lookahead,
                    .kind = .reduce,
                    .rule = item.rule,
                    .occurrence = item.occurrence,
                });
            }

            for (self.grammar.variables.items) |variable| {
                const target = try self.gotoState(state.*, variable);
                if (target.items.items.len == 0) continue;
                const target_index = self.stateIndex(target) orelse return error.MissingGotoState;
                try state.gotos.append(self.allocator, .{ .variable = variable, .state = target_index });
            }
        }
    }

    fn addAction(self: *Builder, state: *State, action: Action) !void {
        for (state.actions.items) |*existing| {
            if (existing.terminal != action.terminal) continue;
            if (existing.kind == .accept or action.kind == .accept) {
                existing.* = if (existing.kind == .accept) existing.* else action;
                return;
            }
            if (existing.kind == action.kind and existing.state == action.state and existing.rule == action.rule) {
                if (self.occurrencesEquivalent(existing.occurrence, action.occurrence)) return;
                try self.reportProcedureHooksConflict(state, existing.*);
                return error.AmbiguousProcedureHooks;
            }
            try self.reportActionConflict(state, existing.*, action);
            return error.AmbiguousGrammar;
        }
        try state.actions.append(self.allocator, action);
    }

    fn reportProcedureHooksConflict(self: *Builder, state: *State, existing: Action) !void {
        const state_index = self.stateIndex(state.*) orelse 0;
        const existing_rule = self.grammar.rules.items[existing.rule];
        const existing_rule_text = try common.ruleText(self.allocator, self.grammar.symbols.items, existing_rule);
        defer self.allocator.free(existing_rule_text);
        std.log.warn("ambiguous grammar: state {d} has multiple procedure hooks on the same reduction:\n  {s}", .{ state_index, existing_rule_text });
    }

    fn reportActionConflict(self: *Builder, state: *State, existing: Action, incoming: Action) !void {
        const state_index = self.stateIndex(state.*) orelse return;
        const terminal_name = try common.symbolText(self.allocator, self.grammar.symbols.items, existing.terminal);
        defer self.allocator.free(terminal_name);
        const existing_text = try self.describeAction(existing);
        defer self.allocator.free(existing_text);
        const incoming_text = try self.describeAction(incoming);
        defer self.allocator.free(incoming_text);
        std.log.warn("ambiguous grammar: state {d}, terminal {s} has conflicting actions:\n  {s}\n  {s}", .{ state_index, terminal_name, existing_text, incoming_text });
    }

    fn describeAction(self: *Builder, action: Action) ![]const u8 {
        return switch (action.kind) {
            .shift => std.fmt.allocPrint(self.allocator, "shift to state {d}", .{action.state}),
            .accept => self.allocator.dupe(u8, "accept"),
            .reduce => blk: {
                const rule = self.grammar.rules.items[action.rule];
                const text = try common.ruleText(self.allocator, self.grammar.symbols.items, rule);
                defer self.allocator.free(text);
                break :blk try std.fmt.allocPrint(self.allocator, "reduce by {s}", .{text});
            },
        };
    }

    fn closeState(self: *Builder, state: *State) !void {
        var index: usize = 0;
        while (index < state.items.items.len) : (index += 1) {
            const item = state.items.items[index];
            const rule = self.grammar.rules.items[item.rule];
            if (item.head >= rule.rhs.items.len) continue;
            const head_symbol = rule.rhs.items[item.head];
            if (self.grammar.symbols.items[head_symbol].kind != .variable) continue;

            var lookaheads = std.AutoHashMap(usize, void).init(self.allocator);
            defer lookaheads.deinit();
            try common.firstsAfterItem(self.allocator, self.grammar, item, &lookaheads);
            for (self.grammar.rules.items, 0..) |candidate_rule, rule_index| {
                if (candidate_rule.header != head_symbol) continue;
                var iterator = lookaheads.keyIterator();
                while (iterator.next()) |lookahead| try appendItemUnique(&state.items, self.allocator, .{
                    .variable = head_symbol,
                    .rule = rule_index,
                    .head = 0,
                    .lookahead = lookahead.*,
                    .occurrence = common.procedureOccurrenceFor(self.grammar, self.options, item.rule, item.head),
                });
            }
        }
        std.mem.sort(Item, state.items.items, {}, itemLessThan);
    }

    fn gotoState(self: *Builder, state: State, symbol: usize) !State {
        var next = State{};
        for (state.items.items) |item| {
            const rule = self.grammar.rules.items[item.rule];
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

    fn stateIndex(self: *Builder, state: State) ?usize {
        for (self.plan.states.items, 0..) |candidate, index| if (itemsEqual(candidate.items.items, state.items.items)) return index;
        return null;
    }

    fn ruleForHeader(self: *Builder, header: usize) ?usize {
        for (self.grammar.rules.items, 0..) |rule, index| if (rule.header == header) return index;
        return null;
    }

    fn occurrencesEquivalent(self: *Builder, lhs: ?Occurrence, rhs: ?Occurrence) bool {
        if (lhs == null or rhs == null) return lhs == null and rhs == null;
        const lhs_annotations = self.grammar.rules.items[lhs.?.rule].rhs_annotations.items[lhs.?.position];
        const rhs_annotations = self.grammar.rules.items[rhs.?.rule].rhs_annotations.items[rhs.?.position];
        if (lhs_annotations.verbatim != rhs_annotations.verbatim) return false;
        const lhs_verbatim_literal = lhs_annotations.verbatim_literal orelse "";
        const rhs_verbatim_literal = rhs_annotations.verbatim_literal orelse "";
        if (!std.mem.eql(u8, lhs_verbatim_literal, rhs_verbatim_literal)) return false;
        const lhs_names = lhs_annotations.procedures.items;
        const rhs_names = rhs_annotations.procedures.items;
        if (lhs_names.len != rhs_names.len) return false;
        for (lhs_names, rhs_names) |lhs_name, rhs_name| if (!std.mem.eql(u8, lhs_name, rhs_name)) return false;
        return true;
    }

    fn occurrenceIsVerbatim(self: *Builder, occurrence: ?Occurrence) bool {
        if (occurrence) |value| {
            return self.grammar.rules.items[value.rule].rhs_annotations.items[value.position].verbatim;
        }
        return false;
    }

    fn planSemanticStackRequirements(self: *Builder) void {
        for (self.plan.states.items) |*state| {
            if (state.gotos.items.len > 0) {
                state.uses_semantic_stack = true;
                continue;
            }
            for (state.actions.items) |action| switch (action.kind) {
                .shift => {
                    state.uses_semantic_stack = true;
                    break;
                },
                .reduce => if (self.options.with_ast or self.options.with_procedures or self.grammar.uses_verbatim) {
                    state.uses_semantic_stack = true;
                    break;
                },
                .accept => {},
            };
        }
    }

    fn planStateDecisionsAndDiagnostics(self: *Builder) !void {
        for (self.plan.states.items, 0..) |state, state_index| {
            var entries = std.ArrayList(switch_planning.Entry).empty;
            for (state.actions.items, 0..) |action, action_index| {
                if (action.kind == .reduce and self.occurrenceIsVerbatim(action.occurrence)) {
                    try entries.append(self.allocator, .{ .terminal = "", .target = action_index });
                    continue;
                }
                for (self.grammar.symbols.items[action.terminal].terminals.items) |terminal| try entries.append(self.allocator, .{
                    .terminal = terminal,
                    .target = action_index,
                });
            }
            const tree = try switch_planning.build(self.allocator, entries.items);
            if (entries.items.len == 0) {
                tree.diagnostic = try self.addDiagnostic(state_index, tree.*, .state);
            } else try self.planActionDiagnostics(state_index, tree);

            var decision = StateDecision{ .action_tree = tree };
            if (state.gotos.items.len == 0) decision.goto_diagnostic = try self.addDiagnostic(state_index, treeForNoExpectedTokens(), .goto);
            try self.plan.state_decisions.append(self.allocator, decision);
        }
    }

    fn planActionDiagnostics(self: *Builder, state_index: usize, node: *switch_planning.Node) !void {
        for (node.groups.items) |group| {
            if (!group.child.isLeaf()) try self.planActionDiagnostics(state_index, group.child);
        }
        if (node.fallback == null) node.diagnostic = try self.addDiagnostic(state_index, node.*, .action);
    }

    fn addDiagnostic(self: *Builder, state_index: usize, node: switch_planning.Node, kind: SyntaxErrorSite) !usize {
        const index = self.plan.syntax_error_handlers.items.len;
        const stem = try std.fmt.allocPrint(self.allocator, "state_{d}_{s}", .{ state_index, @tagName(kind) });
        const error_function_name = try common.syntaxErrorFunctionName(self.allocator, "lr_", stem, index);
        try self.plan.error_message_specs.append(self.allocator, .{ .name = error_function_name });
        try self.plan.syntax_error_handlers.append(self.allocator, .{
            .name = try std.fmt.allocPrint(self.allocator, "lr_syntax_error_{d}", .{index}),
            .state_index = state_index,
            .expected_tokens = try switch_planning.expectedHeads(self.allocator, node),
            .error_function_name = error_function_name,
            .recoverable = kind != .goto,
        });
        return index;
    }

    fn planMetadata(self: *Builder) !void {
        self.plan.variable_indices = try self.allocator.alloc(?usize, self.grammar.symbols.items.len);
        self.plan.symbol_returns_stack_node = try self.allocator.alloc(bool, self.grammar.symbols.items.len);
        @memset(self.plan.variable_indices, null);
        for (self.grammar.variables.items, 0..) |symbol_index, variable_index| self.plan.variable_indices[symbol_index] = variable_index;
        for (self.grammar.symbols.items, 0..) |symbol, symbol_index| {
            self.plan.symbol_returns_stack_node[symbol_index] = common.symbolReturnsNode(symbol, self.options);
        }
        self.plan.longest_terminal_length = common.longestTerminalLengthWithRecovery(self.grammar);
    }
};

fn treeForNoExpectedTokens() switch_planning.Node {
    return .{};
}

fn appendItemUnique(items: *std.ArrayList(Item), allocator: std.mem.Allocator, item: Item) !void {
    for (items.items) |existing| if (itemEqual(existing, item)) return;
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
    for (lhs, rhs) |a, b| if (!itemEqual(a, b)) return false;
    return true;
}

fn appendTestRule(allocator: std.mem.Allocator, rules: *std.ArrayList(common.Rule), header: usize, rhs_index: []const u8, rhs: []const usize) !void {
    var rule = common.Rule{ .header = header, .rhs_index = rhs_index };
    for (rhs) |symbol| {
        try rule.rhs.append(allocator, symbol);
        try rule.rhs_annotations.append(allocator, .{});
    }
    try rules.append(allocator, rule);
}

fn testPreparedGrammar(allocator: std.mem.Allocator) !common.PreparedGrammar {
    var grammar = common.PreparedGrammar{ .augmented_start = undefined, .eof = undefined };
    const root = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Root", .variable);
    const value = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Value", .variable);
    const a = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "a", .terminal);
    grammar.augmented_start = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "_AugmentedStart", .variable);
    grammar.eof = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "\x00", .end);
    try appendTestRule(allocator, &grammar.rules, root, "0", &.{value});
    try appendTestRule(allocator, &grammar.rules, value, "0", &.{a});
    try appendTestRule(allocator, &grammar.rules, grammar.augmented_start, "0", &.{ root, grammar.eof });
    std.mem.sort(common.Rule, grammar.rules.items, grammar.symbols.items, common.ruleLessThan);
    return grammar;
}

test "LR planning completes canonical topology decisions and recovery metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const grammar = try testPreparedGrammar(allocator);
    const options = common.Options{ .with_ast = false, .with_procedures = false, .with_error_recovery = true };
    const plan = try LRPlan.build(allocator, &grammar, options);

    try std.testing.expect(plan.states.items.len > 1);
    try std.testing.expectEqual(plan.states.items.len, plan.state_decisions.items.len);
    try std.testing.expectEqual(plan.states.items.len, plan.recovery.automatic_candidates.items.len);
    try std.testing.expect(plan.syntax_error_handlers.items.len != 0);
    try std.testing.expect(plan.topologyEqual(&plan));
    for (plan.state_decisions.items) |decision| {
        if (decision.action_tree.fallback == null) try std.testing.expect(decision.action_tree.diagnostic != null);
    }
}

fn testAmbiguousGrammar(allocator: std.mem.Allocator) !common.PreparedGrammar {
    var grammar = common.PreparedGrammar{ .augmented_start = undefined, .eof = undefined };
    const root = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Root", .variable);
    const value = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Value", .variable);
    const plus = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "+", .terminal);
    const a = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "a", .terminal);
    grammar.augmented_start = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "_AugmentedStart", .variable);
    grammar.eof = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "\x00", .end);
    try appendTestRule(allocator, &grammar.rules, root, "0", &.{value});
    try appendTestRule(allocator, &grammar.rules, value, "0", &.{ value, plus, value });
    try appendTestRule(allocator, &grammar.rules, value, "1", &.{a});
    try appendTestRule(allocator, &grammar.rules, grammar.augmented_start, "0", &.{ root, grammar.eof });
    std.mem.sort(common.Rule, grammar.rules.items, grammar.symbols.items, common.ruleLessThan);
    return grammar;
}

test "LR planning reports conflicting actions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const grammar = try testAmbiguousGrammar(allocator);
    const options = common.Options{ .with_ast = false, .with_procedures = false, .with_error_recovery = false };
    try std.testing.expectError(error.AmbiguousGrammar, LRPlan.build(allocator, &grammar, options));
}
