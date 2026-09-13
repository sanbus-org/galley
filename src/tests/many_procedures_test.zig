const std = @import("std");
const parser = @import("parser-under-test");
const procedures = parser.procedures;

// Compiling this binary is the quota regression: 161 hooked procedures must
// build under the default Zig comptime branch quota.
test "many procedures compile and all hooks run" {
    procedures.resetHookCallCount();
    var input_buffer: [160]u8 = .{'a'} ** 160;
    const input = input_buffer[0..];
    var parsed = try parser.parseBytes(std.testing.io, std.testing.allocator, input, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(input.len, parsed.result.parsed_bytes);
    try std.testing.expectEqual(@as(usize, 161), procedures.hook_call_count);
}
