const std = @import("std");

pub const Suite = enum {
    build,
    generator,
    runtime,
    matrix,
    matrix_compile,
    matrix_api,
    matrix_error,
    matrix_cli,
    galley_parity,

    pub fn isMatrix(self: Suite) bool {
        return switch (self) {
            .matrix, .matrix_compile, .matrix_api, .matrix_error, .matrix_cli => true,
            else => false,
        };
    }

    pub fn supportsNameFilter(self: Suite) bool {
        return switch (self) {
            .build, .generator, .runtime, .matrix_api, .matrix_error => true,
            else => false,
        };
    }
};

pub const Selection = struct {
    suites: []const Suite,
    cases: []const []const u8,
    names: []const []const u8,
    is_filtered: bool,

    pub fn parse(allocator: std.mem.Allocator, filters: []const []const u8) !Selection {
        return parseInternal(allocator, filters, true);
    }

    fn parseInternal(allocator: std.mem.Allocator, filters: []const []const u8, report_errors: bool) !Selection {
        var suites: std.ArrayList(Suite) = .empty;
        errdefer suites.deinit(allocator);
        var cases: std.ArrayList([]const u8) = .empty;
        errdefer cases.deinit(allocator);
        var names: std.ArrayList([]const u8) = .empty;
        errdefer names.deinit(allocator);

        for (filters) |filter| {
            const separator = std.mem.indexOfScalar(u8, filter, ':') orelse {
                if (report_errors) std.log.err("invalid test filter '{s}': use suite:<suite>, case:<parser-language>, or name:<test-name>", .{filter});
                return error.InvalidTestFilter;
            };
            const prefix = filter[0..separator];
            const value = filter[separator + 1 ..];
            if (value.len == 0) {
                if (report_errors) std.log.err("invalid test filter '{s}': the value cannot be empty", .{filter});
                return error.InvalidTestFilter;
            }

            if (std.mem.eql(u8, prefix, "suite")) {
                const suite = parseSuite(value) orelse {
                    if (report_errors) std.log.err("unknown test suite '{s}'", .{value});
                    return error.InvalidTestFilter;
                };
                appendUnique(Suite, allocator, &suites, suite);
            } else if (std.mem.eql(u8, prefix, "case")) {
                appendUnique([]const u8, allocator, &cases, value);
            } else if (std.mem.eql(u8, prefix, "name")) {
                appendUnique([]const u8, allocator, &names, value);
            } else {
                if (report_errors) std.log.err("unknown test filter prefix '{s}': expected suite, case, or name", .{prefix});
                return error.InvalidTestFilter;
            }
        }

        const pending: Selection = .{
            .suites = suites.items,
            .cases = cases.items,
            .names = names.items,
            .is_filtered = filters.len != 0,
        };
        try pending.validate(report_errors);

        const owned_suites = try suites.toOwnedSlice(allocator);
        errdefer allocator.free(owned_suites);
        const owned_cases = try cases.toOwnedSlice(allocator);
        errdefer allocator.free(owned_cases);
        const owned_names = try names.toOwnedSlice(allocator);
        return .{
            .suites = owned_suites,
            .cases = owned_cases,
            .names = owned_names,
            .is_filtered = filters.len != 0,
        };
    }

    pub fn includes(self: Selection, suite: Suite) bool {
        if (!self.is_filtered) return true;
        if (self.suites.len == 0) return self.cases.len != 0 and suite.isMatrix() and suite != .matrix;

        for (self.suites) |selected| {
            if (selected == suite) return true;
            if (selected == .matrix and suite.isMatrix() and suite != .matrix) return true;
        }
        return false;
    }

    pub fn includesMatrix(self: Selection) bool {
        return self.includes(.matrix_compile) or
            self.includes(.matrix_api) or
            self.includes(.matrix_error) or
            self.includes(.matrix_cli);
    }

    pub fn matchesCase(self: Selection, case_name: []const u8) bool {
        if (self.cases.len == 0) return true;
        for (self.cases) |selected| {
            if (std.mem.eql(u8, selected, case_name)) return true;
        }
        return false;
    }

    fn validate(self: Selection, report_errors: bool) !void {
        if (self.names.len != 0) {
            if (self.suites.len == 0) {
                if (report_errors) std.log.err("name: filters require an explicit Zig test suite", .{});
                return error.InvalidTestFilter;
            }
            for (self.suites) |suite| {
                if (!suite.supportsNameFilter()) {
                    if (report_errors) std.log.err("suite:{s} cannot be combined with name: filters", .{suiteName(suite)});
                    return error.InvalidTestFilter;
                }
            }
        }

        if (self.cases.len != 0) {
            for (self.suites) |suite| {
                if (!suite.isMatrix()) {
                    if (report_errors) std.log.err("case: filters can only be combined with matrix suites", .{});
                    return error.InvalidTestFilter;
                }
            }
        }
    }
};

pub fn suiteName(suite: Suite) []const u8 {
    return switch (suite) {
        .build => "build",
        .generator => "generator",
        .runtime => "runtime",
        .matrix => "matrix",
        .matrix_compile => "matrix-compile",
        .matrix_api => "matrix-api",
        .matrix_error => "matrix-error",
        .matrix_cli => "matrix-cli",
        .galley_parity => "galley-parity",
    };
}

fn parseSuite(value: []const u8) ?Suite {
    inline for (std.meta.tags(Suite)) |suite| {
        if (std.mem.eql(u8, value, suiteName(suite))) return suite;
    }
    return null;
}

fn appendUnique(
    comptime T: type,
    allocator: std.mem.Allocator,
    list: *std.ArrayList(T),
    value: T,
) void {
    for (list.items) |existing| {
        const equal = if (T == []const u8)
            std.mem.eql(u8, existing, value)
        else
            existing == value;
        if (equal) return;
    }
    list.append(allocator, value) catch @panic("OOM");
}

test "unfiltered selection includes every suite and case" {
    const selection = try Selection.parse(std.testing.allocator, &.{});
    defer std.testing.allocator.free(selection.suites);
    defer std.testing.allocator.free(selection.cases);
    defer std.testing.allocator.free(selection.names);

    try std.testing.expect(selection.includes(.generator));
    try std.testing.expect(selection.includes(.matrix_api));
    try std.testing.expect(selection.includes(.galley_parity));
    try std.testing.expect(selection.matchesCase("ll-sanbus"));
}

test "selectors OR within a type and AND across types" {
    const selection = try Selection.parse(std.testing.allocator, &.{
        "suite:matrix-api",
        "suite:matrix-error",
        "case:ll-sanbus",
        "case:lr-json",
        "name:parse bytes",
        "name:parse files",
    });
    defer std.testing.allocator.free(selection.suites);
    defer std.testing.allocator.free(selection.cases);
    defer std.testing.allocator.free(selection.names);

    try std.testing.expect(selection.includes(.matrix_api));
    try std.testing.expect(selection.includes(.matrix_error));
    try std.testing.expect(!selection.includes(.matrix_cli));
    try std.testing.expect(selection.matchesCase("ll-sanbus"));
    try std.testing.expect(selection.matchesCase("lr-json"));
    try std.testing.expect(!selection.matchesCase("ll-json"));
    try std.testing.expectEqual(@as(usize, 2), selection.names.len);
}

test "case selector defaults to the complete matrix suite" {
    const selection = try Selection.parse(std.testing.allocator, &.{"case:ll-sanbus"});
    defer std.testing.allocator.free(selection.suites);
    defer std.testing.allocator.free(selection.cases);
    defer std.testing.allocator.free(selection.names);

    try std.testing.expect(selection.includes(.matrix_compile));
    try std.testing.expect(selection.includes(.matrix_api));
    try std.testing.expect(selection.includes(.matrix_error));
    try std.testing.expect(selection.includes(.matrix_cli));
    try std.testing.expect(!selection.includes(.generator));
    try std.testing.expect(!selection.includes(.galley_parity));
}

test "invalid selector forms are rejected" {
    try std.testing.expectError(error.InvalidTestFilter, Selection.parseInternal(std.testing.allocator, &.{"ll-sanbus"}, false));
    try std.testing.expectError(error.InvalidTestFilter, Selection.parseInternal(std.testing.allocator, &.{"suite:unknown"}, false));
    try std.testing.expectError(error.InvalidTestFilter, Selection.parseInternal(std.testing.allocator, &.{"name:dropSelf"}, false));
    try std.testing.expectError(error.InvalidTestFilter, Selection.parseInternal(std.testing.allocator, &.{ "suite:runtime", "case:ll-sanbus" }, false));
    try std.testing.expectError(error.InvalidTestFilter, Selection.parseInternal(std.testing.allocator, &.{ "suite:matrix-cli", "name:parse" }, false));
}
