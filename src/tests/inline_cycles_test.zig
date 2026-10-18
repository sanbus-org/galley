const std = @import("std");
const builtin = @import("builtin");
const parser = @import("parser-under-test");

// The grammar's shapes each have a call an inlined parser could make into
// its own expansion. This build forces inlining, so compiling it is the
// check; the parses confirm the shapes still accept their language.

fn parseAll(input: []const u8) !void {
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, null, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
}

test "inline cycles: the build forces parsers inline" {
    try std.testing.expect(parser.parser.inlining_cap != 0 and builtin.mode != .debug);
}

test "inline cycles: a cycle breaks at a rule that consumes before it recurses" {
    try parseAll("1x");
    try parseAll("1[[[x]]]");
    try parseAll("1[[-]]");
}

test "inline cycles: a cycle breaks outside a variable whose factored rules loop" {
    try parseAll("2xyz");
    try parseAll("2xxxyz");
    try parseAll("2xyxyzw");
    try parseAll("2xyxyxyzww");
}

test "inline cycles: a helper calls its variable's parser" {
    try parseAll("3xz");
    try parseAll("3xxxzyy");
}

test "inline cycles: a helper of a helper calls its variable's parser" {
    try parseAll("4xyz");
    try parseAll("4xq");
    try parseAll("4xyxyzw");
    try parseAll("4xyxyxqww");
}

test "inline cycles: a helper makes a flattened call of its variable" {
    try parseAll("5l;");
    try parseAll("5l;l;l;");
}

test "inline cycles: a cycle without a breaker" {
    try parseAll("6x");
    try parseAll("6a(x)");
    try parseAll("6(([x]))");
}
