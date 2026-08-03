const builtin = @import("builtin");
const std = @import("std");
const root = @import("galley");
const procedures = root.procedures;
const error_messages = root.error_messages;
const data_structures = root.data_structures;
const string_utilities = root.string_utilities;

pub const parser_type = data_structures.ParserType.ll;
pub const ErrorRecoveryMode = enum { disabled, automatic, explicit };
pub const is_ast_enabled = true;
pub const are_procedures_enabled = true;
pub const is_error_recovery_enabled = true;
pub const error_recovery_mode: ErrorRecoveryMode = .explicit;
pub const is_position_tracking_enabled = builtin.mode != .ReleaseFast;
pub const is_input_streaming_enabled = false;
pub const longest_terminal_length = 2;

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
    "RecoveryTail", // 10
    "ProcedureTail", // 11
    "RightHandSides", // 12
    "RightHandSideLine", // 13
    "RightHandSidesTail", // 14
    "|", // 15
    "RightHandSide", // 16
    "space", // 17
    "Symbol", // 18
    "RightHandSideTail", // 19
    "TerminalSymbol", // 20
    "GenerativeTerminalSymbol", // 21
    "UppercaseId", // 22
    "_", // 23
    "'", // 24
    "StringContent", // 25
    "\x03", // 26
    "\"", // 27
    "SimpleStringContent", // 28
    "LowercaseId", // 29
    "GenerativeTerminalExceptions", // 30
    "^", // 31
    "@", // 32
    "CamelCaseId", // 33
    "RecoveryPoint", // 34
    "!", // 35
    "RecoveryPointBody", // 36
    "character", // 37
    "_Utf8Scalar", // 38
    "character^'\"\x03", // 39
    "_Utf8TwoByte", // 40
    "_Utf8ThreeByte", // 41
    "_Utf8FourByte", // 42
    "utf8_lead_two", // 43
    "utf8_continuation", // 44
    "\xe0", // 45
    "utf8_continuation_a0_bf", // 46
    "utf8_lead_three_general", // 47
    "\xed", // 48
    "utf8_continuation_80_9f", // 49
    "\xf0", // 50
    "utf8_continuation_90_bf", // 51
    "utf8_lead_four_general", // 52
    "\xf4", // 53
    "utf8_continuation_80_8f", // 54
    "ControlCharacter", // 55
    "\x01", // 56
    "\x04", // 57
    "character^\"\n\"", // 58
    "AnyContentTail", // 59
    "IdTail", // 60
    "letter", // 61
    "digit", // 62
    "lowercase_letter", // 63
    "uppercase_letter", // 64
    "CamelCaseIdTail", // 65
    "_AugmentedStart", // 66
    "\x00", // 67
    "GenerativeTerminal", // 68
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
    false,
    true,
    false,
    true,
    false,
    true,
    false,
    false,
    false,
    true,
    true,
    true,
    true,
    true,
    true,
    true,
    true,
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
    false,
    false,
    false,
    true,
    false,
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
    false,
    true,
    true,
    false,
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
    "RecoveryTail",
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
    "RecoveryPoint",
    "RecoveryPointBody",
    "_Utf8Scalar",
    "_Utf8TwoByte",
    "_Utf8ThreeByte",
    "_Utf8FourByte",
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
    14,
    16,
    18,
    19,
    20,
    21,
    22,
    25,
    28,
    29,
    30,
    33,
    34,
    36,
    38,
    40,
    41,
    42,
    55,
    59,
    60,
    65,
    66,
    68,
};

pub const rules = &[_]data_structures.Rule{
    data_structures.Rule{ .header = 6, .right_hand_side = &[_]u16{ 55, 59 }, .right_hand_side_index = "1" }, // AnyContent
    data_structures.Rule{ .header = 6, .right_hand_side = &[_]u16{ 58, 59 }, .right_hand_side_index = "0" }, // AnyContent
    data_structures.Rule{ .header = 31, .right_hand_side = &[_]u16{}, .right_hand_side_index = "2" }, // AnyContentTail
    data_structures.Rule{ .header = 31, .right_hand_side = &[_]u16{ 55, 59 }, .right_hand_side_index = "1" }, // AnyContentTail
    data_structures.Rule{ .header = 31, .right_hand_side = &[_]u16{ 58, 59 }, .right_hand_side_index = "0" }, // AnyContentTail
    data_structures.Rule{ .header = 23, .right_hand_side = &[_]u16{ 63, 65 }, .right_hand_side_index = "0" }, // CamelCaseId
    data_structures.Rule{ .header = 33, .right_hand_side = &[_]u16{}, .right_hand_side_index = "2" }, // CamelCaseIdTail
    data_structures.Rule{ .header = 33, .right_hand_side = &[_]u16{ 61, 65 }, .right_hand_side_index = "0" }, // CamelCaseIdTail
    data_structures.Rule{ .header = 33, .right_hand_side = &[_]u16{ 62, 65 }, .right_hand_side_index = "1" }, // CamelCaseIdTail
    data_structures.Rule{ .header = 30, .right_hand_side = &[_]u16{26}, .right_hand_side_index = "1" }, // ControlCharacter
    data_structures.Rule{ .header = 30, .right_hand_side = &[_]u16{56}, .right_hand_side_index = "0" }, // ControlCharacter
    data_structures.Rule{ .header = 30, .right_hand_side = &[_]u16{57}, .right_hand_side_index = "2" }, // ControlCharacter
    data_structures.Rule{ .header = 35, .right_hand_side = &[_]u16{}, .right_hand_side_index = "0" }, // GenerativeTerminal
    data_structures.Rule{ .header = 22, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // GenerativeTerminalExceptions
    data_structures.Rule{ .header = 22, .right_hand_side = &[_]u16{ 31, 20, 30 }, .right_hand_side_index = "0" }, // GenerativeTerminalExceptions
    data_structures.Rule{ .header = 17, .right_hand_side = &[_]u16{ 29, 30 }, .right_hand_side_index = "0" }, // GenerativeTerminalSymbol
    data_structures.Rule{ .header = 32, .right_hand_side = &[_]u16{}, .right_hand_side_index = "3" }, // IdTail
    data_structures.Rule{ .header = 32, .right_hand_side = &[_]u16{ 23, 60 }, .right_hand_side_index = "2" }, // IdTail
    data_structures.Rule{ .header = 32, .right_hand_side = &[_]u16{ 61, 60 }, .right_hand_side_index = "0" }, // IdTail
    data_structures.Rule{ .header = 32, .right_hand_side = &[_]u16{ 62, 60 }, .right_hand_side_index = "1" }, // IdTail
    data_structures.Rule{ .header = 21, .right_hand_side = &[_]u16{ 63, 60 }, .right_hand_side_index = "0" }, // LowercaseId
    data_structures.Rule{ .header = 4, .right_hand_side = &[_]u16{ 5, 6 }, .right_hand_side_index = "0" }, // NewLines
    data_structures.Rule{ .header = 5, .right_hand_side = &[_]u16{}, .right_hand_side_index = "2" }, // NewLinesTail
    data_structures.Rule{ .header = 5, .right_hand_side = &[_]u16{ 5, 6 }, .right_hand_side_index = "0" }, // NewLinesTail
    data_structures.Rule{ .header = 5, .right_hand_side = &[_]u16{ 7, 8, 5, 6 }, .right_hand_side_index = "1" }, // NewLinesTail
    data_structures.Rule{ .header = 9, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // ProcedureTail
    data_structures.Rule{ .header = 9, .right_hand_side = &[_]u16{ 32, 33, 11 }, .right_hand_side_index = "0" }, // ProcedureTail
    data_structures.Rule{ .header = 24, .right_hand_side = &[_]u16{ 35, 36 }, .right_hand_side_index = "0" }, // RecoveryPoint
    data_structures.Rule{ .header = 25, .right_hand_side = &[_]u16{ 20, 31 }, .right_hand_side_index = "1" }, // RecoveryPointBody
    data_structures.Rule{ .header = 25, .right_hand_side = &[_]u16{ 31, 20 }, .right_hand_side_index = "0" }, // RecoveryPointBody
    data_structures.Rule{ .header = 8, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // RecoveryTail
    data_structures.Rule{ .header = 8, .right_hand_side = &[_]u16{ 34, 10 }, .right_hand_side_index = "0" }, // RecoveryTail
    data_structures.Rule{ .header = 13, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // RightHandSide
    data_structures.Rule{ .header = 13, .right_hand_side = &[_]u16{ 17, 18, 10, 11, 19 }, .right_hand_side_index = "0" }, // RightHandSide
    data_structures.Rule{ .header = 11, .right_hand_side = &[_]u16{ 7, 8, 5 }, .right_hand_side_index = "1" }, // RightHandSideLine
    data_structures.Rule{ .header = 11, .right_hand_side = &[_]u16{ 15, 10, 11, 16, 5 }, .right_hand_side_index = "0" }, // RightHandSideLine
    data_structures.Rule{ .header = 15, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // RightHandSideTail
    data_structures.Rule{ .header = 15, .right_hand_side = &[_]u16{ 17, 18, 10, 11, 19 }, .right_hand_side_index = "0" }, // RightHandSideTail
    data_structures.Rule{ .header = 10, .right_hand_side = &[_]u16{ 13, 14 }, .right_hand_side_index = "0" }, // RightHandSides
    data_structures.Rule{ .header = 12, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // RightHandSidesTail
    data_structures.Rule{ .header = 12, .right_hand_side = &[_]u16{ 13, 14 }, .right_hand_side_index = "0" }, // RightHandSidesTail
    data_structures.Rule{ .header = 2, .right_hand_side = &[_]u16{ 9, 10, 11, 5, 12 }, .right_hand_side_index = "0" }, // Rule
    data_structures.Rule{ .header = 1, .right_hand_side = &[_]u16{ 2, 3 }, .right_hand_side_index = "0" }, // Rules
    data_structures.Rule{ .header = 3, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // RulesTail
    data_structures.Rule{ .header = 3, .right_hand_side = &[_]u16{ 4, 2, 3 }, .right_hand_side_index = "0" }, // RulesTail
    data_structures.Rule{ .header = 20, .right_hand_side = &[_]u16{}, .right_hand_side_index = "2" }, // SimpleStringContent
    data_structures.Rule{ .header = 20, .right_hand_side = &[_]u16{ 38, 28 }, .right_hand_side_index = "1" }, // SimpleStringContent
    data_structures.Rule{ .header = 20, .right_hand_side = &[_]u16{ 39, 28 }, .right_hand_side_index = "0" }, // SimpleStringContent
    data_structures.Rule{ .header = 0, .right_hand_side = &[_]u16{1}, .right_hand_side_index = "0" }, // Start
    data_structures.Rule{ .header = 19, .right_hand_side = &[_]u16{}, .right_hand_side_index = "2" }, // StringContent
    data_structures.Rule{ .header = 19, .right_hand_side = &[_]u16{ 37, 25 }, .right_hand_side_index = "0" }, // StringContent
    data_structures.Rule{ .header = 19, .right_hand_side = &[_]u16{ 38, 25 }, .right_hand_side_index = "1" }, // StringContent
    data_structures.Rule{ .header = 14, .right_hand_side = &[_]u16{9}, .right_hand_side_index = "0" }, // Symbol
    data_structures.Rule{ .header = 14, .right_hand_side = &[_]u16{20}, .right_hand_side_index = "1" }, // Symbol
    data_structures.Rule{ .header = 14, .right_hand_side = &[_]u16{21}, .right_hand_side_index = "2" }, // Symbol
    data_structures.Rule{ .header = 16, .right_hand_side = &[_]u16{ 24, 25, 26 }, .right_hand_side_index = "0" }, // TerminalSymbol
    data_structures.Rule{ .header = 16, .right_hand_side = &[_]u16{ 27, 28, 27 }, .right_hand_side_index = "1" }, // TerminalSymbol
    data_structures.Rule{ .header = 18, .right_hand_side = &[_]u16{ 64, 60 }, .right_hand_side_index = "0" }, // UppercaseId
    data_structures.Rule{ .header = 7, .right_hand_side = &[_]u16{22}, .right_hand_side_index = "0" }, // VariableSymbol
    data_structures.Rule{ .header = 7, .right_hand_side = &[_]u16{ 23, 22 }, .right_hand_side_index = "1" }, // VariableSymbol
    data_structures.Rule{ .header = 34, .right_hand_side = &[_]u16{ 0, 67 }, .right_hand_side_index = "0" }, // _AugmentedStart
    data_structures.Rule{ .header = 29, .right_hand_side = &[_]u16{ 50, 51, 44, 44 }, .right_hand_side_index = "0" }, // _Utf8FourByte
    data_structures.Rule{ .header = 29, .right_hand_side = &[_]u16{ 52, 44, 44, 44 }, .right_hand_side_index = "1" }, // _Utf8FourByte
    data_structures.Rule{ .header = 29, .right_hand_side = &[_]u16{ 53, 54, 44, 44 }, .right_hand_side_index = "2" }, // _Utf8FourByte
    data_structures.Rule{ .header = 26, .right_hand_side = &[_]u16{40}, .right_hand_side_index = "0" }, // _Utf8Scalar
    data_structures.Rule{ .header = 26, .right_hand_side = &[_]u16{41}, .right_hand_side_index = "1" }, // _Utf8Scalar
    data_structures.Rule{ .header = 26, .right_hand_side = &[_]u16{42}, .right_hand_side_index = "2" }, // _Utf8Scalar
    data_structures.Rule{ .header = 28, .right_hand_side = &[_]u16{ 45, 46, 44 }, .right_hand_side_index = "0" }, // _Utf8ThreeByte
    data_structures.Rule{ .header = 28, .right_hand_side = &[_]u16{ 47, 44, 44 }, .right_hand_side_index = "1" }, // _Utf8ThreeByte
    data_structures.Rule{ .header = 28, .right_hand_side = &[_]u16{ 48, 49, 44 }, .right_hand_side_index = "2" }, // _Utf8ThreeByte
    data_structures.Rule{ .header = 27, .right_hand_side = &[_]u16{ 43, 44 }, .right_hand_side_index = "0" }, // _Utf8TwoByte
};

const RootReduction = struct {
    ast_root: ?data_structures.Node.Pointer = null,
    semantic_root: if (are_procedures_enabled) ?data_structures.Payload else void = if (are_procedures_enabled) null else {},
};
const ExplicitRecoveryScope = struct {
    id: usize,
    target: root.SyntaxRecoveryTarget,
    points: []const root.SyntaxRecoveryPoint,
};

fn llTryExplicitScope(context: *data_structures.Context, scope: *const ExplicitRecoveryScope) !bool {
    if (!try context.tryExplicitRecovery(scope.id, scope.target, scope.points)) return false;
    try llFlushSyntaxDiagnostic(context);
    return true;
}
fn llTryRecoverySelection_0(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_1(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_2(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    if (try llTryExplicitScope(context, &ExplicitRecoveryScope{ .id = 2, .target = .{ .lhs_variable = "Rule" }, .points = &[_]root.SyntaxRecoveryPoint{.{ .terminal = "\n\n", .@"resume" = .before }} })) return true;
    return false;
}

fn llTryRecoverySelection_3(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_4(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_6(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_8(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_9(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_10(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_11(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_12(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_13(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    if (try llTryExplicitScope(context, &ExplicitRecoveryScope{ .id = 13, .target = .{ .lhs_variable = "RightHandSideLine" }, .points = &[_]root.SyntaxRecoveryPoint{.{ .terminal = "\n", .@"resume" = .after }} })) return true;
    return false;
}

fn llTryRecoverySelection_14(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_16(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_18(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_19(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_20(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_21(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_22(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_25(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_28(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_29(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_30(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_33(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_34(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_36(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_38(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_40(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_41(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_42(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_55(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_59(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_60(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_65(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_66(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_0(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_1(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_2(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_3(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_4(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_5(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_6(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_7(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_8(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_9(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_10(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_11(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_13(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_14(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_15(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_16(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_17(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_18(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_19(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_20(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_21(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_22(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_23(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_24(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_25(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_26(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_27(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_28(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_29(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_30(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_31(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_32(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_33(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_34(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    if (try llTryExplicitScope(context, &ExplicitRecoveryScope{ .id = 13, .target = .{ .lhs_variable = "RightHandSideLine" }, .points = &[_]root.SyntaxRecoveryPoint{.{ .terminal = "\n", .@"resume" = .after }} })) return true;
    return false;
}

fn llTryRecoveryRule_35(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    if (try llTryExplicitScope(context, &ExplicitRecoveryScope{ .id = 13, .target = .{ .lhs_variable = "RightHandSideLine" }, .points = &[_]root.SyntaxRecoveryPoint{.{ .terminal = "\n", .@"resume" = .after }} })) return true;
    return false;
}

fn llTryRecoveryRule_36(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_37(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_38(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_39(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_40(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_41(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    if (try llTryExplicitScope(context, &ExplicitRecoveryScope{ .id = 2, .target = .{ .lhs_variable = "Rule" }, .points = &[_]root.SyntaxRecoveryPoint{.{ .terminal = "\n\n", .@"resume" = .before }} })) return true;
    return false;
}

fn llTryRecoveryRule_42(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_43(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_44(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_45(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_46(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_47(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_48(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_49(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_50(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_51(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_52(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_53(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_54(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_55(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_56(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_57(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_58(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_59(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_60(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_61(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_62(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_63(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_64(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_65(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_66(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_67(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_68(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_69(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_70(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

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
    var arr: [71]?*const data_structures.Procedure = .{null} ** 71;

    for (rules, 0..) |rule, index| {
        const procedure_name = "reduction_" ++ variables[rule.header] ++ "_" ++ rule.right_hand_side_index;
        if (@hasDecl(procedures, procedure_name)) {
            arr[index] = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), procedure_name);
        }
    }

    break :rule_procedures arr;
};

pub const symbol_procedures = symbol_procedures: {
    var arr: [69]?*const data_structures.Procedure = .{null} ** 69;

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
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
};

pub const variable_procedures = variable_procedures: {
    var arr: [36]?*const ProcedureSequenceNode = .{null} ** 36;

    for (variable_procedure_names, 0..) |procedure_names, index| {
        arr[index] = makeProcedureSequence(procedure_names);
    }

    break :variable_procedures arr;
};

pub const reduction_procedure: ?*const data_structures.Procedure = if (@hasDecl(procedures, "reduction")) data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, "reduction"), "reduction") else null;

// Parser for Symbol "Start" with index 0
fn parse_Start(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 0);

    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Start -> Rules\n", .{});
                }
            }
            {
                const child_node = parse_Rules(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_48(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[48],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[48]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Start <~ Rules\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_0(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "Rules" with index 1
fn parse_Rules(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 1);

    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Rules -> Rule, RulesTail\n", .{});
                }
            }
            {
                const child_node = parse_Rule(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_42(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RulesTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_42(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[42],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[42]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Rules <~ Rule, RulesTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_1(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "Rule" with index 2
fn parse_Rule(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 2);

    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Rule -> VariableSymbol, RecoveryTail, ProcedureTail, 'new_line', RightHandSides\n", .{});
                }
            }
            {
                const child_node = parse_VariableSymbol(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_41(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RecoveryTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_41(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_ProcedureTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_41(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            parse_generative_terminal_new_line(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_41(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 3
            {
                const child_node = parse_RightHandSides(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_41(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 4 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[41],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[41]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Rule <~ VariableSymbol, RecoveryTail, ProcedureTail, 'new_line', RightHandSides\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_2(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "RulesTail" at index 2 of its right hand side
// Right hand side: -> NewLines, Rule, RulesTail
fn parse_RulesTail_0_2(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            10 => { // '\n'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: RulesTail -> NewLines, Rule, RulesTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 3);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 2
                }
                repeating_node_address = temporary_address;
                {
                    const child_node = parse_NewLines(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_44(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    };
                    if (child_node != data_structures.Node.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                    }
                }
                {
                    const child_node = parse_Rule(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_44(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    };
                    if (child_node != data_structures.Node.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                    }
                }
            },
            else => break,
        }
    }
    const exit_node = parse_RulesTail(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_44(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: RulesTail <~ NewLines, Rule, RulesTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[44],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[44]) |procedure_pointer| {
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
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Parser for Symbol "RulesTail" with index 3
fn parse_RulesTail(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 3);

    switch (context.head(u8, 0)) {
        0 => { // '\x00'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RulesTail -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[43],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[43]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
                const child_node = parse_NewLines(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_44(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_Rule(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_44(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RulesTail_0_2(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_44(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[44],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[44]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RulesTail <~ NewLines, Rule, RulesTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_3(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "NewLines" with index 4
fn parse_NewLines(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 4);

    switch (context.head(u8, 0)) {
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: NewLines -> 'new_line', NewLinesTail\n", .{});
                }
            }
            parse_generative_terminal_new_line(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_21(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_NewLinesTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_21(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[21],
                .node_address = node_address,
            };
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: NewLines <~ 'new_line', NewLinesTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_4(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "generative_terminal_new_line" with index 5
inline fn parse_generative_terminal_new_line(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        10 => { // '\n'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_5(context, occurrence_recovery);
        },
    }
}

// Self-Repeating Parser for Symbol "NewLinesTail" at index 1 of its right hand side
// Right hand side: -> 'new_line', NewLinesTail
fn parse_NewLinesTail_0_1(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            10 => { // '\n'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: NewLinesTail -> 'new_line', NewLinesTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 5);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_new_line(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_23(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
            },
            else => break,
        }
    }
    const exit_node = parse_NewLinesTail(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_23(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: NewLinesTail <~ 'new_line', NewLinesTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[23],
            .node_address = repeating_node_address,
        };
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
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "NewLinesTail" at index 3 of its right hand side
// Right hand side: -> '#', AnyContent, 'new_line', NewLinesTail
fn parse_NewLinesTail_1_3(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            35 => { // '#'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: NewLinesTail -> '#', AnyContent, 'new_line', NewLinesTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 5);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 3
                }
                repeating_node_address = temporary_address;
                parse_terminal__x35(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_24(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
                {
                    const child_node = parse_AnyContent(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_24(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    };
                    if (child_node != data_structures.Node.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                    }
                }
                parse_generative_terminal_new_line(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_24(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 2
            },
            else => break,
        }
    }
    const exit_node = parse_NewLinesTail(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_24(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 3 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: NewLinesTail <~ '#', AnyContent, 'new_line', NewLinesTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[24],
            .node_address = repeating_node_address,
        };
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
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Parser for Symbol "NewLinesTail" with index 6
fn parse_NewLinesTail(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 5);

    switch (context.head(u8, 0)) {
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: NewLinesTail -> 'new_line', NewLinesTail\n", .{});
                }
            }
            parse_generative_terminal_new_line(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_23(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_NewLinesTail_0_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_23(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[23],
                .node_address = node_address,
            };
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            parse_terminal__x35(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_24(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_AnyContent(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_24(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            parse_generative_terminal_new_line(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_24(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            {
                const child_node = parse_NewLinesTail_1_3(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_24(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 3 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[24],
                .node_address = node_address,
            };
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[22],
                .node_address = node_address,
            };
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: NewLinesTail <~ \n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_6(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_#" with index 7
inline fn parse_terminal__x35(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        35 => { // '#'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_7(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "AnyContent" with index 8
fn parse_AnyContent(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 6);

    switch (context.head(u8, 0)) {
        1, 3, 4 => { // '\x01', '\x03', '\x04'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: AnyContent -> ControlCharacter, AnyContentTail\n", .{});
                }
            }
            {
                const child_node = parse_ControlCharacter(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_0(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_AnyContentTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_0(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[0],
                .node_address = node_address,
            };
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            parse_generative_terminal_character_x94_x34_x92n_x34(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_1(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_AnyContentTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_1(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[1],
                .node_address = node_address,
            };
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: AnyContent <~ 'character^\"\\n\"', AnyContentTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_8(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "VariableSymbol" with index 9
fn parse_VariableSymbol(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 7);

    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: VariableSymbol -> UppercaseId\n", .{});
                }
            }
            {
                const child_node = parse_UppercaseId(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_58(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[58],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[58]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            parse_terminal__(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_59(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_UppercaseId(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_59(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[59],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[59]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: VariableSymbol <~ '_', UppercaseId\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_9(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "RecoveryTail" at index 1 of its right hand side
// Right hand side: -> RecoveryPoint, RecoveryTail
fn parse_RecoveryTail_0_1(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            33 => { // '!'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: RecoveryTail -> RecoveryPoint, RecoveryTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 8);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                {
                    const child_node = parse_RecoveryPoint(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_31(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    };
                    if (child_node != data_structures.Node.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                    }
                }
            },
            else => break,
        }
    }
    const exit_node = parse_RecoveryTail(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_31(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: RecoveryTail <~ RecoveryPoint, RecoveryTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[31],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[31]) |procedure_pointer| {
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
                std.debug.print("Procedure outcome for RecoveryTail: {f}\n", .{
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Parser for Symbol "RecoveryTail" with index 10
fn parse_RecoveryTail(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 8);

    switch (context.head(u8, 0)) {
        10, 32, 64 => { // '\n', ' ', '@'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RecoveryTail -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[30],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[30]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for RecoveryTail: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RecoveryTail <~ \n", .{});
                }
            }
        },
        33 => { // '!'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RecoveryTail -> RecoveryPoint, RecoveryTail\n", .{});
                }
            }
            {
                const child_node = parse_RecoveryPoint(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_31(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RecoveryTail_0_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_31(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[31],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[31]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for RecoveryTail: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RecoveryTail <~ RecoveryPoint, RecoveryTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_10(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "ProcedureTail" at index 2 of its right hand side
// Right hand side: -> '@', CamelCaseId, ProcedureTail
fn parse_ProcedureTail_0_2(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            64 => { // '@'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: ProcedureTail -> '@', CamelCaseId, ProcedureTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 9);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 2
                }
                repeating_node_address = temporary_address;
                parse_terminal__x64(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_26(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
                {
                    const child_node = parse_CamelCaseId(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_26(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    };
                    if (child_node != data_structures.Node.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                    }
                }
            },
            else => break,
        }
    }
    const exit_node = parse_ProcedureTail(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_26(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: ProcedureTail <~ '@', CamelCaseId, ProcedureTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[26],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[26]) |procedure_pointer| {
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
                std.debug.print("Procedure outcome for ProcedureTail: {f}\n", .{
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Parser for Symbol "ProcedureTail" with index 11
fn parse_ProcedureTail(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 9);

    switch (context.head(u8, 0)) {
        10, 32 => { // '\n', ' '
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: ProcedureTail -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[25],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[25]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for ProcedureTail: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            parse_terminal__x64(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_26(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_CamelCaseId(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_26(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_ProcedureTail_0_2(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_26(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[26],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[26]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for ProcedureTail: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: ProcedureTail <~ '@', CamelCaseId, ProcedureTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_11(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "RightHandSides" with index 12
fn parse_RightHandSides(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 10);

    switch (context.head(u8, 0)) {
        35, 124 => { // '#', '|'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSides -> RightHandSideLine, RightHandSidesTail\n", .{});
                }
            }
            {
                const child_node = parse_RightHandSideLine(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_38(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RightHandSidesTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_38(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[38],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[38]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for RightHandSides: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSides <~ RightHandSideLine, RightHandSidesTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_12(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "RightHandSideLine" with index 13
fn parse_RightHandSideLine(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 11);

    switch (context.head(u8, 0)) {
        35 => { // '#'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSideLine -> '#', AnyContent, 'new_line'\n", .{});
                }
            }
            parse_terminal__x35(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_34(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_AnyContent(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_34(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            parse_generative_terminal_new_line(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_34(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[34],
                .node_address = node_address,
            };
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
                    std.debug.print("Procedure outcome for RightHandSideLine: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSideLine <~ '#', AnyContent, 'new_line'\n", .{});
                }
            }
        },
        124 => { // '|'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSideLine -> '|', RecoveryTail, ProcedureTail, RightHandSide, 'new_line'\n", .{});
                }
            }
            parse_terminal__x124(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_35(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_RecoveryTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_35(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_ProcedureTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_35(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RightHandSide(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_35(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 3 (chain if replaceWithChildren)
                }
            }
            parse_generative_terminal_new_line(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_35(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 4
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[35],
                .node_address = node_address,
            };
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
                    std.debug.print("Procedure outcome for RightHandSideLine: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSideLine <~ '|', RecoveryTail, ProcedureTail, RightHandSide, 'new_line'\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_13(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "RightHandSidesTail" at index 1 of its right hand side
// Right hand side: -> RightHandSideLine, RightHandSidesTail
fn parse_RightHandSidesTail_0_1(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            35, 124 => { // '#', '|'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: RightHandSidesTail -> RightHandSideLine, RightHandSidesTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 12);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                {
                    const child_node = parse_RightHandSideLine(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_40(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    };
                    if (child_node != data_structures.Node.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                    }
                }
            },
            else => break,
        }
    }
    const exit_node = parse_RightHandSidesTail(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_40(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: RightHandSidesTail <~ RightHandSideLine, RightHandSidesTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[40],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[40]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[12], &args);
        if (comptime symbol_procedures[14]) |procedure_pointer| {
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
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Parser for Symbol "RightHandSidesTail" with index 14
fn parse_RightHandSidesTail(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 12);

    switch (context.head(u8, 0)) {
        0, 10 => { // '\x00', '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSidesTail -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[39],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[39]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[12], &args);
            if (comptime symbol_procedures[14]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
                const child_node = parse_RightHandSideLine(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_40(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RightHandSidesTail_0_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_40(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[40],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[40]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[12], &args);
            if (comptime symbol_procedures[14]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSidesTail <~ RightHandSideLine, RightHandSidesTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_14(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_|" with index 15
inline fn parse_terminal__x124(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        124 => { // '|'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_15(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "RightHandSide" with index 16
fn parse_RightHandSide(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 13);

    switch (context.head(u8, 0)) {
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSide -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[32],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[32]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[13], &args);
            if (comptime symbol_procedures[16]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSide <~ \n", .{});
                }
            }
        },
        32 => { // ' '
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSide -> 'space', Symbol, RecoveryTail, ProcedureTail, RightHandSideTail\n", .{});
                }
            }
            parse_generative_terminal_space(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_33(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_Symbol(context, &ExplicitRecoveryScope{ .id = 190, .target = .{ .occurrence = .{ .parent_variable = "RightHandSide", .rhs_index = 0, .symbol_index = 1, .variable = "Symbol" } }, .points = &[_]root.SyntaxRecoveryPoint{.{ .terminal = "\n", .@"resume" = .before }} }) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_33(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RecoveryTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_33(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_ProcedureTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_33(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 3 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RightHandSideTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_33(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 4 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[33],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[33]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[13], &args);
            if (comptime symbol_procedures[16]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSide <~ 'space', Symbol, RecoveryTail, ProcedureTail, RightHandSideTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_16(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "generative_terminal_space" with index 17
inline fn parse_generative_terminal_space(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        32 => { // ' '
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_17(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "Symbol" with index 18
fn parse_Symbol(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 14);

    switch (context.head(u8, 0)) {
        34, 39 => { // '\"', '''
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Symbol -> TerminalSymbol\n", .{});
                }
            }
            {
                const child_node = parse_TerminalSymbol(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_53(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[53],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[53]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for Symbol: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
                const child_node = parse_VariableSymbol(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_52(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[52],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[52]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for Symbol: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
                const child_node = parse_GenerativeTerminalSymbol(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_54(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[54],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[54]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for Symbol: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Symbol <~ GenerativeTerminalSymbol\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_18(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "RightHandSideTail" at index 4 of its right hand side
// Right hand side: -> 'space', Symbol, RecoveryTail, ProcedureTail, RightHandSideTail
fn parse_RightHandSideTail_0_4(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            32 => { // ' '
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: RightHandSideTail -> 'space', Symbol, RecoveryTail, ProcedureTail, RightHandSideTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 15);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 4
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_space(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_37(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
                {
                    const child_node = parse_Symbol(context, &ExplicitRecoveryScope{ .id = 203, .target = .{ .occurrence = .{ .parent_variable = "RightHandSideTail", .rhs_index = 0, .symbol_index = 1, .variable = "Symbol" } }, .points = &[_]root.SyntaxRecoveryPoint{.{ .terminal = "\n", .@"resume" = .before }} }) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_37(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    };
                    if (child_node != data_structures.Node.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                    }
                }
                {
                    const child_node = parse_RecoveryTail(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_37(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    };
                    if (child_node != data_structures.Node.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                    }
                }
                {
                    const child_node = parse_ProcedureTail(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_37(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    };
                    if (child_node != data_structures.Node.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 3 (chain if replaceWithChildren)
                    }
                }
            },
            else => break,
        }
    }
    const exit_node = parse_RightHandSideTail(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_37(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 4 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: RightHandSideTail <~ 'space', Symbol, RecoveryTail, ProcedureTail, RightHandSideTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[37],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[37]) |procedure_pointer| {
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
                std.debug.print("Procedure outcome for RightHandSideTail: {f}\n", .{
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Parser for Symbol "RightHandSideTail" with index 19
fn parse_RightHandSideTail(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 15);

    switch (context.head(u8, 0)) {
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSideTail -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[36],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[36]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for RightHandSideTail: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSideTail <~ \n", .{});
                }
            }
        },
        32 => { // ' '
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSideTail -> 'space', Symbol, RecoveryTail, ProcedureTail, RightHandSideTail\n", .{});
                }
            }
            parse_generative_terminal_space(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_37(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_Symbol(context, &ExplicitRecoveryScope{ .id = 203, .target = .{ .occurrence = .{ .parent_variable = "RightHandSideTail", .rhs_index = 0, .symbol_index = 1, .variable = "Symbol" } }, .points = &[_]root.SyntaxRecoveryPoint{.{ .terminal = "\n", .@"resume" = .before }} }) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_37(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RecoveryTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_37(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_ProcedureTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_37(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 3 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RightHandSideTail_0_4(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_37(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 4 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[37],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[37]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for RightHandSideTail: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSideTail <~ 'space', Symbol, RecoveryTail, ProcedureTail, RightHandSideTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_19(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "TerminalSymbol" with index 20
fn parse_TerminalSymbol(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 16);

    switch (context.head(u8, 0)) {
        34 => { // '\"'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: TerminalSymbol -> '\"', SimpleStringContent, '\"'\n", .{});
                }
            }
            parse_terminal__x34(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_56(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_SimpleStringContent(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_56(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            parse_terminal__x34(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_56(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[56],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[56]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for TerminalSymbol: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            parse_terminal__x39(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_55(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_StringContent(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_55(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            parse_terminal__x92x03(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_55(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[55],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[55]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for TerminalSymbol: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: TerminalSymbol <~ ''', StringContent, '\\x03'\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_20(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "GenerativeTerminalSymbol" with index 21
fn parse_GenerativeTerminalSymbol(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 17);

    switch (context.head(u8, 0)) {
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: GenerativeTerminalSymbol -> LowercaseId, GenerativeTerminalExceptions\n", .{});
                }
            }
            {
                const child_node = parse_LowercaseId(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_15(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_GenerativeTerminalExceptions(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_15(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[15],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[15]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for GenerativeTerminalSymbol: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: GenerativeTerminalSymbol <~ LowercaseId, GenerativeTerminalExceptions\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_21(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "UppercaseId" with index 22
fn parse_UppercaseId(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 18);

    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: UppercaseId -> 'uppercase_letter', IdTail\n", .{});
                }
            }
            parse_generative_terminal_uppercase_letter(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_57(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_IdTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_57(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[57],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[57]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[18], &args);
            if (comptime symbol_procedures[22]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: UppercaseId <~ 'uppercase_letter', IdTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_22(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "terminal__" with index 23
inline fn parse_terminal__(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        95 => { // '_'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_23(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "terminal_'" with index 24
inline fn parse_terminal__x39(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        39 => { // '''
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_24(context, occurrence_recovery);
        },
    }
}

// Self-Repeating Parser for Symbol "StringContent" at index 1 of its right hand side
// Right hand side: -> 'character', StringContent
fn parse_StringContent_0_1(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            9, 10, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: StringContent -> 'character', StringContent\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 19);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_character(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_50(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
            },
            else => break,
        }
    }
    const exit_node = parse_StringContent(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_50(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: StringContent <~ 'character', StringContent\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[50],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[50]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[19], &args);
        if (comptime symbol_procedures[25]) |procedure_pointer| {
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
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "StringContent" at index 1 of its right hand side
// Right hand side: -> _Utf8Scalar, StringContent
fn parse_StringContent_1_1(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf', '\xe0', '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xed', '\xee', '\xef', '\xf0', '\xf1', '\xf2', '\xf3', '\xf4'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: StringContent -> _Utf8Scalar, StringContent\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 19);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse__Utf8Scalar_(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_51(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
            },
            else => break,
        }
    }
    const exit_node = parse_StringContent(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_51(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: StringContent <~ _Utf8Scalar, StringContent\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[51],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[51]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[19], &args);
        if (comptime symbol_procedures[25]) |procedure_pointer| {
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
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Parser for Symbol "StringContent" with index 25
fn parse_StringContent(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 19);

    switch (context.head(u8, 0)) {
        3 => { // '\x03'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: StringContent -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[49],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[49]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[19], &args);
            if (comptime symbol_procedures[25]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            parse_generative_terminal_character(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_50(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_StringContent_0_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_50(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[50],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[50]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[19], &args);
            if (comptime symbol_procedures[25]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: StringContent <~ 'character', StringContent\n", .{});
                }
            }
        },
        194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf', '\xe0', '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xed', '\xee', '\xef', '\xf0', '\xf1', '\xf2', '\xf3', '\xf4'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: StringContent -> _Utf8Scalar, StringContent\n", .{});
                }
            }
            parse__Utf8Scalar_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_51(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_StringContent_1_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_51(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[51],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[51]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[19], &args);
            if (comptime symbol_procedures[25]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: StringContent <~ _Utf8Scalar, StringContent\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_25(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_\x03" with index 26
inline fn parse_terminal__x92x03(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        3 => { // '\x03'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_26(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "terminal_"" with index 27
inline fn parse_terminal__x34(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        34 => { // '\"'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_27(context, occurrence_recovery);
        },
    }
}

// Self-Repeating Parser for Symbol "SimpleStringContent" at index 1 of its right hand side
// Right hand side: -> _Utf8Scalar, SimpleStringContent
fn parse_SimpleStringContent_1_1(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf', '\xe0', '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xed', '\xee', '\xef', '\xf0', '\xf1', '\xf2', '\xf3', '\xf4'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: SimpleStringContent -> _Utf8Scalar, SimpleStringContent\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 20);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse__Utf8Scalar_(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_46(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
            },
            else => break,
        }
    }
    const exit_node = parse_SimpleStringContent(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_46(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: SimpleStringContent <~ _Utf8Scalar, SimpleStringContent\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[46],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[46]) |procedure_pointer| {
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
                std.debug.print("Procedure outcome for SimpleStringContent: {f}\n", .{
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "SimpleStringContent" at index 1 of its right hand side
// Right hand side: -> 'character^'\"\\x03', SimpleStringContent
fn parse_SimpleStringContent_0_1(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            9, 10, 11, 12, 13, 32, 33, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: SimpleStringContent -> 'character^'\"\\x03', SimpleStringContent\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 20);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_character_x94_x39_x34_x92x03(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_47(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
            },
            else => break,
        }
    }
    const exit_node = parse_SimpleStringContent(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_47(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: SimpleStringContent <~ 'character^'\"\\x03', SimpleStringContent\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[47],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[47]) |procedure_pointer| {
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
                std.debug.print("Procedure outcome for SimpleStringContent: {f}\n", .{
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Parser for Symbol "SimpleStringContent" with index 28
fn parse_SimpleStringContent(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 20);

    switch (context.head(u8, 0)) {
        9, 10, 11, 12, 13, 32, 33, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: SimpleStringContent -> 'character^'\"\\x03', SimpleStringContent\n", .{});
                }
            }
            parse_generative_terminal_character_x94_x39_x34_x92x03(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_47(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_SimpleStringContent_0_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_47(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[47],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[47]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for SimpleStringContent: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[45],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[45]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for SimpleStringContent: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: SimpleStringContent <~ \n", .{});
                }
            }
        },
        194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf', '\xe0', '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xed', '\xee', '\xef', '\xf0', '\xf1', '\xf2', '\xf3', '\xf4'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: SimpleStringContent -> _Utf8Scalar, SimpleStringContent\n", .{});
                }
            }
            parse__Utf8Scalar_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_46(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_SimpleStringContent_1_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_46(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[46],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[46]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for SimpleStringContent: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: SimpleStringContent <~ _Utf8Scalar, SimpleStringContent\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_28(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "LowercaseId" with index 29
fn parse_LowercaseId(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 21);

    switch (context.head(u8, 0)) {
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: LowercaseId -> 'lowercase_letter', IdTail\n", .{});
                }
            }
            parse_generative_terminal_lowercase_letter(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_20(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_IdTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_20(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[20],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[20]) |procedure_pointer| {
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
                    std.debug.print("Procedure outcome for LowercaseId: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: LowercaseId <~ 'lowercase_letter', IdTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_29(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "GenerativeTerminalExceptions" at index 2 of its right hand side
// Right hand side: -> '^', TerminalSymbol, GenerativeTerminalExceptions
fn parse_GenerativeTerminalExceptions_0_2(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            94 => { // '^'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: GenerativeTerminalExceptions -> '^', TerminalSymbol, GenerativeTerminalExceptions\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 22);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 2
                }
                repeating_node_address = temporary_address;
                parse_terminal__x94(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_14(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
                {
                    const child_node = parse_TerminalSymbol(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_14(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    };
                    if (child_node != data_structures.Node.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                    }
                }
            },
            else => break,
        }
    }
    const exit_node = parse_GenerativeTerminalExceptions(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_14(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: GenerativeTerminalExceptions <~ '^', TerminalSymbol, GenerativeTerminalExceptions\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[14],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[14]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[22], &args);
        if (comptime symbol_procedures[30]) |procedure_pointer| {
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
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Parser for Symbol "GenerativeTerminalExceptions" with index 30
fn parse_GenerativeTerminalExceptions(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 22);

    switch (context.head(u8, 0)) {
        10, 32, 33, 64 => { // '\n', ' ', '!', '@'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: GenerativeTerminalExceptions -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[13],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[13]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[22], &args);
            if (comptime symbol_procedures[30]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            parse_terminal__x94(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_14(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_TerminalSymbol(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_14(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_GenerativeTerminalExceptions_0_2(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_14(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[14],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[14]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[22], &args);
            if (comptime symbol_procedures[30]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: GenerativeTerminalExceptions <~ '^', TerminalSymbol, GenerativeTerminalExceptions\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_30(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_^" with index 31
inline fn parse_terminal__x94(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        94 => { // '^'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_31(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "terminal_@" with index 32
inline fn parse_terminal__x64(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        64 => { // '@'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_32(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "CamelCaseId" with index 33
fn parse_CamelCaseId(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 23);

    switch (context.head(u8, 0)) {
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: CamelCaseId -> 'lowercase_letter', CamelCaseIdTail\n", .{});
                }
            }
            parse_generative_terminal_lowercase_letter(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_5(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_CamelCaseIdTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_5(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[5],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[5]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[23], &args);
            if (comptime symbol_procedures[33]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: CamelCaseId <~ 'lowercase_letter', CamelCaseIdTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_33(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "RecoveryPoint" with index 34
fn parse_RecoveryPoint(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 24);

    switch (context.head(u8, 0)) {
        33 => { // '!'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RecoveryPoint -> '!', RecoveryPointBody\n", .{});
                }
            }
            parse_terminal__x33(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_27(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_RecoveryPointBody(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_27(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[27],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[27]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[24], &args);
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
                    std.debug.print("Procedure outcome for RecoveryPoint: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RecoveryPoint <~ '!', RecoveryPointBody\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_34(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_!" with index 35
inline fn parse_terminal__x33(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        33 => { // '!'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_35(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "RecoveryPointBody" with index 36
fn parse_RecoveryPointBody(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 25);

    switch (context.head(u8, 0)) {
        34, 39 => { // '\"', '''
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RecoveryPointBody -> TerminalSymbol, '^'\n", .{});
                }
            }
            {
                const child_node = parse_TerminalSymbol(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_28(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            parse_terminal__x94(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_28(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[28],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[28]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[25], &args);
            if (comptime symbol_procedures[36]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for RecoveryPointBody: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RecoveryPointBody <~ TerminalSymbol, '^'\n", .{});
                }
            }
        },
        94 => { // '^'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RecoveryPointBody -> '^', TerminalSymbol\n", .{});
                }
            }
            parse_terminal__x94(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_29(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_TerminalSymbol(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_29(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[29],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[29]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[25], &args);
            if (comptime symbol_procedures[36]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for RecoveryPointBody: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RecoveryPointBody <~ '^', TerminalSymbol\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_36(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "generative_terminal_character" with index 37
inline fn parse_generative_terminal_character(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        9, 10, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_37(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "_Utf8Scalar" with index 38
fn parse__Utf8Scalar(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8Scalar -> _Utf8TwoByte\n", .{});
                }
            }
            parse__Utf8TwoByte_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_64(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8Scalar <~ _Utf8TwoByte\n", .{});
                }
            }
        },
        224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239 => { // '\xe0', '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xed', '\xee', '\xef'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8Scalar -> _Utf8ThreeByte\n", .{});
                }
            }
            parse__Utf8ThreeByte_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_65(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8Scalar <~ _Utf8ThreeByte\n", .{});
                }
            }
        },
        240, 241, 242, 243, 244 => { // '\xf0', '\xf1', '\xf2', '\xf3', '\xf4'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8Scalar -> _Utf8FourByte\n", .{});
                }
            }
            parse__Utf8FourByte_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_66(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8Scalar <~ _Utf8FourByte\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_38(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_character^'"\x03" with index 39
inline fn parse_generative_terminal_character_x94_x39_x34_x92x03(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        9, 10, 11, 12, 13, 32, 33, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_39(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "_Utf8TwoByte" with index 40
fn parse__Utf8TwoByte(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8TwoByte -> 'utf8_lead_two', 'utf8_continuation'\n", .{});
                }
            }
            parse_generative_terminal_utf8_lead_two(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_70(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_70(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8TwoByte <~ 'utf8_lead_two', 'utf8_continuation'\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_40(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "_Utf8ThreeByte" with index 41
fn parse__Utf8ThreeByte(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        224 => { // '\xe0'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8ThreeByte -> '\\xe0', 'utf8_continuation_a0_bf', 'utf8_continuation'\n", .{});
                }
            }
            parse_terminal__x92xe0(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_67(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_a0_bf(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_67(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_67(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8ThreeByte <~ '\\xe0', 'utf8_continuation_a0_bf', 'utf8_continuation'\n", .{});
                }
            }
        },
        225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 238, 239 => { // '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xee', '\xef'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8ThreeByte -> 'utf8_lead_three_general', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
            parse_generative_terminal_utf8_lead_three_general(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_68(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_68(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_68(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8ThreeByte <~ 'utf8_lead_three_general', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
        },
        237 => { // '\xed'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8ThreeByte -> '\\xed', 'utf8_continuation_80_9f', 'utf8_continuation'\n", .{});
                }
            }
            parse_terminal__x92xed(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_69(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_80_9f(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_69(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_69(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8ThreeByte <~ '\\xed', 'utf8_continuation_80_9f', 'utf8_continuation'\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_41(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "_Utf8FourByte" with index 42
fn parse__Utf8FourByte(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        240 => { // '\xf0'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8FourByte -> '\\xf0', 'utf8_continuation_90_bf', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
            parse_terminal__x92xf0(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_61(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_90_bf(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_61(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_61(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_61(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 3
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8FourByte <~ '\\xf0', 'utf8_continuation_90_bf', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
        },
        241, 242, 243 => { // '\xf1', '\xf2', '\xf3'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8FourByte -> 'utf8_lead_four_general', 'utf8_continuation', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
            parse_generative_terminal_utf8_lead_four_general(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_62(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_62(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_62(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_62(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 3
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8FourByte <~ 'utf8_lead_four_general', 'utf8_continuation', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
        },
        244 => { // '\xf4'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8FourByte -> '\\xf4', 'utf8_continuation_80_8f', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
            parse_terminal__x92xf4(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_63(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_80_8f(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_63(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_63(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_63(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 3
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8FourByte <~ '\\xf4', 'utf8_continuation_80_8f', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_42(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_utf8_lead_two" with index 43
inline fn parse_generative_terminal_utf8_lead_two(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_43(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_utf8_continuation" with index 44
inline fn parse_generative_terminal_utf8_continuation(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191 => { // '\x80', '\x81', '\x82', '\x83', '\x84', '\x85', '\x86', '\x87', '\x88', '\x89', '\x8a', '\x8b', '\x8c', '\x8d', '\x8e', '\x8f', '\x90', '\x91', '\x92', '\x93', '\x94', '\x95', '\x96', '\x97', '\x98', '\x99', '\x9a', '\x9b', '\x9c', '\x9d', '\x9e', '\x9f', '\xa0', '\xa1', '\xa2', '\xa3', '\xa4', '\xa5', '\xa6', '\xa7', '\xa8', '\xa9', '\xaa', '\xab', '\xac', '\xad', '\xae', '\xaf', '\xb0', '\xb1', '\xb2', '\xb3', '\xb4', '\xb5', '\xb6', '\xb7', '\xb8', '\xb9', '\xba', '\xbb', '\xbc', '\xbd', '\xbe', '\xbf'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_44(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "terminal_\xe0" with index 45
inline fn parse_terminal__x92xe0(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        224 => { // '\xe0'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_45(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_utf8_continuation_a0_bf" with index 46
inline fn parse_generative_terminal_utf8_continuation_a0_bf(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191 => { // '\xa0', '\xa1', '\xa2', '\xa3', '\xa4', '\xa5', '\xa6', '\xa7', '\xa8', '\xa9', '\xaa', '\xab', '\xac', '\xad', '\xae', '\xaf', '\xb0', '\xb1', '\xb2', '\xb3', '\xb4', '\xb5', '\xb6', '\xb7', '\xb8', '\xb9', '\xba', '\xbb', '\xbc', '\xbd', '\xbe', '\xbf'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_46(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_utf8_lead_three_general" with index 47
inline fn parse_generative_terminal_utf8_lead_three_general(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 238, 239 => { // '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xee', '\xef'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_47(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "terminal_\xed" with index 48
inline fn parse_terminal__x92xed(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        237 => { // '\xed'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_48(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_utf8_continuation_80_9f" with index 49
inline fn parse_generative_terminal_utf8_continuation_80_9f(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159 => { // '\x80', '\x81', '\x82', '\x83', '\x84', '\x85', '\x86', '\x87', '\x88', '\x89', '\x8a', '\x8b', '\x8c', '\x8d', '\x8e', '\x8f', '\x90', '\x91', '\x92', '\x93', '\x94', '\x95', '\x96', '\x97', '\x98', '\x99', '\x9a', '\x9b', '\x9c', '\x9d', '\x9e', '\x9f'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_49(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "terminal_\xf0" with index 50
inline fn parse_terminal__x92xf0(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        240 => { // '\xf0'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_50(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_utf8_continuation_90_bf" with index 51
inline fn parse_generative_terminal_utf8_continuation_90_bf(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191 => { // '\x90', '\x91', '\x92', '\x93', '\x94', '\x95', '\x96', '\x97', '\x98', '\x99', '\x9a', '\x9b', '\x9c', '\x9d', '\x9e', '\x9f', '\xa0', '\xa1', '\xa2', '\xa3', '\xa4', '\xa5', '\xa6', '\xa7', '\xa8', '\xa9', '\xaa', '\xab', '\xac', '\xad', '\xae', '\xaf', '\xb0', '\xb1', '\xb2', '\xb3', '\xb4', '\xb5', '\xb6', '\xb7', '\xb8', '\xb9', '\xba', '\xbb', '\xbc', '\xbd', '\xbe', '\xbf'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_51(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_utf8_lead_four_general" with index 52
inline fn parse_generative_terminal_utf8_lead_four_general(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        241, 242, 243 => { // '\xf1', '\xf2', '\xf3'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_52(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "terminal_\xf4" with index 53
inline fn parse_terminal__x92xf4(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        244 => { // '\xf4'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_53(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_utf8_continuation_80_8f" with index 54
inline fn parse_generative_terminal_utf8_continuation_80_8f(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143 => { // '\x80', '\x81', '\x82', '\x83', '\x84', '\x85', '\x86', '\x87', '\x88', '\x89', '\x8a', '\x8b', '\x8c', '\x8d', '\x8e', '\x8f'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_54(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "ControlCharacter" with index 55
fn parse_ControlCharacter(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 30);

    switch (context.head(u8, 0)) {
        1 => { // '\x01'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: ControlCharacter -> '\\x01'\n", .{});
                }
            }
            parse_terminal__x92x01(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_10(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[10],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[10]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[30], &args);
            if (comptime symbol_procedures[55]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            parse_terminal__x92x03(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_9(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[9],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[9]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[30], &args);
            if (comptime symbol_procedures[55]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            parse_terminal__x92x04(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_11(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[11],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[11]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[30], &args);
            if (comptime symbol_procedures[55]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: ControlCharacter <~ '\\x04'\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_55(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_\x01" with index 56
inline fn parse_terminal__x92x01(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        1 => { // '\x01'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_56(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "terminal_\x04" with index 57
inline fn parse_terminal__x92x04(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        4 => { // '\x04'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_57(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_character^"\n"" with index 58
inline fn parse_generative_terminal_character_x94_x34_x92n_x34(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        9, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_58(context, occurrence_recovery);
        },
    }
}

// Self-Repeating Parser for Symbol "AnyContentTail" at index 1 of its right hand side
// Right hand side: -> ControlCharacter, AnyContentTail
fn parse_AnyContentTail_1_1(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            1, 3, 4 => { // '\x01', '\x03', '\x04'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: AnyContentTail -> ControlCharacter, AnyContentTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 31);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                {
                    const child_node = parse_ControlCharacter(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_3(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    };
                    if (child_node != data_structures.Node.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                    }
                }
            },
            else => break,
        }
    }
    const exit_node = parse_AnyContentTail(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_3(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: AnyContentTail <~ ControlCharacter, AnyContentTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[3],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[3]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[31], &args);
        if (comptime symbol_procedures[59]) |procedure_pointer| {
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
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "AnyContentTail" at index 1 of its right hand side
// Right hand side: -> 'character^\"\\n\"', AnyContentTail
fn parse_AnyContentTail_0_1(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            9, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: AnyContentTail -> 'character^\"\\n\"', AnyContentTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 31);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_character_x94_x34_x92n_x34(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_4(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
            },
            else => break,
        }
    }
    const exit_node = parse_AnyContentTail(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_4(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: AnyContentTail <~ 'character^\"\\n\"', AnyContentTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[4],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[4]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[31], &args);
        if (comptime symbol_procedures[59]) |procedure_pointer| {
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
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Parser for Symbol "AnyContentTail" with index 59
fn parse_AnyContentTail(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 31);

    switch (context.head(u8, 0)) {
        1, 3, 4 => { // '\x01', '\x03', '\x04'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: AnyContentTail -> ControlCharacter, AnyContentTail\n", .{});
                }
            }
            {
                const child_node = parse_ControlCharacter(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_3(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_AnyContentTail_1_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_3(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[3],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[3]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[31], &args);
            if (comptime symbol_procedures[59]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            parse_generative_terminal_character_x94_x34_x92n_x34(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_4(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_AnyContentTail_0_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_4(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[4],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[4]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[31], &args);
            if (comptime symbol_procedures[59]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[2],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[2]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[31], &args);
            if (comptime symbol_procedures[59]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: AnyContentTail <~ \n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_59(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "IdTail" at index 1 of its right hand side
// Right hand side: -> '_', IdTail
fn parse_IdTail_2_1(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            95 => { // '_'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: IdTail -> '_', IdTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 32);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_terminal__(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_17(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
            },
            else => break,
        }
    }
    const exit_node = parse_IdTail(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_17(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: IdTail <~ '_', IdTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[17],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[17]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[32], &args);
        if (comptime symbol_procedures[60]) |procedure_pointer| {
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
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "IdTail" at index 1 of its right hand side
// Right hand side: -> 'letter', IdTail
fn parse_IdTail_0_1(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: IdTail -> 'letter', IdTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 32);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_letter(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_18(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
            },
            else => break,
        }
    }
    const exit_node = parse_IdTail(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_18(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: IdTail <~ 'letter', IdTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[18],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[18]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[32], &args);
        if (comptime symbol_procedures[60]) |procedure_pointer| {
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
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "IdTail" at index 1 of its right hand side
// Right hand side: -> 'digit', IdTail
fn parse_IdTail_1_1(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            48, 49, 50, 51, 52, 53, 54, 55, 56, 57 => { // '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: IdTail -> 'digit', IdTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 32);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_digit(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_19(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
            },
            else => break,
        }
    }
    const exit_node = parse_IdTail(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_19(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: IdTail <~ 'digit', IdTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[19],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[19]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[32], &args);
        if (comptime symbol_procedures[60]) |procedure_pointer| {
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
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Parser for Symbol "IdTail" with index 60
fn parse_IdTail(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 32);

    switch (context.head(u8, 0)) {
        10, 32, 33, 64, 94 => { // '\n', ' ', '!', '@', '^'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: IdTail -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[16],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[16]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[32], &args);
            if (comptime symbol_procedures[60]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            parse_generative_terminal_digit(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_19(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_IdTail_1_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_19(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[19],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[19]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[32], &args);
            if (comptime symbol_procedures[60]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            parse_generative_terminal_letter(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_18(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_IdTail_0_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_18(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[18],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[18]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[32], &args);
            if (comptime symbol_procedures[60]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            parse_terminal__(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_17(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_IdTail_2_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_17(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[17],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[17]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[32], &args);
            if (comptime symbol_procedures[60]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: IdTail <~ '_', IdTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_60(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "generative_terminal_letter" with index 61
inline fn parse_generative_terminal_letter(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_61(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_digit" with index 62
inline fn parse_generative_terminal_digit(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        48, 49, 50, 51, 52, 53, 54, 55, 56, 57 => { // '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_62(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_lowercase_letter" with index 63
inline fn parse_generative_terminal_lowercase_letter(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_63(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_uppercase_letter" with index 64
inline fn parse_generative_terminal_uppercase_letter(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_64(context, occurrence_recovery);
        },
    }
}

// Self-Repeating Parser for Symbol "CamelCaseIdTail" at index 1 of its right hand side
// Right hand side: -> 'letter', CamelCaseIdTail
fn parse_CamelCaseIdTail_0_1(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: CamelCaseIdTail -> 'letter', CamelCaseIdTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 33);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_letter(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_7(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
            },
            else => break,
        }
    }
    const exit_node = parse_CamelCaseIdTail(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_7(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: CamelCaseIdTail <~ 'letter', CamelCaseIdTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[7],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[7]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[33], &args);
        if (comptime symbol_procedures[65]) |procedure_pointer| {
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
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "CamelCaseIdTail" at index 1 of its right hand side
// Right hand side: -> 'digit', CamelCaseIdTail
fn parse_CamelCaseIdTail_1_1(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = data_structures.Node.invalid_pointer;
    node_address = node_address; // dummy store so Zig always sees this local as mutated (0-repetition paths return the initial value)
    _ = &node_address;
    var repeating_node_address = node_address;
    repeating_node_address = repeating_node_address; // dummy store for 0-repetition paths

    while (true) {
        switch (context.head(u8, 0)) {
            48, 49, 50, 51, 52, 53, 54, 55, 56, 57 => { // '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: CamelCaseIdTail -> 'digit', CamelCaseIdTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.pos(), 33);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_digit(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_8(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
            },
            else => break,
        }
    }
    const exit_node = parse_CamelCaseIdTail(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_8(context, occurrence_recovery)) {
                return data_structures.Node.invalid_pointer;
            }
            return err;
        },
        else => return err,
    };
    if (exit_node != data_structures.Node.invalid_pointer) {
        if (node_address == data_structures.Node.invalid_pointer) {
            node_address = exit_node;
        } else {
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: CamelCaseIdTail <~ 'digit', CamelCaseIdTail\n", .{});
            }
        }

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[8],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[8]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[33], &args);
        if (comptime symbol_procedures[65]) |procedure_pointer| {
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
                    string_utilities.fmtNode(args.node_address, context),
                });
            }
        }

        if (args.node_address) |effective| {
            if (node_address == repeating_node_address) {
                node_address = effective;
            }
        } else {
            data_structures.Node.unlinkWrapper(repeating_node_address, context.node_allocator);
            if (node_address == repeating_node_address) {
                node_address = data_structures.Node.invalid_pointer;
            }
        }
        repeating_node_address = context.node_allocator.at(repeating_node_address).parent;
    }
    return node_address;
}

// Parser for Symbol "CamelCaseIdTail" with index 65
fn parse_CamelCaseIdTail(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.pos(), 33);

    switch (context.head(u8, 0)) {
        10, 32, 64 => { // '\n', ' ', '@'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: CamelCaseIdTail -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[6],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[6]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[33], &args);
            if (comptime symbol_procedures[65]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            parse_generative_terminal_digit(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_8(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_CamelCaseIdTail_1_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_8(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[8],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[8]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[33], &args);
            if (comptime symbol_procedures[65]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

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
            parse_generative_terminal_letter(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_7(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_CamelCaseIdTail_0_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_7(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                };
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.pos() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[7],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[7]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[33], &args);
            if (comptime symbol_procedures[65]) |procedure_pointer| {
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: CamelCaseIdTail <~ 'letter', CamelCaseIdTail\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_65(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "_AugmentedStart" with index 66
fn parse__AugmentedStart(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope, root_reduction: *RootReduction) anyerror!void {
    root_reduction.* = .{};
    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _AugmentedStart -> Start, '\\x00'\n", .{});
                }
            }
            var root_node: data_structures.Node.Pointer = data_structures.Node.invalid_pointer;
            root_node = parse_Start(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_60(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_special_EOF(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_60(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            if (root_node != data_structures.Node.invalid_pointer) {
                root_reduction.ast_root = root_node;
                root_reduction.semantic_root = context.node_allocator.at(root_node).payload;
            }
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _AugmentedStart <~ Start, '\\x00'\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_66(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "special_EOF" with index 67
inline fn parse_special_EOF(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        0 => { // '\x00'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_67(context, occurrence_recovery);
        },
    }
}


// AST-Suppressed Parser for Symbol "_Utf8Scalar" with index 38
fn parse__Utf8Scalar_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8Scalar -> _Utf8TwoByte\n", .{});
                }
            }
            parse__Utf8TwoByte_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_64(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8Scalar <~ _Utf8TwoByte\n", .{});
                }
            }
        },
        224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239 => { // '\xe0', '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xed', '\xee', '\xef'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8Scalar -> _Utf8ThreeByte\n", .{});
                }
            }
            parse__Utf8ThreeByte_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_65(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8Scalar <~ _Utf8ThreeByte\n", .{});
                }
            }
        },
        240, 241, 242, 243, 244 => { // '\xf0', '\xf1', '\xf2', '\xf3', '\xf4'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8Scalar -> _Utf8FourByte\n", .{});
                }
            }
            parse__Utf8FourByte_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_66(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8Scalar <~ _Utf8FourByte\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_68(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "_Utf8TwoByte" with index 40
fn parse__Utf8TwoByte_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8TwoByte -> 'utf8_lead_two', 'utf8_continuation'\n", .{});
                }
            }
            parse_generative_terminal_utf8_lead_two_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_70(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_70(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8TwoByte <~ 'utf8_lead_two', 'utf8_continuation'\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_69(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "_Utf8ThreeByte" with index 41
fn parse__Utf8ThreeByte_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        224 => { // '\xe0'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8ThreeByte -> '\\xe0', 'utf8_continuation_a0_bf', 'utf8_continuation'\n", .{});
                }
            }
            parse_terminal__x92xe0_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_67(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_a0_bf_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_67(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_67(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8ThreeByte <~ '\\xe0', 'utf8_continuation_a0_bf', 'utf8_continuation'\n", .{});
                }
            }
        },
        225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 238, 239 => { // '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xee', '\xef'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8ThreeByte -> 'utf8_lead_three_general', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
            parse_generative_terminal_utf8_lead_three_general_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_68(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_68(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_68(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8ThreeByte <~ 'utf8_lead_three_general', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
        },
        237 => { // '\xed'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8ThreeByte -> '\\xed', 'utf8_continuation_80_9f', 'utf8_continuation'\n", .{});
                }
            }
            parse_terminal__x92xed_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_69(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_80_9f_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_69(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_69(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8ThreeByte <~ '\\xed', 'utf8_continuation_80_9f', 'utf8_continuation'\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_70(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "_Utf8FourByte" with index 42
fn parse__Utf8FourByte_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        240 => { // '\xf0'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8FourByte -> '\\xf0', 'utf8_continuation_90_bf', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
            parse_terminal__x92xf0_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_61(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_90_bf_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_61(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_61(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_61(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 3
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8FourByte <~ '\\xf0', 'utf8_continuation_90_bf', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
        },
        241, 242, 243 => { // '\xf1', '\xf2', '\xf3'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8FourByte -> 'utf8_lead_four_general', 'utf8_continuation', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
            parse_generative_terminal_utf8_lead_four_general_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_62(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_62(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_62(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_62(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 3
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8FourByte <~ 'utf8_lead_four_general', 'utf8_continuation', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
        },
        244 => { // '\xf4'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8FourByte -> '\\xf4', 'utf8_continuation_80_8f', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
            parse_terminal__x92xf4_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_63(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_80_8f_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_63(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_63(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_63(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 3
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: _Utf8FourByte <~ '\\xf4', 'utf8_continuation_80_8f', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_71(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "generative_terminal_utf8_lead_two" with index 43
inline fn parse_generative_terminal_utf8_lead_two_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_72(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "generative_terminal_utf8_continuation" with index 44
inline fn parse_generative_terminal_utf8_continuation_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191 => { // '\x80', '\x81', '\x82', '\x83', '\x84', '\x85', '\x86', '\x87', '\x88', '\x89', '\x8a', '\x8b', '\x8c', '\x8d', '\x8e', '\x8f', '\x90', '\x91', '\x92', '\x93', '\x94', '\x95', '\x96', '\x97', '\x98', '\x99', '\x9a', '\x9b', '\x9c', '\x9d', '\x9e', '\x9f', '\xa0', '\xa1', '\xa2', '\xa3', '\xa4', '\xa5', '\xa6', '\xa7', '\xa8', '\xa9', '\xaa', '\xab', '\xac', '\xad', '\xae', '\xaf', '\xb0', '\xb1', '\xb2', '\xb3', '\xb4', '\xb5', '\xb6', '\xb7', '\xb8', '\xb9', '\xba', '\xbb', '\xbc', '\xbd', '\xbe', '\xbf'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_73(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "terminal_\xe0" with index 45
inline fn parse_terminal__x92xe0_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        224 => { // '\xe0'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_74(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "generative_terminal_utf8_continuation_a0_bf" with index 46
inline fn parse_generative_terminal_utf8_continuation_a0_bf_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191 => { // '\xa0', '\xa1', '\xa2', '\xa3', '\xa4', '\xa5', '\xa6', '\xa7', '\xa8', '\xa9', '\xaa', '\xab', '\xac', '\xad', '\xae', '\xaf', '\xb0', '\xb1', '\xb2', '\xb3', '\xb4', '\xb5', '\xb6', '\xb7', '\xb8', '\xb9', '\xba', '\xbb', '\xbc', '\xbd', '\xbe', '\xbf'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_75(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "generative_terminal_utf8_lead_three_general" with index 47
inline fn parse_generative_terminal_utf8_lead_three_general_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 238, 239 => { // '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xee', '\xef'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_76(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "terminal_\xed" with index 48
inline fn parse_terminal__x92xed_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        237 => { // '\xed'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_77(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "generative_terminal_utf8_continuation_80_9f" with index 49
inline fn parse_generative_terminal_utf8_continuation_80_9f_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159 => { // '\x80', '\x81', '\x82', '\x83', '\x84', '\x85', '\x86', '\x87', '\x88', '\x89', '\x8a', '\x8b', '\x8c', '\x8d', '\x8e', '\x8f', '\x90', '\x91', '\x92', '\x93', '\x94', '\x95', '\x96', '\x97', '\x98', '\x99', '\x9a', '\x9b', '\x9c', '\x9d', '\x9e', '\x9f'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_78(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "terminal_\xf0" with index 50
inline fn parse_terminal__x92xf0_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        240 => { // '\xf0'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_79(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "generative_terminal_utf8_continuation_90_bf" with index 51
inline fn parse_generative_terminal_utf8_continuation_90_bf_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191 => { // '\x90', '\x91', '\x92', '\x93', '\x94', '\x95', '\x96', '\x97', '\x98', '\x99', '\x9a', '\x9b', '\x9c', '\x9d', '\x9e', '\x9f', '\xa0', '\xa1', '\xa2', '\xa3', '\xa4', '\xa5', '\xa6', '\xa7', '\xa8', '\xa9', '\xaa', '\xab', '\xac', '\xad', '\xae', '\xaf', '\xb0', '\xb1', '\xb2', '\xb3', '\xb4', '\xb5', '\xb6', '\xb7', '\xb8', '\xb9', '\xba', '\xbb', '\xbc', '\xbd', '\xbe', '\xbf'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_80(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "generative_terminal_utf8_lead_four_general" with index 52
inline fn parse_generative_terminal_utf8_lead_four_general_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        241, 242, 243 => { // '\xf1', '\xf2', '\xf3'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_81(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "terminal_\xf4" with index 53
inline fn parse_terminal__x92xf4_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        244 => { // '\xf4'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_82(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "generative_terminal_utf8_continuation_80_8f" with index 54
inline fn parse_generative_terminal_utf8_continuation_80_8f_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143 => { // '\x80', '\x81', '\x82', '\x83', '\x84', '\x85', '\x86', '\x87', '\x88', '\x89', '\x8a', '\x8b', '\x8c', '\x8d', '\x8e', '\x8f'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_83(context, occurrence_recovery);
        },
    }
}


fn ll_syntax_error_0(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "Start" }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
    context.setPendingSyntaxErrorSite(0);
    if (try llTryRecoverySelection_0(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_1(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "Rules" }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
    context.setPendingSyntaxErrorSite(1);
    if (try llTryRecoverySelection_1(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_2(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "Rule" }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
    context.setPendingSyntaxErrorSite(2);
    if (try llTryRecoverySelection_2(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_3(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "RulesTail" }, &[_][]const u8{"\x00", "\n"});
    context.setPendingSyntaxErrorSite(3);
    if (try llTryRecoverySelection_3(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_4(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "NewLines" }, &[_][]const u8{"\n"});
    context.setPendingSyntaxErrorSite(4);
    if (try llTryRecoverySelection_4(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_5(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "new_line" }, &[_][]const u8{"\n"});
    context.setPendingSyntaxErrorSite(5);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_6(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "NewLinesTail" }, &[_][]const u8{"\n", "#", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
    context.setPendingSyntaxErrorSite(6);
    if (try llTryRecoverySelection_6(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_7(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "#" }, &[_][]const u8{"#"});
    context.setPendingSyntaxErrorSite(7);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_8(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "AnyContent" }, &[_][]const u8{"\x01", "\x03", "\x04", "\t", "\x0b", "\x0c", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
    context.setPendingSyntaxErrorSite(8);
    if (try llTryRecoverySelection_8(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_9(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "VariableSymbol" }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
    context.setPendingSyntaxErrorSite(9);
    if (try llTryRecoverySelection_9(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_10(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "RecoveryTail" }, &[_][]const u8{"\n", " ", "!", "@"});
    context.setPendingSyntaxErrorSite(10);
    if (try llTryRecoverySelection_10(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_11(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "ProcedureTail" }, &[_][]const u8{"\n", " ", "@"});
    context.setPendingSyntaxErrorSite(11);
    if (try llTryRecoverySelection_11(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_12(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "RightHandSides" }, &[_][]const u8{"#", "|"});
    context.setPendingSyntaxErrorSite(12);
    if (try llTryRecoverySelection_12(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_13(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "RightHandSideLine" }, &[_][]const u8{"#", "|"});
    context.setPendingSyntaxErrorSite(13);
    if (try llTryRecoverySelection_13(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_14(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "RightHandSidesTail" }, &[_][]const u8{"\x00", "\n", "#", "|"});
    context.setPendingSyntaxErrorSite(14);
    if (try llTryRecoverySelection_14(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_15(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "|" }, &[_][]const u8{"|"});
    context.setPendingSyntaxErrorSite(15);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_16(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "RightHandSide" }, &[_][]const u8{"\n", " "});
    context.setPendingSyntaxErrorSite(16);
    if (try llTryRecoverySelection_16(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_17(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "space" }, &[_][]const u8{" "});
    context.setPendingSyntaxErrorSite(17);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_18(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "Symbol" }, &[_][]const u8{"\"", "'", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(18);
    if (try llTryRecoverySelection_18(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_19(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "RightHandSideTail" }, &[_][]const u8{"\n", " "});
    context.setPendingSyntaxErrorSite(19);
    if (try llTryRecoverySelection_19(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_20(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "TerminalSymbol" }, &[_][]const u8{"\"", "'"});
    context.setPendingSyntaxErrorSite(20);
    if (try llTryRecoverySelection_20(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_21(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "GenerativeTerminalSymbol" }, &[_][]const u8{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(21);
    if (try llTryRecoverySelection_21(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_22(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "UppercaseId" }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"});
    context.setPendingSyntaxErrorSite(22);
    if (try llTryRecoverySelection_22(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_23(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "_" }, &[_][]const u8{"_"});
    context.setPendingSyntaxErrorSite(23);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_24(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "'" }, &[_][]const u8{"'"});
    context.setPendingSyntaxErrorSite(24);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_25(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "StringContent" }, &[_][]const u8{"\x03", "\t", "\n", "\x0b", "\x0c", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~", "\xc2", "\xc3", "\xc4", "\xc5", "\xc6", "\xc7", "\xc8", "\xc9", "\xca", "\xcb", "\xcc", "\xcd", "\xce", "\xcf", "\xd0", "\xd1", "\xd2", "\xd3", "\xd4", "\xd5", "\xd6", "\xd7", "\xd8", "\xd9", "\xda", "\xdb", "\xdc", "\xdd", "\xde", "\xdf", "\xe0", "\xe1", "\xe2", "\xe3", "\xe4", "\xe5", "\xe6", "\xe7", "\xe8", "\xe9", "\xea", "\xeb", "\xec", "\xed", "\xee", "\xef", "\xf0", "\xf1", "\xf2", "\xf3", "\xf4"});
    context.setPendingSyntaxErrorSite(25);
    if (try llTryRecoverySelection_25(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_26(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "\x03" }, &[_][]const u8{"\x03"});
    context.setPendingSyntaxErrorSite(26);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_27(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "\"" }, &[_][]const u8{"\""});
    context.setPendingSyntaxErrorSite(27);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_28(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "SimpleStringContent" }, &[_][]const u8{"\t", "\n", "\x0b", "\x0c", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~", "\xc2", "\xc3", "\xc4", "\xc5", "\xc6", "\xc7", "\xc8", "\xc9", "\xca", "\xcb", "\xcc", "\xcd", "\xce", "\xcf", "\xd0", "\xd1", "\xd2", "\xd3", "\xd4", "\xd5", "\xd6", "\xd7", "\xd8", "\xd9", "\xda", "\xdb", "\xdc", "\xdd", "\xde", "\xdf", "\xe0", "\xe1", "\xe2", "\xe3", "\xe4", "\xe5", "\xe6", "\xe7", "\xe8", "\xe9", "\xea", "\xeb", "\xec", "\xed", "\xee", "\xef", "\xf0", "\xf1", "\xf2", "\xf3", "\xf4"});
    context.setPendingSyntaxErrorSite(28);
    if (try llTryRecoverySelection_28(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_29(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "LowercaseId" }, &[_][]const u8{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(29);
    if (try llTryRecoverySelection_29(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_30(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "GenerativeTerminalExceptions" }, &[_][]const u8{"\n", " ", "!", "@", "^"});
    context.setPendingSyntaxErrorSite(30);
    if (try llTryRecoverySelection_30(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_31(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "^" }, &[_][]const u8{"^"});
    context.setPendingSyntaxErrorSite(31);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_32(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "@" }, &[_][]const u8{"@"});
    context.setPendingSyntaxErrorSite(32);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_33(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "CamelCaseId" }, &[_][]const u8{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(33);
    if (try llTryRecoverySelection_33(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_34(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "RecoveryPoint" }, &[_][]const u8{"!"});
    context.setPendingSyntaxErrorSite(34);
    if (try llTryRecoverySelection_34(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_35(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "!" }, &[_][]const u8{"!"});
    context.setPendingSyntaxErrorSite(35);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_36(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "RecoveryPointBody" }, &[_][]const u8{"\"", "'", "^"});
    context.setPendingSyntaxErrorSite(36);
    if (try llTryRecoverySelection_36(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_37(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "character" }, &[_][]const u8{"\t", "\n", "\x0b", "\x0c", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
    context.setPendingSyntaxErrorSite(37);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_38(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "_Utf8Scalar" }, &[_][]const u8{"\xc2", "\xc3", "\xc4", "\xc5", "\xc6", "\xc7", "\xc8", "\xc9", "\xca", "\xcb", "\xcc", "\xcd", "\xce", "\xcf", "\xd0", "\xd1", "\xd2", "\xd3", "\xd4", "\xd5", "\xd6", "\xd7", "\xd8", "\xd9", "\xda", "\xdb", "\xdc", "\xdd", "\xde", "\xdf", "\xe0", "\xe1", "\xe2", "\xe3", "\xe4", "\xe5", "\xe6", "\xe7", "\xe8", "\xe9", "\xea", "\xeb", "\xec", "\xed", "\xee", "\xef", "\xf0", "\xf1", "\xf2", "\xf3", "\xf4"});
    context.setPendingSyntaxErrorSite(38);
    if (try llTryRecoverySelection_38(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_39(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "character^'\"\x03" }, &[_][]const u8{"\t", "\n", "\x0b", "\x0c", "\r", " ", "!", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
    context.setPendingSyntaxErrorSite(39);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_40(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "_Utf8TwoByte" }, &[_][]const u8{"\xc2", "\xc3", "\xc4", "\xc5", "\xc6", "\xc7", "\xc8", "\xc9", "\xca", "\xcb", "\xcc", "\xcd", "\xce", "\xcf", "\xd0", "\xd1", "\xd2", "\xd3", "\xd4", "\xd5", "\xd6", "\xd7", "\xd8", "\xd9", "\xda", "\xdb", "\xdc", "\xdd", "\xde", "\xdf"});
    context.setPendingSyntaxErrorSite(40);
    if (try llTryRecoverySelection_40(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_41(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "_Utf8ThreeByte" }, &[_][]const u8{"\xe0", "\xe1", "\xe2", "\xe3", "\xe4", "\xe5", "\xe6", "\xe7", "\xe8", "\xe9", "\xea", "\xeb", "\xec", "\xed", "\xee", "\xef"});
    context.setPendingSyntaxErrorSite(41);
    if (try llTryRecoverySelection_41(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_42(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "_Utf8FourByte" }, &[_][]const u8{"\xf0", "\xf1", "\xf2", "\xf3", "\xf4"});
    context.setPendingSyntaxErrorSite(42);
    if (try llTryRecoverySelection_42(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_43(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "utf8_lead_two" }, &[_][]const u8{"\xc2", "\xc3", "\xc4", "\xc5", "\xc6", "\xc7", "\xc8", "\xc9", "\xca", "\xcb", "\xcc", "\xcd", "\xce", "\xcf", "\xd0", "\xd1", "\xd2", "\xd3", "\xd4", "\xd5", "\xd6", "\xd7", "\xd8", "\xd9", "\xda", "\xdb", "\xdc", "\xdd", "\xde", "\xdf"});
    context.setPendingSyntaxErrorSite(43);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_44(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "utf8_continuation" }, &[_][]const u8{"\x80", "\x81", "\x82", "\x83", "\x84", "\x85", "\x86", "\x87", "\x88", "\x89", "\x8a", "\x8b", "\x8c", "\x8d", "\x8e", "\x8f", "\x90", "\x91", "\x92", "\x93", "\x94", "\x95", "\x96", "\x97", "\x98", "\x99", "\x9a", "\x9b", "\x9c", "\x9d", "\x9e", "\x9f", "\xa0", "\xa1", "\xa2", "\xa3", "\xa4", "\xa5", "\xa6", "\xa7", "\xa8", "\xa9", "\xaa", "\xab", "\xac", "\xad", "\xae", "\xaf", "\xb0", "\xb1", "\xb2", "\xb3", "\xb4", "\xb5", "\xb6", "\xb7", "\xb8", "\xb9", "\xba", "\xbb", "\xbc", "\xbd", "\xbe", "\xbf"});
    context.setPendingSyntaxErrorSite(44);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_45(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "\xe0" }, &[_][]const u8{"\xe0"});
    context.setPendingSyntaxErrorSite(45);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_46(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "utf8_continuation_a0_bf" }, &[_][]const u8{"\xa0", "\xa1", "\xa2", "\xa3", "\xa4", "\xa5", "\xa6", "\xa7", "\xa8", "\xa9", "\xaa", "\xab", "\xac", "\xad", "\xae", "\xaf", "\xb0", "\xb1", "\xb2", "\xb3", "\xb4", "\xb5", "\xb6", "\xb7", "\xb8", "\xb9", "\xba", "\xbb", "\xbc", "\xbd", "\xbe", "\xbf"});
    context.setPendingSyntaxErrorSite(46);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_47(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "utf8_lead_three_general" }, &[_][]const u8{"\xe1", "\xe2", "\xe3", "\xe4", "\xe5", "\xe6", "\xe7", "\xe8", "\xe9", "\xea", "\xeb", "\xec", "\xee", "\xef"});
    context.setPendingSyntaxErrorSite(47);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_48(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "\xed" }, &[_][]const u8{"\xed"});
    context.setPendingSyntaxErrorSite(48);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_49(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "utf8_continuation_80_9f" }, &[_][]const u8{"\x80", "\x81", "\x82", "\x83", "\x84", "\x85", "\x86", "\x87", "\x88", "\x89", "\x8a", "\x8b", "\x8c", "\x8d", "\x8e", "\x8f", "\x90", "\x91", "\x92", "\x93", "\x94", "\x95", "\x96", "\x97", "\x98", "\x99", "\x9a", "\x9b", "\x9c", "\x9d", "\x9e", "\x9f"});
    context.setPendingSyntaxErrorSite(49);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_50(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "\xf0" }, &[_][]const u8{"\xf0"});
    context.setPendingSyntaxErrorSite(50);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_51(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "utf8_continuation_90_bf" }, &[_][]const u8{"\x90", "\x91", "\x92", "\x93", "\x94", "\x95", "\x96", "\x97", "\x98", "\x99", "\x9a", "\x9b", "\x9c", "\x9d", "\x9e", "\x9f", "\xa0", "\xa1", "\xa2", "\xa3", "\xa4", "\xa5", "\xa6", "\xa7", "\xa8", "\xa9", "\xaa", "\xab", "\xac", "\xad", "\xae", "\xaf", "\xb0", "\xb1", "\xb2", "\xb3", "\xb4", "\xb5", "\xb6", "\xb7", "\xb8", "\xb9", "\xba", "\xbb", "\xbc", "\xbd", "\xbe", "\xbf"});
    context.setPendingSyntaxErrorSite(51);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_52(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "utf8_lead_four_general" }, &[_][]const u8{"\xf1", "\xf2", "\xf3"});
    context.setPendingSyntaxErrorSite(52);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_53(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "\xf4" }, &[_][]const u8{"\xf4"});
    context.setPendingSyntaxErrorSite(53);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_54(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "utf8_continuation_80_8f" }, &[_][]const u8{"\x80", "\x81", "\x82", "\x83", "\x84", "\x85", "\x86", "\x87", "\x88", "\x89", "\x8a", "\x8b", "\x8c", "\x8d", "\x8e", "\x8f"});
    context.setPendingSyntaxErrorSite(54);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_55(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "ControlCharacter" }, &[_][]const u8{"\x01", "\x03", "\x04"});
    context.setPendingSyntaxErrorSite(55);
    if (try llTryRecoverySelection_55(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_56(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "\x01" }, &[_][]const u8{"\x01"});
    context.setPendingSyntaxErrorSite(56);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_57(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "\x04" }, &[_][]const u8{"\x04"});
    context.setPendingSyntaxErrorSite(57);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_58(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "character^\"\n\"" }, &[_][]const u8{"\t", "\x0b", "\x0c", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
    context.setPendingSyntaxErrorSite(58);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_59(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "AnyContentTail" }, &[_][]const u8{"\x01", "\x03", "\x04", "\t", "\n", "\x0b", "\x0c", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
    context.setPendingSyntaxErrorSite(59);
    if (try llTryRecoverySelection_59(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_60(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "IdTail" }, &[_][]const u8{"\n", " ", "!", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "^", "_", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(60);
    if (try llTryRecoverySelection_60(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_61(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "letter" }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(61);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_62(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "digit" }, &[_][]const u8{"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"});
    context.setPendingSyntaxErrorSite(62);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_63(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "lowercase_letter" }, &[_][]const u8{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(63);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_64(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "uppercase_letter" }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"});
    context.setPendingSyntaxErrorSite(64);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_65(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "CamelCaseIdTail" }, &[_][]const u8{"\n", " ", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(65);
    if (try llTryRecoverySelection_65(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_66(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "_AugmentedStart" }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
    context.setPendingSyntaxErrorSite(66);
    if (try llTryRecoverySelection_66(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_67(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "\x00" }, &[_][]const u8{"\x00"});
    context.setPendingSyntaxErrorSite(67);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_68(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "_Utf8Scalar" }, &[_][]const u8{"\xc2", "\xc3", "\xc4", "\xc5", "\xc6", "\xc7", "\xc8", "\xc9", "\xca", "\xcb", "\xcc", "\xcd", "\xce", "\xcf", "\xd0", "\xd1", "\xd2", "\xd3", "\xd4", "\xd5", "\xd6", "\xd7", "\xd8", "\xd9", "\xda", "\xdb", "\xdc", "\xdd", "\xde", "\xdf", "\xe0", "\xe1", "\xe2", "\xe3", "\xe4", "\xe5", "\xe6", "\xe7", "\xe8", "\xe9", "\xea", "\xeb", "\xec", "\xed", "\xee", "\xef", "\xf0", "\xf1", "\xf2", "\xf3", "\xf4"});
    context.setPendingSyntaxErrorSite(68);
    if (try llTryRecoverySelection_38(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_69(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "_Utf8TwoByte" }, &[_][]const u8{"\xc2", "\xc3", "\xc4", "\xc5", "\xc6", "\xc7", "\xc8", "\xc9", "\xca", "\xcb", "\xcc", "\xcd", "\xce", "\xcf", "\xd0", "\xd1", "\xd2", "\xd3", "\xd4", "\xd5", "\xd6", "\xd7", "\xd8", "\xd9", "\xda", "\xdb", "\xdc", "\xdd", "\xde", "\xdf"});
    context.setPendingSyntaxErrorSite(69);
    if (try llTryRecoverySelection_40(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_70(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "_Utf8ThreeByte" }, &[_][]const u8{"\xe0", "\xe1", "\xe2", "\xe3", "\xe4", "\xe5", "\xe6", "\xe7", "\xe8", "\xe9", "\xea", "\xeb", "\xec", "\xed", "\xee", "\xef"});
    context.setPendingSyntaxErrorSite(70);
    if (try llTryRecoverySelection_41(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_71(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "_Utf8FourByte" }, &[_][]const u8{"\xf0", "\xf1", "\xf2", "\xf3", "\xf4"});
    context.setPendingSyntaxErrorSite(71);
    if (try llTryRecoverySelection_42(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_72(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "utf8_lead_two" }, &[_][]const u8{"\xc2", "\xc3", "\xc4", "\xc5", "\xc6", "\xc7", "\xc8", "\xc9", "\xca", "\xcb", "\xcc", "\xcd", "\xce", "\xcf", "\xd0", "\xd1", "\xd2", "\xd3", "\xd4", "\xd5", "\xd6", "\xd7", "\xd8", "\xd9", "\xda", "\xdb", "\xdc", "\xdd", "\xde", "\xdf"});
    context.setPendingSyntaxErrorSite(72);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_73(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "utf8_continuation" }, &[_][]const u8{"\x80", "\x81", "\x82", "\x83", "\x84", "\x85", "\x86", "\x87", "\x88", "\x89", "\x8a", "\x8b", "\x8c", "\x8d", "\x8e", "\x8f", "\x90", "\x91", "\x92", "\x93", "\x94", "\x95", "\x96", "\x97", "\x98", "\x99", "\x9a", "\x9b", "\x9c", "\x9d", "\x9e", "\x9f", "\xa0", "\xa1", "\xa2", "\xa3", "\xa4", "\xa5", "\xa6", "\xa7", "\xa8", "\xa9", "\xaa", "\xab", "\xac", "\xad", "\xae", "\xaf", "\xb0", "\xb1", "\xb2", "\xb3", "\xb4", "\xb5", "\xb6", "\xb7", "\xb8", "\xb9", "\xba", "\xbb", "\xbc", "\xbd", "\xbe", "\xbf"});
    context.setPendingSyntaxErrorSite(73);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_74(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "\xe0" }, &[_][]const u8{"\xe0"});
    context.setPendingSyntaxErrorSite(74);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_75(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "utf8_continuation_a0_bf" }, &[_][]const u8{"\xa0", "\xa1", "\xa2", "\xa3", "\xa4", "\xa5", "\xa6", "\xa7", "\xa8", "\xa9", "\xaa", "\xab", "\xac", "\xad", "\xae", "\xaf", "\xb0", "\xb1", "\xb2", "\xb3", "\xb4", "\xb5", "\xb6", "\xb7", "\xb8", "\xb9", "\xba", "\xbb", "\xbc", "\xbd", "\xbe", "\xbf"});
    context.setPendingSyntaxErrorSite(75);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_76(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "utf8_lead_three_general" }, &[_][]const u8{"\xe1", "\xe2", "\xe3", "\xe4", "\xe5", "\xe6", "\xe7", "\xe8", "\xe9", "\xea", "\xeb", "\xec", "\xee", "\xef"});
    context.setPendingSyntaxErrorSite(76);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_77(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "\xed" }, &[_][]const u8{"\xed"});
    context.setPendingSyntaxErrorSite(77);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_78(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "utf8_continuation_80_9f" }, &[_][]const u8{"\x80", "\x81", "\x82", "\x83", "\x84", "\x85", "\x86", "\x87", "\x88", "\x89", "\x8a", "\x8b", "\x8c", "\x8d", "\x8e", "\x8f", "\x90", "\x91", "\x92", "\x93", "\x94", "\x95", "\x96", "\x97", "\x98", "\x99", "\x9a", "\x9b", "\x9c", "\x9d", "\x9e", "\x9f"});
    context.setPendingSyntaxErrorSite(78);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_79(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "\xf0" }, &[_][]const u8{"\xf0"});
    context.setPendingSyntaxErrorSite(79);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_80(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "utf8_continuation_90_bf" }, &[_][]const u8{"\x90", "\x91", "\x92", "\x93", "\x94", "\x95", "\x96", "\x97", "\x98", "\x99", "\x9a", "\x9b", "\x9c", "\x9d", "\x9e", "\x9f", "\xa0", "\xa1", "\xa2", "\xa3", "\xa4", "\xa5", "\xa6", "\xa7", "\xa8", "\xa9", "\xaa", "\xab", "\xac", "\xad", "\xae", "\xaf", "\xb0", "\xb1", "\xb2", "\xb3", "\xb4", "\xb5", "\xb6", "\xb7", "\xb8", "\xb9", "\xba", "\xbb", "\xbc", "\xbd", "\xbe", "\xbf"});
    context.setPendingSyntaxErrorSite(80);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_81(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "utf8_lead_four_general" }, &[_][]const u8{"\xf1", "\xf2", "\xf3"});
    context.setPendingSyntaxErrorSite(81);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_82(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "\xf4" }, &[_][]const u8{"\xf4"});
    context.setPendingSyntaxErrorSite(82);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_83(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = "utf8_continuation_80_8f" }, &[_][]const u8{"\x80", "\x81", "\x82", "\x83", "\x84", "\x85", "\x86", "\x87", "\x88", "\x89", "\x8a", "\x8b", "\x8c", "\x8d", "\x8e", "\x8f"});
    context.setPendingSyntaxErrorSite(83);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}
fn llFlushSyntaxDiagnostic(context: *data_structures.Context) !void {
    const site = context.pendingSyntaxErrorSite() orelse return;
    context.clearPendingSyntaxErrorSite();
    switch (site) {
        0 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        1 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        2 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        3 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        4 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        5 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        6 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        7 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        8 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        9 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        10 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_RecoveryTail__expected_RecoveryPoint_or_end_of_RecoveryTail"))
                @field(error_messages, "syntax_error_ll_RecoveryTail__expected_RecoveryPoint_or_end_of_RecoveryTail")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_RecoveryTail"))
                @field(error_messages, "syntax_error_ll_RecoveryTail")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        11 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        12 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        13 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        14 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        15 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        16 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        17 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        18 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        19 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        20 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        21 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        22 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        23 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        24 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        25 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_StringContent__expected__Utf8Scalar_or_end_of_StringContent_or_generative_terminal_character"))
                @field(error_messages, "syntax_error_ll_StringContent__expected__Utf8Scalar_or_end_of_StringContent_or_generative_terminal_character")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        26 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        27 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        28 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_SimpleStringContent__expected__Utf8Scalar_or_end_of_SimpleStringContent_or_generative_terminal_character_x94_x39_x34_x92x03"))
                @field(error_messages, "syntax_error_ll_SimpleStringContent__expected__Utf8Scalar_or_end_of_SimpleStringContent_or_generative_terminal_character_x94_x39_x34_x92x03")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        29 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        30 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        31 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        32 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        33 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        34 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_RecoveryPoint__expected_terminal__x33"))
                @field(error_messages, "syntax_error_ll_RecoveryPoint__expected_terminal__x33")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_RecoveryPoint"))
                @field(error_messages, "syntax_error_ll_RecoveryPoint")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        35 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x33__expected_terminal__x33"))
                @field(error_messages, "syntax_error_ll_terminal__x33__expected_terminal__x33")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x33"))
                @field(error_messages, "syntax_error_ll_terminal__x33")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        36 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_RecoveryPointBody__expected_TerminalSymbol_or_terminal__x94"))
                @field(error_messages, "syntax_error_ll_RecoveryPointBody__expected_TerminalSymbol_or_terminal__x94")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_RecoveryPointBody"))
                @field(error_messages, "syntax_error_ll_RecoveryPointBody")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        37 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        38 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll__Utf8Scalar__expected__Utf8FourByte_or__Utf8ThreeByte_or__Utf8TwoByte"))
                @field(error_messages, "syntax_error_ll__Utf8Scalar__expected__Utf8FourByte_or__Utf8ThreeByte_or__Utf8TwoByte")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll__Utf8Scalar"))
                @field(error_messages, "syntax_error_ll__Utf8Scalar")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        39 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        40 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll__Utf8TwoByte__expected_generative_terminal_utf8_lead_two"))
                @field(error_messages, "syntax_error_ll__Utf8TwoByte__expected_generative_terminal_utf8_lead_two")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll__Utf8TwoByte"))
                @field(error_messages, "syntax_error_ll__Utf8TwoByte")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        41 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll__Utf8ThreeByte__expected_generative_terminal_utf8_lead_three_general_or_terminal__x92xe0_or_terminal__x92xed"))
                @field(error_messages, "syntax_error_ll__Utf8ThreeByte__expected_generative_terminal_utf8_lead_three_general_or_terminal__x92xe0_or_terminal__x92xed")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll__Utf8ThreeByte"))
                @field(error_messages, "syntax_error_ll__Utf8ThreeByte")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        42 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll__Utf8FourByte__expected_generative_terminal_utf8_lead_four_general_or_terminal__x92xf0_or_terminal__x92xf4"))
                @field(error_messages, "syntax_error_ll__Utf8FourByte__expected_generative_terminal_utf8_lead_four_general_or_terminal__x92xf0_or_terminal__x92xf4")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll__Utf8FourByte"))
                @field(error_messages, "syntax_error_ll__Utf8FourByte")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        43 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_two__expected_generative_terminal_utf8_lead_two"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_two__expected_generative_terminal_utf8_lead_two")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_two"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_two")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        44 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation__expected_generative_terminal_utf8_continuation"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation__expected_generative_terminal_utf8_continuation")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        45 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92xe0__expected_terminal__x92xe0"))
                @field(error_messages, "syntax_error_ll_terminal__x92xe0__expected_terminal__x92xe0")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92xe0"))
                @field(error_messages, "syntax_error_ll_terminal__x92xe0")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        46 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_a0_bf__expected_generative_terminal_utf8_continuation_a0_bf"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_a0_bf__expected_generative_terminal_utf8_continuation_a0_bf")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_a0_bf"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_a0_bf")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        47 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_three_general__expected_generative_terminal_utf8_lead_three_general"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_three_general__expected_generative_terminal_utf8_lead_three_general")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_three_general"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_three_general")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        48 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92xed__expected_terminal__x92xed"))
                @field(error_messages, "syntax_error_ll_terminal__x92xed__expected_terminal__x92xed")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92xed"))
                @field(error_messages, "syntax_error_ll_terminal__x92xed")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        49 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_80_9f__expected_generative_terminal_utf8_continuation_80_9f"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_80_9f__expected_generative_terminal_utf8_continuation_80_9f")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_80_9f"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_80_9f")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        50 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92xf0__expected_terminal__x92xf0"))
                @field(error_messages, "syntax_error_ll_terminal__x92xf0__expected_terminal__x92xf0")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92xf0"))
                @field(error_messages, "syntax_error_ll_terminal__x92xf0")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        51 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_90_bf__expected_generative_terminal_utf8_continuation_90_bf"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_90_bf__expected_generative_terminal_utf8_continuation_90_bf")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_90_bf"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_90_bf")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        52 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_four_general__expected_generative_terminal_utf8_lead_four_general"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_four_general__expected_generative_terminal_utf8_lead_four_general")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_four_general"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_four_general")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        53 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92xf4__expected_terminal__x92xf4"))
                @field(error_messages, "syntax_error_ll_terminal__x92xf4__expected_terminal__x92xf4")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92xf4"))
                @field(error_messages, "syntax_error_ll_terminal__x92xf4")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        54 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_80_8f__expected_generative_terminal_utf8_continuation_80_8f"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_80_8f__expected_generative_terminal_utf8_continuation_80_8f")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_80_8f"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_80_8f")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        55 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        56 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        57 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        58 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        59 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        60 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        61 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        62 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        63 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        64 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        65 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        66 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        67 => {
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        68 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll__Utf8Scalar__expected__Utf8FourByte_or__Utf8ThreeByte_or__Utf8TwoByte"))
                @field(error_messages, "syntax_error_ll__Utf8Scalar__expected__Utf8FourByte_or__Utf8ThreeByte_or__Utf8TwoByte")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll__Utf8Scalar"))
                @field(error_messages, "syntax_error_ll__Utf8Scalar")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        69 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll__Utf8TwoByte__expected_generative_terminal_utf8_lead_two"))
                @field(error_messages, "syntax_error_ll__Utf8TwoByte__expected_generative_terminal_utf8_lead_two")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll__Utf8TwoByte"))
                @field(error_messages, "syntax_error_ll__Utf8TwoByte")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        70 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll__Utf8ThreeByte__expected_generative_terminal_utf8_lead_three_general_or_terminal__x92xe0_or_terminal__x92xed"))
                @field(error_messages, "syntax_error_ll__Utf8ThreeByte__expected_generative_terminal_utf8_lead_three_general_or_terminal__x92xe0_or_terminal__x92xed")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll__Utf8ThreeByte"))
                @field(error_messages, "syntax_error_ll__Utf8ThreeByte")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        71 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll__Utf8FourByte__expected_generative_terminal_utf8_lead_four_general_or_terminal__x92xf0_or_terminal__x92xf4"))
                @field(error_messages, "syntax_error_ll__Utf8FourByte__expected_generative_terminal_utf8_lead_four_general_or_terminal__x92xf0_or_terminal__x92xf4")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll__Utf8FourByte"))
                @field(error_messages, "syntax_error_ll__Utf8FourByte")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        72 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_two__expected_generative_terminal_utf8_lead_two"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_two__expected_generative_terminal_utf8_lead_two")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_two"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_two")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        73 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation__expected_generative_terminal_utf8_continuation"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation__expected_generative_terminal_utf8_continuation")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        74 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92xe0__expected_terminal__x92xe0"))
                @field(error_messages, "syntax_error_ll_terminal__x92xe0__expected_terminal__x92xe0")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92xe0"))
                @field(error_messages, "syntax_error_ll_terminal__x92xe0")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        75 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_a0_bf__expected_generative_terminal_utf8_continuation_a0_bf"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_a0_bf__expected_generative_terminal_utf8_continuation_a0_bf")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_a0_bf"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_a0_bf")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        76 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_three_general__expected_generative_terminal_utf8_lead_three_general"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_three_general__expected_generative_terminal_utf8_lead_three_general")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_three_general"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_three_general")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        77 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92xed__expected_terminal__x92xed"))
                @field(error_messages, "syntax_error_ll_terminal__x92xed__expected_terminal__x92xed")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92xed"))
                @field(error_messages, "syntax_error_ll_terminal__x92xed")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        78 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_80_9f__expected_generative_terminal_utf8_continuation_80_9f"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_80_9f__expected_generative_terminal_utf8_continuation_80_9f")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_80_9f"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_80_9f")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        79 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92xf0__expected_terminal__x92xf0"))
                @field(error_messages, "syntax_error_ll_terminal__x92xf0__expected_terminal__x92xf0")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92xf0"))
                @field(error_messages, "syntax_error_ll_terminal__x92xf0")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        80 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_90_bf__expected_generative_terminal_utf8_continuation_90_bf"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_90_bf__expected_generative_terminal_utf8_continuation_90_bf")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_90_bf"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_90_bf")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        81 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_four_general__expected_generative_terminal_utf8_lead_four_general"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_four_general__expected_generative_terminal_utf8_lead_four_general")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_four_general"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_lead_four_general")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        82 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92xf4__expected_terminal__x92xf4"))
                @field(error_messages, "syntax_error_ll_terminal__x92xf4__expected_terminal__x92xf4")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92xf4"))
                @field(error_messages, "syntax_error_ll_terminal__x92xf4")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        83 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_80_8f__expected_generative_terminal_utf8_continuation_80_8f"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_80_8f__expected_generative_terminal_utf8_continuation_80_8f")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_80_8f"))
                @field(error_messages, "syntax_error_ll_generative_terminal_utf8_continuation_80_8f")(.{
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
            if (!builtin.is_test) std.debug.print("{s}", .{diagnostic_message});
        },
        else => unreachable,
    }
}

pub fn parseWithResult(context: *data_structures.Context) !root.ParseResult {
    var root_reduction: RootReduction = .{};
    _ = parse__AugmentedStart(context, null, &root_reduction) catch |err| switch (err) {
        root.ParseError.SyntaxError, error.ExplicitSyntaxRecovery => {
            try llFlushSyntaxDiagnostic(context);
            return root.ParseError.SyntaxError;
        },
        else => return err,
    };
    if (context.hasSyntaxErrors()) return root.ParseError.SyntaxError;

    if (context.verbosityLevel() > 0) {
        std.log.info("The input file was parsed successfully!", .{});
    }
    return .{
        .parsed_bytes = context.pos() - 1,
        .line = context.line,
        .column = context.column,
        .ast_root = root_reduction.ast_root,
        .semantic_root = root_reduction.semantic_root,
    };
}

pub fn parse(context: *data_structures.Context) !void {
    _ = try parseWithResult(context);
}
