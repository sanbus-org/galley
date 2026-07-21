const std = @import("std");
const parser = @import("parser-under-test");

const ExpectedTarget = union(enum) {
    lhs: []const u8,
    production: struct { variable: []const u8, rhs_index: usize },
    occurrence: struct {
        parent: []const u8,
        rhs_index: usize,
        symbol_index: usize,
        variable: []const u8,
    },
};

fn expectRecovery(
    input: []const u8,
    expected_count: usize,
    expected_target: ExpectedTarget,
    terminal: []const u8,
    resume_side: parser.SyntaxRecoveryResume,
) !void {
    parser.procedures.reset();
    parser.error_messages.reset();
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();

    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes(input, null));
    try std.testing.expectEqual(expected_count, session.syntaxErrorCount());
    const diagnostic = session.lastDiagnostic() orelse return error.MissingDiagnostic;
    const syntax = switch (diagnostic) {
        .syntax => |value| value,
    };
    const recovery = syntax.recovery orelse return error.MissingRecoveryContext;
    try std.testing.expectEqualStrings(terminal, recovery.terminal);
    try std.testing.expectEqual(resume_side, recovery.@"resume");
    switch (expected_target) {
        .lhs => |variable| switch (recovery.target) {
            .lhs_variable => |actual| try std.testing.expectEqualStrings(variable, actual),
            else => return error.WrongRecoveryTarget,
        },
        .production => |expected| switch (recovery.target) {
            .production => |actual| {
                try std.testing.expectEqualStrings(expected.variable, actual.variable);
                try std.testing.expectEqual(expected.rhs_index, actual.rhs_index);
            },
            else => return error.WrongRecoveryTarget,
        },
        .occurrence => |expected| switch (recovery.target) {
            .occurrence => |actual| {
                try std.testing.expectEqualStrings(expected.parent, actual.parent_variable);
                try std.testing.expectEqual(expected.rhs_index, actual.rhs_index);
                try std.testing.expectEqual(expected.symbol_index, actual.symbol_index);
                try std.testing.expectEqualStrings(expected.variable, actual.variable);
            },
            else => return error.WrongRecoveryTarget,
        },
    }
}

fn astContainsVariable(
    context: *parser.data_structures.Context,
    address: parser.data_structures.ASTNode.Pointer,
    variable: []const u8,
) bool {
    if (address == parser.data_structures.ASTNode.invalid_pointer) return false;
    const node = context.node_allocator.at(address);
    if (node.variable < parser.parser.variables.len and
        std.mem.eql(u8, parser.parser.variables[node.variable], variable))
    {
        return true;
    }
    var child = node.first_child;
    while (child != parser.data_structures.ASTNode.invalid_pointer) {
        const next = context.node_allocator.at(child).next;
        if (astContainsVariable(context, child, variable)) return true;
        child = next;
    }
    return false;
}

test "explicit recovery mode and occurrence consume" {
    try std.testing.expectEqual(parser.parser.ErrorRecoveryMode.explicit, parser.parser.error_recovery_mode);
    try std.testing.expect(parser.parser.is_error_recovery_enabled);
    try expectRecovery("oaq;z", 1, .{ .occurrence = .{
        .parent = "Occurrence",
        .rhs_index = 0,
        .symbol_index = 1,
        .variable = "Damaged",
    } }, ";", .after);
    try std.testing.expectEqual(@as(usize, 0), parser.procedures.marks());
}

test "explicit recovery preserves the next construct terminal" {
    try expectRecovery("baq}", 1, .{ .occurrence = .{
        .parent = "Before",
        .rhs_index = 0,
        .symbol_index = 1,
        .variable = "Damaged",
    } }, "}", .before);
}

test "explicit recovery uses production then LHS scopes" {
    try expectRecovery("paq;", 1, .{ .production = .{ .variable = "Production", .rhs_index = 0 } }, ";", .after);
    try std.testing.expectEqual(@as(usize, 0), parser.procedures.marks());

    try expectRecovery("laq;", 1, .{ .lhs = "Lhs" }, ";", .after);
    try std.testing.expectEqual(@as(usize, 0), parser.procedures.marks());
}

test "explicit recovery winner ordering is earliest longest then source" {
    try expectRecovery("maq;;", 1, .{ .occurrence = .{
        .parent = "Multi",
        .rhs_index = 0,
        .symbol_index = 1,
        .variable = "Damaged",
    } }, ";;", .before);
    try expectRecovery("yaq;", 1, .{ .occurrence = .{
        .parent = "Tie",
        .rhs_index = 0,
        .symbol_index = 1,
        .variable = "Damaged",
    } }, ";", .before);
}

test "explicit recovery falls back to an enclosing committed occurrence" {
    try expectRecovery("raiq;", 1, .{ .occurrence = .{
        .parent = "Outer",
        .rhs_index = 0,
        .symbol_index = 1,
        .variable = "Inner",
    } }, ";", .after);
}

test "explicit mode has no automatic fallback outside active scopes" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes("faq;", null));
    try std.testing.expectEqual(@as(usize, 1), session.syntaxErrorCount());
    const diagnostic = session.lastDiagnostic() orelse return error.MissingDiagnostic;
    switch (diagnostic) {
        .syntax => |syntax| try std.testing.expectEqual(null, syntax.recovery),
    }
}

test "explicit recovery does not invent a synchronization terminal at EOF" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes("oaq", null));
    try std.testing.expectEqual(@as(usize, 1), session.syntaxErrorCount());
    const diagnostic = session.lastDiagnostic() orelse return error.MissingDiagnostic;
    switch (diagnostic) {
        .syntax => |syntax| try std.testing.expectEqual(null, syntax.recovery),
    }
}

test "explicit recovery omits the damaged AST value and completes its parent" {
    parser.procedures.reset();
    const input: [:0]const u8 = "oaq;z";
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    var context = session._makeContext(.{ .bytes = .{ .input = input[0 .. input.len + 1] } }, null);
    try std.testing.expectError(parser.ParseError.SyntaxError, session._parseContext(&context));

    const root_address = parser.procedures.capturedRoot();
    try std.testing.expect(root_address != parser.data_structures.ASTNode.invalid_pointer);
    try std.testing.expect(astContainsVariable(&context, root_address, "Occurrence"));
    try std.testing.expect(!astContainsVariable(&context, root_address, "Damaged"));
    try std.testing.expectEqual(@as(usize, 0), parser.procedures.marks());
}

test "explicit LR recovery does not activate speculative shared-prefix production scopes" {
    if (parser.parser.parser_type != .lr) return;
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes("saq;", null));
    try std.testing.expectEqual(@as(usize, 1), session.syntaxErrorCount());
    const diagnostic = session.lastDiagnostic() orelse return error.MissingDiagnostic;
    switch (diagnostic) {
        .syntax => |syntax| try std.testing.expectEqual(null, syntax.recovery),
    }
}

test "explicit LR recovery resolves canonical variable occurrences from the committed path" {
    if (parser.parser.parser_type != .lr) return;
    try expectRecovery("daq;", 1, .{ .occurrence = .{
        .parent = "Distinct",
        .rhs_index = 0,
        .symbol_index = 1,
        .variable = "Damaged",
    } }, ";", .after);
    try expectRecovery("dbq,", 1, .{ .occurrence = .{
        .parent = "Distinct",
        .rhs_index = 1,
        .symbol_index = 1,
        .variable = "Damaged",
    } }, ",", .after);
}

test "explicit LR recovery finds the nearest recursive occurrence" {
    if (parser.parser.parser_type != .lr) return;
    try expectRecovery("caaaq;", 1, .{ .occurrence = .{
        .parent = "Recursive",
        .rhs_index = 0,
        .symbol_index = 1,
        .variable = "Recursive",
    } }, ";", .after);
}

test "explicit recovery permits later independent diagnostics" {
    try expectRecovery("taq;bq;", 2, .{ .occurrence = .{
        .parent = "Two",
        .rhs_index = 0,
        .symbol_index = 3,
        .variable = "Damaged",
    } }, ";", .after);
}

test "explicit custom message hook sees finalized recovery" {
    try expectRecovery("oaq;z", 1, .{ .occurrence = .{
        .parent = "Occurrence",
        .rhs_index = 0,
        .symbol_index = 1,
        .variable = "Damaged",
    } }, ";", .after);
    try std.testing.expectEqual(@as(usize, 1), parser.error_messages.callCount());
    try std.testing.expect(parser.error_messages.sawFinalizedRecovery());
}
