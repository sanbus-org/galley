const std = @import("std");
const parser = @import("galley_parser");

pub fn main(init: std.process.Init) !void {
    const grammar =
        \\Start
        \\| "a"
        \\
    ;

    var parsed = try parser.parseBytes(
        init.io,
        init.gpa,
        grammar,
        .{ .input_path = "inline.grm" },
    );
    defer parsed.deinit();
    if (parsed.result.parsed_bytes != grammar.len) return error.ShortParse;

    var reader = try parsed.session.read(parsed.result);
    defer reader.deinit();
    if (parser.procedures.grammarFromAstAllocator(reader.astAllocator()) == null) {
        return error.GrammarModelMissing;
    }
}
