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
    if (!options.with_error_recovery or grammar.uses_explicit_recovery) return result;

    for (grammar.symbols.items, 0..) |symbol, symbol_index| {
        var candidates = std.ArrayList([]const u8).empty;
        var sequence_is_nullable = true;
        if (symbol.kind == .variable) {
            for (first_sets[symbol_index]) |entry| {
                for (grammar.symbols.items[entry.terminal].terminals.items) |terminal| {
                    try appendUnique(&candidates, allocator, terminal);
                }
            }
            if (nullable_rules[symbol_index] == null) sequence_is_nullable = false;
        } else {
            for (symbol.terminals.items) |terminal| try appendUnique(&candidates, allocator, terminal);
            sequence_is_nullable = false;
        }
        if (sequence_is_nullable and symbol.kind == .variable) {
            for (follow_sets[symbol_index]) |entry| {
                for (grammar.symbols.items[entry.terminal].terminals.items) |terminal| {
                    try appendUnique(&candidates, allocator, terminal);
                }
            }
        }
        std.mem.sort([]const u8, candidates.items, {}, stringLessThan);
        try result.automatic_candidates.put(symbol_index, try allocator.dupe([]const u8, candidates.items));
    }
    return result;
}

fn appendUnique(items: *std.ArrayList([]const u8), allocator: std.mem.Allocator, value: []const u8) !void {
    for (items.items) |item| if (std.mem.eql(u8, item, value)) return;
    try items.append(allocator, value);
}

fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}
