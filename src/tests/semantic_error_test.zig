const std = @import("std");
const parser = @import("parser-under-test");

fn parseClean(input: []const u8) !void {
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
}

fn expectSemanticFailure(input: []const u8, expected_count: usize) !void {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SemanticError, session.parseBytes(input, null));

    var read_guard = try session.readLatest();
    defer read_guard.deinit();
    try std.testing.expectEqual(expected_count, read_guard.semanticErrorCount());
    try std.testing.expectEqual(@as(usize, 0), read_guard.syntaxErrorCount());
    try std.testing.expectEqual(expected_count, read_guard.recordedDiagnostics().len);

    const diagnostic = read_guard.lastDiagnostic() orelse return error.MissingDiagnostic;
    const semantic = switch (diagnostic) {
        .semantic => |value| value,
        else => return error.ExpectedSemanticDiagnostic,
    };
    try std.testing.expectEqualStrings("Item", semantic.variable);
    try std.testing.expectEqualStrings("unexpected item", semantic.message);
    try std.testing.expectEqual(@as(u32, 1), semantic.line);
    try std.testing.expectEqual(@as(usize, 1), semantic.text_length);

    const rendered = try parser.renderParseDiagnostic(std.testing.allocator, diagnostic, .plain);
    defer std.testing.allocator.free(rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "SemanticError at 1:") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "unexpected item") != null);
}

test "clean input parses without semantic errors" {
    try parseClean("aa");
}

test "single semantic error fails the parse but records one diagnostic" {
    try expectSemanticFailure("ab", 1);
}

test "semantic errors aggregate without aborting the parse" {
    try expectSemanticFailure("bb", 2);
}

test "error nodes are marked and visible from the parent" {
    if (comptime !parser.parser.is_ast_enabled) return;
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SemanticError, session.parseBytes("bb", null));

    var marked: usize = 0;
    var index: usize = 0;
    while (index < session.node_allocator.counter) : (index += 1) {
        const node = session.node_allocator.at(index);
        if (!node.is_semantic_error) continue;
        marked += 1;
        try std.testing.expectEqualStrings("Item", parser.parser.variables[node.variable]);
    }
    try std.testing.expectEqual(@as(usize, 2), marked);

    var root: usize = 0;
    var found_root = false;
    index = 0;
    while (index < session.node_allocator.counter) : (index += 1) {
        const node = session.node_allocator.at(index);
        if (std.mem.eql(u8, parser.parser.variables[node.variable], "Start")) {
            root = index;
            found_root = true;
            break;
        }
    }
    try std.testing.expect(found_root);
    try std.testing.expect(parser.data_structures.Node.hasSemanticErrorSubtree(root, &session.node_allocator));
}

test "clean tree carries no semantic error marks" {
    if (comptime !parser.parser.is_ast_enabled) return;
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, "aa", .{});
    defer parsed.deinit();
    const root = parsed.result.ast_root orelse return error.MissingAstRoot;
    try std.testing.expect(!parser.data_structures.Node.hasSemanticErrorSubtree(root, &parsed.session.node_allocator));
}

test "semantic counts reset between parses" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SemanticError, session.parseBytes("bb", null));
    const clean = try session.parseBytes("aa", null);
    try std.testing.expectEqual(@as(usize, 2), clean.parsed_bytes);
    var read_guard = try session.readLatest();
    defer read_guard.deinit();
    try std.testing.expectEqual(@as(usize, 0), read_guard.semanticErrorCount());
}

test "syntax errors keep precedence over semantic errors" {
    var session = try parser.Session.init(std.testing.io, std.testing.allocator, .{});
    defer session.deinit();
    try std.testing.expectError(parser.ParseError.SyntaxError, session.parseBytes("?", null));
}
