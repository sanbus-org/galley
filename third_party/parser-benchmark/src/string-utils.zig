const std = @import("std");

const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB", "PB" };

pub fn formatWithThousands(value: anytype, buf: []u8) ![]u8 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    const n: u64 = switch (info) {
        .int, .comptime_int => @intCast(value),
        .float, .comptime_float => @intFromFloat(value),
        else => @compileError("formatWithThousands: expected int or float, got " ++ @typeName(T)),
    };

    var tmp: [32]u8 = undefined;
    const digits = std.fmt.bufPrint(&tmp, "{d}", .{n}) catch unreachable;

    var out_pos: usize = 0;
    const len = digits.len;
    for (digits, 0..) |ch, i| {
        const remaining = len - i;
        if (i > 0 and remaining % 3 == 0) {
            buf[out_pos] = ',';
            out_pos += 1;
        }
        buf[out_pos] = ch;
        out_pos += 1;
    }

    return buf[0..out_pos];
}

pub fn formatFileSize(size: anytype, buf: []u8) ![]u8 {
    const T = @TypeOf(size);
    const info = @typeInfo(T);

    const fsize: f64 = switch (info) {
        .int, .comptime_int => @floatFromInt(size),
        .float, .comptime_float => @floatCast(size),
        else => @compileError("formatFileSize: expected int or float, got " ++ @typeName(T)),
    };

    var value = fsize;
    var unit_index: usize = 0;

    while (value >= 1024.0 and unit_index < units.len - 1) {
        value /= 1024.0;
        unit_index += 1;
    }

    if (unit_index == 0) {
        return std.fmt.bufPrint(buf, "{d} {s}", .{ @as(u64, @intFromFloat(value)), units[unit_index] });
    } else {
        return std.fmt.bufPrint(buf, "{d:.2} {s}", .{ value, units[unit_index] });
    }
}
