const std = @import("std");
const parser = @import("parser-under-test");

// Every `List` rule reaches `List` again from its last position, through the
// helpers factoring creates, so LL parses a list of any length in one loop:
// `depth` levels are far more than recursion survives. The same tests run
// against LR, which parses the language with its own stack, so both agree.

const depth = 100_000;
const has_procedures = parser.parser.are_procedures_enabled;
const is_explicit = parser.parser.is_error_recovery_enabled and parser.parser.error_recovery_mode == .explicit;

fn ignoreDiagnostic(_: []const u8) void {}

/// `a;1;a;1;...`: `items` words and numbers alternating, then `last`.
fn alternatingList(items: usize, last: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(std.testing.allocator);
    for (0..items) |index| try list.appendSlice(std.testing.allocator, if (index % 2 == 0) "a;" else "1;");
    try list.appendSlice(std.testing.allocator, last);
    return list.toOwnedSlice(std.testing.allocator);
}

fn resetProcedures() void {
    if (comptime has_procedures) parser.procedures.reset();
}

/// Checks the reductions of a parsed list of `items` alternating items that
/// ends with a word.
fn expectListReductions(items: usize) !void {
    if (comptime !has_procedures) return;
    try std.testing.expectEqual(items, parser.procedures.listCount());
    try std.testing.expect(parser.procedures.reducedInnermostFirst());
    // Each word but the last continues at the marked occurrence.
    try std.testing.expectEqual(items / 2, parser.procedures.markCount());
}

test "a list far deeper than recursion allows parses" {
    const input = try alternatingList(depth - 1, "b");
    defer std.testing.allocator.free(input);
    resetProcedures();
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, null, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
    try expectListReductions(depth);
}

test "each level's node holds the next level as its last child" {
    if (comptime !parser.parser.is_ast_enabled) return error.SkipZigTest;
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, "a;1;b", null, .{});
    defer parsed.deinit();
    const nodes = &parsed.session.node_allocator;
    var address = nodes.at(parsed.result.ast_root.?).first_child;
    var texts: [3][]const u8 = undefined;
    var levels: usize = 0;
    while (address != parser.data_structures.Node.invalid_pointer) : (levels += 1) {
        const node = nodes.at(address);
        try std.testing.expectEqualStrings("List", parser.parser.variables[node.variable]);
        texts[levels] = "a;1;b"[node.text_start..][0..node.text_length];
        const last = node.last_child;
        address = if (last != parser.data_structures.Node.invalid_pointer and
            std.mem.eql(u8, parser.parser.variables[nodes.at(last).variable], "List")) last else parser.data_structures.Node.invalid_pointer;
    }
    try std.testing.expectEqual(@as(usize, 3), levels);
    try std.testing.expectEqualStrings("a;1;b", texts[0]);
    try std.testing.expectEqualStrings("1;b", texts[1]);
    try std.testing.expectEqualStrings("b", texts[2]);
}

test "a list nests at a position that is not last" {
    resetProcedures();
    const input = "(a;1);b;(c;(2));3";
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, null, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
    if (comptime has_procedures) try std.testing.expectEqual(@as(usize, 9), parser.procedures.listCount());
}

test "each level reduces with the next level as a child" {
    if (comptime !has_procedures) return error.SkipZigTest;
    // Words, numbers and inner lists are nodes; terminals are not.
    for ([_]struct { input: []const u8, children: []const u32 }{
        .{ .input = "a;1;b", .children = &.{ 1, 2, 2 } },
        .{ .input = "(a;1);b", .children = &.{ 1, 2, 1, 2 } },
    }) |case| {
        resetProcedures();
        var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, case.input, null, .{});
        defer parsed.deinit();
        try std.testing.expectEqualSlices(u32, case.children, parser.procedures.childCounts());
    }
}

test "an error after a nested list reports the variables still being parsed" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .max_errors = 1, .syntax_error_reporter = &ignoreDiagnostic });
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes("(a;1;b);%", null));
    var read_guard = try session.readLatest();
    defer read_guard.deinit();
    const diagnostic = read_guard.lastDiagnostic() orelse return error.MissingDiagnostic;
    const syntax = switch (diagnostic) {
        .syntax => |value| value,
        .semantic, .indentation, .hook => return error.ExpectedSyntaxDiagnostic,
    };
    // Repeats of List share one entry; the inner list's levels are gone.
    const variables = switch (syntax.context) {
        .while_parsing => |value| value,
        else => return error.ExpectedVariableContext,
    };
    try std.testing.expectEqual(@as(usize, 2), variables.len);
    try std.testing.expectEqualStrings("List", variables[0]);
    try std.testing.expectEqualStrings("Start", variables[1]);
}

test "a failure deep in a list leaves the session ready for the next parse" {
    const broken = try alternatingList(depth - 1, "%");
    defer std.testing.allocator.free(broken);
    const valid = try alternatingList(depth - 1, "b");
    defer std.testing.allocator.free(valid);
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .syntax_error_reporter = &ignoreDiagnostic });
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes(broken, null));
    resetProcedures();
    const result = try session.parseBytes(valid, null);
    try std.testing.expectEqual(valid.len, result.parsed_bytes);
    try expectListReductions(depth);
}

/// Where a recovery is expected. An occurrence within a list sits in a
/// helper factoring created, whose name is not the grammar's, so its parent
/// is checked only when given.
const Target = union(enum) {
    occurrence: struct { parent: ?[]const u8 = null, symbol_index: ?usize = null, variable: []const u8 = "List" },
    production: struct { variable: []const u8, rhs_index: usize },
    lhs: []const u8,
};

const Expected = struct { terminal: []const u8, target: Target = .{ .occurrence = .{} } };

fn expectExplicitRecovery(input: []const u8, expected: Expected) !void {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .syntax_error_reporter = &ignoreDiagnostic });
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes(input, null));
    var read_guard = try session.readLatest();
    defer read_guard.deinit();
    try std.testing.expectEqual(@as(usize, 1), read_guard.syntaxErrorCount());
    const diagnostic = read_guard.lastDiagnostic() orelse return error.MissingDiagnostic;
    const syntax = switch (diagnostic) {
        .syntax => |value| value,
        .semantic, .indentation, .hook => return error.ExpectedSyntaxDiagnostic,
    };
    const recovery = syntax.recovery orelse return error.MissingRecoveryContext;
    try std.testing.expectEqualStrings(expected.terminal, recovery.terminal);
    try std.testing.expectEqual(parser.SyntaxRecoveryResume.after, recovery.@"resume");
    switch (expected.target) {
        .occurrence => |occurrence| switch (recovery.target) {
            .occurrence => |actual| {
                if (occurrence.parent) |parent| try std.testing.expectEqualStrings(parent, actual.parent_variable);
                if (occurrence.symbol_index) |symbol_index| try std.testing.expectEqual(symbol_index, actual.symbol_index);
                try std.testing.expectEqualStrings(occurrence.variable, actual.variable);
            },
            else => return error.WrongRecoveryTarget,
        },
        .production => |production| switch (recovery.target) {
            .production => |actual| {
                try std.testing.expectEqualStrings(production.variable, actual.variable);
                try std.testing.expectEqual(production.rhs_index, actual.rhs_index);
            },
            else => return error.WrongRecoveryTarget,
        },
        .lhs => |variable| switch (recovery.target) {
            .lhs_variable => |actual| try std.testing.expectEqualStrings(variable, actual),
            else => return error.WrongRecoveryTarget,
        },
    }
}

/// `prefix`, `count` copies of `repeated`, then `suffix`.
fn repeat(prefix: []const u8, repeated: []const u8, count: usize, suffix: []const u8) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(std.testing.allocator);
    try bytes.appendSlice(std.testing.allocator, prefix);
    for (0..count) |_| try bytes.appendSlice(std.testing.allocator, repeated);
    try bytes.appendSlice(std.testing.allocator, suffix);
    return bytes.toOwnedSlice(std.testing.allocator);
}

test "explicit recovery deep in a list uses the occurrence that level continued at" {
    if (comptime !is_explicit) return error.SkipZigTest;
    // The failing level continued after a word, whose occurrence recovers
    // at ".".
    const input = try alternatingList(depth - 1, "%x.");
    defer std.testing.allocator.free(input);
    try expectExplicitRecovery(input, .{ .terminal = "." });
}

test "explicit recovery falls back to the level around a failing one" {
    if (comptime !is_explicit) return error.SkipZigTest;
    // The failing level continued after a word (recovering at "."), the level
    // around it after a number (recovering at ","): that one recovers, and
    // only the levels outside it reduce.
    resetProcedures();
    const items = depth - 1;
    const input = try alternatingList(items, "%x,");
    defer std.testing.allocator.free(input);
    try expectExplicitRecovery(input, .{ .terminal = "," });
    if (comptime has_procedures) {
        try std.testing.expectEqual(items - 1, parser.procedures.listCount());
        try std.testing.expect(parser.procedures.reducedInnermostFirst());
    }
}

test "explicit recovery falls back through every open level of a list" {
    if (comptime !is_explicit) return error.SkipZigTest;
    // No level inside the list can recover without a "."; the outermost
    // level's occurrence, in Start, recovers at "!".
    const input = try alternatingList(depth - 1, "%x!");
    defer std.testing.allocator.free(input);
    try expectExplicitRecovery(input, .{ .terminal = "!", .target = .{ .occurrence = .{ .parent = "Start", .symbol_index = 0 } } });
}

test "explicit recovery deep in a list uses an occurrence factoring moved into a helper" {
    if (comptime !is_explicit) return error.SkipZigTest;
    // The failing level continued after a parenthesized list.
    const input = try alternatingList(depth - 1, "(a);%x?");
    defer std.testing.allocator.free(input);
    try expectExplicitRecovery(input, .{ .terminal = "?" });
}

test "explicit recovery deep in a list uses a production scope of an enclosing level" {
    if (comptime !is_explicit) return error.SkipZigTest;
    // The level around the failing one parsed the "+" production.
    const input = try alternatingList(depth - 1, "+1;%x$");
    defer std.testing.allocator.free(input);
    try expectExplicitRecovery(input, .{ .terminal = "$", .target = .{ .production = .{ .variable = "List", .rhs_index = 2 } } });
}

test "explicit recovery deep in a list uses the variable's own scope" {
    if (comptime !is_explicit) return error.SkipZigTest;
    const input = try alternatingList(depth - 1, "%x#");
    defer std.testing.allocator.free(input);
    try expectExplicitRecovery(input, .{ .terminal = "#", .target = .{ .lhs = "List" } });
}

test "a hidden loop parses deep input" {
    const input = try repeat(">", "c", depth, ".!");
    defer std.testing.allocator.free(input);
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, null, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
}

test "explicit recovery deep in a hidden loop uses the failing level's occurrence" {
    if (comptime !is_explicit) return error.SkipZigTest;
    const input = try repeat(">", "c", depth, "%;!");
    defer std.testing.allocator.free(input);
    try expectExplicitRecovery(input, .{ .terminal = ";", .target = .{ .occurrence = .{ .parent = "_Chain", .symbol_index = 1, .variable = "_Chain" } } });
}

test "a variable whose every rule repeats it ends only on an error" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{ .syntax_error_reporter = &ignoreDiagnostic });
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes("?xyx", null));
}
