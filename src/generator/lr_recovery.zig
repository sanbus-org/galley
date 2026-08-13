const std = @import("std");
const common = @import("generator_common");

pub const Occurrence = common.RecoveryOccurrence;

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
                try common.firstsAfterItem(allocator, grammar, parent, &lookaheads);
                const procedure_occurrence = common.procedureOccurrenceFor(grammar, options, parent.rule, parent.head);
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
