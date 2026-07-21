const std = @import("std");
const parser = @import("parser-under-test");
const comparison_options = @import("comparison-options");

const malformed_grammar: [:0]const u8 =
    \\Start
    \\| ?
    \\| ?
    \\| "valid"
    \\
    \\Next
    \\| "still-valid"
    \\
;

const RecoveryResume = enum { before, after };

const Summary = struct {
    error_count: usize,
    reached_bytes: usize,
    line: u32,
    column: u32,
    unexpected_token: []const u8,
    recovery_resume: ?RecoveryResume,
    recovery_terminal: ?[]const u8,
    recovery_variable: ?[]const u8,
    rendered: []u8,

    fn deinit(self: Summary, allocator: std.mem.Allocator) void {
        allocator.free(self.unexpected_token);
        if (self.recovery_terminal) |terminal| allocator.free(terminal);
        if (self.recovery_variable) |variable| allocator.free(variable);
        allocator.free(self.rendered);
    }
};

fn run(io: std.Io, allocator: std.mem.Allocator) !Summary {
    var session = try parser.Session.init(io, allocator, .{});
    defer session.deinit();

    var context = session._makeContext(.{
        .bytes = .{ .input = malformed_grammar[0 .. malformed_grammar.len + 1] },
    }, null);
    if (session._parseContext(&context)) |_| {
        return error.ExpectedSyntaxError;
    } else |err| switch (err) {
        parser.ParseError.SyntaxError => {},
        else => return err,
    }

    const diagnostic = session.lastDiagnostic() orelse return error.MissingDiagnostic;
    const syntax = switch (diagnostic) {
        .syntax => |value| value,
    };
    const recovery_resume: ?RecoveryResume = if (syntax.recovery) |recovery|
        switch (recovery.@"resume") {
            .before => .before,
            .after => .after,
        }
    else
        null;
    const recovery_terminal = if (syntax.recovery) |recovery|
        try allocator.dupe(u8, recovery.terminal)
    else
        null;
    errdefer if (recovery_terminal) |terminal| allocator.free(terminal);
    const recovery_variable = if (syntax.recovery) |recovery| switch (recovery.target) {
        .occurrence => |occurrence| try allocator.dupe(u8, occurrence.variable),
        else => null,
    } else null;
    errdefer if (recovery_variable) |variable| allocator.free(variable);
    const unexpected_token = try allocator.dupe(u8, syntax.unexpected_token);
    errdefer allocator.free(unexpected_token);
    const rendered = try parser.renderParseDiagnostic(allocator, diagnostic, .plain);
    return .{
        .error_count = session.syntaxErrorCount(),
        .reached_bytes = context.pos() - 1,
        .line = syntax.line,
        .column = syntax.column,
        .unexpected_token = unexpected_token,
        .recovery_resume = recovery_resume,
        .recovery_terminal = recovery_terminal,
        .recovery_variable = recovery_variable,
        .rendered = rendered,
    };
}

fn printSummary(summary: Summary) void {
    std.debug.print(
        \\--- {s} summary ---
        \\mode: {s}
        \\syntax errors: {d}
        \\input reached: {d}/{d} bytes
        \\last diagnostic:
        \\{s}
        \\
    , .{
        comparison_options.label,
        @tagName(parser.parser.error_recovery_mode),
        summary.error_count,
        summary.reached_bytes,
        malformed_grammar.len,
        summary.rendered,
    });
}

pub fn main(init: std.process.Init) !void {
    std.debug.print("=== {s} recovery ===\n", .{comparison_options.heading});
    const summary = try run(init.io, init.gpa);
    defer summary.deinit(init.gpa);
    printSummary(summary);
}

test "galley recovery comparison records the selected mode and behavior" {
    const summary = try run(std.testing.io, std.testing.allocator);
    defer summary.deinit(std.testing.allocator);

    try std.testing.expectEqual(malformed_grammar.len, summary.reached_bytes);
    if (comparison_options.is_explicit) {
        try std.testing.expectEqual(parser.parser.ErrorRecoveryMode.explicit, parser.parser.error_recovery_mode);
        try std.testing.expectEqual(@as(usize, 2), summary.error_count);
        try std.testing.expectEqual(@as(u32, 3), summary.line);
        try std.testing.expectEqual(@as(u32, 3), summary.column);
        try std.testing.expectEqualStrings("?", summary.unexpected_token);
        try std.testing.expectEqual(.before, summary.recovery_resume orelse return error.MissingRecovery);
        try std.testing.expectEqualStrings("\n", summary.recovery_terminal orelse return error.MissingRecoveryTerminal);
        try std.testing.expectEqualStrings("Symbol", summary.recovery_variable orelse return error.WrongRecoveryTarget);
    } else {
        try std.testing.expectEqual(parser.parser.ErrorRecoveryMode.automatic, parser.parser.error_recovery_mode);
        try std.testing.expectEqual(@as(usize, 2), summary.error_count);
        try std.testing.expectEqual(@as(u32, 4), summary.line);
        try std.testing.expectEqual(@as(u32, 3), summary.column);
        try std.testing.expectEqualStrings("\"", summary.unexpected_token);
        try std.testing.expect(summary.recovery_resume == null);
    }
}
