const std = @import("std");
const common = @import("common.zig");

/// Coverage for the -D config-override splice path, which nothing else in
/// CI exercises: the matrix suites regenerate parsers with explicit flags,
/// while these overrides edit the checked-in `languages/<lang>/config.zig`.
/// This runs the production `common.applyConfigOverrides` sequence over
/// every checked-in language config, so a config missing one of the four
/// spliced constants fails here — in the build suite — instead of
/// mid-benchmark.
const splice_names = [_][]const u8{ "ast", "procedures", "error_recovery", "ast_for_terminals" };

fn overrideWith(comptime name: []const u8, value: bool) common.ConfigOverrides {
    var overrides: common.ConfigOverrides = .{};
    @field(overrides, name) = value;
    return overrides;
}

fn allOverrides(value: bool) common.ConfigOverrides {
    return .{
        .ast = value,
        .procedures = value,
        .error_recovery = value,
        .ast_for_terminals = value,
    };
}

test "every language config carries all four spliced constants" {
    // The API documents its intermediates as arena-owned (the build passes
    // b.allocator); an arena mirrors that here.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var languages = try std.Io.Dir.cwd().openDir(std.testing.io, "languages", .{ .iterate = true });
    defer languages.close(std.testing.io);

    var configs_seen: usize = 0;
    var it = languages.iterate();
    while (try it.next(std.testing.io)) |entry| {
        if (entry.kind != .directory) continue;
        const rel = try std.fmt.allocPrint(allocator, "{s}/config.zig", .{entry.name});
        const base = languages.readFileAlloc(std.testing.io, rel, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        configs_seen += 1;

        // Single-constant splices first, so a missing constant reports its
        // language and name instead of failing opaquely on the full sequence.
        inline for (splice_names) |name| {
            _ = common.applyConfigOverrides(allocator, base, overrideWith(name, true)) catch |err| {
                std.debug.print("languages/{s}: cannot splice {s}: {s}\n", .{ rel, name, @errorName(err) });
                return err;
            };
        }

        // The full production sequence, both polarities: four spliced lines
        // differ between them, so byte-identical results would mean nothing
        // was spliced at all.
        const all_true = try common.applyConfigOverrides(allocator, base, allOverrides(true));
        const all_false = try common.applyConfigOverrides(allocator, base, allOverrides(false));
        try std.testing.expect(!std.mem.eql(u8, all_true, all_false));
    }

    // A wrong working directory or an emptied languages/ must not pass
    // vacuously.
    try std.testing.expect(configs_seen > 0);
}
