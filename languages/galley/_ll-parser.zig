const builtin = @import("builtin");
const std = @import("std");
const root = @import("galley");
const procedures = root.procedures;
const data_structures = root.data_structures;
const string_utilities = root.string_utilities;

pub const is_ast_enabled = true;
pub const are_procedures_enabled = true;
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
    "character", // 32
    "character^'\"\x03", // 33
    "ControlCharacter", // 34
    "\x01", // 35
    "\x04", // 36
    "character^\"\n\"", // 37
    "AnyContentTail", // 38
    "IdTail", // 39
    "letter", // 40
    "digit", // 41
    "lowercase_letter", // 42
    "uppercase_letter", // 43
    "_AugmentedStart", // 44
    "\x00", // 45
    "GenerativeTerminal", // 46
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
    "ControlCharacter",
    "AnyContentTail",
    "IdTail",
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
    34,
    38,
    39,
    44,
    46,
};

pub const rules = &[_]data_structures.Rule{
    data_structures.Rule{ .header = 6, .right_hand_side = &[_]u16{ 34, 38 }, .right_hand_side_index = "1" }, // AnyContent
    data_structures.Rule{ .header = 6, .right_hand_side = &[_]u16{ 37, 38 }, .right_hand_side_index = "0" }, // AnyContent
    data_structures.Rule{ .header = 23, .right_hand_side = &[_]u16{}, .right_hand_side_index = "2" }, // AnyContentTail
    data_structures.Rule{ .header = 23, .right_hand_side = &[_]u16{ 34, 38 }, .right_hand_side_index = "1" }, // AnyContentTail
    data_structures.Rule{ .header = 23, .right_hand_side = &[_]u16{ 37, 38 }, .right_hand_side_index = "0" }, // AnyContentTail
    data_structures.Rule{ .header = 22, .right_hand_side = &[_]u16{25}, .right_hand_side_index = "1" }, // ControlCharacter
    data_structures.Rule{ .header = 22, .right_hand_side = &[_]u16{35}, .right_hand_side_index = "0" }, // ControlCharacter
    data_structures.Rule{ .header = 22, .right_hand_side = &[_]u16{36}, .right_hand_side_index = "2" }, // ControlCharacter
    data_structures.Rule{ .header = 26, .right_hand_side = &[_]u16{}, .right_hand_side_index = "0" }, // GenerativeTerminal
    data_structures.Rule{ .header = 21, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // GenerativeTerminalExceptions
    data_structures.Rule{ .header = 21, .right_hand_side = &[_]u16{ 30, 19, 29 }, .right_hand_side_index = "0" }, // GenerativeTerminalExceptions
    data_structures.Rule{ .header = 16, .right_hand_side = &[_]u16{ 28, 29 }, .right_hand_side_index = "0" }, // GenerativeTerminalSymbol
    data_structures.Rule{ .header = 24, .right_hand_side = &[_]u16{}, .right_hand_side_index = "3" }, // IdTail
    data_structures.Rule{ .header = 24, .right_hand_side = &[_]u16{ 22, 39 }, .right_hand_side_index = "2" }, // IdTail
    data_structures.Rule{ .header = 24, .right_hand_side = &[_]u16{ 40, 39 }, .right_hand_side_index = "0" }, // IdTail
    data_structures.Rule{ .header = 24, .right_hand_side = &[_]u16{ 41, 39 }, .right_hand_side_index = "1" }, // IdTail
    data_structures.Rule{ .header = 20, .right_hand_side = &[_]u16{ 42, 39 }, .right_hand_side_index = "0" }, // LowercaseId
    data_structures.Rule{ .header = 4, .right_hand_side = &[_]u16{ 5, 6 }, .right_hand_side_index = "0" }, // NewLines
    data_structures.Rule{ .header = 5, .right_hand_side = &[_]u16{}, .right_hand_side_index = "2" }, // NewLinesTail
    data_structures.Rule{ .header = 5, .right_hand_side = &[_]u16{ 5, 6 }, .right_hand_side_index = "0" }, // NewLinesTail
    data_structures.Rule{ .header = 5, .right_hand_side = &[_]u16{ 7, 8, 5, 6 }, .right_hand_side_index = "1" }, // NewLinesTail
    data_structures.Rule{ .header = 8, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // ProcedureTail
    data_structures.Rule{ .header = 8, .right_hand_side = &[_]u16{ 31, 28, 10 }, .right_hand_side_index = "0" }, // ProcedureTail
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
    data_structures.Rule{ .header = 19, .right_hand_side = &[_]u16{ 33, 27 }, .right_hand_side_index = "0" }, // SimpleStringContent
    data_structures.Rule{ .header = 0, .right_hand_side = &[_]u16{1}, .right_hand_side_index = "0" }, // Start
    data_structures.Rule{ .header = 18, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // StringContent
    data_structures.Rule{ .header = 18, .right_hand_side = &[_]u16{ 32, 24 }, .right_hand_side_index = "0" }, // StringContent
    data_structures.Rule{ .header = 13, .right_hand_side = &[_]u16{9}, .right_hand_side_index = "0" }, // Symbol
    data_structures.Rule{ .header = 13, .right_hand_side = &[_]u16{19}, .right_hand_side_index = "1" }, // Symbol
    data_structures.Rule{ .header = 13, .right_hand_side = &[_]u16{20}, .right_hand_side_index = "2" }, // Symbol
    data_structures.Rule{ .header = 15, .right_hand_side = &[_]u16{ 23, 24, 25 }, .right_hand_side_index = "0" }, // TerminalSymbol
    data_structures.Rule{ .header = 15, .right_hand_side = &[_]u16{ 26, 27, 26 }, .right_hand_side_index = "1" }, // TerminalSymbol
    data_structures.Rule{ .header = 17, .right_hand_side = &[_]u16{ 43, 39 }, .right_hand_side_index = "0" }, // UppercaseId
    data_structures.Rule{ .header = 7, .right_hand_side = &[_]u16{21}, .right_hand_side_index = "0" }, // VariableSymbol
    data_structures.Rule{ .header = 7, .right_hand_side = &[_]u16{ 22, 21 }, .right_hand_side_index = "1" }, // VariableSymbol
    data_structures.Rule{ .header = 25, .right_hand_side = &[_]u16{ 0, 45 }, .right_hand_side_index = "0" }, // _AugmentedStart
};

pub const rule_procedures = rule_procedures: {
    var arr: [50]?*const data_structures.Procedure = .{null} ** 50;

    for (rules, 0..) |rule, index| {
        const procedure_name = "reduction_" ++ variables[rule.header] ++ "_" ++ rule.right_hand_side_index;
        if (@hasDecl(procedures, procedure_name)) {
            arr[index] = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), procedure_name);
        }
    }

    break :rule_procedures arr;
};

pub const symbol_procedures = symbol_procedures: {
    var arr: [47]?*const data_structures.Procedure = .{null} ** 47;

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
};

const ProcedureSequenceNode = struct {
    procedure: *const data_structures.Procedure,
    next: ?*const ProcedureSequenceNode,
};

pub const variable_procedures = variable_procedures: {
    var arr: [27]?*const ProcedureSequenceNode = .{null} ** 27;

    for (variable_procedure_names, 0..) |procedure_names, index| {
        var last: ?*const ProcedureSequenceNode = null;
        for (procedure_names) |procedure_name| {
            last = &ProcedureSequenceNode{
                .procedure = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), procedure_name),
                .next = last,
            };
            arr[index] = last;
        }
    }

    break :variable_procedures arr;
};

pub const reduction_procedure: ?*const data_structures.Procedure = if (@hasDecl(procedures, "reduction")) data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, "reduction"), "reduction") else null;

// Parser for Symbol "Start" with index 0
fn parse_Start(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 0);

    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Start -> Rules\n", .{});
                }
            }
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_Rules(context), context); // child 0
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[38],
                .node = node_address,
            };

            if (comptime rule_procedures[38]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[0];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Start <~ Rules\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mStart\x1b[0m.\nExpected tokens: \x1b[32m\'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "Rules" with index 1
fn parse_Rules(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 1);

    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Rules -> Rule, RulesTail\n", .{});
                }
            }
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_Rule(context), context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_RulesTail(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[33],
                .node = node_address,
            };

            if (comptime rule_procedures[33]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[1];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Rules <~ Rule, RulesTail\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mRules\x1b[0m.\nExpected tokens: \x1b[32m\'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "Rule" with index 2
fn parse_Rule(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 2);

    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Rule -> VariableSymbol, ProcedureTail, 'new_line', RightHandSides\n", .{});
                }
            }
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_VariableSymbol(context), context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_ProcedureTail(context), context); // child 1
            try parse_generative_terminal_new_line(context); // child 2
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_RightHandSides(context), context); // child 3
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[32],
                .node = node_address,
            };

            if (comptime rule_procedures[32]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[2];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Rule <~ VariableSymbol, ProcedureTail, 'new_line', RightHandSides\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mRule\x1b[0m.\nExpected tokens: \x1b[32m\'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "RulesTail" at index 2 of its right hand side
// Right hand side: -> NewLines, Rule, RulesTail
fn parse_RulesTail_0_2(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    var repeating_node_address = node_address;
    var repeating_node: *data_structures.ASTNode = undefined;

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
                    repeating_node.immediate_insert_child(repeating_node_address, temporary_address, context); // child 2
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                repeating_node.immediate_insert_child(repeating_node_address, try parse_NewLines(context), context); // child 0
                repeating_node.immediate_insert_child(repeating_node_address, try parse_Rule(context), context); // child 1
            },
            else => break,
        }
    }
    const exit_node = try parse_RulesTail(context);
    if (node_address == data_structures.ASTNode.invalid_pointer) {
        node_address = exit_node;
    } else {
        repeating_node.immediate_insert_child(repeating_node_address, exit_node, context); // child 2
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
            .rule = rules[35],
            .node = repeating_node_address,
        };

        if (comptime rule_procedures[35]) |procedure_pointer| {
            const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        comptime var procedure_pointer_head = variable_procedures[3];
        inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            try procedure(&args);
            procedure_pointer_head = procedure_pointer_head_.next;
        }

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

        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "RulesTail" with index 3
fn parse_RulesTail(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 3);

    switch (context.head(u8, 0)) {
        0 => { // '\x00'
        },
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RulesTail -> NewLines, Rule, RulesTail\n", .{});
                }
            }
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_NewLines(context), context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_Rule(context), context); // child 1
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_RulesTail_0_2(context), context); // child 2
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[35],
                .node = node_address,
            };

            if (comptime rule_procedures[35]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[3];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RulesTail <~ NewLines, Rule, RulesTail\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mRulesTail\x1b[0m.\nExpected tokens: \x1b[32m\'\\x00', '\\n\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "NewLines" with index 4
fn parse_NewLines(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 4);

    switch (context.head(u8, 0)) {
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: NewLines -> 'new_line', NewLinesTail\n", .{});
                }
            }
            try parse_generative_terminal_new_line(context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_NewLinesTail(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[17],
                .node = node_address,
            };

            if (comptime rule_procedures[17]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[4];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: NewLines <~ 'new_line', NewLinesTail\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mNewLines\x1b[0m.\nExpected tokens: \x1b[32m\'\\n\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "generative_terminal_new_line" with index 5
inline fn parse_generative_terminal_new_line(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        10 => { // '\n'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mnew_line\x1b[0m.\nExpected tokens: \x1b[32m\'\\n\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Self-Repeating Parser for Symbol "NewLinesTail" at index 1 of its right hand side
// Right hand side: -> 'new_line', NewLinesTail
fn parse_NewLinesTail_0_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    var repeating_node_address = node_address;
    var repeating_node: *data_structures.ASTNode = undefined;

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
                    repeating_node.immediate_insert_child(repeating_node_address, temporary_address, context); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_generative_terminal_new_line(context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_NewLinesTail(context);
    if (node_address == data_structures.ASTNode.invalid_pointer) {
        node_address = exit_node;
    } else {
        repeating_node.immediate_insert_child(repeating_node_address, exit_node, context); // child 1
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
            .rule = rules[19],
            .node = repeating_node_address,
        };

        if (comptime rule_procedures[19]) |procedure_pointer| {
            const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        comptime var procedure_pointer_head = variable_procedures[5];
        inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            try procedure(&args);
            procedure_pointer_head = procedure_pointer_head_.next;
        }

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

        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "NewLinesTail" at index 3 of its right hand side
// Right hand side: -> '#', AnyContent, 'new_line', NewLinesTail
fn parse_NewLinesTail_1_3(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    var repeating_node_address = node_address;
    var repeating_node: *data_structures.ASTNode = undefined;

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
                    repeating_node.immediate_insert_child(repeating_node_address, temporary_address, context); // child 3
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_terminal__x35(context); // child 0
                repeating_node.immediate_insert_child(repeating_node_address, try parse_AnyContent(context), context); // child 1
                try parse_generative_terminal_new_line(context); // child 2
            },
            else => break,
        }
    }
    const exit_node = try parse_NewLinesTail(context);
    if (node_address == data_structures.ASTNode.invalid_pointer) {
        node_address = exit_node;
    } else {
        repeating_node.immediate_insert_child(repeating_node_address, exit_node, context); // child 3
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
            .rule = rules[20],
            .node = repeating_node_address,
        };

        if (comptime rule_procedures[20]) |procedure_pointer| {
            const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        comptime var procedure_pointer_head = variable_procedures[5];
        inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            try procedure(&args);
            procedure_pointer_head = procedure_pointer_head_.next;
        }

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

        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "NewLinesTail" with index 6
fn parse_NewLinesTail(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 5);

    switch (context.head(u8, 0)) {
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: NewLinesTail -> 'new_line', NewLinesTail\n", .{});
                }
            }
            try parse_generative_terminal_new_line(context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_NewLinesTail_0_1(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[19],
                .node = node_address,
            };

            if (comptime rule_procedures[19]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[5];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_AnyContent(context), context); // child 1
            try parse_generative_terminal_new_line(context); // child 2
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_NewLinesTail_1_3(context), context); // child 3
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[20],
                .node = node_address,
            };

            if (comptime rule_procedures[20]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[5];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: NewLinesTail <~ '#', AnyContent, 'new_line', NewLinesTail\n", .{});
                }
            }
        },
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mNewLinesTail\x1b[0m.\nExpected tokens: \x1b[32m\'\\n', '#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_#" with index 7
inline fn parse_terminal__x35(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        35 => { // '#'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34m#\x1b[0m.\nExpected tokens: \x1b[32m\'#\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Parser for Symbol "AnyContent" with index 8
fn parse_AnyContent(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 6);

    switch (context.head(u8, 0)) {
        1, 3, 4 => { // '\x01', '\x03', '\x04'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: AnyContent -> ControlCharacter, AnyContentTail\n", .{});
                }
            }
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_ControlCharacter(context), context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_AnyContentTail(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[0],
                .node = node_address,
            };

            if (comptime rule_procedures[0]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[6];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_AnyContentTail(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[1],
                .node = node_address,
            };

            if (comptime rule_procedures[1]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[6];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: AnyContent <~ 'character^\"\\n\"', AnyContentTail\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mAnyContent\x1b[0m.\nExpected tokens: \x1b[32m\'\\x01', '\\x03', '\\x04', '\\t', '\\x0b', '\\x0c', '\\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{{', '|', '}}', '~\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "VariableSymbol" with index 9
fn parse_VariableSymbol(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 7);

    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: VariableSymbol -> UppercaseId\n", .{});
                }
            }
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_UppercaseId(context), context); // child 0
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[47],
                .node = node_address,
            };

            if (comptime rule_procedures[47]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[7];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_UppercaseId(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[48],
                .node = node_address,
            };

            if (comptime rule_procedures[48]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[7];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: VariableSymbol <~ '_', UppercaseId\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mVariableSymbol\x1b[0m.\nExpected tokens: \x1b[32m\'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "ProcedureTail" at index 2 of its right hand side
// Right hand side: -> '@', LowercaseId, ProcedureTail
fn parse_ProcedureTail_0_2(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    var repeating_node_address = node_address;
    var repeating_node: *data_structures.ASTNode = undefined;

    while (true) {
        switch (context.head(u8, 0)) {
            64 => { // '@'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: ProcedureTail -> '@', LowercaseId, ProcedureTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 8);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediate_insert_child(repeating_node_address, temporary_address, context); // child 2
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_terminal__x64(context); // child 0
                repeating_node.immediate_insert_child(repeating_node_address, try parse_LowercaseId(context), context); // child 1
            },
            else => break,
        }
    }
    const exit_node = try parse_ProcedureTail(context);
    if (node_address == data_structures.ASTNode.invalid_pointer) {
        node_address = exit_node;
    } else {
        repeating_node.immediate_insert_child(repeating_node_address, exit_node, context); // child 2
    }
    while (repeating_node_address != data_structures.ASTNode.invalid_pointer) {
        repeating_node = context.node_allocator.at(repeating_node_address);

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: ProcedureTail <~ '@', LowercaseId, ProcedureTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[22],
            .node = repeating_node_address,
        };

        if (comptime rule_procedures[22]) |procedure_pointer| {
            const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        comptime var procedure_pointer_head = variable_procedures[8];
        inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            try procedure(&args);
            procedure_pointer_head = procedure_pointer_head_.next;
        }

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

        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "ProcedureTail" with index 10
fn parse_ProcedureTail(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 8);

    switch (context.head(u8, 0)) {
        10, 32 => { // '\n', ' '
        },
        64 => { // '@'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: ProcedureTail -> '@', LowercaseId, ProcedureTail\n", .{});
                }
            }
            try parse_terminal__x64(context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_LowercaseId(context), context); // child 1
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_ProcedureTail_0_2(context), context); // child 2
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[22],
                .node = node_address,
            };

            if (comptime rule_procedures[22]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[8];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: ProcedureTail <~ '@', LowercaseId, ProcedureTail\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mProcedureTail\x1b[0m.\nExpected tokens: \x1b[32m\'\\n', ' ', '@\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "RightHandSides" with index 11
fn parse_RightHandSides(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 9);

    switch (context.head(u8, 0)) {
        35, 124 => { // '#', '|'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSides -> RightHandSideLine, RightHandSidesTail\n", .{});
                }
            }
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_RightHandSideLine(context), context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_RightHandSidesTail(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[29],
                .node = node_address,
            };

            if (comptime rule_procedures[29]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[9];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSides <~ RightHandSideLine, RightHandSidesTail\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mRightHandSides\x1b[0m.\nExpected tokens: \x1b[32m\'#', '|\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "RightHandSideLine" with index 12
fn parse_RightHandSideLine(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 10);

    switch (context.head(u8, 0)) {
        35 => { // '#'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSideLine -> '#', AnyContent, 'new_line'\n", .{});
                }
            }
            try parse_terminal__x35(context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_AnyContent(context), context); // child 1
            try parse_generative_terminal_new_line(context); // child 2
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[25],
                .node = node_address,
            };

            if (comptime rule_procedures[25]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[10];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_ProcedureTail(context), context); // child 1
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_RightHandSide(context), context); // child 2
            try parse_generative_terminal_new_line(context); // child 3
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[26],
                .node = node_address,
            };

            if (comptime rule_procedures[26]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[10];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSideLine <~ '|', ProcedureTail, RightHandSide, 'new_line'\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mRightHandSideLine\x1b[0m.\nExpected tokens: \x1b[32m\'#', '|\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "RightHandSidesTail" at index 1 of its right hand side
// Right hand side: -> RightHandSideLine, RightHandSidesTail
fn parse_RightHandSidesTail_0_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    var repeating_node_address = node_address;
    var repeating_node: *data_structures.ASTNode = undefined;

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
                    repeating_node.immediate_insert_child(repeating_node_address, temporary_address, context); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                repeating_node.immediate_insert_child(repeating_node_address, try parse_RightHandSideLine(context), context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_RightHandSidesTail(context);
    if (node_address == data_structures.ASTNode.invalid_pointer) {
        node_address = exit_node;
    } else {
        repeating_node.immediate_insert_child(repeating_node_address, exit_node, context); // child 1
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
            .rule = rules[31],
            .node = repeating_node_address,
        };

        if (comptime rule_procedures[31]) |procedure_pointer| {
            const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        comptime var procedure_pointer_head = variable_procedures[11];
        inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            try procedure(&args);
            procedure_pointer_head = procedure_pointer_head_.next;
        }

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

        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "RightHandSidesTail" with index 13
fn parse_RightHandSidesTail(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 11);

    switch (context.head(u8, 0)) {
        0, 10 => { // '\x00', '\n'
        },
        35, 124 => { // '#', '|'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSidesTail -> RightHandSideLine, RightHandSidesTail\n", .{});
                }
            }
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_RightHandSideLine(context), context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_RightHandSidesTail_0_1(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[31],
                .node = node_address,
            };

            if (comptime rule_procedures[31]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[11];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSidesTail <~ RightHandSideLine, RightHandSidesTail\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mRightHandSidesTail\x1b[0m.\nExpected tokens: \x1b[32m\'\\x00', '\\n', '#', '|\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_|" with index 14
inline fn parse_terminal__x124(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        124 => { // '|'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34m|\x1b[0m.\nExpected tokens: \x1b[32m\'|\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Parser for Symbol "RightHandSide" with index 15
fn parse_RightHandSide(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 12);

    switch (context.head(u8, 0)) {
        10 => { // '\n'
        },
        32 => { // ' '
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSide -> 'space', Symbol, ProcedureTail, RightHandSideTail\n", .{});
                }
            }
            try parse_generative_terminal_space(context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_Symbol(context), context); // child 1
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_ProcedureTail(context), context); // child 2
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_RightHandSideTail(context), context); // child 3
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[24],
                .node = node_address,
            };

            if (comptime rule_procedures[24]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[12];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSide <~ 'space', Symbol, ProcedureTail, RightHandSideTail\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mRightHandSide\x1b[0m.\nExpected tokens: \x1b[32m\'\\n', ' \'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "generative_terminal_space" with index 16
inline fn parse_generative_terminal_space(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        32 => { // ' '
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mspace\x1b[0m.\nExpected tokens: \x1b[32m\' \'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Parser for Symbol "Symbol" with index 17
fn parse_Symbol(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 13);

    switch (context.head(u8, 0)) {
        34, 39 => { // '\"', '''
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Symbol -> TerminalSymbol\n", .{});
                }
            }
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_TerminalSymbol(context), context); // child 0
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[42],
                .node = node_address,
            };

            if (comptime rule_procedures[42]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[13];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_VariableSymbol(context), context); // child 0
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[41],
                .node = node_address,
            };

            if (comptime rule_procedures[41]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[13];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_GenerativeTerminalSymbol(context), context); // child 0
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[43],
                .node = node_address,
            };

            if (comptime rule_procedures[43]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[13];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Symbol <~ GenerativeTerminalSymbol\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mSymbol\x1b[0m.\nExpected tokens: \x1b[32m\'\"', ''', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "RightHandSideTail" at index 3 of its right hand side
// Right hand side: -> 'space', Symbol, ProcedureTail, RightHandSideTail
fn parse_RightHandSideTail_0_3(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    var repeating_node_address = node_address;
    var repeating_node: *data_structures.ASTNode = undefined;

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
                    repeating_node.immediate_insert_child(repeating_node_address, temporary_address, context); // child 3
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_generative_terminal_space(context); // child 0
                repeating_node.immediate_insert_child(repeating_node_address, try parse_Symbol(context), context); // child 1
                repeating_node.immediate_insert_child(repeating_node_address, try parse_ProcedureTail(context), context); // child 2
            },
            else => break,
        }
    }
    const exit_node = try parse_RightHandSideTail(context);
    if (node_address == data_structures.ASTNode.invalid_pointer) {
        node_address = exit_node;
    } else {
        repeating_node.immediate_insert_child(repeating_node_address, exit_node, context); // child 3
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
            .rule = rules[28],
            .node = repeating_node_address,
        };

        if (comptime rule_procedures[28]) |procedure_pointer| {
            const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        comptime var procedure_pointer_head = variable_procedures[14];
        inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            try procedure(&args);
            procedure_pointer_head = procedure_pointer_head_.next;
        }

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

        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "RightHandSideTail" with index 18
fn parse_RightHandSideTail(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 14);

    switch (context.head(u8, 0)) {
        10 => { // '\n'
        },
        32 => { // ' '
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSideTail -> 'space', Symbol, ProcedureTail, RightHandSideTail\n", .{});
                }
            }
            try parse_generative_terminal_space(context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_Symbol(context), context); // child 1
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_ProcedureTail(context), context); // child 2
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_RightHandSideTail_0_3(context), context); // child 3
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[28],
                .node = node_address,
            };

            if (comptime rule_procedures[28]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[14];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSideTail <~ 'space', Symbol, ProcedureTail, RightHandSideTail\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mRightHandSideTail\x1b[0m.\nExpected tokens: \x1b[32m\'\\n', ' \'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "TerminalSymbol" with index 19
fn parse_TerminalSymbol(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 15);

    switch (context.head(u8, 0)) {
        34 => { // '\"'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: TerminalSymbol -> '\"', SimpleStringContent, '\"'\n", .{});
                }
            }
            try parse_terminal__x34(context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_SimpleStringContent(context), context); // child 1
            try parse_terminal__x34(context); // child 2
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[45],
                .node = node_address,
            };

            if (comptime rule_procedures[45]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[15];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_StringContent(context), context); // child 1
            try parse_terminal__x92x03(context); // child 2
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[44],
                .node = node_address,
            };

            if (comptime rule_procedures[44]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[15];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: TerminalSymbol <~ ''', StringContent, '\\x03'\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mTerminalSymbol\x1b[0m.\nExpected tokens: \x1b[32m\'\"', ''\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "GenerativeTerminalSymbol" with index 20
fn parse_GenerativeTerminalSymbol(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 16);

    switch (context.head(u8, 0)) {
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: GenerativeTerminalSymbol -> LowercaseId, GenerativeTerminalExceptions\n", .{});
                }
            }
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_LowercaseId(context), context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_GenerativeTerminalExceptions(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[11],
                .node = node_address,
            };

            if (comptime rule_procedures[11]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[16];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: GenerativeTerminalSymbol <~ LowercaseId, GenerativeTerminalExceptions\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mGenerativeTerminalSymbol\x1b[0m.\nExpected tokens: \x1b[32m\'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "UppercaseId" with index 21
fn parse_UppercaseId(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 17);

    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: UppercaseId -> 'uppercase_letter', IdTail\n", .{});
                }
            }
            try parse_generative_terminal_uppercase_letter(context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_IdTail(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[46],
                .node = node_address,
            };

            if (comptime rule_procedures[46]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[17];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: UppercaseId <~ 'uppercase_letter', IdTail\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mUppercaseId\x1b[0m.\nExpected tokens: \x1b[32m\'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "terminal__" with index 22
inline fn parse_terminal__(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        95 => { // '_'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34m_\x1b[0m.\nExpected tokens: \x1b[32m\'_\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Parser for Symbol "terminal_'" with index 23
inline fn parse_terminal__x39(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        39 => { // '''
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34m'\x1b[0m.\nExpected tokens: \x1b[32m\''\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Self-Repeating Parser for Symbol "StringContent" at index 1 of its right hand side
// Right hand side: -> 'character', StringContent
fn parse_StringContent_0_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    var repeating_node_address = node_address;
    var repeating_node: *data_structures.ASTNode = undefined;

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
                    repeating_node.immediate_insert_child(repeating_node_address, temporary_address, context); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_generative_terminal_character(context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_StringContent(context);
    if (node_address == data_structures.ASTNode.invalid_pointer) {
        node_address = exit_node;
    } else {
        repeating_node.immediate_insert_child(repeating_node_address, exit_node, context); // child 1
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
            .rule = rules[40],
            .node = repeating_node_address,
        };

        if (comptime rule_procedures[40]) |procedure_pointer| {
            const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        comptime var procedure_pointer_head = variable_procedures[18];
        inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            try procedure(&args);
            procedure_pointer_head = procedure_pointer_head_.next;
        }

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

        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "StringContent" with index 24
fn parse_StringContent(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 18);

    switch (context.head(u8, 0)) {
        3 => { // '\x03'
        },
        9, 10, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: StringContent -> 'character', StringContent\n", .{});
                }
            }
            try parse_generative_terminal_character(context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_StringContent_0_1(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[40],
                .node = node_address,
            };

            if (comptime rule_procedures[40]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[18];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: StringContent <~ 'character', StringContent\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mStringContent\x1b[0m.\nExpected tokens: \x1b[32m\'\\x03', '\\t', '\\n', '\\x0b', '\\x0c', '\\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{{', '|', '}}', '~\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_\x03" with index 25
inline fn parse_terminal__x92x03(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        3 => { // '\x03'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34m\\x03\x1b[0m.\nExpected tokens: \x1b[32m\'\\x03\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Parser for Symbol "terminal_"" with index 26
inline fn parse_terminal__x34(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        34 => { // '\"'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34m\"\x1b[0m.\nExpected tokens: \x1b[32m\'\"\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Self-Repeating Parser for Symbol "SimpleStringContent" at index 1 of its right hand side
// Right hand side: -> 'character^'\"\\x03', SimpleStringContent
fn parse_SimpleStringContent_0_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    var repeating_node_address = node_address;
    var repeating_node: *data_structures.ASTNode = undefined;

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
                    repeating_node.immediate_insert_child(repeating_node_address, temporary_address, context); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_generative_terminal_character_x94_x39_x34_x92x03(context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_SimpleStringContent(context);
    if (node_address == data_structures.ASTNode.invalid_pointer) {
        node_address = exit_node;
    } else {
        repeating_node.immediate_insert_child(repeating_node_address, exit_node, context); // child 1
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
            .rule = rules[37],
            .node = repeating_node_address,
        };

        if (comptime rule_procedures[37]) |procedure_pointer| {
            const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        comptime var procedure_pointer_head = variable_procedures[19];
        inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            try procedure(&args);
            procedure_pointer_head = procedure_pointer_head_.next;
        }

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

        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "SimpleStringContent" with index 27
fn parse_SimpleStringContent(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 19);

    switch (context.head(u8, 0)) {
        9, 10, 11, 12, 13, 32, 33, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: SimpleStringContent -> 'character^'\"\\x03', SimpleStringContent\n", .{});
                }
            }
            try parse_generative_terminal_character_x94_x39_x34_x92x03(context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_SimpleStringContent_0_1(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[37],
                .node = node_address,
            };

            if (comptime rule_procedures[37]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[19];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: SimpleStringContent <~ 'character^'\"\\x03', SimpleStringContent\n", .{});
                }
            }
        },
        34 => { // '\"'
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mSimpleStringContent\x1b[0m.\nExpected tokens: \x1b[32m\'\\t', '\\n', '\\x0b', '\\x0c', '\\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{{', '|', '}}', '~\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "LowercaseId" with index 28
fn parse_LowercaseId(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 20);

    switch (context.head(u8, 0)) {
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: LowercaseId -> 'lowercase_letter', IdTail\n", .{});
                }
            }
            try parse_generative_terminal_lowercase_letter(context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_IdTail(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[16],
                .node = node_address,
            };

            if (comptime rule_procedures[16]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[20];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: LowercaseId <~ 'lowercase_letter', IdTail\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mLowercaseId\x1b[0m.\nExpected tokens: \x1b[32m\'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "GenerativeTerminalExceptions" at index 2 of its right hand side
// Right hand side: -> '^', TerminalSymbol, GenerativeTerminalExceptions
fn parse_GenerativeTerminalExceptions_0_2(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    var repeating_node_address = node_address;
    var repeating_node: *data_structures.ASTNode = undefined;

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
                    repeating_node.immediate_insert_child(repeating_node_address, temporary_address, context); // child 2
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_terminal__x94(context); // child 0
                repeating_node.immediate_insert_child(repeating_node_address, try parse_TerminalSymbol(context), context); // child 1
            },
            else => break,
        }
    }
    const exit_node = try parse_GenerativeTerminalExceptions(context);
    if (node_address == data_structures.ASTNode.invalid_pointer) {
        node_address = exit_node;
    } else {
        repeating_node.immediate_insert_child(repeating_node_address, exit_node, context); // child 2
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
            .rule = rules[10],
            .node = repeating_node_address,
        };

        if (comptime rule_procedures[10]) |procedure_pointer| {
            const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        comptime var procedure_pointer_head = variable_procedures[21];
        inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            try procedure(&args);
            procedure_pointer_head = procedure_pointer_head_.next;
        }

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

        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "GenerativeTerminalExceptions" with index 29
fn parse_GenerativeTerminalExceptions(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 21);

    switch (context.head(u8, 0)) {
        10, 32, 64 => { // '\n', ' ', '@'
        },
        94 => { // '^'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: GenerativeTerminalExceptions -> '^', TerminalSymbol, GenerativeTerminalExceptions\n", .{});
                }
            }
            try parse_terminal__x94(context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_TerminalSymbol(context), context); // child 1
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_GenerativeTerminalExceptions_0_2(context), context); // child 2
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[10],
                .node = node_address,
            };

            if (comptime rule_procedures[10]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[21];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: GenerativeTerminalExceptions <~ '^', TerminalSymbol, GenerativeTerminalExceptions\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mGenerativeTerminalExceptions\x1b[0m.\nExpected tokens: \x1b[32m\'\\n', ' ', '@', '^\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_^" with index 30
inline fn parse_terminal__x94(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        94 => { // '^'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34m^\x1b[0m.\nExpected tokens: \x1b[32m\'^\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Parser for Symbol "terminal_@" with index 31
inline fn parse_terminal__x64(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        64 => { // '@'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34m@\x1b[0m.\nExpected tokens: \x1b[32m\'@\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Parser for Symbol "generative_terminal_character" with index 32
inline fn parse_generative_terminal_character(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        9, 10, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mcharacter\x1b[0m.\nExpected tokens: \x1b[32m\'\\t', '\\n', '\\x0b', '\\x0c', '\\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{{', '|', '}}', '~\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Parser for Symbol "generative_terminal_character^'"\x03" with index 33
inline fn parse_generative_terminal_character_x94_x39_x34_x92x03(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        9, 10, 11, 12, 13, 32, 33, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mcharacter^'\"\\x03\x1b[0m.\nExpected tokens: \x1b[32m\'\\t', '\\n', '\\x0b', '\\x0c', '\\r', ' ', '!', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{{', '|', '}}', '~\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Parser for Symbol "ControlCharacter" with index 34
fn parse_ControlCharacter(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 22);

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
                .rule = rules[6],
                .node = node_address,
            };

            if (comptime rule_procedures[6]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[22];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

            if (comptime symbol_procedures[34]) |procedure_pointer| {
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
                .rule = rules[5],
                .node = node_address,
            };

            if (comptime rule_procedures[5]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[22];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

            if (comptime symbol_procedures[34]) |procedure_pointer| {
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
                .rule = rules[7],
                .node = node_address,
            };

            if (comptime rule_procedures[7]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[22];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

            if (comptime symbol_procedures[34]) |procedure_pointer| {
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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: ControlCharacter <~ '\\x04'\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mControlCharacter\x1b[0m.\nExpected tokens: \x1b[32m\'\\x01', '\\x03', '\\x04\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_\x01" with index 35
inline fn parse_terminal__x92x01(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        1 => { // '\x01'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34m\\x01\x1b[0m.\nExpected tokens: \x1b[32m\'\\x01\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Parser for Symbol "terminal_\x04" with index 36
inline fn parse_terminal__x92x04(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        4 => { // '\x04'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34m\\x04\x1b[0m.\nExpected tokens: \x1b[32m\'\\x04\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Parser for Symbol "generative_terminal_character^"\n"" with index 37
inline fn parse_generative_terminal_character_x94_x34_x92n_x34(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        9, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mcharacter^\"\\n\"\x1b[0m.\nExpected tokens: \x1b[32m\'\\t', '\\x0b', '\\x0c', '\\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{{', '|', '}}', '~\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Self-Repeating Parser for Symbol "AnyContentTail" at index 1 of its right hand side
// Right hand side: -> ControlCharacter, AnyContentTail
fn parse_AnyContentTail_1_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    var repeating_node_address = node_address;
    var repeating_node: *data_structures.ASTNode = undefined;

    while (true) {
        switch (context.head(u8, 0)) {
            1, 3, 4 => { // '\x01', '\x03', '\x04'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: AnyContentTail -> ControlCharacter, AnyContentTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 23);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediate_insert_child(repeating_node_address, temporary_address, context); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                repeating_node.immediate_insert_child(repeating_node_address, try parse_ControlCharacter(context), context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_AnyContentTail(context);
    if (node_address == data_structures.ASTNode.invalid_pointer) {
        node_address = exit_node;
    } else {
        repeating_node.immediate_insert_child(repeating_node_address, exit_node, context); // child 1
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

        if (comptime rule_procedures[3]) |procedure_pointer| {
            const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        comptime var procedure_pointer_head = variable_procedures[23];
        inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            try procedure(&args);
            procedure_pointer_head = procedure_pointer_head_.next;
        }

        if (comptime symbol_procedures[38]) |procedure_pointer| {
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

        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "AnyContentTail" at index 1 of its right hand side
// Right hand side: -> 'character^\"\\n\"', AnyContentTail
fn parse_AnyContentTail_0_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    var repeating_node_address = node_address;
    var repeating_node: *data_structures.ASTNode = undefined;

    while (true) {
        switch (context.head(u8, 0)) {
            9, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: AnyContentTail -> 'character^\"\\n\"', AnyContentTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 23);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediate_insert_child(repeating_node_address, temporary_address, context); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_generative_terminal_character_x94_x34_x92n_x34(context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_AnyContentTail(context);
    if (node_address == data_structures.ASTNode.invalid_pointer) {
        node_address = exit_node;
    } else {
        repeating_node.immediate_insert_child(repeating_node_address, exit_node, context); // child 1
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

        if (comptime rule_procedures[4]) |procedure_pointer| {
            const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        comptime var procedure_pointer_head = variable_procedures[23];
        inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            try procedure(&args);
            procedure_pointer_head = procedure_pointer_head_.next;
        }

        if (comptime symbol_procedures[38]) |procedure_pointer| {
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

        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "AnyContentTail" with index 38
fn parse_AnyContentTail(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 23);

    switch (context.head(u8, 0)) {
        1, 3, 4 => { // '\x01', '\x03', '\x04'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: AnyContentTail -> ControlCharacter, AnyContentTail\n", .{});
                }
            }
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_ControlCharacter(context), context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_AnyContentTail_1_1(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[3],
                .node = node_address,
            };

            if (comptime rule_procedures[3]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[23];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

            if (comptime symbol_procedures[38]) |procedure_pointer| {
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
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_AnyContentTail_0_1(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[4],
                .node = node_address,
            };

            if (comptime rule_procedures[4]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[23];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

            if (comptime symbol_procedures[38]) |procedure_pointer| {
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

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: AnyContentTail <~ 'character^\"\\n\"', AnyContentTail\n", .{});
                }
            }
        },
        10 => { // '\n'
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mAnyContentTail\x1b[0m.\nExpected tokens: \x1b[32m\'\\x01', '\\x03', '\\x04', '\\t', '\\n', '\\x0b', '\\x0c', '\\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{{', '|', '}}', '~\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "IdTail" at index 1 of its right hand side
// Right hand side: -> '_', IdTail
fn parse_IdTail_2_1(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    var node_address = data_structures.ASTNode.invalid_pointer;
    var repeating_node_address = node_address;
    var repeating_node: *data_structures.ASTNode = undefined;

    while (true) {
        switch (context.head(u8, 0)) {
            95 => { // '_'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: IdTail -> '_', IdTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 24);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediate_insert_child(repeating_node_address, temporary_address, context); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_terminal__(context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_IdTail(context);
    if (node_address == data_structures.ASTNode.invalid_pointer) {
        node_address = exit_node;
    } else {
        repeating_node.immediate_insert_child(repeating_node_address, exit_node, context); // child 1
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
            .rule = rules[13],
            .node = repeating_node_address,
        };

        if (comptime rule_procedures[13]) |procedure_pointer| {
            const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        comptime var procedure_pointer_head = variable_procedures[24];
        inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            try procedure(&args);
            procedure_pointer_head = procedure_pointer_head_.next;
        }

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
                std.debug.print("Procedure outcome for IdTail: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
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
    var repeating_node_address = node_address;
    var repeating_node: *data_structures.ASTNode = undefined;

    while (true) {
        switch (context.head(u8, 0)) {
            65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: IdTail -> 'letter', IdTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 24);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediate_insert_child(repeating_node_address, temporary_address, context); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_generative_terminal_letter(context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_IdTail(context);
    if (node_address == data_structures.ASTNode.invalid_pointer) {
        node_address = exit_node;
    } else {
        repeating_node.immediate_insert_child(repeating_node_address, exit_node, context); // child 1
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
            .rule = rules[14],
            .node = repeating_node_address,
        };

        if (comptime rule_procedures[14]) |procedure_pointer| {
            const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        comptime var procedure_pointer_head = variable_procedures[24];
        inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            try procedure(&args);
            procedure_pointer_head = procedure_pointer_head_.next;
        }

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
                std.debug.print("Procedure outcome for IdTail: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
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
    var repeating_node_address = node_address;
    var repeating_node: *data_structures.ASTNode = undefined;

    while (true) {
        switch (context.head(u8, 0)) {
            48, 49, 50, 51, 52, 53, 54, 55, 56, 57 => { // '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: IdTail -> 'digit', IdTail\n", .{});
                    }
                }
                const temporary_address = context.node_allocator.create(context.pos(), 24);
                if (node_address == data_structures.ASTNode.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    repeating_node.immediate_insert_child(repeating_node_address, temporary_address, context); // child 1
                }
                repeating_node_address = temporary_address;
                repeating_node = context.node_allocator.at(repeating_node_address);
                try parse_generative_terminal_digit(context); // child 0
            },
            else => break,
        }
    }
    const exit_node = try parse_IdTail(context);
    if (node_address == data_structures.ASTNode.invalid_pointer) {
        node_address = exit_node;
    } else {
        repeating_node.immediate_insert_child(repeating_node_address, exit_node, context); // child 1
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
            .rule = rules[15],
            .node = repeating_node_address,
        };

        if (comptime rule_procedures[15]) |procedure_pointer| {
            const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }

        comptime var procedure_pointer_head = variable_procedures[24];
        inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
            try procedure(&args);
            procedure_pointer_head = procedure_pointer_head_.next;
        }

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
                std.debug.print("Procedure outcome for IdTail: {f}\n", .{
                    string_utilities.fmtASTNode(args.node, context),
                });
            }
        }

        repeating_node_address = repeating_node.parent;
    }
    return node_address;
}

// Parser for Symbol "IdTail" with index 39
fn parse_IdTail(context: *data_structures.Context) anyerror!data_structures.ASTNode.Pointer {
    const node_address = context.node_allocator.create(context.pos(), 24);

    switch (context.head(u8, 0)) {
        10, 32, 64, 94 => { // '\n', ' ', '@', '^'
        },
        48, 49, 50, 51, 52, 53, 54, 55, 56, 57 => { // '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: IdTail -> 'digit', IdTail\n", .{});
                }
            }
            try parse_generative_terminal_digit(context); // child 0
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_IdTail_1_1(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[15],
                .node = node_address,
            };

            if (comptime rule_procedures[15]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[24];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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
                    std.debug.print("Procedure outcome for IdTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }

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
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_IdTail_0_1(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[14],
                .node = node_address,
            };

            if (comptime rule_procedures[14]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[24];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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
                    std.debug.print("Procedure outcome for IdTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }

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
            context.node_allocator.at(node_address).immediate_insert_child(node_address, try parse_IdTail_2_1(context), context); // child 1
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[13],
                .node = node_address,
            };

            if (comptime rule_procedures[13]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[24];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

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
                    std.debug.print("Procedure outcome for IdTail: {f}\n", .{
                        string_utilities.fmtASTNode(args.node, context),
                    });
                }
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: IdTail <~ '_', IdTail\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mIdTail\x1b[0m.\nExpected tokens: \x1b[32m\'\\n', ' ', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '^', '_', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
    return node_address;
}

// Parser for Symbol "generative_terminal_letter" with index 40
inline fn parse_generative_terminal_letter(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mletter\x1b[0m.\nExpected tokens: \x1b[32m\'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Parser for Symbol "generative_terminal_digit" with index 41
inline fn parse_generative_terminal_digit(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        48, 49, 50, 51, 52, 53, 54, 55, 56, 57 => { // '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mdigit\x1b[0m.\nExpected tokens: \x1b[32m\'0', '1', '2', '3', '4', '5', '6', '7', '8', '9\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Parser for Symbol "generative_terminal_lowercase_letter" with index 42
inline fn parse_generative_terminal_lowercase_letter(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34mlowercase_letter\x1b[0m.\nExpected tokens: \x1b[32m\'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Parser for Symbol "generative_terminal_uppercase_letter" with index 43
inline fn parse_generative_terminal_uppercase_letter(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34muppercase_letter\x1b[0m.\nExpected tokens: \x1b[32m\'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Parser for Symbol "_AugmentedStart" with index 44
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
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[49],
                .node = null,
            };

            if (comptime rule_procedures[49]) |procedure_pointer| {
                const procedure = comptime @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            comptime var procedure_pointer_head = variable_procedures[25];
            inline while (comptime procedure_pointer_head) |procedure_pointer_head_| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer_head_.procedure));
                try procedure(&args);
                procedure_pointer_head = procedure_pointer_head_.next;
            }

            if (comptime symbol_procedures[44]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _AugmentedStart <~ Start, '\\x00'\n", .{});
                }
            }
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34m_AugmentedStart\x1b[0m.\nExpected tokens: \x1b[32m\'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

// Parser for Symbol "special_EOF" with index 45
inline fn parse_special_EOF(context: *data_structures.Context) anyerror!void {
    switch (context.head(u8, 0)) {
        0 => { // '\x00'
            context.release_token(1);
        },
        else => {
            std.debug.print("\x1b[35mSyntaxError at {d}:{d}:\n\x1b[37mUnexpected token \x1b[31m\"{f}\"\x1b[37m while parsing \x1b[34m\\x00\x1b[0m.\nExpected tokens: \x1b[32m\'\\x00\'\x1b[0m\n", .{
                if (comptime builtin.mode != .ReleaseFast) context.line else 0,
                if (comptime builtin.mode != .ReleaseFast) context.column else 0,
                string_utilities.fmtString(context.token.items()),
            });
            return error.SyntaxError;
        },
    }
}

pub fn parseWithResult(context: *data_structures.Context) !root.ParseResult {
    _ = parse__AugmentedStart(context) catch {
        return error.ParseError;
    };

    if (context.verbosityLevel() > 0) {
        std.log.info("The input file was parsed successfully!", .{});
    }

    const ast_root: ?data_structures.ASTNode.Pointer = if (context.node_allocator.counter > 0) 0 else null;
    return .{ .parsed_bytes = context.pos(), .ast_root = ast_root };
}

pub fn parse(context: *data_structures.Context) !void {
    _ = try parseWithResult(context);
}
