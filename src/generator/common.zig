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
    /// Receives every generation failure message, grammar syntax errors
    /// included, before the error is returned.
    error_reporter: ErrorReporter = null,
};

/// Receives one generation failure message. Null prints it to stderr.
pub const ErrorReporter = ?*const fn (message: []const u8) void;

/// The one exit for generation failure messages.
pub fn reportError(reporter: ErrorReporter, message: []const u8) void {
    if (reporter) |report| report(message) else std.debug.print("{s}\n", .{message});
}

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
    // `options` supplies only the error reporter: every field of the
    // prepared grammar is a grammar fact. Configuration is applied at
    // comptime inside the generated parser.
    try validateGrammar(allocator, grammar, options.error_reporter);

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
            "_GenerativeTerminal",
            .variable,
        );
        result.generative_terminal = generative_terminal;
        try result.rules.append(allocator, .{ .header = generative_terminal, .rhs_index = "0" });
    }

    std.mem.sort(Rule, result.rules.items, result.symbols.items, ruleLessThan);
    {
        const nullable = try allocator.alloc(bool, result.symbols.items.len);
        defer allocator.free(nullable);
        computeNullableFixpoint(&result, nullable);
        for (result.variables.items) |variable| {
            _ = try nullableRuleFromNullable(allocator, &result, nullable, variable, options.error_reporter);
        }
    }
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

/// Identifier-safe spellings of every symbol, indexed like the symbol table.
pub const SymbolNames = struct {
    /// Readable, kind-prefixed spelling: variables bare, `terminal_<spelling>`,
    /// `generative_terminal_<spelling>`, and `special_EOF` for end-of-input.
    reprs: []const []const u8,
    /// `safeIdentifier(repr)`: the stem of every generated Zig identifier and
    /// of every identifier-safe hook name.
    stems: []const []const u8,
};

/// The single source of generated-identifier stems: LL parser function names,
/// LR planning, and the `reduction_` hook binder all take their stems from
/// here. Fails with `error.SymbolNameCollision` when two producers would bind
/// one hook name. Every symbol but end of input binds `reduction_<stem>`, so
/// this also keeps stems, and the identifiers built from them, unique.
pub fn planSymbolNames(allocator: std.mem.Allocator, symbols: []const Symbol, rules: []const Rule, reporter: ErrorReporter) !SymbolNames {
    const reprs = try allocator.alloc([]const u8, symbols.len);
    const stems = try allocator.alloc([]const u8, symbols.len);
    for (symbols, 0..) |symbol, index| {
        const prefix = switch (symbol.kind) {
            .end => {
                reprs[index] = try allocator.dupe(u8, "special_EOF");
                stems[index] = reprs[index];
                continue;
            },
            .variable => "",
            .terminal => "terminal_",
            .generative_terminal => "generative_terminal_",
        };
        const spelling = try readableSymbolName(allocator, symbol.id);
        defer allocator.free(spelling);
        reprs[index] = try std.mem.concat(allocator, u8, &.{ prefix, spelling });
        stems[index] = try safeIdentifier(allocator, reprs[index]);
    }
    try checkHookNameCollisions(allocator, symbols, rules, stems, reporter);
    return .{ .reprs = reprs, .stems = stems };
}

/// One producer of a hook name: a symbol's readable or identifier-safe
/// name, or a production's `reduction_<Var>_<N>`.
const HookNameProducer = union(enum) { symbol: usize, production: usize };

fn checkHookNameCollisions(
    allocator: std.mem.Allocator,
    symbols: []const Symbol,
    rules: []const Rule,
    stems: []const []const u8,
    reporter: ErrorReporter,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var owners = std.StringHashMap(HookNameProducer).init(arena_allocator);
    for (symbols, stems, 0..) |symbol, stem, index| {
        const hook_names = try symbolHookNames(arena_allocator, symbol, stem) orelse continue;
        try claimHookName(&owners, symbols, rules, reporter, hook_names.readable, .{ .symbol = index });
        if (hook_names.identifier_safe) |name| try claimHookName(&owners, symbols, rules, reporter, name, .{ .symbol = index });
    }
    for (rules, 0..) |rule, index| {
        if (!bindsHooks(symbols[rule.header])) continue;
        try claimHookName(&owners, symbols, rules, reporter, try reductionProcedureName(arena_allocator, symbols, rule), .{ .production = index });
    }
}

fn claimHookName(
    owners: *std.StringHashMap(HookNameProducer),
    symbols: []const Symbol,
    rules: []const Rule,
    reporter: ErrorReporter,
    name: []const u8,
    producer: HookNameProducer,
) !void {
    const owner = try owners.getOrPut(name);
    if (!owner.found_existing) {
        owner.value_ptr.* = producer;
        return;
    }
    const message = try hookNameCollisionMessage(owners.allocator, symbols, rules, owner.value_ptr.*, producer, name);
    defer owners.allocator.free(message);
    reportError(reporter, message);
    return error.SymbolNameCollision;
}

fn hookNameCollisionMessage(
    allocator: std.mem.Allocator,
    symbols: []const Symbol,
    rules: []const Rule,
    first: HookNameProducer,
    second: HookNameProducer,
    name: []const u8,
) ![]const u8 {
    const first_text = try describeHookProducer(allocator, symbols, rules, first);
    defer allocator.free(first_text);
    const second_text = try describeHookProducer(allocator, symbols, rules, second);
    defer allocator.free(second_text);
    return std.fmt.allocPrint(
        allocator,
        "hook name collision: {s} and {s} both bind \"{s}\"; rename one of them",
        .{ first_text, second_text, name },
    );
}

fn describeHookProducer(
    allocator: std.mem.Allocator,
    symbols: []const Symbol,
    rules: []const Rule,
    producer: HookNameProducer,
) ![]const u8 {
    const symbol_index = switch (producer) {
        .production => |index| {
            const text = try ruleText(allocator, symbols, rules[index]);
            defer allocator.free(text);
            return std.fmt.allocPrint(allocator, "production {s}", .{text});
        },
        .symbol => |index| index,
    };
    const kind = switch (symbols[symbol_index].kind) {
        .variable => "variable",
        .terminal => "terminal",
        .generative_terminal => "generative terminal",
        .end => unreachable, // End of input binds no hook name.
    };
    const text = try symbolText(allocator, symbols, symbol_index);
    defer allocator.free(text);
    return std.fmt.allocPrint(allocator, "{s} {s}", .{ kind, text });
}

/// The two procedure-module declaration names that bind a symbol's automatic
/// hook. Both are looked up, `readable` first, so it wins when both exist.
pub const SymbolHookNames = struct {
    /// Variables and generative terminals: `reduction_<id>`. Terminals:
    /// `reduction_"<spelling>"`, spelled by `readableSymbolName`.
    readable: []const u8,
    /// `reduction_<stem>`; null when it equals `readable` (variables), so the
    /// binder never repeats a lookup.
    identifier_safe: ?[]const u8,
};

/// Whether `symbol` binds hooks. None of these produce a node a hook could
/// run for, so neither they nor their productions bind a hook name: end of
/// input, a variable whose name begins with `_` (helpers, the generator's
/// own `_AugmentedStart` and `_GenerativeTerminal` included), and a
/// transparent left-factoring tail, whose alternatives expand inline into
/// its parent.
pub fn bindsHooks(symbol: Symbol) bool {
    return switch (symbol.kind) {
        .end => false,
        .variable => !std.mem.startsWith(u8, symbol.id, "_") and !symbol.synthetic_transparent,
        .terminal, .generative_terminal => true,
    };
}

/// The hook names that bind `symbol`, or null when it binds none
/// (`bindsHooks`): no hook can run for it, so it has no name to claim or
/// look up. Its stem (`special_EOF` for end of input) still names generated
/// identifiers.
pub fn symbolHookNames(allocator: std.mem.Allocator, symbol: Symbol, stem: []const u8) !?SymbolHookNames {
    if (!bindsHooks(symbol)) return null;
    const readable = switch (symbol.kind) {
        .end => unreachable,
        .variable, .generative_terminal => try std.fmt.allocPrint(allocator, "reduction_{s}", .{symbol.id}),
        .terminal => blk: {
            const spelling = try readableSymbolName(allocator, symbol.id);
            defer allocator.free(spelling);
            break :blk try std.fmt.allocPrint(allocator, "reduction_\"{s}\"", .{spelling});
        },
    };
    const identifier_safe = try std.fmt.allocPrint(allocator, "reduction_{s}", .{stem});
    if (std.mem.eql(u8, readable, identifier_safe)) {
        allocator.free(identifier_safe);
        return .{ .readable = readable, .identifier_safe = null };
    }
    return .{ .readable = readable, .identifier_safe = identifier_safe };
}

/// Renders a production as `Header -> symbol symbol ...` for diagnostics,
/// or `Header -> <empty>` when the RHS is empty, matching `symbolsText`.
pub fn ruleText(allocator: std.mem.Allocator, symbols: []const Symbol, rule: Rule) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    const header = try symbolText(allocator, symbols, rule.header);
    defer allocator.free(header);
    try out.appendSlice(allocator, header);
    try out.appendSlice(allocator, " ->");
    if (rule.rhs.items.len == 0) {
        try out.appendSlice(allocator, " <empty>");
        return out.toOwnedSlice(allocator);
    }
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

/// Formats the epsilon/epsilon diagnostic for `variable` with its first two
/// nullable productions. Shared by `nullableRule` and its tests so the
/// logged text is asserted, not just the error.
pub fn nullableAmbiguityMessage(
    allocator: std.mem.Allocator,
    symbols: []const Symbol,
    variable: usize,
    first: Rule,
    second: Rule,
) ![]u8 {
    const variable_name = symbols[variable].id;
    const first_text = try ruleText(allocator, symbols, first);
    defer allocator.free(first_text);
    const second_text = try ruleText(allocator, symbols, second);
    defer allocator.free(second_text);
    return std.fmt.allocPrint(
        allocator,
        "ambiguous grammar: variable \"{s}\" has two nullable productions:\n  {s}\n  {s}",
        .{ variable_name, first_text, second_text },
    );
}

/// Nullable flags plus FIRST/FOLLOW terminal sets indexed by symbol.
/// Emptiness is reported through `nullable` rather than epsilon tokens.
pub const GrammarAnalysis = struct {
    nullable: []bool,
    firsts: []std.AutoHashMap(usize, void),
    follows: []std.AutoHashMap(usize, void),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *GrammarAnalysis) void {
        self.allocator.free(self.nullable);
        for (self.firsts) |*map| map.deinit();
        self.allocator.free(self.firsts);
        for (self.follows) |*map| map.deinit();
        self.allocator.free(self.follows);
    }

    pub fn isNullable(self: *const GrammarAnalysis, symbol: usize) bool {
        return self.nullable[symbol];
    }
};

fn computeNullableFixpoint(grammar: *const PreparedGrammar, nullable: []bool) void {
    @memset(nullable, false);
    var changed = true;
    while (changed) {
        changed = false;
        for (grammar.rules.items) |rule| {
            if (nullable[rule.header]) continue;
            var rule_nullable = true;
            for (rule.rhs.items) |symbol_index| {
                if (grammar.symbols.items[symbol_index].kind != .variable or !nullable[symbol_index]) {
                    rule_nullable = false;
                    break;
                }
            }
            if (rule_nullable) {
                nullable[rule.header] = true;
                changed = true;
            }
        }
    }
}

/// Computes nullable plus FIRST and FOLLOW terminal sets once per grammar.
/// FIRST(A) holds every terminal that can start a derivation of A; FOLLOW(A)
/// holds every terminal that can follow A. Neither stores epsilon; emptiness
/// is reported through `nullable`.
pub fn analyzeGrammarSets(allocator: std.mem.Allocator, grammar: *const PreparedGrammar) !GrammarAnalysis {
    const nullable = try allocator.alloc(bool, grammar.symbols.items.len);
    errdefer allocator.free(nullable);
    computeNullableFixpoint(grammar, nullable);

    var firsts = try allocator.alloc(std.AutoHashMap(usize, void), grammar.symbols.items.len);
    errdefer allocator.free(firsts);
    for (firsts) |*map| map.* = std.AutoHashMap(usize, void).init(allocator);
    errdefer {
        for (firsts) |*map| map.deinit();
    }

    var changed = true;
    while (changed) {
        changed = false;
        for (grammar.rules.items) |rule| {
            for (rule.rhs.items) |symbol_index| {
                if (grammar.symbols.items[symbol_index].kind != .variable) {
                    if (!firsts[rule.header].contains(symbol_index)) {
                        try firsts[rule.header].put(symbol_index, {});
                        changed = true;
                    }
                    break;
                }
                // Adding a variable's own FIRST set to itself is a no-op;
                // skipping also avoids mutating a map while iterating it.
                if (symbol_index != rule.header) {
                    var it = firsts[symbol_index].keyIterator();
                    while (it.next()) |entry| {
                        if (!firsts[rule.header].contains(entry.*)) {
                            try firsts[rule.header].put(entry.*, {});
                            changed = true;
                        }
                    }
                }
                if (!nullable[symbol_index]) break;
            }
        }
    }

    var follows = try allocator.alloc(std.AutoHashMap(usize, void), grammar.symbols.items.len);
    errdefer allocator.free(follows);
    for (follows) |*map| map.* = std.AutoHashMap(usize, void).init(allocator);
    errdefer {
        for (follows) |*map| map.deinit();
    }

    changed = true;
    while (changed) {
        changed = false;
        for (grammar.rules.items) |rule| {
            for (rule.rhs.items, 0..) |symbol_index, position| {
                if (grammar.symbols.items[symbol_index].kind != .variable) continue;
                var next = position + 1;
                var propagates = true;
                while (next < rule.rhs.items.len) {
                    const next_index = rule.rhs.items[next];
                    if (grammar.symbols.items[next_index].kind != .variable) {
                        if (!follows[symbol_index].contains(next_index)) {
                            try follows[symbol_index].put(next_index, {});
                            changed = true;
                        }
                        propagates = false;
                        break;
                    }
                    var it = firsts[next_index].keyIterator();
                    while (it.next()) |entry| {
                        if (!follows[symbol_index].contains(entry.*)) {
                            try follows[symbol_index].put(entry.*, {});
                            changed = true;
                        }
                    }
                    if (!nullable[next_index]) {
                        propagates = false;
                        break;
                    }
                    next += 1;
                }
                // Empty or fully nullable suffix: FOLLOW(header) flows here.
                // Self-propagation is a no-op; skipping avoids iterating a
                // map while mutating it.
                if (propagates and rule.header != symbol_index) {
                    var it = follows[rule.header].keyIterator();
                    while (it.next()) |entry| {
                        if (!follows[symbol_index].contains(entry.*)) {
                            try follows[symbol_index].put(entry.*, {});
                            changed = true;
                        }
                    }
                }
            }
        }
    }

    return .{ .nullable = nullable, .firsts = firsts, .follows = follows, .allocator = allocator };
}

/// Given a finished nullable table, returns the index of the sole nullable
/// rule for `variable`, or null when none exists. Two nullable productions
/// report both shapes and return `error.AmbiguousGrammar`.
pub fn nullableRuleFromNullable(
    allocator: std.mem.Allocator,
    grammar: *const PreparedGrammar,
    nullable: []const bool,
    variable: usize,
    reporter: ErrorReporter,
) !?usize {
    var found: ?usize = null;
    for (grammar.rules.items, 0..) |rule, rule_index| {
        if (rule.header != variable) continue;
        var rule_nullable = true;
        for (rule.rhs.items) |symbol_index| {
            if (grammar.symbols.items[symbol_index].kind != .variable or !nullable[symbol_index]) {
                rule_nullable = false;
                break;
            }
        }
        if (!rule_nullable) continue;
        if (found) |first| {
            const message = try nullableAmbiguityMessage(
                allocator,
                grammar.symbols.items,
                variable,
                grammar.rules.items[first],
                rule,
            );
            defer allocator.free(message);
            reportError(reporter, message);
            return error.AmbiguousGrammar;
        }
        found = rule_index;
    }
    return found;
}

/// Returns the index of the sole nullable rule for `variable`, or null when
/// none exists. When two or more productions of the same variable are
/// nullable the grammar is ambiguous and `error.AmbiguousGrammar` is
/// returned after reporting the variable and both productions.
pub fn nullableRule(
    allocator: std.mem.Allocator,
    grammar: *const PreparedGrammar,
    variable: usize,
    reporter: ErrorReporter,
) !?usize {
    const nullable = try allocator.alloc(bool, grammar.symbols.items.len);
    defer allocator.free(nullable);
    computeNullableFixpoint(grammar, nullable);
    return nullableRuleFromNullable(allocator, grammar, nullable, variable, reporter);
}

/// Rejects grammars whose verbatim-annotated RHS positions can match empty
/// input, shared by the LL and LR planners.
pub fn validateVerbatimSymbols(allocator: std.mem.Allocator, grammar: *const PreparedGrammar, reporter: ErrorReporter) !void {
    if (!grammar.uses_verbatim) return;
    const nullable = try allocator.alloc(bool, grammar.symbols.items.len);
    defer allocator.free(nullable);
    computeNullableFixpoint(grammar, nullable);
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
                .variable => try nullableRuleFromNullable(allocator, grammar, nullable, symbol_index, reporter) != null,
                .end => false,
            };
            if (empty_matchable) return error.EmptyVerbatimSymbol;
        }
    }
}

/// Collects the FIRST terminals of the symbols appearing after the dot of an
/// item, falling back to the item's own lookahead when the tail is empty or
/// fully nullable.
pub fn firstsAfterItemWithAnalysis(
    grammar: *const PreparedGrammar,
    analysis: *const GrammarAnalysis,
    item: anytype,
    out: *std.AutoHashMap(usize, void),
) !void {
    const rule = grammar.rules.items[item.rule];
    var index = item.head + 1;
    while (index < rule.rhs.items.len) : (index += 1) {
        const symbol_index = rule.rhs.items[index];
        if (grammar.symbols.items[symbol_index].kind == .variable) {
            var it = analysis.firsts[symbol_index].keyIterator();
            while (it.next()) |entry| try out.put(entry.*, {});
            if (!analysis.nullable[symbol_index]) return;
        } else {
            try out.put(symbol_index, {});
            return;
        }
    }
    try out.put(item.lookahead, {});
}

/// Resolves whether a rule RHS position carries a procedure occurrence.
/// Grammar fact only: an occurrence exists whenever the grammar declares a
/// procedure or verbatim at that position. Which occurrences run under a
/// given configuration is decided at comptime inside the generated parser.
pub fn procedureOccurrenceFor(
    grammar: *const PreparedGrammar,
    rule_index: usize,
    position: usize,
) ?RecoveryOccurrence {
    const rule = grammar.rules.items[rule_index];
    if (position >= rule.rhs.items.len) return null;
    const annotations = rule.rhs_annotations.items[position];
    if (annotations.verbatim) return .{ .rule = rule_index, .position = position };
    if (annotations.procedures.items.len == 0) return null;
    return .{ .rule = rule_index, .position = position };
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

pub fn validateGrammar(allocator: std.mem.Allocator, grammar: anytype, reporter: ErrorReporter) !void {
    if (findDuplicateRuleHeader(grammar.rules)) |duplicate| {
        const rule = grammar.rules[duplicate.second];
        const message = try std.fmt.allocPrint(allocator, "duplicate rule header \"{s}\" (first defined at rule {d})", .{ rule.header, duplicate.first + 1 });
        defer allocator.free(message);
        reportError(reporter, message);
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
                    const message = try std.fmt.allocPrint(allocator, "undefined variable \"{s}\" referenced in rule \"{s}\"", .{ symbol.id, rule.header });
                    defer allocator.free(message);
                    reportError(reporter, message);
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
/// a header that binds no hooks (`bindsHooks`) or builds no node
/// (`ast_enabled == false`) is excluded.
/// Both the generated parser's comptime check and the CLI's generation-time
/// warning delegate here so they can never diverge.
pub fn requiresReductionProcedure(
    symbols: []const Symbol,
    rules: []const Rule,
    rule_index: usize,
) bool {
    const header = symbols[rules[rule_index].header];
    if (header.kind != .variable) return false;
    if (!bindsHooks(header)) return false;
    return header.ast_enabled;
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
) ![]RequiredReductionProcedure {
    var out = std.ArrayList(RequiredReductionProcedure).empty;
    for (rules, 0..) |rule, rule_index| {
        if (!requiresReductionProcedure(symbols, rules, rule_index)) continue;
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

/// What a hook name binds. A compiled consumer's generated `procedures.zig`
/// wraps only the `general`, `variable` and `annotation` hooks.
pub const HookFamily = enum { general, variable, terminal, production, annotation };

/// A symbol's hook: its index in `HookPlan.names`, and the Zig-only spelling
/// the binder looks up before the listed name.
pub const SymbolHook = struct {
    index: usize,
    /// `reduction_"<spelling>"` for a terminal, `reduction_<id>` for a
    /// generative terminal; null for a variable, whose listed name is
    /// already its readable one.
    readable: ?[]const u8,
};

/// Every hook a generated parser binds, planned once from its prepared
/// grammar. A hook's index is its position in `names`, and every name is an
/// identifier, so every host can spell it. The emitted parser binds through
/// these indexes and serves `names` as its `hook_names`, so the list a
/// library validates installs against and the parser's binding are one
/// table.
pub const HookPlan = struct {
    names: []const []const u8,
    families: []const HookFamily,
    /// Indexed like the symbol table; null for a symbol that binds none.
    symbols: []const ?SymbolHook,
    /// Indexed like the rule table: the `reduction_<Var>_<N>` hook, or null
    /// when the rule's header binds none.
    rules: []const ?usize,
    /// Annotation procedure name (`print`) to the index of its `hook_print`.
    annotations: std.StringArrayHashMapUnmanaged(usize),

    /// The general fallback `reduction` is always hook zero.
    pub const general_index = 0;

    pub const empty: HookPlan = .{ .names = &.{}, .families = &.{}, .symbols = &.{}, .rules = &.{}, .annotations = .empty };

    pub fn annotationIndex(self: *const HookPlan, procedure: []const u8) usize {
        return self.annotations.get(procedure).?;
    }
};

/// Plans `HookPlan` for a prepared grammar and its symbol stems: the general
/// `reduction`, then `reduction_<stem>` per symbol that binds hooks, then
/// `reduction_<Var>_<N>` per rule of such a symbol, then `hook_<name>` per
/// annotation procedure in first-use order. Allocates from `allocator`,
/// which must be an arena: the plan also holds static and grammar-owned
/// strings, so its parts are never freed one by one.
pub fn planHooks(
    allocator: std.mem.Allocator,
    symbols: []const Symbol,
    stems: []const []const u8,
    rules: []const Rule,
    variables: []const usize,
) !HookPlan {
    var hook_names: std.ArrayList([]const u8) = .empty;
    var families: std.ArrayList(HookFamily) = .empty;
    try hook_names.append(allocator, "reduction");
    try families.append(allocator, .general);

    const symbol_hooks = try allocator.alloc(?SymbolHook, symbols.len);
    for (symbols, stems, symbol_hooks) |symbol, stem, *symbol_hook| {
        const symbol_hook_names = try symbolHookNames(allocator, symbol, stem) orelse {
            symbol_hook.* = null;
            continue;
        };
        const identifier_safe = symbol_hook_names.identifier_safe orelse symbol_hook_names.readable;
        symbol_hook.* = .{
            .index = hook_names.items.len,
            .readable = if (symbol_hook_names.identifier_safe != null) symbol_hook_names.readable else null,
        };
        try hook_names.append(allocator, identifier_safe);
        try families.append(allocator, if (symbol.kind == .variable) .variable else .terminal);
    }

    const rule_hooks = try allocator.alloc(?usize, rules.len);
    for (rules, rule_hooks) |rule, *rule_hook| {
        if (!bindsHooks(symbols[rule.header])) {
            rule_hook.* = null;
            continue;
        }
        rule_hook.* = hook_names.items.len;
        try hook_names.append(allocator, try reductionProcedureName(allocator, symbols, rule));
        try families.append(allocator, .production);
    }

    var annotations: std.StringArrayHashMapUnmanaged(usize) = .empty;
    for (rules) |rule| {
        try planAnnotationHooks(allocator, &hook_names, &families, &annotations, rule.annotations.procedures.items);
        for (rule.rhs_annotations.items) |rhs_annotations| {
            try planAnnotationHooks(allocator, &hook_names, &families, &annotations, rhs_annotations.procedures.items);
        }
    }
    for (variables) |symbol_index| {
        try planAnnotationHooks(allocator, &hook_names, &families, &annotations, symbols[symbol_index].annotations.procedures.items);
    }

    return .{
        .names = try hook_names.toOwnedSlice(allocator),
        .families = try families.toOwnedSlice(allocator),
        .symbols = symbol_hooks,
        .rules = rule_hooks,
        .annotations = annotations,
    };
}

fn planAnnotationHooks(
    allocator: std.mem.Allocator,
    hook_names: *std.ArrayList([]const u8),
    families: *std.ArrayList(HookFamily),
    annotations: *std.StringArrayHashMapUnmanaged(usize),
    procedures: []const []const u8,
) !void {
    for (procedures) |procedure| {
        const entry = try annotations.getOrPut(allocator, procedure);
        if (entry.found_existing) continue;
        entry.value_ptr.* = hook_names.items.len;
        try hook_names.append(allocator, try std.fmt.allocPrint(allocator, "hook_{s}", .{procedure}));
        try families.append(allocator, .annotation);
    }
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

/// Identical bytes only; prefixes stay longest-match.
pub fn overlappingTerminalMember(a: []const []const u8, b: []const []const u8) ?[]const u8 {
    for (a) |x| {
        for (b) |y| {
            if (std.mem.eql(u8, x, y)) return x;
        }
    }
    return null;
}

/// Null for identical indices; otherwise the first shared byte sequence.
pub fn overlappingSymbolMember(symbols: []const Symbol, a: usize, b: usize) ?[]const u8 {
    if (a == b) return null;
    if (a >= symbols.len or b >= symbols.len) return null;
    return overlappingTerminalMember(symbols[a].terminals.items, symbols[b].terminals.items);
}

test "overlapping members require identical bytes" {
    try std.testing.expectEqualStrings("a", overlappingTerminalMember(&.{ "a", "ab" }, &.{"a"}).?);
    try std.testing.expect(overlappingTerminalMember(&.{"="}, &.{"=="}) == null);
    try std.testing.expect(overlappingTerminalMember(&.{""}, &.{""}).?.len == 0);
    try std.testing.expect(overlappingTerminalMember(&.{"a"}, &.{"b"}) == null);
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
    const caret = std.mem.indexOfScalar(u8, id, '^');
    const base = if (caret) |index| id[0..index] else id;
    var members: std.ArrayList([]const u8) = .empty;
    defer members.deinit(allocator);
    try expandBaseTerminal(allocator, &members, base);
    if (caret == null) {
        try out.appendSlice(allocator, members.items);
        return;
    }
    var exceptions: std.ArrayList([]const u8) = .empty;
    defer exceptions.deinit(allocator);
    try parseExceptionTerminals(allocator, id, &exceptions);
    for (members.items) |member| {
        // Exceptions match members by whole-string equality.
        var excluded = false;
        for (exceptions.items) |exception| {
            if (std.mem.eql(u8, member, exception)) {
                excluded = true;
                break;
            }
        }
        if (!excluded) try out.append(allocator, member);
    }
}

fn expandBaseTerminal(allocator: std.mem.Allocator, out: *std.ArrayList([]const u8), base: []const u8) !void {
    if (std.mem.eql(u8, base, "digit")) return appendChars(allocator, out, "0123456789");
    if (std.mem.eql(u8, base, "hex_digit")) return appendChars(allocator, out, "0123456789abcdefABCDEF");
    if (std.mem.eql(u8, base, "letter")) return appendChars(allocator, out, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ");
    if (std.mem.eql(u8, base, "lowercase_letter")) return appendChars(allocator, out, "abcdefghijklmnopqrstuvwxyz");
    if (std.mem.eql(u8, base, "uppercase_letter")) return appendChars(allocator, out, "ABCDEFGHIJKLMNOPQRSTUVWXYZ");
    if (std.mem.eql(u8, base, "new_line")) return out.append(allocator, "\n");
    if (std.mem.eql(u8, base, "space")) return out.append(allocator, " ");
    if (std.mem.eql(u8, base, "block_start")) return out.append(allocator, "\x01");
    if (std.mem.eql(u8, base, "block_end")) return out.append(allocator, "\x02");
    if (std.mem.eql(u8, base, "utf8_lead_two")) return appendByteRange(allocator, out, 0xc2, 0xdf);
    if (std.mem.eql(u8, base, "utf8_lead_three_general")) {
        try appendByteRange(allocator, out, 0xe1, 0xec);
        return appendByteRange(allocator, out, 0xee, 0xef);
    }
    if (std.mem.eql(u8, base, "utf8_lead_four_general")) return appendByteRange(allocator, out, 0xf1, 0xf3);
    if (std.mem.eql(u8, base, "utf8_continuation")) return appendByteRange(allocator, out, 0x80, 0xbf);
    if (std.mem.eql(u8, base, "utf8_continuation_80_8f")) return appendByteRange(allocator, out, 0x80, 0x8f);
    if (std.mem.eql(u8, base, "utf8_continuation_80_9f")) return appendByteRange(allocator, out, 0x80, 0x9f);
    if (std.mem.eql(u8, base, "utf8_continuation_90_bf")) return appendByteRange(allocator, out, 0x90, 0xbf);
    if (std.mem.eql(u8, base, "utf8_continuation_a0_bf")) return appendByteRange(allocator, out, 0xa0, 0xbf);
    if (std.mem.eql(u8, base, "character")) return appendChars(allocator, out, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~ \t\n\r\x0b\x0c");
    if (std.mem.eql(u8, base, "whitespace")) return appendChars(allocator, out, " \t\n\r\x0b\x0c");
    if (std.mem.eql(u8, base, "punctuation")) return appendChars(allocator, out, "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~");
    if (std.mem.eql(u8, base, "operator")) {
        for (&[_][]const u8{ "+", "*", "/", "&", "|", ">", ">=", "<", "<=", "=" }) |op| try out.append(allocator, op);
        return;
    }
    return error.UnknownGenerativeTerminal;
}

fn parseExceptionTerminals(allocator: std.mem.Allocator, id: []const u8, out: *std.ArrayList([]const u8)) !void {
    var i = std.mem.indexOfScalar(u8, id, '^') orelse return;
    while (i < id.len) {
        i += 1;
        if (i >= id.len) break;
        if (i + 1 < id.len and id[i] == '\\' and id[i + 1] == '"') {
            const end = rawStringEnd(id, i) orelse return error.InvalidRawString;
            const content = try allocator.dupe(u8, id[i + 3 .. end - 2]);
            try out.append(allocator, content);
            i = end;
            continue;
        }
        const quote = id[i];
        i += 1;
        var decoded = std.ArrayList(u8).empty;
        defer decoded.deinit(allocator);
        while (i < id.len and id[i] != quote) {
            if (id[i] == '\\' and i + 1 < id.len) {
                switch (id[i + 1]) {
                    'n' => {
                        try decoded.append(allocator, '\n');
                        i += 2;
                        continue;
                    },
                    'r' => {
                        try decoded.append(allocator, '\r');
                        i += 2;
                        continue;
                    },
                    't' => {
                        try decoded.append(allocator, '\t');
                        i += 2;
                        continue;
                    },
                    '\\' => {
                        try decoded.append(allocator, '\\');
                        i += 2;
                        continue;
                    },
                    '"' => {
                        try decoded.append(allocator, '"');
                        i += 2;
                        continue;
                    },
                    '\'' => {
                        try decoded.append(allocator, '\'');
                        i += 2;
                        continue;
                    },
                    'x' => {
                        if (i + 3 >= id.len) return error.InvalidRawString;
                        const byte = std.fmt.parseInt(u8, id[i + 2 .. i + 4], 16) catch return error.InvalidRawString;
                        try decoded.append(allocator, byte);
                        i += 4;
                        continue;
                    },
                    'u' => {
                        if (i + 2 >= id.len or id[i + 2] != '{') return error.InvalidRawString;
                        const end = std.mem.indexOfScalarPos(u8, id, i + 3, '}') orelse return error.InvalidRawString;
                        const digits = id[i + 3 .. end];
                        if (digits.len == 0 or digits.len > 2) return error.InvalidRawString;
                        const byte = std.fmt.parseInt(u8, digits, 16) catch return error.InvalidRawString;
                        try decoded.append(allocator, byte);
                        i = end + 1;
                        continue;
                    },
                    else => {
                        try decoded.append(allocator, id[i + 1]);
                        i += 2;
                        continue;
                    },
                }
            }
            try decoded.append(allocator, id[i]);
            i += 1;
        }
        if (i < id.len) i += 1;
        try out.append(allocator, try decoded.toOwnedSlice(allocator));
    }
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
        .{ .id = "character^\"\\n\"", .excluded = "\n" },
        .{ .id = "character^\"\\t\"", .excluded = "\t" },
        .{ .id = "character^\"\\r\"", .excluded = "\r" },
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

test "generative exceptions exclude whole terminals for every class" {
    const Case = struct {
        id: []const u8,
        expected_count: usize,
        present: []const u8,
        absent: []const u8,
    };
    const cases = [_]Case{
        .{ .id = "digit^\"1\"", .expected_count = 9, .present = "029", .absent = "1" },
        .{ .id = "digit^\"1\"^\"3\"", .expected_count = 8, .present = "029", .absent = "13" },
        .{ .id = "whitespace^\" \"", .expected_count = 5, .present = "\t\n", .absent = " " },
        .{ .id = "punctuation^\".\"", .expected_count = 31, .present = "!,", .absent = "." },
        .{ .id = "letter^\"a\"", .expected_count = 51, .present = "b", .absent = "a" },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    for (cases) |case| {
        var expanded: std.ArrayList([]const u8) = .empty;
        try expandGenerativeTerminal(arena.allocator(), &expanded, case.id);
        try std.testing.expectEqual(case.expected_count, expanded.items.len);
        for (case.present) |byte| {
            var found = false;
            for (expanded.items) |item| {
                if (std.mem.eql(u8, item, &.{byte})) found = true;
            }
            try std.testing.expect(found);
        }
        for (case.absent) |byte| {
            for (expanded.items) |item| {
                try std.testing.expect(!std.mem.eql(u8, item, &.{byte}));
            }
        }
    }

    var operator_single: std.ArrayList([]const u8) = .empty;
    try expandGenerativeTerminal(arena.allocator(), &operator_single, "operator^\"+\"");
    try std.testing.expectEqual(@as(usize, 9), operator_single.items.len);
    for (operator_single.items) |item| {
        try std.testing.expect(!std.mem.eql(u8, item, "+"));
    }

    var operator_multi: std.ArrayList([]const u8) = .empty;
    try expandGenerativeTerminal(arena.allocator(), &operator_multi, "operator^\">=\"");
    try std.testing.expectEqual(@as(usize, 9), operator_multi.items.len);
    var saw_head = false;
    var saw_tail = false;
    for (operator_multi.items) |item| {
        try std.testing.expect(!std.mem.eql(u8, item, ">="));
        if (std.mem.eql(u8, item, ">")) saw_head = true;
        if (std.mem.eql(u8, item, "=")) saw_tail = true;
    }
    try std.testing.expect(saw_head);
    try std.testing.expect(saw_tail);
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

    const empty_rule = Rule{ .header = expression, .rhs_index = "1" };
    const empty_text = try ruleText(allocator, symbols.items, empty_rule);
    defer allocator.free(empty_text);
    try std.testing.expectEqualStrings("Expression -> <empty>", empty_text);
}

test "nullable ambiguity message names the variable and both productions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var symbols: std.ArrayList(Symbol) = .empty;
    var variables: std.ArrayList(usize) = .empty;
    const variable = try addSymbol(allocator, &symbols, &variables, "A", .variable);
    const other_variable = try addSymbol(allocator, &symbols, &variables, "B", .variable);

    const empty_rule = Rule{ .header = variable, .rhs_index = "0" };
    var second_rule = Rule{ .header = variable, .rhs_index = "1" };
    try second_rule.rhs.append(allocator, other_variable);
    try second_rule.rhs_annotations.append(allocator, .{});

    const message = try nullableAmbiguityMessage(allocator, symbols.items, variable, empty_rule, second_rule);
    defer allocator.free(message);
    try std.testing.expectEqualStrings(
        "ambiguous grammar: variable \"A\" has two nullable productions:\n  A -> <empty>\n  A -> B",
        message,
    );
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
    const generative = try addSymbol(allocator, &symbols, &variables, "_GenerativeTerminal", .variable);

    var rules = std.ArrayList(Rule).empty;
    try rules.append(allocator, .{ .header = visible, .rhs_index = "0" });
    try rules.append(allocator, .{ .header = visible, .rhs_index = "1" });
    try rules.append(allocator, .{ .header = helper, .rhs_index = "0" });
    try rules.append(allocator, .{ .header = augmented, .rhs_index = "0" });
    try rules.append(allocator, .{ .header = generative, .rhs_index = "0" });

    try std.testing.expect(requiresReductionProcedure(symbols.items, rules.items, 0));
    try std.testing.expect(requiresReductionProcedure(symbols.items, rules.items, 1));
    try std.testing.expect(!requiresReductionProcedure(symbols.items, rules.items, 2));
    try std.testing.expect(!requiresReductionProcedure(symbols.items, rules.items, 3));
    try std.testing.expect(!requiresReductionProcedure(symbols.items, rules.items, 4));

    const collected = try collectRequiredReductionProcedures(allocator, symbols.items, rules.items);
    try std.testing.expectEqual(@as(usize, 2), collected.len);
    try std.testing.expectEqualStrings("reduction_Visible_0", collected[0].procedure_name);
    try std.testing.expectEqualStrings("Visible", collected[0].variable);
    try std.testing.expectEqualStrings("0", collected[0].rhs_index);
    try std.testing.expectEqualStrings("reduction_Visible_1", collected[1].procedure_name);
    _ = terminal;
}

test "symbol hook names are a readable spelling plus the identifier-safe stem" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var symbols: std.ArrayList(Symbol) = .empty;
    var variables: std.ArrayList(usize) = .empty;
    _ = try addSymbol(allocator, &symbols, &variables, "A", .variable);
    _ = try addSymbol(allocator, &symbols, &variables, "A", .terminal);
    _ = try addSymbol(allocator, &symbols, &variables, "{", .terminal);
    _ = try addSymbol(allocator, &symbols, &variables, "\t", .terminal);
    _ = try addSymbol(allocator, &symbols, &variables, "\x00", .terminal);
    _ = try addSymbol(allocator, &symbols, &variables, "digit", .generative_terminal);
    _ = try addSymbol(allocator, &symbols, &variables, "\x00", .end);

    const expected = [_]struct { readable: []const u8, identifier_safe: ?[]const u8 }{
        .{ .readable = "reduction_A", .identifier_safe = null },
        .{ .readable = "reduction_\"A\"", .identifier_safe = "reduction_terminal_A" },
        .{ .readable = "reduction_\"{\"", .identifier_safe = "reduction_terminal__x123" },
        .{ .readable = "reduction_\"\\t\"", .identifier_safe = "reduction_terminal__x92t" },
        .{ .readable = "reduction_\"\\x00\"", .identifier_safe = "reduction_terminal__x92x00" },
        .{ .readable = "reduction_digit", .identifier_safe = "reduction_generative_terminal_digit" },
    };
    const symbol_names = try planSymbolNames(allocator, symbols.items, &.{}, null);
    for (expected, 0..) |entry, index| {
        const hook_names = (try symbolHookNames(allocator, symbols.items[index], symbol_names.stems[index])).?;
        try std.testing.expectEqualStrings(entry.readable, hook_names.readable);
        try std.testing.expectEqualDeep(entry.identifier_safe, hook_names.identifier_safe);
    }
    // End of input binds no hook but keeps its identifier stem.
    try std.testing.expectEqual(@as(?SymbolHookNames, null), try symbolHookNames(allocator, symbols.items[6], symbol_names.stems[6]));
    try std.testing.expectEqualStrings("special_EOF", symbol_names.stems[6]);
}

/// Keeps the last reported generation failure message for assertions.
const CapturedError = struct {
    var buffer: [256]u8 = undefined;
    var length: usize = 0;

    fn report(message: []const u8) void {
        length = @min(message.len, buffer.len);
        @memcpy(buffer[0..length], message[0..length]);
    }

    fn last() []const u8 {
        return buffer[0..length];
    }
};

test "two producers of one hook name fail symbol name planning and report both" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // `safeIdentifier` maps both "," and "_x44" to `terminal__x44`.
    var terminal_symbols: std.ArrayList(Symbol) = .empty;
    var terminal_variables: std.ArrayList(usize) = .empty;
    _ = try addSymbol(allocator, &terminal_symbols, &terminal_variables, ",", .terminal);
    _ = try addSymbol(allocator, &terminal_symbols, &terminal_variables, "_x44", .terminal);
    try std.testing.expectError(error.SymbolNameCollision, planSymbolNames(allocator, terminal_symbols.items, &.{}, &CapturedError.report));
    try std.testing.expectEqualStrings(
        "hook name collision: terminal \",\" and terminal \"_x44\" both bind \"reduction_terminal__x44\"; rename one of them",
        CapturedError.last(),
    );

    // The first production of `A` and the variable `A_0` both bind `reduction_A_0`.
    var symbols: std.ArrayList(Symbol) = .empty;
    var variables: std.ArrayList(usize) = .empty;
    const a = try addSymbol(allocator, &symbols, &variables, "A", .variable);
    _ = try addSymbol(allocator, &symbols, &variables, "A_0", .variable);
    const terminal = try addSymbol(allocator, &symbols, &variables, "a", .terminal);
    var rules: std.ArrayList(Rule) = .empty;
    try rules.append(allocator, .{ .header = a, .rhs_index = "0" });
    try rules.items[0].rhs.append(allocator, terminal);
    try std.testing.expectError(error.SymbolNameCollision, planSymbolNames(allocator, symbols.items, rules.items, &CapturedError.report));
    try std.testing.expectEqualStrings(
        "hook name collision: variable A_0 and production A -> \"a\" both bind \"reduction_A_0\"; rename one of them",
        CapturedError.last(),
    );
}
