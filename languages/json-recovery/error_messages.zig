const std = @import("std");
const root = @import("galley");

const Guidance = enum {
    value,
    object_member,
    object_value,
    array_value,
    string,
    number,
    generic,
};

fn syntax(args: root.SyntaxErrorMessageArgs) root.SyntaxDiagnostic {
    return switch (args.diagnostic) {
        .syntax => |diagnostic| diagnostic,
    };
}

fn isName(name: []const u8, expected: []const u8) bool {
    return std.mem.eql(u8, name, expected);
}

fn isObjectScope(name: []const u8) bool {
    return isName(name, "ObjectMembers") or isName(name, "ObjectMembersTail");
}

fn isArrayScope(name: []const u8) bool {
    return isName(name, "ArrayMembers") or isName(name, "ArrayMembersTail");
}

fn isValueSlot(name: []const u8) bool {
    return isName(name, "Value") or isName(name, "_ValueSlot");
}

fn expectsJsonValue(diagnostic: root.SyntaxDiagnostic) bool {
    for (diagnostic.expected_tokens) |expected| {
        if (isName(expected, "-") or
            isName(expected, "0") or
            isName(expected, "1") or
            isName(expected, "2") or
            isName(expected, "3") or
            isName(expected, "4") or
            isName(expected, "5") or
            isName(expected, "6") or
            isName(expected, "7") or
            isName(expected, "8") or
            isName(expected, "9") or
            isName(expected, "[") or
            isName(expected, "f") or
            isName(expected, "n") or
            isName(expected, "t") or
            isName(expected, "{")) return true;
    }
    return false;
}

fn guidanceFromRecovery(diagnostic: root.SyntaxDiagnostic, recovery: root.SyntaxRecovery) ?Guidance {
    return switch (recovery.target) {
        .occurrence => |occurrence| if (isValueSlot(occurrence.variable))
            if (isObjectScope(occurrence.parent_variable))
                .object_value
            else if (isArrayScope(occurrence.parent_variable))
                .array_value
            else
                .value
        else
            null,
        .production => |production| if (isObjectScope(production.variable))
            if (expectsJsonValue(diagnostic)) .object_value else .object_member
        else if (isArrayScope(production.variable))
            .array_value
        else if (isName(production.variable, "Value"))
            if (isName(recovery.terminal, "}")) .object_member else if (isName(recovery.terminal, "]")) .array_value else .value
        else
            null,
        .lhs_variable => |variable| if (isObjectScope(variable))
            .object_member
        else if (isArrayScope(variable))
            .array_value
        else
            null,
    };
}

fn guidanceFromContext(context: root.SyntaxDiagnosticContext) Guidance {
    const name = switch (context) {
        .while_parsing => |name| name,
        .none, .state => return .generic,
    };
    if (isValueSlot(name)) return .value;
    if (isObjectScope(name)) return .object_member;
    if (isArrayScope(name)) return .array_value;
    if (isName(name, "_StringContent")) return .string;
    if (isName(name, "IntegerNumber") or
        isName(name, "_PositiveIntegerNumberTail") or
        isName(name, "FloatTail")) return .number;
    return .generic;
}

fn guidanceFor(diagnostic: root.SyntaxDiagnostic) Guidance {
    if (diagnostic.recovery) |recovery| {
        if (guidanceFromRecovery(diagnostic, recovery)) |guidance| return guidance;
    }
    return guidanceFromContext(diagnostic.context);
}

fn guidanceText(guidance: Guidance) []const u8 {
    return switch (guidance) {
        .value => "Expected a JSON value.\n" ++
            "A value must be an object, array, string, number, `true`, `false`, or `null`.",
        .object_member => "Expected an object member written as `\"key\": value`, or `}` to close the object.\n" ++
            "Object members must be separated by commas.",
        .object_value => "Expected a JSON value after this object's `:`.\n" ++
            "Recovery preserved the next `,` or `}` so later members can still be parsed.",
        .array_value => "Expected a JSON value in this array, or `]` to close the array.\n" ++
            "Array elements must be separated by commas.",
        .string => "Expected valid JSON string content or the closing quote.",
        .number => "Expected a JSON number: digits with an optional leading `-` and fractional part.",
        .generic => "Expected valid JSON syntax.\n" ++
            "Check delimiters, commas, object keys, and the spelling of literal values.",
    };
}

pub fn renderJsonSyntaxError(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    const diagnostic = syntax(args);
    const body = guidanceText(guidanceFor(diagnostic));
    var output: std.Io.Writer.Allocating = .init(args.allocator);
    errdefer output.deinit();
    switch (args.style) {
        .plain => try output.writer.print(
            "SyntaxError at {d}:{d}:\n{s}\nUnexpected token: \"{f}\"\n",
            .{
                diagnostic.line,
                diagnostic.column,
                body,
                root.string_utilities.fmtString(diagnostic.unexpected_token),
            },
        ),
        .ansi => try output.writer.print(
            "\x1b[35mSyntaxError at {d}:{d}:\x1b[0m\n{s}\n" ++
                "\x1b[37mUnexpected token: \x1b[31m\"{f}\"\x1b[0m\n",
            .{
                diagnostic.line,
                diagnostic.column,
                body,
                root.string_utilities.fmtString(diagnostic.unexpected_token),
            },
        ),
    }
    if (diagnostic.recovery) |recovery| try root.formatSyntaxRecovery(&output.writer, recovery);
    return output.toOwnedSlice();
}
