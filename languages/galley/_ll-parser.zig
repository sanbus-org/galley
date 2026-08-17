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
pub const allow_no_ast_tree_procedures = false;
pub const is_error_recovery_enabled = true;
pub const error_recovery_mode: ErrorRecoveryMode = .explicit;
pub const is_position_tracking_enabled = builtin.mode != .ReleaseFast;
pub const is_input_streaming_enabled = false;
pub const syntax_error_stack_depth = root.syntax_error_stack_depth;
pub const is_syntax_error_stack_enabled = syntax_error_stack_depth > 1;
pub const uses_verbatim = true;
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
    "AnnotationTail", // 10
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
    "RawString", // 23
    "\"", // 24
    "SimpleStringContent", // 25
    "\\\"", // 26
    "RawIndicator", // 27
    "character^\"\\u{22}\"^\"\\n\"^\"\\u{5c}\"", // 28
    "LowercaseId", // 29
    "GenerativeTerminalExceptions", // 30
    "^", // 31
    "@", // 32
    "Annotation", // 33
    "Procedure", // 34
    "!", // 35
    "RecoveryPoint", // 36
    ">", // 37
    "VerbatimMarker", // 38
    "CamelCaseId", // 39
    "TerminalAndCursor", // 40
    "character^\"\\u{22}\"", // 41
    "_Utf8Scalar", // 42
    "_Utf8TwoByte", // 43
    "_Utf8ThreeByte", // 44
    "_Utf8FourByte", // 45
    "utf8_lead_two", // 46
    "utf8_continuation", // 47
    "\xe0", // 48
    "utf8_continuation_a0_bf", // 49
    "utf8_lead_three_general", // 50
    "\xed", // 51
    "utf8_continuation_80_9f", // 52
    "\xf0", // 53
    "utf8_continuation_90_bf", // 54
    "utf8_lead_four_general", // 55
    "\xf4", // 56
    "utf8_continuation_80_8f", // 57
    "ControlCharacter", // 58
    "\x01", // 59
    "\x02", // 60
    "character^\"\\n\"", // 61
    "AnyContentTail", // 62
    "IdTail", // 63
    "letter", // 64
    "digit", // 65
    "lowercase_letter", // 66
    "uppercase_letter", // 67
    "CamelCaseIdTail", // 68
    "_AugmentedStart", // 69
    "\x00", // 70
    "GenerativeTerminal", // 71
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
    false,
    true,
    false,
    true,
    false,
    true,
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
    false,
    false,
    true,
    false,
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
    true,
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
    "AnnotationTail",
    "RightHandSides",
    "RightHandSideLine",
    "RightHandSidesTail",
    "RightHandSide",
    "Symbol",
    "RightHandSideTail",
    "TerminalSymbol",
    "GenerativeTerminalSymbol",
    "UppercaseId",
    "RawString",
    "SimpleStringContent",
    "RawIndicator",
    "LowercaseId",
    "GenerativeTerminalExceptions",
    "Annotation",
    "Procedure",
    "RecoveryPoint",
    "VerbatimMarker",
    "CamelCaseId",
    "TerminalAndCursor",
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
    15,
    17,
    18,
    19,
    20,
    21,
    23,
    25,
    27,
    29,
    30,
    33,
    34,
    36,
    38,
    39,
    40,
    42,
    43,
    44,
    45,
    58,
    62,
    63,
    68,
    69,
    71,
};

pub const rules = &[_]data_structures.Rule{
    data_structures.Rule{ .header = 23, .right_hand_side = &[_]u16{34}, .right_hand_side_index = "0" }, // Annotation
    data_structures.Rule{ .header = 23, .right_hand_side = &[_]u16{ 35, 36 }, .right_hand_side_index = "1" }, // Annotation
    data_structures.Rule{ .header = 23, .right_hand_side = &[_]u16{ 37, 38 }, .right_hand_side_index = "2" }, // Annotation
    data_structures.Rule{ .header = 8, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // AnnotationTail
    data_structures.Rule{ .header = 8, .right_hand_side = &[_]u16{ 32, 33, 10 }, .right_hand_side_index = "0" }, // AnnotationTail
    data_structures.Rule{ .header = 6, .right_hand_side = &[_]u16{ 58, 62 }, .right_hand_side_index = "1" }, // AnyContent
    data_structures.Rule{ .header = 6, .right_hand_side = &[_]u16{ 61, 62 }, .right_hand_side_index = "0" }, // AnyContent
    data_structures.Rule{ .header = 34, .right_hand_side = &[_]u16{}, .right_hand_side_index = "2" }, // AnyContentTail
    data_structures.Rule{ .header = 34, .right_hand_side = &[_]u16{ 58, 62 }, .right_hand_side_index = "1" }, // AnyContentTail
    data_structures.Rule{ .header = 34, .right_hand_side = &[_]u16{ 61, 62 }, .right_hand_side_index = "0" }, // AnyContentTail
    data_structures.Rule{ .header = 27, .right_hand_side = &[_]u16{ 66, 68 }, .right_hand_side_index = "0" }, // CamelCaseId
    data_structures.Rule{ .header = 36, .right_hand_side = &[_]u16{}, .right_hand_side_index = "2" }, // CamelCaseIdTail
    data_structures.Rule{ .header = 36, .right_hand_side = &[_]u16{ 64, 68 }, .right_hand_side_index = "0" }, // CamelCaseIdTail
    data_structures.Rule{ .header = 36, .right_hand_side = &[_]u16{ 65, 68 }, .right_hand_side_index = "1" }, // CamelCaseIdTail
    data_structures.Rule{ .header = 33, .right_hand_side = &[_]u16{59}, .right_hand_side_index = "0" }, // ControlCharacter
    data_structures.Rule{ .header = 33, .right_hand_side = &[_]u16{60}, .right_hand_side_index = "1" }, // ControlCharacter
    data_structures.Rule{ .header = 38, .right_hand_side = &[_]u16{}, .right_hand_side_index = "0" }, // GenerativeTerminal
    data_structures.Rule{ .header = 22, .right_hand_side = &[_]u16{}, .right_hand_side_index = "1" }, // GenerativeTerminalExceptions
    data_structures.Rule{ .header = 22, .right_hand_side = &[_]u16{ 31, 19, 30 }, .right_hand_side_index = "0" }, // GenerativeTerminalExceptions
    data_structures.Rule{ .header = 16, .right_hand_side = &[_]u16{ 29, 30 }, .right_hand_side_index = "0" }, // GenerativeTerminalSymbol
    data_structures.Rule{ .header = 35, .right_hand_side = &[_]u16{}, .right_hand_side_index = "3" }, // IdTail
    data_structures.Rule{ .header = 35, .right_hand_side = &[_]u16{ 22, 63 }, .right_hand_side_index = "2" }, // IdTail
    data_structures.Rule{ .header = 35, .right_hand_side = &[_]u16{ 64, 63 }, .right_hand_side_index = "0" }, // IdTail
    data_structures.Rule{ .header = 35, .right_hand_side = &[_]u16{ 65, 63 }, .right_hand_side_index = "1" }, // IdTail
    data_structures.Rule{ .header = 21, .right_hand_side = &[_]u16{ 66, 63 }, .right_hand_side_index = "0" }, // LowercaseId
    data_structures.Rule{ .header = 4, .right_hand_side = &[_]u16{ 5, 6 }, .right_hand_side_index = "0" }, // NewLines
    data_structures.Rule{ .header = 5, .right_hand_side = &[_]u16{}, .right_hand_side_index = "2" }, // NewLinesTail
    data_structures.Rule{ .header = 5, .right_hand_side = &[_]u16{ 5, 6 }, .right_hand_side_index = "0" }, // NewLinesTail
    data_structures.Rule{ .header = 5, .right_hand_side = &[_]u16{ 7, 8, 5, 6 }, .right_hand_side_index = "1" }, // NewLinesTail
    data_structures.Rule{ .header = 24, .right_hand_side = &[_]u16{39}, .right_hand_side_index = "0" }, // Procedure
    data_structures.Rule{ .header = 20, .right_hand_side = &[_]u16{28}, .right_hand_side_index = "0" }, // RawIndicator
    data_structures.Rule{ .header = 18, .right_hand_side = &[_]u16{ 26, 27, 24 }, .right_hand_side_index = "0" }, // RawString
    data_structures.Rule{ .header = 25, .right_hand_side = &[_]u16{40}, .right_hand_side_index = "0" }, // RecoveryPoint
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
    data_structures.Rule{ .header = 19, .right_hand_side = &[_]u16{}, .right_hand_side_index = "2" }, // SimpleStringContent
    data_structures.Rule{ .header = 19, .right_hand_side = &[_]u16{ 41, 25 }, .right_hand_side_index = "0" }, // SimpleStringContent
    data_structures.Rule{ .header = 19, .right_hand_side = &[_]u16{ 42, 25 }, .right_hand_side_index = "1" }, // SimpleStringContent
    data_structures.Rule{ .header = 0, .right_hand_side = &[_]u16{1}, .right_hand_side_index = "0" }, // Start
    data_structures.Rule{ .header = 13, .right_hand_side = &[_]u16{9}, .right_hand_side_index = "0" }, // Symbol
    data_structures.Rule{ .header = 13, .right_hand_side = &[_]u16{19}, .right_hand_side_index = "1" }, // Symbol
    data_structures.Rule{ .header = 13, .right_hand_side = &[_]u16{20}, .right_hand_side_index = "2" }, // Symbol
    data_structures.Rule{ .header = 28, .right_hand_side = &[_]u16{ 19, 31 }, .right_hand_side_index = "1" }, // TerminalAndCursor
    data_structures.Rule{ .header = 28, .right_hand_side = &[_]u16{ 31, 19 }, .right_hand_side_index = "0" }, // TerminalAndCursor
    data_structures.Rule{ .header = 15, .right_hand_side = &[_]u16{23}, .right_hand_side_index = "0" }, // TerminalSymbol
    data_structures.Rule{ .header = 15, .right_hand_side = &[_]u16{ 24, 25, 24 }, .right_hand_side_index = "1" }, // TerminalSymbol
    data_structures.Rule{ .header = 17, .right_hand_side = &[_]u16{ 67, 63 }, .right_hand_side_index = "0" }, // UppercaseId
    data_structures.Rule{ .header = 7, .right_hand_side = &[_]u16{21}, .right_hand_side_index = "0" }, // VariableSymbol
    data_structures.Rule{ .header = 7, .right_hand_side = &[_]u16{ 22, 21 }, .right_hand_side_index = "1" }, // VariableSymbol
    data_structures.Rule{ .header = 26, .right_hand_side = &[_]u16{37}, .right_hand_side_index = "0" }, // VerbatimMarker
    data_structures.Rule{ .header = 26, .right_hand_side = &[_]u16{40}, .right_hand_side_index = "1" }, // VerbatimMarker
    data_structures.Rule{ .header = 37, .right_hand_side = &[_]u16{ 0, 70 }, .right_hand_side_index = "0" }, // _AugmentedStart
    data_structures.Rule{ .header = 32, .right_hand_side = &[_]u16{ 53, 54, 47, 47 }, .right_hand_side_index = "0" }, // _Utf8FourByte
    data_structures.Rule{ .header = 32, .right_hand_side = &[_]u16{ 55, 47, 47, 47 }, .right_hand_side_index = "1" }, // _Utf8FourByte
    data_structures.Rule{ .header = 32, .right_hand_side = &[_]u16{ 56, 57, 47, 47 }, .right_hand_side_index = "2" }, // _Utf8FourByte
    data_structures.Rule{ .header = 29, .right_hand_side = &[_]u16{43}, .right_hand_side_index = "0" }, // _Utf8Scalar
    data_structures.Rule{ .header = 29, .right_hand_side = &[_]u16{44}, .right_hand_side_index = "1" }, // _Utf8Scalar
    data_structures.Rule{ .header = 29, .right_hand_side = &[_]u16{45}, .right_hand_side_index = "2" }, // _Utf8Scalar
    data_structures.Rule{ .header = 31, .right_hand_side = &[_]u16{ 48, 49, 47 }, .right_hand_side_index = "0" }, // _Utf8ThreeByte
    data_structures.Rule{ .header = 31, .right_hand_side = &[_]u16{ 50, 47, 47 }, .right_hand_side_index = "1" }, // _Utf8ThreeByte
    data_structures.Rule{ .header = 31, .right_hand_side = &[_]u16{ 51, 52, 47 }, .right_hand_side_index = "2" }, // _Utf8ThreeByte
    data_structures.Rule{ .header = 30, .right_hand_side = &[_]u16{ 46, 47 }, .right_hand_side_index = "0" }, // _Utf8TwoByte
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
    if (try llTryExplicitScope(context, &ExplicitRecoveryScope{ .id = 12, .target = .{ .lhs_variable = "RightHandSideLine" }, .points = &[_]root.SyntaxRecoveryPoint{.{ .terminal = "\n", .@"resume" = .after }} })) return true;
    return false;
}

fn llTryRecoverySelection_13(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_15(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_17(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
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

fn llTryRecoverySelection_23(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_25(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_27(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
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

fn llTryRecoverySelection_39(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_40(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_42(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_43(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_44(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_45(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_58(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_62(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_63(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_68(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoverySelection_69(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
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

fn llTryRecoveryRule_12(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
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
    return false;
}

fn llTryRecoveryRule_35(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    if (try llTryExplicitScope(context, &ExplicitRecoveryScope{ .id = 12, .target = .{ .lhs_variable = "RightHandSideLine" }, .points = &[_]root.SyntaxRecoveryPoint{.{ .terminal = "\n", .@"resume" = .after }} })) return true;
    return false;
}

fn llTryRecoveryRule_36(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    if (try llTryExplicitScope(context, &ExplicitRecoveryScope{ .id = 12, .target = .{ .lhs_variable = "RightHandSideLine" }, .points = &[_]root.SyntaxRecoveryPoint{.{ .terminal = "\n", .@"resume" = .after }} })) return true;
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
    return false;
}

fn llTryRecoveryRule_42(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    if (try llTryExplicitScope(context, &ExplicitRecoveryScope{ .id = 2, .target = .{ .lhs_variable = "Rule" }, .points = &[_]root.SyntaxRecoveryPoint{.{ .terminal = "\n\n", .@"resume" = .before }} })) return true;
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

fn llTryRecoveryRule_71(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
    if (occurrence) |scope| if (try llTryExplicitScope(context, scope)) return true;
    return false;
}

fn llTryRecoveryRule_72(context: *data_structures.Context, occurrence: ?*const ExplicitRecoveryScope) !bool {
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
    var arr: [73]?*const data_structures.Procedure = .{null} ** 73;

    for (rules, 0..) |rule, index| {
        const procedure_name = "reduction_" ++ variables[rule.header] ++ "_" ++ rule.right_hand_side_index;
        if (@hasDecl(procedures, procedure_name)) {
            arr[index] = data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, procedure_name), procedure_name);
        }
    }

    break :rule_procedures arr;
};

pub const symbol_procedures = symbol_procedures: {
    var arr: [72]?*const data_structures.Procedure = .{null} ** 72;

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
    &[_][]const u8{},
    &[_][]const u8{},
    &[_][]const u8{},
};

pub const variable_procedures = variable_procedures: {
    var arr: [39]?*const ProcedureSequenceNode = .{null} ** 39;

    for (variable_procedure_names, 0..) |procedure_names, index| {
        arr[index] = makeProcedureSequence(procedure_names);
    }

    break :variable_procedures arr;
};

pub const reduction_procedure: ?*const data_structures.Procedure = if (@hasDecl(procedures, "reduction")) data_structures.wrap_procedure(data_structures.Procedure, @field(procedures, "reduction"), "reduction") else null;

// Parser for Symbol "Start" with index 0
fn parse_Start(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 0);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("Start") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
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
                        if (try llTryRecoveryRule_49(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_0(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "Rules" with index 1
fn parse_Rules(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 1);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("Rules") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
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
                        if (try llTryRecoveryRule_43(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RulesTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_43(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_1(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "Rule" with index 2
fn parse_Rule(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 2);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("Rule") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Rule -> VariableSymbol, AnnotationTail, 'new_line', RightHandSides\n", .{});
                }
            }
            {
                const child_node = parse_VariableSymbol(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_42(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_AnnotationTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_42(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            parse_generative_terminal_new_line(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_42(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            {
                const child_node = parse_RightHandSides(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_42(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 3
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 3 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                    std.debug.print("Reduction: Rule <~ VariableSymbol, AnnotationTail, 'new_line', RightHandSides\n", .{});
                }
            }        },
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
                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 3);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 2
                }
                repeating_node_address = temporary_address;
                {
                    const child_node = parse_NewLines(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_45(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
                    if (child_node != data_structures.Node.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                    }
                }
                {
                    const child_node = parse_Rule(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_45(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 1
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
            if (try llTryRecoveryRule_45(context, occurrence_recovery)) {
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
        }        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[45],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[45]) |procedure_pointer| {
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
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 3);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("RulesTail") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        0 => { // '\x00'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RulesTail -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                    std.debug.print("Reduction: RulesTail <~ \n", .{});
                }
            }        },
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RulesTail -> NewLines, Rule, RulesTail\n", .{});
                }
            }
            {
                const child_node = parse_NewLines(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_45(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_Rule(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_45(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RulesTail_0_2(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_45(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_3(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "NewLines" with index 4
fn parse_NewLines(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 4);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("NewLines") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: NewLines -> 'new_line', NewLinesTail\n", .{});
                }
            }
            parse_generative_terminal_new_line(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_25(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_NewLinesTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_25(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            }        },
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
                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 5);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_new_line(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_27(context, occurrence_recovery)) {
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
            if (try llTryRecoveryRule_27(context, occurrence_recovery)) {
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
        }        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[27],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[27]) |procedure_pointer| {
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
                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 5);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 3
                }
                repeating_node_address = temporary_address;
                parse_terminal__x35(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_28(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
                {
                    const child_node = parse_AnyContent(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_28(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 1
                    if (child_node != data_structures.Node.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                    }
                }
                parse_generative_terminal_new_line(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_28(context, occurrence_recovery)) {
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
            if (try llTryRecoveryRule_28(context, occurrence_recovery)) {
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
        }        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[28],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[28]) |procedure_pointer| {
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
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 5);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("NewLinesTail") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: NewLinesTail -> 'new_line', NewLinesTail\n", .{});
                }
            }
            parse_generative_terminal_new_line(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_27(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_NewLinesTail_0_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_27(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            }        },
        35 => { // '#'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: NewLinesTail -> '#', AnyContent, 'new_line', NewLinesTail\n", .{});
                }
            }
            parse_terminal__x35(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_28(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_AnyContent(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_28(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            parse_generative_terminal_new_line(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_28(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            {
                const child_node = parse_NewLinesTail_1_3(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_28(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 3
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 3 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            }        },
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: NewLinesTail -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            }        },
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
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 6);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("AnyContent") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        1, 2 => { // '\x01', '\x02'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: AnyContent -> ControlCharacter, AnyContentTail\n", .{});
                }
            }
            {
                const child_node = parse_ControlCharacter(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_5(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_AnyContentTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_5(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            }        },
        9, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: AnyContent -> 'character^\"\\\\n\"', AnyContentTail\n", .{});
                }
            }
            parse_generative_terminal_character_x94_x34_x92_x92n_x34(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_6(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_AnyContentTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_6(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                    std.debug.print("Reduction: AnyContent <~ 'character^\"\\\\n\"', AnyContentTail\n", .{});
                }
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_8(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "VariableSymbol" with index 9
fn parse_VariableSymbol(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 7);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("VariableSymbol") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
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
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            }        },
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
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_9(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "AnnotationTail" at index 2 of its right hand side
// Right hand side: -> '@', Annotation, AnnotationTail
fn parse_AnnotationTail_0_2(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
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
                        std.debug.print("Rule expansion: AnnotationTail -> '@', Annotation, AnnotationTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 8);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 2
                }
                repeating_node_address = temporary_address;
                parse_terminal__x64(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_4(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
                {
                    const child_node = parse_Annotation(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_4(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 1
                    if (child_node != data_structures.Node.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                    }
                }
            },
            else => break,
        }
    }
    const exit_node = parse_AnnotationTail(context, occurrence_recovery) catch |err| switch (err) {
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
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: AnnotationTail <~ '@', Annotation, AnnotationTail\n", .{});
            }
        }        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;

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
                std.debug.print("Procedure outcome for AnnotationTail: {f}\n", .{
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

// Parser for Symbol "AnnotationTail" with index 10
fn parse_AnnotationTail(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 8);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("AnnotationTail") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        10, 32 => { // '\n', ' '
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: AnnotationTail -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                    std.debug.print("Procedure outcome for AnnotationTail: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: AnnotationTail <~ \n", .{});
                }
            }        },
        64 => { // '@'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: AnnotationTail -> '@', Annotation, AnnotationTail\n", .{});
                }
            }
            parse_terminal__x64(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_4(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_Annotation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_4(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_AnnotationTail_0_2(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_4(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                    std.debug.print("Procedure outcome for AnnotationTail: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: AnnotationTail <~ '@', Annotation, AnnotationTail\n", .{});
                }
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_10(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "RightHandSides" with index 11
fn parse_RightHandSides(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 9);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("RightHandSides") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
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
                        if (try llTryRecoveryRule_39(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RightHandSidesTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_39(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSides <~ RightHandSideLine, RightHandSidesTail\n", .{});
                }
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_11(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "RightHandSideLine" with index 12
fn parse_RightHandSideLine(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 10);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("RightHandSideLine") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        35 => { // '#'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSideLine -> '#', AnyContent, 'new_line'\n", .{});
                }
            }
            parse_terminal__x35(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_35(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_AnyContent(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_35(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
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
                }; // child 2
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSideLine <~ '#', AnyContent, 'new_line'\n", .{});
                }
            }        },
        124 => { // '|'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSideLine -> '|', AnnotationTail, RightHandSide, 'new_line'\n", .{});
                }
            }
            parse_terminal__x124(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_36(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_AnnotationTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_36(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RightHandSide(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_36(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            parse_generative_terminal_new_line(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_36(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 3
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSideLine <~ '|', AnnotationTail, RightHandSide, 'new_line'\n", .{});
                }
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_12(context, occurrence_recovery);
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
                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 11);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                {
                    const child_node = parse_RightHandSideLine(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_41(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
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
            if (try llTryRecoveryRule_41(context, occurrence_recovery)) {
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
        }        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[41],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[41]) |procedure_pointer| {
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

// Parser for Symbol "RightHandSidesTail" with index 13
fn parse_RightHandSidesTail(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 11);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("RightHandSidesTail") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        0, 10 => { // '\x00', '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSidesTail -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSidesTail <~ \n", .{});
                }
            }        },
        35, 124 => { // '#', '|'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSidesTail -> RightHandSideLine, RightHandSidesTail\n", .{});
                }
            }
            {
                const child_node = parse_RightHandSideLine(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_41(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RightHandSidesTail_0_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_41(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSidesTail <~ RightHandSideLine, RightHandSidesTail\n", .{});
                }
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_13(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_|" with index 14
inline fn parse_terminal__x124(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        124 => { // '|'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_14(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "RightHandSide" with index 15
fn parse_RightHandSide(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 12);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("RightHandSide") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSide -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSide <~ \n", .{});
                }
            }        },
        32 => { // ' '
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSide -> 'space', Symbol, AnnotationTail, RightHandSideTail\n", .{});
                }
            }
            parse_generative_terminal_space(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_34(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_Symbol(context, &ExplicitRecoveryScope{ .id = 197, .target = .{ .occurrence = .{ .parent_variable = "RightHandSide", .rhs_index = 0, .symbol_index = 1, .variable = "Symbol" } }, .points = &[_]root.SyntaxRecoveryPoint{.{ .terminal = "\n", .@"resume" = .before }} }) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_34(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_AnnotationTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_34(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RightHandSideTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_34(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 3
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 3 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSide <~ 'space', Symbol, AnnotationTail, RightHandSideTail\n", .{});
                }
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_15(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "generative_terminal_space" with index 16
inline fn parse_generative_terminal_space(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        32 => { // ' '
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_16(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "Symbol" with index 17
fn parse_Symbol(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 13);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("Symbol") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        34 => { // '\"'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Symbol -> TerminalSymbol\n", .{});
                }
            }
            {
                const child_node = parse_TerminalSymbol(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_51(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Symbol <~ TerminalSymbol\n", .{});
                }
            }        },
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Symbol -> VariableSymbol\n", .{});
                }
            }
            {
                const child_node = parse_VariableSymbol(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_50(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Symbol <~ VariableSymbol\n", .{});
                }
            }        },
        92 => { // '\\'
            switch (context.head(u8, 1)) {
                34 => { // '\"'
                    if (comptime builtin.mode == .Debug) {
                        if (context.verbosityLevel() > 1) {
                            std.debug.print("Rule expansion: Symbol -> TerminalSymbol\n", .{});
                        }
                    }
                    {
                        const child_node = parse_TerminalSymbol(context, null) catch |err| switch (err) {
                            error.ExplicitSyntaxRecovery => {
                                if (try llTryRecoveryRule_51(context, occurrence_recovery)) {
                                    return data_structures.Node.invalid_pointer;
                                }
                                return err;
                            },
                            else => return err,
                        }; // child 0
                        if (child_node != data_structures.Node.invalid_pointer) {
                            context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                        }
                    }
                    context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                                string_utilities.fmtNode(args.node_address, context),
                            });
                        }
                    }
                    node_address = args.node_address orelse data_structures.Node.invalid_pointer;

                    if (comptime builtin.mode == .Debug) {
                        if (context.verbosityLevel() > 1) {
                            std.debug.print("Reduction: Symbol <~ TerminalSymbol\n", .{});
                        }
                    }                },
                else => {
                    @branchHint(.unlikely);
                    return ll_syntax_error_17(context, occurrence_recovery);
                },
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
                        if (try llTryRecoveryRule_52(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Symbol <~ GenerativeTerminalSymbol\n", .{});
                }
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_18(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Self-Repeating Parser for Symbol "RightHandSideTail" at index 3 of its right hand side
// Right hand side: -> 'space', Symbol, AnnotationTail, RightHandSideTail
fn parse_RightHandSideTail_0_3(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
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
                        std.debug.print("Rule expansion: RightHandSideTail -> 'space', Symbol, AnnotationTail, RightHandSideTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 14);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 3
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_space(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_38(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
                {
                    const child_node = parse_Symbol(context, &ExplicitRecoveryScope{ .id = 208, .target = .{ .occurrence = .{ .parent_variable = "RightHandSideTail", .rhs_index = 0, .symbol_index = 1, .variable = "Symbol" } }, .points = &[_]root.SyntaxRecoveryPoint{.{ .terminal = "\n", .@"resume" = .before }} }) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_38(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 1
                    if (child_node != data_structures.Node.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                    }
                }
                {
                    const child_node = parse_AnnotationTail(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_38(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 2
                    if (child_node != data_structures.Node.invalid_pointer) {
                        context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                    }
                }
            },
            else => break,
        }
    }
    const exit_node = parse_RightHandSideTail(context, occurrence_recovery) catch |err| switch (err) {
        error.ExplicitSyntaxRecovery => {
            if (try llTryRecoveryRule_38(context, occurrence_recovery)) {
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
                std.debug.print("Reduction: RightHandSideTail <~ 'space', Symbol, AnnotationTail, RightHandSideTail\n", .{});
            }
        }        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[38],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[38]) |procedure_pointer| {
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

// Parser for Symbol "RightHandSideTail" with index 18
fn parse_RightHandSideTail(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 14);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("RightHandSideTail") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSideTail -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSideTail <~ \n", .{});
                }
            }        },
        32 => { // ' '
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RightHandSideTail -> 'space', Symbol, AnnotationTail, RightHandSideTail\n", .{});
                }
            }
            parse_generative_terminal_space(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_38(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_Symbol(context, &ExplicitRecoveryScope{ .id = 208, .target = .{ .occurrence = .{ .parent_variable = "RightHandSideTail", .rhs_index = 0, .symbol_index = 1, .variable = "Symbol" } }, .points = &[_]root.SyntaxRecoveryPoint{.{ .terminal = "\n", .@"resume" = .before }} }) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_38(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_AnnotationTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_38(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_RightHandSideTail_0_3(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_38(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 3
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 3 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RightHandSideTail <~ 'space', Symbol, AnnotationTail, RightHandSideTail\n", .{});
                }
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_19(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "TerminalSymbol" with index 19
fn parse_TerminalSymbol(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 15);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("TerminalSymbol") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
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
                }; // child 1
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
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: TerminalSymbol <~ '\"', SimpleStringContent, '\"'\n", .{});
                }
            }        },
        92 => { // '\\'
            switch (context.head(u8, 1)) {
                34 => { // '\"'
                    if (comptime builtin.mode == .Debug) {
                        if (context.verbosityLevel() > 1) {
                            std.debug.print("Rule expansion: TerminalSymbol -> RawString\n", .{});
                        }
                    }
                    {
                        const child_node = parse_RawString(context, null) catch |err| switch (err) {
                            error.ExplicitSyntaxRecovery => {
                                if (try llTryRecoveryRule_55(context, occurrence_recovery)) {
                                    return data_structures.Node.invalid_pointer;
                                }
                                return err;
                            },
                            else => return err,
                        }; // child 0
                        if (child_node != data_structures.Node.invalid_pointer) {
                            context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                        }
                    }
                    context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                                string_utilities.fmtNode(args.node_address, context),
                            });
                        }
                    }
                    node_address = args.node_address orelse data_structures.Node.invalid_pointer;

                    if (comptime builtin.mode == .Debug) {
                        if (context.verbosityLevel() > 1) {
                            std.debug.print("Reduction: TerminalSymbol <~ RawString\n", .{});
                        }
                    }                },
                else => {
                    @branchHint(.unlikely);
                    return ll_syntax_error_20(context, occurrence_recovery);
                },
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_21(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "GenerativeTerminalSymbol" with index 20
fn parse_GenerativeTerminalSymbol(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 16);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("GenerativeTerminalSymbol") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
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
                        if (try llTryRecoveryRule_19(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_GenerativeTerminalExceptions(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_19(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: GenerativeTerminalSymbol <~ LowercaseId, GenerativeTerminalExceptions\n", .{});
                }
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_22(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "UppercaseId" with index 21
fn parse_UppercaseId(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 17);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("UppercaseId") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
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
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: UppercaseId <~ 'uppercase_letter', IdTail\n", .{});
                }
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_23(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "terminal__" with index 22
inline fn parse_terminal__(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        95 => { // '_'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_24(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "RawString" with index 23
fn parse_RawString(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 18);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("RawString") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u16, 0)) {
        23586 => { // '\\\"'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RawString -> '\\\\\"', RawIndicator, '\"'\n", .{});
                }
            }
            parse_terminal__x92_x92_x34(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_31(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            const verbatim_start = context.currentTokenSourceOffset();
            {
                const child_node = parse_RawIndicator(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_31(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            const verbatim_terminator = context.getTextSlice(verbatim_start, context.currentTokenSourceOffset() - verbatim_start);
            try context.captureVerbatim(verbatim_terminator, true);
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(child_node).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(child_node).text_start;
                }
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            parse_terminal__x34(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_31(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            try runProcedureSequence(variable_procedures[18], &args);
            if (comptime symbol_procedures[23]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            if (comptime reduction_procedure) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 2) {
                    std.debug.print("Procedure outcome for RawString: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RawString <~ '\\\\\"', RawIndicator, '\"'\n", .{});
                }
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_25(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_"" with index 24
inline fn parse_terminal__x34(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        34 => { // '\"'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_26(context, occurrence_recovery);
        },
    }
}

// Self-Repeating Parser for Symbol "SimpleStringContent" at index 1 of its right hand side
// Right hand side: -> 'character^\"\\\\u{{22}}\"', SimpleStringContent
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
                        std.debug.print("Rule expansion: SimpleStringContent -> 'character^\"\\\\u{{22}}\"', SimpleStringContent\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 19);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34(context, null) catch |err| switch (err) {
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
                std.debug.print("Reduction: SimpleStringContent <~ 'character^\"\\\\u{{22}}\"', SimpleStringContent\n", .{});
            }
        }        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;

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
                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 19);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse__Utf8Scalar_(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_48(context, occurrence_recovery)) {
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
            if (try llTryRecoveryRule_48(context, occurrence_recovery)) {
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
        }        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[48],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[48]) |procedure_pointer| {
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

// Parser for Symbol "SimpleStringContent" with index 25
fn parse_SimpleStringContent(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 19);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("SimpleStringContent") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        9, 10, 11, 12, 13, 32, 33, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: SimpleStringContent -> 'character^\"\\\\u{{22}}\"', SimpleStringContent\n", .{});
                }
            }
            parse_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34(context, null) catch |err| switch (err) {
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
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                    std.debug.print("Procedure outcome for SimpleStringContent: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: SimpleStringContent <~ 'character^\"\\\\u{{22}}\"', SimpleStringContent\n", .{});
                }
            }        },
        34 => { // '\"'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: SimpleStringContent -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            }        },
        194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf', '\xe0', '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xed', '\xee', '\xef', '\xf0', '\xf1', '\xf2', '\xf3', '\xf4'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: SimpleStringContent -> _Utf8Scalar, SimpleStringContent\n", .{});
                }
            }
            parse__Utf8Scalar_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_48(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_SimpleStringContent_1_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_48(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_27(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_\\"" with index 26
inline fn parse_terminal__x92_x92_x34(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u16, 0)) {
        23586 => { // '\\\"'
            context.releaseToken(2);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_28(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "RawIndicator" with index 27
fn parse_RawIndicator(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 20);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("RawIndicator") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        9, 11, 12, 13, 32, 33, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\x0b', '\x0c', '\r', ' ', '!', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RawIndicator -> 'character^\"\\\\u{{22}}\"^\"\\\\n\"^\"\\\\u{{5c}}\"'\n", .{});
                }
            }
            parse_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34_x94_x34_x92_x92n_x34_x94_x34_x92_x92u_x1235c_x125_x34(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_30(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            try runProcedureSequence(variable_procedures[20], &args);
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
                    std.debug.print("Procedure outcome for RawIndicator: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RawIndicator <~ 'character^\"\\\\u{{22}}\"^\"\\\\n\"^\"\\\\u{{5c}}\"'\n", .{});
                }
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_29(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "generative_terminal_character^"\\u{22}"^"\\n"^"\\u{5c}"" with index 28
inline fn parse_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34_x94_x34_x92_x92n_x34_x94_x34_x92_x92u_x1235c_x125_x34(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        9, 11, 12, 13, 32, 33, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\x0b', '\x0c', '\r', ' ', '!', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_30(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "LowercaseId" with index 29
fn parse_LowercaseId(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 21);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("LowercaseId") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: LowercaseId -> 'lowercase_letter', IdTail\n", .{});
                }
            }
            parse_generative_terminal_lowercase_letter(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_24(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_IdTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_24(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_31(context, occurrence_recovery);
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
                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 22);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 2
                }
                repeating_node_address = temporary_address;
                parse_terminal__x94(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_18(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
                {
                    const child_node = parse_TerminalSymbol(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_18(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 1
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
            context.node_allocator.at(repeating_node_address).immediateAppendChildren(repeating_node_address, exit_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
        }
    }
    while (repeating_node_address != data_structures.Node.invalid_pointer) {

        if (comptime builtin.mode == .Debug) {
            if (context.verbosityLevel() > 1) {
                std.debug.print("Reduction: GenerativeTerminalExceptions <~ '^', TerminalSymbol, GenerativeTerminalExceptions\n", .{});
            }
        }        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;

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
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 22);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("GenerativeTerminalExceptions") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        10, 32, 64 => { // '\n', ' ', '@'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: GenerativeTerminalExceptions -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            }        },
        94 => { // '^'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: GenerativeTerminalExceptions -> '^', TerminalSymbol, GenerativeTerminalExceptions\n", .{});
                }
            }
            parse_terminal__x94(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_18(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_TerminalSymbol(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_18(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_GenerativeTerminalExceptions_0_2(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_18(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 2 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_32(context, occurrence_recovery);
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
            return ll_syntax_error_33(context, occurrence_recovery);
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
            return ll_syntax_error_34(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "Annotation" with index 33
fn parse_Annotation(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 23);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("Annotation") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        33 => { // '!'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Annotation -> '!', RecoveryPoint\n", .{});
                }
            }
            parse_terminal__x33(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_1(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_RecoveryPoint(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_1(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                    std.debug.print("Procedure outcome for Annotation: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Annotation <~ '!', RecoveryPoint\n", .{});
                }
            }        },
        62 => { // '>'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Annotation -> '>', VerbatimMarker\n", .{});
                }
            }
            parse_terminal__x62(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_2(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_VerbatimMarker(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_2(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                    std.debug.print("Procedure outcome for Annotation: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Annotation <~ '>', VerbatimMarker\n", .{});
                }
            }        },
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Annotation -> Procedure\n", .{});
                }
            }
            {
                const child_node = parse_Procedure(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_0(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                    std.debug.print("Procedure outcome for Annotation: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Annotation <~ Procedure\n", .{});
                }
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_35(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "Procedure" with index 34
fn parse_Procedure(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 24);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("Procedure") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: Procedure -> CamelCaseId\n", .{});
                }
            }
            {
                const child_node = parse_CamelCaseId(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_29(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                    std.debug.print("Procedure outcome for Procedure: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: Procedure <~ CamelCaseId\n", .{});
                }
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_36(context, occurrence_recovery);
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
            return ll_syntax_error_37(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "RecoveryPoint" with index 36
fn parse_RecoveryPoint(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 25);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("RecoveryPoint") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        34, 94 => { // '\"', '^'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: RecoveryPoint -> TerminalAndCursor\n", .{});
                }
            }
            {
                const child_node = parse_TerminalAndCursor(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_32(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                    std.debug.print("Procedure outcome for RecoveryPoint: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: RecoveryPoint <~ TerminalAndCursor\n", .{});
                }
            }        },
        92 => { // '\\'
            switch (context.head(u8, 1)) {
                34 => { // '\"'
                    if (comptime builtin.mode == .Debug) {
                        if (context.verbosityLevel() > 1) {
                            std.debug.print("Rule expansion: RecoveryPoint -> TerminalAndCursor\n", .{});
                        }
                    }
                    {
                        const child_node = parse_TerminalAndCursor(context, null) catch |err| switch (err) {
                            error.ExplicitSyntaxRecovery => {
                                if (try llTryRecoveryRule_32(context, occurrence_recovery)) {
                                    return data_structures.Node.invalid_pointer;
                                }
                                return err;
                            },
                            else => return err,
                        }; // child 0
                        if (child_node != data_structures.Node.invalid_pointer) {
                            context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                        }
                    }
                    context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                            std.debug.print("Procedure outcome for RecoveryPoint: {f}\n", .{
                                string_utilities.fmtNode(args.node_address, context),
                            });
                        }
                    }
                    node_address = args.node_address orelse data_structures.Node.invalid_pointer;

                    if (comptime builtin.mode == .Debug) {
                        if (context.verbosityLevel() > 1) {
                            std.debug.print("Reduction: RecoveryPoint <~ TerminalAndCursor\n", .{});
                        }
                    }                },
                else => {
                    @branchHint(.unlikely);
                    return ll_syntax_error_38(context, occurrence_recovery);
                },
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_39(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_>" with index 37
inline fn parse_terminal__x62(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        62 => { // '>'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_40(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "VerbatimMarker" with index 38
fn parse_VerbatimMarker(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 26);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("VerbatimMarker") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        34, 94 => { // '\"', '^'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: VerbatimMarker -> TerminalAndCursor\n", .{});
                }
            }
            {
                const child_node = parse_TerminalAndCursor(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_61(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[61],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[61]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[26], &args);
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
                    std.debug.print("Procedure outcome for VerbatimMarker: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: VerbatimMarker <~ TerminalAndCursor\n", .{});
                }
            }        },
        62 => { // '>'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: VerbatimMarker -> '>'\n", .{});
                }
            }
            parse_terminal__x62(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_60(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[60],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[60]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[26], &args);
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
                    std.debug.print("Procedure outcome for VerbatimMarker: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: VerbatimMarker <~ '>'\n", .{});
                }
            }        },
        92 => { // '\\'
            switch (context.head(u8, 1)) {
                34 => { // '\"'
                    if (comptime builtin.mode == .Debug) {
                        if (context.verbosityLevel() > 1) {
                            std.debug.print("Rule expansion: VerbatimMarker -> TerminalAndCursor\n", .{});
                        }
                    }
                    {
                        const child_node = parse_TerminalAndCursor(context, null) catch |err| switch (err) {
                            error.ExplicitSyntaxRecovery => {
                                if (try llTryRecoveryRule_61(context, occurrence_recovery)) {
                                    return data_structures.Node.invalid_pointer;
                                }
                                return err;
                            },
                            else => return err,
                        }; // child 0
                        if (child_node != data_structures.Node.invalid_pointer) {
                            context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                        }
                    }
                    context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
                    var args = data_structures.ProcedureArguments{
                        .context = context,
                        .rule = rules[61],
                        .node_address = node_address,
                    };
                    try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
                    if (comptime rule_procedures[61]) |procedure_pointer| {
                        const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                        try procedure(&args);
                    }
                    try runProcedureSequence(variable_procedures[26], &args);
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
                            std.debug.print("Procedure outcome for VerbatimMarker: {f}\n", .{
                                string_utilities.fmtNode(args.node_address, context),
                            });
                        }
                    }
                    node_address = args.node_address orelse data_structures.Node.invalid_pointer;

                    if (comptime builtin.mode == .Debug) {
                        if (context.verbosityLevel() > 1) {
                            std.debug.print("Reduction: VerbatimMarker <~ TerminalAndCursor\n", .{});
                        }
                    }                },
                else => {
                    @branchHint(.unlikely);
                    return ll_syntax_error_41(context, occurrence_recovery);
                },
            }
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_42(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "CamelCaseId" with index 39
fn parse_CamelCaseId(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 27);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("CamelCaseId") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: CamelCaseId -> 'lowercase_letter', CamelCaseIdTail\n", .{});
                }
            }
            parse_generative_terminal_lowercase_letter(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_10(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_CamelCaseIdTail(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_10(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            try runProcedureSequence(variable_procedures[27], &args);
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_43(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "TerminalAndCursor" with index 40
fn parse_TerminalAndCursor(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 28);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("TerminalAndCursor") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        34 => { // '\"'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: TerminalAndCursor -> TerminalSymbol, '^'\n", .{});
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
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            parse_terminal__x94(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_53(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            try runProcedureSequence(variable_procedures[28], &args);
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
                    std.debug.print("Procedure outcome for TerminalAndCursor: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: TerminalAndCursor <~ TerminalSymbol, '^'\n", .{});
                }
            }        },
        92 => { // '\\'
            switch (context.head(u8, 1)) {
                34 => { // '\"'
                    if (comptime builtin.mode == .Debug) {
                        if (context.verbosityLevel() > 1) {
                            std.debug.print("Rule expansion: TerminalAndCursor -> TerminalSymbol, '^'\n", .{});
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
                        }; // child 0
                        if (child_node != data_structures.Node.invalid_pointer) {
                            context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                        }
                    }
                    parse_terminal__x94(context, null) catch |err| switch (err) {
                            error.ExplicitSyntaxRecovery => {
                                if (try llTryRecoveryRule_53(context, occurrence_recovery)) {
                                    return data_structures.Node.invalid_pointer;
                                }
                                return err;
                            },
                            else => return err,
                        }; // child 1
                    context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
                    try runProcedureSequence(variable_procedures[28], &args);
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
                            std.debug.print("Procedure outcome for TerminalAndCursor: {f}\n", .{
                                string_utilities.fmtNode(args.node_address, context),
                            });
                        }
                    }
                    node_address = args.node_address orelse data_structures.Node.invalid_pointer;

                    if (comptime builtin.mode == .Debug) {
                        if (context.verbosityLevel() > 1) {
                            std.debug.print("Reduction: TerminalAndCursor <~ TerminalSymbol, '^'\n", .{});
                        }
                    }                },
                else => {
                    @branchHint(.unlikely);
                    return ll_syntax_error_44(context, occurrence_recovery);
                },
            }
        },
        94 => { // '^'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: TerminalAndCursor -> '^', TerminalSymbol\n", .{});
                }
            }
            parse_terminal__x94(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_54(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_TerminalSymbol(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_54(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            try runProcedureSequence(variable_procedures[28], &args);
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
                    std.debug.print("Procedure outcome for TerminalAndCursor: {f}\n", .{
                        string_utilities.fmtNode(args.node_address, context),
                    });
                }
            }
            node_address = args.node_address orelse data_structures.Node.invalid_pointer;

            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Reduction: TerminalAndCursor <~ '^', TerminalSymbol\n", .{});
                }
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_45(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "generative_terminal_character^"\\u{22}"" with index 41
inline fn parse_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        9, 10, 11, 12, 13, 32, 33, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\n', '\x0b', '\x0c', '\r', ' ', '!', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_46(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "_Utf8Scalar" with index 42
fn parse__Utf8Scalar(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("_Utf8Scalar") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8Scalar -> _Utf8TwoByte\n", .{});
                }
            }
            parse__Utf8TwoByte_(context, null) catch |err| switch (err) {
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
                    std.debug.print("Reduction: _Utf8Scalar <~ _Utf8TwoByte\n", .{});
                }
            }        },
        224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239 => { // '\xe0', '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xed', '\xee', '\xef'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8Scalar -> _Utf8ThreeByte\n", .{});
                }
            }
            parse__Utf8ThreeByte_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_67(context, occurrence_recovery)) {
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
            }        },
        240, 241, 242, 243, 244 => { // '\xf0', '\xf1', '\xf2', '\xf3', '\xf4'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8Scalar -> _Utf8FourByte\n", .{});
                }
            }
            parse__Utf8FourByte_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_68(context, occurrence_recovery)) {
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_47(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "_Utf8TwoByte" with index 43
fn parse__Utf8TwoByte(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("_Utf8TwoByte") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8TwoByte -> 'utf8_lead_two', 'utf8_continuation'\n", .{});
                }
            }
            parse_generative_terminal_utf8_lead_two(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_72(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_72(context, occurrence_recovery)) {
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_48(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "_Utf8ThreeByte" with index 44
fn parse__Utf8ThreeByte(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("_Utf8ThreeByte") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        224 => { // '\xe0'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8ThreeByte -> '\\xe0', 'utf8_continuation_a0_bf', 'utf8_continuation'\n", .{});
                }
            }
            parse_terminal__x92xe0(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_69(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_a0_bf(context, null) catch |err| switch (err) {
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
                    std.debug.print("Reduction: _Utf8ThreeByte <~ '\\xe0', 'utf8_continuation_a0_bf', 'utf8_continuation'\n", .{});
                }
            }        },
        225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 238, 239 => { // '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xee', '\xef'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8ThreeByte -> 'utf8_lead_three_general', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
            parse_generative_terminal_utf8_lead_three_general(context, null) catch |err| switch (err) {
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
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_70(context, occurrence_recovery)) {
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
            }        },
        237 => { // '\xed'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8ThreeByte -> '\\xed', 'utf8_continuation_80_9f', 'utf8_continuation'\n", .{});
                }
            }
            parse_terminal__x92xed(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_71(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_80_9f(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_71(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_71(context, occurrence_recovery)) {
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_49(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "_Utf8FourByte" with index 45
fn parse__Utf8FourByte(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("_Utf8FourByte") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        240 => { // '\xf0'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8FourByte -> '\\xf0', 'utf8_continuation_90_bf', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
            parse_terminal__x92xf0(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_63(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_90_bf(context, null) catch |err| switch (err) {
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
                    std.debug.print("Reduction: _Utf8FourByte <~ '\\xf0', 'utf8_continuation_90_bf', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }        },
        241, 242, 243 => { // '\xf1', '\xf2', '\xf3'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8FourByte -> 'utf8_lead_four_general', 'utf8_continuation', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
            parse_generative_terminal_utf8_lead_four_general(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_64(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_64(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_64(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_64(context, occurrence_recovery)) {
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
            }        },
        244 => { // '\xf4'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8FourByte -> '\\xf4', 'utf8_continuation_80_8f', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
            parse_terminal__x92xf4(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_65(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_80_8f(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_65(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_65(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            parse_generative_terminal_utf8_continuation(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_65(context, occurrence_recovery)) {
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_50(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_utf8_lead_two" with index 46
inline fn parse_generative_terminal_utf8_lead_two(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_51(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_utf8_continuation" with index 47
inline fn parse_generative_terminal_utf8_continuation(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191 => { // '\x80', '\x81', '\x82', '\x83', '\x84', '\x85', '\x86', '\x87', '\x88', '\x89', '\x8a', '\x8b', '\x8c', '\x8d', '\x8e', '\x8f', '\x90', '\x91', '\x92', '\x93', '\x94', '\x95', '\x96', '\x97', '\x98', '\x99', '\x9a', '\x9b', '\x9c', '\x9d', '\x9e', '\x9f', '\xa0', '\xa1', '\xa2', '\xa3', '\xa4', '\xa5', '\xa6', '\xa7', '\xa8', '\xa9', '\xaa', '\xab', '\xac', '\xad', '\xae', '\xaf', '\xb0', '\xb1', '\xb2', '\xb3', '\xb4', '\xb5', '\xb6', '\xb7', '\xb8', '\xb9', '\xba', '\xbb', '\xbc', '\xbd', '\xbe', '\xbf'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_52(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "terminal_\xe0" with index 48
inline fn parse_terminal__x92xe0(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        224 => { // '\xe0'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_53(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_utf8_continuation_a0_bf" with index 49
inline fn parse_generative_terminal_utf8_continuation_a0_bf(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191 => { // '\xa0', '\xa1', '\xa2', '\xa3', '\xa4', '\xa5', '\xa6', '\xa7', '\xa8', '\xa9', '\xaa', '\xab', '\xac', '\xad', '\xae', '\xaf', '\xb0', '\xb1', '\xb2', '\xb3', '\xb4', '\xb5', '\xb6', '\xb7', '\xb8', '\xb9', '\xba', '\xbb', '\xbc', '\xbd', '\xbe', '\xbf'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_54(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_utf8_lead_three_general" with index 50
inline fn parse_generative_terminal_utf8_lead_three_general(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 238, 239 => { // '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xee', '\xef'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_55(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "terminal_\xed" with index 51
inline fn parse_terminal__x92xed(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        237 => { // '\xed'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_56(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_utf8_continuation_80_9f" with index 52
inline fn parse_generative_terminal_utf8_continuation_80_9f(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159 => { // '\x80', '\x81', '\x82', '\x83', '\x84', '\x85', '\x86', '\x87', '\x88', '\x89', '\x8a', '\x8b', '\x8c', '\x8d', '\x8e', '\x8f', '\x90', '\x91', '\x92', '\x93', '\x94', '\x95', '\x96', '\x97', '\x98', '\x99', '\x9a', '\x9b', '\x9c', '\x9d', '\x9e', '\x9f'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_57(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "terminal_\xf0" with index 53
inline fn parse_terminal__x92xf0(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        240 => { // '\xf0'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_58(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_utf8_continuation_90_bf" with index 54
inline fn parse_generative_terminal_utf8_continuation_90_bf(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191 => { // '\x90', '\x91', '\x92', '\x93', '\x94', '\x95', '\x96', '\x97', '\x98', '\x99', '\x9a', '\x9b', '\x9c', '\x9d', '\x9e', '\x9f', '\xa0', '\xa1', '\xa2', '\xa3', '\xa4', '\xa5', '\xa6', '\xa7', '\xa8', '\xa9', '\xaa', '\xab', '\xac', '\xad', '\xae', '\xaf', '\xb0', '\xb1', '\xb2', '\xb3', '\xb4', '\xb5', '\xb6', '\xb7', '\xb8', '\xb9', '\xba', '\xbb', '\xbc', '\xbd', '\xbe', '\xbf'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_59(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_utf8_lead_four_general" with index 55
inline fn parse_generative_terminal_utf8_lead_four_general(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        241, 242, 243 => { // '\xf1', '\xf2', '\xf3'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_60(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "terminal_\xf4" with index 56
inline fn parse_terminal__x92xf4(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        244 => { // '\xf4'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_61(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_utf8_continuation_80_8f" with index 57
inline fn parse_generative_terminal_utf8_continuation_80_8f(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143 => { // '\x80', '\x81', '\x82', '\x83', '\x84', '\x85', '\x86', '\x87', '\x88', '\x89', '\x8a', '\x8b', '\x8c', '\x8d', '\x8e', '\x8f'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_62(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "ControlCharacter" with index 58
fn parse_ControlCharacter(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 33);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("ControlCharacter") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        1 => { // '\x01'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: ControlCharacter -> '\\x01'\n", .{});
                }
            }
            parse_terminal__x92x01(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_14(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            try runProcedureSequence(variable_procedures[33], &args);
            if (comptime symbol_procedures[58]) |procedure_pointer| {
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
            }        },
        2 => { // '\x02'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: ControlCharacter -> '\\x02'\n", .{});
                }
            }
            parse_terminal__x92x02(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_15(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            try runProcedureSequence(variable_procedures[33], &args);
            if (comptime symbol_procedures[58]) |procedure_pointer| {
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
                    std.debug.print("Reduction: ControlCharacter <~ '\\x02'\n", .{});
                }
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_63(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "terminal_\x01" with index 59
inline fn parse_terminal__x92x01(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        1 => { // '\x01'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_64(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "terminal_\x02" with index 60
inline fn parse_terminal__x92x02(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        2 => { // '\x02'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_65(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_character^"\\n"" with index 61
inline fn parse_generative_terminal_character_x94_x34_x92_x92n_x34(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        9, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_66(context, occurrence_recovery);
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
            1, 2 => { // '\x01', '\x02'
                if (comptime builtin.mode == .Debug) {
                    if (context.verbosityLevel() > 1) {
                        std.debug.print("Rule expansion: AnyContentTail -> ControlCharacter, AnyContentTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 34);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                {
                    const child_node = parse_ControlCharacter(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_8(context, occurrence_recovery)) {
                                return data_structures.Node.invalid_pointer;
                            }
                            return err;
                        },
                        else => return err,
                    }; // child 0
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
                std.debug.print("Reduction: AnyContentTail <~ ControlCharacter, AnyContentTail\n", .{});
            }
        }        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;

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
        try runProcedureSequence(variable_procedures[34], &args);
        if (comptime symbol_procedures[62]) |procedure_pointer| {
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
// Right hand side: -> 'character^\"\\\\n\"', AnyContentTail
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
                        std.debug.print("Rule expansion: AnyContentTail -> 'character^\"\\\\n\"', AnyContentTail\n", .{});
                    }
                }
                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 34);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_character_x94_x34_x92_x92n_x34(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_9(context, occurrence_recovery)) {
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
            if (try llTryRecoveryRule_9(context, occurrence_recovery)) {
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
                std.debug.print("Reduction: AnyContentTail <~ 'character^\"\\\\n\"', AnyContentTail\n", .{});
            }
        }        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[9],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[9]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[34], &args);
        if (comptime symbol_procedures[62]) |procedure_pointer| {
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

// Parser for Symbol "AnyContentTail" with index 62
fn parse_AnyContentTail(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 34);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("AnyContentTail") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        1, 2 => { // '\x01', '\x02'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: AnyContentTail -> ControlCharacter, AnyContentTail\n", .{});
                }
            }
            {
                const child_node = parse_ControlCharacter(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_8(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 0 (chain if replaceWithChildren)
                }
            }
            {
                const child_node = parse_AnyContentTail_1_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_8(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            try runProcedureSequence(variable_procedures[34], &args);
            if (comptime symbol_procedures[62]) |procedure_pointer| {
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
            }        },
        9, 11, 12, 13, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126 => { // '\t', '\x0b', '\x0c', '\r', ' ', '!', '\"', '#', '$', '%', '&', ''', '(', ')', '*', '+', ',', '-', '.', '/', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', ':', ';', '<', '=', '>', '?', '@', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '{', '|', '}', '~'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: AnyContentTail -> 'character^\"\\\\n\"', AnyContentTail\n", .{});
                }
            }
            parse_generative_terminal_character_x94_x34_x92_x92n_x34(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_9(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_AnyContentTail_0_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_9(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            try runProcedureSequence(variable_procedures[34], &args);
            if (comptime symbol_procedures[62]) |procedure_pointer| {
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
                    std.debug.print("Reduction: AnyContentTail <~ 'character^\"\\\\n\"', AnyContentTail\n", .{});
                }
            }        },
        10 => { // '\n'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: AnyContentTail -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            try runProcedureSequence(variable_procedures[34], &args);
            if (comptime symbol_procedures[62]) |procedure_pointer| {
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_67(context, occurrence_recovery);
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
                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 35);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_terminal__(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_21(context, occurrence_recovery)) {
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
            if (try llTryRecoveryRule_21(context, occurrence_recovery)) {
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
        }        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[21],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[21]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[35], &args);
        if (comptime symbol_procedures[63]) |procedure_pointer| {
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
                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 35);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_letter(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_22(context, occurrence_recovery)) {
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
            if (try llTryRecoveryRule_22(context, occurrence_recovery)) {
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
        }        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[22],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[22]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[35], &args);
        if (comptime symbol_procedures[63]) |procedure_pointer| {
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
                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 35);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_digit(context, null) catch |err| switch (err) {
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
    const exit_node = parse_IdTail(context, occurrence_recovery) catch |err| switch (err) {
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
                std.debug.print("Reduction: IdTail <~ 'digit', IdTail\n", .{});
            }
        }        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;

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
        try runProcedureSequence(variable_procedures[35], &args);
        if (comptime symbol_procedures[63]) |procedure_pointer| {
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

// Parser for Symbol "IdTail" with index 63
fn parse_IdTail(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 35);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("IdTail") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        10, 32, 64, 94 => { // '\n', ' ', '@', '^'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: IdTail -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            try runProcedureSequence(variable_procedures[35], &args);
            if (comptime symbol_procedures[63]) |procedure_pointer| {
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
            }        },
        48, 49, 50, 51, 52, 53, 54, 55, 56, 57 => { // '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: IdTail -> 'digit', IdTail\n", .{});
                }
            }
            parse_generative_terminal_digit(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_23(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_IdTail_1_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_23(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            try runProcedureSequence(variable_procedures[35], &args);
            if (comptime symbol_procedures[63]) |procedure_pointer| {
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
            }        },
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: IdTail -> 'letter', IdTail\n", .{});
                }
            }
            parse_generative_terminal_letter(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_22(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_IdTail_0_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_22(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            try runProcedureSequence(variable_procedures[35], &args);
            if (comptime symbol_procedures[63]) |procedure_pointer| {
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
            }        },
        95 => { // '_'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: IdTail -> '_', IdTail\n", .{});
                }
            }
            parse_terminal__(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_21(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_IdTail_2_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_21(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            try runProcedureSequence(variable_procedures[35], &args);
            if (comptime symbol_procedures[63]) |procedure_pointer| {
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_68(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "generative_terminal_letter" with index 64
inline fn parse_generative_terminal_letter(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_69(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_digit" with index 65
inline fn parse_generative_terminal_digit(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        48, 49, 50, 51, 52, 53, 54, 55, 56, 57 => { // '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_70(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_lowercase_letter" with index 66
inline fn parse_generative_terminal_lowercase_letter(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_71(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "generative_terminal_uppercase_letter" with index 67
inline fn parse_generative_terminal_uppercase_letter(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_72(context, occurrence_recovery);
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
                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 36);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_letter(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_12(context, occurrence_recovery)) {
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
            if (try llTryRecoveryRule_12(context, occurrence_recovery)) {
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
        }        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[12],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[12]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[36], &args);
        if (comptime symbol_procedures[68]) |procedure_pointer| {
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
                const temporary_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 36);
                if (node_address == data_structures.Node.invalid_pointer) {
                    node_address = temporary_address;
                } else {
                    context.node_allocator.at(repeating_node_address).immediateInsertChild(repeating_node_address, temporary_address, context.node_allocator); // child 1
                }
                repeating_node_address = temporary_address;
                parse_generative_terminal_digit(context, null) catch |err| switch (err) {
                        error.ExplicitSyntaxRecovery => {
                            if (try llTryRecoveryRule_13(context, occurrence_recovery)) {
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
            if (try llTryRecoveryRule_13(context, occurrence_recovery)) {
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
        }        context.node_allocator.at(repeating_node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(repeating_node_address).text_start;

        var args = data_structures.ProcedureArguments{
            .context = context,
            .rule = rules[13],
            .node_address = repeating_node_address,
        };
        try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
        if (comptime rule_procedures[13]) |procedure_pointer| {
            const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
            try procedure(&args);
        }
        try runProcedureSequence(variable_procedures[36], &args);
        if (comptime symbol_procedures[68]) |procedure_pointer| {
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

// Parser for Symbol "CamelCaseIdTail" with index 68
fn parse_CamelCaseIdTail(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    var node_address = try context.node_allocator.create(context.currentTokenSourceOffset(), 36);

    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("CamelCaseIdTail") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        10, 32, 64 => { // '\n', ' ', '@'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: CamelCaseIdTail -> \n", .{});
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            try runProcedureSequence(variable_procedures[36], &args);
            if (comptime symbol_procedures[68]) |procedure_pointer| {
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
            }        },
        48, 49, 50, 51, 52, 53, 54, 55, 56, 57 => { // '0', '1', '2', '3', '4', '5', '6', '7', '8', '9'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: CamelCaseIdTail -> 'digit', CamelCaseIdTail\n", .{});
                }
            }
            parse_generative_terminal_digit(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_13(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_CamelCaseIdTail_1_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_13(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
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
            try runProcedureSequence(variable_procedures[36], &args);
            if (comptime symbol_procedures[68]) |procedure_pointer| {
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
            }        },
        65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122 => { // 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: CamelCaseIdTail -> 'letter', CamelCaseIdTail\n", .{});
                }
            }
            parse_generative_terminal_letter(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_12(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            {
                const child_node = parse_CamelCaseIdTail_0_1(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_12(context, occurrence_recovery)) {
                            return data_structures.Node.invalid_pointer;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
                if (child_node != data_structures.Node.invalid_pointer) {
                    context.node_allocator.at(node_address).immediateAppendChildren(node_address, child_node, context.node_allocator); // child 1 (chain if replaceWithChildren)
                }
            }
            context.node_allocator.at(node_address).text_length = context.currentTokenSourceOffset() - context.node_allocator.at(node_address).text_start;
            var args = data_structures.ProcedureArguments{
                .context = context,
                .rule = rules[12],
                .node_address = node_address,
            };
            try runProcedureSequence(comptime makeProcedureSequence(&[_][]const u8{}), &args);
            if (comptime rule_procedures[12]) |procedure_pointer| {
                const procedure = @as(*data_structures.Procedure, @constCast(procedure_pointer));
                try procedure(&args);
            }
            try runProcedureSequence(variable_procedures[36], &args);
            if (comptime symbol_procedures[68]) |procedure_pointer| {
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_73(context, occurrence_recovery);
        },
    }
    return node_address;
}

// Parser for Symbol "_AugmentedStart" with index 69
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
                        if (try llTryRecoveryRule_62(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_special_EOF(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_62(context, occurrence_recovery)) {
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_74(context, occurrence_recovery);
        },
    }
}

// Parser for Symbol "special_EOF" with index 70
inline fn parse_special_EOF(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        0 => { // '\x00'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_75(context, occurrence_recovery);
        },
    }
}


// AST-Suppressed Parser for Symbol "_Utf8Scalar" with index 42
fn parse__Utf8Scalar_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("_Utf8Scalar") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8Scalar -> _Utf8TwoByte\n", .{});
                }
            }
            parse__Utf8TwoByte_(context, null) catch |err| switch (err) {
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
                    std.debug.print("Reduction: _Utf8Scalar <~ _Utf8TwoByte\n", .{});
                }
            }        },
        224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239 => { // '\xe0', '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xed', '\xee', '\xef'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8Scalar -> _Utf8ThreeByte\n", .{});
                }
            }
            parse__Utf8ThreeByte_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_67(context, occurrence_recovery)) {
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
            }        },
        240, 241, 242, 243, 244 => { // '\xf0', '\xf1', '\xf2', '\xf3', '\xf4'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8Scalar -> _Utf8FourByte\n", .{});
                }
            }
            parse__Utf8FourByte_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_68(context, occurrence_recovery)) {
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_76(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "_Utf8TwoByte" with index 43
fn parse__Utf8TwoByte_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("_Utf8TwoByte") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8TwoByte -> 'utf8_lead_two', 'utf8_continuation'\n", .{});
                }
            }
            parse_generative_terminal_utf8_lead_two_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_72(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_72(context, occurrence_recovery)) {
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_77(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "_Utf8ThreeByte" with index 44
fn parse__Utf8ThreeByte_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("_Utf8ThreeByte") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        224 => { // '\xe0'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8ThreeByte -> '\\xe0', 'utf8_continuation_a0_bf', 'utf8_continuation'\n", .{});
                }
            }
            parse_terminal__x92xe0_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_69(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_a0_bf_(context, null) catch |err| switch (err) {
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
                    std.debug.print("Reduction: _Utf8ThreeByte <~ '\\xe0', 'utf8_continuation_a0_bf', 'utf8_continuation'\n", .{});
                }
            }        },
        225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 238, 239 => { // '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xee', '\xef'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8ThreeByte -> 'utf8_lead_three_general', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
            parse_generative_terminal_utf8_lead_three_general_(context, null) catch |err| switch (err) {
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
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_70(context, occurrence_recovery)) {
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
            }        },
        237 => { // '\xed'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8ThreeByte -> '\\xed', 'utf8_continuation_80_9f', 'utf8_continuation'\n", .{});
                }
            }
            parse_terminal__x92xed_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_71(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_80_9f_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_71(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_71(context, occurrence_recovery)) {
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_78(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "_Utf8FourByte" with index 45
fn parse__Utf8FourByte_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    const push_syntax_error_variable = if (comptime is_syntax_error_stack_enabled) context.pushSyntaxErrorVariable("_Utf8FourByte") else false;
    defer if (push_syntax_error_variable) context.popSyntaxErrorVariable();
    switch (context.head(u8, 0)) {
        240 => { // '\xf0'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8FourByte -> '\\xf0', 'utf8_continuation_90_bf', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
            parse_terminal__x92xf0_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_63(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_90_bf_(context, null) catch |err| switch (err) {
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
                    std.debug.print("Reduction: _Utf8FourByte <~ '\\xf0', 'utf8_continuation_90_bf', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }        },
        241, 242, 243 => { // '\xf1', '\xf2', '\xf3'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8FourByte -> 'utf8_lead_four_general', 'utf8_continuation', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
            parse_generative_terminal_utf8_lead_four_general_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_64(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_64(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_64(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_64(context, occurrence_recovery)) {
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
            }        },
        244 => { // '\xf4'
            if (comptime builtin.mode == .Debug) {
                if (context.verbosityLevel() > 1) {
                    std.debug.print("Rule expansion: _Utf8FourByte -> '\\xf4', 'utf8_continuation_80_8f', 'utf8_continuation', 'utf8_continuation'\n", .{});
                }
            }
            parse_terminal__x92xf4_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_65(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 0
            parse_generative_terminal_utf8_continuation_80_8f_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_65(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 1
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_65(context, occurrence_recovery)) {
                            return;
                        }
                        return err;
                    },
                    else => return err,
                }; // child 2
            parse_generative_terminal_utf8_continuation_(context, null) catch |err| switch (err) {
                    error.ExplicitSyntaxRecovery => {
                        if (try llTryRecoveryRule_65(context, occurrence_recovery)) {
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
            }        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_79(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "generative_terminal_utf8_lead_two" with index 46
inline fn parse_generative_terminal_utf8_lead_two_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223 => { // '\xc2', '\xc3', '\xc4', '\xc5', '\xc6', '\xc7', '\xc8', '\xc9', '\xca', '\xcb', '\xcc', '\xcd', '\xce', '\xcf', '\xd0', '\xd1', '\xd2', '\xd3', '\xd4', '\xd5', '\xd6', '\xd7', '\xd8', '\xd9', '\xda', '\xdb', '\xdc', '\xdd', '\xde', '\xdf'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_80(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "generative_terminal_utf8_continuation" with index 47
inline fn parse_generative_terminal_utf8_continuation_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191 => { // '\x80', '\x81', '\x82', '\x83', '\x84', '\x85', '\x86', '\x87', '\x88', '\x89', '\x8a', '\x8b', '\x8c', '\x8d', '\x8e', '\x8f', '\x90', '\x91', '\x92', '\x93', '\x94', '\x95', '\x96', '\x97', '\x98', '\x99', '\x9a', '\x9b', '\x9c', '\x9d', '\x9e', '\x9f', '\xa0', '\xa1', '\xa2', '\xa3', '\xa4', '\xa5', '\xa6', '\xa7', '\xa8', '\xa9', '\xaa', '\xab', '\xac', '\xad', '\xae', '\xaf', '\xb0', '\xb1', '\xb2', '\xb3', '\xb4', '\xb5', '\xb6', '\xb7', '\xb8', '\xb9', '\xba', '\xbb', '\xbc', '\xbd', '\xbe', '\xbf'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_81(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "terminal_\xe0" with index 48
inline fn parse_terminal__x92xe0_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        224 => { // '\xe0'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_82(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "generative_terminal_utf8_continuation_a0_bf" with index 49
inline fn parse_generative_terminal_utf8_continuation_a0_bf_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191 => { // '\xa0', '\xa1', '\xa2', '\xa3', '\xa4', '\xa5', '\xa6', '\xa7', '\xa8', '\xa9', '\xaa', '\xab', '\xac', '\xad', '\xae', '\xaf', '\xb0', '\xb1', '\xb2', '\xb3', '\xb4', '\xb5', '\xb6', '\xb7', '\xb8', '\xb9', '\xba', '\xbb', '\xbc', '\xbd', '\xbe', '\xbf'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_83(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "generative_terminal_utf8_lead_three_general" with index 50
inline fn parse_generative_terminal_utf8_lead_three_general_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 238, 239 => { // '\xe1', '\xe2', '\xe3', '\xe4', '\xe5', '\xe6', '\xe7', '\xe8', '\xe9', '\xea', '\xeb', '\xec', '\xee', '\xef'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_84(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "terminal_\xed" with index 51
inline fn parse_terminal__x92xed_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        237 => { // '\xed'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_85(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "generative_terminal_utf8_continuation_80_9f" with index 52
inline fn parse_generative_terminal_utf8_continuation_80_9f_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159 => { // '\x80', '\x81', '\x82', '\x83', '\x84', '\x85', '\x86', '\x87', '\x88', '\x89', '\x8a', '\x8b', '\x8c', '\x8d', '\x8e', '\x8f', '\x90', '\x91', '\x92', '\x93', '\x94', '\x95', '\x96', '\x97', '\x98', '\x99', '\x9a', '\x9b', '\x9c', '\x9d', '\x9e', '\x9f'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_86(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "terminal_\xf0" with index 53
inline fn parse_terminal__x92xf0_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        240 => { // '\xf0'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_87(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "generative_terminal_utf8_continuation_90_bf" with index 54
inline fn parse_generative_terminal_utf8_continuation_90_bf_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191 => { // '\x90', '\x91', '\x92', '\x93', '\x94', '\x95', '\x96', '\x97', '\x98', '\x99', '\x9a', '\x9b', '\x9c', '\x9d', '\x9e', '\x9f', '\xa0', '\xa1', '\xa2', '\xa3', '\xa4', '\xa5', '\xa6', '\xa7', '\xa8', '\xa9', '\xaa', '\xab', '\xac', '\xad', '\xae', '\xaf', '\xb0', '\xb1', '\xb2', '\xb3', '\xb4', '\xb5', '\xb6', '\xb7', '\xb8', '\xb9', '\xba', '\xbb', '\xbc', '\xbd', '\xbe', '\xbf'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_88(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "generative_terminal_utf8_lead_four_general" with index 55
inline fn parse_generative_terminal_utf8_lead_four_general_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        241, 242, 243 => { // '\xf1', '\xf2', '\xf3'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_89(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "terminal_\xf4" with index 56
inline fn parse_terminal__x92xf4_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        244 => { // '\xf4'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_90(context, occurrence_recovery);
        },
    }
}

// AST-Suppressed Parser for Symbol "generative_terminal_utf8_continuation_80_8f" with index 57
inline fn parse_generative_terminal_utf8_continuation_80_8f_(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    switch (context.head(u8, 0)) {
        128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143 => { // '\x80', '\x81', '\x82', '\x83', '\x84', '\x85', '\x86', '\x87', '\x88', '\x89', '\x8a', '\x8b', '\x8c', '\x8d', '\x8e', '\x8f'
            context.releaseToken(1);
        },
        else => {
            @branchHint(.unlikely);
            return ll_syntax_error_91(context, occurrence_recovery);
        },
    }
}


fn ll_syntax_error_0(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"Start"} }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
    context.setPendingSyntaxErrorSite(0);
    if (try llTryRecoverySelection_0(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_1(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"Rules"} }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
    context.setPendingSyntaxErrorSite(1);
    if (try llTryRecoverySelection_1(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_2(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"Rule"} }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
    context.setPendingSyntaxErrorSite(2);
    if (try llTryRecoverySelection_2(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_3(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"RulesTail"} }, &[_][]const u8{"\x00", "\n"});
    context.setPendingSyntaxErrorSite(3);
    if (try llTryRecoverySelection_3(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_4(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"NewLines"} }, &[_][]const u8{"\n"});
    context.setPendingSyntaxErrorSite(4);
    if (try llTryRecoverySelection_4(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_5(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"new_line"} }, &[_][]const u8{"\n"});
    context.setPendingSyntaxErrorSite(5);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_6(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"NewLinesTail"} }, &[_][]const u8{"\n", "#", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
    context.setPendingSyntaxErrorSite(6);
    if (try llTryRecoverySelection_6(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_7(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"#"} }, &[_][]const u8{"#"});
    context.setPendingSyntaxErrorSite(7);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_8(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"AnyContent"} }, &[_][]const u8{"\x01", "\x02", "\t", "\x0b", "\x0c", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
    context.setPendingSyntaxErrorSite(8);
    if (try llTryRecoverySelection_8(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_9(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"VariableSymbol"} }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
    context.setPendingSyntaxErrorSite(9);
    if (try llTryRecoverySelection_9(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_10(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"AnnotationTail"} }, &[_][]const u8{"\n", " ", "@"});
    context.setPendingSyntaxErrorSite(10);
    if (try llTryRecoverySelection_10(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_11(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"RightHandSides"} }, &[_][]const u8{"#", "|"});
    context.setPendingSyntaxErrorSite(11);
    if (try llTryRecoverySelection_11(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_12(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"RightHandSideLine"} }, &[_][]const u8{"#", "|"});
    context.setPendingSyntaxErrorSite(12);
    if (try llTryRecoverySelection_12(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_13(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"RightHandSidesTail"} }, &[_][]const u8{"\x00", "\n", "#", "|"});
    context.setPendingSyntaxErrorSite(13);
    if (try llTryRecoverySelection_13(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_14(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"|"} }, &[_][]const u8{"|"});
    context.setPendingSyntaxErrorSite(14);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_15(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"RightHandSide"} }, &[_][]const u8{"\n", " "});
    context.setPendingSyntaxErrorSite(15);
    if (try llTryRecoverySelection_15(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_16(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"space"} }, &[_][]const u8{" "});
    context.setPendingSyntaxErrorSite(16);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_17(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"Symbol"} }, &[_][]const u8{"\""});
    context.setPendingSyntaxErrorSite(17);
    if (try llTryRecoverySelection_17(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_18(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"Symbol"} }, &[_][]const u8{"\"", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "\\", "_", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(18);
    if (try llTryRecoverySelection_17(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_19(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"RightHandSideTail"} }, &[_][]const u8{"\n", " "});
    context.setPendingSyntaxErrorSite(19);
    if (try llTryRecoverySelection_18(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_20(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"TerminalSymbol"} }, &[_][]const u8{"\""});
    context.setPendingSyntaxErrorSite(20);
    if (try llTryRecoverySelection_19(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_21(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"TerminalSymbol"} }, &[_][]const u8{"\"", "\\"});
    context.setPendingSyntaxErrorSite(21);
    if (try llTryRecoverySelection_19(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_22(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"GenerativeTerminalSymbol"} }, &[_][]const u8{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(22);
    if (try llTryRecoverySelection_20(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_23(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"UppercaseId"} }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"});
    context.setPendingSyntaxErrorSite(23);
    if (try llTryRecoverySelection_21(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_24(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"_"} }, &[_][]const u8{"_"});
    context.setPendingSyntaxErrorSite(24);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_25(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"RawString"} }, &[_][]const u8{"\\\""});
    context.setPendingSyntaxErrorSite(25);
    if (try llTryRecoverySelection_23(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_26(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"\""} }, &[_][]const u8{"\""});
    context.setPendingSyntaxErrorSite(26);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_27(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"SimpleStringContent"} }, &[_][]const u8{"\t", "\n", "\x0b", "\x0c", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~", "\xc2", "\xc3", "\xc4", "\xc5", "\xc6", "\xc7", "\xc8", "\xc9", "\xca", "\xcb", "\xcc", "\xcd", "\xce", "\xcf", "\xd0", "\xd1", "\xd2", "\xd3", "\xd4", "\xd5", "\xd6", "\xd7", "\xd8", "\xd9", "\xda", "\xdb", "\xdc", "\xdd", "\xde", "\xdf", "\xe0", "\xe1", "\xe2", "\xe3", "\xe4", "\xe5", "\xe6", "\xe7", "\xe8", "\xe9", "\xea", "\xeb", "\xec", "\xed", "\xee", "\xef", "\xf0", "\xf1", "\xf2", "\xf3", "\xf4"});
    context.setPendingSyntaxErrorSite(27);
    if (try llTryRecoverySelection_25(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_28(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"\\\""} }, &[_][]const u8{"\\\""});
    context.setPendingSyntaxErrorSite(28);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_29(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"RawIndicator"} }, &[_][]const u8{"\t", "\x0b", "\x0c", "\r", " ", "!", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
    context.setPendingSyntaxErrorSite(29);
    if (try llTryRecoverySelection_27(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_30(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"character^\"\\u{22}\"^\"\\n\"^\"\\u{5c}\""} }, &[_][]const u8{"\t", "\x0b", "\x0c", "\r", " ", "!", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
    context.setPendingSyntaxErrorSite(30);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_31(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"LowercaseId"} }, &[_][]const u8{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(31);
    if (try llTryRecoverySelection_29(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_32(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"GenerativeTerminalExceptions"} }, &[_][]const u8{"\n", " ", "@", "^"});
    context.setPendingSyntaxErrorSite(32);
    if (try llTryRecoverySelection_30(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_33(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"^"} }, &[_][]const u8{"^"});
    context.setPendingSyntaxErrorSite(33);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_34(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"@"} }, &[_][]const u8{"@"});
    context.setPendingSyntaxErrorSite(34);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_35(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"Annotation"} }, &[_][]const u8{"!", ">", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(35);
    if (try llTryRecoverySelection_33(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_36(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"Procedure"} }, &[_][]const u8{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(36);
    if (try llTryRecoverySelection_34(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_37(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"!"} }, &[_][]const u8{"!"});
    context.setPendingSyntaxErrorSite(37);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_38(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"RecoveryPoint"} }, &[_][]const u8{"\""});
    context.setPendingSyntaxErrorSite(38);
    if (try llTryRecoverySelection_36(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_39(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"RecoveryPoint"} }, &[_][]const u8{"\"", "\\", "^"});
    context.setPendingSyntaxErrorSite(39);
    if (try llTryRecoverySelection_36(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_40(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{">"} }, &[_][]const u8{">"});
    context.setPendingSyntaxErrorSite(40);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_41(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"VerbatimMarker"} }, &[_][]const u8{"\""});
    context.setPendingSyntaxErrorSite(41);
    if (try llTryRecoverySelection_38(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_42(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"VerbatimMarker"} }, &[_][]const u8{"\"", ">", "\\", "^"});
    context.setPendingSyntaxErrorSite(42);
    if (try llTryRecoverySelection_38(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_43(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"CamelCaseId"} }, &[_][]const u8{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(43);
    if (try llTryRecoverySelection_39(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_44(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"TerminalAndCursor"} }, &[_][]const u8{"\""});
    context.setPendingSyntaxErrorSite(44);
    if (try llTryRecoverySelection_40(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_45(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"TerminalAndCursor"} }, &[_][]const u8{"\"", "\\", "^"});
    context.setPendingSyntaxErrorSite(45);
    if (try llTryRecoverySelection_40(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_46(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"character^\"\\u{22}\""} }, &[_][]const u8{"\t", "\n", "\x0b", "\x0c", "\r", " ", "!", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
    context.setPendingSyntaxErrorSite(46);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_47(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"_Utf8Scalar"} }, &[_][]const u8{"\xc2", "\xc3", "\xc4", "\xc5", "\xc6", "\xc7", "\xc8", "\xc9", "\xca", "\xcb", "\xcc", "\xcd", "\xce", "\xcf", "\xd0", "\xd1", "\xd2", "\xd3", "\xd4", "\xd5", "\xd6", "\xd7", "\xd8", "\xd9", "\xda", "\xdb", "\xdc", "\xdd", "\xde", "\xdf", "\xe0", "\xe1", "\xe2", "\xe3", "\xe4", "\xe5", "\xe6", "\xe7", "\xe8", "\xe9", "\xea", "\xeb", "\xec", "\xed", "\xee", "\xef", "\xf0", "\xf1", "\xf2", "\xf3", "\xf4"});
    context.setPendingSyntaxErrorSite(47);
    if (try llTryRecoverySelection_42(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_48(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"_Utf8TwoByte"} }, &[_][]const u8{"\xc2", "\xc3", "\xc4", "\xc5", "\xc6", "\xc7", "\xc8", "\xc9", "\xca", "\xcb", "\xcc", "\xcd", "\xce", "\xcf", "\xd0", "\xd1", "\xd2", "\xd3", "\xd4", "\xd5", "\xd6", "\xd7", "\xd8", "\xd9", "\xda", "\xdb", "\xdc", "\xdd", "\xde", "\xdf"});
    context.setPendingSyntaxErrorSite(48);
    if (try llTryRecoverySelection_43(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_49(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"_Utf8ThreeByte"} }, &[_][]const u8{"\xe0", "\xe1", "\xe2", "\xe3", "\xe4", "\xe5", "\xe6", "\xe7", "\xe8", "\xe9", "\xea", "\xeb", "\xec", "\xed", "\xee", "\xef"});
    context.setPendingSyntaxErrorSite(49);
    if (try llTryRecoverySelection_44(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_50(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"_Utf8FourByte"} }, &[_][]const u8{"\xf0", "\xf1", "\xf2", "\xf3", "\xf4"});
    context.setPendingSyntaxErrorSite(50);
    if (try llTryRecoverySelection_45(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_51(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"utf8_lead_two"} }, &[_][]const u8{"\xc2", "\xc3", "\xc4", "\xc5", "\xc6", "\xc7", "\xc8", "\xc9", "\xca", "\xcb", "\xcc", "\xcd", "\xce", "\xcf", "\xd0", "\xd1", "\xd2", "\xd3", "\xd4", "\xd5", "\xd6", "\xd7", "\xd8", "\xd9", "\xda", "\xdb", "\xdc", "\xdd", "\xde", "\xdf"});
    context.setPendingSyntaxErrorSite(51);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_52(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"utf8_continuation"} }, &[_][]const u8{"\x80", "\x81", "\x82", "\x83", "\x84", "\x85", "\x86", "\x87", "\x88", "\x89", "\x8a", "\x8b", "\x8c", "\x8d", "\x8e", "\x8f", "\x90", "\x91", "\x92", "\x93", "\x94", "\x95", "\x96", "\x97", "\x98", "\x99", "\x9a", "\x9b", "\x9c", "\x9d", "\x9e", "\x9f", "\xa0", "\xa1", "\xa2", "\xa3", "\xa4", "\xa5", "\xa6", "\xa7", "\xa8", "\xa9", "\xaa", "\xab", "\xac", "\xad", "\xae", "\xaf", "\xb0", "\xb1", "\xb2", "\xb3", "\xb4", "\xb5", "\xb6", "\xb7", "\xb8", "\xb9", "\xba", "\xbb", "\xbc", "\xbd", "\xbe", "\xbf"});
    context.setPendingSyntaxErrorSite(52);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_53(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"\xe0"} }, &[_][]const u8{"\xe0"});
    context.setPendingSyntaxErrorSite(53);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_54(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"utf8_continuation_a0_bf"} }, &[_][]const u8{"\xa0", "\xa1", "\xa2", "\xa3", "\xa4", "\xa5", "\xa6", "\xa7", "\xa8", "\xa9", "\xaa", "\xab", "\xac", "\xad", "\xae", "\xaf", "\xb0", "\xb1", "\xb2", "\xb3", "\xb4", "\xb5", "\xb6", "\xb7", "\xb8", "\xb9", "\xba", "\xbb", "\xbc", "\xbd", "\xbe", "\xbf"});
    context.setPendingSyntaxErrorSite(54);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_55(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"utf8_lead_three_general"} }, &[_][]const u8{"\xe1", "\xe2", "\xe3", "\xe4", "\xe5", "\xe6", "\xe7", "\xe8", "\xe9", "\xea", "\xeb", "\xec", "\xee", "\xef"});
    context.setPendingSyntaxErrorSite(55);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_56(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"\xed"} }, &[_][]const u8{"\xed"});
    context.setPendingSyntaxErrorSite(56);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_57(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"utf8_continuation_80_9f"} }, &[_][]const u8{"\x80", "\x81", "\x82", "\x83", "\x84", "\x85", "\x86", "\x87", "\x88", "\x89", "\x8a", "\x8b", "\x8c", "\x8d", "\x8e", "\x8f", "\x90", "\x91", "\x92", "\x93", "\x94", "\x95", "\x96", "\x97", "\x98", "\x99", "\x9a", "\x9b", "\x9c", "\x9d", "\x9e", "\x9f"});
    context.setPendingSyntaxErrorSite(57);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_58(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"\xf0"} }, &[_][]const u8{"\xf0"});
    context.setPendingSyntaxErrorSite(58);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_59(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"utf8_continuation_90_bf"} }, &[_][]const u8{"\x90", "\x91", "\x92", "\x93", "\x94", "\x95", "\x96", "\x97", "\x98", "\x99", "\x9a", "\x9b", "\x9c", "\x9d", "\x9e", "\x9f", "\xa0", "\xa1", "\xa2", "\xa3", "\xa4", "\xa5", "\xa6", "\xa7", "\xa8", "\xa9", "\xaa", "\xab", "\xac", "\xad", "\xae", "\xaf", "\xb0", "\xb1", "\xb2", "\xb3", "\xb4", "\xb5", "\xb6", "\xb7", "\xb8", "\xb9", "\xba", "\xbb", "\xbc", "\xbd", "\xbe", "\xbf"});
    context.setPendingSyntaxErrorSite(59);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_60(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"utf8_lead_four_general"} }, &[_][]const u8{"\xf1", "\xf2", "\xf3"});
    context.setPendingSyntaxErrorSite(60);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_61(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"\xf4"} }, &[_][]const u8{"\xf4"});
    context.setPendingSyntaxErrorSite(61);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_62(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"utf8_continuation_80_8f"} }, &[_][]const u8{"\x80", "\x81", "\x82", "\x83", "\x84", "\x85", "\x86", "\x87", "\x88", "\x89", "\x8a", "\x8b", "\x8c", "\x8d", "\x8e", "\x8f"});
    context.setPendingSyntaxErrorSite(62);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_63(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"ControlCharacter"} }, &[_][]const u8{"\x01", "\x02"});
    context.setPendingSyntaxErrorSite(63);
    if (try llTryRecoverySelection_58(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_64(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"\x01"} }, &[_][]const u8{"\x01"});
    context.setPendingSyntaxErrorSite(64);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_65(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"\x02"} }, &[_][]const u8{"\x02"});
    context.setPendingSyntaxErrorSite(65);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_66(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"character^\"\\n\""} }, &[_][]const u8{"\t", "\x0b", "\x0c", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
    context.setPendingSyntaxErrorSite(66);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_67(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"AnyContentTail"} }, &[_][]const u8{"\x01", "\x02", "\t", "\n", "\x0b", "\x0c", "\r", " ", "!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]", "^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{", "|", "}", "~"});
    context.setPendingSyntaxErrorSite(67);
    if (try llTryRecoverySelection_62(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_68(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"IdTail"} }, &[_][]const u8{"\n", " ", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "^", "_", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(68);
    if (try llTryRecoverySelection_63(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_69(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"letter"} }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(69);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_70(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"digit"} }, &[_][]const u8{"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"});
    context.setPendingSyntaxErrorSite(70);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_71(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"lowercase_letter"} }, &[_][]const u8{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(71);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_72(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"uppercase_letter"} }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"});
    context.setPendingSyntaxErrorSite(72);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_73(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!data_structures.Node.Pointer {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"CamelCaseIdTail"} }, &[_][]const u8{"\n", " ", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"});
    context.setPendingSyntaxErrorSite(73);
    if (try llTryRecoverySelection_68(context, occurrence_recovery)) {
        return data_structures.Node.invalid_pointer;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_74(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"_AugmentedStart"} }, &[_][]const u8{"A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "_"});
    context.setPendingSyntaxErrorSite(74);
    if (try llTryRecoverySelection_69(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_75(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"\x00"} }, &[_][]const u8{"\x00"});
    context.setPendingSyntaxErrorSite(75);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_76(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"_Utf8Scalar"} }, &[_][]const u8{"\xc2", "\xc3", "\xc4", "\xc5", "\xc6", "\xc7", "\xc8", "\xc9", "\xca", "\xcb", "\xcc", "\xcd", "\xce", "\xcf", "\xd0", "\xd1", "\xd2", "\xd3", "\xd4", "\xd5", "\xd6", "\xd7", "\xd8", "\xd9", "\xda", "\xdb", "\xdc", "\xdd", "\xde", "\xdf", "\xe0", "\xe1", "\xe2", "\xe3", "\xe4", "\xe5", "\xe6", "\xe7", "\xe8", "\xe9", "\xea", "\xeb", "\xec", "\xed", "\xee", "\xef", "\xf0", "\xf1", "\xf2", "\xf3", "\xf4"});
    context.setPendingSyntaxErrorSite(76);
    if (try llTryRecoverySelection_42(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_77(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"_Utf8TwoByte"} }, &[_][]const u8{"\xc2", "\xc3", "\xc4", "\xc5", "\xc6", "\xc7", "\xc8", "\xc9", "\xca", "\xcb", "\xcc", "\xcd", "\xce", "\xcf", "\xd0", "\xd1", "\xd2", "\xd3", "\xd4", "\xd5", "\xd6", "\xd7", "\xd8", "\xd9", "\xda", "\xdb", "\xdc", "\xdd", "\xde", "\xdf"});
    context.setPendingSyntaxErrorSite(77);
    if (try llTryRecoverySelection_43(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_78(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"_Utf8ThreeByte"} }, &[_][]const u8{"\xe0", "\xe1", "\xe2", "\xe3", "\xe4", "\xe5", "\xe6", "\xe7", "\xe8", "\xe9", "\xea", "\xeb", "\xec", "\xed", "\xee", "\xef"});
    context.setPendingSyntaxErrorSite(78);
    if (try llTryRecoverySelection_44(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_79(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"_Utf8FourByte"} }, &[_][]const u8{"\xf0", "\xf1", "\xf2", "\xf3", "\xf4"});
    context.setPendingSyntaxErrorSite(79);
    if (try llTryRecoverySelection_45(context, occurrence_recovery)) {
        return;
    }
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_80(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"utf8_lead_two"} }, &[_][]const u8{"\xc2", "\xc3", "\xc4", "\xc5", "\xc6", "\xc7", "\xc8", "\xc9", "\xca", "\xcb", "\xcc", "\xcd", "\xce", "\xcf", "\xd0", "\xd1", "\xd2", "\xd3", "\xd4", "\xd5", "\xd6", "\xd7", "\xd8", "\xd9", "\xda", "\xdb", "\xdc", "\xdd", "\xde", "\xdf"});
    context.setPendingSyntaxErrorSite(80);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_81(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"utf8_continuation"} }, &[_][]const u8{"\x80", "\x81", "\x82", "\x83", "\x84", "\x85", "\x86", "\x87", "\x88", "\x89", "\x8a", "\x8b", "\x8c", "\x8d", "\x8e", "\x8f", "\x90", "\x91", "\x92", "\x93", "\x94", "\x95", "\x96", "\x97", "\x98", "\x99", "\x9a", "\x9b", "\x9c", "\x9d", "\x9e", "\x9f", "\xa0", "\xa1", "\xa2", "\xa3", "\xa4", "\xa5", "\xa6", "\xa7", "\xa8", "\xa9", "\xaa", "\xab", "\xac", "\xad", "\xae", "\xaf", "\xb0", "\xb1", "\xb2", "\xb3", "\xb4", "\xb5", "\xb6", "\xb7", "\xb8", "\xb9", "\xba", "\xbb", "\xbc", "\xbd", "\xbe", "\xbf"});
    context.setPendingSyntaxErrorSite(81);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_82(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"\xe0"} }, &[_][]const u8{"\xe0"});
    context.setPendingSyntaxErrorSite(82);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_83(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"utf8_continuation_a0_bf"} }, &[_][]const u8{"\xa0", "\xa1", "\xa2", "\xa3", "\xa4", "\xa5", "\xa6", "\xa7", "\xa8", "\xa9", "\xaa", "\xab", "\xac", "\xad", "\xae", "\xaf", "\xb0", "\xb1", "\xb2", "\xb3", "\xb4", "\xb5", "\xb6", "\xb7", "\xb8", "\xb9", "\xba", "\xbb", "\xbc", "\xbd", "\xbe", "\xbf"});
    context.setPendingSyntaxErrorSite(83);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_84(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"utf8_lead_three_general"} }, &[_][]const u8{"\xe1", "\xe2", "\xe3", "\xe4", "\xe5", "\xe6", "\xe7", "\xe8", "\xe9", "\xea", "\xeb", "\xec", "\xee", "\xef"});
    context.setPendingSyntaxErrorSite(84);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_85(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"\xed"} }, &[_][]const u8{"\xed"});
    context.setPendingSyntaxErrorSite(85);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_86(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"utf8_continuation_80_9f"} }, &[_][]const u8{"\x80", "\x81", "\x82", "\x83", "\x84", "\x85", "\x86", "\x87", "\x88", "\x89", "\x8a", "\x8b", "\x8c", "\x8d", "\x8e", "\x8f", "\x90", "\x91", "\x92", "\x93", "\x94", "\x95", "\x96", "\x97", "\x98", "\x99", "\x9a", "\x9b", "\x9c", "\x9d", "\x9e", "\x9f"});
    context.setPendingSyntaxErrorSite(86);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_87(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"\xf0"} }, &[_][]const u8{"\xf0"});
    context.setPendingSyntaxErrorSite(87);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_88(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"utf8_continuation_90_bf"} }, &[_][]const u8{"\x90", "\x91", "\x92", "\x93", "\x94", "\x95", "\x96", "\x97", "\x98", "\x99", "\x9a", "\x9b", "\x9c", "\x9d", "\x9e", "\x9f", "\xa0", "\xa1", "\xa2", "\xa3", "\xa4", "\xa5", "\xa6", "\xa7", "\xa8", "\xa9", "\xaa", "\xab", "\xac", "\xad", "\xae", "\xaf", "\xb0", "\xb1", "\xb2", "\xb3", "\xb4", "\xb5", "\xb6", "\xb7", "\xb8", "\xb9", "\xba", "\xbb", "\xbc", "\xbd", "\xbe", "\xbf"});
    context.setPendingSyntaxErrorSite(88);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_89(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"utf8_lead_four_general"} }, &[_][]const u8{"\xf1", "\xf2", "\xf3"});
    context.setPendingSyntaxErrorSite(89);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_90(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"\xf4"} }, &[_][]const u8{"\xf4"});
    context.setPendingSyntaxErrorSite(90);
    _ = occurrence_recovery;
    return error.ExplicitSyntaxRecovery;
}

fn ll_syntax_error_91(context: *data_structures.Context, occurrence_recovery: ?*const ExplicitRecoveryScope) anyerror!void {
    @branchHint(.cold);
    try context.recordSyntaxDiagnostic(.{ .while_parsing = &[_][]const u8{"utf8_continuation_80_8f"} }, &[_][]const u8{"\x80", "\x81", "\x82", "\x83", "\x84", "\x85", "\x86", "\x87", "\x88", "\x89", "\x8a", "\x8b", "\x8c", "\x8d", "\x8e", "\x8f"});
    context.setPendingSyntaxErrorSite(91);
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        8 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_AnyContent__expected_ControlCharacter_or_generative_terminal_character_x94_x34_x92_x92n_x34"))
                @field(error_messages, "syntax_error_ll_AnyContent__expected_ControlCharacter_or_generative_terminal_character_x94_x34_x92_x92n_x34")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        10 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_AnnotationTail__expected_end_of_AnnotationTail_or_terminal__x64"))
                @field(error_messages, "syntax_error_ll_AnnotationTail__expected_end_of_AnnotationTail_or_terminal__x64")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_AnnotationTail"))
                @field(error_messages, "syntax_error_ll_AnnotationTail")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        11 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        12 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        13 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        14 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        15 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        16 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        17 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_Symbol__expected_TerminalSymbol"))
                @field(error_messages, "syntax_error_ll_Symbol__expected_TerminalSymbol")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        20 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_TerminalSymbol__expected_RawString"))
                @field(error_messages, "syntax_error_ll_TerminalSymbol__expected_RawString")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        21 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_TerminalSymbol__expected_RawString_or_terminal__x34"))
                @field(error_messages, "syntax_error_ll_TerminalSymbol__expected_RawString_or_terminal__x34")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        22 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        23 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        24 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        25 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_RawString__expected_terminal__x92_x92_x34"))
                @field(error_messages, "syntax_error_ll_RawString__expected_terminal__x92_x92_x34")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_RawString"))
                @field(error_messages, "syntax_error_ll_RawString")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        26 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        27 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_SimpleStringContent__expected__Utf8Scalar_or_end_of_SimpleStringContent_or_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34"))
                @field(error_messages, "syntax_error_ll_SimpleStringContent__expected__Utf8Scalar_or_end_of_SimpleStringContent_or_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        28 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92_x92_x34__expected_terminal__x92_x92_x34"))
                @field(error_messages, "syntax_error_ll_terminal__x92_x92_x34__expected_terminal__x92_x92_x34")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92_x92_x34"))
                @field(error_messages, "syntax_error_ll_terminal__x92_x92_x34")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        29 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_RawIndicator__expected_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34_x94_x34_x92_x92n_x34_x94_x34_x92_x92u_x1235c_x125_x34"))
                @field(error_messages, "syntax_error_ll_RawIndicator__expected_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34_x94_x34_x92_x92n_x34_x94_x34_x92_x92u_x1235c_x125_x34")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_RawIndicator"))
                @field(error_messages, "syntax_error_ll_RawIndicator")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        30 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34_x94_x34_x92_x92n_x34_x94_x34_x92_x92u_x1235c_x125_x34__expected_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34_x94_x34_x92_x92n_x34_x94_x34_x92_x92u_x1235c_x125_x34"))
                @field(error_messages, "syntax_error_ll_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34_x94_x34_x92_x92n_x34_x94_x34_x92_x92u_x1235c_x125_x34__expected_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34_x94_x34_x92_x92n_x34_x94_x34_x92_x92u_x1235c_x125_x34")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34_x94_x34_x92_x92n_x34_x94_x34_x92_x92u_x1235c_x125_x34"))
                @field(error_messages, "syntax_error_ll_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34_x94_x34_x92_x92n_x34_x94_x34_x92_x92u_x1235c_x125_x34")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        31 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        32 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        33 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        34 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        35 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_Annotation__expected_Procedure_or_terminal__x33_or_terminal__x62"))
                @field(error_messages, "syntax_error_ll_Annotation__expected_Procedure_or_terminal__x33_or_terminal__x62")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_Annotation"))
                @field(error_messages, "syntax_error_ll_Annotation")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        36 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_Procedure__expected_CamelCaseId"))
                @field(error_messages, "syntax_error_ll_Procedure__expected_CamelCaseId")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_Procedure"))
                @field(error_messages, "syntax_error_ll_Procedure")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        37 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        38 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_RecoveryPoint__expected_TerminalAndCursor"))
                @field(error_messages, "syntax_error_ll_RecoveryPoint__expected_TerminalAndCursor")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        39 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_RecoveryPoint__expected_TerminalAndCursor"))
                @field(error_messages, "syntax_error_ll_RecoveryPoint__expected_TerminalAndCursor")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        40 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x62__expected_terminal__x62"))
                @field(error_messages, "syntax_error_ll_terminal__x62__expected_terminal__x62")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x62"))
                @field(error_messages, "syntax_error_ll_terminal__x62")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        41 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_VerbatimMarker__expected_TerminalAndCursor"))
                @field(error_messages, "syntax_error_ll_VerbatimMarker__expected_TerminalAndCursor")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_VerbatimMarker"))
                @field(error_messages, "syntax_error_ll_VerbatimMarker")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        42 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_VerbatimMarker__expected_TerminalAndCursor_or_terminal__x62"))
                @field(error_messages, "syntax_error_ll_VerbatimMarker__expected_TerminalAndCursor_or_terminal__x62")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_VerbatimMarker"))
                @field(error_messages, "syntax_error_ll_VerbatimMarker")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        43 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        44 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_TerminalAndCursor__expected_TerminalSymbol"))
                @field(error_messages, "syntax_error_ll_TerminalAndCursor__expected_TerminalSymbol")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_TerminalAndCursor"))
                @field(error_messages, "syntax_error_ll_TerminalAndCursor")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        45 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_TerminalAndCursor__expected_TerminalSymbol_or_terminal__x94"))
                @field(error_messages, "syntax_error_ll_TerminalAndCursor__expected_TerminalSymbol_or_terminal__x94")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_TerminalAndCursor"))
                @field(error_messages, "syntax_error_ll_TerminalAndCursor")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        46 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34__expected_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34"))
                @field(error_messages, "syntax_error_ll_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34__expected_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34"))
                @field(error_messages, "syntax_error_ll_generative_terminal_character_x94_x34_x92_x92u_x12322_x125_x34")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        47 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        48 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        49 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        50 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        51 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        52 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        53 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        54 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        55 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        56 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        57 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        58 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        59 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        60 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        61 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        62 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        63 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_ControlCharacter__expected_terminal__x92x01_or_terminal__x92x02"))
                @field(error_messages, "syntax_error_ll_ControlCharacter__expected_terminal__x92x01_or_terminal__x92x02")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        64 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        65 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92x02__expected_terminal__x92x02"))
                @field(error_messages, "syntax_error_ll_terminal__x92x02__expected_terminal__x92x02")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_terminal__x92x02"))
                @field(error_messages, "syntax_error_ll_terminal__x92x02")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        66 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_character_x94_x34_x92_x92n_x34__expected_generative_terminal_character_x94_x34_x92_x92n_x34"))
                @field(error_messages, "syntax_error_ll_generative_terminal_character_x94_x34_x92_x92n_x34__expected_generative_terminal_character_x94_x34_x92_x92n_x34")(.{
                    .allocator = context.runtime().arena_allocator,
                    .context = context,
                    .diagnostic = diagnostic,
                    .style = .ansi,
                }) catch ""
            else if (comptime @hasDecl(error_messages, "syntax_error_ll_generative_terminal_character_x94_x34_x92_x92n_x34"))
                @field(error_messages, "syntax_error_ll_generative_terminal_character_x94_x34_x92_x92n_x34")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        67 => {
            const diagnostic = context.runtime().last_diagnostic.?;
            const diagnostic_message = if (comptime @hasDecl(error_messages, "syntax_error_ll_AnyContentTail__expected_ControlCharacter_or_end_of_AnyContentTail_or_generative_terminal_character_x94_x34_x92_x92n_x34"))
                @field(error_messages, "syntax_error_ll_AnyContentTail__expected_ControlCharacter_or_end_of_AnyContentTail_or_generative_terminal_character_x94_x34_x92_x92n_x34")(.{
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        68 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        69 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        70 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        71 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        72 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        73 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        74 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        75 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        76 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        77 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        78 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        79 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        80 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        81 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        82 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        83 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        84 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        85 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        86 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        87 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        88 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        89 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        90 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
        },
        91 => {
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
            if (context.runtimeConst().syntax_error_reporter) |reporter| reporter(diagnostic_message) else std.debug.print("{s}", .{diagnostic_message});
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
