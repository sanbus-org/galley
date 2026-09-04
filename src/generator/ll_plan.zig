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
    tree: *switch_planning.Node,
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

    pub fn build(allocator: std.mem.Allocator, grammar: *common.PreparedGrammar, options: common.Options) !LLPlan {
        var factoring_steps: usize = 0;
        while (true) {
            var builder = Builder{
                .allocator = allocator,
                .grammar = grammar,
                .options = options,
                .plan = LLPlan.init(allocator),
            };
            builder.plan.augmented_start = grammar.augmented_start;
            try builder.analyzeGrammar();
            try builder.buildParseTable();
            if (builder.pending_ambiguity) |ambiguity| {
                if (try factorSharedPrefixStep(allocator, grammar, options, ambiguity)) {
                    factoring_steps += 1;
                    if (factoring_steps > max_automatic_factoring_steps) {
                        try builder.reportAmbiguity(ambiguity.variable, ambiguity.terminal, ambiguity.rule_a, ambiguity.rule_b);
                        return error.AmbiguousGrammar;
                    }
                    continue;
                }
                try builder.reportAmbiguity(ambiguity.variable, ambiguity.terminal, ambiguity.rule_a, ambiguity.rule_b);
                return error.AmbiguousGrammar;
            }
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

const Ambiguity = struct { variable: usize, terminal: usize, rule_a: usize, rule_b: usize };

/// Bounds automatic left-factoring rewrites per grammar so a pathological
/// conflict cycle fails with `AmbiguousGrammar` instead of looping.
const max_automatic_factoring_steps: usize = 64;

/// Applies one automatic left-factoring rewrite for `ambiguity` when the two
/// conflicting productions share a nonempty RHS prefix whose occurrence
/// annotations agree in every sharing rule. The shared prefix is hoisted
/// into a fresh synthetic-transparent `<Variable>_Tail` variable — the same
/// shape the diagnostic suggests, minus the node: the emitter expands the
/// tail's alternatives inline at the single parent call site, so suffix
/// children splice directly into the parent with identical trees and no new
/// hooks. Returns false when the conflict has no hoistable prefix (indirect
/// FIRST overlap, FIRST/FOLLOW clash, diverging prefix annotations, or
/// production-level annotations on a sharing rule, which would lose their
/// reduction site), in which case the caller still reports
/// `AmbiguousGrammar`.
fn factorSharedPrefixStep(
    allocator: std.mem.Allocator,
    grammar: *common.PreparedGrammar,
    options: common.Options,
    ambiguity: Ambiguity,
) !bool {
    _ = options;
    const variable = ambiguity.variable;
    const rhs_a = grammar.rules.items[ambiguity.rule_a].rhs.items;
    const rhs_b = grammar.rules.items[ambiguity.rule_b].rhs.items;
    var prefix_len: usize = 0;
    while (prefix_len < rhs_a.len and prefix_len < rhs_b.len and rhs_a[prefix_len] == rhs_b[prefix_len]) : (prefix_len += 1) {}
    if (prefix_len == 0) return false;

    var sharing = std.ArrayList(usize).empty;
    for (grammar.rules.items, 0..) |rule, rule_index| {
        if (rule.header != variable) continue;
        if (rule.rhs.items.len < prefix_len) continue;
        var matches = true;
        for (rhs_a[0..prefix_len], 0..) |symbol_index, position| {
            if (rule.rhs.items[position] != symbol_index) {
                matches = false;
                break;
            }
        }
        if (matches) try sharing.append(allocator, rule_index);
    }
    if (sharing.items.len < 2) return false;

    const first_rule = grammar.rules.items[sharing.items[0]];
    for (sharing.items[1..]) |rule_index| {
        const rule = grammar.rules.items[rule_index];
        for (0..prefix_len) |position| {
            if (!annotationsEqual(first_rule.rhs_annotations.items[position], rule.rhs_annotations.items[position])) return false;
        }
    }

    // Transparent splice has no reduction site for production-level
    // annotations: each sharing rule's own procedures, recovery scope, and
    // verbatim markers would have nowhere to fire once the alternatives
    // merge into one parent production.
    for (sharing.items) |rule_index| {
        if (!ruleAnnotationsEmpty(grammar.rules.items[rule_index].annotations)) return false;
    }

    const variable_name = try common.symbolText(allocator, grammar.symbols.items, variable);
    defer allocator.free(variable_name);
    const tail_name = try allocateTailName(allocator, grammar, variable_name);
    defer allocator.free(tail_name);
    const tail = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, tail_name, .variable);
    // Not `_`-prefixed on purpose: `_` drops the subtree, while the tail's
    // suffix children must survive spliced into the parent. The dedicated
    // internal flag keeps `ast_enabled` true so planning treats the tail
    // normally; only emission and hook coverage know it is transparent.
    grammar.symbols.items[tail].synthetic_transparent = true;

    var factored_rule = common.Rule{ .header = variable, .rhs_index = "" };
    for (rhs_a[0..prefix_len], 0..) |symbol_index, position| {
        try factored_rule.rhs.append(allocator, symbol_index);
        try factored_rule.rhs_annotations.append(allocator, try cloneAnnotations(allocator, first_rule.rhs_annotations.items[position]));
    }
    try factored_rule.rhs.append(allocator, tail);
    try factored_rule.rhs_annotations.append(allocator, .{});

    var tail_rules = std.ArrayList(common.Rule).empty;
    for (sharing.items) |rule_index| {
        const rule = grammar.rules.items[rule_index];
        var tail_rule = common.Rule{ .header = tail, .rhs_index = "" };
        tail_rule.annotations = try cloneAnnotations(allocator, rule.annotations);
        for (rule.rhs.items[prefix_len..], prefix_len..) |symbol_index, position| {
            try tail_rule.rhs.append(allocator, symbol_index);
            try tail_rule.rhs_annotations.append(allocator, try cloneAnnotations(allocator, rule.rhs_annotations.items[position]));
        }
        try tail_rules.append(allocator, tail_rule);
    }

    var removal = sharing.items.len;
    while (removal > 0) {
        removal -= 1;
        _ = grammar.rules.orderedRemove(sharing.items[removal]);
    }
    try grammar.rules.append(allocator, factored_rule);
    for (tail_rules.items) |tail_rule| try grammar.rules.append(allocator, tail_rule);

    std.mem.sort(common.Rule, grammar.rules.items, grammar.symbols.items, common.ruleLessThan);
    try renumberRhsIndices(allocator, grammar, variable);
    try renumberRhsIndices(allocator, grammar, tail);
    return true;
}

/// Rewrites a prepared grammar's shared prefixes to fixpoint without
/// planning anything else, so strict hook collection for LL sees the same
/// productions the LL emitter's comptime check sees. Grammars with no
/// factorable conflict are returned untouched.
pub fn factorSharedPrefixes(allocator: std.mem.Allocator, grammar: *common.PreparedGrammar) !void {
    var steps: usize = 0;
    while (try factorOneConflict(allocator, grammar)) {
        steps += 1;
        if (steps > max_automatic_factoring_steps) return;
    }
}

fn factorOneConflict(allocator: std.mem.Allocator, grammar: *common.PreparedGrammar) !bool {
    var probe = Builder{
        .allocator = allocator,
        .grammar = grammar,
        .options = .{},
        .plan = LLPlan.init(allocator),
    };
    try probe.analyzeGrammar();
    try probe.buildParseTable();
    const ambiguity = probe.pending_ambiguity orelse return false;
    return factorSharedPrefixStep(allocator, grammar, .{}, ambiguity);
}

fn cloneAnnotations(allocator: std.mem.Allocator, source: common.Annotations) !common.Annotations {
    var result = common.Annotations{
        .verbatim = source.verbatim,
        .verbatim_consume = source.verbatim_consume,
    };
    if (source.verbatim_literal) |literal| result.verbatim_literal = try allocator.dupe(u8, literal);
    for (source.procedures.items) |name| try result.procedures.append(allocator, try allocator.dupe(u8, name));
    for (source.recovery_points.items) |point| {
        try result.recovery_points.append(allocator, .{
            .terminal = try allocator.dupe(u8, point.terminal),
            .@"resume" = point.@"resume",
        });
    }
    return result;
}

fn renumberRhsIndices(allocator: std.mem.Allocator, grammar: *common.PreparedGrammar, header: usize) !void {
    var next: usize = 0;
    for (grammar.rules.items) |*rule| {
        if (rule.header != header) continue;
        rule.rhs_index = try std.fmt.allocPrint(allocator, "{d}", .{next});
        next += 1;
    }
}

fn annotationsEqual(a: common.Annotations, b: common.Annotations) bool {
    if (a.procedures.items.len != b.procedures.items.len) return false;
    for (a.procedures.items, b.procedures.items) |a_name, b_name| {
        if (!std.mem.eql(u8, a_name, b_name)) return false;
    }
    if (a.recovery_points.items.len != b.recovery_points.items.len) return false;
    for (a.recovery_points.items, b.recovery_points.items) |a_point, b_point| {
        if (!std.mem.eql(u8, a_point.terminal, b_point.terminal)) return false;
        if (a_point.@"resume" != b_point.@"resume") return false;
    }
    if (a.verbatim != b.verbatim) return false;
    if (a.verbatim_consume != b.verbatim_consume) return false;
    if (a.verbatim_literal == null and b.verbatim_literal == null) return true;
    if (a.verbatim_literal == null or b.verbatim_literal == null) return false;
    return std.mem.eql(u8, a.verbatim_literal.?, b.verbatim_literal.?);
}

fn ruleAnnotationsEmpty(annotations: common.Annotations) bool {
    return annotations.procedures.items.len == 0 and
        annotations.recovery_points.items.len == 0 and
        !annotations.verbatim and
        annotations.verbatim_literal == null;
}

fn allocateTailName(allocator: std.mem.Allocator, grammar: *const common.PreparedGrammar, variable_name: []const u8) ![]const u8 {
    var candidate = try std.fmt.allocPrint(allocator, "{s}_Tail", .{variable_name});
    var suffix: usize = 0;
    while (hasSymbolId(grammar, candidate)) : (suffix += 1) {
        allocator.free(candidate);
        candidate = try std.fmt.allocPrint(allocator, "{s}_Tail{d}", .{ variable_name, suffix });
    }
    return candidate;
}

fn hasSymbolId(grammar: *const common.PreparedGrammar, id: []const u8) bool {
    for (grammar.symbols.items) |symbol| {
        if (std.mem.eql(u8, symbol.id, id)) return true;
    }
    return false;
}

const Builder = struct {
    allocator: std.mem.Allocator,
    grammar: *common.PreparedGrammar,
    options: common.Options,
    plan: LLPlan,
    pending_ambiguity: ?Ambiguity = null,

    fn analyzeGrammar(self: *Builder) !void {
        self.plan.nullable_rules = try self.allocator.alloc(?usize, self.grammar.symbols.items.len);
        @memset(self.plan.nullable_rules, null);
        self.plan.first_sets = try self.allocator.alloc([]const TerminalRule, self.grammar.symbols.items.len);
        self.plan.follow_sets = try self.allocator.alloc([]const TerminalRule, self.grammar.symbols.items.len);
        for (self.plan.first_sets) |*set| set.* = &.{};
        for (self.plan.follow_sets) |*set| set.* = &.{};

        for (self.grammar.variables.items) |variable| {
            self.plan.nullable_rules[variable] = try common.nullableRule(self.allocator, self.grammar, variable, null);
            var first_map = std.AutoHashMap(usize, usize).init(self.allocator);
            defer first_map.deinit();
            try self.firsts(variable, &first_map, null);
            self.plan.first_sets[variable] = try self.terminalRulesFromMap(first_map);

            var follow_map = std.AutoHashMap(usize, usize).init(self.allocator);
            defer follow_map.deinit();
            try self.follows(variable, &follow_map, null);
            self.plan.follow_sets[variable] = try self.terminalRulesFromMap(follow_map);
        }
        try common.validateVerbatimSymbols(self.allocator, self.grammar);
    }

    fn terminalRulesFromMap(self: *Builder, map: std.AutoHashMap(usize, usize)) ![]const TerminalRule {
        var result = std.ArrayList(TerminalRule).empty;
        var iterator = map.iterator();
        while (iterator.next()) |entry| {
            try result.append(self.allocator, .{ .terminal = entry.key_ptr.*, .rule = entry.value_ptr.* });
        }
        return result.toOwnedSlice(self.allocator);
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
                    while (child_iterator.next()) |entry| try self.putUnique(out, variable, entry.key_ptr.*, rule_index);
                } else {
                    try self.putUnique(out, variable, symbol_index, rule_index);
                }
                if (symbol.kind != .variable or try common.nullableRule(self.allocator, self.grammar, symbol_index, null) == null) break;
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
                        while (it.next()) |entry| try out.put(entry.key_ptr.*, rule_index);
                    } else {
                        try out.put(next_symbol_index, rule_index);
                    }
                    if (next_symbol.kind != .variable or try common.nullableRule(self.allocator, self.grammar, next_symbol_index, null) == null) {
                        propagated = false;
                        break;
                    }
                }
                if (propagated and rule.header != variable) {
                    var header_follow = std.AutoHashMap(usize, usize).init(self.allocator);
                    defer header_follow.deinit();
                    try self.follows(rule.header, &header_follow, &local_visited);
                    var it = header_follow.iterator();
                    while (it.next()) |entry| try out.put(entry.key_ptr.*, rule_index);
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
            if (existing.rule != entry.rule) {
                if (self.pending_ambiguity == null) {
                    self.pending_ambiguity = .{ .variable = entry.variable, .terminal = entry.terminal, .rule_a = existing.rule, .rule_b = entry.rule };
                }
            }
            return;
        }
        try self.plan.parse_table.append(self.allocator, entry);
    }

    fn reportAmbiguity(self: *Builder, variable: usize, terminal: usize, rule_a: usize, rule_b: usize) !void {
        const message = try self.explainConflict(variable, terminal, rule_a, rule_b);
        defer self.allocator.free(message);
        std.log.warn("{s}", .{message});
    }

    fn explainConflict(self: *Builder, variable: usize, terminal: usize, rule_a: usize, rule_b: usize) ![]const u8 {
        var out = std.ArrayList(u8).empty;
        const variable_name = try common.symbolText(self.allocator, self.grammar.symbols.items, variable);
        defer self.allocator.free(variable_name);
        const terminal_name = try common.symbolText(self.allocator, self.grammar.symbols.items, terminal);
        defer self.allocator.free(terminal_name);
        try out.appendSlice(self.allocator, "ambiguous grammar: variable ");
        try out.appendSlice(self.allocator, variable_name);
        try out.appendSlice(self.allocator, ", terminal ");
        try out.appendSlice(self.allocator, terminal_name);
        try out.appendSlice(self.allocator, " matches two productions:\n");
        try self.appendProductionChain(&out, variable, terminal, rule_a);
        try self.appendProductionChain(&out, variable, terminal, rule_b);
        if (try self.leftFactorSuggestion(variable, rule_a, rule_b)) |suggestion| {
            defer self.allocator.free(suggestion);
            try out.appendSlice(self.allocator, "  suggestion: left-factor the shared prefix\n  ");
            try out.appendSlice(self.allocator, suggestion);
            try out.appendSlice(self.allocator, "\n");
        }
        return out.toOwnedSlice(self.allocator);
    }

    fn appendProductionChain(self: *Builder, out: *std.ArrayList(u8), variable: usize, terminal: usize, rule_index: usize) !void {
        const rule_text = try common.ruleText(self.allocator, self.grammar.symbols.items, self.grammar.rules.items[rule_index]);
        defer self.allocator.free(rule_text);
        try out.appendSlice(self.allocator, "  ");
        try out.appendSlice(self.allocator, rule_text);
        try out.appendSlice(self.allocator, "\n");

        var first_visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer first_visited.deinit();
        var follow_visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer follow_visited.deinit();
        var null_visited = std.AutoHashMap(usize, void).init(self.allocator);
        defer null_visited.deinit();

        if (self.plan.nullable_rules[variable] == rule_index) {
            try self.explainFollowChain(out, variable, terminal, &follow_visited, &null_visited);
        } else {
            try self.explainFirstProduction(out, terminal, rule_index, &first_visited, &null_visited);
        }
    }

    /// Walks the conflicting production's RHS and descends into the first
    /// symbol that derives `terminal`, emitting the reason chain below the
    /// production line already rendered by `appendProductionChain`.
    fn explainFirstProduction(self: *Builder, out: *std.ArrayList(u8), terminal: usize, rule_index: usize, visited: *std.AutoHashMap(usize, void), null_visited: *std.AutoHashMap(usize, void)) !void {
        const rule = self.grammar.rules.items[rule_index];
        var nullable_prefix = std.ArrayList(usize).empty;
        defer nullable_prefix.deinit(self.allocator);
        for (rule.rhs.items) |symbol_index| {
            const symbol = self.grammar.symbols.items[symbol_index];
            if (symbol.kind != .variable) return;
            if (self.terminalInFirst(symbol_index, terminal)) {
                try self.emitNullChains(out, nullable_prefix.items, null_visited);
                try self.explainFirstChain(out, symbol_index, terminal, visited, null_visited);
                return;
            }
            if (self.plan.nullable_rules[symbol_index] != null) {
                try nullable_prefix.append(self.allocator, symbol_index);
                continue;
            }
            return;
        }
    }

    /// Explains why `terminal ∈ FIRST(variable)` by walking the stored reason
    /// rule back to the rule that contains `terminal` directly.
    fn explainFirstChain(self: *Builder, out: *std.ArrayList(u8), variable: usize, terminal: usize, visited: *std.AutoHashMap(usize, void), null_visited: *std.AutoHashMap(usize, void)) !void {
        if (visited.contains(variable)) return;
        const rule_index = self.reasonInFirst(variable, terminal) orelse return;
        try visited.put(variable, {});
        const rule_text = try common.ruleText(self.allocator, self.grammar.symbols.items, self.grammar.rules.items[rule_index]);
        defer self.allocator.free(rule_text);
        try out.appendSlice(self.allocator, "    ");
        try out.appendSlice(self.allocator, rule_text);
        try out.appendSlice(self.allocator, "\n");

        const rule = self.grammar.rules.items[rule_index];
        var nullable_prefix = std.ArrayList(usize).empty;
        defer nullable_prefix.deinit(self.allocator);
        for (rule.rhs.items) |symbol_index| {
            const symbol = self.grammar.symbols.items[symbol_index];
            if (symbol.kind != .variable) {
                if (symbol_index == terminal) try self.emitNullChains(out, nullable_prefix.items, null_visited);
                return;
            }
            if (self.terminalInFirst(symbol_index, terminal)) {
                try self.emitNullChains(out, nullable_prefix.items, null_visited);
                try self.explainFirstChain(out, symbol_index, terminal, visited, null_visited);
                return;
            }
            if (self.plan.nullable_rules[symbol_index] != null) {
                try nullable_prefix.append(self.allocator, symbol_index);
                continue;
            }
            return;
        }
    }

    /// Explains why `terminal ∈ FOLLOW(variable)` by walking the stored
    /// containing rule, descending into a following symbol's FIRST chain or
    /// propagating to the header's FOLLOW chain.
    fn explainFollowChain(self: *Builder, out: *std.ArrayList(u8), variable: usize, terminal: usize, visited: *std.AutoHashMap(usize, void), null_visited: *std.AutoHashMap(usize, void)) !void {
        if (visited.contains(variable)) return;
        const rule_index = self.reasonInFollow(variable, terminal) orelse return;
        try visited.put(variable, {});
        const rule = self.grammar.rules.items[rule_index];
        const rule_text = try common.ruleText(self.allocator, self.grammar.symbols.items, rule);
        defer self.allocator.free(rule_text);
        try out.appendSlice(self.allocator, "    ");
        try out.appendSlice(self.allocator, rule_text);
        try out.appendSlice(self.allocator, "\n");

        for (rule.rhs.items, 0..) |symbol_index, rhs_pos| {
            if (symbol_index != variable) continue;
            if (!self.followPositionExplains(terminal, rule, rhs_pos)) continue;
            const propagated = try self.explainFollowPosition(out, rule, rhs_pos, terminal, visited, null_visited);
            if (propagated and rule.header != variable) {
                try self.explainFollowChain(out, rule.header, terminal, visited, null_visited);
            }
            return;
        }
    }

    /// Determines, without emitting, whether the occurrence of a variable at
    /// `rhs_pos` in `rule` places `terminal` into its FOLLOW set: `terminal`
    /// follows directly, `terminal ∈ FIRST` of a following symbol, or every
    /// following symbol is nullable so the terminal propagates to the header.
    fn followPositionExplains(self: *Builder, terminal: usize, rule: common.Rule, rhs_pos: usize) bool {
        var next_pos = rhs_pos + 1;
        while (next_pos < rule.rhs.items.len) : (next_pos += 1) {
            const symbol_index = rule.rhs.items[next_pos];
            const symbol = self.grammar.symbols.items[symbol_index];
            if (symbol.kind != .variable) return symbol_index == terminal;
            if (self.terminalInFirst(symbol_index, terminal)) return true;
            if (self.plan.nullable_rules[symbol_index] == null) return false;
        }
        return true;
    }

    /// Emits the derivation lines explaining why `terminal` follows a variable
    /// after position `rhs_pos` in `rule`. Returns whether the explanation
    /// ends in propagation to the header's FOLLOW chain.
    fn explainFollowPosition(self: *Builder, out: *std.ArrayList(u8), rule: common.Rule, rhs_pos: usize, terminal: usize, visited: *std.AutoHashMap(usize, void), null_visited: *std.AutoHashMap(usize, void)) !bool {
        var nullable_prefix = std.ArrayList(usize).empty;
        defer nullable_prefix.deinit(self.allocator);
        var next_pos = rhs_pos + 1;
        while (next_pos < rule.rhs.items.len) : (next_pos += 1) {
            const symbol_index = rule.rhs.items[next_pos];
            const symbol = self.grammar.symbols.items[symbol_index];
            if (symbol.kind != .variable) {
                if (symbol_index == terminal) try self.emitNullChains(out, nullable_prefix.items, null_visited);
                return false;
            }
            if (self.terminalInFirst(symbol_index, terminal)) {
                try self.emitNullChains(out, nullable_prefix.items, null_visited);
                try self.explainFirstChain(out, symbol_index, terminal, visited, null_visited);
                return false;
            }
            try nullable_prefix.append(self.allocator, symbol_index);
        }
        try self.emitNullChains(out, nullable_prefix.items, null_visited);
        return true;
    }

    fn emitNullChains(self: *Builder, out: *std.ArrayList(u8), symbols: []const usize, null_visited: *std.AutoHashMap(usize, void)) !void {
        for (symbols) |symbol_index| {
            try self.explainNullChain(out, symbol_index, null_visited);
        }
    }

    fn explainNullChain(self: *Builder, out: *std.ArrayList(u8), variable: usize, null_visited: *std.AutoHashMap(usize, void)) !void {
        if (null_visited.contains(variable)) return;
        const rule_index = self.plan.nullable_rules[variable] orelse return;
        try null_visited.put(variable, {});
        const rule_text = try common.ruleText(self.allocator, self.grammar.symbols.items, self.grammar.rules.items[rule_index]);
        defer self.allocator.free(rule_text);
        try out.appendSlice(self.allocator, "    ");
        try out.appendSlice(self.allocator, rule_text);
        try out.appendSlice(self.allocator, "\n");
        for (self.grammar.rules.items[rule_index].rhs.items) |child| {
            try self.explainNullChain(out, child, null_visited);
        }
    }

    fn terminalInFirst(self: *Builder, variable: usize, terminal: usize) bool {
        for (self.plan.first_sets[variable]) |entry| {
            if (entry.terminal == terminal) return true;
        }
        return false;
    }

    fn reasonInFirst(self: *Builder, variable: usize, terminal: usize) ?usize {
        for (self.plan.first_sets[variable]) |entry| {
            if (entry.terminal == terminal) return entry.rule;
        }
        return null;
    }

    fn reasonInFollow(self: *Builder, variable: usize, terminal: usize) ?usize {
        for (self.plan.follow_sets[variable]) |entry| {
            if (entry.terminal == terminal) return entry.rule;
        }
        return null;
    }

    /// When two productions of the same variable share a nonempty RHS prefix,
    /// returns a suggested left-factored rewrite hoisting that prefix into a
    /// new tail variable. Returns null when the conflict has no syntactic
    /// prefix to hoist (e.g. a FIRST/FOLLOW clash through a nullable rule).
    fn leftFactorSuggestion(self: *Builder, variable: usize, rule_a: usize, rule_b: usize) !?[]const u8 {
        const rhs_a = self.grammar.rules.items[rule_a].rhs.items;
        const rhs_b = self.grammar.rules.items[rule_b].rhs.items;
        var prefix_len: usize = 0;
        while (prefix_len < rhs_a.len and prefix_len < rhs_b.len and rhs_a[prefix_len] == rhs_b[prefix_len]) : (prefix_len += 1) {}
        if (prefix_len == 0) return null;

        const prefix_text = try common.symbolsText(self.allocator, self.grammar.symbols.items, rhs_a[0..prefix_len]);
        defer self.allocator.free(prefix_text);
        const suffix_a_text = try common.symbolsText(self.allocator, self.grammar.symbols.items, rhs_a[prefix_len..]);
        defer self.allocator.free(suffix_a_text);
        const suffix_b_text = try common.symbolsText(self.allocator, self.grammar.symbols.items, rhs_b[prefix_len..]);
        defer self.allocator.free(suffix_b_text);

        const variable_name = try common.symbolText(self.allocator, self.grammar.symbols.items, variable);
        defer self.allocator.free(variable_name);
        const tail_name = try self.freshTailName(variable_name);
        defer self.allocator.free(tail_name);

        return try std.fmt.allocPrint(
            self.allocator,
            "{s} -> {s} {s}\n  {s} -> {s}\n  {s} -> {s}",
            .{ variable_name, prefix_text, tail_name, tail_name, suffix_a_text, tail_name, suffix_b_text },
        );
    }

    fn freshTailName(self: *Builder, variable_name: []const u8) ![]const u8 {
        return allocateTailName(self.allocator, self.grammar, variable_name);
    }

    fn symbolIdTaken(self: *Builder, id: []const u8) bool {
        return hasSymbolId(self.grammar, id);
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
        // Purely structural: which parsers may be referenced from an
        // AST-suppressed call site is a grammar fact, independent of any
        // generation-time configuration, so every variant's config can find
        // its suppressed parsers present.
        for (self.grammar.variables.items) |variable| {
            if (self.hasParseEntries(variable)) try self.planAstSuppressedChildren(variable, false);
        }
        // Synthetic transparent tails never emit parsers, but both decision
        // variants must still be planned: inline expansion sites inside
        // suppressed bodies read the skip variant's tree.
        for (self.grammar.variables.items) |variable| {
            if (!self.grammar.symbols.items[variable].synthetic_transparent) continue;
            if (!self.hasParseEntries(variable)) continue;
            try self.plan.needs_ast_suppressed_parser.put(variable, {});
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
        self.plan.variable_indices = try self.allocator.alloc(?usize, symbol_count);
        @memset(self.plan.has_parse_entries, false);
        @memset(self.plan.variable_indices, null);

        for (self.plan.parse_table.items) |entry| self.plan.has_parse_entries[entry.variable] = true;
        for (self.grammar.variables.items, 0..) |symbol_index, variable_index| self.plan.variable_indices[symbol_index] = variable_index;

        var emitted = std.ArrayList(usize).empty;
        for (self.grammar.symbols.items, 0..) |symbol, symbol_index| {
            if (symbol.kind != .variable or self.plan.has_parse_entries[symbol_index]) try emitted.append(self.allocator, symbol_index);
        }
        self.plan.emitted_symbols = try emitted.toOwnedSlice(self.allocator);

        self.plan.longest_terminal_length = common.longestTerminalLengthWithRecovery(self.grammar);
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
                    var self_repeating_entries = std.ArrayList(switch_planning.Entry).empty;
                    for (self.plan.parse_table.items) |entry| {
                        if (entry.variable != symbol_index or entry.rule != rule_index) continue;
                        for (self.grammar.symbols.items[entry.terminal].terminals.items) |terminal| {
                            if (terminal.len > 0) try self_repeating_entries.append(self.allocator, .{ .terminal = terminal, .target = rule_index });
                        }
                    }
                    const tree = try switch_planning.build(self.allocator, self_repeating_entries.items);
                    try self.plan.self_repeating_decisions.append(self.allocator, .{
                        .variable = symbol_index,
                        .rule_index = rule_index,
                        .self_index = self_index,
                        .skip_ast_construction = skip_ast_construction,
                        .tree = tree,
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
            try common.appendUniqueString(&stems, self.allocator, try std.fmt.allocPrint(self.allocator, "valid_{s}", .{self.plan.parser_names[symbol_index]}));
        } else if (self.grammar.symbols.items[symbol_index].kind == .variable) {
            for (node.groups.items) |group| {
                for (group.child.entries) |entry| try common.appendUniqueString(&stems, self.allocator, try self.ruleExpectedStem(symbol_index, entry.target));
            }
        } else try common.appendUniqueString(&stems, self.allocator, self.plan.parser_names[symbol_index]);
        if (stems.items.len == 0) try common.appendUniqueString(&stems, self.allocator, try std.fmt.allocPrint(self.allocator, "valid_{s}", .{self.plan.parser_names[symbol_index]}));
        std.mem.sort([]const u8, stems.items, {}, common.headLessThan);
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

    fn putUnique(self: *Builder, map: *std.AutoHashMap(usize, usize), variable: usize, key: usize, value: usize) !void {
        if (map.get(key)) |existing| {
            if (existing != value) {
                if (self.pending_ambiguity == null) {
                    self.pending_ambiguity = .{ .variable = variable, .terminal = key, .rule_a = existing, .rule_b = value };
                }
            }
            return;
        }
        try map.put(key, value);
    }
};

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

fn testAmbiguousGrammar(allocator: std.mem.Allocator) !common.PreparedGrammar {
    var grammar = common.PreparedGrammar{ .augmented_start = undefined, .eof = undefined };
    const root = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Root", .variable);
    const a = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "a", .terminal);
    const b = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "b", .terminal);
    grammar.augmented_start = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "_AugmentedStart", .variable);
    grammar.eof = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "\x00", .end);
    grammar.generative_terminal = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "GenerativeTerminal", .variable);
    try appendTestRule(allocator, &grammar.rules, root, "0", &.{ a, b });
    try appendTestRule(allocator, &grammar.rules, root, "1", &.{a});
    try appendTestRule(allocator, &grammar.rules, grammar.augmented_start, "0", &.{ root, grammar.eof });
    try appendTestRule(allocator, &grammar.rules, grammar.generative_terminal.?, "0", &.{});
    std.mem.sort(common.Rule, grammar.rules.items, grammar.symbols.items, common.ruleLessThan);
    return grammar;
}

test "LL planning still rejects indirect first-set conflicts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // No shared RHS prefix: Root -> Via and Root -> "a" overlap only through
    // Via -> "a", so there is nothing to hoist and planning must fail.
    var grammar = common.PreparedGrammar{ .augmented_start = undefined, .eof = undefined };
    const root = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Root", .variable);
    const via = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Via", .variable);
    const a = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "a", .terminal);
    grammar.augmented_start = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "_AugmentedStart", .variable);
    grammar.eof = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "\x00", .end);
    grammar.generative_terminal = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "GenerativeTerminal", .variable);
    try appendTestRule(allocator, &grammar.rules, root, "0", &.{via});
    try appendTestRule(allocator, &grammar.rules, root, "1", &.{a});
    try appendTestRule(allocator, &grammar.rules, via, "0", &.{a});
    try appendTestRule(allocator, &grammar.rules, grammar.augmented_start, "0", &.{ root, grammar.eof });
    try appendTestRule(allocator, &grammar.rules, grammar.generative_terminal.?, "0", &.{});
    std.mem.sort(common.Rule, grammar.rules.items, grammar.symbols.items, common.ruleLessThan);

    const options = common.Options{ .with_ast = true, .with_procedures = false, .with_error_recovery = false };
    try std.testing.expectError(error.AmbiguousGrammar, LLPlan.build(allocator, &grammar, options));
}

test "LL planning automatically factors directly shared prefixes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var grammar = try testAmbiguousGrammar(allocator);
    const options = common.Options{ .with_ast = true, .with_procedures = false, .with_error_recovery = false };
    const plan = try LLPlan.build(allocator, &grammar, options);

    var root: usize = undefined;
    var tail: usize = undefined;
    var tail_found = false;
    for (grammar.symbols.items, 0..) |symbol, index| {
        if (std.mem.eql(u8, symbol.id, "Root")) root = index;
        if (std.mem.eql(u8, symbol.id, "Root_Tail")) {
            tail = index;
            tail_found = true;
        }
    }
    try std.testing.expect(tail_found);
    // Transparent tail: no node and no hooks of its own — suffix children
    // splice into the parent — but planning still treats it normally, so
    // `ast_enabled` stays true and suppressed machinery is untouched.
    try std.testing.expect(grammar.symbols.items[tail].synthetic_transparent);
    try std.testing.expect(grammar.symbols.items[tail].ast_enabled);

    var root_rule_count: usize = 0;
    var tail_rule_count: usize = 0;
    for (grammar.rules.items) |rule| {
        if (rule.header == root) {
            root_rule_count += 1;
            try std.testing.expectEqual(@as(usize, 2), rule.rhs.items.len);
            try std.testing.expectEqual(tail, rule.rhs.items[1]);
        }
        if (rule.header == tail) tail_rule_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), root_rule_count);
    try std.testing.expectEqual(@as(usize, 2), tail_rule_count);

    // One parse entry per side: Root decides on the shared terminal, the
    // tail decides on the distinguishing continuation.
    var root_entries: usize = 0;
    for (plan.parse_table.items) |entry| if (entry.variable == root) {
        root_entries += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), root_entries);
}

test "LL planning keeps conflicts whose prefix annotations diverge" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var grammar = try testAmbiguousGrammar(allocator);
    for (grammar.rules.items) |*rule| {
        if (!std.mem.eql(u8, grammar.symbols.items[rule.header].id, "Root")) continue;
        if (rule.rhs.items.len != 2) continue;
        try rule.rhs_annotations.items[0].procedures.append(allocator, try allocator.dupe(u8, "prefixHook"));
        break;
    }
    const options = common.Options{ .with_ast = true, .with_procedures = false, .with_error_recovery = false };
    try std.testing.expectError(error.AmbiguousGrammar, LLPlan.build(allocator, &grammar, options));
}

test "LL planning keeps conflicts whose productions carry procedures" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var grammar = try testAmbiguousGrammar(allocator);
    // Production-level procedures would lose their reduction site once the
    // alternatives merge into one transparent parent production.
    for (grammar.rules.items) |*rule| {
        if (!std.mem.eql(u8, grammar.symbols.items[rule.header].id, "Root")) continue;
        if (rule.rhs.items.len != 2) continue;
        try rule.annotations.procedures.append(allocator, try allocator.dupe(u8, "productionHook"));
        break;
    }
    const options = common.Options{ .with_ast = true, .with_procedures = false, .with_error_recovery = false };
    try std.testing.expectError(error.AmbiguousGrammar, LLPlan.build(allocator, &grammar, options));
}

test "ambiguity explanation traces first and follow derivation chains" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var grammar = common.PreparedGrammar{ .augmented_start = undefined, .eof = undefined };
    const root = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Root", .variable);
    const tail = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "ConditionalBranchTail", .variable);
    const branch = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "ConditionalBranch", .variable);
    const x = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "X", .variable);
    const y = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Y", .variable);
    const z = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Z", .variable);
    const open = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "{", .terminal);
    grammar.augmented_start = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "_AugmentedStart", .variable);
    grammar.eof = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "\x00", .end);
    grammar.generative_terminal = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "GenerativeTerminal", .variable);

    try appendTestRule(allocator, &grammar.rules, tail, "0", &.{ branch, tail });
    try appendTestRule(allocator, &grammar.rules, tail, "1", &.{});
    try appendTestRule(allocator, &grammar.rules, branch, "0", &.{ x, y });
    try appendTestRule(allocator, &grammar.rules, x, "0", &.{});
    try appendTestRule(allocator, &grammar.rules, y, "0", &.{ x, open });
    try appendTestRule(allocator, &grammar.rules, z, "0", &.{ tail, open });
    try appendTestRule(allocator, &grammar.rules, root, "0", &.{tail});
    try appendTestRule(allocator, &grammar.rules, grammar.augmented_start, "0", &.{ root, grammar.eof });
    try appendTestRule(allocator, &grammar.rules, grammar.generative_terminal.?, "0", &.{});
    std.mem.sort(common.Rule, grammar.rules.items, grammar.symbols.items, common.ruleLessThan);

    var builder = Builder{
        .allocator = allocator,
        .grammar = &grammar,
        .options = .{ .with_ast = false, .with_procedures = false, .with_error_recovery = false },
        .plan = LLPlan.init(allocator),
    };
    try builder.analyzeGrammar();
    try builder.buildParseTable();

    const ambiguity = builder.pending_ambiguity.?;
    try std.testing.expectEqual(tail, ambiguity.variable);
    try std.testing.expectEqual(open, ambiguity.terminal);

    const message = try builder.explainConflict(ambiguity.variable, ambiguity.terminal, ambiguity.rule_a, ambiguity.rule_b);
    defer allocator.free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "  ConditionalBranchTail -> ConditionalBranch ConditionalBranchTail") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "    ConditionalBranch -> X Y") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "    X ->") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "    Y -> X \"{\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "  ConditionalBranchTail ->\n    Z -> ConditionalBranchTail \"{\"") != null);
}

test "ambiguity explanation stops at a rule containing the terminal directly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var grammar = common.PreparedGrammar{ .augmented_start = undefined, .eof = undefined };
    const root = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Root", .variable);
    const via = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Via", .variable);
    const a = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "a", .terminal);
    grammar.augmented_start = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "_AugmentedStart", .variable);
    grammar.eof = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "\x00", .end);
    grammar.generative_terminal = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "GenerativeTerminal", .variable);
    try appendTestRule(allocator, &grammar.rules, root, "0", &.{via});
    try appendTestRule(allocator, &grammar.rules, root, "1", &.{a});
    try appendTestRule(allocator, &grammar.rules, via, "0", &.{a});
    try appendTestRule(allocator, &grammar.rules, grammar.augmented_start, "0", &.{ root, grammar.eof });
    try appendTestRule(allocator, &grammar.rules, grammar.generative_terminal.?, "0", &.{});
    std.mem.sort(common.Rule, grammar.rules.items, grammar.symbols.items, common.ruleLessThan);

    var builder = Builder{
        .allocator = allocator,
        .grammar = &grammar,
        .options = .{ .with_ast = false, .with_procedures = false, .with_error_recovery = false },
        .plan = LLPlan.init(allocator),
    };
    try builder.analyzeGrammar();
    try builder.buildParseTable();

    const ambiguity = builder.pending_ambiguity.?;
    const message = try builder.explainConflict(ambiguity.variable, ambiguity.terminal, ambiguity.rule_a, ambiguity.rule_b);
    defer allocator.free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "  Root -> Via\n    Via -> \"a\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, message, "  Root -> \"a\"\n") != null);
}

test "self-repeating decisions discriminate on full terminal bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var grammar = common.PreparedGrammar{ .augmented_start = undefined, .eof = undefined };
    const root = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Root", .variable);
    const tail = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "ArithmeticExpressionTail", .variable);
    const operator = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Operator", .variable);
    const plus = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, " +", .terminal);
    const minus = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, " -", .terminal);
    const star = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, " *", .terminal);
    const slash = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, " /", .terminal);
    const comparison = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, " <", .terminal);
    grammar.augmented_start = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "_AugmentedStart", .variable);
    grammar.eof = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "\x00", .end);
    grammar.generative_terminal = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "GenerativeTerminal", .variable);

    try appendTestRule(allocator, &grammar.rules, root, "0", &.{ tail, comparison });
    try appendTestRule(allocator, &grammar.rules, tail, "0", &.{ operator, tail });
    try appendTestRule(allocator, &grammar.rules, tail, "1", &.{});
    try appendTestRule(allocator, &grammar.rules, operator, "0", &.{plus});
    try appendTestRule(allocator, &grammar.rules, operator, "1", &.{minus});
    try appendTestRule(allocator, &grammar.rules, operator, "2", &.{star});
    try appendTestRule(allocator, &grammar.rules, operator, "3", &.{slash});
    try appendTestRule(allocator, &grammar.rules, grammar.augmented_start, "0", &.{ root, grammar.eof });
    try appendTestRule(allocator, &grammar.rules, grammar.generative_terminal.?, "0", &.{});
    std.mem.sort(common.Rule, grammar.rules.items, grammar.symbols.items, common.ruleLessThan);

    var tail_index: usize = undefined;
    for (grammar.symbols.items, 0..) |symbol, index| {
        if (std.mem.eql(u8, symbol.id, "ArithmeticExpressionTail")) tail_index = index;
    }

    var rule_index: usize = undefined;
    var self_index: usize = undefined;
    for (grammar.rules.items, 0..) |rule, index| {
        if (rule.header != tail_index or rule.rhs.items.len == 0) continue;
        for (rule.rhs.items, 0..) |child, child_index| {
            if (child == tail_index) {
                rule_index = index;
                self_index = child_index;
            }
        }
    }

    const plan = try LLPlan.build(allocator, &grammar, .{ .with_ast = false, .with_procedures = false, .with_error_recovery = false });
    const decision = plan.selfRepeatingDecision(tail_index, rule_index, self_index, false);
    try std.testing.expectEqual(@as(usize, 2), decision.tree.step_length);

    const heads = try switch_planning.expectedHeads(allocator, decision.tree.*);
    var saw_plus = false;
    var saw_comparison = false;
    for (heads) |head| {
        if (std.mem.eql(u8, head, " +")) saw_plus = true;
        if (std.mem.eql(u8, head, " <")) saw_comparison = true;
    }
    try std.testing.expect(saw_plus);
    try std.testing.expect(!saw_comparison);
}

test "left-factor suggestion hoists a shared RHS prefix" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var grammar = common.PreparedGrammar{ .augmented_start = undefined, .eof = undefined };
    const root = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Root", .variable);
    const colon = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, ":", .terminal);
    const fields = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Fields", .variable);
    const tail = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Tail", .variable);
    grammar.augmented_start = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "_AugmentedStart", .variable);
    grammar.eof = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "\x00", .end);
    grammar.generative_terminal = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "GenerativeTerminal", .variable);

    try appendTestRule(allocator, &grammar.rules, root, "0", &.{ colon, fields, tail });
    try appendTestRule(allocator, &grammar.rules, root, "1", &.{ colon, tail });
    try appendTestRule(allocator, &grammar.rules, grammar.augmented_start, "0", &.{ root, grammar.eof });
    try appendTestRule(allocator, &grammar.rules, grammar.generative_terminal.?, "0", &.{});
    std.mem.sort(common.Rule, grammar.rules.items, grammar.symbols.items, common.ruleLessThan);

    var root_index: usize = undefined;
    for (grammar.symbols.items, 0..) |symbol, index| {
        if (std.mem.eql(u8, symbol.id, "Root")) root_index = index;
    }
    var rule_a: usize = undefined;
    var rule_b: usize = undefined;
    var found: usize = 0;
    for (grammar.rules.items, 0..) |rule, index| {
        if (rule.header != root_index) continue;
        if (found == 0) rule_a = index else rule_b = index;
        found += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), found);

    var builder = Builder{
        .allocator = allocator,
        .grammar = &grammar,
        .options = .{ .with_ast = false, .with_procedures = false, .with_error_recovery = false },
        .plan = LLPlan.init(allocator),
    };

    const suggestion = (try builder.leftFactorSuggestion(root_index, rule_a, rule_b)).?;
    defer allocator.free(suggestion);
    try std.testing.expect(std.mem.indexOf(u8, suggestion, "Root -> \":\" Root_Tail") != null);
    try std.testing.expect(std.mem.indexOf(u8, suggestion, "Root_Tail -> Fields Tail") != null);
    try std.testing.expect(std.mem.indexOf(u8, suggestion, "Root_Tail -> Tail") != null);
}

test "left-factorization yields no suggestion without a shared prefix" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var grammar = common.PreparedGrammar{ .augmented_start = undefined, .eof = undefined };
    const root = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Root", .variable);
    const via_var = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "Via", .variable);
    const a = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "a", .terminal);
    grammar.augmented_start = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "_AugmentedStart", .variable);
    grammar.eof = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "\x00", .end);
    grammar.generative_terminal = try common.addSymbol(allocator, &grammar.symbols, &grammar.variables, "GenerativeTerminal", .variable);
    try appendTestRule(allocator, &grammar.rules, root, "0", &.{via_var});
    try appendTestRule(allocator, &grammar.rules, root, "1", &.{a});
    try appendTestRule(allocator, &grammar.rules, via_var, "0", &.{a});
    try appendTestRule(allocator, &grammar.rules, grammar.augmented_start, "0", &.{ root, grammar.eof });
    try appendTestRule(allocator, &grammar.rules, grammar.generative_terminal.?, "0", &.{});
    std.mem.sort(common.Rule, grammar.rules.items, grammar.symbols.items, common.ruleLessThan);

    var root_index: usize = undefined;
    for (grammar.symbols.items, 0..) |symbol, index| {
        if (std.mem.eql(u8, symbol.id, "Root")) root_index = index;
    }
    var rule_a: usize = undefined;
    var rule_b: usize = undefined;
    var found: usize = 0;
    for (grammar.rules.items, 0..) |rule, index| {
        if (rule.header != root_index) continue;
        if (found == 0) rule_a = index else rule_b = index;
        found += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), found);

    var builder = Builder{
        .allocator = allocator,
        .grammar = &grammar,
        .options = .{ .with_ast = false, .with_procedures = false, .with_error_recovery = false },
        .plan = LLPlan.init(allocator),
    };
    try std.testing.expect(try builder.leftFactorSuggestion(root_index, rule_a, rule_b) == null);
}
