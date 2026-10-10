const std = @import("std");
const common = @import("generator_common");
const emitter_common = @import("generator_emitter_common");
const planning = @import("ll_plan.zig");
const switch_planning = @import("generator_switch_plan");

pub const Options = common.Options;
pub const atomic_file = common.atomic_file;
const Symbol = common.Symbol;
const Rule = common.Rule;
const emitFormatToken = common.emitFormatToken;
const emitStringLiteral = common.emitStringLiteral;
const indented = common.indented;
const SyntaxErrorHandlerSpec = planning.SyntaxErrorHandler;
const LLPlan = planning.LLPlan;

/// Explicit error set for the transparent-tail expansion cycle
/// (emitChildParseLine → emitTransparentTailInline → Switch → Leaf → back).
/// Covers writer failures and allocation; naming it breaks the inference
/// loop Zig reports for mutually recursive emitters.
const EmitError = std.mem.Allocator.Error || std.Io.Writer.Error;

/// The LL backend tracks the in-progress variable stack whenever the generated
/// parser is compiled with the stack enabled (`syntax_error_stack_depth > 1`).
/// The generated source gates the push/pop instrumentation on the comptime
/// `is_syntax_error_stack_enabled` const: when the stack is enabled, the
/// `defer` that pops the stack always runs; when disabled, the whole
/// instrumentation folds away.
const Generator = struct {
    allocator: std.mem.Allocator,
    options: Options,
    symbols: std.ArrayList(Symbol),
    variables: std.ArrayList(usize),
    rules: std.ArrayList(Rule),
    plan: *const LLPlan,
    has_occurrence_procedures: bool,
    uses_explicit_recovery: bool,
    has_recovery_annotations: bool,
    uses_verbatim: bool,
    end_symbol: usize,
    verbatim_literal: ?[]const u8 = null,
    verbatim_consume: bool = true,
    decision_count: usize = 0,
    /// Comptime branch budget spent so far in the body being rendered by
    /// calls to inline terminal parsers (see `functionBodyBranchQuota`).
    inline_call_cost: usize = 0,
    /// Comptime branch budget one call to each terminal parser spends in its
    /// caller, indexed by symbol; filled before any parser is emitted.
    terminal_inline_costs: []usize = &.{},
    /// Largest `functionBodyBranchQuota` computed since it was last reset, so
    /// a terminal's cost is measured exactly like any caller's body.
    largest_body_branch_quota: usize = 0,
    /// The tail loop whose rule dispatch is being rendered, if any.
    tail_loop: ?TailLoop = null,
    /// The variable whose flattened parser body is being rendered, if any:
    /// its children go to the caller's node, `node_address`.
    flattened_variable: ?usize = null,
    /// Whether the occurrence being emitted is the last symbol of the tail
    /// loop variable's rule, counting through inlined helpers.
    in_last_position: bool = false,
    /// Which of the current level's occurrence values the code emitted since
    /// the last reset names, so a tail loop declares exactly those.
    occurrence_uses: OccurrenceUses = .{},

    fn init(allocator: std.mem.Allocator, options: Options, grammar: *const common.PreparedGrammar, plan: *const LLPlan) Generator {
        return .{
            .allocator = allocator,
            .options = options,
            .symbols = grammar.symbols,
            .variables = grammar.variables,
            .rules = grammar.rules,
            .plan = plan,
            .has_occurrence_procedures = grammar.has_occurrence_procedures,
            .uses_explicit_recovery = grammar.uses_explicit_recovery,
            .has_recovery_annotations = grammar.has_recovery_annotations,
            .uses_verbatim = grammar.uses_verbatim,
            .end_symbol = grammar.eof,
        };
    }

    fn emit(self: *Generator, writer: *std.Io.Writer) !void {
        try writer.writeAll(
            \\const builtin = @import("builtin");
            \\const std = @import("std");
            \\const root = @import("galley");
            \\const procedures = root.procedures;
            \\const error_messages = root.error_messages;
            \\const data_structures = root.data_structures;
            \\const string_utilities = root.string_utilities;
            \\
        );
        try emitter_common.emitParserMetadata(
            writer,
            "ll",
            self.has_recovery_annotations,
            self.longestTerminalLength(),
            self.uses_verbatim,
            true,
        );

        try emitter_common.emitGrammarTables(writer, self.symbols.items, self.variables.items, self.rules.items, self.end_symbol);
        try writer.writeAll(
            \\fn symbolReturnsNodeSuppressed(comptime symbol_index: usize, comptime suppress_ast: bool) bool {
            \\    return !suppress_ast and symbolReturnsNode(symbol_index);
            \\}
            \\fn nodeReturnType(comptime symbol_index: usize, comptime suppress_ast: bool) type {
            \\    if (symbolReturnsNodeSuppressed(symbol_index, suppress_ast)) return root.data_structures.VariableResult;
            \\    return void;
            \\}
            \\
            \\fn ruleHasNodeChildren(comptime rule_index: usize, comptime suppress_ast: bool) bool {
            \\    inline for (rules[rule_index].right_hand_side) |child_symbol| {
            \\        if (symbolReturnsNodeSuppressed(child_symbol, suppress_ast)) return true;
            \\    }
            \\    return false;
            \\}
            \\
        );
        try writer.writeAll(
            \\const RootReduction = struct {
            \\    ast_root: ?data_structures.Node.Pointer = null,
            \\    semantic_root: if (are_procedures_enabled) ?data_structures.Payload else void = if (are_procedures_enabled) null else {},
            \\};
            \\
        );
        // Recovery support for every style is emitted unconditionally: the
        // active style is selected at comptime per configuration, and unused
        // support folds away under lazy analysis.
        try self.emitRecoverySupport(writer);
        if (self.uses_explicit_recovery) {
            try self.emitExplicitRecoverySupport(writer);
        }
        try emitter_common.emitProcedureSupport(self.allocator, writer, self.rules.items, self.symbols.items, &self.plan.hooks, self.variables.items);
        try emitter_common.emitReservedLeftoverCheck(self.allocator, writer, self.symbols.items);
        try self.measureTerminalInlineCosts();
        try self.emitParserFunctions(writer);
        try self.emitAstSuppressedParsers(writer);
        try self.emitSyntaxErrorHandlers(writer);
        if (self.uses_explicit_recovery) try self.emitExplicitSyntaxDiagnosticFlusher(writer);
        try writer.writeAll(
            \\pub fn parseWithResult(context: *data_structures.Context) !root.ParseResult {
            \\    var root_reduction: RootReduction = .{};
            \\    _ = parse__AugmentedStart(context
        );
        if (self.has_occurrence_procedures) try writer.writeAll(", null");
        if (self.uses_explicit_recovery) try writer.writeAll(", null");
        try writer.writeAll(", &root_reduction");
        if (self.uses_explicit_recovery) {
            try writer.writeAll(
                \\) catch |err| switch (err) {
                \\        root.ParseError.SyntaxError, error.ExplicitSyntaxRecovery => {
                \\            try llFlushSyntaxDiagnostic(context);
                \\            return root.ParseError.SyntaxError;
                \\        },
                \\        else => return err,
                \\    };
            );
        } else {
            try writer.writeAll(
                \\) catch |err| switch (err) {
                \\        root.ParseError.SyntaxError => return root.ParseError.SyntaxError,
                \\        else => return err,
                \\    };
            );
        }
        try writer.writeAll(
            \\
            \\    if (context.verbosityLevel() > 0 and !context.hasSyntaxErrors()) {
            \\        std.log.info("The input file was parsed successfully!", .{});
            \\    }
            \\
        );
        try writer.writeAll(
            \\    return .{
            \\        .parsed_bytes = context.currentTokenSourceOffset() -| 1,
            \\        .line = context.line,
            \\        .column = context.column,
            \\        .ast_root = root_reduction.ast_root,
            \\        .semantic_root = root_reduction.semantic_root,
            \\    };
            \\}
            \\
            \\pub fn parse(context: *data_structures.Context) !void {
            \\    _ = try parseWithResult(context);
            \\}
            \\
        );
        // Cold fail-fast support at the very end so it does not sit between
        // the hot parser functions and displace them in the final binary.
        try self.emitFailFastSyntaxErrorSupport(writer);
    }

    fn emitRecoverySupport(self: *Generator, writer: *std.Io.Writer) !void {
        _ = self;
        try emitter_common.emitRecoveryOffsetFunction(writer, "llRecoveryOffset");
    }

    fn emitExplicitRecoverySupport(self: *Generator, writer: *std.Io.Writer) !void {
        try emitter_common.emitExplicitRecoveryScopeStruct(writer);
        try writer.writeByte('\n');
        try writer.writeAll(
            \\fn llTryExplicitScope(context: *data_structures.Context, scope: *const ExplicitRecoveryScope) !bool {
            \\    if (!try context.tryExplicitRecovery(scope.id, scope.target, scope.points)) return false;
            \\    try llFlushSyntaxDiagnostic(context);
            \\    return true;
            \\}
            \\
        );

        for (self.variables.items) |variable| {
            if (!self.hasParseEntries(variable)) continue;
            try writer.print("fn llTryRecoverySelection_{d}(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {{\n", .{variable});
            try writer.writeAll("    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;\n");
            if (self.symbols.items[variable].annotations.recovery_points.items.len != 0) {
                try writer.writeAll("    if (try llTryExplicitScope(context, ");
                try emitter_common.emitLhsRecoveryScope(writer, &self.plan.recovery.scopes, self.symbols.items, variable);
                try writer.writeAll(")) return true;\n");
            }
            try writer.writeAll("    return false;\n}\n\n");
        }

        for (self.rules.items, 0..) |rule, rule_index| {
            if (self.symbols.items[rule.header].kind != .variable or !self.hasParseEntries(rule.header)) continue;
            try writer.print("fn llTryRecoveryRule_{d}(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {{\n", .{rule_index});
            try writer.writeAll("    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;\n");
            if (rule.annotations.recovery_points.items.len != 0) {
                try writer.writeAll("    if (try llTryExplicitScope(context, ");
                try emitter_common.emitProductionRecoveryScope(writer, &self.plan.recovery.scopes, self.symbols.items, rule, rule_index);
                try writer.writeAll(")) return true;\n");
            }
            if (self.symbols.items[rule.header].annotations.recovery_points.items.len != 0) {
                try writer.writeAll("    if (try llTryExplicitScope(context, ");
                try emitter_common.emitLhsRecoveryScope(writer, &self.plan.recovery.scopes, self.symbols.items, rule.header);
                try writer.writeAll(")) return true;\n");
            }
            try writer.writeAll("    return false;\n}\n\n");
        }
    }

    fn emitExplicitSyntaxDiagnosticFlusher(self: *Generator, writer: *std.Io.Writer) !void {
        const renderer_names = try self.allocator.alloc([]const u8, self.plan.syntax_error_handlers.items.len);
        defer self.allocator.free(renderer_names);
        for (self.plan.syntax_error_handlers.items, 0..) |spec, site_index| {
            renderer_names[site_index] = try std.fmt.allocPrint(self.allocator, "{s}_message", .{spec.name});
        }
        defer for (renderer_names) |name| self.allocator.free(name);
        try emitter_common.emitExplicitDiagnosticFlusher(writer, "ll", renderer_names);
    }

    fn emitOccurrenceRecoveryScope(self: *Generator, writer: *std.Io.Writer, rule: Rule, child_index: usize) !void {
        const rule_index = self.ruleIndex(rule);
        const variable = rule.rhs.items[child_index];
        const target_id = (self.plan.recovery.scopes.findOccurrence(rule_index, child_index) orelse unreachable).id;
        try writer.print("&ExplicitRecoveryScope{{ .id = {d}, .target = .{{ .occurrence = .{{ .parent_variable = ", .{target_id});
        try emitStringLiteral(writer, self.symbols.items[rule.header].id);
        try writer.print(", .rhs_index = {s}, .symbol_index = {d}, .variable = ", .{ rule.rhs_index, child_index });
        try emitStringLiteral(writer, self.symbols.items[variable].id);
        try writer.writeAll(" } }, .points = ");
        try emitter_common.emitRecoveryPoints(writer, rule.rhs_annotations.items[child_index].recovery_points.items);
        try writer.writeAll(" }");
    }

    fn emitParserFunctions(self: *Generator, writer: *std.Io.Writer) !void {
        for (self.plan.emitted_symbols) |symbol_index| {
            const symbol = self.symbols.items[symbol_index];
            // Transparent factoring helpers never emit parsers: their
            // alternatives expand inline at the single parent call site
            // (see emitChildParseLine), so there is no callee to generate.
            if (symbol.synthetic_transparent) continue;
            if (symbol.kind == .variable) {
                // A variable flattened at every use is only ever parsed
                // into its caller's node.
                if (!symbol.annotations.flatten) try self.emitVariableParser(writer, symbol_index, false);
                if (self.hasFlattenedOccurrence(symbol_index)) try self.emitFlattenedParser(writer, symbol_index);
            } else {
                try self.emitTerminalParser(writer, symbol_index, false);
            }
            try writer.writeByte('\n');
        }
    }

    fn emitAstSuppressedParsers(self: *Generator, writer: *std.Io.Writer) !void {
        for (self.plan.ast_suppressed_order) |symbol_index| {
            try writer.writeByte('\n');
            const symbol = self.symbols.items[symbol_index];
            // Same as above: transparent helpers expand inline in both
            // variants, so neither variant emits a function.
            if (symbol.synthetic_transparent) continue;
            if (symbol.kind == .variable) {
                if (!self.hasParseEntries(symbol_index)) continue;
                try self.emitVariableParser(writer, symbol_index, true);
            } else {
                try self.emitTerminalParser(writer, symbol_index, true);
            }
        }
        if (self.plan.ast_suppressed_order.len > 0) try writer.writeByte('\n');
    }

    /// Called by `emitModeGatedBody` before it renders each function body.
    /// Decision labels only need to be unique within one function, and
    /// numbering them per function keeps per-configuration bodies textually
    /// identical so they still deduplicate.
    pub fn beginFunctionBody(self: *Generator) void {
        self.decision_count = 0;
        self.inline_call_cost = 0;
    }

    /// Comptime branch budget each `(` in a generated body may spend on the
    /// inline and comptime work behind it (inline runtime helpers, rule table
    /// lookups), which the generator cannot see into. Counting every `(`
    /// overcounts calls about threefold (`if (`, `switch (`, builtins), which
    /// leaves each real call well above the deepest inline chain today
    /// (`head` through the lexer, about five calls).
    const branch_quota_per_call = 8;

    /// The `@setEvalBranchQuota` a rendered function body needs. Zig charges
    /// every inline call, including those inside inlined bodies, against the
    /// analyzing function's budget (1000 by default). Every call site in the
    /// text gets `branch_quota_per_call`, and each call to an inline terminal
    /// parser also carries that parser's whole cost.
    pub fn functionBodyBranchQuota(self: *Generator, text: []const u8) usize {
        const quota = branch_quota_per_call * std.mem.count(u8, text, "(") + self.inline_call_cost;
        self.largest_body_branch_quota = @max(self.largest_body_branch_quota, quota);
        return quota;
    }

    /// Terminal parsers are `inline fn`, so every call spends the callee's
    /// budget in the caller. Measure each once, before any caller is emitted,
    /// as the largest quota among its configuration variants' bodies: a
    /// caller's variant only calls the matching variant of the terminal.
    fn measureTerminalInlineCosts(self: *Generator) EmitError!void {
        const costs = try self.allocator.alloc(usize, self.symbols.items.len);
        @memset(costs, 0);
        self.terminal_inline_costs = costs;
        for ([_][]const usize{ self.plan.emitted_symbols, self.plan.ast_suppressed_order }, [_]bool{ false, true }) |symbols, skip_ast_construction| {
            for (symbols) |symbol_index| {
                if (self.symbols.items[symbol_index].kind == .variable) continue;
                var buffer = std.Io.Writer.Allocating.init(self.allocator);
                defer buffer.deinit();
                self.largest_body_branch_quota = 0;
                self.emitTerminalParser(&buffer.writer, symbol_index, skip_ast_construction) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => return error.WriteFailed,
                };
                costs[symbol_index] = @max(costs[symbol_index], self.largest_body_branch_quota);
            }
        }
    }

    fn parserName(self: *Generator, symbol_index: usize) ![]const u8 {
        return self.plan.symbol_names.stems[symbol_index];
    }

    fn emitVariableParser(self: *Generator, writer: *std.Io.Writer, variable: usize, skip_ast_construction: bool) !void {
        try self.emitSelfRepeatingParsers(writer, variable, skip_ast_construction);
        const name = try self.parserName(variable);
        try writer.print("// {s}Parser for Symbol \"", .{if (skip_ast_construction) "AST-Suppressed " else ""});
        try std.zig.stringEscape(self.symbols.items[variable].id, writer);
        try writer.print("\" with index {d}\n", .{variable});
        // A tail loop that builds nodes stays out of line, as the recursive
        // parser it replaces did: inlined into its callers it bloats them
        // (JSON with AST: -10%), while loops without nodes gain from
        // inlining. One generated file serves every build, so a wrapper picks
        // when the build compiles.
        const suffix = if (skip_ast_construction) "_" else "";
        const loops = try self.tailLoopEnabled(variable, skip_ast_construction);
        if (loops) {
            try writer.print("inline fn parse_{s}{s}(context: *data_structures.Context", .{ name, suffix });
            if (self.has_occurrence_procedures) try writer.writeAll(", occurrence_procedures: ?*const ProcedureSequenceNode");
            if (self.uses_explicit_recovery) try writer.writeAll(", occurrence_recovery: ?*const ExplicitRecoveryScope");
            try writer.print(") anyerror!nodeReturnType({d}, {s}) {{\n", .{ variable, if (skip_ast_construction) "true" else "false" });
            try writer.print("    return @call(if (symbolReturnsNodeSuppressed({d}, {s})) .never_inline else .auto, parse_{s}{s}_loop, .{{context", .{ variable, if (skip_ast_construction) "true" else "false", name, suffix });
            if (self.has_occurrence_procedures) try writer.writeAll(", occurrence_procedures");
            if (self.uses_explicit_recovery) try writer.writeAll(", occurrence_recovery");
            try writer.writeAll("});\n}\n");
        }
        // A loop's levels each have their own occurrence; the caller's is
        // the outermost level's.
        const parameter_prefix = if (loops) "outer_" else "";
        try writer.print("fn parse_{s}{s}{s}(context: *data_structures.Context", .{ name, suffix, if (loops) "_loop" else "" });
        if (self.has_occurrence_procedures) {
            try writer.print(", {s}occurrence_procedures: ?*const ProcedureSequenceNode", .{parameter_prefix});
        }
        if (self.uses_explicit_recovery) {
            try writer.print(", {s}occurrence_recovery: ?*const ExplicitRecoveryScope", .{parameter_prefix});
        }
        if (variable == self.plan.augmented_start) {
            try writer.writeAll(", root_reduction: *RootReduction");
        }
        try writer.print(") anyerror!nodeReturnType({d}, {s}) {{\n", .{ variable, if (skip_ast_construction) "true" else "false" });
        // A loop body names its own `outer_` parameters.
        try emitter_common.emitModeGatedBody(Generator, self, writer, VariableParserBody, .{ .variable = variable, .skip_ast_construction = skip_ast_construction }, self.has_occurrence_procedures and !loops, renderVariableParserBody);
        try writer.writeAll("}\n");
    }

    const VariableParserBody = struct {
        variable: usize,
        skip_ast_construction: bool,
    };

    fn renderVariableParserBody(self: *Generator, writer: *std.Io.Writer, params: VariableParserBody) !void {
        const variable = params.variable;
        const skip_ast_construction = params.skip_ast_construction;
        const returns_node = self.symbolReturnsNode(variable, skip_ast_construction);
        if (variable != self.plan.augmented_start and !returns_node) {
            if (try self.byteRunBytes(variable)) |bytes| return self.emitByteRunLoop(writer, bytes);
        }
        if (variable == self.plan.augmented_start) {
            try writer.writeAll("    root_reduction.* = .{};\n");
        }
        if (try self.tailLoopEnabled(variable, skip_ast_construction)) return self.renderTailLoopBody(writer, variable, skip_ast_construction, returns_node);
        if (returns_node) {
            const variable_index = self.variableIndex(variable);
            if (self.options.with_ast) {
                const is_var = self.options.with_procedures and !skip_ast_construction;
                try writer.print("    {s} node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), {d});\n\n", .{ if (is_var) "var" else "const", variable_index });
            } else {
                try writer.print("    var node = data_structures.Node{{ .text_start = context.currentTokenSourceOffset(), .variable = {d}, .payload = .{{}} }};\n\n", .{variable_index});
            }
        }
        if (variable != self.plan.augmented_start) {
            try writer.writeAll("    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable(");
            try emitStringLiteral(writer, self.symbols.items[variable].id);
            try writer.writeAll(") else false;\n    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();\n");
        }

        try self.emitVariableDispatch(writer, variable, "    ", skip_ast_construction);
        if (returns_node) {
            try writer.writeAll(if (self.options.with_ast) "    return node_address;\n" else "    return node;\n");
        }
    }

    /// Selects and parses one of `variable`'s rules, or reports a syntax
    /// error when it has none to select.
    fn emitVariableDispatch(self: *Generator, writer: *std.Io.Writer, variable: usize, indent: []const u8, skip_ast_construction: bool) EmitError!void {
        const decision = self.plan.parserDecision(variable, skip_ast_construction);
        if (decision.tree.entries.len == 0) {
            const spec = self.plan.syntax_error_handlers.items[decision.tree.diagnostic.?];
            try emitter_common.emitSkipLeftoverBlockEndNewlines(writer, indent);
            try writer.print("{s}switch (context.head(u8, 0)) {{\n", .{indent});
            try writer.print("{s}    else => {{\n", .{indent});
            try writer.print("{s}        @branchHint(.unlikely);\n", .{indent});
            try self.emitSyntaxErrorCall(writer, spec, try indented(self.allocator, indent, 8));
            try writer.print("{s}    }},\n", .{indent});
            try writer.print("{s}}}\n", .{indent});
        } else {
            try self.emitRuleDispatch(writer, variable, decision.tree, indent, skip_ast_construction, VariableRuleBody{
                .generator = self,
                .variable = variable,
                .skip_ast_construction = skip_ast_construction,
            }, VariableRuleBody.emit);
        }
    }

    /// The parser of a flattened occurrence of `variable`: it builds no node
    /// and runs no hook of the variable's, and appends the children to the
    /// caller's node. Where the variable continues into a flattened
    /// self-reference it loops, so the levels cost neither nodes nor stack.
    /// It hands the caller's node back, flagged when recovery cut it short.
    /// Without AST construction it hands back a carrier instead, whose
    /// temporary children, kept in the parse arena, the caller takes on.
    fn emitFlattenedParser(self: *Generator, writer: *std.Io.Writer, variable: usize) !void {
        const name = try self.parserName(variable);
        try writer.writeAll("// Flattened Parser for Symbol \"");
        try std.zig.stringEscape(self.symbols.items[variable].id, writer);
        try writer.print("\" with index {d}\n", .{variable});
        try writer.print("fn parse_{s}_flattened(context: *data_structures.Context, node_address: data_structures.Node.Pointer) anyerror!nodeReturnType({d}, false) {{\n", .{ name, variable });
        try emitter_common.emitModeGatedBody(Generator, self, writer, FlattenedParserBody, .{ .variable = variable }, false, renderFlattenedParserBody);
        try writer.writeAll("}\n\n");
    }

    const FlattenedParserBody = struct {
        variable: usize,
    };

    fn renderFlattenedParserBody(self: *Generator, writer: *std.Io.Writer, params: FlattenedParserBody) !void {
        const variable = params.variable;
        const loops = self.reachesTail(variable, .flattened);
        self.flattened_variable = variable;
        defer self.flattened_variable = null;
        if (loops) self.tail_loop = .{ .variable = variable, .skip_ast_construction = false, .kind = .flattened, .keeps_frames = false };
        defer self.tail_loop = null;
        self.occurrence_uses = .{};

        var dispatch = std.Io.Writer.Allocating.init(self.allocator);
        try self.emitVariableDispatch(&dispatch.writer, variable, if (loops) "        " else "    ", false);

        try writer.writeAll("    _ = &node_address;\n");
        const carries_children = !self.options.with_ast and self.symbolReturnsNode(variable, false);
        if (carries_children) try writer.writeAll("    var node = data_structures.Node{ .payload = .{} };\n    _ = &node;\n");
        // The occurrence is flattened, so it carries no recovery points,
        // and neither does the variable.
        if (self.occurrence_uses.recovery) try writer.writeAll("    const occurrence_recovery: ?*const ExplicitRecoveryScope = null;\n");
        try writer.writeAll("    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable(");
        try emitStringLiteral(writer, self.symbols.items[variable].id);
        try writer.writeAll(") else false;\n    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();\n");
        if (loops) {
            try writer.writeAll("    descend: while (true) {\n");
            try writer.writeAll(dispatch.written());
            try writer.writeAll("        break;\n    }\n");
        } else {
            try writer.writeAll(dispatch.written());
        }
        if (self.symbolReturnsNode(variable, false)) {
            try writer.print("    return {s};\n", .{if (self.options.with_ast) "node_address" else "node"});
        }
    }

    /// Whether the body being rendered keeps its children on a carrier: a
    /// flattened parser without AST construction.
    fn keepsChildren(self: *Generator) bool {
        return self.flattened_variable != null and !self.options.with_ast;
    }

    const TailReach = enum { never, sometimes, always };

    /// Which tail self-references a parser variant loops on. A variant
    /// without nodes loops on all of them. A node-building variant loops on
    /// those that are not flattened and calls the flattened variant for the
    /// others, which loops on exactly those, appending every level to the
    /// one node.
    const LoopKind = enum { suppressed, nodes, flattened };

    fn loopKind(skip_ast_construction: bool) LoopKind {
        return if (skip_ast_construction) .suppressed else .nodes;
    }

    fn continuesLoop(self: *Generator, kind: LoopKind, rule: Rule, position: usize) bool {
        return switch (kind) {
            .suppressed => true,
            .nodes => !common.isFlattenedOccurrence(self.symbols.items, rule, position),
            .flattened => common.isFlattenedOccurrence(self.symbols.items, rule, position),
        };
    }

    /// Whether `rule`'s last position reaches `variable` again, directly or
    /// through the last position of inlined helpers, as a self-reference the
    /// `kind` of loop continues at: on no path, on some, or on every path.
    fn tailReach(self: *Generator, variable: usize, rule: Rule, kind: LoopKind) TailReach {
        if (rule.rhs.items.len == 0) return .never;
        const last_index = rule.rhs.items.len - 1;
        const last = rule.rhs.items[last_index];
        if (last == variable) return if (planning.isTailLoopPosition(rule, last_index) and self.continuesLoop(kind, rule, last_index)) .always else .never;
        const symbol = self.symbols.items[last];
        if (symbol.kind != .variable or !symbol.synthetic_transparent) return .never;
        var any = false;
        var all = true;
        for (self.rules.items) |helper_rule| {
            if (helper_rule.header != last) continue;
            switch (self.tailReach(variable, helper_rule, kind)) {
                .never => all = false,
                .sometimes => {
                    any = true;
                    all = false;
                },
                .always => any = true,
            }
        }
        if (!any) return .never;
        return if (all) .always else .sometimes;
    }

    /// Whether the parser of `variable`, in the variant `skip_ast_construction`
    /// selects, is a tail loop: some rule reaches the variable again from its
    /// last position. A variant whose self-references call the other variant
    /// (the variable is not AST-enabled) leaves the looping to that one, and a
    /// byte run is a loop of its own.
    fn tailLoopEnabled(self: *Generator, variable: usize, skip_ast_construction: bool) EmitError!bool {
        if (variable == self.plan.augmented_start) return false;
        if (!skip_ast_construction and !self.symbols.items[variable].ast_enabled) return false;
        if (try self.byteRunBytes(variable) != null) return false;
        return self.reachesTail(variable, loopKind(skip_ast_construction));
    }

    fn reachesTail(self: *Generator, variable: usize, kind: LoopKind) bool {
        for (self.rules.items) |rule| {
            if (rule.header != variable) continue;
            if (self.tailReach(variable, rule, kind) != .never) return true;
        }
        return false;
    }

    /// Whether `variable` needs a flattened parser: some occurrence of it is
    /// flattened, or every one is.
    fn hasFlattenedOccurrence(self: *Generator, variable: usize) bool {
        if (self.symbols.items[variable].annotations.flatten) return true;
        for (self.rules.items) |rule| {
            for (rule.rhs.items, 0..) |symbol_index, position| {
                if (symbol_index == variable and common.isFlattenedOccurrence(self.symbols.items, rule, position)) return true;
            }
        }
        return false;
    }

    /// An occurrence where a variable's rule reaches the variable again from
    /// its last symbol; the variable's parser loops there instead of calling
    /// itself.
    const TailSite = struct {
        /// The variable's rule whose expansion holds the occurrence.
        rule_index: usize,
        /// The rule holding the occurrence: that rule, or an inlined helper's.
        occurrence_rule: Rule,
        position: usize,
        /// The occurrence's child slot, where a node built by value lands.
        slot: usize,
    };

    const TailLoop = struct {
        variable: usize,
        skip_ast_construction: bool,
        kind: LoopKind,
        /// Each open level keeps a frame, to reduce its node around the inner
        /// one or to retry explicit recovery outward.
        keeps_frames: bool,
        rule_index: usize = 0,
        sites: std.ArrayList(TailSite) = .empty,
    };

    /// The tail loop around the body being rendered when it keeps frames. A
    /// level inside it does not return: its result, or its failure, ends
    /// the descent, and the open levels then finish around it as their
    /// recursive calls did.
    fn framedTailLoop(self: *Generator) ?*TailLoop {
        if (self.tail_loop) |*loop| {
            if (loop.keeps_frames) return loop;
        }
        return null;
    }

    /// Hands `expression` (or nothing) back as the current level's result.
    fn emitLevelReturn(self: *Generator, writer: *std.Io.Writer, indent: []const u8, expression: ?[]const u8) !void {
        const loop = self.framedTailLoop() orelse {
            if (expression) |value| {
                try writer.print("{s}return {s};\n", .{ indent, value });
            } else {
                try writer.print("{s}return;\n", .{indent});
            }
            return;
        };
        if (expression) |value| {
            if (self.symbolReturnsNode(loop.variable, loop.skip_ast_construction)) {
                try writer.print("{s}{s} = {s};\n", .{ indent, if (self.options.with_ast) "node_address" else "tail_result", value });
            } else {
                try writer.print("{s}{s};\n", .{ indent, value });
            }
        }
        try writer.print("{s}break :descend;\n", .{indent});
    }

    /// Fails the current level after its explicit recovery found nothing, so
    /// the level around it tries its own.
    fn emitLevelFailure(self: *Generator, writer: *std.Io.Writer, indent: []const u8) !void {
        if (self.framedTailLoop() == null) {
            try writer.print("{s}return err;\n", .{indent});
            return;
        }
        try writer.print("{s}tail_failure = err;\n{s}break :descend;\n", .{ indent, indent });
    }

    /// Writes `call` so that, inside a framed loop with explicit recovery, a
    /// recovery failure fails the current level instead of the whole parser.
    fn emitHandledCall(self: *Generator, writer: *std.Io.Writer, indent: []const u8, call: []const u8) !void {
        if (self.framedTailLoop() == null or !self.uses_explicit_recovery) {
            try writer.print("try {s}", .{call});
            return;
        }
        try writer.print("{s} catch |err| switch (err) {{\n", .{call});
        try writer.print("{s}    error.ExplicitSyntaxRecovery => {{\n", .{indent});
        try self.emitLevelFailure(writer, try indented(self.allocator, indent, 8));
        try writer.print("{s}    }},\n{s}    else => return err,\n{s}}}", .{ indent, indent, indent });
    }

    /// Starts the next level at `site`: the open level keeps a frame, and
    /// the loop parses the variable again.
    fn emitTailDescent(self: *Generator, writer: *std.Io.Writer, indent: []const u8, site: usize) !void {
        const loop = self.tail_loop.?;
        if (loop.keeps_frames) {
            if (self.options.with_ast) {
                const node = if (self.symbolReturnsNode(loop.variable, loop.skip_ast_construction)) "node_address" else "data_structures.Node.invalid_pointer";
                try writer.print("{s}try context.tail_frames.push(.{{ .node = {s}, .site = {d} }});\n", .{ indent, node, site });
            } else if (self.symbolReturnsNode(loop.variable, loop.skip_ast_construction)) {
                try writer.print("{s}try tail_frames.append(context.runtime().arena_allocator, .{{ .level = level, .site = {d} }});\n", .{ indent, site });
            } else {
                try writer.print("{s}try tail_frames.append(context.runtime().arena_allocator, .{{ .site = {d} }});\n", .{ indent, site });
            }
        } else if (self.has_occurrence_procedures and loop.kind != .flattened) {
            try writer.print("{s}tail_depth += 1;\n", .{indent});
        }
        try writer.print("{s}continue :descend;\n", .{indent});
    }

    /// How generated loop code reads its frames: the session's stack above
    /// this call's base with AST construction, a local list otherwise.
    const TailFrameAccess = struct {
        count: []const u8,
        top_site: []const u8,
        pop: []const u8,
    };

    fn tailFrameAccess(self: *Generator) TailFrameAccess {
        if (self.options.with_ast) return .{
            .count = "context.tail_frames.frames.items.len - tail_frame_base",
            .top_site = "context.tail_frames.frames.items[context.tail_frames.frames.items.len - 1].site",
            .pop = "context.tail_frames.frames.pop().?",
        };
        return .{
            .count = "tail_frames.items.len",
            .top_site = "tail_frames.items[tail_frames.items.len - 1].site",
            .pop = "tail_frames.pop().?",
        };
    }

    const OccurrenceUses = struct {
        procedures: bool = false,
        recovery: bool = false,

        fn merge(self: OccurrenceUses, other: OccurrenceUses) OccurrenceUses {
            return .{ .procedures = self.procedures or other.procedures, .recovery = self.recovery or other.recovery };
        }
    };

    /// Names, in emitted code, the occurrence procedures of the node the body
    /// builds. Every such name goes through here, so the use is recorded.
    fn occurrenceProceduresName(self: *Generator) []const u8 {
        self.occurrence_uses.procedures = true;
        return "occurrence_procedures";
    }

    /// Names, in emitted code, the recovery scope of the occurrence being
    /// parsed. Every such name goes through here, so the use is recorded.
    fn occurrenceRecoveryName(self: *Generator) []const u8 {
        self.occurrence_uses.recovery = true;
        return "occurrence_recovery";
    }

    /// Declares the current level's occurrence procedures and recovery scope,
    /// as far as `uses` names them: the caller's at the outermost level, and
    /// at a deeper one those of the site the level above continued at.
    fn emitLevelOccurrences(self: *Generator, writer: *std.Io.Writer, indent: []const u8, uses: OccurrenceUses, loop: TailLoop) !void {
        const access = self.tailFrameAccess();
        const returns_node = self.symbolReturnsNode(loop.variable, loop.skip_ast_construction);
        if (uses.procedures) {
            if (!loop.keeps_frames) {
                // Without frames the variable builds no node, so deeper levels
                // were called without occurrence procedures.
                try writer.print("{s}const occurrence_procedures: ?*const ProcedureSequenceNode = if (tail_depth == 0) outer_occurrence_procedures else null;\n", .{indent});
            } else {
                try writer.print("{s}const occurrence_procedures: ?*const ProcedureSequenceNode = if ({s} == 0) outer_occurrence_procedures else switch ({s}) {{\n", .{ indent, access.count, access.top_site });
                for (loop.sites.items, 0..) |site, site_index| {
                    try writer.print("{s}    {d} => ", .{ indent, site_index });
                    if (returns_node) {
                        try emitter_common.emitProcedureSequenceExpression(writer, &self.plan.hooks, site.occurrence_rule.rhs_annotations.items[site.position].procedures.items);
                    } else {
                        try writer.writeAll("null");
                    }
                    try writer.writeAll(",\n");
                }
                try writer.print("{s}    else => unreachable,\n{s}}};\n", .{ indent, indent });
            }
        }
        if (uses.recovery) {
            try writer.print("{s}const occurrence_recovery: ?*const ExplicitRecoveryScope = if ({s} == 0) outer_occurrence_recovery else switch ({s}) {{\n", .{ indent, access.count, access.top_site });
            for (loop.sites.items, 0..) |site, site_index| {
                try writer.print("{s}    {d} => ", .{ indent, site_index });
                if (site.occurrence_rule.rhs_annotations.items[site.position].recovery_points.items.len != 0) {
                    try self.emitOccurrenceRecoveryScope(writer, site.occurrence_rule, site.position);
                } else {
                    try writer.writeAll("null");
                }
                try writer.writeAll(",\n");
            }
            try writer.print("{s}    else => unreachable,\n{s}}};\n", .{ indent, indent });
        }
    }

    /// Pops the error-message variable of the level a frame count names,
    /// when that level pushed one.
    fn emitLeaveLevel(writer: *std.Io.Writer, indent: []const u8, level: []const u8) !void {
        try writer.print(
            \\{s}if (comptime is_syntax_error_stack_enabled) {{
            \\{s}    if ({s} < syntax_error_depth) {{
            \\{s}        context.popSyntaxErrorVariable();
            \\{s}        syntax_error_depth -= 1;
            \\{s}    }}
            \\{s}}}
            \\
        , .{ indent, indent, level, indent, indent, indent, indent });
    }

    /// The variable's parser as a loop: where a rule reaches the variable
    /// again from its last position, the next level starts instead of a
    /// recursive call, so input depth costs no stack. A level that keeps a
    /// frame finishes after the levels inside it, innermost first, exactly
    /// as its recursive call would have: it takes the inner result as its
    /// last child, reduces, and pops its error-message variable.
    fn renderTailLoopBody(self: *Generator, writer: *std.Io.Writer, variable: usize, skip_ast_construction: bool, returns_node: bool) !void {
        const with_ast = self.options.with_ast;
        const explicit = self.uses_explicit_recovery;
        const keeps_frames = returns_node or explicit;
        const value_nodes = returns_node and !with_ast;
        const variable_index = self.variableIndex(variable);
        const access = self.tailFrameAccess();

        // The dispatch first: it names the sites the frames refer to.
        var dispatch = std.Io.Writer.Allocating.init(self.allocator);
        self.occurrence_uses = .{};
        self.tail_loop = .{ .variable = variable, .skip_ast_construction = skip_ast_construction, .kind = loopKind(skip_ast_construction), .keeps_frames = keeps_frames };
        const decision = self.plan.parserDecision(variable, skip_ast_construction);
        self.emitRuleDispatch(&dispatch.writer, variable, decision.tree, "        ", skip_ast_construction, VariableRuleBody{
            .generator = self,
            .variable = variable,
            .skip_ast_construction = skip_ast_construction,
        }, VariableRuleBody.emit) catch |err| {
            self.tail_loop = null;
            return err;
        };
        const loop = self.tail_loop.?;
        self.tail_loop = null;
        const dispatch_uses = self.occurrence_uses;
        var all_uses = dispatch_uses;

        // Sites of one rule finish alike unless their child slots differ.
        var unwind = std.Io.Writer.Allocating.init(self.allocator);
        const uw = &unwind.writer;
        if (keeps_frames) {
            try emitLeaveLevel(uw, "    ", access.count);
            if (explicit) {
                try uw.writeAll("    if (tail_failure) |failure| {\n        while (true) {\n");
                try uw.print("            if ({s} == 0) return failure;\n", .{access.count});
                try uw.print("            const tail_frame = {s};\n", .{access.pop});
                var recovery_text = std.Io.Writer.Allocating.init(self.allocator);
                self.occurrence_uses = .{};
                try recovery_text.writer.writeAll("            const recovered = switch (tail_frame.site) {\n");
                for (loop.sites.items, 0..) |site, site_index| {
                    try recovery_text.writer.print("                {d} => try llTryRecoveryRule_{d}(context, {s}),\n", .{ site_index, self.ruleIndex(site.occurrence_rule), self.occurrenceRecoveryName() });
                }
                try recovery_text.writer.writeAll("                else => unreachable,\n            };\n");
                try self.emitLevelOccurrences(uw, "            ", self.occurrence_uses, loop);
                all_uses = all_uses.merge(self.occurrence_uses);
                try uw.writeAll(recovery_text.written());
                try uw.writeAll("            if (recovered) {\n");
                if (returns_node) {
                    if (with_ast) {
                        try uw.writeAll("                node_address = context.keepRecoveredNode(tail_frame.node);\n");
                    } else {
                        try uw.print("                tail_result = {s};\n", .{self.missingNode()});
                    }
                }
                try emitLeaveLevel(uw, "                ", access.count);
                try uw.writeAll("                break;\n            }\n");
                try emitLeaveLevel(uw, "            ", access.count);
                try uw.writeAll("        }\n    }\n");
            }
            try uw.print("    while ({s} > 0) {{\n", .{access.count});
            try uw.print("        const tail_frame = {s};\n", .{access.pop});
            if (returns_node and with_ast) {
                try uw.writeAll(
                    \\        const inner_node_address = node_address;
                    \\        node_address = tail_frame.node;
                    \\        if (inner_node_address != data_structures.Node.invalid_pointer) {
                    \\            context.node_allocator.at(node_address).immediateAppendChildren(node_address, inner_node_address, context.node_allocator);
                    \\        }
                    \\
                );
            } else if (value_nodes) {
                try uw.writeAll("        const inner_result = tail_result;\n        level = tail_frame.level;\n");
            }
            var finish = std.Io.Writer.Allocating.init(self.allocator);
            self.occurrence_uses = .{};
            try finish.writer.writeAll("        switch (tail_frame.site) {\n");
            const handled = try self.allocator.alloc(bool, loop.sites.items.len);
            @memset(handled, false);
            for (loop.sites.items, 0..) |site, site_index| {
                if (handled[site_index]) continue;
                try finish.writer.print("            {d}", .{site_index});
                handled[site_index] = true;
                if (!value_nodes) {
                    for (loop.sites.items[site_index + 1 ..], site_index + 1..) |other, other_index| {
                        if (other.rule_index != site.rule_index) continue;
                        try finish.writer.print(", {d}", .{other_index});
                        handled[other_index] = true;
                    }
                }
                try finish.writer.writeAll(" => {\n");
                if (value_nodes) {
                    try finish.writer.print(
                        \\                if (inner_result) |value| {{
                        \\                    level.children[{d}] = value;
                        \\                    level.node.appendTemporaryChild(&level.children[{d}].?);
                        \\                }}
                        \\
                    , .{ site.slot, site.slot });
                }
                try self.emitRuleFinalize(&finish.writer, site.rule_index, variable, "                ", skip_ast_construction, "level.node");
                try finish.writer.writeAll("            },\n");
            }
            try finish.writer.writeAll("            else => unreachable,\n        }\n");
            try self.emitLevelOccurrences(uw, "        ", self.occurrence_uses, loop);
            all_uses = all_uses.merge(self.occurrence_uses);
            try uw.writeAll(finish.written());
            if (value_nodes) try uw.writeAll("        tail_result = level.node;\n");
            try emitLeaveLevel(uw, "        ", access.count);
            try uw.writeAll("    }\n");
            if (returns_node) try uw.print("    return {s};\n", .{if (with_ast) "node_address" else "tail_result"});
        }

        // Declarations, then the descent. The caller's occurrence is read
        // through the levels; a build that reads none still names it.
        if (self.has_occurrence_procedures and !all_uses.procedures) {
            try writer.writeAll("    _ = &outer_occurrence_procedures;\n");
        }
        if (explicit and !all_uses.recovery) {
            try writer.writeAll("    _ = &outer_occurrence_recovery;\n");
        }
        if (keeps_frames and with_ast) {
            try writer.writeAll(
                \\    const tail_frame_base = context.tail_frames.frames.items.len;
                \\    errdefer context.tail_frames.frames.shrinkRetainingCapacity(tail_frame_base);
                \\
            );
        } else if (value_nodes) {
            var slots: usize = 0;
            for (self.rules.items) |rule| {
                if (rule.header == variable) slots = @max(slots, self.expandedSlotCount(rule));
            }
            try writer.print(
                \\    const TailLevel = struct {{ node: data_structures.Node, children: [{d}]?data_structures.Node }};
                \\    var tail_frames: std.ArrayList(struct {{ level: *TailLevel, site: u32 }}) = .empty;
                \\    var level: *TailLevel = undefined;
                \\    var tail_result: data_structures.VariableResult = undefined;
                \\
            , .{slots});
        } else if (keeps_frames) {
            try writer.writeAll("    var tail_frames: std.ArrayList(struct { site: u32 }) = .empty;\n");
        }
        if (returns_node and with_ast) try writer.writeAll("    var node_address: data_structures.Node.Pointer = undefined;\n");
        if (explicit) try writer.writeAll("    var tail_failure: ?anyerror = null;\n    _ = &tail_failure;\n");
        if (!keeps_frames and self.has_occurrence_procedures) try writer.writeAll("    var tail_depth: usize = 0;\n    _ = &tail_depth;\n");
        try writer.writeAll("    var syntax_error_depth: usize = 0;\n    _ = &syntax_error_depth;\n");
        try writer.print("    {s} if (comptime is_syntax_error_stack_enabled) for (0..syntax_error_depth) |_| context.popSyntaxErrorVariable();\n", .{if (keeps_frames) "errdefer" else "defer"});

        try writer.writeAll("    descend: while (true) {\n");
        try self.emitLevelOccurrences(writer, "        ", dispatch_uses, loop);
        if (returns_node and with_ast) {
            try writer.print("        node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), {d});\n", .{variable_index});
        } else if (value_nodes) {
            try writer.print(
                \\        level = try context.runtime().arena_allocator.create(TailLevel);
                \\        level.* = .{{ .node = .{{ .text_start = context.currentTokenSourceOffset(), .variable = {d}, .payload = .{{}} }}, .children = @splat(null) }};
                \\
            , .{variable_index});
        }
        try writer.writeAll("        if (comptime is_syntax_error_stack_enabled) {\n            if (context.pushSyntaxErrorVariable(");
        try emitStringLiteral(writer, self.symbols.items[variable].id);
        try writer.writeAll(")) syntax_error_depth += 1;\n        }\n");
        try writer.writeAll(dispatch.written());
        if (value_nodes) try writer.writeAll("        tail_result = level.node;\n");
        try writer.writeAll("        break;\n    }\n");
        try writer.writeAll(unwind.written());
    }

    fn emitSelfRepeatingParsers(self: *Generator, writer: *std.Io.Writer, variable: usize, skip_ast_construction: bool) !void {
        // A byte run parses as one loop in its own parser.
        if (try self.byteRunBytes(variable) != null) return;
        for (self.rules.items, 0..) |rule, rule_index| {
            if (rule.header != variable) continue;
            for (rule.rhs.items, 0..) |symbol_index, child_index| {
                if (symbol_index != variable or planning.isTailLoopPosition(rule, child_index)) continue;
                try self.emitSelfRepeatingParser(writer, variable, rule_index, child_index, skip_ast_construction);
                try writer.writeByte('\n');
            }
        }
    }

    fn symbolReturnsNode(self: *Generator, symbol_index: usize, skip_ast_construction: bool) bool {
        if (skip_ast_construction) return false;
        return common.symbolReturnsNode(self.symbols.items[symbol_index], self.options);
    }

    const BodyRecoveryMode = emitter_common.BodyRecoveryMode;

    fn bodyRecoveryMode(self: *const Generator) BodyRecoveryMode {
        if (!self.options.with_error_recovery) return .disabled;
        return if (self.uses_explicit_recovery) .explicit else .automatic;
    }

    fn ruleHasNodeChildren(self: *Generator, rule: Rule, skip_ast_construction: bool) bool {
        for (rule.rhs.items, 0..) |symbol_index, position| {
            const child = self.symbols.items[symbol_index];
            // A flattened child hands back no node of its own.
            if (!skip_ast_construction and common.isFlattenedOccurrence(self.symbols.items, rule, position)) continue;
            // Transparent helpers contribute no node of their own; only
            // their spliced suffix children count.
            if (child.kind == .variable and child.synthetic_transparent) {
                if (self.transparentHasNodeChildren(symbol_index, skip_ast_construction)) return true;
                continue;
            }
            const child_skips_ast_construction = (self.options.with_ast or self.options.with_procedures) and
                (skip_ast_construction or
                    (self.symbols.items[symbol_index].kind == .variable and !self.symbols.items[symbol_index].ast_enabled));
            if (self.symbolReturnsNode(symbol_index, child_skips_ast_construction)) return true;
        }
        return false;
    }

    fn transparentHasNodeChildren(self: *Generator, tail: usize, skip_ast_construction: bool) bool {
        // Terminates: factored suffixes predate their tail, so no tail rule
        // RHS can reference a transparent symbol.
        for (self.rules.items) |rule| {
            if (rule.header != tail) continue;
            if (self.ruleHasNodeChildren(rule, skip_ast_construction)) return true;
        }
        return false;
    }

    /// Number of child slots `rule` occupies in a caller's fixed array once
    /// transparent helpers expand inline. Plain symbols occupy one slot; a
    /// transparent helper occupies its widest alternative (each prong fills
    /// a static prefix of those slots, so siblings after it start past the
    /// maximum). Only matters without AST construction, where children live
    /// in caller-owned stack arrays.
    fn expandedSlotCount(self: *Generator, rule: Rule) usize {
        var total: usize = 0;
        for (rule.rhs.items) |symbol_index| total += self.expandedSymbolSlots(symbol_index);
        return total;
    }

    fn expandedSymbolSlots(self: *Generator, symbol_index: usize) usize {
        const symbol = self.symbols.items[symbol_index];
        if (symbol.kind == .variable and symbol.synthetic_transparent) {
            var widest: usize = 0;
            for (self.rules.items) |rule| {
                if (rule.header != symbol_index) continue;
                widest = @max(widest, self.expandedSlotCount(rule));
            }
            return widest;
        }
        return 1;
    }

    fn expandedChildSlot(self: *Generator, rule: Rule, position: usize) usize {
        var offset: usize = 0;
        for (rule.rhs.items[0..position]) |symbol_index| offset += self.expandedSymbolSlots(symbol_index);
        return offset;
    }

    /// Emits the neutral node result for the CURRENT configuration: typed by
    /// the runtime façade, so no-AST builds get `null` and AST builds get
    /// the pointer sentinel without any combo-dependent typing.
    fn missingNode(self: *Generator) []const u8 {
        _ = self;
        return "data_structures.invalid_variable_node";
    }

    fn hasParseEntries(self: *Generator, variable: usize) bool {
        return self.plan.has_parse_entries[variable];
    }

    fn emitSelfRepeatingParser(self: *Generator, writer: *std.Io.Writer, variable: usize, rule_index: usize, self_index: usize, skip_ast_construction: bool) !void {
        const rule = self.rules.items[rule_index];
        const name = try self.parserName(variable);
        try writer.print("// {s}Self-Repeating Parser for Symbol \"", .{if (skip_ast_construction) "AST-Suppressed " else ""});
        try self.emitSymbolRepr(writer, variable);
        try writer.print("\" at index {d} of its right hand side\n// Right hand side: -> ", .{self_index});
        try emitter_common.emitRuleSymbolsForDebug(writer, self.symbols.items, rule);
        try writer.print("\nfn parse_{s}_{s}_{d}{s}(context: *data_structures.Context", .{
            name,
            rule.rhs_index,
            self_index,
            if (skip_ast_construction) "_" else "",
        });
        if (self.has_occurrence_procedures) {
            try writer.writeAll(", occurrence_procedures: ?*const ProcedureSequenceNode");
        }
        if (self.uses_explicit_recovery) {
            try writer.writeAll(", occurrence_recovery: ?*const ExplicitRecoveryScope");
        }
        try writer.print(") anyerror!nodeReturnType({d}, {s}) {{\n", .{ variable, if (skip_ast_construction) "true" else "false" });
        try emitter_common.emitModeGatedBody(Generator, self, writer, SelfRepeatingParserBody, .{
            .variable = variable,
            .rule_index = rule_index,
            .self_index = self_index,
            .skip_ast_construction = skip_ast_construction,
        }, self.has_occurrence_procedures, renderSelfRepeatingParserBody);
        try writer.writeAll("}\n");
    }

    const SelfRepeatingParserBody = struct {
        variable: usize,
        rule_index: usize,
        self_index: usize,
        skip_ast_construction: bool,
    };

    fn renderSelfRepeatingParserBody(self: *Generator, writer: *std.Io.Writer, params: SelfRepeatingParserBody) !void {
        const variable = params.variable;
        const rule_index = params.rule_index;
        const self_index = params.self_index;
        const skip_ast_construction = params.skip_ast_construction;
        const rule = self.rules.items[rule_index];
        const name = try self.parserName(variable);
        const returns_node = self.symbolReturnsNode(variable, skip_ast_construction);

        if (returns_node and !self.options.with_ast) {
            try writer.print(
                \\    const SemanticReductionFrame = struct {{
                \\        node: data_structures.Node,
                \\        children: [{d}]?data_structures.Node,
                \\    }};
                \\    const semantic_allocator = context.runtime().arena_allocator;
                \\    var frames: std.ArrayList(*SemanticReductionFrame) = .empty;
                \\    defer frames.deinit(semantic_allocator);
                \\
            , .{self.expandedSlotCount(rule)});
            if (self.has_occurrence_procedures) {
                try writer.writeAll("    const recursive_occurrence_procedures = ");
                try emitter_common.emitProcedureSequenceExpression(writer, &self.plan.hooks, rule.rhs_annotations.items[self_index].procedures.items);
                try writer.writeAll(";\n");
            }

            try self.emitSelfRepeatingLoop(writer, self.plan.selfRepeatingDecision(variable, rule_index, self_index, skip_ast_construction).tree, .{
                .rule = rule,
                .variable = variable,
                .self_index = self_index,
                .skip_ast_construction = skip_ast_construction,
                .returns_node = returns_node,
                .frames_mode = true,
            });

            const explicit_recovery = self.uses_explicit_recovery;
            try writer.print("    var reduced_node = {s}parse_{s}(context", .{ if (explicit_recovery) "" else "try ", name });
            if (self.has_occurrence_procedures) {
                try writer.writeAll(", if (frames.items.len == 0) occurrence_procedures else recursive_occurrence_procedures");
            }
            if (self.uses_explicit_recovery) try writer.writeAll(", occurrence_recovery");
            if (explicit_recovery) {
                try self.emitExplicitRuleCatch(writer, rule, variable, skip_ast_construction, "", null);
            } else {
                try writer.writeByte(')');
            }
            try writer.writeAll(";\n    var frame_index = frames.items.len;\n    while (frame_index > 0) {\n        frame_index -= 1;\n        const frame = frames.items[frame_index];\n        if (reduced_node) |value| {\n");
            try writer.print("            frame.children[{d}] = value;\n", .{self_index});
            try writer.print("            frame.node.appendTemporaryChild(&frame.children[{d}].?);\n", .{self_index});
            try writer.writeAll("        }\n");
            // Structural: whether children are called via their suppressed
            // variants follows the enclosing variant's suppression and the
            // parent variable's own AST fact — never the rendered combo
            // (combo-driven node building is decided inside each child line).
            const skip_ast_for_children = skip_ast_construction or !self.symbols.items[variable].ast_enabled;
            for (rule.rhs.items[self_index + 1 ..], self_index + 1..) |symbol_index, child_index| {
                try self.emitChildParseLine(writer, symbol_index, variable, rule, child_index, "frame.node", "frame.children", "        ", skip_ast_for_children, child_index);
            }
            try writer.writeAll("        frame.node.text_length = context.currentTokenSourceOffset() - frame.node.text_start;\n");
            try emitter_common.emitDebugReduction(writer, self.symbols.items, rule, "        ");
            try self.emitProcedureBlock(
                writer,
                rule_index,
                variable,
                "frame.node",
                if (self.has_occurrence_procedures) "if (frame_index == 0) occurrence_procedures else recursive_occurrence_procedures" else "null",
                "        ",
                false,
            );
            try writer.writeAll("        frame.node.clearTemporaryChildren();\n        reduced_node = frame.node;\n    }\n    return reduced_node;\n");
            return;
        }

        if (returns_node) {
            try writer.writeAll(
                \\    var node_address = data_structures.Node.invalid_pointer;
                \\    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
                \\    _ = &node_address;
                \\    var repeating_node_address = node_address;
                \\    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
                \\
            );
        } else if (rule.rhs.items.len > self_index + 1) {
            try writer.writeAll(
                \\    var counter: usize = 0;
                \\    counter = counter; // dummy store for 0-repetition paths
                \\
            );
        }

        try self.emitSelfRepeatingLoop(writer, self.plan.selfRepeatingDecision(variable, rule_index, self_index, skip_ast_construction).tree, .{
            .rule = rule,
            .variable = variable,
            .self_index = self_index,
            .skip_ast_construction = skip_ast_construction,
            .returns_node = returns_node,
            .frames_mode = false,
        });

        if (returns_node) {
            const explicit_recovery = self.uses_explicit_recovery;
            try writer.print("    const exit_node = {s}parse_{s}(context", .{ if (explicit_recovery) "" else "try ", name });
            if (self.has_occurrence_procedures) {
                try writer.writeAll(", if (node_address == data_structures.Node.invalid_pointer) occurrence_procedures else ");
                try emitter_common.emitProcedureSequenceExpression(writer, &self.plan.hooks, rule.rhs_annotations.items[self_index].procedures.items);
            }
            if (self.uses_explicit_recovery) {
                try writer.writeAll(", occurrence_recovery");
            }
            if (explicit_recovery) {
                try self.emitExplicitRuleCatch(writer, rule, variable, skip_ast_construction, "", "repeating_node_address");
            } else {
                try writer.writeByte(')');
            }
            try writer.print(
                \\;
                \\    if (exit_node != data_structures.Node.invalid_pointer) {{
                \\        if (node_address == data_structures.Node.invalid_pointer) {{
                \\            node_address = exit_node;
                \\        }} else {{
                \\            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child {d} (chain if replaceWithChildren)
                \\        }}
                \\    }}
                \\    while (repeating_node_address != data_structures.Node.invalid_pointer) {{
            , .{self_index});
            try writer.writeByte('\n');
            const skip_ast_for_children = skip_ast_construction or !self.symbols.items[variable].ast_enabled;
            for (rule.rhs.items[self_index + 1 ..], self_index + 1..) |symbol_index, child_index| {
                try self.emitChildParseLine(writer, symbol_index, variable, rule, child_index, "node", "repeating_node_address", "        ", skip_ast_for_children, child_index);
            }
            try writer.writeByte('\n');
            try emitter_common.emitDebugReduction(writer, self.symbols.items, rule, "        ");
            if (self.options.with_ast) {
                try writer.writeAll("        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;\n");
            }
            // Hooks may detach the wrapper (`replaceWithChildren` does) and
            // the removal below does, which clears its links. The enclosing
            // wrapper is the loop's next position, so read it before either.
            try writer.writeAll("        const enclosing_node_address = context.node_allocator.at(repeating_node_address).parent;\n");
            if (self.options.with_procedures and self.options.with_ast) {
                try writer.writeByte('\n');
                if (self.has_occurrence_procedures) {
                    try writer.writeAll("        const reduction_occurrence_procedures = if (enclosing_node_address == data_structures.Node.invalid_pointer) occurrence_procedures else ");
                    try emitter_common.emitProcedureSequenceExpression(writer, &self.plan.hooks, rule.rhs_annotations.items[self_index].procedures.items);
                    try writer.writeAll(";\n");
                }
                try self.emitProcedureBlock(
                    writer,
                    rule_index,
                    variable,
                    "repeating_node_address",
                    if (self.has_occurrence_procedures) "reduction_occurrence_procedures" else "null",
                    "        ",
                    true,
                );
                try writer.writeByte('\n');
                try writer.writeAll(
                    \\        if (args.node_address) |effective| {
                    \\            if (node_address == repeating_node_address) {
                    \\                node_address = effective;
                    \\            }
                    \\        } else {
                    \\            data_structures.Node.removeSelf(repeating_node_address, context.node_allocator);
                    \\            if (node_address == repeating_node_address) {
                    \\                node_address = data_structures.Node.invalid_pointer;
                    \\            }
                    \\        }
                    \\
                );
            }
            try writer.writeAll("        repeating_node_address = enclosing_node_address;\n");
            try writer.writeAll(
                \\    }
                \\    return node_address;
                \\
            );
        } else {
            const explicit_recovery = self.uses_explicit_recovery;
            try writer.print("    {s}parse_{s}{s}(context", .{ if (explicit_recovery) "" else "try ", name, if (skip_ast_construction) "_" else "" });
            if (self.has_occurrence_procedures) try writer.writeAll(", null");
            if (self.uses_explicit_recovery) try writer.writeAll(", occurrence_recovery");
            if (explicit_recovery) {
                try self.emitExplicitRuleCatch(writer, rule, variable, skip_ast_construction, "", null);
            } else {
                try writer.writeByte(')');
            }
            try writer.writeAll(";\n");
            if (rule.rhs.items.len > self_index + 1) {
                try writer.writeAll("    for (0..counter) |_| {\n");
                const skip_ast_for_children = skip_ast_construction or !self.symbols.items[variable].ast_enabled;
                for (rule.rhs.items[self_index + 1 ..], self_index + 1..) |symbol_index, child_index| {
                    try self.emitChildParseLine(writer, symbol_index, variable, rule, child_index, null, null, "        ", skip_ast_for_children, child_index);
                }
                try writer.writeAll("    }\n");
            }
        }
    }

    const SelfRepeatingLeafParams = struct {
        rule: Rule,
        variable: usize,
        self_index: usize,
        skip_ast_construction: bool,
        returns_node: bool,
        frames_mode: bool,
    };

    /// The repetition loop: each iteration asks the decision whether the
    /// rule repeats, then runs the repeated prefix once.
    fn emitSelfRepeatingLoop(self: *Generator, writer: *std.Io.Writer, node: *const switch_planning.Node, params: SelfRepeatingLeafParams) !void {
        try writer.writeAll("\n    while (true) {\n");
        const repeats = try self.emitDecision(writer, .repetition, params.variable, node, "        ", params.skip_ast_construction);
        try writer.print("        if (!{s}) break;\n", .{repeats});
        try self.emitSelfRepeatingLeafBody(writer, "        ", params);
        try writer.writeAll("    }\n");
    }

    fn emitSelfRepeatingLeafBody(self: *Generator, writer: *std.Io.Writer, indent: []const u8, params: SelfRepeatingLeafParams) !void {
        try self.emitDebugRuleExpansion(writer, params.rule, params.variable, indent);
        if (params.frames_mode) {
            try writer.print(
                \\{s}const frame = try semantic_allocator.create(SemanticReductionFrame);
                \\{s}frame.* = .{{
                \\{s}    .node = .{{ .text_start = context.currentTokenSourceOffset(), .variable = {d}, .payload = .{{}} }},
                \\{s}    .children = @splat(null),
                \\{s}}};
                \\{s}try frames.append(semantic_allocator, frame);
                \\
            , .{ indent, indent, indent, self.variableIndex(params.variable), indent, indent, indent });
            const skip_ast_for_children = params.skip_ast_construction or !self.symbols.items[params.variable].ast_enabled;
            for (params.rule.rhs.items[0..params.self_index], 0..) |symbol_index, child_index| {
                try self.emitChildParseLine(writer, symbol_index, params.variable, params.rule, child_index, "frame.node", "frame.children", indent, skip_ast_for_children, child_index);
            }
        } else {
            if (params.returns_node) {
                try writer.print(
                    \\{s}const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), {d});
                    \\{s}if (node_address == data_structures.Node.invalid_pointer) {{
                    \\{s}    node_address = temporary_address;
                    \\{s}}} else {{
                    \\{s}    context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, temporary_address, context.node_allocator); // child {d}
                    \\{s}}}
                    \\{s}repeating_node_address = temporary_address;
                    \\
                , .{ indent, self.variableIndex(params.variable), indent, indent, indent, indent, params.self_index, indent, indent });
            }
            const skip_ast_for_children = params.skip_ast_construction or !self.symbols.items[params.variable].ast_enabled;
            for (params.rule.rhs.items[0..params.self_index], 0..) |symbol_index, child_index| {
                try self.emitChildParseLine(writer, symbol_index, params.variable, params.rule, child_index, if (params.returns_node) "node" else null, if (params.returns_node) "repeating_node_address" else null, indent, skip_ast_for_children, child_index);
            }
            if (!params.returns_node and params.rule.rhs.items.len > params.self_index + 1) {
                try writer.print("{s}counter += 1;\n", .{indent});
            }
        }
    }

    fn emitTerminalParser(self: *Generator, writer: *std.Io.Writer, terminal_index: usize, skip_ast_construction: bool) !void {
        const name = try self.parserName(terminal_index);
        try writer.print("// {s}Parser for Symbol \"", .{if (skip_ast_construction) "AST-Suppressed " else ""});
        try self.emitSymbolRepr(writer, terminal_index);
        try writer.print("\" with index {d}\n", .{terminal_index});
        try writer.print("inline fn parse_{s}{s}(context: *data_structures.Context", .{ name, if (skip_ast_construction) "_" else "" });
        if (self.has_occurrence_procedures) {
            try writer.writeAll(", occurrence_procedures: ?*const ProcedureSequenceNode");
        }
        if (self.uses_explicit_recovery) {
            try writer.writeAll(", occurrence_recovery: ?*const ExplicitRecoveryScope");
        }
        try writer.print(") anyerror!nodeReturnType({d}, {s}) {{\n", .{ terminal_index, if (skip_ast_construction) "true" else "false" });
        try emitter_common.emitModeGatedBody(Generator, self, writer, TerminalParserBody, .{
            .terminal_index = terminal_index,
            .skip_ast_construction = skip_ast_construction,
        }, self.has_occurrence_procedures, renderTerminalParserBody);
        try writer.writeAll("}\n");
    }

    const TerminalParserBody = struct {
        terminal_index: usize,
        skip_ast_construction: bool,
    };

    fn renderTerminalParserBody(self: *Generator, writer: *std.Io.Writer, params: TerminalParserBody) !void {
        const terminal_index = params.terminal_index;
        const skip_ast_construction = params.skip_ast_construction;
        const returns_node = self.symbolReturnsNode(terminal_index, skip_ast_construction);
        if (returns_node) {
            if (self.options.with_ast) {
                try writer.print("    {s} node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), data_structures.Node.invalid_variable);\n\n", .{
                    if (self.options.with_procedures) "var" else "const",
                });
            } else {
                try writer.writeAll("    var node = data_structures.Node{ .text_start = context.currentTokenSourceOffset(), .payload = .{} };\n\n");
            }
        }

        const decision = self.plan.parserDecision(terminal_index, skip_ast_construction);
        try self.emitTerminalSwitch(writer, decision.tree, 0, "    ");
        try writer.writeByte('\n');
        if (returns_node) {
            if (self.options.with_ast) {
                try writer.writeAll("    context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;\n");
            } else {
                try writer.writeAll("    node.text_length = context.currentTokenSourceOffset() - node.text_start;\n");
            }
            if (self.options.with_procedures) {
                try self.emitTerminalProcedureBlock(
                    writer,
                    terminal_index,
                    if (self.options.with_ast) "node_address" else "node",
                    if (self.has_occurrence_procedures) "occurrence_procedures" else "null",
                    "    ",
                );
                if (self.options.with_ast) try writer.writeAll("    node_address = args.node_address orelse data_structures.Node.invalid_pointer;\n\n");
            }
            try writer.writeAll(if (self.options.with_ast) "    return node_address;\n" else "    return node;\n");
        }
    }

    fn emitRecoveryCandidates(self: *Generator, writer: *std.Io.Writer, candidates: []const []const u8) !void {
        _ = self;
        try writer.writeAll("&[_][]const u8{");
        for (candidates, 0..) |candidate, index| {
            if (index != 0) try writer.writeAll(", ");
            try emitStringLiteral(writer, candidate);
        }
        try writer.writeAll("}");
    }

    fn emitTerminalSwitch(self: *Generator, writer: *std.Io.Writer, node: *const switch_planning.Node, prefix_length: usize, indent: []const u8) EmitError!void {
        if (node.groups.items.len == 0) {
            if (node.fallback != null) {
                try self.emitTerminalLeaf(writer, node.fallback_length orelse prefix_length, indent);
                return;
            }
        }

        try emitter_common.emitMergedSwitch(
            TerminalSwitchContext,
            EmitError,
            self.allocator,
            writer,
            node,
            prefix_length,
            indent,
            .{ .generator = self, .node = node, .prefix_length = prefix_length, .indent = indent },
            renderTerminalProngBody,
            renderTerminalFallbackBody,
            renderTerminalElse,
        );
    }

    const TerminalSwitchContext = struct {
        generator: *Generator,
        node: *const switch_planning.Node,
        prefix_length: usize,
        indent: []const u8,
    };

    fn renderTerminalProngBody(context: TerminalSwitchContext, buffer: *std.Io.Writer, group_index: usize) EmitError!void {
        const group = context.node.groups.items[group_index];
        const step_length = context.node.step_length;
        if (group.child.isLeaf()) {
            try context.generator.emitTerminalLeaf(buffer, group.child.fallback_length orelse context.prefix_length + step_length, context.indent);
        } else {
            const child_indent = try indented(context.generator.allocator, context.indent, 8);
            try context.generator.emitTerminalSwitch(buffer, group.child, context.prefix_length + step_length, child_indent);
            try buffer.writeByte('\n');
        }
    }

    fn renderTerminalFallbackBody(context: TerminalSwitchContext, buffer: *std.Io.Writer) EmitError!void {
        try context.generator.emitTerminalLeaf(buffer, context.node.fallback_length orelse context.prefix_length, context.indent);
    }

    fn renderTerminalElse(context: TerminalSwitchContext, writer: *std.Io.Writer) EmitError!void {
        if (context.node.fallback != null) {
            try writer.print("{s}    else => {{ // ''\n", .{context.indent});
            try context.generator.emitTerminalLeaf(writer, context.node.fallback_length orelse context.prefix_length, context.indent);
            try writer.print("{s}    }},\n", .{context.indent});
            return;
        }
        try context.generator.emitSyntaxErrorElse(writer, context.node, context.indent);
    }

    fn emitTerminalLeaf(self: *Generator, writer: *std.Io.Writer, length: usize, indent: []const u8) EmitError!void {
        _ = self;
        try writer.print("{s}        context.releaseToken({d});\n", .{ indent, length });
    }

    /// The `else` prong of a decision or terminal switch that no rule
    /// accepts: report the syntax error the plan attached to `node`.
    fn emitSyntaxErrorElse(self: *Generator, writer: *std.Io.Writer, node: *const switch_planning.Node, indent: []const u8) EmitError!void {
        const spec = self.plan.syntax_error_handlers.items[node.diagnostic.?];
        try writer.print("{s}    else => {{\n", .{indent});
        try writer.print("{s}        @branchHint(.unlikely);\n", .{indent});
        try self.emitSyntaxErrorCall(writer, spec, try indented(self.allocator, indent, 8));
        try writer.print("{s}    }},\n", .{indent});
    }

    fn emitSyntaxErrorCall(
        self: *Generator,
        writer: *std.Io.Writer,
        spec: SyntaxErrorHandlerSpec,
        indent: []const u8,
    ) EmitError!void {
        const arguments = if (self.uses_explicit_recovery) try std.fmt.allocPrint(self.allocator, "context, {s}", .{self.occurrenceRecoveryName()}) else "context";
        // A handler that returns recovered; one that cannot recover throws.
        // The node the parser was building outlives the recovery. The text
        // does not depend on whether recovery is enabled, so those
        // configurations keep sharing one body.
        const call = try std.fmt.allocPrint(self.allocator, "{s}({s})", .{ spec.name, arguments });
        if (self.options.with_ast and self.symbolReturnsNode(spec.symbol_index, spec.skip_ast_construction)) {
            try writer.print("{s}_ = ", .{indent});
            try self.emitHandledCall(writer, indent, call);
            try writer.writeAll(";\n");
            try self.emitLevelReturn(writer, indent, recoveredNodeExpression(null));
            return;
        }
        if (self.framedTailLoop() == null) {
            try writer.print("{s}return {s};\n", .{ indent, call });
            return;
        }
        // A loop level's handler result is its result.
        var handled = std.Io.Writer.Allocating.init(self.allocator);
        try self.emitHandledCall(&handled.writer, indent, call);
        try self.emitLevelReturn(writer, indent, handled.written());
    }

    /// What a parser hands its caller after recovering, with AST
    /// construction: the node it was building, flagged and spanning the
    /// skipped input. `inner_level` names the current level of a
    /// self-repeating parser's chain, whose outer levels the recovery also
    /// cuts short.
    fn recoveredNodeExpression(inner_level: ?[]const u8) []const u8 {
        if (inner_level != null) return "context.keepRecoveredChain(node_address, repeating_node_address)";
        return "context.keepRecoveredNode(node_address)";
    }

    const SyntaxErrorHandlerBody = struct {
        spec: SyntaxErrorHandlerSpec,
        site_index: usize,
    };

    fn emitSyntaxErrorHandlers(self: *Generator, writer: *std.Io.Writer) !void {
        // Support functions for every recovery style are emitted unconditionally
        // in emit(); which style a config selects is decided at comptime inside
        // each handler, and unused support folds away.
        for (self.plan.syntax_error_handlers.items, 0..) |spec, site_index| {
            try writer.print("\nnoinline fn {s}(context: *data_structures.Context", .{spec.name});
            if (self.uses_explicit_recovery) try writer.writeAll(", occurrence_recovery: ?*const ExplicitRecoveryScope");
            try writer.print(") linksection(if (builtin.os.tag == .macos) \"__TEXT,__unlikely\" else \".text.unlikely\") anyerror!nodeReturnType({d}, {s}) {{\n", .{ spec.symbol_index, if (spec.skip_ast_construction) "true" else "false" });
            try writer.writeAll("    @branchHint(.cold);\n");
            try emitter_common.emitModeGatedBody(Generator, self, writer, SyntaxErrorHandlerBody, .{ .spec = spec, .site_index = site_index }, false, renderSyntaxErrorHandlerBody);
            try writer.writeAll("}\n");
            try self.emitFailFastSyntaxErrorMessageRenderer(writer, spec);
        }
    }

    fn renderSyntaxErrorHandlerBody(self: *Generator, writer: *std.Io.Writer, params: SyntaxErrorHandlerBody) !void {
        const spec = params.spec;
        const site_index = params.site_index;
        const symbol = self.symbols.items[spec.symbol_index];
        const returns_node = self.symbolReturnsNode(spec.symbol_index, spec.skip_ast_construction);
        // Recovery styles that this grammar can never select (explicit
        // annotations vs automatic) are comptime-unreachable; emit a stub so
        // the gate chain stays exhaustive without touching mode-specific
        // tables that do not exist for this grammar.
        switch (self.bodyRecoveryMode()) {
            .automatic => if (self.uses_explicit_recovery) {
                try writer.writeAll("    unreachable;\n");
                return;
            },
            .explicit => if (!self.uses_explicit_recovery) {
                try writer.writeAll("    unreachable;\n");
                return;
            },
            .disabled => {},
        }
        if (!self.options.with_error_recovery) {
            try writer.writeAll("    return llFailFastSyntaxError(context, .{ .while_parsing = &[_][]const u8{");
            try emitStringLiteral(writer, symbol.id);
            try writer.writeAll("} }, ");
            try self.emitRecoveryCandidates(writer, spec.expected_tokens);
            try writer.print(", {s}_message);\n", .{spec.name});
            return;
        }
        if (self.uses_explicit_recovery) {
            try writer.writeAll("    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{");
            try emitStringLiteral(writer, symbol.id);
            try writer.writeAll("} }, ");
            try self.emitRecoveryCandidates(writer, spec.expected_tokens);
            try writer.writeAll(");\n");
            try writer.print("    context.setPendingSyntaxErrorSite({d});\n", .{site_index});
            if (symbol.kind == .variable) {
                try writer.print("    if (try llTryRecoverySelection_{d}(context, occurrence_recovery)) {{\n", .{spec.symbol_index});
                if (returns_node) {
                    try writer.print("        return {s};\n", .{self.missingNode()});
                } else {
                    try writer.writeAll("        return;\n");
                }
                try writer.writeAll("    }\n");
            } else {
                try writer.writeAll("    _ = occurrence_recovery;\n");
            }
            try writer.writeAll("    return error.ExplicitSyntaxRecovery;\n");
            return;
        }
        const candidates = self.plan.recovery.automatic_candidates.get(spec.symbol_index) orelse unreachable;
        try writer.writeAll("    const report_syntax_error = context.beginSyntaxRecovery();\n");
        try writer.writeAll("    if (report_syntax_error) {\n");
        try writer.writeAll("        try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{");
        try emitStringLiteral(writer, symbol.id);
        try writer.writeAll("} }, ");
        try self.emitRecoveryCandidates(writer, spec.expected_tokens);
        try writer.writeAll(");\n");
        try emitter_common.emitSiteMessagePrint(writer, spec.name, "        ");
        try writer.writeAll("    }\n");
        try writer.writeAll("    if (report_syntax_error and context.syntaxErrorLimitReached()) return root.ParseError.SyntaxError;\n");
        try writer.writeAll("    if (try llRecoveryOffset(context, ");
        try self.emitRecoveryCandidates(writer, candidates);
        try writer.writeAll(", if (report_syntax_error) 1 else 0)) |recovery_offset| {\n");
        try writer.writeAll("        context.skipRecoveryInput(recovery_offset);\n");
        try writer.writeAll("    }\n");
        if (returns_node) {
            try writer.print("    return {s};\n", .{self.missingNode()});
        }
    }

    fn emitFailFastSyntaxErrorSupport(self: *Generator, writer: *std.Io.Writer) !void {
        _ = self;
        try writer.writeByte('\n');
        try emitter_common.emitFailFastSyntaxErrorSupport(writer, "ll", "LL");
    }

    fn emitFailFastSyntaxErrorMessageRenderer(
        self: *Generator,
        writer: *std.Io.Writer,
        spec: SyntaxErrorHandlerSpec,
    ) !void {
        _ = self;
        try writer.writeByte('\n');
        try emitter_common.emitFailFastMessageRenderer(writer, spec.name, &.{ spec.exact_name, spec.symbol_name, "syntax_error_ll", "syntax_error" });
    }

    fn emitRuleBody(self: *Generator, writer: *std.Io.Writer, rule_index: usize, parent_variable: usize, indent: []const u8, skip_ast_construction: bool) !void {
        const rule = self.rules.items[rule_index];
        const parent_returns_node = self.symbolReturnsNode(parent_variable, skip_ast_construction);
        const captures_root = if (parent_variable == self.plan.augmented_start) captures: {
            const start_symbol = rule.rhs.items[0];
            const start_skips_ast_construction = (self.options.with_ast or self.options.with_procedures) and
                (skip_ast_construction or !self.symbols.items[start_symbol].ast_enabled);
            break :captures self.symbolReturnsNode(start_symbol, start_skips_ast_construction);
        } else false;
        try self.emitDebugRuleExpansion(writer, rule, parent_variable, indent);

        const in_tail_loop = if (self.tail_loop) |*loop| loop.variable == parent_variable else false;
        if (in_tail_loop) self.tail_loop.?.rule_index = rule_index;
        // A flattened parser appends to its caller's node, or without AST
        // construction keeps the children on a carrier it hands back.
        const flattened = self.flattened_variable == parent_variable;
        const flattened_target: ?[]const u8 = if (self.options.with_ast) "node_address" else if (parent_returns_node) "node" else null;
        // A loop level builds its node by value in its own frame.
        const value_node = if (in_tail_loop) "level.node" else "node";
        const value_children = if (in_tail_loop) "level.children" else "child_nodes";
        if (rule.rhs.items.len != 0) {
            if (!self.options.with_ast and parent_returns_node and !in_tail_loop and !flattened and self.ruleHasNodeChildren(rule, skip_ast_construction)) {
                try writer.print("{s}var child_nodes: [{d}]?data_structures.Node = @splat(null);\n", .{ indent, self.expandedSlotCount(rule) });
            }
            if (captures_root) {
                try writer.print("{s}var root_node: root.data_structures.VariableResult = {s};\n", .{ indent, self.missingNode() });
            }
            defer self.in_last_position = false;
            for (rule.rhs.items, 0..) |symbol_index, child_index| {
                self.in_last_position = in_tail_loop and child_index + 1 == rule.rhs.items.len;
                try self.emitChildParseLine(
                    writer,
                    symbol_index,
                    parent_variable,
                    rule,
                    child_index,
                    if (flattened) flattened_target else if (parent_returns_node) if (self.options.with_ast) "node_address" else value_node else null,
                    if (captures_root and child_index == 0)
                        "root_node"
                    else if (flattened)
                        flattened_target
                    else if (parent_returns_node)
                        if (self.options.with_ast) "node_address" else value_children
                    else
                        null,
                    indent,
                    skip_ast_construction,
                    child_index,
                );
                // The root is taken as soon as its parse returns, ahead of
                // the symbols after it (the end of the input): a recovered
                // error there still publishes the tree that was parsed.
                if (captures_root and child_index == 0) try self.emitRootCapture(writer, indent);
            }
        }

        // A flattened parser reduces nothing: the caller's node does.
        if (flattened) return;
        // A rule that always continues the loop reduces when it unwinds.
        if (in_tail_loop and self.tailReach(parent_variable, rule, self.tail_loop.?.kind) == .always) return;
        try self.emitRuleFinalize(writer, rule_index, parent_variable, indent, skip_ast_construction, value_node);
    }

    fn emitRootCapture(self: *Generator, writer: *std.Io.Writer, indent: []const u8) !void {
        if (self.options.with_ast) {
            try writer.print("{s}if (root_node != data_structures.Node.invalid_pointer) {{\n{s}    root_reduction.ast_root = root_node;\n", .{ indent, indent });
            if (self.options.with_procedures) {
                try writer.print("{s}    root_reduction.semantic_root = context.node_allocator.at(root_node).payload;\n", .{indent});
            }
            try writer.print("{s}}}\n", .{indent});
        } else {
            try writer.print("{s}if (root_node) |node| root_reduction.semantic_root = node.payload;\n", .{indent});
        }
    }

    /// `value_node` names the node built by value (without AST construction).
    fn emitRuleFinalize(self: *Generator, writer: *std.Io.Writer, rule_index: usize, parent_variable: usize, indent: []const u8, skip_ast_construction: bool, value_node: []const u8) !void {
        const rule = self.rules.items[rule_index];
        const parent_returns_node = self.symbolReturnsNode(parent_variable, skip_ast_construction);

        if (parent_returns_node) {
            if (self.options.with_ast) {
                try writer.print("{s}context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;\n", .{indent});
            } else {
                try writer.print("{s}{s}.text_length = context.currentTokenSourceOffset() - {s}.text_start;\n", .{ indent, value_node, value_node });
            }
        }

        if (self.options.with_procedures and parent_returns_node) {
            try self.emitProcedureBlock(
                writer,
                rule_index,
                parent_variable,
                if (self.options.with_ast) "node_address" else value_node,
                if (self.has_occurrence_procedures) self.occurrenceProceduresName() else "null",
                indent,
                true,
            );
            if (self.options.with_ast) {
                try writer.print("{s}node_address = args.node_address orelse data_structures.Node.invalid_pointer;\n", .{indent});
            }
        }

        if (self.options.with_procedures and parent_returns_node) try writer.writeByte('\n');
        try emitter_common.emitDebugReduction(writer, self.symbols.items, rule, indent);
        if (!self.options.with_ast and parent_returns_node) {
            try writer.print("{s}{s}.clearTemporaryChildren();\n", .{ indent, value_node });
        }
    }

    fn emitChildParseLine(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, parent_variable: usize, rule: Rule, child_index: usize, parent: ?[]const u8, parent_address: ?[]const u8, indent: []const u8, skip_ast_construction: bool, slot_index: usize) !void {
        const name = try self.parserName(symbol_index);
        const child = self.symbols.items[symbol_index];
        const explicit_recovery = self.uses_explicit_recovery;
        const inner_level: ?[]const u8 = if (parent_address) |address|
            (if (std.mem.eql(u8, address, "repeating_node_address")) address else null)
        else
            null;
        const verbatim = rule.rhs_annotations.items[child_index].verbatim;
        self.verbatim_literal = rule.rhs_annotations.items[child_index].verbatim_literal;
        self.verbatim_consume = rule.rhs_annotations.items[child_index].verbatim_consume;
        // Structural, configuration-independent suppression choice: which
        // callee variant (suppressed or not) matches this call site is a
        // grammar/callgraph fact — never a property of the combo rendered.
        const child_skips_ast_construction = skip_ast_construction or (child.kind == .variable and !child.ast_enabled);
        const child_returns_node = self.symbolReturnsNode(symbol_index, child_skips_ast_construction);
        if (self.tail_loop) |*loop| {
            if (symbol_index == loop.variable and self.in_last_position and planning.isTailLoopPosition(rule, child_index) and self.continuesLoop(loop.kind, rule, child_index)) {
                std.debug.assert(child_skips_ast_construction == loop.skip_ast_construction);
                try loop.sites.append(self.allocator, .{ .rule_index = loop.rule_index, .occurrence_rule = rule, .position = child_index, .slot = slot_index });
                try self.emitTailDescent(writer, indent, loop.sites.items.len - 1);
                return;
            }
        }
        // The single transparency gate: synthetic factoring helpers never
        // emit a call. Their alternatives expand inline here so suffix
        // children parse exactly as direct children of the caller — same
        // parsers, same occurrence/recovery attribution, same slots — with
        // no node and no hooks of their own. Every body (normal,
        // self-repeating, suppressed) flows through this function, so
        // every combo splices identically.
        if (child.kind == .variable and child.synthetic_transparent) {
            try self.emitTransparentTailInline(writer, symbol_index, rule, child_index, parent, parent_address, indent, skip_ast_construction);
            return;
        }
        // A flattened occurrence builds no node: its parser appends the
        // children to this one's. Without nodes there is nothing to flatten.
        if (!child_skips_ast_construction and common.isFlattenedOccurrence(self.symbols.items, rule, child_index)) {
            const target = if (self.options.with_ast) parent_address orelse "data_structures.Node.invalid_pointer" else "data_structures.Node.invalid_pointer";
            // Without AST construction the children come back on a carrier.
            const takes_children = !self.options.with_ast and parent != null and child_returns_node;
            if (takes_children) {
                try writer.print("{s}{{\n{s}    const flattened_children = {s}parse_{s}_flattened(context, {s}", .{ indent, indent, if (explicit_recovery) "" else "try ", name, target });
            } else {
                try writer.print("{s}_ = {s}parse_{s}_flattened(context, {s}", .{ indent, if (explicit_recovery) "" else "try ", name, target });
            }
            if (explicit_recovery) {
                try self.emitExplicitRuleCatch(writer, rule, parent_variable, skip_ast_construction, indent, inner_level);
            } else {
                try writer.writeByte(')');
            }
            try writer.print("; // child {d}, flattened\n", .{child_index});
            if (takes_children) {
                try writer.print("{s}    if (flattened_children) |*carrier| {s}.appendTemporaryChildren(carrier);\n{s}}}\n", .{ indent, parent.?, indent });
            }
            return;
        }
        if (child.kind != .variable) self.inline_call_cost += self.terminal_inline_costs[symbol_index];
        const call_name = if (symbol_index == parent_variable and !planning.isTailLoopPosition(rule, child_index))
            try std.fmt.allocPrint(self.allocator, "{s}_{s}_{d}", .{ name, rule.rhs_index, child_index })
        else
            name;
        if (verbatim) try self.emitVerbatimTerminatorStart(writer, symbol_index, indent);
        if (parent != null) {
            if (child_returns_node) {
                if (!self.options.with_ast) {
                    try writer.print("{s}{{\n{s}    {s} child_node = {s}parse_{s}(context", .{ indent, indent, if (verbatim) "var" else "const", if (explicit_recovery) "" else "try ", call_name });
                    try self.emitChildOccurrenceArgument(writer, rule, child_index, child_returns_node);
                    if (explicit_recovery) {
                        try self.emitExplicitRuleCatch(writer, rule, parent_variable, skip_ast_construction, indent, inner_level);
                    } else {
                        try writer.writeByte(')');
                    }
                    try writer.print("; // child {d}\n", .{child_index});
                    if (verbatim) {
                        try self.emitVerbatimCapture(writer, symbol_index, indent);
                        try writer.print("{s}    if (child_node) |*verbatim_node| verbatim_node.text_length = context.currentTokenSourceOffset() - verbatim_node.text_start;\n", .{indent});
                    }
                    if (self.keepsChildren()) {
                        // The children leave this parser before the node that
                        // takes them reduces, so they outlive its frame.
                        try writer.print(
                            \\{s}    if (child_node) |value| try {s}.appendKeptTemporaryChild(context.runtime().arena_allocator, value);
                            \\{s}}}
                            \\
                        , .{ indent, parent.?, indent });
                        return;
                    }
                    try writer.print(
                        \\{s}    if (child_node) |value| {{
                        \\{s}        {s}[{d}] = value;
                        \\{s}        {s}.appendTemporaryChild(&{s}[{d}].?);
                        \\{s}    }}
                        \\{s}}}
                        \\
                    , .{ indent, indent, parent_address.?, slot_index, indent, parent.?, parent_address.?, slot_index, indent, indent });
                    return;
                }
                try writer.print("{s}{{\n{s}    const child_node = {s}parse_{s}(context", .{ indent, indent, if (explicit_recovery) "" else "try ", call_name });
                try self.emitChildOccurrenceArgument(writer, rule, child_index, child_returns_node);
                if (explicit_recovery) {
                    try self.emitExplicitRuleCatch(writer, rule, parent_variable, skip_ast_construction, indent, inner_level);
                } else {
                    try writer.writeByte(')');
                }
                try writer.print("; // child {d}\n", .{child_index});
                if (verbatim) {
                    try self.emitVerbatimCapture(writer, symbol_index, indent);
                    try writer.print(
                        \\{s}    if (child_node != data_structures.Node.invalid_pointer) {{
                        \\{s}        context.node_allocator.at(child_node).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(child_node).text_start;
                        \\{s}    }}
                        \\
                    , .{ indent, indent, indent });
                }
                try writer.print(
                    \\{s}    if (child_node != data_structures.Node.invalid_pointer) {{
                    \\{s}        context.node_allocator.at({s}).immediateAppendChildren({s}, child_node, context.node_allocator); // child {d} (chain if replaceWithChildren)
                    \\{s}    }}
                    \\{s}}}
                    \\
                , .{ indent, indent, parent_address.?, parent_address.?, child_index, indent, indent });
            } else {
                try writer.print("{s}_ = {s}parse_{s}{s}(context", .{ indent, if (explicit_recovery) "" else "try ", call_name, if (child_skips_ast_construction) "_" else "" });
                try self.emitChildOccurrenceArgument(writer, rule, child_index, false);
                if (explicit_recovery) {
                    try self.emitExplicitRuleCatch(writer, rule, parent_variable, skip_ast_construction, indent, inner_level);
                } else {
                    try writer.writeByte(')');
                }
                try writer.print("; // child {d}\n", .{child_index});
                if (verbatim) try self.emitVerbatimCapture(writer, symbol_index, indent);
            }
        } else if (child_returns_node) {
            try writer.print("{s}{s} = {s}parse_{s}(context", .{ indent, parent_address orelse "_", if (explicit_recovery) "" else "try ", call_name });
            try self.emitChildOccurrenceArgument(writer, rule, child_index, true);
            if (explicit_recovery) {
                try self.emitExplicitRuleCatch(writer, rule, parent_variable, skip_ast_construction, indent, inner_level);
            } else {
                try writer.writeByte(')');
            }
            try writer.print("; // child {d}\n", .{child_index});
            if (verbatim) {
                try self.emitVerbatimCapture(writer, symbol_index, indent);
                if (parent_address) |address| {
                    if (!std.mem.eql(u8, address, "_")) {
                        try writer.print("{s}if ({s}) |*verbatim_node| verbatim_node.text_length = context.currentTokenSourceOffset() - verbatim_node.text_start;\n", .{ indent, address });
                    }
                }
            }
        } else {
            try writer.print("{s}_ = {s}parse_{s}{s}(context", .{ indent, if (explicit_recovery) "" else "try ", call_name, if (child_skips_ast_construction) "_" else "" });
            try self.emitChildOccurrenceArgument(writer, rule, child_index, false);
            if (explicit_recovery) {
                try self.emitExplicitRuleCatch(writer, rule, parent_variable, skip_ast_construction, indent, inner_level);
            } else {
                try writer.writeByte(')');
            }
            try writer.print("; // child {d}\n", .{child_index});
            if (verbatim) try self.emitVerbatimCapture(writer, symbol_index, indent);
        }
    }

    /// Carries the grandparent call-site targets through a transparent tail
    /// expansion so suffix children attach exactly where a direct child
    /// would. The tail's own occurrence carries no annotations by
    /// construction (see factorSharedPrefixStep), so nothing is dropped by
    /// not emitting a call for it.
    const TransparentInlineContext = struct {
        in_last_position: bool,
        parent_rule: Rule,
        tail_position: usize,
        parent: ?[]const u8,
        parent_address: ?[]const u8,
        skip_ast_construction: bool,
    };

    fn emitTransparentTailInline(
        self: *Generator,
        writer: *std.Io.Writer,
        tail: usize,
        parent_rule: Rule,
        tail_position: usize,
        parent: ?[]const u8,
        parent_address: ?[]const u8,
        indent: []const u8,
        skip_ast_construction: bool,
    ) EmitError!void {
        // The planned decision already starts at offset zero, which matches
        // the inline point: the shared prefix was consumed by the normal
        // child lines above, so lookahead begins fresh here.
        const decision = self.plan.parserDecision(tail, skip_ast_construction);
        const context: TransparentInlineContext = .{
            .in_last_position = self.in_last_position,
            .parent_rule = parent_rule,
            .tail_position = tail_position,
            .parent = parent,
            .parent_address = parent_address,
            .skip_ast_construction = skip_ast_construction,
        };
        try self.emitRuleDispatch(writer, tail, decision.tree, indent, skip_ast_construction, TransparentTailRuleBody{
            .generator = self,
            .tail = tail,
            .inline_context = context,
        }, TransparentTailRuleBody.emit);
    }

    const VariableRuleBody = struct {
        generator: *Generator,
        variable: usize,
        skip_ast_construction: bool,

        fn emit(self: VariableRuleBody, writer: *std.Io.Writer, rule_index: usize, indent: []const u8) EmitError!void {
            try self.generator.emitRuleBody(writer, rule_index, self.variable, indent, self.skip_ast_construction);
        }
    };

    const TransparentTailRuleBody = struct {
        generator: *Generator,
        tail: usize,
        inline_context: TransparentInlineContext,

        fn emit(self: TransparentTailRuleBody, writer: *std.Io.Writer, rule_index: usize, indent: []const u8) EmitError!void {
            try self.generator.emitTransparentTailLeaf(writer, self.tail, rule_index, indent, self.inline_context);
        }
    };

    /// Emits the decision that selects one of `symbol_index`'s rules, then
    /// one `switch` over the selection whose prongs each hold a rule body
    /// written by `emitBody`. The single gate for rule choice: every leaf of
    /// the byte-level decision names its rule instead of repeating the body,
    /// so size is leaves plus bodies, not leaves times bodies.
    fn emitRuleDispatch(
        self: *Generator,
        writer: *std.Io.Writer,
        symbol_index: usize,
        node: *const switch_planning.Node,
        indent: []const u8,
        skip_ast_construction: bool,
        context: anytype,
        comptime emitBody: fn (@TypeOf(context), *std.Io.Writer, usize, []const u8) EmitError!void,
    ) EmitError!void {
        var rule_indices = std.ArrayList(usize).empty;
        try collectDecisionRules(self.allocator, node, &rule_indices);
        const selected = try self.emitDecision(writer, .rule, symbol_index, node, indent, skip_ast_construction);
        const body_indent = try indented(self.allocator, indent, 8);
        try writer.print("{s}switch ({s}) {{\n", .{ indent, selected });
        for (rule_indices.items) |rule_index| {
            try writer.print("{s}    {d} => {{\n", .{ indent, rule_index });
            try emitBody(context, writer, rule_index, body_indent);
            try writer.print("{s}    }},\n", .{indent});
        }
        try writer.print("{s}    else => unreachable,\n{s}}}\n", .{ indent, indent });
    }

    /// The bytes a byte-run rule repeats, or null when `variable` is not one.
    /// A byte run is a hidden rule `X | c1 X | c2 X | ... |` without
    /// annotations, where every `ci` matches single ordinary bytes only: not
    /// the lexer's synthetic tokens (0x00 to 0x03) nor a newline, whose
    /// meaning depends on indentation. Its language is a run of those bytes.
    fn byteRunBytes(self: *Generator, variable: usize) EmitError!?[]const u8 {
        const symbol = self.symbols.items[variable];
        if (symbol.kind != .variable or symbol.ast_enabled or symbol.synthetic_transparent) return null;
        if (!planning.annotationsEmpty(symbol.annotations)) return null;
        var repeated: [256]bool = @splat(false);
        var has_empty = false;
        var has_repetition = false;
        for (self.rules.items) |rule| {
            if (rule.header != variable) continue;
            if (!planning.annotationsEmpty(rule.annotations)) return null;
            for (rule.rhs_annotations.items) |annotations| {
                if (!planning.annotationsEmpty(annotations)) return null;
            }
            switch (rule.rhs.items.len) {
                0 => has_empty = true,
                2 => {
                    if (rule.rhs.items[1] != variable) return null;
                    const terminal = self.symbols.items[rule.rhs.items[0]];
                    if (terminal.kind != .terminal and terminal.kind != .generative_terminal) return null;
                    if (terminal.terminals.items.len == 0) return null;
                    for (terminal.terminals.items) |member| {
                        if (member.len != 1) return null;
                        switch (member[0]) {
                            0...3, '\n' => return null,
                            else => repeated[member[0]] = true,
                        }
                    }
                    has_repetition = true;
                },
                else => return null,
            }
        }
        if (!has_empty or !has_repetition) return null;
        var bytes = std.ArrayList(u8).empty;
        for (repeated, 0..) |is_repeated, byte| {
            if (is_repeated) try bytes.append(self.allocator, @intCast(byte));
        }
        return try bytes.toOwnedSlice(self.allocator);
    }

    /// Consumes a byte run in one loop: one peek per byte, no decision and
    /// no recursion. Any other byte ends the run, and the caller reports it if
    /// it cannot follow. The loop needs no handling for the 0x03 the
    /// indentation lexer may leave after a dedent: it is only ever emitted
    /// right after block_end (0x02), which already ended the run.
    fn emitByteRunLoop(self: *Generator, writer: *std.Io.Writer, bytes: []const u8) EmitError!void {
        if (self.uses_explicit_recovery) try writer.writeAll("    _ = occurrence_recovery;\n");
        try writer.writeAll("    while (true) {\n        switch (context.head(u8, 0)) {\n            ");
        for (bytes, 0..) |byte, index| {
            if (index != 0) try writer.writeAll(", ");
            try writer.print("{d}", .{byte});
        }
        try writer.writeAll(" => context.releaseToken(1),\n            else => break,\n        }\n    }\n");
    }

    fn collectDecisionRules(allocator: std.mem.Allocator, node: *const switch_planning.Node, rule_indices: *std.ArrayList(usize)) EmitError!void {
        if (node.fallback) |rule_index| {
            if (std.mem.indexOfScalar(usize, rule_indices.items, rule_index) == null) try rule_indices.append(allocator, rule_index);
        }
        for (node.groups.items) |group| try collectDecisionRules(allocator, group.child, rule_indices);
    }

    /// What the leaves of a decision select.
    const DecisionKind = enum {
        /// The index of the rule to parse. Input no rule accepts is a syntax error.
        rule,
        /// Whether another repetition of a self-repeating rule follows. Input
        /// no rule accepts ends the repetition.
        repetition,
    };

    /// Emits `const <selected>: <type> = <label>: { ... };` and returns the
    /// constant's name. The byte-switch inside only breaks out of the label
    /// with a leaf's value (or returns, for a syntax error).
    fn emitDecision(self: *Generator, writer: *std.Io.Writer, kind: DecisionKind, symbol_index: usize, node: *const switch_planning.Node, indent: []const u8, skip_ast_construction: bool) EmitError![]const u8 {
        // Labels only need to be unique within one generated function; the
        // function renderers reset the count so per-configuration bodies stay
        // textually identical and deduplicate.
        const id = self.decision_count;
        self.decision_count += 1;
        const label = try std.fmt.allocPrint(self.allocator, "decision_{d}", .{id});
        const selected = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ switch (kind) {
            .rule => "selected_rule",
            .repetition => "repeats",
        }, id });
        try writer.print("{s}const {s}: {s} = {s}: {{\n", .{ indent, selected, switch (kind) {
            .rule => "usize",
            .repetition => "bool",
        }, label });
        try self.emitDecisionSwitch(writer, .{
            .generator = self,
            .kind = kind,
            .symbol_index = symbol_index,
            .node = node,
            .prefix_length = 0,
            .indent = try indented(self.allocator, indent, 4),
            .skip_ast_construction = skip_ast_construction,
            .label = label,
        });
        try writer.print("\n{s}}};\n", .{indent});
        return selected;
    }

    const DecisionContext = struct {
        generator: *Generator,
        kind: DecisionKind,
        symbol_index: usize,
        node: *const switch_planning.Node,
        prefix_length: usize,
        indent: []const u8,
        skip_ast_construction: bool,
        label: []const u8,

        fn writeLeaf(self: DecisionContext, writer: *std.Io.Writer, rule_index: usize) EmitError!void {
            switch (self.kind) {
                .rule => try writer.print("break :{s} {d}", .{ self.label, rule_index }),
                .repetition => try writer.print("break :{s} true", .{self.label}),
            }
        }
    };

    fn emitDecisionSwitch(self: *Generator, writer: *std.Io.Writer, context: DecisionContext) EmitError!void {
        if (context.node.groups.items.len == 0) {
            if (context.node.fallback) |rule_index| {
                try writer.writeAll(context.indent);
                try context.writeLeaf(writer, rule_index);
                try writer.writeByte(';');
                return;
            }
            if (context.kind == .repetition) {
                try writer.print("{s}break :{s} false;", .{ context.indent, context.label });
                return;
            }
        }
        try emitter_common.emitMergedSwitch(
            DecisionContext,
            EmitError,
            self.allocator,
            writer,
            context.node,
            context.prefix_length,
            context.indent,
            context,
            renderDecisionProngBody,
            renderDecisionFallbackBody,
            renderDecisionElse,
        );
    }

    fn renderDecisionProngBody(context: DecisionContext, buffer: *std.Io.Writer, group_index: usize) EmitError!void {
        const group = context.node.groups.items[group_index];
        if (group.child.isLeaf()) {
            try buffer.print("{s}        ", .{context.indent});
            try context.writeLeaf(buffer, group.child.fallback.?);
            try buffer.writeAll(";\n");
            return;
        }
        var child = context;
        child.node = group.child;
        child.prefix_length = context.prefix_length + context.node.step_length;
        child.indent = try indented(context.generator.allocator, context.indent, 8);
        try context.generator.emitDecisionSwitch(buffer, child);
        try buffer.writeByte('\n');
    }

    fn renderDecisionFallbackBody(context: DecisionContext, buffer: *std.Io.Writer) EmitError!void {
        try buffer.print("{s}        ", .{context.indent});
        try context.writeLeaf(buffer, context.node.fallback.?);
        try buffer.writeAll(";\n");
    }

    fn renderDecisionElse(context: DecisionContext, writer: *std.Io.Writer) EmitError!void {
        if (context.node.fallback) |rule_index| {
            try writer.print("{s}    else => ", .{context.indent});
            try context.writeLeaf(writer, rule_index);
            try writer.writeAll(",\n");
            return;
        }
        switch (context.kind) {
            .rule => try context.generator.emitSyntaxErrorElse(writer, context.node, context.indent),
            .repetition => try writer.print("{s}    else => break :{s} false,\n", .{ context.indent, context.label }),
        }
    }

    fn emitTransparentTailLeaf(
        self: *Generator,
        writer: *std.Io.Writer,
        tail: usize,
        tail_rule_index: usize,
        indent: []const u8,
        context: TransparentInlineContext,
    ) EmitError!void {
        const tail_rule = self.rules.items[tail_rule_index];
        const leaf_indent = try indented(self.allocator, indent, 8);
        try self.emitDebugRuleExpansion(writer, tail_rule, tail, leaf_indent);
        const base_slot = self.expandedChildSlot(context.parent_rule, context.tail_position);
        defer self.in_last_position = false;
        for (tail_rule.rhs.items, 0..) |symbol_index, suffix_index| {
            self.in_last_position = context.in_last_position and suffix_index + 1 == tail_rule.rhs.items.len;
            try self.emitChildParseLine(
                writer,
                symbol_index,
                tail,
                tail_rule,
                suffix_index,
                context.parent,
                context.parent_address,
                leaf_indent,
                context.skip_ast_construction,
                base_slot + self.expandedChildSlot(tail_rule, suffix_index),
            );
        }
    }

    fn emitVerbatimTerminatorStart(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, indent: []const u8) !void {
        if (self.verbatim_literal != null or self.symbols.items[symbol_index].kind == .terminal) return;
        try writer.print("{s}const verbatim_start = context.currentTokenSourceOffset();\n", .{indent});
    }

    fn emitVerbatimCapture(self: *Generator, writer: *std.Io.Writer, symbol_index: usize, indent: []const u8) !void {
        const child = self.symbols.items[symbol_index];
        if (self.verbatim_literal) |literal| {
            try writer.print("{s}try context.captureVerbatim(", .{indent});
            try common.emitStringLiteral(writer, literal);
            try writer.print(", {s});\n", .{if (self.verbatim_consume) "true" else "false"});
        } else if (child.kind == .terminal) {
            try writer.print("{s}try context.captureVerbatim(", .{indent});
            try common.emitStringLiteral(writer, child.id);
            try writer.writeAll(", true);\n");
        } else {
            try writer.print("{s}const verbatim_terminator = context.getTextSlice(verbatim_start, context.currentTokenSourceOffset() - verbatim_start);\n", .{indent});
            try writer.print("{s}try context.captureVerbatim(verbatim_terminator, true);\n", .{indent});
        }
    }

    fn emitExplicitRuleCatch(self: *Generator, writer: *std.Io.Writer, rule: Rule, parent_variable: usize, skip_ast_construction: bool, indent: []const u8, inner_level: ?[]const u8) !void {
        const rule_index = self.ruleIndex(rule);
        try writer.writeAll(") catch |err| switch (err) {\n");
        try writer.print("{s}        error.ExplicitSyntaxRecovery => {{\n", .{indent});
        try writer.print("{s}            if (try llTryRecoveryRule_{d}(context, {s})) {{\n", .{ indent, rule_index, self.occurrenceRecoveryName() });
        const recovered_indent = try indented(self.allocator, indent, 16);
        if (self.symbolReturnsNode(parent_variable, skip_ast_construction)) {
            try self.emitLevelReturn(writer, recovered_indent, if (self.options.with_ast) recoveredNodeExpression(inner_level) else self.missingNode());
        } else {
            try self.emitLevelReturn(writer, recovered_indent, null);
        }
        try writer.print("{s}            }}\n", .{indent});
        try self.emitLevelFailure(writer, try indented(self.allocator, indent, 12));
        try writer.print("{s}        }},\n{s}        else => return err,\n{s}    }}", .{ indent, indent, indent });
    }

    fn emitChildOccurrenceArgument(self: *Generator, writer: *std.Io.Writer, rule: Rule, child_index: usize, child_returns_node: bool) !void {
        if (self.has_occurrence_procedures) {
            try writer.writeAll(", ");
            if (child_returns_node) {
                try emitter_common.emitProcedureSequenceExpression(writer, &self.plan.hooks, rule.rhs_annotations.items[child_index].procedures.items);
            } else {
                try writer.writeAll("null");
            }
        }
        if (self.uses_explicit_recovery) {
            try writer.writeAll(", ");
            const symbol_index = rule.rhs.items[child_index];
            if (self.symbols.items[symbol_index].kind == .variable and
                rule.rhs_annotations.items[child_index].recovery_points.items.len != 0)
            {
                try self.emitOccurrenceRecoveryScope(writer, rule, child_index);
            } else {
                try writer.writeAll("null");
            }
        }
    }

    fn emitProcedureBlock(self: *Generator, writer: *std.Io.Writer, rule_index: usize, parent_variable: usize, node_expr: []const u8, occurrence_expr: []const u8, indent: []const u8, include_outcome: bool) !void {
        const variable_index = self.variableIndex(parent_variable);
        try emitter_common.emitProcedureArgsStruct(writer, indent, self.options.with_ast, rule_index, node_expr, true);
        if (self.has_occurrence_procedures) {
            try writer.print("{s}try runProcedureSequence({s}, &args);\n", .{ indent, occurrence_expr });
        }
        try emitter_common.emitProcedureRuleSequenceCall(writer, indent, &self.plan.hooks, self.rules.items[rule_index].annotations.procedures.items);
        try emitter_common.emitProcedureDispatchTail(writer, indent, rule_index, variable_index, parent_variable, null);
        if (include_outcome and self.options.with_ast) {
            try writer.print(
                \\
                \\{s}if (comptime builtin.mode == .debug) {{
                \\{s}    if (context.verbosityLevel() > 2) {{
                \\{s}        std.debug.print("Procedure outcome for
            , .{ indent, indent, indent });
            try writer.writeAll(" ");
            try emitFormatToken(writer, self.symbols.items[parent_variable].id);
            try writer.print(
                \\: {{f}}\n", .{{
                \\{s}            string_utilities.fmtNode(args.node_address, context),
                \\{s}        }});
                \\{s}    }}
                \\{s}}}
                \\
            , .{ indent, indent, indent, indent });
        }
    }

    fn emitTerminalProcedureBlock(self: *Generator, writer: *std.Io.Writer, terminal_index: usize, node_expr: []const u8, occurrence_expr: []const u8, indent: []const u8) !void {
        try emitter_common.emitProcedureArgsStruct(writer, indent, self.options.with_ast, null, node_expr, false);
        if (self.has_occurrence_procedures) {
            try writer.print("{s}try runProcedureSequence({s}, &args);\n", .{ indent, occurrence_expr });
        }
        try emitter_common.emitProcedureDispatchTail(writer, indent, null, null, null, terminal_index);
    }

    fn emitDebugRuleExpansion(self: *Generator, writer: *std.Io.Writer, rule: Rule, parent_variable: usize, indent: []const u8) !void {
        try writer.print(
            \\{s}if (comptime builtin.mode == .debug) {{
            \\{s}    if (context.verbosityLevel() > 1) {{
            \\{s}        std.debug.print("Rule expansion:
        , .{ indent, indent, indent });
        try writer.writeAll(" ");
        try emitFormatToken(writer, self.symbols.items[parent_variable].id);
        try writer.writeAll(" -> ");
        try emitter_common.emitRuleSymbolsForDebug(writer, self.symbols.items, rule);
        try writer.print(
            \\\n", .{{}});
            \\{s}    }}
            \\{s}}}
            \\
        , .{ indent, indent });
    }

    fn emitSymbolRepr(self: *Generator, writer: *std.Io.Writer, symbol_index: usize) !void {
        try writer.writeAll(self.plan.symbol_names.reprs[symbol_index]);
    }

    fn variableIndex(self: *Generator, symbol_index: usize) usize {
        return self.plan.variable_indices[symbol_index] orelse unreachable;
    }

    fn ruleIndex(self: *Generator, needle: Rule) usize {
        for (self.rules.items, 0..) |rule, index| {
            if (rule.header == needle.header and std.mem.eql(u8, rule.rhs_index, needle.rhs_index)) return index;
        }
        unreachable;
    }

    fn longestTerminalLength(self: *Generator) usize {
        return self.plan.longest_terminal_length;
    }
};

pub fn emit(
    allocator: std.mem.Allocator,
    grammar: *const common.PreparedGrammar,
    plan: *const LLPlan,
    writer: *std.Io.Writer,
    options: Options,
) !void {
    var generator = Generator.init(allocator, options, grammar, plan);
    try generator.emit(writer);
}
