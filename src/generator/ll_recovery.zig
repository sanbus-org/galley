const std = @import("std");
const common = @import("generator_common");

pub const Plan = struct {
    scopes: common.RecoveryPlan = .{},
    automatic_candidates: std.AutoHashMap(usize, []const []const u8),

    pub fn init(allocator: std.mem.Allocator) Plan {
        return .{ .automatic_candidates = std.AutoHashMap(usize, []const []const u8).init(allocator) };
    }
};

pub fn build(
    allocator: std.mem.Allocator,
    grammar: *const common.PreparedGrammar,
    options: common.Options,
    nullable_rules: []const ?usize,
    first_sets: anytype,
    follow_sets: anytype,
) !Plan {
    var result = Plan.init(allocator);
    result.scopes = try common.prepareRecoveryPlan(
        allocator,
        grammar.symbols.items,
        grammar.variables.items,
        grammar.rules.items,
    );
    // Automatic-recovery candidates are a grammar fact: every generated
    // variant must find the table present, because which recovery style is
    // active is selected at comptime per configuration.
    if (!grammar.uses_explicit_recovery) {
        _ = options;
        for (grammar.symbols.items, 0..) |symbol, symbol_index| {
            var candidates = std.ArrayList([]const u8).empty;
            var sequence_is_nullable = true;
            if (symbol.kind == .variable) {
                for (first_sets[symbol_index]) |entry| {
                    for (grammar.symbols.items[entry.terminal].terminals.items) |terminal| {
                        try common.appendUniqueString(&candidates, allocator, terminal);
                    }
                }
                if (nullable_rules[symbol_index] == null) sequence_is_nullable = false;
            } else {
                for (symbol.terminals.items) |terminal| try common.appendUniqueString(&candidates, allocator, terminal);
                sequence_is_nullable = false;
            }
            if (sequence_is_nullable and symbol.kind == .variable) {
                for (follow_sets[symbol_index]) |entry| {
                    for (grammar.symbols.items[entry.terminal].terminals.items) |terminal| {
                        try common.appendUniqueString(&candidates, allocator, terminal);
                    }
                }
            }
            std.mem.sort([]const u8, candidates.items, {}, common.headLessThan);
            try result.automatic_candidates.put(symbol_index, try allocator.dupe([]const u8, candidates.items));
        }
    }
    return result;
}
