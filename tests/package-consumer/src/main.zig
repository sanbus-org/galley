const std = @import("std");
const generator = @import("galley_generator");

pub fn main() !void {
    const grammar =
        \\Start
        \\| "a"
        \\
    ;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const parser_source = try generator.generateParserAlloc(
        arena.allocator(),
        grammar,
        .ll,
        .{ .with_procedures = false },
    );
    if (std.mem.indexOf(u8, parser_source, "pub fn parse") == null) {
        return error.GeneratedParserMissingEntryPoint;
    }
}
