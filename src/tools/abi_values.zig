//! Writes or checks every checked-in copy of the C ABI's named values, from
//! the single declaration in bindings/abi_values.zon.
//!
//! Usage: abi-values [--check | --write]
//!
//! `zig build abi-values` runs this with `--write`; the `build` test suite
//! runs the same renderers (src/tools/abi_values_gen.zig) as a freshness
//! test.

const std = @import("std");
const abi_values = @import("abi_values_gen.zig");

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.skip();

    var mode: enum { check, write } = .check;
    var mode_given = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--check")) {
            if (mode_given) usage();
            mode = .check;
            mode_given = true;
        } else if (std.mem.eql(u8, arg, "--write")) {
            if (mode_given) usage();
            mode = .write;
            mode_given = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            usage();
        } else {
            usage();
        }
    }

    var arena_state: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const decl = try abi_values.loadDeclaration(init.io, init.gpa, arena);
    switch (mode) {
        .check => try abi_values.checkAll(init.io, arena, &decl),
        .write => {
            try abi_values.writeAll(init.io, arena, &decl);
            std.debug.print("abi values: wrote {d} generated copies from {s}\n", .{
                abi_values.copyCount(),
                abi_values.declaration_path,
            });
        },
    }
}

fn usage() noreturn {
    std.debug.print("usage: abi-values [--check | --write]\n", .{});
    std.process.exit(1);
}
