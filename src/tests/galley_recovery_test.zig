const std = @import("std");
const parser = @import("parser-under-test");

fn parseError(input: [:0]const u8) !struct {
    session: parser.Session,
    context: parser.data_structures.Context,
} {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    errdefer session.deinit();
    var context = session._makeContext(.{ .bytes = .{ .input = input[0 .. input.len + 1] } }, null);
    try std.testing.expectError(parser.ParseError.SyntaxError, session._parseContext(&context));
    return .{ .session = session, .context = context };
}

fn syntaxDiagnostic(session: *const parser.Session) parser.SyntaxDiagnostic {
    return switch (session.lastDiagnostic().?) {
        .syntax => |syntax| syntax,
    };
}

fn expectReachedEnd(context: *parser.data_structures.Context, input: [:0]const u8) !void {
    try std.testing.expect(context.pos() >= input.len);
}

test "galley grammar uses explicit recovery" {
    try std.testing.expectEqual(parser.parser.ErrorRecoveryMode.explicit, parser.parser.error_recovery_mode);
}

test "galley grammar recovers a damaged symbol before its newline" {
    const input: [:0]const u8 =
        \\Start
        \\| ?
        \\| "valid"
        \\
    ;
    var parsed = try parseError(input);
    defer parsed.session.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.session.syntaxErrorCount());
    const diagnostic = syntaxDiagnostic(&parsed.session);
    const recovery = diagnostic.recovery orelse return error.MissingRecovery;
    try std.testing.expectEqual(parser.SyntaxRecoveryResume.before, recovery.@"resume");
    try std.testing.expectEqualStrings("\n", recovery.terminal);
    const occurrence = switch (recovery.target) {
        .occurrence => |occurrence| occurrence,
        else => return error.WrongRecoveryTarget,
    };
    try std.testing.expectEqualStrings("Symbol", occurrence.variable);
    if (parser.parser.parser_type == .ll) {
        try std.testing.expectEqualStrings("RightHandSide", occurrence.parent_variable);
        try std.testing.expectEqual(@as(usize, 0), occurrence.rhs_index);
        try std.testing.expectEqual(@as(usize, 1), occurrence.symbol_index);
    } else {
        try std.testing.expectEqualStrings("NonEmptyRightHandSide", occurrence.parent_variable);
        try std.testing.expectEqual(@as(usize, 1), occurrence.rhs_index);
        try std.testing.expectEqual(@as(usize, 0), occurrence.symbol_index);
    }
    try expectReachedEnd(&parsed.context, input);
}

test "galley grammar discards a damaged production line after its newline" {
    const input: [:0]const u8 =
        \\Start
        \\|!
        \\| "also-valid"
        \\
    ;
    var parsed = try parseError(input);
    defer parsed.session.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.session.syntaxErrorCount());
    const diagnostic = syntaxDiagnostic(&parsed.session);
    const recovery = diagnostic.recovery orelse return error.MissingRecovery;
    try std.testing.expectEqual(parser.SyntaxRecoveryResume.after, recovery.@"resume");
    try std.testing.expectEqualStrings("\n", recovery.terminal);
    const variable = switch (recovery.target) {
        .lhs_variable => |variable| variable,
        else => return error.WrongRecoveryTarget,
    };
    try std.testing.expectEqualStrings("RightHandSideLine", variable);
    try expectReachedEnd(&parsed.context, input);
}

test "galley grammar falls back to the next rule separator" {
    const input: [:0]const u8 =
        \\Broken@
        \\| "ignored"
        \\
        \\Next
        \\| "valid"
        \\
    ;
    var parsed = try parseError(input);
    defer parsed.session.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.session.syntaxErrorCount());
    const recovery = syntaxDiagnostic(&parsed.session).recovery orelse return error.MissingRecovery;
    try std.testing.expectEqual(parser.SyntaxRecoveryResume.before, recovery.@"resume");
    try std.testing.expectEqualStrings("\n\n", recovery.terminal);
    const variable = switch (recovery.target) {
        .lhs_variable => |variable| variable,
        else => return error.WrongRecoveryTarget,
    };
    try std.testing.expectEqualStrings("Rule", variable);
    try expectReachedEnd(&parsed.context, input);
}

test "galley grammar fails fast between committed recovery scopes" {
    const input: [:0]const u8 =
        \\Start
        \\| "valid"
        \\
        \\?
        \\Next
        \\| "valid"
        \\
    ;
    var parsed = try parseError(input);
    defer parsed.session.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.session.syntaxErrorCount());
    try std.testing.expect(parsed.context.pos() - 1 < input.len);
    try std.testing.expect(syntaxDiagnostic(&parsed.session).recovery == null);
}
