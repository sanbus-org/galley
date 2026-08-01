const std = @import("std");
const common = @import("generator_common");
const recovery_planning = @import("ll_recovery.zig");
const switch_planning = @import("generator_switch_plan");

pub const ParseEntry = struct { variable: usize, terminal: usize, rule: usize };
pub const TerminalRule = struct { terminal: usize, rule: usize };

pub const SyntaxErrorHandler = struct {
    name: []const u8,
    symbol_index: usize,
    expected_tokens: []const []const u8,
    exact_name: []const u8,
    symbol_name: []const u8,
    skip_ast_construction: bool,
};

pub const ParserDecision = struct {
    symbol_index: usize,
    skip_ast_construction: bool,
    tree: *switch_planning.Node,
};

pub const SelfRepeatingDecision = struct {
    variable: usize,
    rule_index: usize,
    self_index: usize,
    skip_ast_construction: bool,
    cases: []const u8,
};

pub const LLPlan = struct {
    parse_table: std.ArrayList(ParseEntry) = .empty,
    nullable_rules: []?usize = &.{},
    first_sets: [][]const TerminalRule = &.{},
    follow_sets: [][]const TerminalRule = &.{},
    parser_names: [][]const u8 = &.{},
    symbol_reprs: [][]const u8 = &.{},
    emitted_symbols: []const usize = &.{},
    has_parse_entries: []bool = &.{},
    symbol_returns_node: []bool = &.{},
    variable_indices: []?usize = &.{},
    longest_terminal_length: usize = 0,
    parser_decisions: std.ArrayList(ParserDecision) = .empty,
    self_repeating_decisions: std.ArrayList(SelfRepeatingDecision) = .empty,
    error_message_specs: std.ArrayList(common.ErrorMessageSpec) = .empty,
    syntax_error_handlers: std.ArrayList(SyntaxErrorHandler) = .empty,
    needs_ast_suppressed_parser: std.AutoHashMap(usize, void),
    ast_suppressed_order: []const usize = &.{},
    recovery: recovery_planning.Plan,
    augmented_start: usize = 0,

    pub fn init(allocator: std.mem.Allocator) LLPlan {
        return .{
            .needs_ast_suppressed_parser = std.AutoHashMap(usize, void).init(allocator),
            .recovery = recovery_planning.Plan.init(allocator),
        };
    }

    pub fn build(allocator: std.mem.Allocator, grammar: *const common.PreparedGrammar, options: common.Options) !LLPlan {
        var builder = Builder{
            .allocator = allocator,
            .grammar = grammar,
            .options = options,
            .plan = LLPlan.init(allocator),
        };
        builder.plan.augmented_start = grammar.augmented_start;
        try builder.analyzeGrammar();
        try builder.buildParseTable();
        try builder.planAstSuppressedParsers();
        try builder.finishAstSuppressedOrder();
        builder.plan.recovery = try recovery_planning.build(
            allocator,
            grammar,
            options,
            builder.plan.nullable_rules,
            builder.plan.first_sets,
            builder.plan.follow_sets,
        );
        try builder.planNames();
        try builder.planEmissionMetadata();
        try builder.planParsersAndDiagnostics();
        return builder.plan;
    }

    pub fn parserDecision(self: *const LLPlan, symbol_index: usize, skip_ast_construction: bool) *const ParserDecision {
        for (self.parser_decisions.items) |*decision| {
            if (decision.symbol_index == symbol_index and decision.skip_ast_construction == skip_ast_construction) return decision;
        }
        unreachable;
    }

    pub fn selfRepeatingDecision(self: *const LLPlan, variable: usize, rule_index: usize, self_index: usize, skip_ast_construction: bool) *const SelfRepeatingDecision {
        for (self.self_repeating_decisions.items) |*decision| {
            if (decision.variable == variable and decision.rule_index == rule_index and decision.self_index == self_index and decision.skip_ast_construction == skip_ast_construction) return decision;
        }
        unreachable;
    }
};

const Builder = struct {
    allocator: std.mem.Allocator,
    grammar: *const common.PreparedGrammar,
    options: common.Options,
    plan: LLPlan,

    fn analyzeGrammar(self: *Builder) !void {
        self.plan.nullable_rules = try self.allocator.alloc(?usize, self.grammar.symbols.items.len);
        @memset(self.plan.nullable_rules, null);
        self.plan.first_sets = try self.allocator.alloc([]const TerminalRule, self.grammar.symbols.items.len);
        self.plan.follow_sets = try self.allocator.alloc([]const TerminalRule, self.grammar.symbols.items.len);
        for (self.plan.first_sets) |*set| set.* = &.{};
        for (self.plan.follow_sets) |*set| set.* = &.{};

        for (self.grammar.variables.items) |variable| {
            self.plan.nullable_rules[variable] = self.nullableRule(variable);
            var first_map = std.AutoHashMap(usize, usize).init(self.allocator);
            defer first_map.deinit();
            try self.firsts(variable, &first_map, null);
            self.plan.first_sets[variable] = try self.terminalRulesFromMap(first_map);

            var follow_map = std.AutoHashMap(usize, usize).init(self.allocator);
            defer follow_map.deinit();
            try self.follows(variable, &follow_map, null);
            self.plan.follow_sets[variable] = try self.terminalRulesFromMap(follow_map);
        }
    }

    fn terminalRulesFromMap(self: *Builder, map: std.AutoHashMap(usize, usize)) ![]const TerminalRule {
        var result = std.ArrayList(TerminalRule).empty;
        var iterator = map.iterator();
        while (iterator.next()) |entry| {
            try result.append(self.allocator, .{ .terminal = entry.key_ptr.*, .rule = entry.value_ptr.* });
        }
        return result.toOwnedSlice(self.allocator);
    }

    fn nullableRule(self: *Builder, variable: usize) ?usize {
        var visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer visited.deinit();
        return self.nullableRuleImpl(variable, &visited);
    }

    fn nullableRuleImpl(self: *Builder, variable: usize, visited: *std.AutoHashMap(usize, void)) ?usize {
        if (visited.contains(variable)) return null;
        visited.put(variable, {}) catch return null;
        defer _ = visited.remove(variable);
        for (self.grammar.rules.items, 0..) |rule, rule_index| {
            if (rule.header != variable) continue;
            for (rule.rhs.items) |symbol_index| {
                if (self.grammar.symbols.items[symbol_index].kind != .variable or self.nullableRuleImpl(symbol_index, visited) == null) break;
            } else return rule_index;
        }
        return null;
    }

    fn firsts(self: *Builder, variable: usize, out: *std.AutoHashMap(usize, usize), visited: ?*std.AutoHashMap(usize, void)) !void {
        if (visited) |set| {
            if (set.contains(variable)) return;
        }
        var local_visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer local_visited.deinit();
        if (visited) |set| {
            var it = set.iterator();
            while (it.next()) |entry| try local_visited.put(entry.key_ptr.*, {});
        }
        try local_visited.put(variable, {});

        for (self.grammar.rules.items, 0..) |rule, rule_index| {
            if (rule.header != variable) continue;
            for (rule.rhs.items) |symbol_index| {
                const symbol = self.grammar.symbols.items[symbol_index];
                if (symbol.kind == .variable) {
                    var child_firsts = std.AutoHashMap(usize, usize).init(self.allocator);
                    defer child_firsts.deinit();
                    try self.firsts(symbol_index, &child_firsts, &local_visited);
                    var child_iterator = child_firsts.iterator();
                    while (child_iterator.next()) |entry| try putUnique(out, entry.key_ptr.*, rule_index);
                } else {
                    try putUnique(out, symbol_index, rule_index);
                }
                if (symbol.kind != .variable or self.nullableRule(symbol_index) == null) break;
            }
        }
    }

    fn follows(self: *Builder, variable: usize, out: *std.AutoHashMap(usize, usize), visited: ?*std.AutoHashMap(usize, void)) !void {
        if (visited) |set| {
            if (set.contains(variable)) return;
        }
        var local_visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer local_visited.deinit();
        if (visited) |set| {
            var it = set.iterator();
            while (it.next()) |entry| try local_visited.put(entry.key_ptr.*, {});
        }
        try local_visited.put(variable, {});

        for (self.grammar.rules.items, 0..) |rule, rule_index| {
            for (rule.rhs.items, 0..) |symbol_index, rhs_pos| {
                if (symbol_index != variable) continue;
                var propagated = true;
                var next_pos = rhs_pos + 1;
                while (next_pos < rule.rhs.items.len) : (next_pos += 1) {
                    const next_symbol_index = rule.rhs.items[next_pos];
                    const next_symbol = self.grammar.symbols.items[next_symbol_index];
                    if (next_symbol.kind == .variable) {
                        var next_firsts = std.AutoHashMap(usize, usize).init(self.allocator);
                        defer next_firsts.deinit();
                        try self.firsts(next_symbol_index, &next_firsts, null);
                        var it = next_firsts.iterator();
                        while (it.next()) |entry| try out.put(entry.key_ptr.*, entry.value_ptr.*);
                    } else {
                        try out.put(next_symbol_index, rule_index);
                    }
                    if (next_symbol.kind != .variable or self.nullableRule(next_symbol_index) == null) {
                        propagated = false;
                        break;
                    }
                }
                if (propagated and rule.header != variable) {
                    try self.follows(rule.header, out, &local_visited);
                }
            }
        }
    }

    fn buildParseTable(self: *Builder) !void {
        for (self.grammar.variables.items) |variable| {
            for (self.plan.first_sets[variable]) |entry| try self.addParseEntry(.{ .variable = variable, .terminal = entry.terminal, .rule = entry.rule });
            if (self.plan.nullable_rules[variable]) |rule_index| {
                for (self.plan.follow_sets[variable]) |entry| try self.addParseEntry(.{ .variable = variable, .terminal = entry.terminal, .rule = rule_index });
            }
        }
    }

    fn addParseEntry(self: *Builder, entry: ParseEntry) !void {
        for (self.plan.parse_table.items) |existing| {
            if (existing.variable != entry.variable or existing.terminal != entry.terminal) continue;
            if (existing.rule != entry.rule) return error.AmbiguousGrammar;
            return;
        }
        try self.plan.parse_table.append(self.allocator, entry);
    }

    fn hasParseEntries(self: *Builder, variable: usize) bool {
        for (self.plan.parse_table.items) |entry| if (entry.variable == variable) return true;
        return false;
    }

    fn hasParseEntryForRule(self: *Builder, variable: usize, rule_index: usize) bool {
        for (self.plan.parse_table.items) |entry| if (entry.variable == variable and entry.rule == rule_index) return true;
        return false;
    }

    fn planAstSuppressedParsers(self: *Builder) !void {
        if (!self.options.with_ast) return;
        for (self.grammar.variables.items) |variable| {
            if (self.hasParseEntries(variable)) try self.planAstSuppressedChildren(variable, false);
        }
        var generated = std.AutoHashMap(usize, void).init(self.allocator);
        while (generated.count() < self.plan.needs_ast_suppressed_parser.count()) {
            for (self.grammar.symbols.items, 0..) |symbol, symbol_index| {
                if (!self.plan.needs_ast_suppressed_parser.contains(symbol_index) or generated.contains(symbol_index)) continue;
                try generated.put(symbol_index, {});
                if (symbol.kind == .variable and self.hasParseEntries(symbol_index)) try self.planAstSuppressedChildren(symbol_index, true);
            }
        }
    }

    fn planAstSuppressedChildren(self: *Builder, variable: usize, parent_skips_ast: bool) !void {
        for (self.grammar.rules.items, 0..) |rule, rule_index| {
            if (rule.header != variable) continue;
            var self_repeating = false;
            for (rule.rhs.items) |symbol_index| if (symbol_index == variable) {
                self_repeating = true;
                break;
            };
            if (!self_repeating and !self.hasParseEntryForRule(variable, rule_index)) continue;
            for (rule.rhs.items) |symbol_index| {
                const child = self.grammar.symbols.items[symbol_index];
                if (parent_skips_ast or (child.kind == .variable and !child.ast_enabled)) try self.plan.needs_ast_suppressed_parser.put(symbol_index, {});
            }
        }
    }

    fn finishAstSuppressedOrder(self: *Builder) !void {
        var ordered = std.ArrayList(usize).empty;
        for (0..self.grammar.symbols.items.len) |symbol_index| {
            if (self.plan.needs_ast_suppressed_parser.contains(symbol_index)) try ordered.append(self.allocator, symbol_index);
        }
        self.plan.ast_suppressed_order = try ordered.toOwnedSlice(self.allocator);
    }

    fn planNames(self: *Builder) !void {
        self.plan.parser_names = try self.allocator.alloc([]const u8, self.grammar.symbols.items.len);
        self.plan.symbol_reprs = try self.allocator.alloc([]const u8, self.grammar.symbols.items.len);
        for (self.grammar.symbols.items, 0..) |symbol, index| {
            if (symbol.kind == .end) {
                self.plan.parser_names[index] = try self.allocator.dupe(u8, "special_EOF");
                self.plan.symbol_reprs[index] = self.plan.parser_names[index];
                continue;
            }
            const prefix = switch (symbol.kind) {
                .variable => "",
                .terminal => "terminal_",
                .generative_terminal => "generative_terminal_",
                .end => unreachable,
            };
            const repr = try common.readableSymbolName(self.allocator, symbol.id);
            self.plan.symbol_reprs[index] = try std.mem.concat(self.allocator, u8, &.{ prefix, repr });
            self.plan.parser_names[index] = try common.safeIdentifier(self.allocator, self.plan.symbol_reprs[index]);
        }
    }

    fn planEmissionMetadata(self: *Builder) !void {
        const symbol_count = self.grammar.symbols.items.len;
        self.plan.has_parse_entries = try self.allocator.alloc(bool, symbol_count);
        self.plan.symbol_returns_node = try self.allocator.alloc(bool, symbol_count);
        self.plan.variable_indices = try self.allocator.alloc(?usize, symbol_count);
        @memset(self.plan.has_parse_entries, false);
        @memset(self.plan.variable_indices, null);

        for (self.plan.parse_table.items) |entry| self.plan.has_parse_entries[entry.variable] = true;
        for (self.grammar.variables.items, 0..) |symbol_index, variable_index| self.plan.variable_indices[symbol_index] = variable_index;

        var emitted = std.ArrayList(usize).empty;
        for (self.grammar.symbols.items, 0..) |symbol, symbol_index| {
            self.plan.symbol_returns_node[symbol_index] = common.symbolReturnsNode(symbol, self.options);
            if (symbol.kind != .variable or self.plan.has_parse_entries[symbol_index]) try emitted.append(self.allocator, symbol_index);
        }
        self.plan.emitted_symbols = try emitted.toOwnedSlice(self.allocator);

        const grammar_longest = common.longestTerminalLength(self.grammar.symbols.items);
        self.plan.longest_terminal_length = if (self.grammar.uses_explicit_recovery)
            @max(grammar_longest, common.longestRecoveryTerminalLength(self.grammar.symbols.items, self.grammar.rules.items))
        else
            grammar_longest;
    }

    fn planParsersAndDiagnostics(self: *Builder) !void {
        for (self.grammar.symbols.items, 0..) |symbol, symbol_index| {
            if (symbol.kind == .variable and !self.hasParseEntries(symbol_index)) continue;
            try self.planParser(symbol_index, false);
        }
        for (self.grammar.symbols.items, 0..) |symbol, symbol_index| {
            if (!self.plan.needs_ast_suppressed_parser.contains(symbol_index)) continue;
            if (symbol.kind == .variable and !self.hasParseEntries(symbol_index)) continue;
            try self.planParser(symbol_index, true);
        }
    }

    fn planParser(self: *Builder, symbol_index: usize, skip_ast_construction: bool) !void {
        const symbol = self.grammar.symbols.items[symbol_index];
        var entries = std.ArrayList(switch_planning.Entry).empty;
        if (symbol.kind == .variable) {
            for (self.plan.parse_table.items) |entry| {
                if (entry.variable != symbol_index) continue;
                for (self.grammar.symbols.items[entry.terminal].terminals.items) |terminal| try entries.append(self.allocator, .{ .terminal = terminal, .target = entry.rule });
            }
            for (self.grammar.rules.items, 0..) |rule, rule_index| {
                if (rule.header != symbol_index) continue;
                for (rule.rhs.items, 0..) |child, self_index| {
                    if (child != symbol_index) continue;
                    var cases = std.ArrayList(u8).empty;
                    for (self.plan.parse_table.items) |entry| {
                        if (entry.variable != symbol_index or entry.rule != rule_index) continue;
                        for (self.grammar.symbols.items[entry.terminal].terminals.items) |terminal| {
                            if (terminal.len > 0 and !byteContains(cases.items, terminal[0])) try cases.append(self.allocator, terminal[0]);
                        }
                    }
                    std.mem.sort(u8, cases.items, {}, comptime std.sort.asc(u8));
                    try self.plan.self_repeating_decisions.append(self.allocator, .{
                        .variable = symbol_index,
                        .rule_index = rule_index,
                        .self_index = self_index,
                        .skip_ast_construction = skip_ast_construction,
                        .cases = try cases.toOwnedSlice(self.allocator),
                    });
                }
            }
        } else {
            for (symbol.terminals.items) |terminal| try entries.append(self.allocator, .{ .terminal = terminal, .target = 0 });
        }
        const tree = try switch_planning.build(self.allocator, entries.items);
        try self.plan.parser_decisions.append(self.allocator, .{
            .symbol_index = symbol_index,
            .skip_ast_construction = skip_ast_construction,
            .tree = tree,
        });
        try self.planTreeDiagnostics(symbol_index, skip_ast_construction, tree, false);
    }

    fn planTreeDiagnostics(self: *Builder, symbol_index: usize, skip_ast_construction: bool, node: *switch_planning.Node, self_repeating: bool) !void {
        for (node.groups.items) |group| try self.planTreeDiagnostics(symbol_index, skip_ast_construction, group.child, self_repeating);
        if (node.fallback == null and !self_repeating) {
            node.diagnostic = self.plan.syntax_error_handlers.items.len;
            const expected = try switch_planning.expectedHeads(self.allocator, node.*);
            const names = try self.syntaxErrorFunctionNames(symbol_index, node.*);
            try self.plan.syntax_error_handlers.append(self.allocator, .{
                .name = try std.fmt.allocPrint(self.allocator, "ll_syntax_error_{d}", .{node.diagnostic.?}),
                .symbol_index = symbol_index,
                .expected_tokens = expected,
                .exact_name = names.exact,
                .symbol_name = names.symbol,
                .skip_ast_construction = skip_ast_construction,
            });
        }
    }

    fn syntaxErrorFunctionNames(self: *Builder, symbol_index: usize, node: switch_planning.Node) !struct { exact: []const u8, symbol: []const u8 } {
        const symbol_stem = self.plan.parser_names[symbol_index];
        const expected_stem = try self.syntaxErrorExpectedStem(symbol_index, node);
        const exact = try std.fmt.allocPrint(self.allocator, "syntax_error_ll_{s}__expected_{s}", .{ symbol_stem, expected_stem });
        const symbol = try std.fmt.allocPrint(self.allocator, "syntax_error_ll_{s}", .{symbol_stem});
        try self.appendErrorMessageSpec(exact);
        return .{ .exact = exact, .symbol = symbol };
    }

    fn syntaxErrorExpectedStem(self: *Builder, symbol_index: usize, node: switch_planning.Node) ![]const u8 {
        var stems = std.ArrayList([]const u8).empty;
        if (node.groups.items.len == 0) {
            try appendUniqueString(&stems, self.allocator, try std.fmt.allocPrint(self.allocator, "valid_{s}", .{self.plan.parser_names[symbol_index]}));
        } else if (self.grammar.symbols.items[symbol_index].kind == .variable) {
            for (node.groups.items) |group| {
                for (group.child.entries) |entry| try appendUniqueString(&stems, self.allocator, try self.ruleExpectedStem(symbol_index, entry.target));
            }
        } else try appendUniqueString(&stems, self.allocator, self.plan.parser_names[symbol_index]);
        if (stems.items.len == 0) try appendUniqueString(&stems, self.allocator, try std.fmt.allocPrint(self.allocator, "valid_{s}", .{self.plan.parser_names[symbol_index]}));
        std.mem.sort([]const u8, stems.items, {}, stringLessThan);
        return joinWithOr(self.allocator, stems.items);
    }

    fn ruleExpectedStem(self: *Builder, symbol_index: usize, rule_index: usize) ![]const u8 {
        if (rule_index >= self.grammar.rules.items.len) return self.plan.parser_names[symbol_index];
        const rule = self.grammar.rules.items[rule_index];
        if (rule.header != symbol_index) return self.plan.parser_names[symbol_index];
        if (rule.rhs.items.len == 0) return std.fmt.allocPrint(self.allocator, "end_of_{s}", .{self.plan.parser_names[symbol_index]});
        return self.plan.parser_names[rule.rhs.items[0]];
    }

    fn appendErrorMessageSpec(self: *Builder, name: []const u8) !void {
        for (self.plan.error_message_specs.items) |spec| if (std.mem.eql(u8, spec.name, name)) return;
        try self.plan.error_message_specs.append(self.allocator, .{ .name = name });
    }
};

fn putUnique(map: *std.AutoHashMap(usize, usize), key: usize, value: usize) !void {
    if (map.get(key)) |existing| {
        if (existing != value) return error.AmbiguousGrammar;
        return;
    }
    try map.put(key, value);
}

fn byteContains(items: []const u8, byte: u8) bool {
    for (items) |item| if (item == byte) return true;
    return false;
}

fn appendUniqueString(items: *std.ArrayList([]const u8), allocator: std.mem.Allocator, value: []const u8) !void {
    for (items.items) |item| if (std.mem.eql(u8, item, value)) return;
    try items.append(allocator, value);
}

fn stringLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

fn joinWithOr(allocator: std.mem.Allocator, items: []const []const u8) ![]const u8 {
    if (items.len == 0) return allocator.dupe(u8, "valid_input");
    if (items.len == 1) return allocator.dupe(u8, items[0]);
    var out = std.ArrayList(u8).empty;
    for (items, 0..) |item, index| {
        if (index != 0) try out.appendSlice(allocator, "_or_");
        try out.appendSlice(allocator, item);
    }
    return out.toOwnedSlice(allocator);
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
    const optional = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "_Optional", .variable);
    const a = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "a", .terminal);
    const b = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "b", .terminal);
    grammar.augmented_start = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "_AugmentedStart", .variable);
    grammar.eof = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "\x00", .end);
    grammar.generative_terminal = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "GenerativeTerminal", .variable);
    try appendTestRule(allocator, &grammar.rules, root, "0", &.{ optional, b });
    try appendTestRule(allocator, &grammar.rules, optional, "0", &.{a});
    try appendTestRule(allocator, &grammar.rules, optional, "1", &.{});
    try appendTestRule(allocator, &grammar.rules, grammar.augmented_start, "0", &.{ root, grammar.eof });
    try appendTestRule(allocator, &grammar.rules, grammar.generative_terminal.?, "0", &.{});
    std.mem.sort(common.Rule, grammar.rules.items, grammar.symbols.items, common.ruleLessThan);
    return grammar;
}

test "LL planning completes analysis recovery switches and suppressed closure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var grammar = try testPreparedGrammar(allocator);
    const options = common.Options{ .with_ast = true, .with_procedures = false, .with_error_recovery = true };
    const plan = try LLPlan.build(allocator, &grammar, options);

    var root: usize = undefined;
    var optional: usize = undefined;
    for (grammar.symbols.items, 0..) |symbol, index| {
        if (std.mem.eql(u8, symbol.id, "Root")) root = index;
        if (std.mem.eql(u8, symbol.id, "_Optional")) optional = index;
    }
    try std.testing.expect(plan.nullable_rules[optional] != null);
    try std.testing.expect(plan.has_parse_entries[root]);
    try std.testing.expect(plan.recovery.automatic_candidates.get(root).?.len >= 2);
    try std.testing.expect(plan.needs_ast_suppressed_parser.contains(optional));
    try std.testing.expect(plan.syntax_error_handlers.items.len != 0);
    for (plan.parser_decisions.items) |decision| {
        if (decision.tree.fallback == null) try std.testing.expect(decision.tree.diagnostic != null);
    }
}
