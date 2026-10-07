//! A hook that fails aborts the parse: `error.HookFailed`, nothing published,
//! a hook diagnostic of where the parse stopped, and recovery from syntax
//! errors never turns it into anything else. One generated parser per
//! recovery mode, parser family and AST setting.

const std = @import("std");
const parser = @import("parser-under-test");

const procedures = parser.procedures;

fn ignoreDiagnostic(_: []const u8) void {}

fn newSession() !parser.Session {
    return parser.Session.init(std.testing.io, std.testing.allocator, .{
        .syntax_error_reporter = &ignoreDiagnostic,
        .max_errors = 10,
    });
}

const valid = "a=1;b=2";
// Recovers from the damaged value, so the parse still reaches the end.
const recovered = "a=1;b=?;a=2";

fn expectHookFailure(session: *parser.Session, input: []const u8, variable: []const u8, hook_name: []const u8) !void {
    try std.testing.expectError(error.HookFailed, session.parseBytes(input, null));

    // The failure published nothing, and the hook's ticket exited.
    try std.testing.expectError(error.NoParseResult, session.readCurrent());
    try std.testing.expectEqual(@as(u64, 0), session.runtime_context.live_hook.load(.monotonic));

    var guard = try session.readLatest();
    defer guard.deinit();
    const diagnostic = guard.lastDiagnostic() orelse return error.MissingDiagnostic;
    const hook = switch (diagnostic) {
        .hook => |value| value,
        else => return error.ExpectedHookDiagnostic,
    };
    try std.testing.expectEqualStrings(variable, hook.variable);
    try std.testing.expectEqualStrings(hook_name, hook.hook);
    try std.testing.expect(hook.line >= 1 and hook.column >= 1);

    const plain = try parser.renderParseDiagnostic(std.testing.allocator, diagnostic, .plain);
    defer std.testing.allocator.free(plain);
    try std.testing.expect(std.mem.indexOf(u8, plain, "HookError at ") != null);
    try std.testing.expect(std.mem.indexOf(u8, plain, hook_name) != null);
    try std.testing.expect(std.mem.indexOf(u8, plain, variable) != null);

    const ansi = try parser.renderParseDiagnostic(std.testing.allocator, diagnostic, .ansi);
    defer std.testing.allocator.free(ansi);
    try std.testing.expect(std.mem.indexOf(u8, ansi, "HookError at ") != null);
    try std.testing.expect(std.mem.indexOf(u8, ansi, hook_name) != null);
    try std.testing.expect(std.mem.indexOf(u8, ansi, "\x1b[") != null);
}

test "a failing hook aborts a clean parse with HookFailed" {
    var session = try newSession();
    defer session.deinit();
    procedures.fail_at = .entry;
    defer procedures.fail_at = .nowhere;
    try expectHookFailure(&session, valid, "Entry", "reduction_Entry");
}

test "recovery from syntax errors never swallows a hook failure" {
    var session = try newSession();
    defer session.deinit();
    defer procedures.fail_at = .nowhere;

    procedures.fail_at = .document;
    try expectHookFailure(&session, recovered, "Document", "reduction_Document");
    {
        // The recovered syntax error was recorded before the hook failed, and
        // the failure's own diagnostic is the last one.
        var guard = try session.readLatest();
        defer guard.deinit();
        const records = guard.recordedDiagnostics();
        try std.testing.expect(records.len >= 2);
        try std.testing.expect(records[0] == .syntax);
        try std.testing.expect(records[records.len - 1] == .hook);
    }

    procedures.fail_at = .entry;
    try expectHookFailure(&session, recovered, "Entry", "reduction_Entry");
}

test "the session parses again after a hook aborted the parse" {
    var session = try newSession();
    defer session.deinit();
    defer procedures.fail_at = .nowhere;

    procedures.fail_at = .document;
    try expectHookFailure(&session, valid, "Document", "reduction_Document");

    procedures.fail_at = .nowhere;
    const parsed = try session.parseBytes(valid, null);
    try std.testing.expectEqual(valid.len, parsed.parsed_bytes);
    var guard = try session.readCurrent();
    defer guard.deinit();
    try std.testing.expect(guard.lastDiagnostic() == null);
}
