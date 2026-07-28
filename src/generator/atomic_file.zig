const std = @import("std");

pub const Mode = enum {
    create,
    replace,
};

pub fn write(
    io: std.Io,
    dir: std.Io.Dir,
    sub_path: []const u8,
    mode: Mode,
    context: anytype,
    comptime write_fn: anytype,
) !void {
    const permissions = switch (mode) {
        .create => std.Io.File.Permissions.default_file,
        .replace => blk: {
            const stat = dir.statFile(io, sub_path, .{}) catch |err| switch (err) {
                error.FileNotFound => break :blk std.Io.File.Permissions.default_file,
                else => |e| return e,
            };
            break :blk stat.permissions;
        },
    };

    var atomic = try dir.createFileAtomic(io, sub_path, .{
        .permissions = permissions,
        .replace = mode == .replace,
    });
    defer atomic.deinit(io);

    var buffer: [8192]u8 = undefined;
    var file_writer = atomic.file.writer(io, &buffer);
    try write_fn(context, &file_writer.interface);
    try file_writer.interface.flush();

    switch (mode) {
        .create => try atomic.link(io),
        .replace => try atomic.replace(io),
    }
}

pub fn writeAll(io: std.Io, dir: std.Io.Dir, sub_path: []const u8, mode: Mode, contents: []const u8) !void {
    return write(io, dir, sub_path, mode, contents, struct {
        fn emit(bytes: []const u8, writer: *std.Io.Writer) !void {
            try writer.writeAll(bytes);
        }
    }.emit);
}

test "failed atomic replacement preserves the destination" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "output", .data = "original" });

    try std.testing.expectError(error.InjectedFailure, write(
        std.testing.io,
        tmp.dir,
        "output",
        .replace,
        {},
        struct {
            fn emit(_: void, writer: *std.Io.Writer) !void {
                try writer.writeAll("partial replacement");
                return error.InjectedFailure;
            }
        }.emit,
    ));

    const contents = try tmp.dir.readFileAlloc(std.testing.io, "output", std.testing.allocator, .limited(1024));
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqualStrings("original", contents);
}

test "atomic output replaces and creates only after successful writes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "output", .data = "original" });

    try writeAll(std.testing.io, tmp.dir, "output", .replace, "replacement");
    const replacement = try tmp.dir.readFileAlloc(std.testing.io, "output", std.testing.allocator, .limited(1024));
    defer std.testing.allocator.free(replacement);
    try std.testing.expectEqualStrings("replacement", replacement);

    try writeAll(std.testing.io, tmp.dir, "created", .create, "new");
    try std.testing.expectError(
        error.PathAlreadyExists,
        writeAll(std.testing.io, tmp.dir, "created", .create, "overwritten"),
    );
    const created = try tmp.dir.readFileAlloc(std.testing.io, "created", std.testing.allocator, .limited(1024));
    defer std.testing.allocator.free(created);
    try std.testing.expectEqualStrings("new", created);
}
