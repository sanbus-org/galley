const builtin = @import("builtin");
const std = @import("std");
const root = @import("galley");
const procedures = root.procedures;
const error_messages = root.error_messages;
const data_structures = root.data_structures;
const string_utilities = root.string_utilities;

pub const parser_type = data_structures.ParserType.ll;
pub const is_ast_enabled = true;
pub const are_procedures_enabled = true;
pub const is_error_recovery_enabled = false;
pub const input_size_cap = u16;
pub const longest_terminal_length = 1;

pub const symbols = &[_][]const u8{
    "Start", // 0
    "Rules", // 1
    "Rule", // 2
    "RulesTail", // 3
    "NewLines", // 4
    "new_line", // 5
    "NewLinesTail", // 6
    "#", // 7
    "AnyContent", // 8
    "VariableSymbol", // 9
    "ProcedureTail", // 10
    "RightHandSides", // 11
    "RightHandSideLine", // 12
    "RightHandSidesTail", // 13
    "|", // 14
    "RightHandSide", // 15
    "space", // 16
    "Symbol", // 17
    "RightHandSideTail", // 18
    "TerminalSymbol", // 19
    "GenerativeTerminalSymbol", // 20
    "UppercaseId", // 21
    "_", // 22
    "'", // 23
    "StringContent", // 24
    "\x03", // 25
    "\"", // 26
    "SimpleStringContent", // 27
    "LowercaseId", // 28
    "GenerativeTerminalExceptions", // 29
    "^", // 30
    "@", // 31
    "CamelCaseId", // 32
    "character", // 33
    "character^'\"\x03", // 34
    "ControlCharacter", // 35
    "\x01", // 36
    "\x04", // 37
    "character^\"\n\"", // 38
    "AnyContentTail", // 39
    "IdTail", // 40
    "letter", // 41
    "digit", // 42
    "lowercase_letter", // 43
    "uppercase_letter", // 44
    "CamelCaseIdTail", // 45
    "_AugmentedStart", // 46
    "\x00", // 47
    "GenerativeTerminal", // 48
};

pub const is_terminal = &[_]bool{
    false,
    false,
    false,
    false,
    false,
    true,
    false,
    true,
    false,
    false,
    false,
    false,
    false,
    false,
    true,
    false,
    true,
    false,
    false,
    false,
    false,
    false,
    true,
    true,
    false,
    true,
    true,
    false,
    false,
    false,
    true,
    true,
    false,
    true,
    true,
    false,
    true,
    true,
    true,
    false,
    false,
    true,
    true,
    true,
    true,
    false,
    false,
    true,
    false,
};

pub const is_generative_terminal = &[_]bool{
    false,
    false,
    false,
    false,
    false,
    true,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    true,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    false,
    true,
    true,
    false,
    false,
    false,
    true,
    false,
    false,
    true,
    true,
    true,
    true,
    false,
    false,
    false,
    false,
};

pub const variables = &[_][]const u8{
    "Start",
    "Rules",
    "Rule",
    "RulesTail",
    "NewLines",
    "NewLinesTail",
    "AnyContent",
    "VariableSymbol",
    "ProcedureTail",
    "RightHandSides",
    "RightHandSideLine",
    "RightHandSidesTail",
    "RightHandSide",
    "Symbol",
    "RightHandSideTail",
    "TerminalSymbol",
    "GenerativeTerminalSymbol",
    "UppercaseId",
    "StringContent",
    "SimpleStringContent",
    "LowercaseId",
    "GenerativeTerminalExceptions",
    "CamelCaseId",
    "ControlCharacter",
    "AnyContentTail",
    "IdTail",
    "CamelCaseIdTail",
    "_AugmentedStart",
    "GenerativeTerminal",
};

pub const symbol_by_variable = &[_]usize{
    0,
    1,
    2,
    3,
    4,
    6,
    8,
    9,
    10,
    11,
    12,
    13,
    15,
    17,
    18,
    19,
    20,
    21,
    24,
    27,
    28,
    29,
    32,
    35,
    39,
    40,
    45,
    46,
    48,
};

pub const rules = &[_]data_structures.Rule{
    data_structures.Rule{ .header = 6, .right_hand_side = &[_]u16{ 35, 39 }, .right_hand_side_index = "1" }, // AnyContent
    data_structures.Rule{ .header = 6, .right_hand_side = &[_]u16{ 38, 39 }, .right_hand_side_index = "0" }, // AnyContent
    data_structures.Rule{ .header = 24, .right_hand_side = &[_]u16{}, .right_hand_side_index = "2" }, // AnyContentTail
    data_structures.Rule{ .header = 24, .right_hand_side = &[_]u16{ 35, 39 }, .right_hand_side_index = "1" }, // AnyContentTail
    data_structures.Rule{ .header = 24, .right_hand_side = &[_]u16{ 38, 39 }, .right_hand_side_index = "0" }, // AnyContentTail
    data_structures.Rule{ .header = 22, .right_hand_side = &[_]u16{ 43, 45 }, .right_hand_side_index = "0" }, // CamelCaseId
    data_structures.Rule{ .header = 26, .right_hand_side = &[_]u16{}, .right_hand_side_index = "2" }, // CamelCaseIdTail
    data_structures.Rule{ .header = 26, .right_hand_side = &[_]u16{ 41, 45 }, .right_hand_side_index = "0" }, // CamelCaseIdTail
    data_structures.Rule{ .header = 26, .right_hand_side = &[_]u16{ 42, 45 }, .right_hand_side_index = "1" }, // CamelCaseIdTail
    data_structures.Rule{ .header = 23, .right_hand_side = &[_]u16{25}, .right_hand_side_index = "1" }, // ControlCharacter
    data_structures.Rule{ .header = 23, .right_hand_side = &[_]u16{36}, .right_hand_side_index = "0" }, // ControlCharacter
    data_structures.Rule{ .header = 23, .right_hand_side = &[_]u16{37}, .right_hand_side_index = "2" }, // ControlCharacter
    data_structures.Rule{ .header = 28, .right_hand_side = &[_]u16{}, .right_hand_side_index = "0" }, // GenerativeTerminal
    data_structures.Rule{ .header = 21, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // GenerativeTerminalExceptions
    data_structures.Rule{ .header = 21, .right_hand_side = &[_]u16{ 30, 19, 29 }, .right_hand_side_index = "0" }, // GenerativeTerminalExceptions
    data_structures.Rule{ .header = 16, .right_hand_side = &[_]u16{ 28, 29 }, .right_hand_side_index = "0" }, // GenerativeTerminalSymbol
    data_structures.Rule{ .header = 25, .right_hand_side = &[_]u16{}, .right_hand_side_index = "3" }, // IdTail
    data_structures.Rule{ .header = 25, .right_hand_side = &[_]u16{ 22, 40 }, .right_hand_side_index = "2" }, // IdTail
    data_structures.Rule{ .header = 25, .right_hand_side = &[_]u16{ 41, 40 }, .right_hand_side_index = "0" }, // IdTail
    data_structures.Rule{ .header = 25, .right_hand_side = &[_]u16{ 42, 40 }, .right_hand_side_index = "1" }, // IdTail
    data_structures.Rule{ .header = 20, .right_hand_side = &[_]u16{ 43, 40 }, .right_hand_side_index = "0" }, // LowercaseId
    data_structures.Rule{ .header = 4, .right_hand_side = &[_]u16{ 5, 6 }, .right_hand_side_index = "0" }, // NewLines
    data_structures.Rule{ .header = 5, .right_hand_side = &[_]u16{}, .right_hand_side_index = "2" }, // NewLinesTail
    data_structures.Rule{ .header = 5, .right_hand_side = &[_]u16{ 5, 6 }, .right_hand_side_index = "0" }, // NewLinesTail
    data_structures.Rule{ .header = 5, .right_hand_side = &[_]u16{ 7, 8, 5, 6 }, .right_hand_side_index = "1" }, // NewLinesTail
    data_structures.Rule{ .header = 8, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // ProcedureTail
    data_structures.Rule{ .header = 8, .right_hand_side = &[_]u16{ 31, 32, 10 }, .right_hand_side_index = "0" }, // ProcedureTail
    data_structures.Rule{ .header = 12, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // RightHandSide
    data_structures.Rule{ .header = 12, .right_hand_side = &[_]u16{ 16, 17, 10, 18 }, .right_hand_side_index = "0" }, // RightHandSide
    data_structures.Rule{ .header = 10, .right_hand_side = &[_]u16{ 7, 8, 5 }, .right_hand_side_index = "1" }, // RightHandSideLine
    data_structures.Rule{ .header = 10, .right_hand_side = &[_]u16{ 14, 10, 15, 5 }, .right_hand_side_index = "0" }, // RightHandSideLine
    data_structures.Rule{ .header = 14, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // RightHandSideTail
    data_structures.Rule{ .header = 14, .right_hand_side = &[_]u16{ 16, 17, 10, 18 }, .right_hand_side_index = "0" }, // RightHandSideTail
    data_structures.Rule{ .header = 9, .right_hand_side = &[_]u16{ 12, 13 }, .right_hand_side_index = "0" }, // RightHandSides
    data_structures.Rule{ .header = 11, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // RightHandSidesTail
    data_structures.Rule{ .header = 11, .right_hand_side = &[_]u16{ 12, 13 }, .right_hand_side_index = "0" }, // RightHandSidesTail
    data_structures.Rule{ .header = 2, .right_hand_side = &[_]u16{ 9, 10, 5, 11 }, .right_hand_side_index = "0" }, // Rule
    data_structures.Rule{ .header = 1, .right_hand_side = &[_]u16{ 2, 3 }, .right_hand_side_index = "0" }, // Rules
    data_structures.Rule{ .header = 3, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // RulesTail
    data_structures.Rule{ .header = 3, .right_hand_side = &[_]u16{ 4, 2, 3 }, .right_hand_side_index = "0" }, // RulesTail
    data_structures.Rule{ .header = 19, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // SimpleStringContent
    data_structures.Rule{ .header = 19, .right_hand_side = &[_]u16{ 34, 27 }, .right_hand_side_index = "0" }, // SimpleStringContent
    data_structures.Rule{ .header = 0, .right_hand_side = &[_]u16{1}, .right_hand_side_index = "0" }, // Start
    data_structures.Rule{ .header = 18, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // StringContent
    data_structures.Rule{ .header = 18, .right_hand_side = &[_]u16{ 33, 24 }, .right_hand_side_index = "0" }, // StringContent
    data_structures.Rule{ .header = 13, .right_hand_side = &[_]u16{9}, .right_hand_side_index = "0" }, // Symbol
    data_structures.Rule{ .header = 13, .right_hand_side = &[_]u16{19}, .right_hand_side_index = "1" }, // Symbol
    data_structures.Rule{ .header = 13, .right_hand_side = &[_]u16{20}, .right_hand_side_index = "2" }, // Symbol
    data_structures.Rule{ .header = 15, .right_hand_side = &[_]u16{ 23, 24, 25 }, .right_hand_side_index = "0" }, // TerminalSymbol
    data_structures.Rule{ .header = 15, .right_hand_side = &[_]u16{ 26, 27, 26 }, .right_hand_side_index = "1" }, // TerminalSymbol
    data_structures.Rule{ .header = 17, .right_hand_side = &[_]u16{ 44, 40 }, .right_hand_side_index = "0" }, // UppercaseId
    data_structures.Rule{ .header = 7, .right_hand_side = &[_]u16{21}, .right_hand_side_index = "0" }, // VariableSymbol
    data_structures.Rule{ .header = 7, .right_hand_side = &[_]u16{ 22, 21 }, .right_hand_side_index = "1" }, // VariableSymbol
    data_structures.Rule{ .header = 27, .right_hand_side = &[_]u16{ 0, 47 }, .right_hand_side_index = "0" }, // _AugmentedStart
};

const ProcedureSequenceNode = struct {
    procedure: *const data_structures.Procedure,
    next: ?*const ProcedureSequenceNode,
};

fn makeProcedureSequence(comptime procedure_names: []const []const u8) ?*const ProcedureSequenceNode {
    if (procedure_names.len == 0) return null;
    const procedure_name = procedure_names[0];
    return &ProcedureSequenceNode{
        .procedure = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), procedure_name),
        .next = makeProcedureSequence(procedure_names[1..]),
    };
}

fn runProcedureSequence(sequence: ?*const ProcedureSequenceNode, args: *data_structures.ProcedureArguments) !void {
    var current = sequence;
    while (current) |entry| {
        const procedure = @as(*data_structures.Procedure, @constCast(entry.procedure));
        try procedure(args);
        current = entry.next;
    }
}

pub const rule_procedures = rule_procedures: {
    var arr: [54]?*const data_structures.Procedure = .{null} ** 54;

    for (rules, 0..) |rule, index| {
        const procedure_name = "reduction_" ++ variables[rule.header] ++ "_" ++ rule.right_hand_side_index;
        if (@hasDecl(procedures, procedure_name)) {
            arr[index] = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), procedure_name);
        }
    }

    break :rule_procedures arr;
};

pub const symbol_procedures = symbol_procedures: {
    var arr: [49]?*const data_structures.Procedure = .{null} ** 49;

    for (symbols, 0..) |symbol, index| {
        const procedure_name = "reduction_" ++ symbol;
        if (@hasDecl(procedures, procedure_name)) {
            arr[index] = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), symbol);
        }
    }

    break :symbol_procedures arr;
};

const variable_procedure_names = &[_][]const []const u8{
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
};

pub const variable_procedures = variable_procedures: {
    var arr: [29]?*const ProcedureSequenceNode = .{null} ** 29;

    for (variable_procedure_names, 0..) |procedure_names, index| {
        arr[index] = makeProcedureSequence(procedure_names);
    }

    break :variable_procedures arr;
};

pub const reduction_procedure: ?*const data_structures.Procedure = if (@hasDecl(procedures, "reduction")) data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, "reduction"), "reduction") else null;

// Parser for Symbol "Start" with index 0
fn parse_Start(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 0);

    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Start -> Rules\n", .{});
                }
            }
            {
                const child_node = try parse_Rules(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[42],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[42]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[0], &args);
            if (comptime symbol_procedures[0]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for Start: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Start <~ Rules\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "Start" }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_Start__expected_Rules"))
                    @field(error_messages, "syntax_error_ll_Start__expected_Rules")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_Start"))
                    @field(error_messages, "syntax_error_ll_Start")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "Rules" with index 1
fn parse_Rules(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 1);

    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Rules -> Rule, RulesTail\n", .{});
                }
            }
            {
                const child_node = try parse_Rule(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = try parse_RulesTail(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[37],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[37]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[1], &args);
            if (comptime symbol_procedures[1]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for Rules: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Rules <~ Rule, RulesTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "Rules" }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_Rules__expected_Rule"))
                    @field(error_messages, "syntax_error_ll_Rules__expected_Rule")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_Rules"))
                    @field(error_messages, "syntax_error_ll_Rules")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "Rule" with index 2
fn parse_Rule(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 2);

    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Rule -> VariableSymbol, ProcedureTail, 'new_line', RightHandSides\n", .{});
                }
            }
            {
                const child_node = try parse_VariableSymbol(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = try parse_ProcedureTail(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            try parse_generative_terminal_new_line(context); // child 2
            {
                const child_node = try parse_RightHandSides(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 3 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[36],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[36]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[2], &args);
            if (comptime symbol_procedures[2]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for Rule: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Rule <~ VariableSymbol, ProcedureTail, 'new_line', RightHandSides\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "Rule" }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_Rule__expected_VariableSymbol"))
                    @field(error_messages, "syntax_error_ll_Rule__expected_VariableSymbol")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_Rule"))
                    @field(error_messages, "syntax_error_ll_Rule")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "RulesTail" at index 2 of its right hand side
// Right hand side: -> NewLines, Rule, RulesTail
fn parse_RulesTail_0_2(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
    var repeating_node: *data_structures.ASTNode = undefined;
    repeating_node = repeating_node; // dummy store for 0-repetition paths
    _ = &repeating_node;

    while (true) {
        switch (context.head(u8, 0)) {
            10 => { // '\n'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: RulesTail -> NewLines, Rule, RulesTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 3);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 2
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                {
                    const child_node = try parse_NewLines(context);
                    if (child_node != data_structures.ASTNode.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                    }
                }
                {
                    const child_node = try parse_Rule(context);
                    if (child_node != data_structures.ASTNode.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                    }
                }
            },
            else => break,
        }
    }
    const exit_node = try parse_RulesTail(context);
    if (exit_node != data_structures.ASTNode.invalid_pointer) {
        if (node_address == data_structures.ASTNode.invalid_pointer) {
            node_address = exit_node;
        } else {
            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: RulesTail <~ NewLines, Rule, RulesTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[39],
            .node = repeating_node_address,
        };
        _ = &args;
        args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[39]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[3], &args);
        if (comptime symbol_procedures[3]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        if (comptime reduction_procedure) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 2) {
                std.debug.print("Procedure outcome for RulesTail: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        if (args.node) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.ASTNode.invalid_pointer;
            }
        }
        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "RulesTail" with index 3
fn parse_RulesTail(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 3);

    switch (context.head(u8, 0)) {
        0 => { // '\x00'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RulesTail -> \n", .{});
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[38],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[38]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[3], &args);
            if (comptime symbol_procedures[3]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for RulesTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RulesTail <~ \n", .{});
                }
            }
        },
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RulesTail -> NewLines, Rule, RulesTail\n", .{});
                }
            }
            {
                const child_node = try parse_NewLines(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = try parse_Rule(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = try parse_RulesTail_0_2(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[39],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[39]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[3], &args);
            if (comptime symbol_procedures[3]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for RulesTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RulesTail <~ NewLines, Rule, RulesTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "RulesTail" }, &[_][]const u8{"\x00", "\n"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_RulesTail__expected_NewLines_or_end_of_RulesTail"))
                    @field(error_messages, "syntax_error_ll_RulesTail__expected_NewLines_or_end_of_RulesTail")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_RulesTail"))
                    @field(error_messages, "syntax_error_ll_RulesTail")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "NewLines" with index 4
fn parse_NewLines(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 4);

    switch (context.head(u8, 0)) {
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: NewLines -> 'new_line', NewLinesTail\n", .{});
                }
            }
            try parse_generative_terminal_new_line(context); // child 0
            {
                const child_node = try parse_NewLinesTail(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[21],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[21]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[4], &args);
            if (comptime symbol_procedures[4]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for NewLines: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: NewLines <~ 'new_line', NewLinesTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "NewLines" }, &[_][]const u8{"\n"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_NewLines__expected_generative_terminal_new_line"))
                    @field(error_messages, "syntax_error_ll_NewLines__expected_generative_terminal_new_line")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_NewLines"))
                    @field(error_messages, "syntax_error_ll_NewLines")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "generative_terminal_new_line" with index 5
inline fn parse_generative_terminal_new_line(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        10 => { // '\n'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "new_line" }, &[_][]const u8{"\n"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_new_line__expected_generative_terminal_new_line"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_new_line__expected_generative_terminal_new_line")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_new_line"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_new_line")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Self-Repeating Parser for Symbol "NewLinesTail" at index 1 of its right hand side
// Right hand side: -> 'new_line', NewLinesTail
fn parse_NewLinesTail_0_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
    var repeating_node: *data_structures.ASTNode = undefined;
    repeating_node = repeating_node; // dummy store for 0-repetition paths
    _ = &repeating_node;

    while (true) {
        switch (context.head(u8, 0)) {
            10 => { // '\n'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: NewLinesTail -> 'new_line', NewLinesTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 5);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_generative_terminal_new_line(context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_NewLinesTail(context);
    if (exit_node != data_structures.ASTNode.invalid_pointer) {
        if (node_address == data_structures.ASTNode.invalid_pointer) {
            node_address = exit_node;
        } else {
            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: NewLinesTail <~ 'new_line', NewLinesTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[23],
            .node = repeating_node_address,
        };
        _ = &args;
        args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[23]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[5], &args);
        if (comptime symbol_procedures[6]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        if (comptime reduction_procedure) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 2) {
                std.debug.print("Procedure outcome for NewLinesTail: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        if (args.node) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.ASTNode.invalid_pointer;
            }
        }
        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "NewLinesTail" at index 3 of its right hand side
// Right hand side: -> '#', AnyContent, 'new_line', NewLinesTail
fn parse_NewLinesTail_1_3(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
    var repeating_node: *data_structures.ASTNode = undefined;
    repeating_node = repeating_node; // dummy store for 0-repetition paths
    _ = &repeating_node;

    while (true) {
        switch (context.head(u8, 0)) {
            35 => { // '#'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: NewLinesTail -> '#', AnyContent, 'new_line', NewLinesTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 5);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 3
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_terminal__x35(context); // child 0
                {
                    const child_node = try parse_AnyContent(context);
                    if (child_node != data_structures.ASTNode.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                    }
                }
                try parse_generative_terminal_new_line(context); // child 2
            },
            else => break,
        }
    }
    const exit_node = try parse_NewLinesTail(context);
    if (exit_node != data_structures.ASTNode.invalid_pointer) {
        if (node_address == data_structures.ASTNode.invalid_pointer) {
            node_address = exit_node;
        } else {
            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 3 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: NewLinesTail <~ '#', AnyContent, 'new_line', NewLinesTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[24],
            .node = repeating_node_address,
        };
        _ = &args;
        args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[24]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[5], &args);
        if (comptime symbol_procedures[6]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        if (comptime reduction_procedure) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 2) {
                std.debug.print("Procedure outcome for NewLinesTail: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        if (args.node) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.ASTNode.invalid_pointer;
            }
        }
        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "NewLinesTail" with index 6
fn parse_NewLinesTail(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 5);

    switch (context.head(u8, 0)) {
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: NewLinesTail -> 'new_line', NewLinesTail\n", .{});
                }
            }
            try parse_generative_terminal_new_line(context); // child 0
            {
                const child_node = try parse_NewLinesTail_0_1(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[23],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[23]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[5], &args);
            if (comptime symbol_procedures[6]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for NewLinesTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: NewLinesTail <~ 'new_line', NewLinesTail\n", .{});
                }
            }
        },
        35 => { // '#'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: NewLinesTail -> '#', AnyContent, 'new_line', NewLinesTail\n", .{});
                }
            }
            try parse_terminal__x35(context); // child 0
            {
                const child_node = try parse_AnyContent(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            try parse_generative_terminal_new_line(context); // child 2
            {
                const child_node = try parse_NewLinesTail_1_3(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 3 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[24],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[24]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[5], &args);
            if (comptime symbol_procedures[6]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for NewLinesTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: NewLinesTail <~ '#', AnyContent, 'new_line', NewLinesTail\n", .{});
                }
            }
        },
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: NewLinesTail -> \n", .{});
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[22],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[22]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[5], &args);
            if (comptime symbol_procedures[6]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for NewLinesTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: NewLinesTail <~ \n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "NewLinesTail" }, &[_][]const u8{"\n", "#", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_NewLinesTail__expected_end_of_NewLinesTail_or_generative_terminal_new_line_or_terminal__x35"))
                    @field(error_messages, "syntax_error_ll_NewLinesTail__expected_end_of_NewLinesTail_or_generative_terminal_new_line_or_terminal__x35")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_NewLinesTail"))
                    @field(error_messages, "syntax_error_ll_NewLinesTail")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_#" with index 7
inline fn parse_terminal__x35(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        35 => { // '#'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "#" }, &[_][]const u8{"#"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x35__expected_terminal__x35"))
                    @field(error_messages, "syntax_error_ll_terminal__x35__expected_terminal__x35")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x35"))
                    @field(error_messages, "syntax_error_ll_terminal__x35")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Parser for Symbol "AnyContent" with index 8
fn parse_AnyContent(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 6);

    switch (context.head(u8, 0)) {
        1, 3, 4 => { // '\x01', '\x03', '\x04'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: AnyContent -> ControlCharacter, AnyContentTail\n", .{});
                }
            }
            {
                const child_node = try parse_ControlCharacter(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = try parse_AnyContentTail(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[0],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[0]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[6], &args);
            if (comptime symbol_procedures[8]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for AnyContent: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: AnyContent <~ ControlCharacter, AnyContentTail\n", .{});
                }
            }
        },
        9, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: AnyContent -> 'character^\"\\n\"', AnyContentTail\n", .{});
                }
            }
            try parse_generative_terminal_character_x94_x34_x92n_x34(context); // child 0
            {
                const child_node = try parse_AnyContentTail(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[1],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[1]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[6], &args);
            if (comptime symbol_procedures[8]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for AnyContent: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: AnyContent <~ 'character^\"\\n\"', AnyContentTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "AnyContent" }, &[_][]const u8{"\x01", "\x03", "\x04", "\t", "\x0b", "\x0c", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_AnyContent__expected_ControlCharacter_or_generative_terminal_character_x94_x34_x92n_x34"))
                    @field(error_messages, "syntax_error_ll_AnyContent__expected_ControlCharacter_or_generative_terminal_character_x94_x34_x92n_x34")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_AnyContent"))
                    @field(error_messages, "syntax_error_ll_AnyContent")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "VariableSymbol" with index 9
fn parse_VariableSymbol(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 7);

    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: VariableSymbol -> UppercaseId\n", .{});
                }
            }
            {
                const child_node = try parse_UppercaseId(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[51],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[51]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[7], &args);
            if (comptime symbol_procedures[9]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for VariableSymbol: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: VariableSymbol <~ UppercaseId\n", .{});
                }
            }
        },
        95 => { // '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: VariableSymbol -> '_', UppercaseId\n", .{});
                }
            }
            try parse_terminal__(context); // child 0
            {
                const child_node = try parse_UppercaseId(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[52],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[52]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[7], &args);
            if (comptime symbol_procedures[9]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for VariableSymbol: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: VariableSymbol <~ '_', UppercaseId\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "VariableSymbol" }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_VariableSymbol__expected_UppercaseId_or_terminal__"))
                    @field(error_messages, "syntax_error_ll_VariableSymbol__expected_UppercaseId_or_terminal__")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_VariableSymbol"))
                    @field(error_messages, "syntax_error_ll_VariableSymbol")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "ProcedureTail" at index 2 of its right hand side
// Right hand side: -> '@', CamelCaseId, ProcedureTail
fn parse_ProcedureTail_0_2(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
    var repeating_node: *data_structures.ASTNode = undefined;
    repeating_node = repeating_node; // dummy store for 0-repetition paths
    _ = &repeating_node;

    while (true) {
        switch (context.head(u8, 0)) {
            64 => { // '@'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: ProcedureTail -> '@', CamelCaseId, ProcedureTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 8);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 2
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_terminal__x64(context); // child 0
                {
                    const child_node = try parse_CamelCaseId(context);
                    if (child_node != data_structures.ASTNode.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                    }
                }
            },
            else => break,
        }
    }
    const exit_node = try parse_ProcedureTail(context);
    if (exit_node != data_structures.ASTNode.invalid_pointer) {
        if (node_address == data_structures.ASTNode.invalid_pointer) {
            node_address = exit_node;
        } else {
            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: ProcedureTail <~ '@', CamelCaseId, ProcedureTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[26],
            .node = repeating_node_address,
        };
        _ = &args;
        args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[26]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[8], &args);
        if (comptime symbol_procedures[10]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        if (comptime reduction_procedure) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 2) {
                std.debug.print("Procedure outcome for ProcedureTail: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        if (args.node) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.ASTNode.invalid_pointer;
            }
        }
        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "ProcedureTail" with index 10
fn parse_ProcedureTail(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 8);

    switch (context.head(u8, 0)) {
        10, 32 => { // '\n', ' '
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: ProcedureTail -> \n", .{});
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[25],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[25]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[8], &args);
            if (comptime symbol_procedures[10]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for ProcedureTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: ProcedureTail <~ \n", .{});
                }
            }
        },
        64 => { // '@'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: ProcedureTail -> '@', CamelCaseId, ProcedureTail\n", .{});
                }
            }
            try parse_terminal__x64(context); // child 0
            {
                const child_node = try parse_CamelCaseId(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = try parse_ProcedureTail_0_2(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[26],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[26]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[8], &args);
            if (comptime symbol_procedures[10]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for ProcedureTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: ProcedureTail <~ '@', CamelCaseId, ProcedureTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "ProcedureTail" }, &[_][]const u8{"\n", " ", "@"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_ProcedureTail__expected_end_of_ProcedureTail_or_terminal__x64"))
                    @field(error_messages, "syntax_error_ll_ProcedureTail__expected_end_of_ProcedureTail_or_terminal__x64")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_ProcedureTail"))
                    @field(error_messages, "syntax_error_ll_ProcedureTail")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "RightHandSides" with index 11
fn parse_RightHandSides(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 9);

    switch (context.head(u8, 0)) {
        35, 124 => { // '#', '|'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSides -> RightHandSideLine, RightHandSidesTail\n", .{});
                }
            }
            {
                const child_node = try parse_RightHandSideLine(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = try parse_RightHandSidesTail(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[33],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[33]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[9], &args);
            if (comptime symbol_procedures[11]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for RightHandSides: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSides <~ RightHandSideLine, RightHandSidesTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "RightHandSides" }, &[_][]const u8{"#", "|"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_RightHandSides__expected_RightHandSideLine"))
                    @field(error_messages, "syntax_error_ll_RightHandSides__expected_RightHandSideLine")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_RightHandSides"))
                    @field(error_messages, "syntax_error_ll_RightHandSides")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "RightHandSideLine" with index 12
fn parse_RightHandSideLine(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 10);

    switch (context.head(u8, 0)) {
        35 => { // '#'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSideLine -> '#', AnyContent, 'new_line'\n", .{});
                }
            }
            try parse_terminal__x35(context); // child 0
            {
                const child_node = try parse_AnyContent(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            try parse_generative_terminal_new_line(context); // child 2
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[29],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[29]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[10], &args);
            if (comptime symbol_procedures[12]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for RightHandSideLine: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSideLine <~ '#', AnyContent, 'new_line'\n", .{});
                }
            }
        },
        124 => { // '|'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSideLine -> '|', ProcedureTail, RightHandSide, 'new_line'\n", .{});
                }
            }
            try parse_terminal__x124(context); // child 0
            {
                const child_node = try parse_ProcedureTail(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = try parse_RightHandSide(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            try parse_generative_terminal_new_line(context); // child 3
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[30],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[30]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[10], &args);
            if (comptime symbol_procedures[12]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for RightHandSideLine: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSideLine <~ '|', ProcedureTail, RightHandSide, 'new_line'\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "RightHandSideLine" }, &[_][]const u8{"#", "|"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_RightHandSideLine__expected_terminal__x124_or_terminal__x35"))
                    @field(error_messages, "syntax_error_ll_RightHandSideLine__expected_terminal__x124_or_terminal__x35")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_RightHandSideLine"))
                    @field(error_messages, "syntax_error_ll_RightHandSideLine")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "RightHandSidesTail" at index 1 of its right hand side
// Right hand side: -> RightHandSideLine, RightHandSidesTail
fn parse_RightHandSidesTail_0_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
    var repeating_node: *data_structures.ASTNode = undefined;
    repeating_node = repeating_node; // dummy store for 0-repetition paths
    _ = &repeating_node;

    while (true) {
        switch (context.head(u8, 0)) {
            35, 124 => { // '#', '|'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: RightHandSidesTail -> RightHandSideLine, RightHandSidesTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 11);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                {
                    const child_node = try parse_RightHandSideLine(context);
                    if (child_node != data_structures.ASTNode.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                    }
                }
            },
            else => break,
        }
    }
    const exit_node = try parse_RightHandSidesTail(context);
    if (exit_node != data_structures.ASTNode.invalid_pointer) {
        if (node_address == data_structures.ASTNode.invalid_pointer) {
            node_address = exit_node;
        } else {
            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: RightHandSidesTail <~ RightHandSideLine, RightHandSidesTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[35],
            .node = repeating_node_address,
        };
        _ = &args;
        args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[35]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[11], &args);
        if (comptime symbol_procedures[13]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        if (comptime reduction_procedure) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 2) {
                std.debug.print("Procedure outcome for RightHandSidesTail: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        if (args.node) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.ASTNode.invalid_pointer;
            }
        }
        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "RightHandSidesTail" with index 13
fn parse_RightHandSidesTail(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 11);

    switch (context.head(u8, 0)) {
        0, 10 => { // '\x00', '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSidesTail -> \n", .{});
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[34],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[34]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[11], &args);
            if (comptime symbol_procedures[13]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for RightHandSidesTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSidesTail <~ \n", .{});
                }
            }
        },
        35, 124 => { // '#', '|'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSidesTail -> RightHandSideLine, RightHandSidesTail\n", .{});
                }
            }
            {
                const child_node = try parse_RightHandSideLine(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = try parse_RightHandSidesTail_0_1(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[35],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[35]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[11], &args);
            if (comptime symbol_procedures[13]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for RightHandSidesTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSidesTail <~ RightHandSideLine, RightHandSidesTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "RightHandSidesTail" }, &[_][]const u8{"\x00", "\n", "#", "|"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_RightHandSidesTail__expected_RightHandSideLine_or_end_of_RightHandSidesTail"))
                    @field(error_messages, "syntax_error_ll_RightHandSidesTail__expected_RightHandSideLine_or_end_of_RightHandSidesTail")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_RightHandSidesTail"))
                    @field(error_messages, "syntax_error_ll_RightHandSidesTail")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_|" with index 14
inline fn parse_terminal__x124(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        124 => { // '|'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "|" }, &[_][]const u8{"|"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x124__expected_terminal__x124"))
                    @field(error_messages, "syntax_error_ll_terminal__x124__expected_terminal__x124")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x124"))
                    @field(error_messages, "syntax_error_ll_terminal__x124")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Parser for Symbol "RightHandSide" with index 15
fn parse_RightHandSide(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 12);

    switch (context.head(u8, 0)) {
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSide -> \n", .{});
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[27],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[27]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[12], &args);
            if (comptime symbol_procedures[15]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for RightHandSide: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSide <~ \n", .{});
                }
            }
        },
        32 => { // ' '
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSide -> 'space', Symbol, ProcedureTail, RightHandSideTail\n", .{});
                }
            }
            try parse_generative_terminal_space(context); // child 0
            {
                const child_node = try parse_Symbol(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = try parse_ProcedureTail(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = try parse_RightHandSideTail(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 3 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[28],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[28]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[12], &args);
            if (comptime symbol_procedures[15]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for RightHandSide: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSide <~ 'space', Symbol, ProcedureTail, RightHandSideTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "RightHandSide" }, &[_][]const u8{"\n", " "});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_RightHandSide__expected_end_of_RightHandSide_or_generative_terminal_space"))
                    @field(error_messages, "syntax_error_ll_RightHandSide__expected_end_of_RightHandSide_or_generative_terminal_space")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_RightHandSide"))
                    @field(error_messages, "syntax_error_ll_RightHandSide")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "generative_terminal_space" with index 16
inline fn parse_generative_terminal_space(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        32 => { // ' '
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "space" }, &[_][]const u8{" "});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_space__expected_generative_terminal_space"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_space__expected_generative_terminal_space")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_space"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_space")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Parser for Symbol "Symbol" with index 17
fn parse_Symbol(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 13);

    switch (context.head(u8, 0)) {
        34, 39 => { // '\"', '''
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Symbol -> TerminalSymbol\n", .{});
                }
            }
            {
                const child_node = try parse_TerminalSymbol(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[46],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[46]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[13], &args);
            if (comptime symbol_procedures[17]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for Symbol: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Symbol <~ TerminalSymbol\n", .{});
                }
            }
        },
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Symbol -> VariableSymbol\n", .{});
                }
            }
            {
                const child_node = try parse_VariableSymbol(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[45],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[45]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[13], &args);
            if (comptime symbol_procedures[17]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for Symbol: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Symbol <~ VariableSymbol\n", .{});
                }
            }
        },
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Symbol -> GenerativeTerminalSymbol\n", .{});
                }
            }
            {
                const child_node = try parse_GenerativeTerminalSymbol(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[47],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[47]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[13], &args);
            if (comptime symbol_procedures[17]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for Symbol: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Symbol <~ GenerativeTerminalSymbol\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "Symbol" }, &[_][]const u8{"\"", "'", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_Symbol__expected_GenerativeTerminalSymbol_or_TerminalSymbol_or_VariableSymbol"))
                    @field(error_messages, "syntax_error_ll_Symbol__expected_GenerativeTerminalSymbol_or_TerminalSymbol_or_VariableSymbol")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_Symbol"))
                    @field(error_messages, "syntax_error_ll_Symbol")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "RightHandSideTail" at index 3 of its right hand side
// Right hand side: -> 'space', Symbol, ProcedureTail, RightHandSideTail
fn parse_RightHandSideTail_0_3(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
    var repeating_node: *data_structures.ASTNode = undefined;
    repeating_node = repeating_node; // dummy store for 0-repetition paths
    _ = &repeating_node;

    while (true) {
        switch (context.head(u8, 0)) {
            32 => { // ' '
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: RightHandSideTail -> 'space', Symbol, ProcedureTail, RightHandSideTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 14);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 3
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_generative_terminal_space(context); // child 0
                {
                    const child_node = try parse_Symbol(context);
                    if (child_node != data_structures.ASTNode.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                    }
                }
                {
                    const child_node = try parse_ProcedureTail(context);
                    if (child_node != data_structures.ASTNode.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                    }
                }
            },
            else => break,
        }
    }
    const exit_node = try parse_RightHandSideTail(context);
    if (exit_node != data_structures.ASTNode.invalid_pointer) {
        if (node_address == data_structures.ASTNode.invalid_pointer) {
            node_address = exit_node;
        } else {
            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 3 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: RightHandSideTail <~ 'space', Symbol, ProcedureTail, RightHandSideTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[32],
            .node = repeating_node_address,
        };
        _ = &args;
        args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[32]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[14], &args);
        if (comptime symbol_procedures[18]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        if (comptime reduction_procedure) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 2) {
                std.debug.print("Procedure outcome for RightHandSideTail: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        if (args.node) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.ASTNode.invalid_pointer;
            }
        }
        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "RightHandSideTail" with index 18
fn parse_RightHandSideTail(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 14);

    switch (context.head(u8, 0)) {
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSideTail -> \n", .{});
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[31],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[31]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[14], &args);
            if (comptime symbol_procedures[18]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for RightHandSideTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSideTail <~ \n", .{});
                }
            }
        },
        32 => { // ' '
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSideTail -> 'space', Symbol, ProcedureTail, RightHandSideTail\n", .{});
                }
            }
            try parse_generative_terminal_space(context); // child 0
            {
                const child_node = try parse_Symbol(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = try parse_ProcedureTail(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = try parse_RightHandSideTail_0_3(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 3 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[32],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[32]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[14], &args);
            if (comptime symbol_procedures[18]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for RightHandSideTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSideTail <~ 'space', Symbol, ProcedureTail, RightHandSideTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "RightHandSideTail" }, &[_][]const u8{"\n", " "});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_RightHandSideTail__expected_end_of_RightHandSideTail_or_generative_terminal_space"))
                    @field(error_messages, "syntax_error_ll_RightHandSideTail__expected_end_of_RightHandSideTail_or_generative_terminal_space")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_RightHandSideTail"))
                    @field(error_messages, "syntax_error_ll_RightHandSideTail")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "TerminalSymbol" with index 19
fn parse_TerminalSymbol(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 15);

    switch (context.head(u8, 0)) {
        34 => { // '\"'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: TerminalSymbol -> '\"', SimpleStringContent, '\"'\n", .{});
                }
            }
            try parse_terminal__x34(context); // child 0
            {
                const child_node = try parse_SimpleStringContent(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            try parse_terminal__x34(context); // child 2
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[49],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[49]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[15], &args);
            if (comptime symbol_procedures[19]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for TerminalSymbol: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: TerminalSymbol <~ '\"', SimpleStringContent, '\"'\n", .{});
                }
            }
        },
        39 => { // '''
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: TerminalSymbol -> ''', StringContent, '\\x03'\n", .{});
                }
            }
            try parse_terminal__x39(context); // child 0
            {
                const child_node = try parse_StringContent(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            try parse_terminal__x92x03(context); // child 2
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[48],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[48]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[15], &args);
            if (comptime symbol_procedures[19]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for TerminalSymbol: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: TerminalSymbol <~ ''', StringContent, '\\x03'\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "TerminalSymbol" }, &[_][]const u8{"\"", "'"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_TerminalSymbol__expected_terminal__x34_or_terminal__x39"))
                    @field(error_messages, "syntax_error_ll_TerminalSymbol__expected_terminal__x34_or_terminal__x39")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_TerminalSymbol"))
                    @field(error_messages, "syntax_error_ll_TerminalSymbol")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "GenerativeTerminalSymbol" with index 20
fn parse_GenerativeTerminalSymbol(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 16);

    switch (context.head(u8, 0)) {
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: GenerativeTerminalSymbol -> LowercaseId, GenerativeTerminalExceptions\n", .{});
                }
            }
            {
                const child_node = try parse_LowercaseId(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = try parse_GenerativeTerminalExceptions(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[15],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[15]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[16], &args);
            if (comptime symbol_procedures[20]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for GenerativeTerminalSymbol: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: GenerativeTerminalSymbol <~ LowercaseId, GenerativeTerminalExceptions\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "GenerativeTerminalSymbol" }, &[_][]const u8{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_GenerativeTerminalSymbol__expected_LowercaseId"))
                    @field(error_messages, "syntax_error_ll_GenerativeTerminalSymbol__expected_LowercaseId")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_GenerativeTerminalSymbol"))
                    @field(error_messages, "syntax_error_ll_GenerativeTerminalSymbol")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "UppercaseId" with index 21
fn parse_UppercaseId(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 17);

    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: UppercaseId -> 'uppercase_letter', IdTail\n", .{});
                }
            }
            try parse_generative_terminal_uppercase_letter(context); // child 0
            {
                const child_node = try parse_IdTail(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[50],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[50]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[17], &args);
            if (comptime symbol_procedures[21]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for UppercaseId: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: UppercaseId <~ 'uppercase_letter', IdTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "UppercaseId" }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_UppercaseId__expected_generative_terminal_uppercase_letter"))
                    @field(error_messages, "syntax_error_ll_UppercaseId__expected_generative_terminal_uppercase_letter")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_UppercaseId"))
                    @field(error_messages, "syntax_error_ll_UppercaseId")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "terminal__" with index 22
inline fn parse_terminal__(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        95 => { // '_'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "_" }, &[_][]const u8{"_"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal____expected_terminal__"))
                    @field(error_messages, "syntax_error_ll_terminal____expected_terminal__")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__"))
                    @field(error_messages, "syntax_error_ll_terminal__")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Parser for Symbol "terminal_'" with index 23
inline fn parse_terminal__x39(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        39 => { // '''
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "'" }, &[_][]const u8{"'"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x39__expected_terminal__x39"))
                    @field(error_messages, "syntax_error_ll_terminal__x39__expected_terminal__x39")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x39"))
                    @field(error_messages, "syntax_error_ll_terminal__x39")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Self-Repeating Parser for Symbol "StringContent" at index 1 of its right hand side
// Right hand side: -> 'character', StringContent
fn parse_StringContent_0_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
    var repeating_node: *data_structures.ASTNode = undefined;
    repeating_node = repeating_node; // dummy store for 0-repetition paths
    _ = &repeating_node;

    while (true) {
        switch (context.head(u8, 0)) {
            9, 10, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: StringContent -> 'character', StringContent\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 18);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_generative_terminal_character(context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_StringContent(context);
    if (exit_node != data_structures.ASTNode.invalid_pointer) {
        if (node_address == data_structures.ASTNode.invalid_pointer) {
            node_address = exit_node;
        } else {
            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: StringContent <~ 'character', StringContent\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[44],
            .node = repeating_node_address,
        };
        _ = &args;
        args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[44]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[18], &args);
        if (comptime symbol_procedures[24]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        if (comptime reduction_procedure) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 2) {
                std.debug.print("Procedure outcome for StringContent: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        if (args.node) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.ASTNode.invalid_pointer;
            }
        }
        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "StringContent" with index 24
fn parse_StringContent(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 18);

    switch (context.head(u8, 0)) {
        3 => { // '\x03'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: StringContent -> \n", .{});
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[43],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[43]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[18], &args);
            if (comptime symbol_procedures[24]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for StringContent: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: StringContent <~ \n", .{});
                }
            }
        },
        9, 10, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: StringContent -> 'character', StringContent\n", .{});
                }
            }
            try parse_generative_terminal_character(context); // child 0
            {
                const child_node = try parse_StringContent_0_1(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[44],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[44]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[18], &args);
            if (comptime symbol_procedures[24]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for StringContent: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: StringContent <~ 'character', StringContent\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "StringContent" }, &[_][]const u8{"\x03", "\t", "\n", "\x0b", "\x0c", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_StringContent__expected_end_of_StringContent_or_generative_terminal_character"))
                    @field(error_messages, "syntax_error_ll_StringContent__expected_end_of_StringContent_or_generative_terminal_character")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_StringContent"))
                    @field(error_messages, "syntax_error_ll_StringContent")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_\x03" with index 25
inline fn parse_terminal__x92x03(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        3 => { // '\x03'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "\x03" }, &[_][]const u8{"\x03"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92x03__expected_terminal__x92x03"))
                    @field(error_messages, "syntax_error_ll_terminal__x92x03__expected_terminal__x92x03")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92x03"))
                    @field(error_messages, "syntax_error_ll_terminal__x92x03")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Parser for Symbol "terminal_"" with index 26
inline fn parse_terminal__x34(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        34 => { // '\"'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "\"" }, &[_][]const u8{"\""});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x34__expected_terminal__x34"))
                    @field(error_messages, "syntax_error_ll_terminal__x34__expected_terminal__x34")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x34"))
                    @field(error_messages, "syntax_error_ll_terminal__x34")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Self-Repeating Parser for Symbol "SimpleStringContent" at index 1 of its right hand side
// Right hand side: -> 'character^'\"\\x03', SimpleStringContent
fn parse_SimpleStringContent_0_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
    var repeating_node: *data_structures.ASTNode = undefined;
    repeating_node = repeating_node; // dummy store for 0-repetition paths
    _ = &repeating_node;

    while (true) {
        switch (context.head(u8, 0)) {
            9, 10, 11, 12, 13, 32, 33, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: SimpleStringContent -> 'character^'\"\\x03', SimpleStringContent\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 19);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_generative_terminal_character_x94_x39_x34_x92x03(context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_SimpleStringContent(context);
    if (exit_node != data_structures.ASTNode.invalid_pointer) {
        if (node_address == data_structures.ASTNode.invalid_pointer) {
            node_address = exit_node;
        } else {
            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: SimpleStringContent <~ 'character^'\"\\x03', SimpleStringContent\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[41],
            .node = repeating_node_address,
        };
        _ = &args;
        args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[41]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[19], &args);
        if (comptime symbol_procedures[27]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        if (comptime reduction_procedure) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 2) {
                std.debug.print("Procedure outcome for SimpleStringContent: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        if (args.node) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.ASTNode.invalid_pointer;
            }
        }
        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "SimpleStringContent" with index 27
fn parse_SimpleStringContent(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 19);

    switch (context.head(u8, 0)) {
        9, 10, 11, 12, 13, 32, 33, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: SimpleStringContent -> 'character^'\"\\x03', SimpleStringContent\n", .{});
                }
            }
            try parse_generative_terminal_character_x94_x39_x34_x92x03(context); // child 0
            {
                const child_node = try parse_SimpleStringContent_0_1(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[41],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[41]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[19], &args);
            if (comptime symbol_procedures[27]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for SimpleStringContent: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: SimpleStringContent <~ 'character^'\"\\x03', SimpleStringContent\n", .{});
                }
            }
        },
        34 => { // '\"'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: SimpleStringContent -> \n", .{});
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[40],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[40]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[19], &args);
            if (comptime symbol_procedures[27]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for SimpleStringContent: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: SimpleStringContent <~ \n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "SimpleStringContent" }, &[_][]const u8{"\t", "\n", "\x0b", "\x0c", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_SimpleStringContent__expected_end_of_SimpleStringContent_or_generative_terminal_character_x94_x39_x34_x92x03"))
                    @field(error_messages, "syntax_error_ll_SimpleStringContent__expected_end_of_SimpleStringContent_or_generative_terminal_character_x94_x39_x34_x92x03")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_SimpleStringContent"))
                    @field(error_messages, "syntax_error_ll_SimpleStringContent")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "LowercaseId" with index 28
fn parse_LowercaseId(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 20);

    switch (context.head(u8, 0)) {
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: LowercaseId -> 'lowercase_letter', IdTail\n", .{});
                }
            }
            try parse_generative_terminal_lowercase_letter(context); // child 0
            {
                const child_node = try parse_IdTail(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[20],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[20]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[20], &args);
            if (comptime symbol_procedures[28]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for LowercaseId: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: LowercaseId <~ 'lowercase_letter', IdTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "LowercaseId" }, &[_][]const u8{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_LowercaseId__expected_generative_terminal_lowercase_letter"))
                    @field(error_messages, "syntax_error_ll_LowercaseId__expected_generative_terminal_lowercase_letter")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_LowercaseId"))
                    @field(error_messages, "syntax_error_ll_LowercaseId")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "GenerativeTerminalExceptions" at index 2 of its right hand side
// Right hand side: -> '^', TerminalSymbol, GenerativeTerminalExceptions
fn parse_GenerativeTerminalExceptions_0_2(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
    var repeating_node: *data_structures.ASTNode = undefined;
    repeating_node = repeating_node; // dummy store for 0-repetition paths
    _ = &repeating_node;

    while (true) {
        switch (context.head(u8, 0)) {
            94 => { // '^'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: GenerativeTerminalExceptions -> '^', TerminalSymbol, GenerativeTerminalExceptions\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 21);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 2
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_terminal__x94(context); // child 0
                {
                    const child_node = try parse_TerminalSymbol(context);
                    if (child_node != data_structures.ASTNode.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                    }
                }
            },
            else => break,
        }
    }
    const exit_node = try parse_GenerativeTerminalExceptions(context);
    if (exit_node != data_structures.ASTNode.invalid_pointer) {
        if (node_address == data_structures.ASTNode.invalid_pointer) {
            node_address = exit_node;
        } else {
            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: GenerativeTerminalExceptions <~ '^', TerminalSymbol, GenerativeTerminalExceptions\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[14],
            .node = repeating_node_address,
        };
        _ = &args;
        args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[14]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[21], &args);
        if (comptime symbol_procedures[29]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        if (comptime reduction_procedure) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 2) {
                std.debug.print("Procedure outcome for GenerativeTerminalExceptions: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        if (args.node) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.ASTNode.invalid_pointer;
            }
        }
        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "GenerativeTerminalExceptions" with index 29
fn parse_GenerativeTerminalExceptions(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 21);

    switch (context.head(u8, 0)) {
        10, 32, 64 => { // '\n', ' ', '@'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: GenerativeTerminalExceptions -> \n", .{});
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[13],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[13]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[21], &args);
            if (comptime symbol_procedures[29]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for GenerativeTerminalExceptions: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: GenerativeTerminalExceptions <~ \n", .{});
                }
            }
        },
        94 => { // '^'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: GenerativeTerminalExceptions -> '^', TerminalSymbol, GenerativeTerminalExceptions\n", .{});
                }
            }
            try parse_terminal__x94(context); // child 0
            {
                const child_node = try parse_TerminalSymbol(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = try parse_GenerativeTerminalExceptions_0_2(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[14],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[14]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[21], &args);
            if (comptime symbol_procedures[29]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for GenerativeTerminalExceptions: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: GenerativeTerminalExceptions <~ '^', TerminalSymbol, GenerativeTerminalExceptions\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "GenerativeTerminalExceptions" }, &[_][]const u8{"\n", " ", "@", "^"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_GenerativeTerminalExceptions__expected_end_of_GenerativeTerminalExceptions_or_terminal__x94"))
                    @field(error_messages, "syntax_error_ll_GenerativeTerminalExceptions__expected_end_of_GenerativeTerminalExceptions_or_terminal__x94")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_GenerativeTerminalExceptions"))
                    @field(error_messages, "syntax_error_ll_GenerativeTerminalExceptions")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_^" with index 30
inline fn parse_terminal__x94(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        94 => { // '^'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "^" }, &[_][]const u8{"^"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x94__expected_terminal__x94"))
                    @field(error_messages, "syntax_error_ll_terminal__x94__expected_terminal__x94")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x94"))
                    @field(error_messages, "syntax_error_ll_terminal__x94")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Parser for Symbol "terminal_@" with index 31
inline fn parse_terminal__x64(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        64 => { // '@'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "@" }, &[_][]const u8{"@"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x64__expected_terminal__x64"))
                    @field(error_messages, "syntax_error_ll_terminal__x64__expected_terminal__x64")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x64"))
                    @field(error_messages, "syntax_error_ll_terminal__x64")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Parser for Symbol "CamelCaseId" with index 32
fn parse_CamelCaseId(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 22);

    switch (context.head(u8, 0)) {
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: CamelCaseId -> 'lowercase_letter', CamelCaseIdTail\n", .{});
                }
            }
            try parse_generative_terminal_lowercase_letter(context); // child 0
            {
                const child_node = try parse_CamelCaseIdTail(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[5],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[5]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[22], &args);
            if (comptime symbol_procedures[32]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for CamelCaseId: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: CamelCaseId <~ 'lowercase_letter', CamelCaseIdTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "CamelCaseId" }, &[_][]const u8{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_CamelCaseId__expected_generative_terminal_lowercase_letter"))
                    @field(error_messages, "syntax_error_ll_CamelCaseId__expected_generative_terminal_lowercase_letter")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_CamelCaseId"))
                    @field(error_messages, "syntax_error_ll_CamelCaseId")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "generative_terminal_character" with index 33
inline fn parse_generative_terminal_character(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        9, 10, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "character" }, &[_][]const u8{"\t", "\n", "\x0b", "\x0c", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_character__expected_generative_terminal_character"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_character__expected_generative_terminal_character")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_character"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_character")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Parser for Symbol "generative_terminal_character^'"\x03" with index 34
inline fn parse_generative_terminal_character_x94_x39_x34_x92x03(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        9, 10, 11, 12, 13, 32, 33, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "character^'\"\x03" }, &[_][]const u8{"\t", "\n", "\x0b", "\x0c", "\r", " ", "!", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_character_x94_x39_x34_x92x03__expected_generative_terminal_character_x94_x39_x34_x92x03"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_character_x94_x39_x34_x92x03__expected_generative_terminal_character_x94_x39_x34_x92x03")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_character_x94_x39_x34_x92x03"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_character_x94_x39_x34_x92x03")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Parser for Symbol "ControlCharacter" with index 35
fn parse_ControlCharacter(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 23);

    switch (context.head(u8, 0)) {
        1 => { // '\x01'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: ControlCharacter -> '\\x01'\n", .{});
                }
            }
            try parse_terminal__x92x01(context); // child 0
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[10],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[10]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[23], &args);
            if (comptime symbol_procedures[35]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for ControlCharacter: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: ControlCharacter <~ '\\x01'\n", .{});
                }
            }
        },
        3 => { // '\x03'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: ControlCharacter -> '\\x03'\n", .{});
                }
            }
            try parse_terminal__x92x03(context); // child 0
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[9],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[9]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[23], &args);
            if (comptime symbol_procedures[35]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for ControlCharacter: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: ControlCharacter <~ '\\x03'\n", .{});
                }
            }
        },
        4 => { // '\x04'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: ControlCharacter -> '\\x04'\n", .{});
                }
            }
            try parse_terminal__x92x04(context); // child 0
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[11],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[11]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[23], &args);
            if (comptime symbol_procedures[35]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for ControlCharacter: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: ControlCharacter <~ '\\x04'\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "ControlCharacter" }, &[_][]const u8{"\x01", "\x03", "\x04"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_ControlCharacter__expected_terminal__x92x01_or_terminal__x92x03_or_terminal__x92x04"))
                    @field(error_messages, "syntax_error_ll_ControlCharacter__expected_terminal__x92x01_or_terminal__x92x03_or_terminal__x92x04")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_ControlCharacter"))
                    @field(error_messages, "syntax_error_ll_ControlCharacter")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_\x01" with index 36
inline fn parse_terminal__x92x01(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        1 => { // '\x01'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "\x01" }, &[_][]const u8{"\x01"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92x01__expected_terminal__x92x01"))
                    @field(error_messages, "syntax_error_ll_terminal__x92x01__expected_terminal__x92x01")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92x01"))
                    @field(error_messages, "syntax_error_ll_terminal__x92x01")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Parser for Symbol "terminal_\x04" with index 37
inline fn parse_terminal__x92x04(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        4 => { // '\x04'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "\x04" }, &[_][]const u8{"\x04"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92x04__expected_terminal__x92x04"))
                    @field(error_messages, "syntax_error_ll_terminal__x92x04__expected_terminal__x92x04")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92x04"))
                    @field(error_messages, "syntax_error_ll_terminal__x92x04")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Parser for Symbol "generative_terminal_character^"\n"" with index 38
inline fn parse_generative_terminal_character_x94_x34_x92n_x34(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        9, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "character^\"\n\"" }, &[_][]const u8{"\t", "\x0b", "\x0c", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_character_x94_x34_x92n_x34__expected_generative_terminal_character_x94_x34_x92n_x34"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_character_x94_x34_x92n_x34__expected_generative_terminal_character_x94_x34_x92n_x34")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_character_x94_x34_x92n_x34"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_character_x94_x34_x92n_x34")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Self-Repeating Parser for Symbol "AnyContentTail" at index 1 of its right hand side
// Right hand side: -> ControlCharacter, AnyContentTail
fn parse_AnyContentTail_1_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
    var repeating_node: *data_structures.ASTNode = undefined;
    repeating_node = repeating_node; // dummy store for 0-repetition paths
    _ = &repeating_node;

    while (true) {
        switch (context.head(u8, 0)) {
            1, 3, 4 => { // '\x01', '\x03', '\x04'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: AnyContentTail -> ControlCharacter, AnyContentTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 24);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                {
                    const child_node = try parse_ControlCharacter(context);
                    if (child_node != data_structures.ASTNode.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                    }
                }
            },
            else => break,
        }
    }
    const exit_node = try parse_AnyContentTail(context);
    if (exit_node != data_structures.ASTNode.invalid_pointer) {
        if (node_address == data_structures.ASTNode.invalid_pointer) {
            node_address = exit_node;
        } else {
            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: AnyContentTail <~ ControlCharacter, AnyContentTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[3],
            .node = repeating_node_address,
        };
        _ = &args;
        args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[3]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[24], &args);
        if (comptime symbol_procedures[39]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        if (comptime reduction_procedure) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 2) {
                std.debug.print("Procedure outcome for AnyContentTail: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        if (args.node) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.ASTNode.invalid_pointer;
            }
        }
        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "AnyContentTail" at index 1 of its right hand side
// Right hand side: -> 'character^\"\\n\"', AnyContentTail
fn parse_AnyContentTail_0_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
    var repeating_node: *data_structures.ASTNode = undefined;
    repeating_node = repeating_node; // dummy store for 0-repetition paths
    _ = &repeating_node;

    while (true) {
        switch (context.head(u8, 0)) {
            9, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: AnyContentTail -> 'character^\"\\n\"', AnyContentTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 24);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_generative_terminal_character_x94_x34_x92n_x34(context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_AnyContentTail(context);
    if (exit_node != data_structures.ASTNode.invalid_pointer) {
        if (node_address == data_structures.ASTNode.invalid_pointer) {
            node_address = exit_node;
        } else {
            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: AnyContentTail <~ 'character^\"\\n\"', AnyContentTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[4],
            .node = repeating_node_address,
        };
        _ = &args;
        args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[4]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[24], &args);
        if (comptime symbol_procedures[39]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        if (comptime reduction_procedure) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 2) {
                std.debug.print("Procedure outcome for AnyContentTail: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        if (args.node) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.ASTNode.invalid_pointer;
            }
        }
        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "AnyContentTail" with index 39
fn parse_AnyContentTail(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 24);

    switch (context.head(u8, 0)) {
        1, 3, 4 => { // '\x01', '\x03', '\x04'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: AnyContentTail -> ControlCharacter, AnyContentTail\n", .{});
                }
            }
            {
                const child_node = try parse_ControlCharacter(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = try parse_AnyContentTail_1_1(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[3],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[3]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[24], &args);
            if (comptime symbol_procedures[39]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for AnyContentTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: AnyContentTail <~ ControlCharacter, AnyContentTail\n", .{});
                }
            }
        },
        9, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: AnyContentTail -> 'character^\"\\n\"', AnyContentTail\n", .{});
                }
            }
            try parse_generative_terminal_character_x94_x34_x92n_x34(context); // child 0
            {
                const child_node = try parse_AnyContentTail_0_1(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[4],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[4]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[24], &args);
            if (comptime symbol_procedures[39]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for AnyContentTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: AnyContentTail <~ 'character^\"\\n\"', AnyContentTail\n", .{});
                }
            }
        },
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: AnyContentTail -> \n", .{});
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[2],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[2]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[24], &args);
            if (comptime symbol_procedures[39]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for AnyContentTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: AnyContentTail <~ \n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "AnyContentTail" }, &[_][]const u8{"\x01", "\x03", "\x04", "\t", "\n", "\x0b", "\x0c", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_AnyContentTail__expected_ControlCharacter_or_end_of_AnyContentTail_or_generative_terminal_character_x94_x34_x92n_x34"))
                    @field(error_messages, "syntax_error_ll_AnyContentTail__expected_ControlCharacter_or_end_of_AnyContentTail_or_generative_terminal_character_x94_x34_x92n_x34")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_AnyContentTail"))
                    @field(error_messages, "syntax_error_ll_AnyContentTail")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "IdTail" at index 1 of its right hand side
// Right hand side: -> '_', IdTail
fn parse_IdTail_2_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
    var repeating_node: *data_structures.ASTNode = undefined;
    repeating_node = repeating_node; // dummy store for 0-repetition paths
    _ = &repeating_node;

    while (true) {
        switch (context.head(u8, 0)) {
            95 => { // '_'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: IdTail -> '_', IdTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 25);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_terminal__(context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_IdTail(context);
    if (exit_node != data_structures.ASTNode.invalid_pointer) {
        if (node_address == data_structures.ASTNode.invalid_pointer) {
            node_address = exit_node;
        } else {
            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: IdTail <~ '_', IdTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[17],
            .node = repeating_node_address,
        };
        _ = &args;
        args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[17]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[25], &args);
        if (comptime symbol_procedures[40]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        if (comptime reduction_procedure) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 2) {
                std.debug.print("Procedure outcome for IdTail: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        if (args.node) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.ASTNode.invalid_pointer;
            }
        }
        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "IdTail" at index 1 of its right hand side
// Right hand side: -> 'letter', IdTail
fn parse_IdTail_0_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
    var repeating_node: *data_structures.ASTNode = undefined;
    repeating_node = repeating_node; // dummy store for 0-repetition paths
    _ = &repeating_node;

    while (true) {
        switch (context.head(u8, 0)) {
            65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: IdTail -> 'letter', IdTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 25);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_generative_terminal_letter(context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_IdTail(context);
    if (exit_node != data_structures.ASTNode.invalid_pointer) {
        if (node_address == data_structures.ASTNode.invalid_pointer) {
            node_address = exit_node;
        } else {
            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: IdTail <~ 'letter', IdTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[18],
            .node = repeating_node_address,
        };
        _ = &args;
        args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[18]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[25], &args);
        if (comptime symbol_procedures[40]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        if (comptime reduction_procedure) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 2) {
                std.debug.print("Procedure outcome for IdTail: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        if (args.node) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.ASTNode.invalid_pointer;
            }
        }
        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "IdTail" at index 1 of its right hand side
// Right hand side: -> 'digit', IdTail
fn parse_IdTail_1_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
    var repeating_node: *data_structures.ASTNode = undefined;
    repeating_node = repeating_node; // dummy store for 0-repetition paths
    _ = &repeating_node;

    while (true) {
        switch (context.head(u8, 0)) {
            48, 49, 50, 51, 52, 53, 54, 55, 56, 57 => { // '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: IdTail -> 'digit', IdTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 25);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_generative_terminal_digit(context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_IdTail(context);
    if (exit_node != data_structures.ASTNode.invalid_pointer) {
        if (node_address == data_structures.ASTNode.invalid_pointer) {
            node_address = exit_node;
        } else {
            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: IdTail <~ 'digit', IdTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[19],
            .node = repeating_node_address,
        };
        _ = &args;
        args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[19]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[25], &args);
        if (comptime symbol_procedures[40]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        if (comptime reduction_procedure) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 2) {
                std.debug.print("Procedure outcome for IdTail: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        if (args.node) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.ASTNode.invalid_pointer;
            }
        }
        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "IdTail" with index 40
fn parse_IdTail(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 25);

    switch (context.head(u8, 0)) {
        10, 32, 64, 94 => { // '\n', ' ', '@', '^'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: IdTail -> \n", .{});
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[16],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[16]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[25], &args);
            if (comptime symbol_procedures[40]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for IdTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: IdTail <~ \n", .{});
                }
            }
        },
        48, 49, 50, 51, 52, 53, 54, 55, 56, 57 => { // '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: IdTail -> 'digit', IdTail\n", .{});
                }
            }
            try parse_generative_terminal_digit(context); // child 0
            {
                const child_node = try parse_IdTail_1_1(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[19],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[19]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[25], &args);
            if (comptime symbol_procedures[40]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for IdTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: IdTail <~ 'digit', IdTail\n", .{});
                }
            }
        },
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: IdTail -> 'letter', IdTail\n", .{});
                }
            }
            try parse_generative_terminal_letter(context); // child 0
            {
                const child_node = try parse_IdTail_0_1(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[18],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[18]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[25], &args);
            if (comptime symbol_procedures[40]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for IdTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: IdTail <~ 'letter', IdTail\n", .{});
                }
            }
        },
        95 => { // '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: IdTail -> '_', IdTail\n", .{});
                }
            }
            try parse_terminal__(context); // child 0
            {
                const child_node = try parse_IdTail_2_1(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[17],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[17]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[25], &args);
            if (comptime symbol_procedures[40]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for IdTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: IdTail <~ '_', IdTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "IdTail" }, &[_][]const u8{"\n", " ", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "^", "_", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_IdTail__expected_end_of_IdTail_or_generative_terminal_digit_or_generative_terminal_letter_or_terminal__"))
                    @field(error_messages, "syntax_error_ll_IdTail__expected_end_of_IdTail_or_generative_terminal_digit_or_generative_terminal_letter_or_terminal__")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_IdTail"))
                    @field(error_messages, "syntax_error_ll_IdTail")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "generative_terminal_letter" with index 41
inline fn parse_generative_terminal_letter(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "letter" }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_letter__expected_generative_terminal_letter"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_letter__expected_generative_terminal_letter")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_letter"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_letter")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Parser for Symbol "generative_terminal_digit" with index 42
inline fn parse_generative_terminal_digit(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        48, 49, 50, 51, 52, 53, 54, 55, 56, 57 => { // '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "digit" }, &[_][]const u8{"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_digit__expected_generative_terminal_digit"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_digit__expected_generative_terminal_digit")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_digit"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_digit")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Parser for Symbol "generative_terminal_lowercase_letter" with index 43
inline fn parse_generative_terminal_lowercase_letter(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "lowercase_letter" }, &[_][]const u8{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_lowercase_letter__expected_generative_terminal_lowercase_letter"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_lowercase_letter__expected_generative_terminal_lowercase_letter")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_lowercase_letter"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_lowercase_letter")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Parser for Symbol "generative_terminal_uppercase_letter" with index 44
inline fn parse_generative_terminal_uppercase_letter(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "uppercase_letter" }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_uppercase_letter__expected_generative_terminal_uppercase_letter"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_uppercase_letter__expected_generative_terminal_uppercase_letter")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_uppercase_letter"))
                    @field(error_messages, "syntax_error_ll_generative_terminal_uppercase_letter")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Self-Repeating Parser for Symbol "CamelCaseIdTail" at index 1 of its right hand side
// Right hand side: -> 'letter', CamelCaseIdTail
fn parse_CamelCaseIdTail_0_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
    var repeating_node: *data_structures.ASTNode = undefined;
    repeating_node = repeating_node; // dummy store for 0-repetition paths
    _ = &repeating_node;

    while (true) {
        switch (context.head(u8, 0)) {
            65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: CamelCaseIdTail -> 'letter', CamelCaseIdTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 26);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_generative_terminal_letter(context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_CamelCaseIdTail(context);
    if (exit_node != data_structures.ASTNode.invalid_pointer) {
        if (node_address == data_structures.ASTNode.invalid_pointer) {
            node_address = exit_node;
        } else {
            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: CamelCaseIdTail <~ 'letter', CamelCaseIdTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[7],
            .node = repeating_node_address,
        };
        _ = &args;
        args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[7]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[26], &args);
        if (comptime symbol_procedures[45]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        if (comptime reduction_procedure) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 2) {
                std.debug.print("Procedure outcome for CamelCaseIdTail: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        if (args.node) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.ASTNode.invalid_pointer;
            }
        }
        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "CamelCaseIdTail" at index 1 of its right hand side
// Right hand side: -> 'digit', CamelCaseIdTail
fn parse_CamelCaseIdTail_1_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths
    var repeating_node: *data_structures.ASTNode = undefined;
    repeating_node = repeating_node; // dummy store for 0-repetition paths
    _ = &repeating_node;

    while (true) {
        switch (context.head(u8, 0)) {
            48, 49, 50, 51, 52, 53, 54, 55, 56, 57 => { // '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: CamelCaseIdTail -> 'digit', CamelCaseIdTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 26);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_generative_terminal_digit(context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_CamelCaseIdTail(context);
    if (exit_node != data_structures.ASTNode.invalid_pointer) {
        if (node_address == data_structures.ASTNode.invalid_pointer) {
            node_address = exit_node;
        } else {
            repeating_node.immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: CamelCaseIdTail <~ 'digit', CamelCaseIdTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[8],
            .node = repeating_node_address,
        };
        _ = &args;
        args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[8]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[26], &args);
        if (comptime symbol_procedures[45]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        if (comptime reduction_procedure) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 2) {
                std.debug.print("Procedure outcome for CamelCaseIdTail: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        if (args.node) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.ASTNode.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.ASTNode.invalid_pointer;
            }
        }
        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "CamelCaseIdTail" with index 45
fn parse_CamelCaseIdTail(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = context.node_allocator.create(context.pos(), 26);

    switch (context.head(u8, 0)) {
        10, 32, 64 => { // '\n', ' ', '@'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: CamelCaseIdTail -> \n", .{});
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[6],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[6]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[26], &args);
            if (comptime symbol_procedures[45]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for CamelCaseIdTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: CamelCaseIdTail <~ \n", .{});
                }
            }
        },
        48, 49, 50, 51, 52, 53, 54, 55, 56, 57 => { // '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: CamelCaseIdTail -> 'digit', CamelCaseIdTail\n", .{});
                }
            }
            try parse_generative_terminal_digit(context); // child 0
            {
                const child_node = try parse_CamelCaseIdTail_1_1(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[8],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[8]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[26], &args);
            if (comptime symbol_procedures[45]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for CamelCaseIdTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: CamelCaseIdTail <~ 'digit', CamelCaseIdTail\n", .{});
                }
            }
        },
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: CamelCaseIdTail -> 'letter', CamelCaseIdTail\n", .{});
                }
            }
            try parse_generative_terminal_letter(context); // child 0
            {
                const child_node = try parse_CamelCaseIdTail_0_1(context);
                if (child_node != data_structures.ASTNode.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[7],
                .node = node_address,
            };
            _ = &args;
            args = args; // dummy store so Zig sees mutation (only fields mutated via pointer)
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[7]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[26], &args);
            if (comptime symbol_procedures[45]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for CamelCaseIdTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }
            node_address = args.node orelse data_structures.ASTNode.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: CamelCaseIdTail <~ 'letter', CamelCaseIdTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "CamelCaseIdTail" }, &[_][]const u8{"\n", " ", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_CamelCaseIdTail__expected_end_of_CamelCaseIdTail_or_generative_terminal_digit_or_generative_terminal_letter"))
                    @field(error_messages, "syntax_error_ll_CamelCaseIdTail__expected_end_of_CamelCaseIdTail_or_generative_terminal_digit_or_generative_terminal_letter")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_CamelCaseIdTail"))
                    @field(error_messages, "syntax_error_ll_CamelCaseIdTail")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "_AugmentedStart" with index 46
fn parse__AugmentedStart(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _AugmentedStart -> Start, '\\x00'\n", .{});
                }
            }
            _ = try parse_Start(context); // child 0
            try parse_special_EOF(context); // child 1
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _AugmentedStart <~ Start, '\\x00'\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "_AugmentedStart" }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll__AugmentedStart__expected_Start"))
                    @field(error_messages, "syntax_error_ll__AugmentedStart__expected_Start")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll__AugmentedStart"))
                    @field(error_messages, "syntax_error_ll__AugmentedStart")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

// Parser for Symbol "special_EOF" with index 47
inline fn parse_special_EOF(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        0 => { // '\x00'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            try context.recordSyntaxDiagnostic(.{ .while_parsing = "\x00" }, &[_][]const u8{"\x00"});
            if (!builtin.is_test) {
                const diagnostic = context.runtime().last_diagnostic.?;
                const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_special_EOF__expected_special_EOF"))
                    @field(error_messages, "syntax_error_ll_special_EOF__expected_special_EOF")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll_special_EOF"))
                    @field(error_messages, "syntax_error_ll_special_EOF")(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error_ll"))
                    error_messages.syntax_error_ll(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else if (comptime @hasDecl(error_messages, "syntax_error"))
                    error_messages.syntax_error(.{
                        .allocator = context.runtime().arena_allocator,
                        .context = context,
                        .diagnostic = diagnostic,
                        .style = .ansi,
                    }) catch ""
                else
                    root.renderParseDiagnostic(context.runtime().arena_allocator, diagnostic, .ansi) catch "";
                std.debug.print("{s}", .{diagnostic_message});
            }
            return root.ParseError.SyntaxError;
        },
    }
}

pub fn parseWithResult(context: *data_structures.Context) !root.ParseResult {
    _ = parse__AugmentedStart(context) catch |err| switch (err) {
        root.ParseError.SyntaxError => return root.ParseError.SyntaxError,
        else => return err,
    };
    if (context.verbosityLevel() > 0) {
        std.log.info("The input file was parsed successfully!", .{});
    }
    const ast_root: ?data_structures.ASTNode.Pointer = if (context.node_allocator.counter > 0) 0 else null;
    return .{
        .parsed_bytes = context.pos() - 1,
        .line = context.line,
        .column = context.column,
        .ast_root = ast_root,
    };
}

pub fn parse(context: *data_structures.Context) !void {
    _ = try parseWithResult(context);
}
