const std = @import("std");

pub const Options = struct {
    with_ast: bool = true,
    with_procedures: bool = true,
    with_error_recovery: bool = false,
    ast_for_terminals: bool = false,
    input_size: u16 = 16,
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
};

pub const Symbol = struct {
    id: []const u8,
    kind: SymbolKind,
    ast_enabled: bool = true,
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

pub fn addSymbol(
    allocator: std.mem.Allocator,
    symbols: *std.ArrayList(Symbol),
    variables: *std.ArrayList(usize),
    id: []const u8,
    kind: SymbolKind,
) !usize {
    for (symbols.items, 0..) |symbol, index| {
        if (std.mem.eql(u8, symbol.id, id)) return index;
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

pub fn appendProcedureNames(allocator: std.mem.Allocator, target: *std.ArrayList([]const u8), names: []const []const u8) !void {
    for (names) |name| try target.append(allocator, try allocator.dupe(u8, name));
}

pub fn cloneAnnotations(allocator: std.mem.Allocator, source: anytype) !Annotations {
    var result = Annotations{};
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

pub fn validateGrammar(grammar: anytype) !void {
    for (grammar.rules, 0..) |rule, rule_index| {
        for (grammar.rules[0..rule_index]) |previous| {
            if (std.mem.eql(u8, previous.header, rule.header)) return error.DuplicateRuleHeader;
        }
        try validateRecoveryPoints(rule.annotations.recovery_points);
        for (rule.right_hand_sides) |rhs| {
            try validateRecoveryPoints(rhs.annotations.recovery_points);
            for (rhs.symbols) |symbol| {
                try validateRecoveryPoints(symbol.annotations.recovery_points);
                if (symbol.annotations.recovery_points.len != 0 and symbol.kind != .variable) return error.InvalidRecoveryTarget;
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

pub fn longestTerminalLength(symbols: []const Symbol) usize {
    var longest: usize = 0;
    for (symbols) |symbol| {
        for (symbol.terminals.items) |terminal| longest = @max(longest, terminal.len);
    }
    return longest;
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

pub fn readableSymbolName(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    for (bytes) |byte| {
        switch (byte) {
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            0x0b => try out.appendSlice(allocator, "\\x0b"),
            0x0c => try out.appendSlice(allocator, "\\x0c"),
            0x00...0x08, 0x0e...0x1f, 0x7f...0xff => {
                const escaped = try std.fmt.allocPrint(allocator, "\\x{x:0>2}", .{byte});
                try out.appendSlice(allocator, escaped);
            },
            else => try out.append(allocator, byte),
        }
    }
    return out.toOwnedSlice(allocator);
}

pub fn safeIdentifier(allocator: std.mem.Allocator, bytes: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    for (bytes) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '_') {
            try out.append(allocator, byte);
        } else {
            const escaped = try std.fmt.allocPrint(allocator, "_x{d}", .{byte});
            try out.appendSlice(allocator, escaped);
        }
    }
    return out.toOwnedSlice(allocator);
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

pub fn syntaxErrorFunctionName(
    allocator: std.mem.Allocator,
    comptime prefix: []const u8,
    stem: []const u8,
    site_index: usize,
) ![]const u8 {
    return std.fmt.allocPrint(allocator, "syntax_error_" ++ prefix ++ "{s}_{d}", .{ stem, site_index });
}

pub fn emitErrorMessageFunction(writer: *std.Io.Writer, name: []const u8) !void {
    try writer.print(
        \\pub fn {s}(args: root.SyntaxErrorMessageArgs) ![]const u8 {{
        \\    return try root.renderParseDiagnostic(args.allocator, args.diagnostic, args.style);
        \\}}
        \\
        \\
    , .{name});
}

pub fn emitErrorMessageFile(
    writer: *std.Io.Writer,
    parser_label: []const u8,
    specs: []const ErrorMessageSpec,
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
        try emitErrorMessageFunction(writer, spec.name);
    }
}

pub fn headLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

pub fn expandGenerativeTerminal(allocator: std.mem.Allocator, out: *std.ArrayList([]const u8), id: []const u8) !void {
    if (std.mem.eql(u8, id, "digit")) return appendChars(allocator, out, "0123456789");
    if (std.mem.eql(u8, id, "letter")) return appendChars(allocator, out, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ");
    if (std.mem.eql(u8, id, "lowercase_letter")) return appendChars(allocator, out, "abcdefghijklmnopqrstuvwxyz");
    if (std.mem.eql(u8, id, "uppercase_letter")) return appendChars(allocator, out, "ABCDEFGHIJKLMNOPQRSTUVWXYZ");
    if (std.mem.eql(u8, id, "new_line")) return out.append(allocator, "\n");
    if (std.mem.eql(u8, id, "space")) return out.append(allocator, " ");
    if (std.mem.eql(u8, id, "block_start")) return out.append(allocator, "\x01");
    if (std.mem.eql(u8, id, "block_end")) return out.append(allocator, "\x02");
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

fn appendCharsExcept(allocator: std.mem.Allocator, out: *std.ArrayList([]const u8), chars: []const u8, id: []const u8) !void {
    var excluded = [_]bool{false} ** 256;
    var i = std.mem.indexOfScalar(u8, id, '^') orelse id.len;
    while (i < id.len) {
        i += 1;
        if (i >= id.len) break;
        const quote = id[i];
        i += 1;
        while (i < id.len and id[i] != quote and id[i] != 0x03) : (i += 1) excluded[id[i]] = true;
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
