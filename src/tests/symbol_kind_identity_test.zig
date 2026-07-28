const std = @import("std");
const parser = @import("parser-under-test");

fn expectVariableAndTerminal(id: []const u8) !void {
    var variables: usize = 0;
    var terminals: usize = 0;
    for (parser.parser.symbols, parser.parser.is_terminal) |symbol, is_terminal| {
        if (!std.mem.eql(u8, symbol, id)) continue;
        if (is_terminal) {
            terminals += 1;
        } else {
            variables += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 1), variables);
    try std.testing.expectEqual(@as(usize, 1), terminals);
}

test "generated parser keeps same-text variables and terminals distinct" {
    try expectVariableAndTerminal("VariableFirst");
    try expectVariableAndTerminal("TerminalFirst");

    const input = "vVariableFirstTerminalFirstt";
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
}
