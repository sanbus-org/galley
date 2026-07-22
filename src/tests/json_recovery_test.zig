const std = @import("std");
const parser = @import("parser-under-test");

const ParsedError = struct {
    session: parser.Session,
    context: parser.data_structures.Context,
};

fn parseError(input: [:0]const u8) !ParsedError {
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

fn expectReachedEnd(parsed: *ParsedError, input: [:0]const u8) !void {
    try std.testing.expect(parsed.context.pos() >= input.len);
}

test "json grammar uses explicit recovery" {
    try std.testing.expectEqual(parser.parser.ErrorRecoveryMode.explicit, parser.parser.error_recovery_mode);
}

test "json recovers damaged array values at sibling boundaries" {
    const input: [:0]const u8 = "[1, ?, 2, ?, 3]";
    var parsed = try parseError(input);
    defer parsed.session.deinit();

    try std.testing.expectEqual(@as(usize, 2), parsed.session.syntaxErrorCount());
    const recovery = syntaxDiagnostic(&parsed.session).recovery orelse return error.MissingRecovery;
    try std.testing.expectEqual(parser.SyntaxRecoveryResume.before, recovery.@"resume");
    try std.testing.expectEqualStrings(",", recovery.terminal);
    switch (parser.parser.parser_type) {
        .ll => {
            const occurrence = switch (recovery.target) {
                .occurrence => |occurrence| occurrence,
                else => return error.WrongRecoveryTarget,
            };
            try std.testing.expectEqualStrings("_ValueSlot", occurrence.variable);
            try std.testing.expectEqualStrings("ArrayMembersTail", occurrence.parent_variable);
        },
        .lr => {
            const production = switch (recovery.target) {
                .production => |production| production,
                else => return error.WrongRecoveryTarget,
            };
            try std.testing.expectEqualStrings("ArrayMembersTail", production.variable);
        },
    }
    try expectReachedEnd(&parsed, input);
}

test "json recovers damaged object values and renders tailored context" {
    const input: [:0]const u8 = "{\"first\": 1, \"broken\": ?, \"last\": 3}";
    var parsed = try parseError(input);
    defer parsed.session.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.session.syntaxErrorCount());
    const diagnostic = syntaxDiagnostic(&parsed.session);
    const recovery = diagnostic.recovery orelse return error.MissingRecovery;
    try std.testing.expectEqual(parser.SyntaxRecoveryResume.before, recovery.@"resume");
    try std.testing.expectEqualStrings(",", recovery.terminal);
    switch (parser.parser.parser_type) {
        .ll => {
            const occurrence = switch (recovery.target) {
                .occurrence => |occurrence| occurrence,
                else => return error.WrongRecoveryTarget,
            };
            try std.testing.expectEqualStrings("_ValueSlot", occurrence.variable);
            try std.testing.expectEqualStrings("ObjectMembersTail", occurrence.parent_variable);
        },
        .lr => {
            const production = switch (recovery.target) {
                .production => |production| production,
                else => return error.WrongRecoveryTarget,
            };
            try std.testing.expectEqualStrings("ObjectMembersTail", production.variable);
        },
    }

    const message = try parser.error_messages.renderJsonSyntaxError(.{
        .allocator = std.testing.allocator,
        .context = &parsed.context,
        .diagnostic = .{ .syntax = diagnostic },
        .style = .plain,
    });
    defer std.testing.allocator.free(message);
    try std.testing.expect(std.mem.indexOf(u8, message, "Expected a JSON value after this object's `:`.") != null);
    const recovery_text = switch (parser.parser.parser_type) {
        .ll => "Recovery: occurrence _ValueSlot",
        .lr => "Recovery: production ObjectMembersTail[0]",
    };
    try std.testing.expect(std.mem.indexOf(u8, message, recovery_text) != null);
    try expectReachedEnd(&parsed, input);
}

test "json production recovery closes a damaged object tail" {
    const input: [:0]const u8 = "{\"valid\": 1, ?}";
    var parsed = try parseError(input);
    defer parsed.session.deinit();

    const recovery = syntaxDiagnostic(&parsed.session).recovery orelse return error.MissingRecovery;
    try std.testing.expectEqual(parser.SyntaxRecoveryResume.before, recovery.@"resume");
    try std.testing.expectEqualStrings("}", recovery.terminal);
    const production = switch (recovery.target) {
        .production => |production| production,
        else => return error.WrongRecoveryTarget,
    };
    try std.testing.expectEqualStrings("ObjectMembersTail", production.variable);
    try expectReachedEnd(&parsed, input);
}

test "json container production recovery discards an unselectable array" {
    const input: [:0]const u8 = "[?]";
    var parsed = try parseError(input);
    defer parsed.session.deinit();

    const recovery = syntaxDiagnostic(&parsed.session).recovery orelse return error.MissingRecovery;
    try std.testing.expectEqual(parser.SyntaxRecoveryResume.after, recovery.@"resume");
    try std.testing.expectEqualStrings("]", recovery.terminal);
    const production = switch (recovery.target) {
        .production => |production| production,
        else => return error.WrongRecoveryTarget,
    };
    try std.testing.expectEqualStrings("Value", production.variable);
    try expectReachedEnd(&parsed, input);
}

test "json remains fail fast outside committed recovery scopes" {
    const input: [:0]const u8 = "?";
    var parsed = try parseError(input);
    defer parsed.session.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.session.syntaxErrorCount());
    try std.testing.expect(syntaxDiagnostic(&parsed.session).recovery == null);
    try std.testing.expect(parsed.context.pos() <= input.len);
}
