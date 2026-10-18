//! Which variable parsers a generated LL parser forces inline under
//! `inlining_cap`.

const std = @import("std");

/// A variable parser that may be forced inline: its own code, in units of
/// about one decision prong or rule symbol; the variables it calls that may
/// be forced inline into it, once per call site; and its call sites in
/// functions never forced inline. Every other call counts one unit. Each
/// entry follows the entries it calls.
pub const Entry = struct {
    variable: usize,
    size: usize,
    callees: []const usize,
    fixed_calls: usize,
};

/// Indexed by symbol: whether the variable's parser is forced inline. With
/// a cap, a parser is when the code its copies beyond the first add is
/// below the cap. It has one copy per place its body would appear were
/// every entry forced inline, each as large as its body with every entry
/// below it forced in. Both counts are the most inlining can reach and do
/// not depend on what else inlines, so a larger cap only adds parsers and a
/// cap of 0 adds none. Without a cap, every entry's parser is.
pub fn inlinedVariables(comptime symbol_count: usize, comptime entries: []const Entry, comptime cap: ?usize) [symbol_count]bool {
    var inlined: [symbol_count]bool = @splat(false);
    var quota: u32 = 1000;
    var size: [symbol_count]usize = @splat(0);
    var copies: [symbol_count]usize = @splat(0);
    for (entries) |entry| {
        quota += 4 + 2 * @as(u32, @intCast(entry.callees.len));
        @setEvalBranchQuota(quota);
        size[entry.variable] = entry.size;
        for (entry.callees) |callee| size[entry.variable] +|= size[callee];
        copies[entry.variable] = entry.fixed_calls;
    }
    // Callers follow their callees, so walking back reaches every caller of
    // an entry before the entry hands its copies on.
    var index = entries.len;
    while (index > 0) {
        index -= 1;
        const entry = entries[index];
        quota += 4 + 2 * @as(u32, @intCast(entry.callees.len));
        @setEvalBranchQuota(quota);
        for (entry.callees) |callee| copies[callee] +|= copies[entry.variable];
        inlined[entry.variable] = if (cap) |limit| (copies[entry.variable] -| 1) *| size[entry.variable] < limit else true;
    }
    return inlined;
}

// Start calls Value once; Value calls Blank twice and Item once; Item calls
// Blank once; a breaker rule function calls Item once more. Value's body
// holds 10 + 2 * 3 + (4 + 3) = 23 units; Item's copies are its own call from
// the breaker function and the one in each copy of Value.
const example_entries = [_]Entry{
    .{ .variable = 3, .size = 3, .callees = &.{}, .fixed_calls = 0 },
    .{ .variable = 2, .size = 4, .callees = &.{3}, .fixed_calls = 1 },
    .{ .variable = 1, .size = 10, .callees = &.{ 3, 3, 2 }, .fixed_calls = 0 },
    .{ .variable = 0, .size = 2, .callees = &.{1}, .fixed_calls = 1 },
};

fn exampleInlined(comptime cap: ?usize) [4]bool {
    return comptime inlinedVariables(4, &example_entries, cap);
}

test "inlinedVariables forces no parser inline under a cap of 0" {
    try std.testing.expectEqual([4]bool{ false, false, false, false }, exampleInlined(0));
}

test "inlinedVariables forces every parser inline without a cap" {
    try std.testing.expectEqual([4]bool{ true, true, true, true }, exampleInlined(null));
}

test "inlinedVariables inlines a parser with one copy under any cap above 0" {
    // Start and Value have one copy each. Item has two, adding 7 units, and
    // Blank four, adding 3 * 3 = 9.
    try std.testing.expectEqual([4]bool{ true, true, false, false }, exampleInlined(1));
    try std.testing.expectEqual([4]bool{ true, true, true, false }, exampleInlined(8));
    try std.testing.expectEqual([4]bool{ true, true, true, true }, exampleInlined(10));
}

test "inlinedVariables keeps a parser whose copies add exactly the cap a function" {
    try std.testing.expectEqual([4]bool{ true, true, false, false }, exampleInlined(7));
}

test "inlinedVariables only adds parsers as the cap grows" {
    comptime var previous = inlinedVariables(4, &example_entries, 0);
    inline for (1..12) |cap| {
        const current = comptime inlinedVariables(4, &example_entries, cap);
        for (previous, current) |was, is| try std.testing.expect(!was or is);
        previous = current;
    }
}
