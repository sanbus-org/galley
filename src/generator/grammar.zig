const std = @import("std");

pub const SymbolKind = enum {
    variable,
    terminal,
    generative_terminal,
};

pub const SymbolRef = struct {
    id: []const u8,
    kind: SymbolKind,
    procedures: []const []const u8,
};

pub const RightHandSide = struct {
    symbols: []const SymbolRef,
    procedures: []const []const u8,
};

pub const Rule = struct {
    header: []const u8,
    procedures: []const []const u8,
    right_hand_sides: []const RightHandSide,
};

pub const Grammar = struct {
    rules: []const Rule,
};

const MutableRightHandSide = struct {
    symbols: std.ArrayList(SymbolRef) = .empty,
    procedures: std.ArrayList([]const u8) = .empty,
};

const MutableRule = struct {
    header: []const u8,
    procedures: std.ArrayList([]const u8) = .empty,
    right_hand_sides: std.ArrayList(MutableRightHandSide) = .empty,
};

const ParseState = struct {
    rules: std.ArrayList(MutableRule) = .empty,
    current_rule: ?usize = null,
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !*Grammar {
    var state = ParseState{};

    var line_iterator = std.mem.splitScalar(u8, source, '\n');
    while (line_iterator.next()) |raw_line| {
        const line_without_cr = std.mem.trimEnd(u8, raw_line, "\r");
        const line = std.mem.trimEnd(u8, line_without_cr, " \t");

        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, std.mem.trimStart(u8, line, " \t"), "#")) continue;

        if (line[0] == '|') {
            if (state.current_rule == null) return error.RightHandSideWithoutRule;
            try parseRightHandSideLine(allocator, &state, line[1..]);
        } else {
            try parseRuleHeader(allocator, &state, line);
        }
    }

    if (state.rules.items.len == 0) return error.EmptyGrammar;

    return try immutableGrammarFromMutableRules(allocator, state.rules.items);
}

fn immutableGrammarFromMutableRules(allocator: std.mem.Allocator, mutable_rules: []MutableRule) !*Grammar {
    const immutable_rules = try allocator.alloc(Rule, mutable_rules.len);
    for (mutable_rules, 0..) |*mutable_rule, rule_index| {
        const immutable_right_hand_sides = try allocator.alloc(RightHandSide, mutable_rule.right_hand_sides.items.len);
        for (mutable_rule.right_hand_sides.items, 0..) |*mutable_rhs, rhs_index| {
            immutable_right_hand_sides[rhs_index] = .{
                .symbols = try mutable_rhs.symbols.toOwnedSlice(allocator),
                .procedures = try mutable_rhs.procedures.toOwnedSlice(allocator),
            };
        }

        immutable_rules[rule_index] = .{
            .header = mutable_rule.header,
            .procedures = try mutable_rule.procedures.toOwnedSlice(allocator),
            .right_hand_sides = immutable_right_hand_sides,
        };
    }

    const grammar = try allocator.create(Grammar);
    grammar.* = .{ .rules = immutable_rules };
    return grammar;
}

fn parseRuleHeader(allocator: std.mem.Allocator, state: *ParseState, line: []const u8) !void {
    var parsed = try splitProcedures(allocator, line);
    defer parsed.procedures.deinit(allocator);

    if (parsed.id.len == 0) return error.EmptyRuleHeader;
    if (!isVariableId(parsed.id)) return error.InvalidRuleHeader;

    var rule = MutableRule{ .header = try allocator.dupe(u8, parsed.id) };
    for (parsed.procedures.items) |procedure| {
        try rule.procedures.append(allocator, try allocator.dupe(u8, procedure));
    }

    try state.rules.append(allocator, rule);
    state.current_rule = state.rules.items.len - 1;
}

fn parseRightHandSideLine(allocator: std.mem.Allocator, state: *ParseState, line: []const u8) !void {
    const current_rule_index = state.current_rule orelse return error.RightHandSideWithoutRule;
    const trimmed = if (line.len > 0 and line[0] == ' ') line[1..] else line;
    const procedure_text, const symbol_text = splitRuleProcedures(trimmed);

    var rhs = MutableRightHandSide{};
    try appendProcedures(allocator, &rhs.procedures, procedure_text);

    var tokens = try tokenizeLine(allocator, symbol_text);
    defer tokens.deinit(allocator);

    for (tokens.items) |token| {
        var parsed = try splitProcedures(allocator, token);
        defer parsed.procedures.deinit(allocator);

        var symbol = SymbolRef{
            .id = try decodeEscapes(allocator, parsed.id),
            .kind = classifySymbol(parsed.id),
            .procedures = undefined,
        };

        const procedures = try allocator.alloc([]const u8, parsed.procedures.items.len);
        for (parsed.procedures.items, 0..) |procedure, index| {
            procedures[index] = try allocator.dupe(u8, procedure);
        }
        symbol.procedures = procedures;

        try rhs.symbols.append(allocator, symbol);
    }

    try state.rules.items[current_rule_index].right_hand_sides.append(allocator, rhs);
}

const ProcedureSplit = struct {
    id: []const u8,
    procedures: std.ArrayList([]const u8) = .empty,
};

fn splitProcedures(allocator: std.mem.Allocator, text: []const u8) !ProcedureSplit {
    if (text.len > 0 and (text[0] == '"' or text[0] == '\'')) {
        return .{ .id = text };
    }

    const first_at = std.mem.indexOfScalar(u8, text, '@') orelse {
        return .{ .id = text };
    };

    var result = ProcedureSplit{ .id = text[0..first_at] };
    var iterator = std.mem.splitScalar(u8, text[first_at + 1 ..], '@');
    while (iterator.next()) |procedure| {
        if (procedure.len == 0) return error.EmptyProcedureName;
        if (!isLowercaseProcedureName(procedure)) return error.InvalidProcedureName;
        try result.procedures.append(allocator, procedure);
    }
    return result;
}

fn splitRuleProcedures(text: []const u8) struct { []const u8, []const u8 } {
    if (text.len == 0) return .{ "", "" };
    if (text[0] != '@') return .{ "", text };

    const space_index = std.mem.indexOfScalar(u8, text, ' ') orelse return .{ text, "" };
    return .{ text[0..space_index], text[space_index + 1 ..] };
}

fn appendProcedures(allocator: std.mem.Allocator, target: *std.ArrayList([]const u8), text: []const u8) !void {
    if (text.len == 0) return;
    var iterator = std.mem.splitScalar(u8, text[1..], '@');
    while (iterator.next()) |procedure| {
        if (procedure.len == 0) return error.EmptyProcedureName;
        if (!isLowercaseProcedureName(procedure)) return error.InvalidProcedureName;
        try target.append(allocator, try allocator.dupe(u8, procedure));
    }
}

fn tokenizeLine(allocator: std.mem.Allocator, line: []const u8) !std.ArrayList([]const u8) {
    var tokens = std.ArrayList([]const u8).empty;
    var current = std.ArrayList(u8).empty;
    var i: usize = 0;

    while (i < line.len) {
        const c = line[i];
        if (c == ' ') {
            if (current.items.len > 0) {
                try tokens.append(allocator, try current.toOwnedSlice(allocator));
            }
            i += 1;
        } else if (c == '"' or c == '\'') {
            const quote = c;
            const closing_char: u8 = if (quote == '"') '"' else 0x03;
            try current.append(allocator, c);
            i += 1;

            var closing_idx: ?usize = null;
            var j = i;
            while (j < line.len) : (j += 1) {
                if (line[j] == closing_char) {
                    closing_idx = j;
                    break;
                }
            }

            if (closing_idx) |end| {
                try current.appendSlice(allocator, line[i .. end + 1]);
                i = end + 1;
            } else {
                while (i < line.len and line[i] != ' ') : (i += 1) {
                    try current.append(allocator, line[i]);
                }
            }
        } else {
            try current.append(allocator, c);
            i += 1;
        }
    }

    if (current.items.len > 0) {
        try tokens.append(allocator, try current.toOwnedSlice(allocator));
    }
    return tokens;
}

fn classifySymbol(raw_id: []const u8) SymbolKind {
    if ((raw_id.len >= 2 and raw_id[0] == '"' and raw_id[raw_id.len - 1] == '"') or
        (raw_id.len >= 2 and raw_id[0] == '\'' and raw_id[raw_id.len - 1] == 0x03))
    {
        return .terminal;
    }
    if (isVariableId(raw_id)) return .variable;
    return .generative_terminal;
}

fn isVariableId(id: []const u8) bool {
    if (id.len == 0) return false;
    const start: usize = if (id[0] == '_') 1 else 0;
    if (start >= id.len) return false;
    if (!std.ascii.isUpper(id[start])) return false;
    for (id[start + 1 ..]) |char| {
        if (!std.ascii.isAlphanumeric(char) and char != '_') return false;
    }
    return true;
}

fn isLowercaseProcedureName(id: []const u8) bool {
    for (id) |char| {
        if (!(char >= 'a' and char <= 'z') and char != '_') return false;
    }
    return true;
}

fn decodeEscapes(allocator: std.mem.Allocator, raw_id: []const u8) ![]const u8 {
    const unquoted = if ((raw_id.len >= 2 and raw_id[0] == '"' and raw_id[raw_id.len - 1] == '"') or
        (raw_id.len >= 2 and raw_id[0] == '\'' and raw_id[raw_id.len - 1] == 0x03))
        raw_id[1 .. raw_id.len - 1]
    else
        raw_id;

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
            else => try decoded.append(allocator, escaped),
        }
        i += 2;
    }

    return decoded.toOwnedSlice(allocator);
}

test parse {
    const source =
        \\Start
        \\| "a" Tail@drop_self
        \\Tail
        \\|
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const parsed = try parse(arena.allocator(), source);
    try std.testing.expectEqual(@as(usize, 2), parsed.rules.len);
    try std.testing.expectEqualStrings("Start", parsed.rules[0].header);
    try std.testing.expectEqual(@as(usize, 2), parsed.rules[0].right_hand_sides[0].symbols.len);
    try std.testing.expectEqual(SymbolKind.terminal, parsed.rules[0].right_hand_sides[0].symbols[0].kind);
    try std.testing.expectEqualStrings("a", parsed.rules[0].right_hand_sides[0].symbols[0].id);
}
