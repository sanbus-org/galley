const std = @import("std");
const parser = @import("parser-under-test");
const procedures = parser.procedures;

fn variableIndex(name: []const u8) u16 {
    for (parser.parser.variables, 0..) |candidate, index| {
        if (std.mem.eql(u8, candidate, name)) return @intCast(index);
    }
    unreachable;
}

fn parse(input: []const u8) !parser.ParsedInput {
    return parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
}

fn expectAstRootMatchesSemantic(parsed: *parser.ParsedInput, root_name: []const u8, child_names: []const []const u8) !void {
    if (comptime !parser.parser.is_ast_enabled) return;
    const root_address = parsed.result.ast_root orelse return error.MissingAstRoot;
    const allocator = &parsed.session.node_allocator;
    const root = allocator.at(root_address);
    try std.testing.expectEqualStrings(root_name, parser.parser.variables[root.variable]);

    const semantic_root = parsed.result.semantic_root orelse return error.MissingSemanticRoot;
    try std.testing.expectEqual(semantic_root.value, root.payload.value);

    var child_address = root.first_child;
    for (child_names, 0..) |child_name, index| {
        if (child_address == parser.data_structures.Node.invalid_pointer) return error.MissingAstChild;
        const child = allocator.at(child_address);
        try std.testing.expectEqualStrings(child_name, parser.parser.variables[child.variable]);
        if (index == child_names.len - 1) {
            try std.testing.expectEqual(@as(?parser.data_structures.Node.Pointer, parser.data_structures.Node.invalid_pointer), child.next);
        }
        child_address = child.next;
    }
    try std.testing.expectEqual(@as(?parser.data_structures.Node.Pointer, parser.data_structures.Node.invalid_pointer), child_address);
    try std.testing.expectEqual(child_names.len, root.children_count);
}

test "no-AST procedures preserve hook order, children, spans, and payloads" {
    procedures.reset();
    var parsed = try parse("aaax");
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 4), parsed.result.parsed_bytes);
    try std.testing.expectEqual(@as(usize, 8), parsed.result.semantic_root.?.value);
    if (parser.parser.is_ast_enabled) {
        try expectAstRootMatchesSemantic(&parsed, "Start", &.{ "Sequence", "Empty" });
    } else {
        try std.testing.expectEqual(@as(?parser.data_structures.Node.Pointer, null), parsed.result.ast_root);
        try std.testing.expect(@TypeOf(parsed.session.node_allocator) == void);
    }

    const start = variableIndex("Start");
    const sequence = variableIndex("Sequence");
    const empty = variableIndex("Empty");
    var start_hooks: [5]procedures.Hook = undefined;
    var start_hook_count: usize = 0;
    var saw_sequence_occurrence = false;
    var terminal_count: usize = 0;
    for (procedures.trace()) |event| {
        try std.testing.expect(event.hook != .hidden);
        if (event.hook == .terminal_occurrence) {
            terminal_count += 1;
            try std.testing.expectEqual(@as(usize, 1), event.text_length);
        }
        if (event.variable == sequence and event.hook == .occurrence) saw_sequence_occurrence = true;
        if (event.variable != start) continue;
        if (event.hook == .production or event.hook == .automatic_production or event.hook == .lhs or event.hook == .automatic_symbol or event.hook == .general) {
            start_hooks[start_hook_count] = event.hook;
            start_hook_count += 1;
        }
        try std.testing.expectEqual(@as(usize, 0), event.text_start);
        try std.testing.expectEqual(@as(usize, 4), event.text_length);
        try std.testing.expectEqual(@as(usize, 2), event.children_count);
        try std.testing.expectEqual(sequence, event.children[0]);
        try std.testing.expectEqual(empty, event.children[1]);
    }

    try std.testing.expectEqual(@as(usize, 3), terminal_count);
    try std.testing.expect(saw_sequence_occurrence);
    try std.testing.expectEqualSlices(procedures.Hook, &.{ .production, .automatic_production, .lhs, .automatic_symbol, .general }, start_hooks[0..start_hook_count]);
}

test "no-AST procedures survive long right-recursive self-repeating parses" {
    procedures.reset();
    var parsed = try parse("aaaaaaaaaax");
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 11), parsed.result.parsed_bytes);
    try std.testing.expectEqual(@as(usize, 15), parsed.result.semantic_root.?.value);
}

test "no-AST procedures propagate errors without publishing a result" {
    procedures.reset();
    procedures.setFailProduction(true);
    try std.testing.expectError(error.RequestedProcedureFailure, parse("aaax"));
}

test "no-AST procedures map unrecovered explicit recovery to SyntaxError" {
    if (parser.parser.parser_type != .ll) return;
    procedures.reset();
    try std.testing.expectEqual(parser.parser.ErrorRecoveryMode.explicit, parser.parser.error_recovery_mode);
    try std.testing.expectError(parser.ParseError.SyntaxError, parse("q"));
}
