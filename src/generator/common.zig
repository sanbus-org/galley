const std = @import("std");

pub const atomic_file = @import("atomic_file.zig");
pub const names = @import("names.zig");

pub const readableSymbolName = names.readableSymbolName;
pub const safeIdentifier = names.safeIdentifier;
pub const syntaxErrorFunctionName = names.syntaxErrorFunctionName;
pub const headLessThan = names.lessThan;

test {
    _ = names;
}

pub const Options = struct {
    with_ast: bool = true,
    with_procedures: bool = true,
    with_error_recovery: bool = false,
    ast_for_terminals: bool = false,
    with_position_tracking: ?bool = null,
    with_input_streaming: bool = false,
    allow_no_ast_tree_procedures: bool = false,
    require_reduction_procedures: bool = false,
    syntax_error_reporter: ?*const fn (message: []const u8) void = null,

    pub fn validate(self: Options) !void {
        _ = self;
    }
};

pub const ErrorMessageSpec = struct {
    name: []const u8,
};

pub const SymbolKind = enum { variable, terminal, generative_terminal, end };

pub const RecoveryResume = enum { before, after };

pub const RecoveryPoint = struct {
    terminal: []const u8,
    @"resume": RecoveryResume,
};

pub const Annotations = struct {
    procedures: std.ArrayList([]const u8) = .empty,
    recovery_points: std.ArrayList(RecoveryPoint) = .empty,
    verbatim: bool = false,
    verbatim_literal: ?[]const u8 = null,
    verbatim_consume: bool = true,
};

pub const Symbol = struct {
    id: []const u8,
    kind: SymbolKind,
    ast_enabled: bool = true,
    /// Internal-only: set solely by the LL planner's automatic left-factoring.
    /// Never parsed from grammar source and never user-addressable. A
    /// transparent helper builds no node of its own and needs no hooks;
    /// the emitter expands its alternatives inline at the single parent
    /// call site so suffix children splice directly into the parent.
    /// Deliberately distinct from `ast_enabled == false` (the user-facing
    /// `_` contract), which drops the entire subtree.
    synthetic_transparent: bool = false,
    terminals: std.ArrayList([]const u8) = .empty,
    annotations: Annotations = .{},
};

pub const Rule = struct {
    header: usize,
    rhs: std.ArrayList(usize) = .empty,
    rhs_annotations: std.ArrayList(Annotations) = .empty,
    annotations: Annotations = .{},
    rhs_index: []const u8,
};

pub const RecoveryScopeTarget = enum { lhs, production, occurrence };

pub const RecoveryOccurrence = struct { rule: usize, position: usize };

pub const RecoveryScope = struct {
    id: usize,
    target: RecoveryScopeTarget,
    variable: usize,
    rule: ?usize = null,
    position: ?usize = null,
};

/// Recovery metadata is planned independently of Zig source emission. Scope
/// IDs intentionally retain the historical numbering scheme used by both
/// backends so generated output remains unchanged.
pub const RecoveryPlan = struct {
    scopes: std.ArrayList(RecoveryScope) = .empty,

    pub fn findLhs(self: RecoveryPlan, variable: usize) ?RecoveryScope {
        for (self.scopes.items) |scope| {
            if (scope.target == .lhs and scope.variable == variable) return scope;
        }
        return null;
    }

    pub fn findProduction(self: RecoveryPlan, rule: usize) ?RecoveryScope {
        for (self.scopes.items) |scope| {
            if (scope.target == .production and scope.rule.? == rule) return scope;
        }
        return null;
    }

    pub fn findOccurrence(self: RecoveryPlan, rule: usize, position: usize) ?RecoveryScope {
        for (self.scopes.items) |scope| {
            if (scope.target == .occurrence and scope.rule.? == rule and scope.position.? == position) return scope;
        }
        return null;
    }
};

pub fn prepareRecoveryPlan(
    allocator: std.mem.Allocator,
    symbols: []const Symbol,
    variables: []const usize,
    rules: []const Rule,
) !RecoveryPlan {
    var result = RecoveryPlan{};
    for (variables) |variable| {
        if (symbols[variable].annotations.recovery_points.items.len == 0) continue;
        try result.scopes.append(allocator, .{
            .id = variable,
            .target = .lhs,
            .variable = variable,
        });
    }
    for (rules, 0..) |rule, rule_index| {
        if (rule.annotations.recovery_points.items.len == 0) continue;
        try result.scopes.append(allocator, .{
            .id = symbols.len + rule_index,
            .target = .production,
            .variable = rule.header,
            .rule = rule_index,
        });
    }
    for (rules, 0..) |rule, rule_index| {
        for (rule.rhs_annotations.items, 0..) |annotations, position| {
            if (annotations.recovery_points.items.len == 0) continue;
            try result.scopes.append(allocator, .{
                .id = recoveryOccurrenceTargetId(symbols.len, rules, rule_index, position),
                .target = .occurrence,
                .variable = rule.header,
                .rule = rule_index,
                .position = position,
            });
        }
    }
    return result;
}

pub const PreparedGrammar = struct {
    symbols: std.ArrayList(Symbol) = .empty,
    variables: std.ArrayList(usize) = .empty,
    rules: std.ArrayList(Rule) = .empty,
    augmented_start: usize,
    eof: usize,
    generative_terminal: ?usize = null,
    has_occurrence_procedures: bool = false,
    has_recovery_annotations: bool = false,
    uses_explicit_recovery: bool = false,
    uses_verbatim: bool = false,
};

pub fn prepareGrammar(
    allocator: std.mem.Allocator,
    grammar: anytype,
    options: Options,
    add_generative_terminal: bool,
) !PreparedGrammar {
    // `options` no longer shapes grammar preparation: every field of the
    // prepared grammar is a grammar fact. Configuration is applied at
    // comptime inside the generated parser.
    _ = options;
    try validateGrammar(grammar);

    var result = PreparedGrammar{
        .augmented_start = undefined,
        .eof = undefined,
        .has_recovery_annotations = grammarHasRecoveryPoints(grammar),
    };
    // Grammar fact only: explicit-recovery machinery must exist in the
    // generated file whenever the grammar declares annotations, because the
    // active recovery style is selected at comptime per configuration.
    result.uses_explicit_recovery = result.has_recovery_annotations;

    var rhs_counts = std.AutoHashMap(usize, usize).init(allocator);
    defer rhs_counts.deinit();

    for (grammar.rules) |rule| {
        const header = try addSymbol(allocator, &result.symbols, &result.variables, rule.header, .variable);
        try appendAnnotations(allocator, &result.symbols.items[header].annotations, rule.annotations);

        for (rule.right_hand_sides) |rhs| {
            const rhs_index = rhs_counts.get(header) orelse 0;
            try rhs_counts.put(header, rhs_index + 1);

            var generated_rule = Rule{
                .header = header,
                .rhs_index = try std.fmt.allocPrint(allocator, "{d}", .{rhs_index}),
            };
            try appendAnnotations(allocator, &generated_rule.annotations, rhs.annotations);

            for (rhs.symbols) |symbol| {
                const kind: SymbolKind = switch (symbol.kind) {
                    .variable => .variable,
                    .terminal => .terminal,
                    .generative_terminal => .generative_terminal,
                };
                const symbol_index = try addSymbol(allocator, &result.symbols, &result.variables, symbol.id, kind);
                try generated_rule.rhs.append(allocator, symbol_index);
                try generated_rule.rhs_annotations.append(
                    allocator,
                    try cloneAnnotations(allocator, symbol.annotations),
                );
                if (@hasField(@TypeOf(symbol.annotations), "verbatim") and symbol.annotations.verbatim) result.uses_verbatim = true;
                // Grammar fact only: whether ANY annotated procedure
                // occurrence exists. Which occurrences actually run is a
                // configuration decision made at comptime inside the
                // generated parser, so this must not depend on options here.
                if (symbol.annotations.procedures.len != 0) {
                    result.has_occurrence_procedures = true;
                }
            }
            try result.rules.append(allocator, generated_rule);
        }
    }

    const original_start = result.rules.items[0].header;
    result.augmented_start = try addSymbol(allocator, &result.symbols, &result.variables, "_AugmentedStart", .variable);
    result.eof = try addSymbol(allocator, &result.symbols, &result.variables, "\x00", .end);
    var augmented_rule = Rule{ .header = result.augmented_start, .rhs_index = "0" };
    try augmented_rule.rhs.append(allocator, original_start);
    try augmented_rule.rhs_annotations.append(allocator, .{});
    try augmented_rule.rhs.append(allocator, result.eof);
    try augmented_rule.rhs_annotations.append(allocator, .{});
    try result.rules.append(allocator, augmented_rule);

    if (add_generative_terminal) {
        const generative_terminal = try addSymbol(
            allocator,
            &result.symbols,
            &result.variables,
            "GenerativeTerminal",
            .variable,
        );
        result.generative_terminal = generative_terminal;
        try result.rules.append(allocator, .{ .header = generative_terminal, .rhs_index = "0" });
    }

    std.mem.sort(Rule, result.rules.items, result.symbols.items, ruleLessThan);
    return result;
}

/// Renders a symbol the way it is written in a grammar: variables bare,
/// terminals and generative terminals double-quoted, and end-of-input as EOF.
pub fn symbolText(allocator: std.mem.Allocator, symbols: []const Symbol, symbol_index: usize) ![]const u8 {
    const symbol = symbols[symbol_index];
    return switch (symbol.kind) {
        .variable => allocator.dupe(u8, symbol.id),
        .end => allocator.dupe(u8, "EOF"),
        .terminal, .generative_terminal => blk: {
            const escaped = try readableSymbolName(allocator, symbol.id);
            defer allocator.free(escaped);
            break :blk try std.fmt.allocPrint(allocator, "\"{s}\"", .{escaped});
        },
    };
}

/// Renders a production as `Header -> symbol symbol ...` for diagnostics.
pub fn ruleText(allocator: std.mem.Allocator, symbols: []const Symbol, rule: Rule) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    const header = try symbolText(allocator, symbols, rule.header);
    defer allocator.free(header);
    try out.appendSlice(allocator, header);
    try out.appendSlice(allocator, " ->");
    for (rule.rhs.items) |symbol_index| {
        const text = try symbolText(allocator, symbols, symbol_index);
        defer allocator.free(text);
        try out.append(allocator, ' ');
        try out.appendSlice(allocator, text);
    }
    return out.toOwnedSlice(allocator);
}

/// Renders a slice of symbol indices joined by spaces, or "<empty>" when the
/// slice is empty, for left-factoring diagnostics.
pub fn symbolsText(allocator: std.mem.Allocator, symbols: []const Symbol, symbol_indices: []const usize) ![]const u8 {
    if (symbol_indices.len == 0) return allocator.dupe(u8, "<empty>");
    var out = std.ArrayList(u8).empty;
    for (symbol_indices, 0..) |symbol_index, index| {
        if (index != 0) try out.append(allocator, ' ');
        const text = try symbolText(allocator, symbols, symbol_index);
        defer allocator.free(text);
        try out.appendSlice(allocator, text);
    }
    return out.toOwnedSlice(allocator);
}

pub fn symbolReturnsNode(symbol: Symbol, options: Options) bool {
    if (!options.with_ast and !options.with_procedures) return false;
    return switch (symbol.kind) {
        .variable => symbol.ast_enabled,
        .terminal, .generative_terminal => options.ast_for_terminals,
        .end => false,
    };
}

/// Returns the index of a rule for `variable` whose entire RHS is nullable,
/// or null when no such rule exists (including cycles). Copy-on-write visited
/// propagation keeps the recursion free of the caller's set.
pub fn nullableRule(
    allocator: std.mem.Allocator,
    grammar: *const PreparedGrammar,
    variable: usize,
    visited: ?*std.AutoHashMap(usize, void),
) !?usize {
    if (visited) |set| if (set.contains(variable)) return null;
    var local_visited = std.AutoHashMap(usize, void).init(allocator);
    defer local_visited.deinit();
    if (visited) |set| {
        var it = set.keyIterator();
        while (it.next()) |entry| try local_visited.put(entry.*, {});
    }
    try local_visited.put(variable, {});
    for (grammar.rules.items, 0..) |rule, rule_index| {
        if (rule.header != variable) continue;
        for (rule.rhs.items) |symbol_index| {
            if (grammar.symbols.items[symbol_index].kind != .variable or try nullableRule(allocator, grammar, symbol_index, &local_visited) == null) break;
        } else return rule_index;
    }
    return null;
}

/// Rejects grammars whose verbatim-annotated RHS positions can match empty
/// input, shared by the LL and LR planners.
pub fn validateVerbatimSymbols(allocator: std.mem.Allocator, grammar: *const PreparedGrammar) !void {
    if (!grammar.uses_verbatim) return;
    for (grammar.rules.items) |rule| {
        for (rule.rhs.items, 0..) |symbol_index, position| {
            const annotations = rule.rhs_annotations.items[position];
            if (!annotations.verbatim) continue;
            if (annotations.verbatim_literal) |literal| {
                if (literal.len == 0) return error.EmptyVerbatimTerminator;
                if (std.mem.indexOfScalar(u8, literal, 0) != null) return error.NulVerbatimTerminator;
                continue;
            }
            const symbol = grammar.symbols.items[symbol_index];
            const empty_matchable = switch (symbol.kind) {
                .terminal, .generative_terminal => symbol.id.len == 0,
                .variable => try nullableRule(allocator, grammar, symbol_index, null) != null,
                .end => false,
            };
            if (empty_matchable) return error.EmptyVerbatimSymbol;
        }
    }
}

/// Collects the FIRST terminal symbol indices of `variable` into `out`.
pub fn firstsOfVariable(
    allocator: std.mem.Allocator,
    grammar: *const PreparedGrammar,
    variable: usize,
    out: *std.AutoHashMap(usize, void),
    visited: ?*std.AutoHashMap(usize, void),
) !void {
    if (visited) |set| if (set.contains(variable)) return;
    var local_visited = std.AutoHashMap(usize, void).init(allocator);
    defer local_visited.deinit();
    if (visited) |set| {
        var it = set.keyIterator();
        while (it.next()) |entry| try local_visited.put(entry.*, {});
    }
    try local_visited.put(variable, {});
    for (grammar.rules.items) |rule| {
        if (rule.header != variable) continue;
        for (rule.rhs.items) |symbol_index| {
            const symbol = grammar.symbols.items[symbol_index];
            if (symbol.kind == .variable) {
                try firstsOfVariable(allocator, grammar, symbol_index, out, &local_visited);
                if (try nullableRule(allocator, grammar, symbol_index, null) == null) break;
            } else {
                try out.put(symbol_index, {});
                break;
            }
        }
    }
}

/// Collects the FIRST terminals of the symbols appearing after the dot of an
/// item, falling back to the item's own lookahead when the tail is empty or
/// fully nullable.
pub fn firstsAfterItem(
    allocator: std.mem.Allocator,
    grammar: *const PreparedGrammar,
    item: anytype,
    out: *std.AutoHashMap(usize, void),
) !void {
    const rule = grammar.rules.items[item.rule];
    var index = item.head + 1;
    while (index < rule.rhs.items.len) : (index += 1) {
        const symbol_index = rule.rhs.items[index];
        const symbol = grammar.symbols.items[symbol_index];
        if (symbol.kind == .variable) {
            try firstsOfVariable(allocator, grammar, symbol_index, out, null);
            if (try nullableRule(allocator, grammar, symbol_index, null) == null) return;
        } else {
            try out.put(symbol_index, {});
            return;
        }
    }
    try out.put(item.lookahead, {});
}

/// Resolves whether a rule RHS position carries a recoverable procedure
/// occurrence, shared by the LR planning and recovery passes.
pub fn procedureOccurrenceFor(
    grammar: *const PreparedGrammar,
    options: Options,
    rule_index: usize,
    position: usize,
) ?RecoveryOccurrence {
    const rule = grammar.rules.items[rule_index];
    if (position >= rule.rhs.items.len) return null;
    const annotations = rule.rhs_annotations.items[position];
    if (annotations.verbatim) return .{ .rule = rule_index, .position = position };
    if (!options.with_procedures or annotations.procedures.items.len == 0) return null;
    const symbol = grammar.symbols.items[rule.rhs.items[position]];
    return if (symbolReturnsNode(symbol, options)) .{ .rule = rule_index, .position = position } else null;
}

pub fn addSymbol(
    allocator: std.mem.Allocator,
    symbols: *std.ArrayList(Symbol),
    variables: *std.ArrayList(usize),
    id: []const u8,
    kind: SymbolKind,
) !usize {
    for (symbols.items, 0..) |symbol, index| {
        if (symbol.kind == kind and std.mem.eql(u8, symbol.id, id)) return index;
    }

    var symbol = Symbol{
        .id = try allocator.dupe(u8, id),
        .kind = kind,
        .ast_enabled = !(kind == .variable and id.len > 0 and id[0] == '_'),
    };
    if (kind == .terminal or kind == .end) {
        try symbol.terminals.append(allocator, symbol.id);
    } else if (kind == .generative_terminal) {
        try expandGenerativeTerminal(allocator, &symbol.terminals, id);
    }

    const index = symbols.items.len;
    try symbols.append(allocator, symbol);
    if (kind == .variable) try variables.append(allocator, index);
    return index;
}

test "symbol identity includes kind" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var symbols: std.ArrayList(Symbol) = .empty;
    var variables: std.ArrayList(usize) = .empty;

    const variable_first = try addSymbol(allocator, &symbols, &variables, "VariableFirst", .variable);
    const terminal_second = try addSymbol(allocator, &symbols, &variables, "VariableFirst", .terminal);
    try std.testing.expect(variable_first != terminal_second);
    try std.testing.expectEqual(variable_first, try addSymbol(allocator, &symbols, &variables, "VariableFirst", .variable));
    try std.testing.expectEqual(terminal_second, try addSymbol(allocator, &symbols, &variables, "VariableFirst", .terminal));

    const terminal_first = try addSymbol(allocator, &symbols, &variables, "TerminalFirst", .terminal);
    const variable_second = try addSymbol(allocator, &symbols, &variables, "TerminalFirst", .variable);
    try std.testing.expect(terminal_first != variable_second);

    const literal = try addSymbol(allocator, &symbols, &variables, "digit", .terminal);
    const generative = try addSymbol(allocator, &symbols, &variables, "digit", .generative_terminal);
    try std.testing.expect(literal != generative);

    const end = try addSymbol(allocator, &symbols, &variables, "\x00", .end);
    const nul_terminal = try addSymbol(allocator, &symbols, &variables, "\x00", .terminal);
    try std.testing.expect(end != nul_terminal);

    try std.testing.expectEqualSlices(usize, &.{ variable_first, variable_second }, variables.items);
}

test "prepared grammar preserves annotations and stable synthetic symbols" {
    const SourceAnnotations = struct {
        procedures: []const []const u8 = &.{},
        recovery_points: []const struct { terminal: []const u8, @"resume": enum { before, after } } = &.{},
    };
    const SourceSymbol = struct {
        id: []const u8,
        kind: enum { variable, terminal, generative_terminal },
        annotations: SourceAnnotations = .{},
    };
    const SourceRhs = struct {
        symbols: []const SourceSymbol,
        annotations: SourceAnnotations = .{},
    };
    const SourceRule = struct {
        header: []const u8,
        right_hand_sides: []const SourceRhs,
        annotations: SourceAnnotations = .{},
    };

    const source = .{ .rules = &[_]SourceRule{
        .{
            .header = "Root",
            .annotations = .{ .procedures = &.{"root_hook"} },
            .right_hand_sides = &.{.{ .symbols = &.{.{ .id = "x", .kind = .terminal }} }},
        },
    } };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const prepared = try prepareGrammar(arena.allocator(), source, .{}, true);

    try std.testing.expectEqualStrings("_AugmentedStart", prepared.symbols.items[prepared.augmented_start].id);
    try std.testing.expectEqual(SymbolKind.end, prepared.symbols.items[prepared.eof].kind);
    try std.testing.expect(prepared.generative_terminal != null);
    for (prepared.rules.items) |rule| {
        if (!std.mem.eql(u8, prepared.symbols.items[rule.header].id, "Root")) continue;
        try std.testing.expectEqualStrings("root_hook", prepared.symbols.items[rule.header].annotations.procedures.items[0]);
        break;
    } else return error.RootRuleMissing;
}

pub fn appendProcedureNames(allocator: std.mem.Allocator, target: *std.ArrayList([]const u8), procedure_names: []const []const u8) !void {
    for (procedure_names) |name| try target.append(allocator, try allocator.dupe(u8, name));
}

pub fn cloneAnnotations(allocator: std.mem.Allocator, source: anytype) !Annotations {
    var result = Annotations{
        .verbatim = if (@hasField(@TypeOf(source), "verbatim")) source.verbatim else false,
        .verbatim_literal = if (@hasField(@TypeOf(source), "verbatim_literal"))
            source.verbatim_literal
        else
            null,
        .verbatim_consume = if (@hasField(@TypeOf(source), "verbatim_consume"))
            source.verbatim_consume
        else
            true,
    };
    if (result.verbatim_literal) |literal| {
        result.verbatim_literal = try allocator.dupe(u8, literal);
    }
    try appendProcedureNames(allocator, &result.procedures, source.procedures);
    for (source.recovery_points) |point| {
        try result.recovery_points.append(allocator, .{
            .terminal = try allocator.dupe(u8, point.terminal),
            .@"resume" = switch (point.@"resume") {
                .before => .before,
                .after => .after,
            },
        });
    }
    return result;
}

pub fn appendAnnotations(allocator: std.mem.Allocator, target: *Annotations, source: anytype) !void {
    target.verbatim = target.verbatim or (@hasField(@TypeOf(source), "verbatim") and source.verbatim);
    if (@hasField(@TypeOf(source), "verbatim_literal")) {
        if (source.verbatim_literal) |literal| {
            target.verbatim_literal = try allocator.dupe(u8, literal);
        }
    }
    if (@hasField(@TypeOf(source), "verbatim_consume") and
        @hasField(@TypeOf(source), "verbatim") and source.verbatim)
    {
        target.verbatim_consume = source.verbatim_consume;
    }
    try appendProcedureNames(allocator, &target.procedures, source.procedures);
    for (source.recovery_points) |point| {
        try target.recovery_points.append(allocator, .{
            .terminal = try allocator.dupe(u8, point.terminal),
            .@"resume" = switch (point.@"resume") {
                .before => .before,
                .after => .after,
            },
        });
    }
}

/// Indices of two rules that share a header: `first` is the earlier rule and
/// `second` is the later duplicate.
pub const DuplicateRuleHeaders = struct {
    first: usize,
    second: usize,
};

/// Returns the first pair of rules sharing a header, or null when every rule
/// header is unique. `rules` is any slice-like value whose elements expose a
/// `header` field; both the AST-built grammar and the immutable grammar model
/// delegate to this single detection routine.
pub fn findDuplicateRuleHeader(rules: anytype) ?DuplicateRuleHeaders {
    for (rules, 0..) |rule, rule_index| {
        for (rules[0..rule_index], 0..) |previous, previous_index| {
            if (std.mem.eql(u8, previous.header, rule.header)) {
                return .{ .first = previous_index, .second = rule_index };
            }
        }
    }
    return null;
}

pub fn validateGrammar(grammar: anytype) !void {
    if (findDuplicateRuleHeader(grammar.rules)) |duplicate| {
        const rule = grammar.rules[duplicate.second];
        std.debug.print("duplicate rule header \"{s}\" (first defined at rule {d})\n", .{ rule.header, duplicate.first + 1 });
        return error.DuplicateRuleHeader;
    }
    for (grammar.rules) |rule| {
        try validateRecoveryPoints(rule.annotations.recovery_points);
        for (rule.right_hand_sides) |rhs| {
            try validateRecoveryPoints(rhs.annotations.recovery_points);
            for (rhs.symbols) |symbol| {
                try validateRecoveryPoints(symbol.annotations.recovery_points);
                if (symbol.annotations.recovery_points.len != 0 and symbol.kind != .variable) return error.InvalidRecoveryTarget;
            }
        }
    }
    for (grammar.rules) |rule| {
        for (rule.right_hand_sides) |rhs| {
            for (rhs.symbols) |symbol| {
                if (symbol.kind != .variable) continue;
                const defined = for (grammar.rules) |candidate| {
                    if (std.mem.eql(u8, candidate.header, symbol.id)) break true;
                } else false;
                if (!defined) {
                    std.debug.print("undefined variable \"{s}\" referenced in rule \"{s}\"\n", .{ symbol.id, rule.header });
                    return error.UndefinedVariable;
                }
            }
        }
    }
}

fn validateRecoveryPoints(points: anytype) !void {
    for (points) |point| {
        if (point.terminal.len == 0) return error.EmptyRecoveryTerminal;
        if (std.mem.indexOfScalar(u8, point.terminal, 0) != null) return error.NulRecoveryTerminal;
    }
}

pub fn grammarHasRecoveryPoints(grammar: anytype) bool {
    for (grammar.rules) |rule| {
        if (rule.annotations.recovery_points.len != 0) return true;
        for (rule.right_hand_sides) |rhs| {
            if (rhs.annotations.recovery_points.len != 0) return true;
            for (rhs.symbols) |symbol| {
                if (symbol.annotations.recovery_points.len != 0) return true;
            }
        }
    }
    return false;
}

pub fn ruleLessThan(symbols: []const Symbol, lhs: Rule, rhs: Rule) bool {
    const lhs_header = symbols[lhs.header].id;
    const rhs_header = symbols[rhs.header].id;
    const header_order = std.mem.order(u8, lhs_header, rhs_header);
    if (header_order != .eq) return header_order == .lt;

    const min_len = @min(lhs.rhs.items.len, rhs.rhs.items.len);
    var i: usize = 0;
    while (i < min_len) : (i += 1) {
        if (lhs.rhs.items[i] != rhs.rhs.items[i]) return lhs.rhs.items[i] < rhs.rhs.items[i];
    }
    return lhs.rhs.items.len < rhs.rhs.items.len;
}

/// Single source of truth for strict reduction-procedure coverage: whether
/// the production at `rule_index` must declare `reduction_<Var>_<N>` when
/// `require_reduction_procedures` is enabled. Only visible variables count:
/// synthetic augmented/generative headers, AST-suppressed helpers
/// (`ast_enabled == false`), and transparent factoring helpers (which build
/// no node and splice into their parent) produce no hook and are excluded.
/// Both the generated parser's comptime check and the CLI's generation-time
/// warning delegate here so they can never diverge.
pub fn requiresReductionProcedure(
    symbols: []const Symbol,
    rules: []const Rule,
    augmented_start: usize,
    generative_terminal: ?usize,
    rule_index: usize,
) bool {
    const rule = rules[rule_index];
    if (rule.header == augmented_start) return false;
    if (generative_terminal) |generative| if (rule.header == generative) return false;
    const header = symbols[rule.header];
    if (header.kind != .variable) return false;
    if (!header.ast_enabled) return false;
    if (header.synthetic_transparent) return false;
    return true;
}

/// Renders the automatic per-production hook name for `rule` as
/// `reduction_<Var>_<N>`.
pub fn reductionProcedureName(allocator: std.mem.Allocator, symbols: []const Symbol, rule: Rule) ![]const u8 {
    return std.fmt.allocPrint(allocator, "reduction_{s}_{s}", .{ symbols[rule.header].id, rule.rhs_index });
}

/// One strict-coverage obligation: the procedure name, its variable and
/// index, and the production shape for diagnostics.
pub const RequiredReductionProcedure = struct {
    variable: []const u8,
    rhs_index: []const u8,
    procedure_name: []const u8,
    shape: []const u8,
};

/// Collects every production that `requiresReductionProcedure` selects,
/// in rule-table order. Shared by the emitter's comptime check and the
/// CLI's generation-time warning so the two can never diverge.
pub fn collectRequiredReductionProcedures(
    allocator: std.mem.Allocator,
    symbols: []const Symbol,
    rules: []const Rule,
    augmented_start: usize,
    generative_terminal: ?usize,
) ![]RequiredReductionProcedure {
    var out = std.ArrayList(RequiredReductionProcedure).empty;
    for (rules, 0..) |rule, rule_index| {
        if (!requiresReductionProcedure(symbols, rules, augmented_start, generative_terminal, rule_index)) continue;
        const shape = try ruleText(allocator, symbols, rule);
        errdefer allocator.free(shape);
        const procedure_name = try reductionProcedureName(allocator, symbols, rule);
        errdefer allocator.free(procedure_name);
        try out.append(allocator, .{
            .variable = symbols[rule.header].id,
            .rhs_index = rule.rhs_index,
            .procedure_name = procedure_name,
            .shape = shape,
        });
    }
    return out.toOwnedSlice(allocator);
}

pub fn longestTerminalLength(symbols: []const Symbol) usize {
    var longest: usize = 0;
    for (symbols) |symbol| {
        for (symbol.terminals.items) |terminal| longest = @max(longest, terminal.len);
    }
    return longest;
}

/// Appends `value` to `items` only when no equal element is already present.
pub fn appendUniqueString(items: *std.ArrayList([]const u8), allocator: std.mem.Allocator, value: []const u8) !void {
    for (items.items) |item| if (std.mem.eql(u8, item, value)) return;
    try items.append(allocator, value);
}

/// Combines `longestTerminalLength` with the longest recovery-point terminal,
/// matching how the LL and LR planners derive their buffer sizing.
pub fn longestTerminalLengthWithRecovery(grammar: *const PreparedGrammar) usize {
    const grammar_longest = longestTerminalLength(grammar.symbols.items);
    return if (grammar.uses_explicit_recovery)
        @max(grammar_longest, longestRecoveryTerminalLength(grammar.symbols.items, grammar.rules.items))
    else
        grammar_longest;
}

pub fn longestRecoveryTerminalLength(symbols: []const Symbol, rules: []const Rule) usize {
    var longest: usize = 0;
    for (symbols) |symbol| {
        for (symbol.annotations.recovery_points.items) |point| longest = @max(longest, point.terminal.len);
    }
    for (rules) |rule| {
        for (rule.annotations.recovery_points.items) |point| longest = @max(longest, point.terminal.len);
        for (rule.rhs_annotations.items) |annotations| {
            for (annotations.recovery_points.items) |point| longest = @max(longest, point.terminal.len);
        }
    }
    return longest;
}

pub fn recoveryOccurrenceTargetId(symbol_count: usize, rules: []const Rule, rule_index: usize, position: usize) usize {
    var id = symbol_count + rules.len;
    for (rules[0..rule_index]) |rule| id += rule.rhs.items.len;
    return id + position;
}

test "recovery occurrence target ids use cumulative production lengths" {
    var first = Rule{ .header = 0, .rhs_index = "0" };
    defer first.rhs.deinit(std.testing.allocator);
    for (0..10) |symbol| try first.rhs.append(std.testing.allocator, symbol);

    var second = Rule{ .header = 1, .rhs_index = "0" };
    defer second.rhs.deinit(std.testing.allocator);
    try second.rhs.append(std.testing.allocator, 0);

    const rules = [_]Rule{ first, second };
    const base = 4 + rules.len;
    try std.testing.expectEqual(base + 9, recoveryOccurrenceTargetId(4, &rules, 0, 9));
    try std.testing.expectEqual(base + 10, recoveryOccurrenceTargetId(4, &rules, 1, 0));
}

test "recovery planning preserves stable scope numbering and source order" {
    var symbols = [_]Symbol{
        .{ .id = "Root", .kind = .variable },
        .{ .id = "Child", .kind = .variable },
        .{ .id = ";", .kind = .terminal },
    };
    try symbols[0].annotations.recovery_points.append(std.testing.allocator, .{ .terminal = ";", .@"resume" = .after });
    defer symbols[0].annotations.recovery_points.deinit(std.testing.allocator);

    var rule = Rule{ .header = 0, .rhs_index = "0" };
    defer rule.rhs.deinit(std.testing.allocator);
    defer rule.rhs_annotations.deinit(std.testing.allocator);
    try rule.rhs.append(std.testing.allocator, 1);
    try rule.rhs_annotations.append(std.testing.allocator, .{});
    try rule.rhs_annotations.items[0].recovery_points.append(std.testing.allocator, .{ .terminal = ";", .@"resume" = .before });
    defer rule.rhs_annotations.items[0].recovery_points.deinit(std.testing.allocator);
    const rules = [_]Rule{rule};
    const variables = [_]usize{ 0, 1 };
    var plan = try prepareRecoveryPlan(std.testing.allocator, &symbols, &variables, &rules);
    defer plan.scopes.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), plan.scopes.items.len);
    try std.testing.expectEqual(@as(usize, 0), plan.scopes.items[0].id);
    try std.testing.expectEqual(RecoveryScopeTarget.lhs, plan.scopes.items[0].target);
    try std.testing.expectEqual(@as(usize, 4), plan.scopes.items[1].id);
    try std.testing.expectEqual(RecoveryScopeTarget.occurrence, plan.scopes.items[1].target);
    try std.testing.expectEqual(@as(usize, 0), plan.findLhs(0).?.id);
    try std.testing.expectEqual(@as(usize, 4), plan.findOccurrence(0, 0).?.id);
}

pub fn emitStringLiteral(writer: *std.Io.Writer, bytes: []const u8) !void {
    try writer.writeByte('"');
    try std.zig.stringEscape(bytes, writer);
    try writer.writeByte('"');
}

pub fn emitEscapedForComment(writer: *std.Io.Writer, bytes: []const u8) !void {
    try std.zig.stringEscape(bytes, writer);
}

pub fn emitFormatToken(writer: *std.Io.Writer, bytes: []const u8) !void {
    for (bytes) |byte| {
        switch (byte) {
            '\n' => try writer.writeAll("\\\\n"),
            '\t' => try writer.writeAll("\\\\t"),
            '\r' => try writer.writeAll("\\\\r"),
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\\\\\"),
            '{' => try writer.writeAll("{{"),
            '}' => try writer.writeAll("}}"),
            0 => try writer.writeAll("\\\\x00"),
            0x01...0x08, 0x0b, 0x0c, 0x0e...0x1f, 0x7f...0xff => try writer.print("\\\\x{x:0>2}", .{byte}),
            else => try writer.writeByte(byte),
        }
    }
}

pub fn bytesToInt(bytes: []const u8) u128 {
    var value: u128 = 0;
    for (bytes) |byte| {
        value = (value << 8) | byte;
    }
    return value;
}

pub fn indented(allocator: std.mem.Allocator, indent: []const u8, extra: usize) ![]const u8 {
    var result = std.ArrayList(u8).empty;
    try result.appendSlice(allocator, indent);
    try result.appendNTimes(allocator, ' ', extra);
    return result.toOwnedSlice(allocator);
}

pub fn expandGenerativeTerminal(allocator: std.mem.Allocator, out: *std.ArrayList([]const u8), id: []const u8) !void {
    if (std.mem.eql(u8, id, "digit")) return appendChars(allocator, out, "0123456789");
    if (std.mem.eql(u8, id, "hex_digit")) return appendChars(allocator, out, "0123456789abcdefABCDEF");
    if (std.mem.eql(u8, id, "letter")) return appendChars(allocator, out, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ");
    if (std.mem.eql(u8, id, "lowercase_letter")) return appendChars(allocator, out, "abcdefghijklmnopqrstuvwxyz");
    if (std.mem.eql(u8, id, "uppercase_letter")) return appendChars(allocator, out, "ABCDEFGHIJKLMNOPQRSTUVWXYZ");
    if (std.mem.eql(u8, id, "new_line")) return out.append(allocator, "\n");
    if (std.mem.eql(u8, id, "space")) return out.append(allocator, " ");
    if (std.mem.eql(u8, id, "block_start")) return out.append(allocator, "\x01");
    if (std.mem.eql(u8, id, "block_end")) return out.append(allocator, "\x02");
    if (std.mem.eql(u8, id, "utf8_lead_two")) return appendByteRange(allocator, out, 0xc2, 0xdf);
    if (std.mem.eql(u8, id, "utf8_lead_three_general")) {
        try appendByteRange(allocator, out, 0xe1, 0xec);
        return appendByteRange(allocator, out, 0xee, 0xef);
    }
    if (std.mem.eql(u8, id, "utf8_lead_four_general")) return appendByteRange(allocator, out, 0xf1, 0xf3);
    if (std.mem.eql(u8, id, "utf8_continuation")) return appendByteRange(allocator, out, 0x80, 0xbf);
    if (std.mem.eql(u8, id, "utf8_continuation_80_8f")) return appendByteRange(allocator, out, 0x80, 0x8f);
    if (std.mem.eql(u8, id, "utf8_continuation_80_9f")) return appendByteRange(allocator, out, 0x80, 0x9f);
    if (std.mem.eql(u8, id, "utf8_continuation_90_bf")) return appendByteRange(allocator, out, 0x90, 0xbf);
    if (std.mem.eql(u8, id, "utf8_continuation_a0_bf")) return appendByteRange(allocator, out, 0xa0, 0xbf);
    if (std.mem.startsWith(u8, id, "character")) return appendCharsExcept(allocator, out, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~ \t\n\r\x0b\x0c", id);
    if (std.mem.startsWith(u8, id, "whitespace")) return appendChars(allocator, out, " \t\n\r\x0b\x0c");
    if (std.mem.startsWith(u8, id, "punctuation")) return appendChars(allocator, out, "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~");
    if (std.mem.startsWith(u8, id, "operator")) {
        for (&[_][]const u8{ "+", "*", "/", "&", "|", ">", ">=", "<", "<=", "=" }) |op| try out.append(allocator, op);
        return;
    }
    return error.UnknownGenerativeTerminal;
}

fn appendChars(allocator: std.mem.Allocator, out: *std.ArrayList([]const u8), chars: []const u8) !void {
    for (chars) |char| {
        const item = try allocator.alloc(u8, 1);
        item[0] = char;
        try out.append(allocator, item);
    }
}

fn appendByteRange(
    allocator: std.mem.Allocator,
    out: *std.ArrayList([]const u8),
    first: u8,
    last: u8,
) !void {
    var byte = first;
    while (true) : (byte += 1) {
        const item = try allocator.alloc(u8, 1);
        item[0] = byte;
        try out.append(allocator, item);
        if (byte == last) return;
    }
}

test "UTF-8 generative terminals expand to their exact byte ranges" {
    const Range = struct {
        first: u8,
        last: u8,
    };
    const Spec = struct {
        id: []const u8,
        ranges: []const Range,
    };
    const specs = [_]Spec{
        .{ .id = "utf8_lead_two", .ranges = &.{.{ .first = 0xc2, .last = 0xdf }} },
        .{ .id = "utf8_lead_three_general", .ranges = &.{
            .{ .first = 0xe1, .last = 0xec },
            .{ .first = 0xee, .last = 0xef },
        } },
        .{ .id = "utf8_lead_four_general", .ranges = &.{.{ .first = 0xf1, .last = 0xf3 }} },
        .{ .id = "utf8_continuation", .ranges = &.{.{ .first = 0x80, .last = 0xbf }} },
        .{ .id = "utf8_continuation_80_8f", .ranges = &.{.{ .first = 0x80, .last = 0x8f }} },
        .{ .id = "utf8_continuation_80_9f", .ranges = &.{.{ .first = 0x80, .last = 0x9f }} },
        .{ .id = "utf8_continuation_90_bf", .ranges = &.{.{ .first = 0x90, .last = 0xbf }} },
        .{ .id = "utf8_continuation_a0_bf", .ranges = &.{.{ .first = 0xa0, .last = 0xbf }} },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    for (specs) |spec| {
        var expanded: std.ArrayList([]const u8) = .empty;
        try expandGenerativeTerminal(arena.allocator(), &expanded, spec.id);

        var index: usize = 0;
        for (spec.ranges) |range| {
            var expected = range.first;
            while (true) : (expected += 1) {
                try std.testing.expect(index < expanded.items.len);
                try std.testing.expectEqual(@as(usize, 1), expanded.items[index].len);
                try std.testing.expectEqual(expected, expanded.items[index][0]);
                index += 1;
                if (expected == range.last) break;
            }
        }
        try std.testing.expectEqual(index, expanded.items.len);
    }
}

test "character exceptions exclude raw string and quoted content" {
    const Case = struct {
        id: []const u8,
        excluded: []const u8,
    };
    const cases = [_]Case{
        .{ .id = "character^\"\n\"", .excluded = "\n" },
        .{ .id = "character^\\\"~\"~\"", .excluded = "\"" },
        .{ .id = "character^\\\"~\"~\"^\"\n\"^\"\\\\\"", .excluded = "\"\n\\" },
        .{ .id = "character^\\\"~x~\"^\"\n\"", .excluded = "x\n" },
        .{ .id = "character^\\\"~~\"", .excluded = "" },
        .{ .id = "character^\"\\u{22}\"", .excluded = "\"" },
        .{ .id = "character^\"\\u{22}\"^\"\\u{a}\"^\"\\u{5c}\"", .excluded = "\"\n\\" },
        .{ .id = "character^\"\\u{40}\"^\"x\"", .excluded = "@x" },
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    for (cases) |case| {
        var expanded: std.ArrayList([]const u8) = .empty;
        try expandGenerativeTerminal(arena.allocator(), &expanded, case.id);
        for (case.excluded) |byte| {
            for (expanded.items) |item| {
                try std.testing.expect(!std.mem.eql(u8, item, &.{byte}));
            }
        }
    }
}

test "character exceptions reject malformed raw strings" {
    const malformed = [_][]const u8{
        "character^\\\"",
        "character^\\\"~",
        "character^\\\"~x~",
        "character^\\\"~x~x",
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for (malformed) |id| {
        var expanded: std.ArrayList([]const u8) = .empty;
        try std.testing.expectError(error.InvalidRawString, expandGenerativeTerminal(arena.allocator(), &expanded, id));
    }
}

fn appendCharsExcept(allocator: std.mem.Allocator, out: *std.ArrayList([]const u8), chars: []const u8, id: []const u8) !void {
    var excluded = [_]bool{false} ** 256;
    var i = std.mem.indexOfScalar(u8, id, '^') orelse id.len;
    while (i < id.len) {
        i += 1;
        if (i >= id.len) break;
        if (i + 1 < id.len and id[i] == '\\' and id[i + 1] == '"') {
            const end = rawStringEnd(id, i) orelse return error.InvalidRawString;
            const content_start = i + 3;
            for (id[content_start .. end - 2]) |byte| excluded[byte] = true;
            i = end;
            continue;
        }
        const quote = id[i];
        i += 1;
        while (i < id.len and id[i] != quote) {
            if (id[i] == '\\' and i + 1 < id.len) {
                switch (id[i + 1]) {
                    'n' => {
                        excluded['\n'] = true;
                        i += 2;
                        continue;
                    },
                    'r' => {
                        excluded['\r'] = true;
                        i += 2;
                        continue;
                    },
                    't' => {
                        excluded['\t'] = true;
                        i += 2;
                        continue;
                    },
                    'u' => {
                        if (i + 2 >= id.len or id[i + 2] != '{') return error.InvalidRawString;
                        const end = std.mem.indexOfScalarPos(u8, id, i + 3, '}') orelse return error.InvalidRawString;
                        const digits = id[i + 3 .. end];
                        if (digits.len == 0 or digits.len > 2) return error.InvalidRawString;
                        const byte = std.fmt.parseInt(u8, digits, 16) catch return error.InvalidRawString;
                        excluded[byte] = true;
                        i = end + 1;
                        continue;
                    },
                    else => {},
                }
            }
            excluded[id[i]] = true;
            i += 1;
        }
        if (i < id.len) i += 1;
    }
    for (chars) |byte| {
        if (!excluded[byte]) {
            const item = try allocator.alloc(u8, 1);
            item[0] = byte;
            try out.append(allocator, item);
        }
    }
}

/// Returns the index just past the closing quote of a raw string literal that
/// starts at `start` (which points at the opening backslash of `\"`). The
/// literal shape is `\"<indicator><content><indicator>"`.
fn rawStringEnd(id: []const u8, start: usize) ?usize {
    if (start + 2 >= id.len or id[start] != '\\' or id[start + 1] != '"') return null;
    const indicator = id[start + 2];
    const content_end = std.mem.indexOfScalarPos(u8, id, start + 3, indicator) orelse return null;
    const end = content_end + 2;
    if (end > id.len or id[end - 1] != '"') return null;
    return end;
}

test "diagnostic symbol and rule text renders productions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var symbols: std.ArrayList(Symbol) = .empty;
    var variables: std.ArrayList(usize) = .empty;
    const expression = try addSymbol(allocator, &symbols, &variables, "Expression", .variable);
    const plus = try addSymbol(allocator, &symbols, &variables, "+", .terminal);
    const term = try addSymbol(allocator, &symbols, &variables, "Term", .variable);
    const eof = try addSymbol(allocator, &symbols, &variables, "\x00", .end);

    const expression_text = try symbolText(allocator, symbols.items, expression);
    defer allocator.free(expression_text);
    try std.testing.expectEqualStrings("Expression", expression_text);

    const plus_text = try symbolText(allocator, symbols.items, plus);
    defer allocator.free(plus_text);
    try std.testing.expectEqualStrings("\"+\"", plus_text);

    const eof_text = try symbolText(allocator, symbols.items, eof);
    defer allocator.free(eof_text);
    try std.testing.expectEqualStrings("EOF", eof_text);

    var rule = Rule{ .header = expression, .rhs_index = "0" };
    try rule.rhs.append(allocator, term);
    try rule.rhs_annotations.append(allocator, .{});
    try rule.rhs.append(allocator, plus);
    try rule.rhs_annotations.append(allocator, .{});
    try rule.rhs.append(allocator, term);
    try rule.rhs_annotations.append(allocator, .{});

    const rule_text = try ruleText(allocator, symbols.items, rule);
    defer allocator.free(rule_text);
    try std.testing.expectEqualStrings("Expression -> Term \"+\" Term", rule_text);
}

test "strict reduction coverage selects visible productions only" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var symbols: std.ArrayList(Symbol) = .empty;
    var variables: std.ArrayList(usize) = .empty;
    const visible = try addSymbol(allocator, &symbols, &variables, "Visible", .variable);
    const helper = try addSymbol(allocator, &symbols, &variables, "_Helper", .variable);
    const terminal = try addSymbol(allocator, &symbols, &variables, "a", .terminal);
    const augmented = try addSymbol(allocator, &symbols, &variables, "_AugmentedStart", .variable);
    const generative = try addSymbol(allocator, &symbols, &variables, "GenerativeTerminal", .variable);

    var rules = std.ArrayList(Rule).empty;
    try rules.append(allocator, .{ .header = visible, .rhs_index = "0" });
    try rules.append(allocator, .{ .header = visible, .rhs_index = "1" });
    try rules.append(allocator, .{ .header = helper, .rhs_index = "0" });
    try rules.append(allocator, .{ .header = augmented, .rhs_index = "0" });
    try rules.append(allocator, .{ .header = generative, .rhs_index = "0" });

    try std.testing.expect(requiresReductionProcedure(symbols.items, rules.items, augmented, generative, 0));
    try std.testing.expect(requiresReductionProcedure(symbols.items, rules.items, augmented, generative, 1));
    try std.testing.expect(!requiresReductionProcedure(symbols.items, rules.items, augmented, generative, 2));
    try std.testing.expect(!requiresReductionProcedure(symbols.items, rules.items, augmented, generative, 3));
    try std.testing.expect(!requiresReductionProcedure(symbols.items, rules.items, augmented, generative, 4));

    const collected = try collectRequiredReductionProcedures(allocator, symbols.items, rules.items, augmented, generative);
    try std.testing.expectEqual(@as(usize, 2), collected.len);
    try std.testing.expectEqualStrings("reduction_Visible_0", collected[0].procedure_name);
    try std.testing.expectEqualStrings("Visible", collected[0].variable);
    try std.testing.expectEqualStrings("0", collected[0].rhs_index);
    try std.testing.expectEqualStrings("reduction_Visible_1", collected[1].procedure_name);
    _ = terminal;
}
