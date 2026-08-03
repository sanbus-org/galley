const std = @import("std");
const common = @import("generator_common");

pub const Occurrence = struct { rule: usize, position: usize };

pub const RecoveryClosureEdge = struct {
    parent: usize,
    child: usize,
    occurrence: Occurrence,
};

pub const StateMetadata = struct {
    kernel_items: std.ArrayList(usize) = .empty,
    closure_edges: std.ArrayList(RecoveryClosureEdge) = .empty,
};

pub const Plan = struct {
    scopes: common.RecoveryPlan = .{},
    automatic_candidates: std.ArrayList([]const []const u8) = .empty,
    explicit_metadata: std.ArrayList(StateMetadata) = .empty,
};

pub fn build(
    allocator: std.mem.Allocator,
    grammar: *const common.PreparedGrammar,
    options: common.Options,
    states: anytype,
) !Plan {
    var planner = Planner{
        .allocator = allocator,
        .grammar = grammar,
        .options = options,
    };
    var result = Plan{};
    result.scopes = try common.prepareRecoveryPlan(
        allocator,
        grammar.symbols.items,
        grammar.variables.items,
        grammar.rules.items,
    );

    if (options.with_error_recovery and !grammar.uses_explicit_recovery) {
        for (states) |state| {
            var candidates = std.ArrayList([]const u8).empty;
            for (state.actions.items) |action| {
                for (grammar.symbols.items[action.terminal].terminals.items) |terminal| {
                    for (candidates.items) |existing| {
                        if (std.mem.eql(u8, existing, terminal)) break;
                    } else try candidates.append(allocator, terminal);
                }
            }
            std.mem.sort([]const u8, candidates.items, {}, common.headLessThan);
            try result.automatic_candidates.append(allocator, try allocator.dupe([]const u8, candidates.items));
        }
    }

    if (grammar.uses_explicit_recovery) {
        for (states) |state| {
            var metadata = StateMetadata{};
            for (state.items.items, 0..) |item, item_index| {
                if (item.head == 0 and item.variable != grammar.augmented_start) continue;
                try metadata.kernel_items.append(allocator, item_index);
            }
            for (state.items.items, 0..) |parent, parent_index| {
                const parent_rule = grammar.rules.items[parent.rule];
                if (parent.head >= parent_rule.rhs.items.len) continue;
                const child_variable = parent_rule.rhs.items[parent.head];
                if (grammar.symbols.items[child_variable].kind != .variable) continue;
                var lookaheads = std.AutoHashMap(usize, void).init(allocator);
                defer lookaheads.deinit();
                try planner.firstsAfterItem(parent, &lookaheads);
                const procedure_occurrence = planner.procedureOccurrenceFor(parent.rule, parent.head);
                for (state.items.items, 0..) |child, child_index| {
                    if (child.head != 0 or child.variable != child_variable or !lookaheads.contains(child.lookahead) or
                        !std.meta.eql(child.occurrence, procedure_occurrence)) continue;
                    try metadata.closure_edges.append(allocator, .{
                        .parent = parent_index,
                        .child = child_index,
                        .occurrence = .{ .rule = parent.rule, .position = parent.head },
                    });
                }
            }
            try result.explicit_metadata.append(allocator, metadata);
        }
    }
    return result;
}

const Planner = struct {
    allocator: std.mem.Allocator,
    grammar: *const common.PreparedGrammar,
    options: common.Options,

    fn firstsAfterItem(self: *Planner, item: anytype, out: *std.AutoHashMap(usize, void)) !void {
        const rule = self.grammar.rules.items[item.rule];
        var index = item.head + 1;
        while (index < rule.rhs.items.len) : (index += 1) {
            const symbol_index = rule.rhs.items[index];
            const symbol = self.grammar.symbols.items[symbol_index];
            if (symbol.kind == .variable) {
                try self.firstsOfVariable(symbol_index, out, null);
                if (try self.nullableRule(symbol_index, null) == null) return;
            } else {
                try out.put(symbol_index, {});
                return;
            }
        }
        try out.put(item.lookahead, {});
    }

    fn firstsOfVariable(self: *Planner, variable: usize, out: *std.AutoHashMap(usize, void), visited: ?*std.AutoHashMap(usize, void)) !void {
        if (visited) |set| if (set.contains(variable)) return;
        var local_visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer local_visited.deinit();
        if (visited) |set| {
            var it = set.keyIterator();
            while (it.next()) |entry| try local_visited.put(entry.*, {});
        }
        try local_visited.put(variable, {});
        for (self.grammar.rules.items) |rule| {
            if (rule.header != variable) continue;
            for (rule.rhs.items) |symbol_index| {
                const symbol = self.grammar.symbols.items[symbol_index];
                if (symbol.kind == .variable) {
                    try self.firstsOfVariable(symbol_index, out, &local_visited);
                    if (try self.nullableRule(symbol_index, null) == null) break;
                } else {
                    try out.put(symbol_index, {});
                    break;
                }
            }
        }
    }

    fn nullableRule(self: *Planner, variable: usize, visited: ?*std.AutoHashMap(usize, void)) !?usize {
        if (visited) |set| if (set.contains(variable)) return null;
        var local_visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer local_visited.deinit();
        if (visited) |set| {
            var it = set.keyIterator();
            while (it.next()) |entry| try local_visited.put(entry.*, {});
        }
        try local_visited.put(variable, {});
        for (self.grammar.rules.items, 0..) |rule, rule_index| {
            if (rule.header != variable) continue;
            for (rule.rhs.items) |symbol_index| {
                if (self.grammar.symbols.items[symbol_index].kind != .variable or try self.nullableRule(symbol_index, &local_visited) == null) break;
            } else return rule_index;
        }
        return null;
    }

    fn procedureOccurrenceFor(self: *Planner, rule_index: usize, position: usize) ?Occurrence {
        const rule = self.grammar.rules.items[rule_index];
        if (position >= rule.rhs.items.len) return null;
        const annotations = rule.rhs_annotations.items[position];
        if (!self.options.with_procedures or annotations.procedures.items.len == 0) return null;
        const symbol = self.grammar.symbols.items[rule.rhs.items[position]];
        const has_node = switch (symbol.kind) {
            .variable => symbol.ast_enabled,
            .terminal, .generative_terminal => self.options.ast_for_terminals,
            .end => false,
        };
        return if (has_node) .{ .rule = rule_index, .position = position } else null;
    }
};
