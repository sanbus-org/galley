const std = @import("std");
const root = @import("galley");
const data_structures = root.data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;
const Node = data_structures.Node;
const standard_procedures = root.standard_procedures;

pub const SymbolKind = enum {
    variable,
    terminal,
    generative_terminal,
};

pub const RecoveryResume = enum {
    before,
    after,
};

pub const RecoveryPoint = struct {
    terminal: []const u8,
    @"resume": RecoveryResume,
};

pub const Annotations = struct {
    procedures: []const []const u8 = &.{},
    recovery_points: []const RecoveryPoint = &.{},
    verbatim: bool = false,
    verbatim_literal: ?[]const u8 = null,
};

pub const SymbolRef = struct {
    id: []const u8,
    kind: SymbolKind,
    annotations: Annotations = .{},
};

pub const RightHandSide = struct {
    symbols: []const SymbolRef,
    annotations: Annotations = .{},
};

pub const Rule = struct {
    header: []const u8,
    annotations: Annotations = .{},
    right_hand_sides: []const RightHandSide,
};

pub const Grammar = struct {
    rules: []const Rule,
};

pub const Payload = struct {
    grammar: ?*Grammar = null,
};

const MutableRightHandSide = struct {
    symbols: std.ArrayList(SymbolRef) = .empty,
    procedures: std.ArrayList([]const u8) = .empty,
    recovery_points: std.ArrayList(RecoveryPoint) = .empty,
};

const MutableRule = struct {
    header: []const u8,
    procedures: std.ArrayList([]const u8) = .empty,
    recovery_points: std.ArrayList(RecoveryPoint) = .empty,
    right_hand_sides: std.ArrayList(MutableRightHandSide) = .empty,
};

pub fn reduction(args: *ProcedureArguments) void {
    if (args.node_address) |node_address| {
        updateTextLength(args.context, node_address);
    }
}

pub fn reduction_Start(args: *ProcedureArguments) !void {
    if (args.node_address) |node_address| {
        updateTextLength(args.context, node_address);
        const grammar = try grammarFromAst(args.context, node_address);
        const node = args.context.node_allocator.at(node_address);
        if (comptime root.parser.are_procedures_enabled)
            node.payload.grammar = grammar;
    }

    if (args.context.verbosityLevel() > 0)
        std.debug.print("Parsed Galley grammar successfully.\n", .{});
}

fn updateTextLength(context: *data_structures.Context, node_address: Node.Pointer) void {
    const node = context.node_allocator.at(node_address);
    const end = context.pos();
    if (end >= node.text_start) {
        node.text_length = end - node.text_start;
    }
}

fn flattenRightRecursiveTail(args: *ProcedureArguments) !void {
    if (args.node_address) |node_address| {
        updateTextLength(args.context, node_address);
        try standard_procedures.rightRecursiveReduction(args);
    }
}

fn absorbLastChildNamed(comptime child_name: []const u8) type {
    return struct {
        fn function(args: *ProcedureArguments) !void {
            if (args.node_address) |node_address| {
                updateTextLength(args.context, node_address);
                const node = args.context.node_allocator.at(node_address);
                if (node.last_child == Node.invalid_pointer) return;

                const tail_address = node.last_child;
                if (!nodeIs(args.context, tail_address, child_name)) return;

                _ = try Node.removeSelf(tail_address, args.context.node_allocator);
                if (args.context.node_allocator.at(tail_address).first_child != Node.invalid_pointer) {
                    const tail_children = try Node.cleanChildren(tail_address, args.context.node_allocator);
                    if (tail_children != Node.invalid_pointer) {
                        try Node.appendChildren(node_address, args.context.node_allocator, tail_children);
                    }
                }
            }
        }
    };
}

fn flattenLeftRecursiveList(args: *ProcedureArguments) !void {
    if (args.node_address) |node_address| {
        updateTextLength(args.context, node_address);
        try standard_procedures.leftRecursiveReduction(args);
    }
}

fn normalizeList(comptime tail_name: ?[]const u8) type {
    return struct {
        fn function(args: *ProcedureArguments) !void {
            try flattenLeftRecursiveList(args);
            if (tail_name) |name| {
                try absorbLastChildNamed(name).function(args);
            }
        }
    };
}

pub const reduction_RulesTail_0 = flattenRightRecursiveTail;
pub const reduction_RulesTailTail_0 = flattenRightRecursiveTail;
pub const reduction_RightHandSidesTail_0 = flattenRightRecursiveTail;
pub const reduction_RightHandSideTail_0 = flattenRightRecursiveTail;
pub const reduction_ProcedureTail_0 = flattenRightRecursiveTail;
pub const reduction_RecoveryTail_0 = flattenRightRecursiveTail;
pub const reduction_GenerativeTerminalExceptions_0 = flattenRightRecursiveTail;

pub const reduction_Rules = normalizeList("RulesTail").function;
pub const reduction_RightHandSides = normalizeList("RightHandSidesTail").function;
pub const reduction_RightHandSide = normalizeList("RightHandSideTail").function;
pub const reduction_NonEmptyRightHandSide = normalizeList(null).function;
pub const reduction_ProcedureTail = normalizeList(null).function;
pub const reduction_RecoveryTail = normalizeList(null).function;
pub const reduction_GenerativeTerminalExceptions = normalizeList(null).function;

fn grammarFromAst(context: *data_structures.Context, start_address: Node.Pointer) !*Grammar {
    const allocator = context.runtime().arena_allocator;
    const rules_address = firstChildNamed(context, start_address, "Rules") orelse return error.MissingRules;

    var mutable_rules = std.ArrayList(MutableRule).empty;
    var child_address = context.node_allocator.at(rules_address).first_child;
    while (child_address != Node.invalid_pointer) {
        const next_address = context.node_allocator.at(child_address).next;
        if (nodeIs(context, child_address, "Rule")) {
            const rule = try mutableRuleFromAst(context, child_address);
            for (mutable_rules.items) |existing| {
                if (std.mem.eql(u8, existing.header, rule.header)) return error.DuplicateRuleHeader;
            }
            try mutable_rules.append(allocator, rule);
        }
        child_address = next_address;
    }

    if (mutable_rules.items.len == 0) return error.EmptyGrammar;
    return try immutableGrammarFromMutableRules(allocator, mutable_rules.items);
}

fn immutableGrammarFromMutableRules(allocator: std.mem.Allocator, mutable_rules: []MutableRule) !*Grammar {
    const immutable_rules = try allocator.alloc(Rule, mutable_rules.len);
    for (mutable_rules, 0..) |*mutable_rule, rule_index| {
        const immutable_right_hand_sides = try allocator.alloc(RightHandSide, mutable_rule.right_hand_sides.items.len);
        for (mutable_rule.right_hand_sides.items, 0..) |*mutable_rhs, rhs_index| {
            immutable_right_hand_sides[rhs_index] = .{
                .symbols = try mutable_rhs.symbols.toOwnedSlice(allocator),
                .annotations = .{
                    .procedures = try mutable_rhs.procedures.toOwnedSlice(allocator),
                    .recovery_points = try mutable_rhs.recovery_points.toOwnedSlice(allocator),
                },
            };
        }

        immutable_rules[rule_index] = .{
            .header = mutable_rule.header,
            .annotations = .{
                .procedures = try mutable_rule.procedures.toOwnedSlice(allocator),
                .recovery_points = try mutable_rule.recovery_points.toOwnedSlice(allocator),
            },
            .right_hand_sides = immutable_right_hand_sides,
        };
    }

    const grammar = try allocator.create(Grammar);
    grammar.* = .{ .rules = immutable_rules };
    return grammar;
}

fn mutableRuleFromAst(context: *data_structures.Context, rule_address: Node.Pointer) !MutableRule {
    const allocator = context.runtime().arena_allocator;
    const header_address = firstChildNamed(context, rule_address, "VariableSymbol") orelse return error.MissingRuleHeader;
    const right_hand_sides_address = firstChildNamed(context, rule_address, "RightHandSides") orelse return error.MissingRightHandSides;

    var rule = MutableRule{ .header = try allocator.dupe(u8, nodeText(context, header_address)) };
    if (firstChildNamed(context, rule_address, "RecoveryTail")) |recovery_address| {
        try appendRecoveryTail(context, &rule.recovery_points, recovery_address, null, null);
    }
    if (firstChildNamed(context, rule_address, "ProcedureTail")) |procedures_address| {
        try appendProcedureTail(context, &rule.procedures, procedures_address);
    }

    var child_address = context.node_allocator.at(right_hand_sides_address).first_child;
    while (child_address != Node.invalid_pointer) {
        const next_address = context.node_allocator.at(child_address).next;
        if (nodeIs(context, child_address, "RightHandSideLine")) {
            if (try rightHandSideFromAst(context, child_address)) |rhs| {
                try rule.right_hand_sides.append(allocator, rhs);
            }
        }
        child_address = next_address;
    }

    return rule;
}

fn rightHandSideFromAst(context: *data_structures.Context, line_address: Node.Pointer) !?MutableRightHandSide {
    const allocator = context.runtime().arena_allocator;
    const line_procedures_address = firstChildNamed(context, line_address, "ProcedureTail") orelse return null;
    const rhs_address = firstChildNamed(context, line_address, "RightHandSide") orelse
        firstChildNamed(context, line_address, "NonEmptyRightHandSide");

    var rhs = MutableRightHandSide{};
    if (firstChildNamed(context, line_address, "RecoveryTail")) |recovery_address| {
        try appendRecoveryTail(context, &rhs.recovery_points, recovery_address, null, null);
    }
    try appendProcedureTail(context, &rhs.procedures, line_procedures_address);
    const symbols_parent_address = rhs_address orelse return rhs;

    var child_address = context.node_allocator.at(symbols_parent_address).first_child;
    while (child_address != Node.invalid_pointer) {
        if (!nodeIs(context, child_address, "Symbol")) {
            child_address = context.node_allocator.at(child_address).next;
            continue;
        }

        const recovery_tail_address = nextSiblingNamed(context, child_address, "RecoveryTail");
        const procedure_tail_address = nextSiblingNamed(context, child_address, "ProcedureTail") orelse return error.MissingSymbolProcedures;
        try rhs.symbols.append(allocator, try symbolFromAst(context, child_address, recovery_tail_address, procedure_tail_address));
        child_address = context.node_allocator.at(procedure_tail_address).next;
    }

    return rhs;
}

fn symbolFromAst(
    context: *data_structures.Context,
    symbol_address: Node.Pointer,
    recovery_tail_address: ?Node.Pointer,
    procedure_tail_address: Node.Pointer,
) !SymbolRef {
    const allocator = context.runtime().arena_allocator;
    const concrete_address = firstChild(context, symbol_address) orelse return error.MissingSymbol;
    const kind: SymbolKind = if (nodeIs(context, concrete_address, "VariableSymbol"))
        .variable
    else if (nodeIs(context, concrete_address, "TerminalSymbol"))
        .terminal
    else
        .generative_terminal;

    var procedures = std.ArrayList([]const u8).empty;
    try appendProcedureTail(context, &procedures, procedure_tail_address);
    var recovery_points = std.ArrayList(RecoveryPoint).empty;
    var verbatim = false;
    var verbatim_literal: ?[]const u8 = null;
    if (recovery_tail_address) |address| try appendRecoveryTail(context, &recovery_points, address, &verbatim, &verbatim_literal);
    if (recovery_points.items.len != 0 and kind != .variable) return error.InvalidRecoveryTarget;

    const id = if (kind == .generative_terminal)
        try generativeIdFromAst(context, allocator, concrete_address)
    else
        try decodeEscapes(allocator, nodeText(context, concrete_address));

    return .{
        .id = id,
        .kind = kind,
        .annotations = .{
            .procedures = try procedures.toOwnedSlice(allocator),
            .recovery_points = try recovery_points.toOwnedSlice(allocator),
            .verbatim = verbatim,
            .verbatim_literal = verbatim_literal,
        },
    };
}

/// Builds the canonical id for a generative terminal symbol by walking its
/// exception children instead of decoding flattened source text. Each
/// exception `TerminalSymbol` is decoded on its own, so a decoded quote or
/// backslash can never collide with the structural delimiters the generator
/// parses back out.
fn generativeIdFromAst(context: *data_structures.Context, allocator: std.mem.Allocator, node_address: Node.Pointer) ![]const u8 {
    const lowercase_address = firstChildNamed(context, node_address, "LowercaseId") orelse
        return error.MissingGenerativeId;
    var id = std.ArrayList(u8).empty;
    try id.appendSlice(allocator, nodeText(context, lowercase_address));
    try appendExceptionTerminals(context, allocator, &id, node_address);
    return id.toOwnedSlice(allocator);
}

fn appendExceptionTerminals(context: *data_structures.Context, allocator: std.mem.Allocator, id: *std.ArrayList(u8), node_address: Node.Pointer) !void {
    var child_address = context.node_allocator.at(node_address).first_child;
    while (child_address != Node.invalid_pointer) {
        const next_address = context.node_allocator.at(child_address).next;
        if (nodeIs(context, child_address, "TerminalSymbol")) {
            try id.append(allocator, '^');
            try id.append(allocator, '"');
            try appendEncodedTerminal(allocator, id, try decodeEscapes(allocator, nodeText(context, child_address)));
            try id.append(allocator, '"');
        } else {
            try appendExceptionTerminals(context, allocator, id, child_address);
        }
        child_address = next_address;
    }
}

/// Canonically re-encodes decoded exception content so the generator's
/// exception scanner can read it back without structural ambiguity. Every
/// byte the escape scanner treats specially is rendered as a `\u{..}` byte
/// escape, keeping the generator's decode logic a single bounded rule.
fn appendEncodedTerminal(allocator: std.mem.Allocator, id: *std.ArrayList(u8), content: []const u8) !void {
    for (content) |byte| {
        switch (byte) {
            '\n' => try id.appendSlice(allocator, "\\n"),
            '\r' => try id.appendSlice(allocator, "\\r"),
            '\t' => try id.appendSlice(allocator, "\\t"),
            else => {
                const printable = byte >= 0x20 and byte <= 0x7e;
                const special = byte == '\\' or byte == '"';
                if (printable and !special) {
                    try id.append(allocator, byte);
                } else {
                    try id.appendSlice(allocator, "\\u{");
                    var digits_buffer: [2]u8 = undefined;
                    _ = try std.fmt.bufPrint(&digits_buffer, "{x:0>2}", .{byte});
                    try id.appendSlice(allocator, &digits_buffer);
                    try id.append(allocator, '}');
                }
            },
        }
    }
}

fn appendRecoveryTail(context: *data_structures.Context, target: *std.ArrayList(RecoveryPoint), recovery_tail_address: Node.Pointer, verbatim_active: ?*bool, verbatim_literal: ?*?[]const u8) !void {
    const allocator = context.runtime().arena_allocator;
    var child_address = context.node_allocator.at(recovery_tail_address).first_child;
    while (child_address != Node.invalid_pointer) {
        const next_address = context.node_allocator.at(child_address).next;
        if (nodeIs(context, child_address, "RecoveryPoint")) {
            if (firstDescendantNamed(context, child_address, "VerbatimMarker")) |marker_address| {
                if (verbatim_active) |active| {
                    active.* = true;
                    if (firstDescendantNamed(context, marker_address, "TerminalSymbol")) |terminal_address| {
                        const terminal = try decodeEscapes(allocator, nodeText(context, terminal_address));
                        if (terminal.len == 0) return error.EmptyVerbatimTerminator;
                        if (std.mem.indexOfScalar(u8, terminal, 0) != null) return error.NulVerbatimTerminator;
                        if (verbatim_literal) |literal| {
                            literal.* = terminal;
                        }
                    } else if (verbatim_literal) |literal| {
                        literal.* = null;
                    }
                } else {
                    return error.InvalidVerbatimPlacement;
                }
            } else {
                const body_address = firstDescendantNamed(context, child_address, "RecoveryPointBody") orelse return error.MissingRecoveryPointBody;
                const terminal_address = firstDescendantNamed(context, child_address, "TerminalSymbol") orelse return error.MissingRecoveryTerminal;
                const terminal = try decodeEscapes(allocator, nodeText(context, terminal_address));
                if (terminal.len == 0) return error.EmptyRecoveryTerminal;
                if (std.mem.indexOfScalar(u8, terminal, 0) != null) return error.NulRecoveryTerminal;
                const body_node = context.node_allocator.at(body_address);
                const terminal_node = context.node_allocator.at(terminal_address);
                const resume_side: RecoveryResume = if (body_node.text_start < terminal_node.text_start) .before else .after;
                try target.append(allocator, .{ .terminal = terminal, .@"resume" = resume_side });
            }
        }
        child_address = next_address;
    }
}

fn appendProcedureTail(context: *data_structures.Context, target: *std.ArrayList([]const u8), procedure_tail_address: Node.Pointer) !void {
    const allocator = context.runtime().arena_allocator;
    var child_address = context.node_allocator.at(procedure_tail_address).first_child;
    while (child_address != Node.invalid_pointer) {
        const next_address = context.node_allocator.at(child_address).next;
        if (nodeIs(context, child_address, "CamelCaseId")) {
            try target.append(allocator, try allocator.dupe(u8, nodeText(context, child_address)));
        }
        child_address = next_address;
    }
}

fn firstChild(context: *data_structures.Context, node_address: Node.Pointer) ?Node.Pointer {
    const node = context.node_allocator.at(node_address);
    if (node.first_child == Node.invalid_pointer) return null;
    return node.first_child;
}

fn firstChildNamed(context: *data_structures.Context, node_address: Node.Pointer, name: []const u8) ?Node.Pointer {
    var child_address = context.node_allocator.at(node_address).first_child;
    while (child_address != Node.invalid_pointer) {
        const next_address = context.node_allocator.at(child_address).next;
        if (nodeIs(context, child_address, name)) return child_address;
        child_address = next_address;
    }
    return null;
}

fn firstDescendantNamed(context: *data_structures.Context, node_address: Node.Pointer, name: []const u8) ?Node.Pointer {
    var child_address = context.node_allocator.at(node_address).first_child;
    while (child_address != Node.invalid_pointer) {
        const next_address = context.node_allocator.at(child_address).next;
        if (nodeIs(context, child_address, name)) return child_address;
        if (firstDescendantNamed(context, child_address, name)) |found| return found;
        child_address = next_address;
    }
    return null;
}

fn nextSiblingNamed(context: *data_structures.Context, node_address: Node.Pointer, name: []const u8) ?Node.Pointer {
    var sibling_address = context.node_allocator.at(node_address).next;
    while (sibling_address != Node.invalid_pointer) {
        const next_address = context.node_allocator.at(sibling_address).next;
        if (nodeIs(context, sibling_address, name)) return sibling_address;
        sibling_address = next_address;
    }
    return null;
}

fn nodeIs(context: *data_structures.Context, node_address: Node.Pointer, name: []const u8) bool {
    const node = context.node_allocator.at(node_address);
    if (node.variable >= root.parser.variables.len) return false;
    return std.mem.eql(u8, root.parser.variables[node.variable], name);
}

fn nodeText(context: *data_structures.Context, node_address: Node.Pointer) []const u8 {
    const node = context.node_allocator.at(node_address);
    return context.getTextSlice(node.text_start, node.text_length);
}

pub fn grammarFromAstAllocator(node_allocator: *const data_structures.ASTAllocator) ?*Grammar {
    var index: usize = 0;
    while (index < node_allocator.counter) : (index += 1) {
        const node = node_allocator.atConst(@intCast(index));
        if (node.payload.grammar) |grammar| return grammar;
    }
    return null;
}

fn decodeEscapes(allocator: std.mem.Allocator, raw_id: []const u8) ![]const u8 {
    if (rawStringContent(raw_id)) |content| {
        return allocator.dupe(u8, content);
    }

    if (raw_id.len >= 2 and raw_id[0] == '"' and raw_id[raw_id.len - 1] == '"') {
        return decodeEscapedContent(allocator, raw_id[1 .. raw_id.len - 1]);
    }

    return decodeWithRawStrings(allocator, raw_id);
}

fn decodeWithRawStrings(allocator: std.mem.Allocator, raw_id: []const u8) ![]const u8 {
    var decoded = std.ArrayList(u8).empty;
    var i: usize = 0;
    while (i < raw_id.len) {
        if (i > 0 and raw_id[i - 1] == '^' and i + 1 < raw_id.len and raw_id[i] == '\\' and raw_id[i + 1] == '"') {
            const end = rawStringEnd(raw_id, i) orelse return error.InvalidRawString;
            try decoded.appendSlice(allocator, raw_id[i..end]);
            i = end;
            continue;
        }
        if (raw_id[i] != '\\' or i + 1 >= raw_id.len) {
            try decoded.append(allocator, raw_id[i]);
            i += 1;
            continue;
        }

        const escaped = raw_id[i + 1];
        switch (escaped) {
            'n' => try decoded.append(allocator, '\n'),
            'r' => try decoded.append(allocator, '\r'),
            't' => try decoded.append(allocator, '\t'),
            '\\' => try decoded.append(allocator, '\\'),
            '"' => try decoded.append(allocator, '"'),
            '\'' => try decoded.append(allocator, '\''),
            'x' => {
                if (i + 3 >= raw_id.len) return error.InvalidHexEscape;
                const value = try std.fmt.parseInt(u8, raw_id[i + 2 .. i + 4], 16);
                try decoded.append(allocator, value);
                i += 4;
                continue;
            },
            'u' => {
                if (i + 2 >= raw_id.len or raw_id[i + 2] != '{') return error.InvalidUnicodeEscape;
                const end = std.mem.indexOfScalarPos(u8, raw_id, i + 3, '}') orelse
                    return error.InvalidUnicodeEscape;
                const digits = raw_id[i + 3 .. end];
                if (digits.len == 0 or digits.len > 6) return error.InvalidUnicodeEscape;

                const codepoint_value = std.fmt.parseInt(u21, digits, 16) catch
                    return error.InvalidUnicodeEscape;
                var buffer: [4]u8 = undefined;
                const length = std.unicode.utf8Encode(codepoint_value, &buffer) catch
                    return error.InvalidUnicodeEscape;
                try decoded.appendSlice(allocator, buffer[0..length]);
                i = end + 1;
                continue;
            },
            else => try decoded.append(allocator, escaped),
        }
        i += 2;
    }
    return decoded.toOwnedSlice(allocator);
}

fn decodeEscapedContent(allocator: std.mem.Allocator, unquoted: []const u8) ![]const u8 {
    var decoded = std.ArrayList(u8).empty;
    var i: usize = 0;
    while (i < unquoted.len) {
        if (unquoted[i] != '\\' or i + 1 >= unquoted.len) {
            try decoded.append(allocator, unquoted[i]);
            i += 1;
            continue;
        }

        const escaped = unquoted[i + 1];
        switch (escaped) {
            'n' => try decoded.append(allocator, '\n'),
            'r' => try decoded.append(allocator, '\r'),
            't' => try decoded.append(allocator, '\t'),
            '\\' => try decoded.append(allocator, '\\'),
            '"' => try decoded.append(allocator, '"'),
            '\'' => try decoded.append(allocator, '\''),
            'x' => {
                if (i + 3 >= unquoted.len) return error.InvalidHexEscape;
                const value = try std.fmt.parseInt(u8, unquoted[i + 2 .. i + 4], 16);
                try decoded.append(allocator, value);
                i += 4;
                continue;
            },
            'u' => {
                if (i + 2 >= unquoted.len or unquoted[i + 2] != '{') return error.InvalidUnicodeEscape;
                const end = std.mem.indexOfScalarPos(u8, unquoted, i + 3, '}') orelse
                    return error.InvalidUnicodeEscape;
                const digits = unquoted[i + 3 .. end];
                if (digits.len == 0 or digits.len > 6) return error.InvalidUnicodeEscape;

                const codepoint_value = std.fmt.parseInt(u21, digits, 16) catch
                    return error.InvalidUnicodeEscape;
                var buffer: [4]u8 = undefined;
                const length = std.unicode.utf8Encode(codepoint_value, &buffer) catch
                    return error.InvalidUnicodeEscape;
                try decoded.appendSlice(allocator, buffer[0..length]);
                i = end + 1;
                continue;
            },
            else => try decoded.append(allocator, escaped),
        }
        i += 2;
    }

    return decoded.toOwnedSlice(allocator);
}

fn rawStringContent(raw_id: []const u8) ?[]const u8 {
    const end = rawStringEnd(raw_id, 0) orelse return null;
    if (end != raw_id.len) return null;
    return raw_id[3 .. end - 2];
}

fn rawStringEnd(id: []const u8, start: usize) ?usize {
    if (start + 2 >= id.len or id[start] != '\\' or id[start + 1] != '"') return null;
    const indicator = id[start + 2];
    const content_end = std.mem.indexOfScalarPos(u8, id, start + 3, indicator) orelse return null;
    const end = content_end + 2;
    if (end > id.len or id[end - 1] != '"') return null;
    return end;
}

test "grammar Unicode escapes decode every UTF-8 width" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const decoded = try decodeEscapes(
        arena.allocator(),
        "\"\\u{0}\\u{7f}\\u{80}\\u{7ff}\\u{800}\\u{ffff}\\u{10000}\\u{10ffff}\"",
    );
    try std.testing.expectEqualSlices(
        u8,
        "\x00\x7f\xc2\x80\xdf\xbf\xe0\xa0\x80\xef\xbf\xbf\xf0\x90\x80\x80\xf4\x8f\xbf\xbf",
        decoded,
    );
}

test "grammar Unicode escapes reject non-scalars and malformed forms" {
    inline for (&.{
        "\"\\u{}\"",
        "\"\\u{1234567}\"",
        "\"\\u{d800}\"",
        "\"\\u{dfff}\"",
        "\"\\u{110000}\"",
        "\"\\u{xyz}\"",
        "\"\\u{1234\"",
        "\"\\u1234\"",
    }) |encoded| {
        try std.testing.expectError(
            error.InvalidUnicodeEscape,
            decodeEscapes(std.testing.allocator, encoded),
        );
    }
}

test "raw string terminals decode to their verbatim content" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const cases = [_]struct { raw: []const u8, expected: []const u8 }{
        .{ .raw = "\\\"~\"~\"", .expected = "\"" },
        .{ .raw = "\\\"~\\~\"", .expected = "\\" },
        .{ .raw = "\\\"~\\n~\"", .expected = "\\n" },
        .{ .raw = "\\\"~~\"", .expected = "" },
        .{ .raw = "\\\"~anything here~\"", .expected = "anything here" },
    };
    for (cases) |case| {
        const decoded = try decodeEscapes(allocator, case.raw);
        try std.testing.expectEqualStrings(case.expected, decoded);
    }
}

test "raw string exceptions survive escape decoding for the generator" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const cases = [_]struct { raw: []const u8, expected: []const u8 }{
        .{ .raw = "character^\\\"~\"~\"", .expected = "character^\\\"~\"~\"" },
        .{ .raw = "character^\\\"~\"~\"^\"\\n\"", .expected = "character^\\\"~\"~\"^\"\n\"" },
        .{ .raw = "character^\\\"~x~\"^\"\\n\"^\"\\\\\"", .expected = "character^\\\"~x~\"^\"\n\"^\"\\\"" },
        .{ .raw = "character^\"\\n\"", .expected = "character^\"\n\"" },
    };
    for (cases) |case| {
        const decoded = try decodeEscapes(allocator, case.raw);
        try std.testing.expectEqualStrings(case.expected, decoded);
    }
}

test "malformed raw strings are rejected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    inline for (&.{
        "character^\\\"",
        "character^\\\"~",
        "character^\\\"~x~",
        "character^\\\"~x~x",
    }) |raw| {
        try std.testing.expectError(
            error.InvalidRawString,
            decodeEscapes(allocator, raw),
        );
    }
}
