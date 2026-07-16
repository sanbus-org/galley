const std = @import("std");
const parser = @import("parser-under-test");
const procedures = parser.procedures;

fn parse(input: []const u8) !void {
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
}

fn expectNodeName(event: procedures.Event, expected: []const u8) !void {
    const variable = event.node_variable orelse return error.ExpectedProcedureNode;
    try std.testing.expectEqualStrings(expected, parser.parser.variables[variable]);
}

fn expectHookTargets(hook: procedures.Hook, expected: []const []const u8) !void {
    var matched: usize = 0;
    for (procedures.trace()) |event| {
        if (event.hook != hook) continue;
        const variable = event.node_variable orelse return error.ExpectedProcedureNode;
        if (variable == parser.data_structures.ASTNode.invalid_variable) continue;
        if (matched == expected.len) return error.UnexpectedExtraProcedureHook;
        try std.testing.expectEqualStrings(expected[matched], parser.parser.variables[variable]);
        matched += 1;
    }
    try std.testing.expectEqual(expected.len, matched);
}

fn expectOrderedTrace(expected: []const procedures.Hook, node_name: []const u8) !void {
    var matched: usize = 0;
    for (procedures.trace()) |event| {
        const variable = event.node_variable orelse continue;
        if (variable == parser.data_structures.ASTNode.invalid_variable) continue;
        if (!std.mem.eql(u8, node_name, parser.parser.variables[variable])) continue;
        if (matched == expected.len) return error.UnexpectedExtraProcedureHook;
        try std.testing.expectEqual(expected[matched], event.hook);
        matched += 1;
    }
    try std.testing.expectEqual(expected.len, matched);
}

fn expectFilteredHookOrder(expected: []const procedures.Hook, node_name: []const u8) !void {
    var matched: usize = 0;
    for (procedures.trace()) |event| {
        const variable = event.node_variable orelse continue;
        if (variable == parser.data_structures.ASTNode.invalid_variable) continue;
        if (!std.mem.eql(u8, node_name, parser.parser.variables[variable])) continue;

        var belongs_to_sequence = false;
        for (expected) |expected_hook| {
            if (event.hook == expected_hook) {
                belongs_to_sequence = true;
                break;
            }
        }
        if (!belongs_to_sequence) continue;

        if (matched == expected.len) return error.UnexpectedExtraProcedureHook;
        try std.testing.expectEqual(expected[matched], event.hook);
        matched += 1;
    }
    try std.testing.expectEqual(expected.len, matched);
}

test "procedure-hooks LHS hooks run for every position" {
    procedures.resetTrace();
    try parse("lama");
    try expectHookTargets(.lhs, &.{ "LhsTarget", "LhsTarget" });
}

test "procedure-hooks RHS hooks are position-specific" {
    procedures.resetTrace();
    try parse("sxtx");
    try expectHookTargets(.rhs, &.{"RhsTarget"});
    for (procedures.trace()) |event| {
        if (event.hook == .rhs) try std.testing.expectEqual(@as(?usize, 1), event.node_text_start);
    }

    procedures.resetTrace();
    try parse("ux");
    try expectHookTargets(.rhs, &.{});
}

test "procedure-hooks production hooks are alternative-specific LHS hooks" {
    procedures.resetTrace();
    try parse("py");
    try expectHookTargets(.production, &.{"Start"});

    procedures.resetTrace();
    try parse("qy");
    try expectHookTargets(.production, &.{});
}

test "procedure-hooks chains run left to right" {
    procedures.resetTrace();
    try parse("c");
    try expectFilteredHookOrder(&.{ .chain_first, .chain_second }, "ChainTarget");
}

test "procedure-hooks automatic symbol hook matches its symbol" {
    procedures.resetTrace();
    try parse("vw");
    try expectHookTargets(.automatic_auto_target, &.{"AutoTarget"});
}

test "procedure-hooks general reduction runs once and last per variable" {
    procedures.resetTrace();
    try parse("gz");
    try expectHookTargets(.general, &.{ "GeneralLeaf", "Start" });
}

test "procedure-hooks phases follow local-to-global order" {
    procedures.resetTrace();
    try parse("o");
    try expectOrderedTrace(&.{
        .rhs_first,
        .rhs_second,
        .production_first,
        .production_second,
        .automatic_production,
        .lhs_first,
        .lhs_second,
        .automatic_symbol,
        .general,
    }, "Ordered");
}

test "procedure-hooks recursive RHS hooks run for each annotated occurrence" {
    procedures.resetTrace();
    try parse("rre");
    try expectHookTargets(.recursive_occurrence, &.{ "Recursive", "Recursive" });
}

test "procedure-hooks AST-suppressed variables do not run hooks" {
    procedures.resetTrace();
    try parse("h");
    try expectHookTargets(.hidden, &.{});
    for (procedures.trace()) |event| {
        if (event.hook == .general and event.node_variable == null) {
            return error.UnexpectedAstSuppressedReductionHook;
        }
    }
}

test "procedure-hooks node changes propagate through later phases" {
    procedures.resetTrace();
    try parse("dn");

    const expected = [_]procedures.Hook{
        .drop_occurrence,
        .after_drop_production,
        .after_drop_automatic_production,
        .after_drop_lhs,
        .after_drop_automatic_symbol,
        .general,
    };
    var matched: usize = 0;
    for (procedures.trace()) |event| {
        const belongs_to_drop_sequence = switch (event.hook) {
            .drop_occurrence,
            .after_drop_production,
            .after_drop_automatic_production,
            .after_drop_lhs,
            .after_drop_automatic_symbol,
            => true,
            .general => event.node_variable == null,
            else => false,
        };
        if (!belongs_to_drop_sequence) continue;

        if (matched == expected.len) return error.UnexpectedExtraProcedureHook;
        try std.testing.expectEqual(expected[matched], event.hook);
        try std.testing.expect(event.has_rule);
        if (matched == 0) {
            try expectNodeName(event, "DropTarget");
        } else {
            try std.testing.expectEqual(null, event.node_variable);
        }
        matched += 1;
    }
    try std.testing.expectEqual(expected.len, matched);
}

test "procedure-hooks terminal phases run local to global" {
    procedures.resetTrace();
    try parse("j");

    const expected = [_]procedures.Hook{
        .terminal_first,
        .terminal_second,
        .automatic_terminal,
        .general,
    };
    var matched: usize = 0;
    for (procedures.trace()) |event| {
        if (event.node_variable != parser.data_structures.ASTNode.invalid_variable) continue;
        if (matched == expected.len) return error.UnexpectedExtraProcedureHook;
        try std.testing.expectEqual(expected[matched], event.hook);
        try std.testing.expect(!event.has_rule);
        matched += 1;
    }
    try std.testing.expectEqual(expected.len, matched);
}

test "procedure-hooks production indices continue across repeated LHS declarations" {
    procedures.resetTrace();
    try parse("i0");
    try expectHookTargets(.automatic_repeated_production, &.{});

    procedures.resetTrace();
    try parse("i1");
    try expectHookTargets(.automatic_repeated_production, &.{"IndexedTarget"});
}
