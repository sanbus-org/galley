const std = @import("std");

/// Rewrites one constant's value inside an existing `config.zig`, preserving
/// every other byte of the file (comments, ordering, formatting, and any
/// `: Type` annotation, as on `position_tracking: ?bool`). The constant may
/// appear as `pub const <name> = <value>;` or
/// `pub const <name>: <type> = <value>;`; only the value text between `=`
/// and `;` is replaced.
///
/// Returns error.MissingConstant when the file does not contain the
/// expected line, so typos in flag wiring surface immediately.
pub fn editedConstantSource(
    allocator: std.mem.Allocator,
    existing: []const u8,
    comptime name: []const u8,
    value_text: []const u8,
) ![]const u8 {
    var line_start: usize = 0;
    while (std.mem.indexOfScalarPos(u8, existing, line_start, '\n')) |line_end| {
        if (constantValueBounds(existing[line_start..line_end], name)) |bounds| {
            return spliceConstantValue(allocator, existing, line_start, bounds, value_text);
        }
        line_start = line_end + 1;
    }
    // Final line without trailing newline.
    if (constantValueBounds(existing[line_start..], name)) |bounds| {
        return spliceConstantValue(allocator, existing, line_start, bounds, value_text);
    }
    return error.MissingConstant;
}

/// Bounds `[start, end)` of the value text on one `pub const <name> ...`
/// line, relative to the line slice, or null when the line declares a
/// different constant. The name must be followed by a space, ':' or '=',
/// so `ast` never matches `ast_for_terminals`.
fn constantValueBounds(line: []const u8, comptime name: []const u8) ?[2]usize {
    const prefix = "pub const ";
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    const after_prefix = line[prefix.len..];
    if (!std.mem.startsWith(u8, after_prefix, name)) return null;
    const rest = after_prefix[name.len..];
    if (rest.len == 0) return null;
    if (rest[0] != ' ' and rest[0] != ':' and rest[0] != '=') return null;
    const eq_rel = std.mem.indexOfScalar(u8, line, '=') orelse return null;
    if (eq_rel < prefix.len + name.len) return null;
    if (line.len == 0 or line[line.len - 1] != ';') return null;
    var value_start = eq_rel + 1;
    while (value_start < line.len and (line[value_start] == ' ' or line[value_start] == '\t')) : (value_start += 1) {}
    var value_end = line.len - 1;
    while (value_end > value_start and (line[value_end - 1] == ' ' or line[value_end - 1] == '\t' or line[value_end - 1] == '\r')) : (value_end -= 1) {}
    return .{ value_start, value_end };
}

/// Emits `existing` with the constant value on the line starting at
/// `line_start` replaced by `value_text`. `bounds` are value offsets
/// relative to that line, as returned by `constantValueBounds`.
fn spliceConstantValue(
    allocator: std.mem.Allocator,
    existing: []const u8,
    line_start: usize,
    bounds: [2]usize,
    value_text: []const u8,
) ![]const u8 {
    var output = std.Io.Writer.Allocating.init(allocator);
    defer output.deinit();
    try output.writer.print("{s}{s}{s}", .{
        existing[0 .. line_start + bounds[0]],
        value_text,
        existing[line_start + bounds[1] ..],
    });
    return allocator.dupe(u8, output.written());
}
