const std = @import("std");
const root = @import("galley");
const ll_generator = @import("ll_generator");
const lr_generator = @import("lr_generator");
const data_structures = root.data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;
const ASTNode = data_structures.ASTNode;

pub const indentation_syntax = false;

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

pub const Payload = struct {
    grammar: ?*Grammar = null,
};

var last_grammar: ?*Grammar = null;

const MutableRightHandSide = struct {
    symbols: std.ArrayList(SymbolRef) = .empty,
    procedures: std.ArrayList([]const u8) = .empty,
};

const MutableRule = struct {
    header: []const u8,
    procedures: std.ArrayList([]const u8) = .empty,
    right_hand_sides: std.ArrayList(MutableRightHandSide) = .empty,
};

pub fn reduction(args: *ProcedureArguments) void {
    if (args.node) |node_address| {
        updateTextLength(args.context, node_address);
    }
}

pub fn reduction_Start(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        updateTextLength(args.context, node_address);
        const grammar = try grammarFromAst(args.context, node_address);
        const node = args.context.node_allocator.at(node_address);
        if (comptime root.parser.are_procedures_enabled)
            node.payload.grammar = grammar;
        last_grammar = grammar;
        try emitParserForInputPath(args.context, grammar);
    }

    if (args.context.verbosityLevel() > 0)
        std.debug.print("Parsed Galley grammar successfully.\n", .{});
}

fn updateTextLength(context: *data_structures.Context, node_address: ASTNode.Pointer) void {
    const node = context.node_allocator.at(node_address);
    const end = context.pos();
    if (end >= node.text_start) {
        node.text_length = end - node.text_start;
    }
}

fn flattenRightRecursiveTail(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        updateTextLength(args.context, node_address);
        const node = args.context.node_allocator.at(node_address);
        if (node.last_child == ASTNode.invalid_pointer) return;

        const nested_tail_address = node.last_child;
        if (args.context.node_allocator.at(nested_tail_address).variable != node.variable) return;

        _ = try ASTNode.removeSelf(nested_tail_address, args.context);
        if (args.context.node_allocator.at(nested_tail_address).first_child != ASTNode.invalid_pointer) {
            const nested_children = try ASTNode.cleanChildren(nested_tail_address, args.context);
            if (nested_children.len > 0) {
                try ASTNode.appendChildren(node_address, args.context, nested_children[0]);
            }
        }
    }
}

fn absorbLastChildNamed(comptime child_name: []const u8) type {
    return struct {
        fn function(args: *ProcedureArguments) !void {
            if (args.node) |node_address| {
                updateTextLength(args.context, node_address);
                const node = args.context.node_allocator.at(node_address);
                if (node.last_child == ASTNode.invalid_pointer) return;

                const tail_address = node.last_child;
                if (!nodeIs(args.context, tail_address, child_name)) return;

                _ = try ASTNode.removeSelf(tail_address, args.context);
                if (args.context.node_allocator.at(tail_address).first_child != ASTNode.invalid_pointer) {
                    const tail_children = try ASTNode.cleanChildren(tail_address, args.context);
                    if (tail_children.len > 0) {
                        try ASTNode.appendChildren(node_address, args.context, tail_children[0]);
                    }
                }
            }
        }
    };
}

fn flattenLeftRecursiveList(args: *ProcedureArguments) !void {
    if (args.node) |node_address| {
        updateTextLength(args.context, node_address);
        const node = args.context.node_allocator.at(node_address);
        if (node.first_child == ASTNode.invalid_pointer) return;

        const nested_list_address = node.first_child;
        if (args.context.node_allocator.at(nested_list_address).variable != node.variable) return;

        _ = try ASTNode.removeSelf(nested_list_address, args.context);
        if (args.context.node_allocator.at(nested_list_address).first_child != ASTNode.invalid_pointer) {
            const nested_children = try ASTNode.cleanChildren(nested_list_address, args.context);
            if (nested_children.len > 0) {
                try ASTNode.insertChildren(node_address, args.context, 0, nested_children[0]);
            }
        }
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
pub const reduction_GenerativeTerminalExceptions_0 = flattenRightRecursiveTail;

pub const reduction_Rules = normalizeList("RulesTail").function;
pub const reduction_RightHandSides = normalizeList("RightHandSidesTail").function;
pub const reduction_RightHandSide = normalizeList("RightHandSideTail").function;
pub const reduction_NonEmptyRightHandSide = normalizeList(null).function;
pub const reduction_ProcedureTail = normalizeList(null).function;
pub const reduction_GenerativeTerminalExceptions = normalizeList(null).function;

fn grammarFromAst(context: *data_structures.Context, start_address: ASTNode.Pointer) !*Grammar {
    const allocator = context.runtime().arena_allocator;
    const rules_address = firstChildNamed(context, start_address, "Rules") orelse return error.MissingRules;

    var mutable_rules = std.ArrayList(MutableRule).empty;
    var child_address = context.node_allocator.at(rules_address).first_child;
    while (child_address != ASTNode.invalid_pointer) {
        const next_address = context.node_allocator.at(child_address).next;
        if (nodeIs(context, child_address, "Rule")) {
            try mutable_rules.append(allocator, try mutableRuleFromAst(context, child_address));
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

fn mutableRuleFromAst(context: *data_structures.Context, rule_address: ASTNode.Pointer) !MutableRule {
    const allocator = context.runtime().arena_allocator;
    const header_address = firstChildNamed(context, rule_address, "VariableSymbol") orelse return error.MissingRuleHeader;
    const right_hand_sides_address = firstChildNamed(context, rule_address, "RightHandSides") orelse return error.MissingRightHandSides;

    var rule = MutableRule{ .header = try allocator.dupe(u8, nodeText(context, header_address)) };
    if (firstChildNamed(context, rule_address, "ProcedureTail")) |procedures_address| {
        try appendProcedureTail(context, &rule.procedures, procedures_address);
    }

    var child_address = context.node_allocator.at(right_hand_sides_address).first_child;
    while (child_address != ASTNode.invalid_pointer) {
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

fn rightHandSideFromAst(context: *data_structures.Context, line_address: ASTNode.Pointer) !?MutableRightHandSide {
    const allocator = context.runtime().arena_allocator;
    const line_procedures_address = firstChildNamed(context, line_address, "ProcedureTail") orelse return null;
    const rhs_address = firstChildNamed(context, line_address, "RightHandSide") orelse
        firstChildNamed(context, line_address, "NonEmptyRightHandSide");

    var rhs = MutableRightHandSide{};
    try appendProcedureTail(context, &rhs.procedures, line_procedures_address);
    const symbols_parent_address = rhs_address orelse return rhs;

    var child_address = context.node_allocator.at(symbols_parent_address).first_child;
    while (child_address != ASTNode.invalid_pointer) {
        if (!nodeIs(context, child_address, "Symbol")) {
            child_address = context.node_allocator.at(child_address).next;
            continue;
        }

        const procedure_tail_address = nextSiblingNamed(context, child_address, "ProcedureTail") orelse return error.MissingSymbolProcedures;
        try rhs.symbols.append(allocator, try symbolFromAst(context, child_address, procedure_tail_address));
        child_address = context.node_allocator.at(procedure_tail_address).next;
    }

    return rhs;
}

fn symbolFromAst(context: *data_structures.Context, symbol_address: ASTNode.Pointer, procedure_tail_address: ASTNode.Pointer) !SymbolRef {
    const allocator = context.runtime().arena_allocator;
    const concrete_address = firstChild(context, symbol_address) orelse return error.MissingSymbol;
    const raw_id = nodeText(context, concrete_address);
    const kind: SymbolKind = if (nodeIs(context, concrete_address, "VariableSymbol"))
        .variable
    else if (nodeIs(context, concrete_address, "TerminalSymbol"))
        .terminal
    else
        .generative_terminal;

    var procedures = std.ArrayList([]const u8).empty;
    try appendProcedureTail(context, &procedures, procedure_tail_address);

    return .{
        .id = try decodeEscapes(allocator, raw_id),
        .kind = kind,
        .procedures = try procedures.toOwnedSlice(allocator),
    };
}

fn appendProcedureTail(context: *data_structures.Context, target: *std.ArrayList([]const u8), procedure_tail_address: ASTNode.Pointer) !void {
    const allocator = context.runtime().arena_allocator;
    var child_address = context.node_allocator.at(procedure_tail_address).first_child;
    while (child_address != ASTNode.invalid_pointer) {
        const next_address = context.node_allocator.at(child_address).next;
        if (nodeIs(context, child_address, "CamelCaseId")) {
            try target.append(allocator, try allocator.dupe(u8, nodeText(context, child_address)));
        }
        child_address = next_address;
    }
}

fn firstChild(context: *data_structures.Context, node_address: ASTNode.Pointer) ?ASTNode.Pointer {
    const node = context.node_allocator.at(node_address);
    if (node.first_child == ASTNode.invalid_pointer) return null;
    return node.first_child;
}

fn firstChildNamed(context: *data_structures.Context, node_address: ASTNode.Pointer, name: []const u8) ?ASTNode.Pointer {
    var child_address = context.node_allocator.at(node_address).first_child;
    while (child_address != ASTNode.invalid_pointer) {
        const next_address = context.node_allocator.at(child_address).next;
        if (nodeIs(context, child_address, name)) return child_address;
        child_address = next_address;
    }
    return null;
}

fn nextSiblingNamed(context: *data_structures.Context, node_address: ASTNode.Pointer, name: []const u8) ?ASTNode.Pointer {
    var sibling_address = context.node_allocator.at(node_address).next;
    while (sibling_address != ASTNode.invalid_pointer) {
        const next_address = context.node_allocator.at(sibling_address).next;
        if (nodeIs(context, sibling_address, name)) return sibling_address;
        sibling_address = next_address;
    }
    return null;
}

fn nodeIs(context: *data_structures.Context, node_address: ASTNode.Pointer, name: []const u8) bool {
    const node = context.node_allocator.at(node_address);
    if (node.variable >= root.parser.variables.len) return false;
    return std.mem.eql(u8, root.parser.variables[node.variable], name);
}

fn nodeText(context: *data_structures.Context, node_address: ASTNode.Pointer) []const u8 {
    const node = context.node_allocator.at(node_address);
    return context.getTextSlice(node.text_start, node.text_length);
}

pub fn grammarFromContext(context: *data_structures.Context) ?*Grammar {
    if (last_grammar) |grammar| return grammar;
    return grammarFromAstAllocator(context.node_allocator);
}

pub fn grammarFromAstAllocator(node_allocator: *data_structures.ASTAllocator) ?*Grammar {
    var index: usize = 0;
    while (index < node_allocator.counter) : (index += 1) {
        const node = node_allocator.at(@intCast(index));
        if (node.payload.grammar) |grammar| return grammar;
    }
    return null;
}

pub fn emitLlParser(grammar: *const Grammar, allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    try ll_generator.emitParser(allocator, grammar, writer);
}

pub fn emitLlParserWithOptions(grammar: *const Grammar, allocator: std.mem.Allocator, writer: *std.Io.Writer, options: ll_generator.Options) !void {
    try ll_generator.emitParserWithOptions(allocator, grammar, writer, options);
}

pub fn emitLlParserFromContext(context: *data_structures.Context, allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    const grammar = grammarFromContext(context) orelse return error.GrammarModelMissing;
    try emitLlParserWithOptions(grammar, allocator, writer, generatorOptionsFromContext(context));
}

pub fn emitLrParser(grammar: *const Grammar, allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    try lr_generator.emitParser(allocator, grammar, writer);
}

pub fn emitLrParserWithOptions(grammar: *const Grammar, allocator: std.mem.Allocator, writer: *std.Io.Writer, options: lr_generator.Options) !void {
    try lr_generator.emitParserWithOptions(allocator, grammar, writer, options);
}

pub fn emitLrParserFromContext(context: *data_structures.Context, allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    const grammar = grammarFromContext(context) orelse return error.GrammarModelMissing;
    try emitLrParserWithOptions(grammar, allocator, writer, lrGeneratorOptionsFromContext(context));
}

fn emitParserForInputPath(context: *data_structures.Context, grammar: *const Grammar) !void {
    const input_path = context.runtime().input_path orelse return;
    const parser_type: enum { ll, lr } = if (std.mem.endsWith(u8, input_path, "/ll.grm") or std.mem.eql(u8, input_path, "ll.grm"))
        .ll
    else if (std.mem.endsWith(u8, input_path, "/lr.grm") or std.mem.eql(u8, input_path, "lr.grm"))
        .lr
    else
        return;

    const dir_path = std.fs.path.dirname(input_path) orelse ".";
    const output_file = switch (parser_type) {
        .ll => "_ll-parser.zig",
        .lr => "_lr-parser.zig",
    };
    const output_path = try std.fs.path.join(context.runtime().arena_allocator, &.{ dir_path, output_file });

    var output = try std.Io.Dir.cwd().createFile(context.runtime().io, output_path, .{ .truncate = true });
    defer output.close(context.runtime().io);

    var buffer: [8192]u8 = undefined;
    var file_writer = output.writer(context.runtime().io, &buffer);
    switch (parser_type) {
        .ll => try emitLlParserWithOptions(grammar, context.runtime().arena_allocator, &file_writer.interface, generatorOptionsFromContext(context)),
        .lr => try emitLrParserWithOptions(grammar, context.runtime().arena_allocator, &file_writer.interface, lrGeneratorOptionsFromContext(context)),
    }
    try file_writer.interface.flush();
}

fn generatorOptionsFromContext(context: *data_structures.Context) ll_generator.Options {
    return .{
        .with_ast = context.runtime().language_options.with_ast,
        .with_procedures = context.runtime().language_options.with_procedures,
        .ast_for_terminals = context.runtime().language_options.ast_for_terminals,
        .input_size = context.runtime().language_options.input_size,
    };
}

fn lrGeneratorOptionsFromContext(context: *data_structures.Context) lr_generator.Options {
    return .{
        .with_ast = context.runtime().language_options.with_ast,
        .with_procedures = context.runtime().language_options.with_procedures,
        .ast_for_terminals = context.runtime().language_options.ast_for_terminals,
        .input_size = context.runtime().language_options.input_size,
    };
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
