const std = @import("std");
const common = @import("generator_common");

/// Writes the procedure-module lookup name for one grammar annotation.
/// Every author-written hook — standard tree helpers included — is emitted
/// under the generated `hook_` namespace so its declaration cannot collide
/// with unrelated symbols such as libc's; only the generator-invented
/// reduction names keep their established `reduction_` spelling.
fn emitProcedureLookupName(writer: *std.Io.Writer, name: []const u8) !void {
    try writer.writeAll("\"hook_\" ++ ");
    try common.emitStringLiteral(writer, name);
}

pub fn emitRecoveryOffsetFunction(writer: *std.Io.Writer, function_name: []const u8) !void {
    try writer.print(
        \\fn {s}(context: *data_structures.Context, candidates: []const []const u8, start: usize) !?usize {{
        \\    const lookahead = try context.recoveryLookahead();
        \\    if (candidates.len == 0) {{
        \\        if (lookahead[0] == 0) context.finishSyntaxRecovery();
        \\        return null;
        \\    }}
        \\    const upper = @min(context.recoveryWindow(), lookahead.len);
        \\    var offset = start;
        \\    while (offset < upper) : (offset += 1) {{
        \\        for (candidates) |candidate| {{
        \\            if (candidate.len <= lookahead.len - offset and std.mem.eql(u8, lookahead[offset..][0..candidate.len], candidate)) {{
        \\                context.finishSyntaxRecovery();
        \\                return offset;
        \\            }}
        \\        }}
        \\        if (lookahead[offset] == 0) break;
        \\    }}
        \\    if (lookahead[0] == 0) context.finishSyntaxRecovery();
        \\    return null;
        \\}}
        \\
    , .{function_name});
}

pub fn emitRecoveryPoints(writer: *std.Io.Writer, points: []const common.RecoveryPoint) !void {
    try writer.writeAll("&[_]root.SyntaxRecoveryPoint{");
    for (points, 0..) |point, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.writeAll(".{ .terminal = ");
        try common.emitStringLiteral(writer, point.terminal);
        try writer.print(", .@\"resume\" = .{s} }}", .{@tagName(point.@"resume")});
    }
    try writer.writeByte('}');
}

/// Emits the generated `ExplicitRecoveryScope` struct declaration shared
/// verbatim by the LL and LR backends.
pub fn emitExplicitRecoveryScopeStruct(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\const ExplicitRecoveryScope = struct {
        \\    id: usize,
        \\    target: root.SyntaxRecoveryTarget,
        \\    points: []const root.SyntaxRecoveryPoint,
        \\};
        \\
    );
}

/// Emits the `&ExplicitRecoveryScope{...}` literal for a variable's own
/// recovery points, shared verbatim by the LL and LR backends.
pub fn emitLhsRecoveryScope(writer: *std.Io.Writer, scopes: *const common.RecoveryPlan, symbols: []const common.Symbol, variable: usize) !void {
    const scope = scopes.findLhs(variable) orelse unreachable;
    try writer.print("&ExplicitRecoveryScope{{ .id = {d}, .target = .{{ .lhs_variable = ", .{scope.id});
    try common.emitStringLiteral(writer, symbols[variable].id);
    try writer.writeAll(" }, .points = ");
    try emitRecoveryPoints(writer, symbols[variable].annotations.recovery_points.items);
    try writer.writeAll(" }");
}

/// Emits the `&ExplicitRecoveryScope{...}` literal for a rule production's
/// recovery points, shared verbatim by the LL and LR backends.
pub fn emitProductionRecoveryScope(writer: *std.Io.Writer, scopes: *const common.RecoveryPlan, symbols: []const common.Symbol, rule: common.Rule, rule_index: usize) !void {
    const scope = scopes.findProduction(rule_index) orelse unreachable;
    try writer.print("&ExplicitRecoveryScope{{ .id = {d}, .target = .{{ .production = .{{ .variable = ", .{scope.id});
    try common.emitStringLiteral(writer, symbols[rule.header].id);
    try writer.print(", .rhs_index = {s} }} }}, .points = ", .{rule.rhs_index});
    try emitRecoveryPoints(writer, rule.annotations.recovery_points.items);
    try writer.writeAll(" }");
}

/// Emits the fail-fast syntax error support block shared verbatim by the LL
/// and LR backends (emitted when error recovery is disabled). `function_prefix`
/// is the backend lowercase prefix (`ll`/`lr`), `renderer_decl` is the renderer
/// type name prefix (`LL`/`LR`), and `error_messages_decl` is the decl name in
/// the generated error messages namespace (`syntax_error_ll`/`syntax_error_lr`).
pub fn emitFailFastSyntaxErrorSupport(writer: *std.Io.Writer, function_prefix: []const u8, renderer_decl: []const u8, error_messages_decl: []const u8) !void {
    try writer.print(
        \\const {s}FailFastMessageRenderer = *const fn (root.SyntaxErrorMessageArgs) anyerror![]const u8;
        \\
        \\fn {s}FailFastSyntaxError(
        \\    context: *data_structures.Context,
        \\    diagnostic_context: root.SyntaxDiagnosticContext,
        \\    expected_tokens: []const []const u8,
        \\    render_message: {s}FailFastMessageRenderer,
        \\) linksection(if (builtin.os.tag == .macos) "__TEXT,__unlikely" else ".text.unlikely") anyerror {{
        \\    @branchHint(.cold);
        \\    context.recordSyntaxDiagnostic(diagnostic_context, expected_tokens) catch |err| return err;
        \\    const diagnostic_message = render_message(.{{
        \\        .allocator = context.runtime().arena_allocator,
        \\        .context = context,
        \\        .diagnostic = context.runtime().lastDiagnostic().?,
        \\        .style = .plain,
        \\    }}) catch "";
        \\    context.runtime().last_rendered_message = diagnostic_message;
        \\    if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{{s}}", .{{diagnostic_message}});
        \\    return root.ParseError.SyntaxError;
        \\}}
        \\
        \\fn {s}FailFastDefaultMessage(args: root.SyntaxErrorMessageArgs) linksection(if (builtin.os.tag == .macos) "__TEXT,__unlikely" else ".text.unlikely") anyerror![]const u8 {{
        \\    @branchHint(.cold);
        \\    if (args.context.runtime().resolveMessageOverride(args.diagnostic, root.config.error_messages)) |overridden| return overridden;
        \\    if (comptime @hasDecl(error_messages, "{s}"))
        \\        return error_messages.{s}(args);
        \\    if (comptime @hasDecl(error_messages, "syntax_error"))
        \\        return error_messages.syntax_error(args);
        \\    return root.renderParseDiagnostic(args.allocator, args.diagnostic, args.style);
        \\}}
        \\
    , .{ renderer_decl, function_prefix, renderer_decl, function_prefix, error_messages_decl, error_messages_decl });
}

/// Emits a fail-fast syntax error message renderer function shared by the LL
/// and LR backends. `error_message_fields` is the ordered list of error
/// messages namespace decls to try before `fallback_message_function`.
pub fn emitFailFastMessageRenderer(writer: *std.Io.Writer, function_name: []const u8, error_message_fields: []const []const u8, fallback_message_function: []const u8) !void {
    try writer.print("fn {s}_message(args: root.SyntaxErrorMessageArgs) linksection(if (builtin.os.tag == .macos) \"__TEXT,__unlikely\" else \".text.unlikely\") anyerror![]const u8 {{\n", .{function_name});
    try writer.writeAll("    if (root.resolveSyntaxErrorMessage(args.context, args.diagnostic, root.config.error_messages, error_messages, .{");
    for (error_message_fields, 0..) |field, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.print("\"{s}\"", .{field});
    }
    try writer.writeAll("})) |message| return message;\n");
    try writer.print("    return {s}(args);\n}}\n\n", .{fallback_message_function});
}

/// Emits the standalone customization file from completed diagnostic plans.
pub fn emitErrorMessageFile(
    writer: *std.Io.Writer,
    parser_label: []const u8,
    specs: []const common.ErrorMessageSpec,
) !void {
    try writer.print(
        \\const root = @import("galley");
        \\
        \\// Default {s} syntax error messages generated by Galley.
        \\// Edit any function body to customize that error site.
        \\
        \\
    , .{parser_label});
    for (specs) |spec| {
        try writer.print(
            \\pub fn {s}(args: root.SyntaxErrorMessageArgs) ![]const u8 {{
            \\    return try root.renderParseDiagnostic(args.allocator, args.diagnostic, args.style);
            \\}}
            \\
            \\
        , .{spec.name});
    }
}

/// Recovery styles a generated function body can be rendered under. Shared
/// by the LL and LR emitters' mode-gated body driver.
pub const BodyRecoveryMode = enum { disabled, automatic, explicit };

// Boolean minimization for the 4-variable selector used by `emitModeGatedBody`.
// Variables (bit positions): 0 = is_ast_enabled, 1 = are_procedures_enabled,
// 2 = ast_for_terminals, 3 = error_recovery_mode == .disabled (vs active).
// The active recovery label is `.explicit` when the grammar uses explicit
// recovery otherwise `.automatic`. Universe is 16 minterms.
const MintermMask = u16;
const Cube = struct { dontCare: u4, value: u4 };

fn cubeCovers(cube: Cube, minterm: u4) bool {
    const care: u4 = ~cube.dontCare;
    return (minterm & care) == (cube.value & care);
}

fn cubeCoverMask(cube: Cube) MintermMask {
    var mask: MintermMask = 0;
    for (0..16) |m| {
        if (cubeCovers(cube, @as(u4, @intCast(m)))) mask |= @as(MintermMask, 1) << @intCast(m);
    }
    return mask;
}

fn cubeLiteralCount(cube: Cube) usize {
    return 4 - @popCount(cube.dontCare);
}

fn cubeSubsumes(small: Cube, big: Cube) bool {
    if (small.dontCare == big.dontCare and small.value == big.value) return false;
    if ((small.dontCare | big.dontCare) != big.dontCare) return false;
    const careBig: u4 = ~big.dontCare;
    if ((small.value & careBig) != (big.value & careBig)) return false;
    return true;
}

fn emitCubeLiterals(writer: *std.Io.Writer, cube: Cube, uses_explicit: bool) !void {
    // Fixed order: mode, ast, procedures, ast_for_terminals — matches the
    // original gate order so diffs stay readable.
    var first = true;
    const active_label: []const u8 = if (uses_explicit) "explicit" else "automatic";
    if ((cube.dontCare >> 3) & 1 == 0) {
        const is_disabled = (cube.value >> 3) & 1 == 1;
        if (!first) try writer.writeAll(" and ");
        if (is_disabled) try writer.writeAll("error_recovery_mode == .disabled") else try writer.print("error_recovery_mode == .{s}", .{active_label});
        first = false;
    }
    if ((cube.dontCare >> 0) & 1 == 0) {
        const v = (cube.value >> 0) & 1 == 1;
        if (!first) try writer.writeAll(" and ");
        try writer.writeAll(if (v) "is_ast_enabled" else "!is_ast_enabled");
        first = false;
    }
    if ((cube.dontCare >> 1) & 1 == 0) {
        const v = (cube.value >> 1) & 1 == 1;
        if (!first) try writer.writeAll(" and ");
        try writer.writeAll(if (v) "are_procedures_enabled" else "!are_procedures_enabled");
        first = false;
    }
    if ((cube.dontCare >> 2) & 1 == 0) {
        const v = (cube.value >> 2) & 1 == 1;
        if (!first) try writer.writeAll(" and ");
        try writer.writeAll(if (v) "ast_for_terminals" else "!ast_for_terminals");
        first = false;
    }
    if (first) try writer.writeAll("true");
}

fn emitMinimizedCondition(writer: *std.Io.Writer, onSetMask: MintermMask, uses_explicit: bool) !void {
    const allMask: MintermMask = 0xFFFF;
    if (onSetMask == 0) {
        try writer.writeAll("false");
        return;
    }
    if (onSetMask == allMask) {
        try writer.writeAll("true");
        return;
    }
    const offSetMask: MintermMask = (~onSetMask) & allMask;

    // Enumerate all 3^4 = 81 cubes and keep those that are implicants of onSet.
    var implicants: [81]Cube = undefined;
    var implicantMasks: [81]MintermMask = undefined;
    var implicantCount: usize = 0;
    for (0..16) |dc| {
        const dontCare: u4 = @intCast(dc);
        for (0..16) |v| {
            const value: u4 = @intCast(v);
            if ((value & dontCare) != 0) continue;
            const cube: Cube = .{ .dontCare = dontCare, .value = value };
            const cover = cubeCoverMask(cube);
            if (cover == 0) continue;
            if ((cover & onSetMask) == 0) continue;
            if ((cover & offSetMask) != 0) continue;
            implicants[implicantCount] = cube;
            implicantMasks[implicantCount] = cover;
            implicantCount += 1;
        }
    }

    // Keep only prime implicants (not strictly subsumed by another implicant).
    var primes: [81]Cube = undefined;
    var primeMasks: [81]MintermMask = undefined;
    var primeCount: usize = 0;
    for (0..implicantCount) |i| {
        var subsumed = false;
        for (0..implicantCount) |j| {
            if (i == j) continue;
            if (cubeSubsumes(implicants[i], implicants[j])) {
                subsumed = true;
                break;
            }
        }
        if (!subsumed) {
            primes[primeCount] = implicants[i];
            primeMasks[primeCount] = implicantMasks[i];
            primeCount += 1;
        }
    }

    // Find minimal cover: fewest cubes, then fewest literals.
    // Universe is tiny — brute force over subsets when primeCount <= 22
    // (2^22 ~ 4M iterations), otherwise fall back to branch-and-bound.
    var bestSubset: u32 = 0;
    var bestCount: usize = primeCount + 1;
    var bestLits: usize = 1_000_000;
    var found = false;

    if (primeCount <= 22) {
        const total: usize = @as(usize, 1) << @intCast(primeCount);
        for (1..total) |subset| {
            const cnt = @popCount(subset);
            if (cnt > bestCount) continue;
            var unionMask: MintermMask = 0;
            var lits: usize = 0;
            for (0..primeCount) |pi| {
                if ((subset >> @intCast(pi)) & 1 == 1) {
                    unionMask |= primeMasks[pi];
                    lits += cubeLiteralCount(primes[pi]);
                }
            }
            if (unionMask != onSetMask) continue;
            if (!found or cnt < bestCount or (cnt == bestCount and lits < bestLits)) {
                bestCount = cnt;
                bestLits = lits;
                bestSubset = @intCast(subset);
                found = true;
            }
        }
    }
    if (!found) {
        // Branch-and-bound fallback for larger prime sets (should be rare for 4 vars).
        var currentCover: [81]Cube = undefined;
        var currentMasks: [81]MintermMask = undefined;
        var bestCover: [81]Cube = undefined;
        var bestCoverLen: usize = primeCount + 1;
        var bestCoverLits: usize = 1_000_000;
        // Simple DFS using explicit stack / recursion via function.
        // Implemented as recursive closure through a helper.
        const Search = struct {
            fn dfs(
                onSet: MintermMask,
                primesInner: []const Cube,
                primeMasksInner: []const MintermMask,
                uncovered: MintermMask,
                start: usize,
                currentLen: usize,
                currentLits: usize,
                currentCoverInner: []Cube,
                currentMasksInner: []MintermMask,
                bestCoverInner: []Cube,
                bestLen: *usize,
                bestLitsInner: *usize,
                bestSubsetInner: *u32,
            ) void {
                if (uncovered == 0) {
                    if (currentLen < bestLen.* or (currentLen == bestLen.* and currentLits < bestLitsInner.*)) {
                        bestLen.* = currentLen;
                        bestLitsInner.* = currentLits;
                        @memcpy(bestCoverInner[0..currentLen], currentCoverInner[0..currentLen]);
                        // Encode as bitmask for later emission (only valid when primeCount <=32)
                        var mask: u32 = 0;
                        for (0..currentLen) |k| {
                            for (primesInner, 0..) |p, idx| {
                                if (p.dontCare == currentCoverInner[k].dontCare and p.value == currentCoverInner[k].value) {
                                    mask |= @as(u32, 1) << @intCast(idx);
                                    break;
                                }
                            }
                        }
                        bestSubsetInner.* = mask;
                    }
                    return;
                }
                if (currentLen >= bestLen.*) return;
                // Pick first uncovered minterm to branch on.
                const bit: u4 = @intCast(@ctz(uncovered));
                for (start..primesInner.len) |pi| {
                    if ((primeMasksInner[pi] >> bit) & 1 == 0) continue;
                    currentCoverInner[currentLen] = primesInner[pi];
                    currentMasksInner[currentLen] = primeMasksInner[pi];
                    dfs(
                        onSet,
                        primesInner,
                        primeMasksInner,
                        uncovered & ~primeMasksInner[pi],
                        pi + 1,
                        currentLen + 1,
                        currentLits + cubeLiteralCount(primesInner[pi]),
                        currentCoverInner,
                        currentMasksInner,
                        bestCoverInner,
                        bestLen,
                        bestLitsInner,
                        bestSubsetInner,
                    );
                }
            }
        };
        Search.dfs(onSetMask, primes[0..primeCount], primeMasks[0..primeCount], onSetMask, 0, 0, 0, &currentCover, &currentMasks, &bestCover, &bestCoverLen, &bestCoverLits, &bestSubset);
        bestCount = bestCoverLen;
        bestLits = bestCoverLits;
        found = bestCount <= primeCount;
    }

    if (!found) {
        // Fallback: emit naive disjunction (should never happen).
        var first = true;
        for (0..16) |m| {
            if ((onSetMask >> @intCast(m)) & 1 == 0) continue;
            if (!first) try writer.writeAll(" or ");
            const cube: Cube = .{ .dontCare = 0, .value = @intCast(m) };
            try emitCubeLiterals(writer, cube, uses_explicit);
            first = false;
        }
        return;
    }

    // Collect selected cubes.
    var cover: [81]Cube = undefined;
    var coverCount: usize = 0;
    for (0..primeCount) |pi| {
        if ((bestSubset >> @intCast(pi)) & 1 == 1) {
            cover[coverCount] = primes[pi];
            coverCount += 1;
        }
    }
    // Deterministic order: fewer literals first, then dontCare/value for stability.
    for (0..coverCount) |i| {
        for (i + 1..coverCount) |j| {
            const li = cubeLiteralCount(cover[i]);
            const lj = cubeLiteralCount(cover[j]);
            const shouldSwap = lj < li or (lj == li and (cover[j].dontCare < cover[i].dontCare or (cover[j].dontCare == cover[i].dontCare and cover[j].value < cover[i].value)));
            if (shouldSwap) {
                const tmp = cover[i];
                cover[i] = cover[j];
                cover[j] = tmp;
            }
        }
    }

    if (coverCount == 1) {
        try emitCubeLiterals(writer, cover[0], uses_explicit);
        return;
    }
    for (cover[0..coverCount], 0..) |cube, idx| {
        if (idx != 0) try writer.writeAll(" or ");
        const lits = cubeLiteralCount(cube);
        if (lits > 1) try writer.writeAll("(");
        try emitCubeLiterals(writer, cube, uses_explicit);
        if (lits > 1) try writer.writeAll(")");
    }
}

/// Renders one generated function body under every configuration that
/// `config.zig` can select, deduplicates identical texts, and emits them
/// chained behind `comptime` gates on the generated constants. Exactly
/// one branch is analyzed per compilation; disabled branches cost
/// nothing. This is what makes the generated file independent of the
/// options present at generation time.
///
/// Shared single implementation: both parser-family emitters delegate here.
/// The generator type must expose `allocator`, mutable `options`
/// (`with_ast`, `with_procedures`, `ast_for_terminals`,
/// `with_error_recovery`), and fact `uses_explicit_recovery`.
pub fn emitModeGatedBody(
    comptime Generator: type,
    generator: *Generator,
    writer: *std.Io.Writer,
    comptime Params: type,
    params: Params,
    has_occurrence_procedures_parameter: bool,
    comptime render_fn: fn (*Generator, *std.Io.Writer, Params) anyerror!void,
) !void {
    const Combo = struct {
        ast: bool,
        procedures: bool,
        terminals: bool,
        mode: BodyRecoveryMode,
    };
    // Every configuration dimension a body's shape can depend on. Four
    // dimensions ⇒ up to 24 renders; identical bodies deduplicate, and
    // irrelevant dimensions collapse naturally (e.g. terminals is inert
    // when no symbol returns nodes).
    var all_combos: [24]Combo = undefined;
    var combo_count: usize = 0;
    const modes = [_]BodyRecoveryMode{ .explicit, .automatic, .disabled };
    const bools = [_]bool{ true, false };
    for (modes) |mode| {
        for (bools) |ast| {
            for (bools) |procedures| {
                for (bools) |terminals| {
                    all_combos[combo_count] = .{
                        .ast = ast,
                        .procedures = procedures,
                        .terminals = terminals,
                        .mode = mode,
                    };
                    combo_count += 1;
                }
            }
        }
    }
    const saved_options = generator.options;
    defer generator.options = saved_options;

    var texts: [all_combos.len][]const u8 = undefined;
    var groupMasks: [all_combos.len]MintermMask = undefined;
    var kept_count: usize = 0;
    for (all_combos[0..combo_count]) |combo| {
        generator.options.with_ast = combo.ast;
        generator.options.with_procedures = combo.procedures;
        generator.options.ast_for_terminals = combo.terminals;
        generator.options.with_error_recovery = combo.mode != .disabled;
        var buffer = std.Io.Writer.Allocating.init(generator.allocator);
        defer buffer.deinit();
        try render_fn(generator, &buffer.writer, params);
        const rendered = buffer.written();
        const text = if (has_occurrence_procedures_parameter and
            std.mem.indexOf(u8, rendered, "occurrence_procedures") == null)
            try std.fmt.allocPrint(
                generator.allocator,
                "    _ = &occurrence_procedures;\n{s}",
                .{rendered},
            )
        else
            try generator.allocator.dupe(u8, rendered);
        var duplicate_index: ?usize = null;
        for (texts[0..kept_count], 0..) |existing, gi| {
            if (std.mem.eql(u8, existing, text)) {
                duplicate_index = gi;
                break;
            }
        }
        // Map to 4-bit minterm: bit0 ast, bit1 procedures, bit2 terminals,
        // bit3 is_disabled (explicit/automatic collapse to 0).
        const minterm: u4 = @as(u4, if (combo.ast) 1 else 0) |
            (@as(u4, if (combo.procedures) 1 else 0) << 1) |
            (@as(u4, if (combo.terminals) 1 else 0) << 2) |
            (@as(u4, if (combo.mode == .disabled) 1 else 0) << 3);
        const bit: MintermMask = @as(MintermMask, 1) << minterm;
        if (duplicate_index) |gi| {
            generator.allocator.free(text);
            groupMasks[gi] |= bit;
        } else {
            texts[kept_count] = text;
            groupMasks[kept_count] = bit;
            kept_count += 1;
        }
    }

    const allMask: MintermMask = 0xFFFF;
    // Single distinct body that covers the whole universe needs no gate.
    if (kept_count == 1 and groupMasks[0] == allMask) {
        try writer.writeAll(texts[0]);
        return;
    }

    for (texts[0..kept_count], groupMasks[0..kept_count], 0..) |text, mask, index| {
        if (index != 0) try writer.writeAll("} else ");
        try writer.writeAll("if (comptime ");
        try emitMinimizedCondition(writer, mask, generator.uses_explicit_recovery);
        try writer.writeAll(") {\n");
        try writer.writeAll(text);
    }
    try writer.writeAll("}\n");
}

/// Emits the parser metadata header shared by LL and LR generated parsers.
///
/// Option values are no longer baked here: every option is a comptime
/// expression over the consumer's `config.zig`, so changing configuration
/// requires recompilation only — never regeneration. What stays baked is
/// grammar *content* (recovery-annotation presence, verbatim usage, longest
/// terminal) and family capability (parser type, syntax-error stack support).
pub fn emitParserMetadata(
    writer: *std.Io.Writer,
    parser_type: []const u8,
    has_recovery_annotations: bool,
    longest_terminal_length: usize,
    uses_verbatim: bool,
    syntax_error_stack_supported: bool,
) !void {
    try writer.print(
        \\
        \\pub const config = root.config;
        \\pub const parser_type = data_structures.ParserType.{s};
        \\pub const ErrorRecoveryMode = enum {{ disabled, automatic, explicit }};
        \\pub const is_ast_enabled = config.ast;
        \\pub const are_procedures_enabled = config.procedures;
        \\pub const allow_no_ast_tree_procedures = config.allow_no_ast_tree_procedures;
        \\pub const is_error_recovery_enabled = config.error_recovery;
        \\pub const ast_for_terminals = config.ast_for_terminals;
        \\pub const has_recovery_annotations = {};
        \\pub const error_recovery_mode: ErrorRecoveryMode =
        \\    if (!is_error_recovery_enabled) .disabled else if (has_recovery_annotations) .explicit else .automatic;
        \\pub const is_position_tracking_enabled =
        \\    if (config.position_tracking) |enabled| enabled else builtin.mode != .ReleaseFast;
        \\pub const is_input_streaming_enabled = config.input_streaming;
        \\pub const syntax_error_stack_depth = {s};
        \\pub const is_syntax_error_stack_enabled = {s};
        \\{s}pub const longest_terminal_length = {d};
        \\
        \\
    , .{
        parser_type,
        has_recovery_annotations,
        if (syntax_error_stack_supported)
            "root.syntax_error_stack_depth"
        else
            "1",
        if (syntax_error_stack_supported) "syntax_error_stack_depth > 1" else "false",
        if (uses_verbatim) "pub const uses_verbatim = true;\n" else "",
        longest_terminal_length,
    });
}

/// Emits the grammar metadata shared by LL and LR generated parsers.
///
/// The function deliberately preserves the existing table order and source
/// spelling; backends provide only their completed, typed grammar plan.
pub fn emitGrammarTables(
    writer: *std.Io.Writer,
    symbols: []const common.Symbol,
    variables: []const usize,
    rules: []const common.Rule,
    end_symbol: usize,
) !void {
    try writer.writeAll("pub const symbols = &[_][]const u8{\n");
    for (symbols, 0..) |symbol, index| {
        try writer.writeAll("    ");
        try common.emitStringLiteral(writer, symbol.id);
        try writer.print(", // {d}\n", .{index});
    }
    try writer.writeAll("};\n\npub const is_terminal = &[_]bool{\n");
    for (symbols) |symbol| try writer.print("    {},\n", .{symbol.kind != .variable});
    try writer.writeAll("};\n\npub const is_generative_terminal = &[_]bool{\n");
    for (symbols) |symbol| try writer.print("    {},\n", .{symbol.kind == .generative_terminal});
    try writer.writeAll("};\n\npub const is_variable = &[_]bool{\n");
    for (symbols) |symbol| try writer.print("    {},\n", .{symbol.kind == .variable});
    try writer.print("}};\n\npub const end_symbol = {d};\n", .{end_symbol});
    try writer.writeAll("\n/// Per-symbol grammar fact: whether AST construction was enabled for this\n/// symbol by its grammar annotations (`@ast(...)`). Consumed at comptime by\n/// the generated `symbolReturnsNode` derivation.\npub const ast_enabled = &[_]bool{\n");
    for (symbols) |symbol| try writer.print("    {},\n", .{symbol.ast_enabled});
    try writer.writeAll("};\n\n/// Comptime derivation shared by all generated parsers (ruling #1, Option\n/// A): mirrors generator-side `common.symbolReturnsNode`, but reads its\n/// option half from `config.zig` so configuration changes never require\n/// regeneration.\npub fn symbolReturnsNode(comptime symbol_index: usize) bool {\n    if (!is_ast_enabled and !are_procedures_enabled) return false;\n    if (comptime symbol_index == end_symbol) return false;\n    if (comptime is_variable[symbol_index]) return ast_enabled[symbol_index];\n    return ast_for_terminals;\n}\n\npub const variables = &[_][]const u8{\n");
    for (variables) |symbol_index| {
        try writer.writeAll("    ");
        try common.emitStringLiteral(writer, symbols[symbol_index].id);
        try writer.writeAll(",\n");
    }
    try writer.writeAll("};\n\npub const symbol_by_variable = &[_]usize{\n");
    for (variables) |symbol_index| try writer.print("    {d},\n", .{symbol_index});
    try writer.writeAll("};\n\npub const rules = &[_]data_structures.Rule{\n");
    for (rules) |rule| {
        const variable_index = variableIndex(variables, rule.header);
        try writer.print("    data_structures.Rule{{ .header = {d}, .right_hand_side = &[_]u16{{", .{variable_index});
        if (rule.rhs.items.len > 1) try writer.writeByte(' ');
        for (rule.rhs.items, 0..) |symbol_index, i| {
            if (i != 0) try writer.writeAll(", ");
            try writer.print("{d}", .{symbol_index});
        }
        if (rule.rhs.items.len > 1) try writer.writeByte(' ');
        try writer.writeAll("}, .right_hand_side_index = ");
        try common.emitStringLiteral(writer, rule.rhs_index);
        try writer.writeAll(" }, // ");
        try writer.writeAll(symbols[rule.header].id);
        try writer.writeByte('\n');
    }
    try writer.writeAll("};\n\n");
}

fn variableIndex(variables: []const usize, symbol_index: usize) usize {
    for (variables, 0..) |candidate, index| {
        if (candidate == symbol_index) return index;
    }
    unreachable;
}

/// Emits the procedure support declarations shared verbatim by the LL and LR
/// generators. The current node is resolved through the `ProcedureArguments`
/// accessor on each hook phase, so no refresh pass is needed between calls.
pub fn emitProcedureSupport(
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    rules: []const common.Rule,
    symbols: []const common.Symbol,
    variables: []const usize,
) !void {
    try writer.print(
        \\const ProcedureSequenceNode = struct {{
        \\    procedure: *const data_structures.Procedure,
        \\    next: ?*const ProcedureSequenceNode,
        \\}};
        \\
        \\fn makeProcedureSequence(comptime procedure_names: []const []const u8) ?*const ProcedureSequenceNode {{
        \\    if (procedure_names.len == 0) return null;
        \\    const procedure_name = procedure_names[0];
        \\    return &ProcedureSequenceNode{{
        \\        .procedure = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), procedure_name),
        \\        .next = makeProcedureSequence(procedure_names[1..]),
        \\    }};
        \\}}
        \\
        \\fn runProcedureSequence(sequence: ?*const ProcedureSequenceNode, args: *data_structures.ProcedureArguments) !void {{
        \\    var current = sequence;
        \\    while (current) |entry| {{
        \\        const procedure = @as(*data_structures.Procedure, @constCast(entry.procedure));
        \\        try procedure(args);
        \\        current = entry.next;
        \\    }}
        \\}}
        \\
        \\pub const rule_procedures = rule_procedures: {{
        \\    var arr: [{d}]?*const data_structures.Procedure = .{{null}} ** {d};
        \\
        \\    for (rules, 0..) |rule, index| {{
        \\        const procedure_name = "reduction_" ++ variables[rule.header] ++ "_" ++ rule.right_hand_side_index;
        \\        if (@hasDecl(procedures, procedure_name)) {{
        \\            arr[index] = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), procedure_name);
        \\        }}
        \\    }}
        \\
        \\    break :rule_procedures arr;
        \\}};
        \\
        \\pub const symbol_procedures = symbol_procedures: {{
        \\    var arr: [{d}]?*const data_structures.Procedure = .{{null}} ** {d};
        \\
        \\    for (symbols, 0..) |symbol, index| {{
        \\        const procedure_name = "reduction_" ++ symbol;
        \\        if (@hasDecl(procedures, procedure_name)) {{
        \\            arr[index] = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), symbol);
        \\        }}
        \\    }}
        \\
        \\    break :symbol_procedures arr;
        \\}};
        \\
        \\const variable_procedure_names = &[_][]const []const u8{{
        \\
    , .{ rules.len, rules.len, symbols.len, symbols.len });
    for (variables) |symbol_index| {
        const symbol = symbols[symbol_index];
        try writer.writeAll("    &[_][]const u8{");
        for (symbol.annotations.procedures.items, 0..) |procedure, i| {
            if (i != 0) try writer.writeAll(", ");
            try emitProcedureLookupName(writer, procedure);
        }
        try writer.writeAll("},\n");
    }
    try writer.writeAll("};\n");

    // Manifest of every hook this grammar requires through its annotations,
    // emitted under their generated `hook_` lookup names (standard tree
    // helpers included). Binding generators scan it to declare the extern
    // entry points the consumer must implement.
    try writer.writeAll("\npub const user_hook_names = [_][]const u8{");
    var user_hooks: std.ArrayList([]const u8) = .empty;
    defer user_hooks.deinit(allocator);
    for (rules) |rule| {
        try collectUserHooks(allocator, &user_hooks, rule.annotations.procedures.items);
        for (rule.rhs_annotations.items) |annotations| {
            try collectUserHooks(allocator, &user_hooks, annotations.procedures.items);
        }
    }
    for (variables) |symbol_index| {
        try collectUserHooks(allocator, &user_hooks, symbols[symbol_index].annotations.procedures.items);
    }
    for (user_hooks.items) |hook_name| {
        try writer.writeAll("\n    ");
        try common.emitStringLiteral(writer, hook_name);
        try writer.writeAll(",");
    }
    try writer.writeAll("\n};\n");
    try writer.print(
        \\
        \\pub const variable_procedures = variable_procedures: {{
        \\    var arr: [{d}]?*const ProcedureSequenceNode = .{{null}} ** {d};
        \\
        \\    for (variable_procedure_names, 0..) |procedure_names, index| {{
        \\        arr[index] = makeProcedureSequence(procedure_names);
        \\    }}
        \\
        \\    break :variable_procedures arr;
        \\}};
        \\
        \\pub const reduction_procedure: ?*const data_structures.Procedure = if (@hasDecl(procedures, "reduction")) data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, "reduction"), "reduction") else null;
        \\
        \\
    , .{ variables.len, variables.len });
}

/// Appends `hook_`-prefixed hook names to `user_hooks`, skipping names
/// already present.
fn collectUserHooks(
    allocator: std.mem.Allocator,
    user_hooks: *std.ArrayList([]const u8),
    procedures_: []const []const u8,
) !void {
    for (procedures_) |procedure| {
        const hook_name = try std.fmt.allocPrint(allocator, "hook_{s}", .{procedure});
        for (user_hooks.items) |existing| {
            if (std.mem.eql(u8, existing, hook_name)) break;
        } else {
            try user_hooks.append(allocator, hook_name);
        }
    }
}

pub fn emitProcedureSequenceExpression(writer: *std.Io.Writer, procedures_: []const []const u8) !void {
    try writer.writeAll("comptime makeProcedureSequence(&[_][]const u8{");
    for (procedures_, 0..) |procedure, index| {
        if (index != 0) try writer.writeAll(", ");
        try emitProcedureLookupName(writer, procedure);
    }
    try writer.writeAll("})");
}

/// Emits the `var args = data_structures.ProcedureArguments{...};` block shared by
/// the LL and LR backends' procedure call sites. When `rule_index` is present the
/// `.rule` field references the generated rule table; otherwise a `.rule = null`
/// literal is emitted. `trailing_blank` controls an optional blank separator after
/// the closing brace.
pub fn emitProcedureArgsStruct(
    writer: *std.Io.Writer,
    indent: []const u8,
    with_ast: bool,
    rule_index: ?usize,
    node_expr: []const u8,
    trailing_blank: bool,
) !void {
    if (with_ast) {
        if (rule_index) |rule| {
            try writer.print(
                \\{s}var args = data_structures.ProcedureArguments{{
                \\{s}    .context = context,
                \\{s}    .rule = rules[{d}],
                \\{s}    .node_address = {s},
                \\{s}}};
            , .{ indent, indent, indent, rule, indent, node_expr, indent });
        } else {
            try writer.print(
                \\{s}var args = data_structures.ProcedureArguments{{
                \\{s}    .context = context,
                \\{s}    .rule = null,
                \\{s}    .node_address = {s},
                \\{s}}};
            , .{ indent, indent, indent, indent, node_expr, indent });
        }
    } else {
        if (rule_index) |rule| {
            try writer.print(
                \\{s}var args = data_structures.ProcedureArguments{{
                \\{s}    .context = context,
                \\{s}    .rule = rules[{d}],
                \\{s}    ._temp_node = &{s},
                \\{s}}};
            , .{ indent, indent, indent, rule, indent, node_expr, indent });
        } else {
            try writer.print(
                \\{s}var args = data_structures.ProcedureArguments{{
                \\{s}    .context = context,
                \\{s}    .rule = null,
                \\{s}    ._temp_node = &{s},
                \\{s}}};
            , .{ indent, indent, indent, indent, node_expr, indent });
        }
    }
    if (trailing_blank) try writer.writeByte('\n');
}

/// Emits the `{indent}try runProcedureSequence(` prefix of a procedure invocation;
/// the caller writes the procedure/sequence expression, then closes with
/// `, &args);\n`. Shared by the LL and LR backends.
pub fn emitProcedureRunCall(writer: *std.Io.Writer, indent: []const u8) !void {
    try writer.print("{s}try runProcedureSequence(", .{indent});
}

/// Emits a complete `try runProcedureSequence(<rule procedure sequence>, &args);`
/// statement using the rule's own annotation procedures.
pub fn emitProcedureRuleSequenceCall(writer: *std.Io.Writer, indent: []const u8, procedures_: []const []const u8) !void {
    try emitProcedureRunCall(writer, indent);
    try emitProcedureSequenceExpression(writer, procedures_);
    try writer.writeAll(", &args);\n");
}

/// Emits the post-args procedure dispatch tail shared verbatim by the LL and LR
/// backends. The rule variant (all three indices present) is used after a rule
/// reduction; the symbol-only variant is used for terminal procedure blocks.
pub fn emitProcedureDispatchTail(
    writer: *std.Io.Writer,
    indent: []const u8,
    rule_index: ?usize,
    variable_index: ?usize,
    parent_variable: ?usize,
    symbol_index: ?usize,
) !void {
    if (rule_index != null and variable_index != null and parent_variable != null) {
        try writer.print(
            \\{s}if (comptime rule_procedures[{d}]) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\{s}try runProcedureSequence(variable_procedures[{d}], &args);
            \\{s}if (comptime symbol_procedures[{d}]) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\{s}if (comptime reduction_procedure) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\
        , .{
            indent, rule_index.?,     indent, indent,            indent,
            indent, variable_index.?, indent, parent_variable.?, indent,
            indent, indent,           indent, indent,            indent,
            indent,
        });
    } else {
        try writer.print(
            \\{s}if (comptime symbol_procedures[{d}]) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\{s}if (comptime reduction_procedure) |procedure_pointer| {{
            \\{s}    const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            \\{s}    try procedure(&args);
            \\{s}}}
            \\
        , .{
            indent, symbol_index.?, indent, indent, indent,
            indent, indent,         indent, indent,
        });
    }
}

/// Emits a comma-separated rendering of the rule RHS for Debug-mode reduction
/// output, shared verbatim by the LL and LR backends.
pub fn emitRuleSymbolsForDebug(writer: *std.Io.Writer, symbols: []const common.Symbol, rule: common.Rule) !void {
    for (rule.rhs.items, 0..) |symbol_index, i| {
        if (i != 0) try writer.writeAll(", ");
        const symbol = symbols[symbol_index];
        if (symbol.kind == .variable) {
            try common.emitFormatToken(writer, symbol.id);
        } else {
            try writer.writeByte('\'');
            try common.emitFormatToken(writer, symbol.id);
            try writer.writeByte('\'');
        }
    }
}

/// Emits the verbosity-gated Debug reduction log, shared by the LL and LR
/// backends. The head symbol id is taken from the rule header.
pub fn emitDebugReduction(writer: *std.Io.Writer, symbols: []const common.Symbol, rule: common.Rule, indent: []const u8) !void {
    try writer.print(
        \\{s}if (comptime builtin.mode == .Debug) {{
        \\{s}    if (context.verbosityLevel() > 1) {{
        \\{s}        std.debug.print("Reduction:
    , .{ indent, indent, indent });
    try writer.writeAll(" ");
    try common.emitFormatToken(writer, symbols[rule.header].id);
    try writer.writeAll(" <~ ");
    try emitRuleSymbolsForDebug(writer, symbols, rule);
    try writer.print(
        \\\n", .{{}});
        \\{s}    }}
        \\{s}}}
    , .{ indent, indent });
}
