//! Renders every checked-in copy of the C ABI's named values — the C header,
//! the Python, JavaScript, Java, Rust and Go bindings, and the docs page —
//! from the single declaration in `bindings/abi_values.zon`. capi.zig
//! imports the declaration at comptime instead; there is no generated copy in
//! the core.
//!
//! Layout: every artifact is a list of `Block`s. A region block replaces the
//! text between its two marker lines in the checked-in file:
//!
//!     // >>> generated: <id> (bindings/abi_values.zon; regenerate: zig build abi-values)
//!     ...rendered text...
//!     // <<< generated: <id>
//!
//! A whole-file block is the entire file, banner included. `checkAll`
//! re-renders every block and compares it byte for byte with the checked-in
//! text (the `build` test suite runs it); `writeAll` rewrites the files
//! (`zig build abi-values`).
//!
//! One rule per host turns the declaration into each host's names:
//!
//!   * C: `prefix ++ name`, `prefix ++ NAME` for the sentinels.
//!   * Python: class names are PascalCase of the table's `name`, members are
//!     UPPER_SNAKE of the entry's `name`. Only the node-address sentinel is a
//!     module constant: a missing variable reads as `None`.
//!   * JavaScript and Java: enum names are PascalCase of the table's `name`;
//!     members are PascalCase / UPPER_SNAKE of the entry's `name`.
//!   * Rust: the status table renders as the crate's `Error` type — a status
//!     is this language's error — and every other table as PascalCase of its
//!     name; members are PascalCase of the entry's `name` (`error_` dropped
//!     for statuses).
//!   * Go: the status table renders as `Error` with `Err*` constants — same
//!     idiom — and every other table as PascalCase of its name; members are
//!     the type name plus PascalCase of the entry's `name`, with `ast`, `io`
//!     and `lhs` as initialisms.
//!
//! Entry docs are required; every rendering that has a comment syntax prints
//! them. The declaration itself carries no host tables.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const declaration_path = "bindings/abi_values.zon";
const max_file_size = 4 * 1024 * 1024;

pub const schema = struct {
    pub const Entry = struct {
        name: []const u8,
        value: i64,
        text: []const u8 = "",
        carries_diagnostic: bool = false,
        unsigned: bool = false,
        doc: []const u8,
    };
    pub const Table = struct {
        name: []const u8,
        prefix: []const u8,
        title: []const u8,
        doc: []const u8,
        entries: []const Entry,
    };
    pub const Declaration = struct {
        statuses: Table,
        diagnostic_kinds: Table,
        recovery_targets: Table,
        resume_sides: Table,
        parser_types: Table,
        recovery_modes: Table,
        sentinels: Table,
    };
};

const Family = enum {
    statuses,
    diagnostic_kinds,
    recovery_targets,
    resume_sides,
    parser_types,
    recovery_modes,
    sentinels,
};

const families = [_]Family{
    .statuses,
    .diagnostic_kinds,
    .recovery_targets,
    .resume_sides,
    .parser_types,
    .recovery_modes,
    .sentinels,
};

/// The order the typed enums are rendered in the Python, JavaScript and Java
/// copies, unchanged from the files these replace.
const typed_families = [_]Family{
    .parser_types,
    .recovery_modes,
    .diagnostic_kinds,
    .recovery_targets,
    .resume_sides,
    .statuses,
};

fn table(decl: *const schema.Declaration, family: Family) schema.Table {
    return switch (family) {
        .statuses => decl.statuses,
        .diagnostic_kinds => decl.diagnostic_kinds,
        .recovery_targets => decl.recovery_targets,
        .resume_sides => decl.resume_sides,
        .parser_types => decl.parser_types,
        .recovery_modes => decl.recovery_modes,
        .sentinels => decl.sentinels,
    };
}

fn isStatus(t: schema.Table) bool {
    return std.mem.eql(u8, t.name, "status");
}

fn isSentinel(t: schema.Table) bool {
    return std.mem.eql(u8, t.name, "sentinel");
}

// ---------------------------------------------------------------------------
// Loading and validation
// ---------------------------------------------------------------------------

pub fn loadDeclaration(io: std.Io, gpa: Allocator, arena: Allocator) !schema.Declaration {
    const source = std.Io.Dir.cwd().readFileAlloc(io, declaration_path, arena, .limited(max_file_size)) catch |err| switch (err) {
        error.FileNotFound => {
            std.debug.print("abi values: {s} is missing\n", .{declaration_path});
            return err;
        },
        error.StreamTooLong => {
            std.debug.print("abi values: {s} is larger than {d} bytes\n", .{ declaration_path, max_file_size });
            return error.InvalidDeclaration;
        },
        else => return err,
    };
    const source_z = try arena.dupeSentinel(u8, source, 0);
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    const decl = std.zon.parse.fromSlice(schema.Declaration, .{
        .gpa = gpa,
        .arena = arena,
        .source = source_z,
        .diagnostics = &diagnostics,
    }) catch |err| switch (err) {
        error.ParseZon => {
            diagnostics.log(declaration_path);
            return error.InvalidDeclaration;
        },
        error.OutOfMemory => return err,
    };
    try validate(arena, &decl);
    return decl;
}

fn isSnakeCase(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |c| {
        if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '_')) return false;
    }
    return true;
}

fn fullCName(arena: Allocator, t: schema.Table, e: schema.Entry, uppercase_stem: bool) ![]const u8 {
    const stem = if (uppercase_stem) try upperStem(arena, e.name) else e.name;
    return std.mem.concat(arena, u8, &.{ t.prefix, stem });
}

fn validate(arena: Allocator, decl: *const schema.Declaration) !void {
    for (families) |family| {
        const t = table(decl, family);
        if (!isSnakeCase(t.name) or t.prefix.len == 0 or t.title.len == 0 or t.doc.len == 0) {
            std.debug.print("abi values: {s}.{s}: name, prefix, title and doc must be non-empty\n", .{ declaration_path, @tagName(family) });
            return error.InvalidDeclaration;
        }
        if (t.entries.len == 0) {
            std.debug.print("abi values: {s}.{s}: no entries\n", .{ declaration_path, @tagName(family) });
            return error.InvalidDeclaration;
        }
    }
    var seen: std.ArrayListUnmanaged([]const u8) = .empty;
    for (families) |family| {
        const t = table(decl, family);
        const sentinel = isSentinel(t);
        const status = isStatus(t);
        for (t.entries, 0..) |e, index| {
            if (!isSnakeCase(e.name)) {
                std.debug.print("abi values: {s}.{s}: \"{s}\" is not snake_case\n", .{ declaration_path, @tagName(family), e.name });
                return error.InvalidDeclaration;
            }
            if (e.doc.len == 0) {
                std.debug.print("abi values: {s}.{s}.{s}: doc is required\n", .{ declaration_path, @tagName(family), e.name });
                return error.InvalidDeclaration;
            }
            if (status) {
                if (e.text.len == 0) {
                    std.debug.print("abi values: {s}.{s}.{s}: a status needs its rendered text\n", .{ declaration_path, @tagName(family), e.name });
                    return error.InvalidDeclaration;
                }
            } else {
                if (e.text.len != 0 or e.carries_diagnostic) {
                    std.debug.print("abi values: {s}.{s}.{s}: text and carries_diagnostic are status-only facts\n", .{ declaration_path, @tagName(family), e.name });
                    return error.InvalidDeclaration;
                }
            }
            if (!sentinel and e.unsigned) {
                std.debug.print("abi values: {s}.{s}.{s}: unsigned is a sentinel-only fact\n", .{ declaration_path, @tagName(family), e.name });
                return error.InvalidDeclaration;
            }
            const expected: i64 = if (sentinel)
                std.math.maxInt(i64)
            else if (status)
                -@as(i64, @intCast(index))
            else
                @intCast(index);
            if (e.value != expected) {
                std.debug.print("abi values: {s}.{s}.{s}: value {d}, expected {d}\n", .{ declaration_path, @tagName(family), e.name, e.value, expected });
                return error.InvalidDeclaration;
            }
            const c_name = try fullCName(arena, t, e, sentinel);
            for (seen.items) |other| {
                if (std.mem.eql(u8, other, c_name)) {
                    std.debug.print("abi values: {s}: duplicate C name {s}\n", .{ declaration_path, c_name });
                    return error.InvalidDeclaration;
                }
            }
            try seen.append(arena, c_name);
        }
    }
}

// ---------------------------------------------------------------------------
// Case and name helpers
// ---------------------------------------------------------------------------

fn upperStem(arena: Allocator, name: []const u8) ![]const u8 {
    const out = try arena.alloc(u8, name.len);
    for (name, out) |c, *o| o.* = std.ascii.toUpper(c);
    return out;
}

fn pascalStem(arena: Allocator, name: []const u8, initialisms: []const []const u8) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    var words = std.mem.splitScalar(u8, name, '_');
    while (words.next()) |word| {
        if (word.len == 0) continue;
        var all_upper = false;
        for (initialisms) |initialism| {
            if (std.ascii.eqlIgnoreCase(word, initialism)) {
                all_upper = true;
                break;
            }
        }
        if (all_upper) {
            for (word) |c| try out.writer.writeByte(std.ascii.toUpper(c));
        } else {
            try out.writer.writeByte(std.ascii.toUpper(word[0]));
            try out.writer.writeAll(word[1..]);
        }
    }
    return arena.dupe(u8, out.written());
}

fn camelStem(arena: Allocator, name: []const u8) ![]const u8 {
    const pascal = try pascalStem(arena, name, &.{});
    if (pascal.len == 0) return pascal;
    const out = try arena.dupe(u8, pascal);
    out[0] = std.ascii.toLower(out[0]);
    return out;
}

fn hostTypeName(arena: Allocator, t: schema.Table) ![]const u8 {
    return pascalStem(arena, t.name, &.{});
}

fn statusStem(e: schema.Entry) []const u8 {
    return if (std.mem.startsWith(u8, e.name, "error_")) e.name["error_".len..] else e.name;
}

fn rustStatusVariant(arena: Allocator, e: schema.Entry) ![]const u8 {
    return pascalStem(arena, statusStem(e), &.{});
}

const go_initialisms = [_][]const u8{ "ast", "io", "lhs" };

fn goMember(arena: Allocator, t: schema.Table, e: schema.Entry) ![]const u8 {
    if (isStatus(t)) {
        return std.mem.concat(arena, u8, &.{ "Err", try pascalStem(arena, statusStem(e), &go_initialisms) });
    }
    return std.mem.concat(arena, u8, &.{ try hostTypeName(arena, t), try pascalStem(arena, e.name, &go_initialisms) });
}

fn goSentinelName(arena: Allocator, e: schema.Entry) ![]const u8 {
    return camelStem(arena, e.name);
}

// ---------------------------------------------------------------------------
// Doc rendering
// ---------------------------------------------------------------------------

const DocMode = enum { keep, strip, javadoc };

const Token = struct { start: usize, end: usize };

fn nextToken(text: []const u8, from: usize) ?Token {
    var index = from;
    while (index < text.len and std.ascii.isWhitespace(text[index])) index += 1;
    if (index == text.len) return null;
    const start = index;
    while (index < text.len) {
        const c = text[index];
        if (std.ascii.isWhitespace(c)) break;
        if (c == '`') {
            index += 1;
            while (index < text.len and text[index] != '`') index += 1;
            if (index < text.len) index += 1;
            continue;
        }
        index += 1;
    }
    return .{ .start = start, .end = index };
}

fn transformToken(arena: Allocator, token: []const u8, mode: DocMode) ![]const u8 {
    switch (mode) {
        .keep => return token,
        .strip => {
            var out: std.ArrayListUnmanaged(u8) = .empty;
            for (token) |c| {
                if (c != '`') try out.append(arena, c);
            }
            return out.toOwnedSlice(arena);
        },
        .javadoc => {
            var out: std.ArrayListUnmanaged(u8) = .empty;
            var index: usize = 0;
            while (index < token.len) {
                if (token[index] == '`') {
                    const close = std.mem.indexOfScalar(u8, token[index + 1 ..], '`') orelse token.len;
                    try out.appendSlice(arena, "{@code ");
                    try out.appendSlice(arena, token[index + 1 .. index + 1 + close]);
                    try out.append(arena, '}');
                    index += close + 2;
                } else {
                    try out.append(arena, token[index]);
                    index += 1;
                }
            }
            return out.toOwnedSlice(arena);
        },
    }
}

fn docLines(arena: Allocator, text: []const u8, mode: DocMode, content_width: usize) ![]const []const u8 {
    var lines: std.ArrayListUnmanaged([]const u8) = .empty;
    var line: std.ArrayListUnmanaged(u8) = .empty;
    var index: usize = 0;
    while (nextToken(text, index)) |token| {
        index = token.end;
        const word = try transformToken(arena, text[token.start..token.end], mode);
        if (line.items.len != 0 and line.items.len + 1 + word.len > content_width) {
            try lines.append(arena, try arena.dupe(u8, line.items));
            line.clearRetainingCapacity();
        }
        if (line.items.len != 0) try line.append(arena, ' ');
        try line.appendSlice(arena, word);
    }
    if (line.items.len != 0) try lines.append(arena, try arena.dupe(u8, line.items));
    return lines.toOwnedSlice(arena);
}

fn writeCComment(w: *std.Io.Writer, arena: Allocator, text: []const u8, indent: []const u8) !void {
    const lines = try docLines(arena, text, .strip, 78 -| (indent.len + 3));
    if (lines.len == 0) return;
    try w.print("{s}/* {s}", .{ indent, lines[0] });
    for (lines[1..]) |line| try w.print("\n{s} * {s}", .{ indent, line });
    try w.print("\n{s} */\n", .{indent});
}

fn writeSlashDoc(w: *std.Io.Writer, arena: Allocator, text: []const u8, indent: []const u8, name: []const u8) !void {
    const lines = try docLines(arena, text, .strip, 80 -| (indent.len + 3));
    for (lines, 0..) |line, index| {
        if (index == 0 and name.len != 0) {
            try w.print("{s}// {s}: {s}\n", .{ indent, name, line });
        } else {
            try w.print("{s}// {s}\n", .{ indent, line });
        }
    }
}

fn writeCodeDoc(w: *std.Io.Writer, arena: Allocator, text: []const u8, indent: []const u8) !void {
    const lines = try docLines(arena, text, .keep, 80 -| (indent.len + 4));
    for (lines) |line| try w.print("{s}/// {s}\n", .{ indent, line });
}

fn writeBraceDoc(w: *std.Io.Writer, arena: Allocator, text: []const u8, indent: []const u8) !void {
    const lines = try docLines(arena, text, .keep, 78 -| (indent.len + 3));
    try w.print("{s}/**\n", .{indent});
    for (lines) |line| try w.print("{s} * {s}\n", .{ indent, line });
    try w.print("{s} */\n", .{indent});
}

fn writeJavadoc(w: *std.Io.Writer, arena: Allocator, text: []const u8, indent: []const u8) !void {
    const lines = try docLines(arena, text, .javadoc, 78 -| (indent.len + 3));
    try w.print("{s}/**\n", .{indent});
    for (lines) |line| try w.print("{s} * {s}\n", .{ indent, line });
    try w.print("{s} */\n", .{indent});
}

fn writePyDocstring(w: *std.Io.Writer, arena: Allocator, text: []const u8, indent: []const u8) !void {
    const lines = try docLines(arena, text, .keep, 78 -| (indent.len + 3));
    if (lines.len == 0) return;
    if (lines.len == 1) {
        try w.print("{s}\"\"\"{s}\"\"\"\n", .{ indent, lines[0] });
        return;
    }
    try w.print("{s}\"\"\"{s}\n", .{ indent, lines[0] });
    for (lines[1..], 0..) |line, index| {
        if (index + 2 == lines.len) {
            try w.print("{s}{s}\"\"\"\n", .{ indent, line });
        } else {
            try w.print("{s}{s}\n", .{ indent, line });
        }
    }
}

fn writeSpaces(w: *std.Io.Writer, count: usize) !void {
    var left = count;
    while (left >= 8) : (left -= 8) try w.writeAll("        ");
    switch (left) {
        0 => {},
        1 => try w.writeByte(' '),
        2 => try w.writeAll("  "),
        3 => try w.writeAll("   "),
        4 => try w.writeAll("    "),
        5 => try w.writeAll("     "),
        6 => try w.writeAll("      "),
        7 => try w.writeAll("       "),
        else => unreachable,
    }
}

// ---------------------------------------------------------------------------
// C header
// ---------------------------------------------------------------------------

fn renderHeaderSentinels(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    const t = table(decl, .sentinels);
    for (t.entries, 0..) |e, index| {
        if (index != 0) try w.writeByte('\n');
        try writeCComment(w, arena, e.doc, "");
        const name = try fullCName(arena, t, e, true);
        const value: u64 = @intCast(e.value);
        try w.print("#define {s} 0x{X:0>16}{s}\n", .{ name, value, if (e.unsigned) "ULL" else "LL" });
    }
}

fn writeCEnum(w: *std.Io.Writer, arena: Allocator, t: schema.Table, trailing_comma: bool) !void {
    var width: usize = 0;
    for (t.entries) |e| {
        const name = try fullCName(arena, t, e, isSentinel(t));
        width = @max(width, name.len);
    }
    try w.writeAll("enum {\n");
    for (t.entries, 0..) |e, index| {
        try writeCComment(w, arena, e.doc, "    ");
        const name = try fullCName(arena, t, e, isSentinel(t));
        try w.print("    {s}", .{name});
        try writeSpaces(w, width - name.len);
        try w.print(" = {d}", .{e.value});
        if (trailing_comma or index + 1 != t.entries.len) try w.writeByte(',');
        try w.writeByte('\n');
    }
    try w.writeAll("};\n");
}

fn renderHeaderStatuses(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    try writeCEnum(w, arena, table(decl, .statuses), true);
}

fn renderHeaderFlags(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    try writeCEnum(w, arena, table(decl, .parser_types), false);
    try w.writeByte('\n');
    try writeCEnum(w, arena, table(decl, .recovery_modes), false);
}

fn renderHeaderKinds(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    try writeCEnum(w, arena, table(decl, .diagnostic_kinds), false);
    try w.writeByte('\n');
    try writeCEnum(w, arena, table(decl, .recovery_targets), false);
    try w.writeByte('\n');
    try writeCEnum(w, arena, table(decl, .resume_sides), false);
}

// ---------------------------------------------------------------------------
// Python
// ---------------------------------------------------------------------------

fn writePackedCArray(w: *std.Io.Writer, lhs: []const u8, items: []const []const u8) !void {
    try w.print("    {s} = {{", .{lhs});
    var column: usize = 4 + lhs.len + 4;
    for (items, 0..) |item, index| {
        if (index != 0) {
            if (column + item.len + 3 > 78) {
                try w.writeAll(",\n        ");
                column = 8;
            } else {
                try w.writeAll(", ");
                column += 2;
            }
        }
        try w.writeAll(item);
        column += item.len;
    }
    try w.writeAll("};\n");
}

fn renderPythonEnumArrays(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    for (typed_families) |family| {
        const t = table(decl, family);
        var members: std.ArrayListUnmanaged([]const u8) = .empty;
        var values: std.ArrayListUnmanaged([]const u8) = .empty;
        for (t.entries) |e| {
            try members.append(arena, try std.mem.concat(arena, u8, &.{ "\"", try upperStem(arena, e.name), "\"" }));
            try values.append(arena, try fullCName(arena, t, e, false));
        }
        try writePackedCArray(w, try std.mem.concat(arena, u8, &.{ "static const char *const ", t.name, "_members[]" }), members.items);
        try writePackedCArray(w, try std.mem.concat(arena, u8, &.{ "static const long long ", t.name, "_values[]" }), values.items);
    }
    try w.writeAll("    if (");
    for (typed_families, 0..) |family, index| {
        const t = table(decl, family);
        const class = try hostTypeName(arena, t);
        if (index != 0) try w.writeAll("\n        ");
        try w.print("ADD_INT_ENUM(module, \"{s}\", {s}) < 0", .{ class, t.name });
        if (index + 1 != typed_families.len) try w.writeAll(" ||");
    }
    try w.writeAll(")\n        return -1;\n");
}

fn renderPythonStatusFlags(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    const t = table(decl, .statuses);
    try w.writeAll("static int status_carries_diagnostic(long long status)\n{\n    switch (status) {\n");
    for (t.entries) |e| {
        if (!e.carries_diagnostic) continue;
        try w.print("    case {s}:\n", .{try fullCName(arena, t, e, false)});
    }
    try w.writeAll("        return 1;\n    default:\n        return 0;\n    }\n}\n");
}

fn renderPyiEnums(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    for (typed_families) |family| {
        const t = table(decl, family);
        try w.print("class {s}(enum.IntEnum):\n", .{try hostTypeName(arena, t)});
        try writePyDocstring(w, arena, t.doc, "    ");
        for (t.entries) |e| {
            try w.print("    {s} = {d}\n", .{ try upperStem(arena, e.name), e.value });
            try writePyDocstring(w, arena, e.doc, "    ");
        }
        try w.writeByte('\n');
    }
    const t = table(decl, .sentinels);
    for (t.entries) |e| {
        // Python answers a node without a variable as `None`, so only the
        // node-address sentinel is a module constant here.
        if (!std.mem.eql(u8, e.name, "invalid_node")) continue;
        try w.print("{s}: Final[int]\n", .{try upperStem(arena, e.name)});
        try writePyDocstring(w, arena, e.doc, "");
    }
}

// ---------------------------------------------------------------------------
// JavaScript
// ---------------------------------------------------------------------------

fn renderJsConstants(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    try w.writeAll("// >>> generated file (bindings/abi_values.zon; regenerate: zig build abi-values)\n\n");
    const sentinels = table(decl, .sentinels);
    for (sentinels.entries) |e| {
        try writeBraceDoc(w, arena, e.doc, "");
        const value: u64 = @intCast(e.value);
        try w.print("export const {s} = 0x{x}n;\n\n", .{ try upperStem(arena, e.name), value });
    }
    var carries: std.ArrayListUnmanaged([]const u8) = .empty;
    for (typed_families) |family| {
        const t = table(decl, family);
        try writeBraceDoc(w, arena, t.doc, "");
        try w.print("export enum {s} {{\n", .{try hostTypeName(arena, t)});
        for (t.entries) |e| {
            try writeBraceDoc(w, arena, e.doc, "  ");
            try w.print("  {s} = {d},\n", .{ try pascalStem(arena, e.name, &.{}), e.value });
        }
        try w.writeAll("}\n\n");
        if (isStatus(t)) {
            const class = try hostTypeName(arena, t);
            for (t.entries) |e| {
                if (!e.carries_diagnostic) continue;
                try carries.append(arena, try std.mem.concat(arena, u8, &.{ class, ".", try pascalStem(arena, e.name, &.{}) }));
            }
        }
    }
    try writeBraceDoc(w, arena, "The statuses that end a parse that ran: a failure with one of them carries the session's diagnostic of that attempt. Every other status carries none.", "");
    try w.writeAll("const CARRIES_DIAGNOSTIC: ReadonlySet<number> = new Set([\n");
    for (carries.items) |name| try w.print("  {s},\n", .{name});
    try w.writeAll("]);\n\n");
    try writeBraceDoc(w, arena, "True when a failure with `status` carries the session's diagnostic: exactly the statuses that ended a parse that ran, whose diagnostic then belongs to that attempt. Every other status carries none.", "");
    try w.writeAll(
        \\export function statusCarriesDiagnostic(status: number): boolean {
        \\  return CARRIES_DIAGNOSTIC.has(status);
        \\}
        \\
    );
}

// ---------------------------------------------------------------------------
// Java
// ---------------------------------------------------------------------------

fn writeJavaPrologue(w: *std.Io.Writer, arena: Allocator, t: schema.Table) !void {
    try w.writeAll("package org.sanbus.galley;\n\n// >>> generated file (bindings/abi_values.zon; regenerate: zig build abi-values)\n\n");
    try writeJavadoc(w, arena, t.doc, "");
}

fn renderJavaStatuses(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    const t = table(decl, .statuses);
    try writeJavaPrologue(w, arena, t);
    try w.writeAll("public enum Status {\n");
    for (t.entries) |e| {
        try writeJavadoc(w, arena, e.doc, "    ");
        try w.print("    {s}({d}, {s}),\n", .{ try upperStem(arena, e.name), e.value, if (e.carries_diagnostic) "true" else "false" });
    }
    try writeJavadoc(w, arena, "Fallback for codes this binding does not know.", "    ");
    try w.writeAll(
        \\    UNKNOWN(Integer.MIN_VALUE, false);
        \\
        \\    private final int code;
        \\    private final boolean carriesDiagnostic;
        \\
        \\    Status(int code, boolean carriesDiagnostic) {
        \\        this.code = code;
        \\        this.carriesDiagnostic = carriesDiagnostic;
        \\    }
        \\
    );
    try writeJavadoc(w, arena, "Raw status code.", "    ");
    try w.writeAll("    public int getCode() { return code; }\n\n");
    try writeJavadoc(w, arena, "Whether a failure with this status carries the session's diagnostic of the parse it ended: true for the statuses that end a parse that ran, false for every other status.", "    ");
    try w.writeAll("    public boolean carriesDiagnostic() { return carriesDiagnostic; }\n\n");
    try writeJavadoc(w, arena, "Single converter for this category: known codes map to their member, anything else maps to `UNKNOWN`.", "    ");
    try w.writeAll(
        \\    public static Status fromCode(long code) {
        \\        for (Status value : values()) {
        \\            if (value != UNKNOWN && value.code == code) return value;
        \\        }
        \\        return UNKNOWN;
        \\    }
        \\}
        \\
    );
}

fn renderJavaFamily(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration, family: Family) !void {
    const t = table(decl, family);
    const class = try hostTypeName(arena, t);
    try writeJavaPrologue(w, arena, t);
    try w.print("public enum {s} {{\n", .{class});
    for (t.entries) |e| {
        try writeJavadoc(w, arena, e.doc, "    ");
        try w.print("    {s}({d}),\n", .{ try upperStem(arena, e.name), e.value });
    }
    try writeJavadoc(w, arena, "Fallback for codes this binding does not know.", "    ");
    try w.writeAll(
        \\    UNKNOWN(-1);
        \\
        \\    private final int code;
        \\
    );
    try w.print("    {s}(int code) {{ this.code = code; }}\n\n", .{class});
    try writeJavadoc(w, arena, "Raw code value.", "    ");
    try w.writeAll("    public int getCode() { return code; }\n\n");
    try writeJavadoc(w, arena, "Single converter for this category: known codes map to their member, anything else maps to `UNKNOWN`.", "    ");
    try w.print(
        \\    public static {s} fromCode(long code) {{
        \\        for ({s} value : values()) {{
        \\            if (value.code == code) return value;
        \\        }}
        \\        return UNKNOWN;
        \\    }}
        \\}}
        \\
    , .{ class, class });
}

fn renderJavaSentinels(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    const t = table(decl, .sentinels);
    for (t.entries, 0..) |e, index| {
        if (index != 0) try w.writeByte('\n');
        try writeJavadoc(w, arena, e.doc, "    ");
        const value: u64 = @intCast(e.value);
        try w.print("    public static final long {s} = 0x{X:0>16}L;\n", .{ try upperStem(arena, e.name), value });
    }
}

fn renderJavaDiagnosticKinds(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    try renderJavaFamily(w, arena, decl, .diagnostic_kinds);
}

fn renderJavaRecoveryTargets(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    try renderJavaFamily(w, arena, decl, .recovery_targets);
}

fn renderJavaResumeSides(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    try renderJavaFamily(w, arena, decl, .resume_sides);
}

fn renderJavaParserTypes(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    try renderJavaFamily(w, arena, decl, .parser_types);
}

fn renderJavaRecoveryModes(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    try renderJavaFamily(w, arena, decl, .recovery_modes);
}

// ---------------------------------------------------------------------------
// Rust
// ---------------------------------------------------------------------------

fn writeRustErrorBody(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    const t = table(decl, .statuses);
    try w.writeAll("/// Failure modes mirroring the status codes of the C API.\n#[derive(Debug, Clone, Copy, PartialEq, Eq)]\npub enum Error {\n");
    for (t.entries) |e| {
        if (e.value == 0) continue;
        try writeCodeDoc(w, arena, e.doc, "    ");
        try w.print("    {s},\n", .{try rustStatusVariant(arena, e)});
    }
    try w.writeAll("}\n\nimpl Error {\n    fn from_status(status: i64) -> Self {\n        match status {\n");
    for (t.entries) |e| {
        if (e.value == 0) continue;
        try w.print("            {d} => Error::{s},\n", .{ e.value, try rustStatusVariant(arena, e) });
    }
    try w.writeAll("            _ => Error::Internal,\n        }\n    }\n");
}

/// The status enum and its code-to-variant match: the part both Rust files
/// carry.
fn renderRustErrorEnum(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    try writeRustErrorBody(w, arena, decl);
    try w.writeAll("}\n");
}

/// The lib-only additions to the shared region: the variant-to-code match and
/// the methods built on it.
fn renderRustLibErrorEnum(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    try writeRustErrorBody(w, arena, decl);
    const t = table(decl, .statuses);
    try w.writeAll("\n    /// The C status code this error mirrors.\n    fn status(&self) -> i64 {\n        match self {\n");
    for (t.entries) |e| {
        if (e.value == 0) continue;
        try w.print("            Error::{s} => {d},\n", .{ try rustStatusVariant(arena, e), e.value });
    }
    try w.writeAll(
        \\        }
        \\    }
        \\
        \\    /// Static description of this error, straight from the library.
        \\    pub fn description(&self) -> &'static str {
        \\        unsafe { cstr(galley_status_string(self.status())).unwrap_or("unknown error") }
        \\    }
        \\}
        \\
    );
}

fn renderRustDiagnosticKinds(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    const t = table(decl, .diagnostic_kinds);
    try w.writeAll("/// Diagnostic classifications mirroring the C API's diagnostic kinds.\n#[derive(Debug, Default, PartialEq, Eq)]\npub enum DiagnosticKind {\n    #[default]\n    None,\n");
    for (t.entries) |e| {
        if (std.mem.eql(u8, e.name, "none")) continue;
        try writeCodeDoc(w, arena, e.doc, "    ");
        try w.print("    {s},\n", .{try pascalStem(arena, e.name, &.{})});
    }
    try w.writeAll("}\n");
}

fn renderRustDiagnosticKindFn(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    const t = table(decl, .diagnostic_kinds);
    try w.writeAll("/// One diagnostic kind code — the C enum value — as an enum, or the status\n/// value it came with. Only a status is negative; the none kind is a real\n/// value.\nfn diagnostic_kind(status: i64) -> Result<DiagnosticKind, Error> {\n    match status {\n");
    for (t.entries) |e| {
        try w.print("        {d} => Ok(DiagnosticKind::{s}),\n", .{ e.value, try pascalStem(arena, e.name, &.{}) });
    }
    try w.writeAll("        refused => Err(Error::from_status(refused)),\n    }\n}\n");
}

fn renderRustSentinels(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    const t = table(decl, .sentinels);
    for (t.entries, 0..) |e, index| {
        if (index != 0) try w.writeByte('\n');
        try writeCodeDoc(w, arena, e.doc, "");
        const name = try upperStem(arena, e.name);
        const value: u64 = @intCast(e.value);
        if (e.unsigned) {
            try w.print("const {s}: u64 = 0x{X:0>16};\n", .{ name, value });
        } else {
            try w.print("const {s}: i64 = 0x{X:0>16};\n", .{ name, value });
        }
    }
}

// ---------------------------------------------------------------------------
// Go
// ---------------------------------------------------------------------------

fn renderGoSentinels(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    const t = table(decl, .sentinels);
    for (t.entries, 0..) |e, index| {
        if (index != 0) try w.writeByte('\n');
        try writeSlashDoc(w, arena, e.doc, "", "");
        const value: u64 = @intCast(e.value);
        const name = try goSentinelName(arena, e);
        if (e.unsigned) {
            try w.print("const {s} = uint64(0x{X:0>16})\n", .{ name, value });
        } else {
            try w.print("const {s} = int64(0x{X:0>16})\n", .{ name, value });
        }
    }
}

fn renderGoStatuses(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    const t = table(decl, .statuses);
    var width: usize = 0;
    for (t.entries) |e| {
        if (e.value == 0) continue;
        width = @max(width, (try goMember(arena, t, e)).len);
    }
    try w.writeAll("// Status codes mirrored from the C API (negative values are failures).\ntype Error int32\n\nconst (\n");
    for (t.entries) |e| {
        if (e.value == 0) continue;
        const name = try goMember(arena, t, e);
        try writeSlashDoc(w, arena, e.doc, "\t", name);
        try w.print("\t{s}", .{name});
        try writeSpaces(w, width - name.len + 1);
        try w.print("Error = {d}\n", .{e.value});
    }
    try w.writeAll(")\n");
}

fn renderGoStatusFlags(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    const t = table(decl, .statuses);
    try w.writeAll("func statusCarriesDiagnostic(code Error) bool {\n\tswitch code {\n\tcase ");
    var column: usize = 6;
    var first = true;
    for (t.entries) |e| {
        if (!e.carries_diagnostic) continue;
        const name = try goMember(arena, t, e);
        if (!first) {
            if (column + name.len + 3 > 80) {
                try w.writeAll(",\n\t\t");
                column = 2;
            } else {
                try w.writeAll(", ");
                column += 2;
            }
        }
        try w.writeAll(name);
        column += name.len;
        first = false;
    }
    try w.writeAll(":\n\t\treturn true\n\t}\n\treturn false\n}\n");
}

fn renderGoDiagnosticKinds(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    const t = table(decl, .diagnostic_kinds);
    var width: usize = 0;
    for (t.entries) |e| width = @max(width, (try goMember(arena, t, e)).len);
    try w.writeAll("type DiagnosticKind int32\n\nconst (\n");
    for (t.entries) |e| {
        const name = try goMember(arena, t, e);
        try writeSlashDoc(w, arena, e.doc, "\t", name);
        try w.print("\t{s}", .{name});
        try writeSpaces(w, width - name.len + 1);
        try w.print("DiagnosticKind = {d}\n", .{e.value});
    }
    try w.writeAll(")\n");
}

fn renderGoRecoveryTargets(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    const t = table(decl, .recovery_targets);
    var width: usize = 0;
    for (t.entries) |e| width = @max(width, (try goMember(arena, t, e)).len);
    try w.writeAll("type RecoveryTarget int32\n\nconst (\n");
    for (t.entries) |e| {
        const name = try goMember(arena, t, e);
        try writeSlashDoc(w, arena, e.doc, "\t", name);
        try w.print("\t{s}", .{name});
        try writeSpaces(w, width - name.len + 1);
        try w.print("RecoveryTarget = {d}\n", .{e.value});
    }
    try w.writeAll(")\n");
}

// ---------------------------------------------------------------------------
// Docs page
// ---------------------------------------------------------------------------

fn cell(arena: Allocator, parts: []const []const u8) ![]const u8 {
    return std.mem.concat(arena, u8, parts);
}

fn pyCell(arena: Allocator, t: schema.Table, e: schema.Entry) ![]const u8 {
    if (isSentinel(t)) {
        if (std.mem.eql(u8, e.name, "invalid_node")) return try upperStem(arena, e.name);
        return "—";
    }
    return cell(arena, &.{ try hostTypeName(arena, t), ".", try upperStem(arena, e.name) });
}

fn jsCell(arena: Allocator, t: schema.Table, e: schema.Entry) ![]const u8 {
    if (isSentinel(t)) return try upperStem(arena, e.name);
    return cell(arena, &.{ try hostTypeName(arena, t), ".", try pascalStem(arena, e.name, &.{}) });
}

fn javaCell(arena: Allocator, t: schema.Table, e: schema.Entry) ![]const u8 {
    if (isSentinel(t)) return cell(arena, &.{ "Galley.", try upperStem(arena, e.name) });
    return cell(arena, &.{ try hostTypeName(arena, t), ".", try upperStem(arena, e.name) });
}

fn rustCell(arena: Allocator, t: schema.Table, e: schema.Entry) ![]const u8 {
    if (isSentinel(t)) return try upperStem(arena, e.name);
    if (isStatus(t)) {
        if (e.value == 0) return "—";
        return cell(arena, &.{ "Error::", try rustStatusVariant(arena, e) });
    }
    if (std.mem.eql(u8, t.name, "diagnostic_kind")) {
        return cell(arena, &.{ "DiagnosticKind::", try pascalStem(arena, e.name, &.{}) });
    }
    return "—";
}

fn goCell(arena: Allocator, t: schema.Table, e: schema.Entry) ![]const u8 {
    if (isSentinel(t)) return try goSentinelName(arena, e);
    if (isStatus(t)) {
        if (e.value == 0) return "—";
        return try goMember(arena, t, e);
    }
    if (std.mem.eql(u8, t.name, "diagnostic_kind") or std.mem.eql(u8, t.name, "recovery_target")) {
        return try goMember(arena, t, e);
    }
    return "—";
}

fn renderDocs(w: *std.Io.Writer, arena: Allocator, decl: *const schema.Declaration) !void {
    try w.writeAll(
        \\# ABI Values
        \\
        \\<!-- >>> generated file (bindings/abi_values.zon; regenerate: zig build abi-values) -->
        \\
        \\Every named value shared by the C ABI and the language bindings is
        \\declared once in
        \\[`bindings/abi_values.zon`](https://github.com/sanbus-org/galley/blob/main/bindings/abi_values.zon)
        \\and rendered into each binding's idiom by
        \\[`src/tools/abi_values_gen.zig`](https://github.com/sanbus-org/galley/blob/main/src/tools/abi_values_gen.zig).
        \\The copies are checked in; `zig build abi-values` regenerates them, and
        \\the `build` test suite fails when one drifts.
        \\
    );
    for (families) |family| {
        const t = table(decl, family);
        const sentinel = isSentinel(t);
        try w.print("\n## {s}\n\n{s}\n\n", .{ t.title, t.doc });
        if (isStatus(t)) {
            try w.writeAll("| Name | Value | Text | Python | JavaScript | Java | Rust | Go |\n| --- | ---: | --- | --- | --- | --- | --- | --- |\n");
        } else {
            try w.writeAll("| Name | Value | Python | JavaScript | Java | Rust | Go |\n| --- | ---: | --- | --- | --- | --- | --- |\n");
        }
        for (t.entries) |e| {
            const c_name = try fullCName(arena, t, e, sentinel);
            if (isStatus(t)) {
                try w.print("| `{s}` | {d} | `{s}` | {s} | {s} | {s} | {s} | {s} |\n", .{
                    c_name,
                    e.value,
                    e.text,
                    try docCell(arena, try pyCell(arena, t, e)),
                    try docCell(arena, try jsCell(arena, t, e)),
                    try docCell(arena, try javaCell(arena, t, e)),
                    try docCell(arena, try rustCell(arena, t, e)),
                    try docCell(arena, try goCell(arena, t, e)),
                });
            } else {
                try w.print("| `{s}` | {d} | {s} | {s} | {s} | {s} | {s} |\n", .{
                    c_name,
                    e.value,
                    try docCell(arena, try pyCell(arena, t, e)),
                    try docCell(arena, try jsCell(arena, t, e)),
                    try docCell(arena, try javaCell(arena, t, e)),
                    try docCell(arena, try rustCell(arena, t, e)),
                    try docCell(arena, try goCell(arena, t, e)),
                });
            }
        }
        try w.writeByte('\n');
        for (t.entries) |e| {
            const c_name = try fullCName(arena, t, e, sentinel);
            try w.print("- **`{s}`** — {s}\n", .{ c_name, e.doc });
        }
    }
}

fn docCell(arena: Allocator, cell_text: []const u8) ![]const u8 {
    if (std.mem.eql(u8, cell_text, "—")) return cell_text;
    return std.mem.concat(arena, u8, &.{ "`", cell_text, "`" });
}

// ---------------------------------------------------------------------------
// Artifacts
// ---------------------------------------------------------------------------

pub const Kind = enum { regions, whole_file };

pub const Block = struct {
    id: []const u8,
    render: *const fn (*std.Io.Writer, Allocator, *const schema.Declaration) anyerror!void,
};

pub const Artifact = struct {
    path: []const u8,
    kind: Kind = .regions,
    blocks: []const Block,
};

pub const artifacts = [_]Artifact{
    .{ .path = "bindings/c/galley.h", .blocks = &.{
        .{ .id = "sentinels", .render = renderHeaderSentinels },
        .{ .id = "statuses", .render = renderHeaderStatuses },
        .{ .id = "flags", .render = renderHeaderFlags },
        .{ .id = "kinds", .render = renderHeaderKinds },
    } },
    .{ .path = "bindings/python/_galley.c", .blocks = &.{
        .{ .id = "status flags", .render = renderPythonStatusFlags },
        .{ .id = "enum arrays", .render = renderPythonEnumArrays },
    } },
    .{ .path = "bindings/python/galley.pyi", .blocks = &.{
        .{ .id = "enums", .render = renderPyiEnums },
    } },
    .{ .path = "bindings/js/core/src/constants.ts", .kind = .whole_file, .blocks = &.{
        .{ .id = "whole file", .render = renderJsConstants },
    } },
    .{ .path = "bindings/java/src/main/java/org/sanbus/galley/Status.java", .kind = .whole_file, .blocks = &.{
        .{ .id = "whole file", .render = renderJavaStatuses },
    } },
    .{ .path = "bindings/java/src/main/java/org/sanbus/galley/DiagnosticKind.java", .kind = .whole_file, .blocks = &.{
        .{ .id = "whole file", .render = renderJavaDiagnosticKinds },
    } },
    .{ .path = "bindings/java/src/main/java/org/sanbus/galley/RecoveryTarget.java", .kind = .whole_file, .blocks = &.{
        .{ .id = "whole file", .render = renderJavaRecoveryTargets },
    } },
    .{ .path = "bindings/java/src/main/java/org/sanbus/galley/ResumeSide.java", .kind = .whole_file, .blocks = &.{
        .{ .id = "whole file", .render = renderJavaResumeSides },
    } },
    .{ .path = "bindings/java/src/main/java/org/sanbus/galley/ParserType.java", .kind = .whole_file, .blocks = &.{
        .{ .id = "whole file", .render = renderJavaParserTypes },
    } },
    .{ .path = "bindings/java/src/main/java/org/sanbus/galley/RecoveryMode.java", .kind = .whole_file, .blocks = &.{
        .{ .id = "whole file", .render = renderJavaRecoveryModes },
    } },
    .{ .path = "bindings/java/src/main/java/org/sanbus/galley/Galley.java", .blocks = &.{
        .{ .id = "sentinels", .render = renderJavaSentinels },
    } },
    .{ .path = "bindings/rust/src/lib.rs", .blocks = &.{
        .{ .id = "error enum", .render = renderRustLibErrorEnum },
        .{ .id = "diagnostic kinds", .render = renderRustDiagnosticKinds },
        .{ .id = "sentinels", .render = renderRustSentinels },
        .{ .id = "diagnostic kind fn", .render = renderRustDiagnosticKindFn },
    } },
    .{ .path = "bindings/rust/src/procedure.rs", .blocks = &.{
        .{ .id = "sentinels", .render = renderRustSentinels },
        .{ .id = "error enum", .render = renderRustErrorEnum },
    } },
    .{ .path = "bindings/go/assets/wrapper.go.tmpl", .blocks = &.{
        .{ .id = "sentinels", .render = renderGoSentinels },
        .{ .id = "statuses", .render = renderGoStatuses },
        .{ .id = "status flags", .render = renderGoStatusFlags },
        .{ .id = "diagnostic kinds", .render = renderGoDiagnosticKinds },
        .{ .id = "recovery targets", .render = renderGoRecoveryTargets },
    } },
    .{ .path = "docs/abi_values.md", .kind = .whole_file, .blocks = &.{
        .{ .id = "whole file", .render = renderDocs },
    } },
};

pub fn copyCount() usize {
    return artifacts.len;
}

// ---------------------------------------------------------------------------
// Region location, checking, writing
// ---------------------------------------------------------------------------

const Region = struct { start: usize, end: usize };

/// The text after a marker prefix on `line`, or null when the line carries
/// no such marker.
fn markerRest(line: []const u8, prefix: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, line, prefix) orelse return null;
    return line[start + prefix.len ..];
}

/// True when `line` carries the open marker of exactly block `id`: the id,
/// whole, followed by the regeneration hint's parenthesis.
fn isOpenMarker(line: []const u8, id: []const u8) bool {
    const rest = markerRest(line, ">>> generated: ") orelse return false;
    return std.mem.startsWith(u8, rest, id) and std.mem.startsWith(u8, rest[id.len..], " (");
}

/// True when `line` carries the close marker of exactly block `id`.
fn isCloseMarker(line: []const u8, id: []const u8) bool {
    const rest = markerRest(line, "<<< generated: ") orelse return false;
    return std.mem.eql(u8, std.mem.trimEnd(u8, rest, " \t\r"), id);
}

fn locateRegion(source: []const u8, path: []const u8, id: []const u8) !Region {
    var lines = std.mem.splitScalar(u8, source, '\n');
    var offset: usize = 0;
    var begin: ?usize = null;
    while (lines.next()) |line| : (offset += line.len + 1) {
        if (isOpenMarker(line, id)) {
            begin = offset + line.len + 1;
        } else if (isCloseMarker(line, id)) {
            if (begin) |b| return .{ .start = b, .end = offset };
            std.debug.print("abi values: {s}: block \"{s}\" closes before it opens\n", .{ path, id });
            return error.MarkerMissing;
        }
    }
    std.debug.print("abi values: {s}: no marker block \"{s}\"\n", .{ path, id });
    return error.MarkerMissing;
}

fn renderBlock(arena: Allocator, block: Block, decl: *const schema.Declaration) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    try block.render(&out.writer, arena, decl);
    return out.written();
}

pub fn checkAll(io: std.Io, arena: Allocator, decl: *const schema.Declaration) !void {
    for (artifacts) |artifact| {
        const source = std.Io.Dir.cwd().readFileAlloc(io, artifact.path, arena, .limited(max_file_size)) catch |err| {
            std.debug.print("abi values: cannot read {s}: {t}\n", .{ artifact.path, err });
            return error.GeneratedCopiesOutOfDate;
        };
        if (artifact.kind == .whole_file) {
            const rendered = try renderBlock(arena, artifact.blocks[0], decl);
            if (!std.mem.eql(u8, source, rendered)) {
                std.debug.print("abi values: {s} is stale ({d} generated bytes); regenerate with `zig build abi-values`\n", .{ artifact.path, rendered.len });
                return error.GeneratedCopiesOutOfDate;
            }
            continue;
        }
        for (artifact.blocks) |block| {
            const region = try locateRegion(source, artifact.path, block.id);
            const rendered = try renderBlock(arena, block, decl);
            if (!std.mem.eql(u8, source[region.start..region.end], rendered)) {
                std.debug.print("abi values: {s} block \"{s}\" is stale ({d} generated bytes); regenerate with `zig build abi-values`\n", .{ artifact.path, block.id, rendered.len });
                return error.GeneratedCopiesOutOfDate;
            }
        }
    }
}

const PendingWrite = struct { path: []const u8, data: []const u8 };

/// The artifact's complete next content: the single rendered block for a
/// whole-file artifact, or the checked-in text with every block between its
/// markers replaced. Reads and renders only; nothing is written here.
fn renderArtifact(io: std.Io, arena: Allocator, artifact: Artifact, decl: *const schema.Declaration) ![]const u8 {
    if (artifact.kind == .whole_file) return renderBlock(arena, artifact.blocks[0], decl);

    const source = std.Io.Dir.cwd().readFileAlloc(io, artifact.path, arena, .limited(max_file_size)) catch |err| {
        std.debug.print("abi values: cannot read {s}: {t}\n", .{ artifact.path, err });
        return error.ArtifactUnreadable;
    };
    var out: std.Io.Writer.Allocating = .init(arena);
    var cursor: usize = 0;
    for (artifact.blocks) |block| {
        const region = try locateRegion(source, artifact.path, block.id);
        if (region.start < cursor) {
            std.debug.print("abi values: {s}: block \"{s}\" overlaps the previous one\n", .{ artifact.path, block.id });
            return error.MarkerMissing;
        }
        try out.writer.writeAll(source[cursor..region.start]);
        try block.render(&out.writer, arena, decl);
        cursor = region.end;
    }
    try out.writer.writeAll(source[cursor..]);
    return out.written();
}

pub fn writeAll(io: std.Io, arena: Allocator, decl: *const schema.Declaration) !void {
    // Render every artifact before writing any of them: a stale marker, a
    // missing file or a failed render leaves the whole tree untouched.
    var pending: std.ArrayListUnmanaged(PendingWrite) = .empty;
    for (artifacts) |artifact| {
        try pending.append(arena, .{
            .path = artifact.path,
            .data = try renderArtifact(io, arena, artifact, decl),
        });
    }
    for (pending.items) |write| {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = write.path, .data = write.data });
    }
}

test "checked-in copies match bindings/abi_values.zon" {
    var arena_state: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const decl = try loadDeclaration(std.testing.io, std.testing.allocator, arena);
    try checkAll(std.testing.io, arena, &decl);
}
