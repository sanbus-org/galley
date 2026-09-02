const std = @import("std");
const common = @import("generator_common");

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

/// Writes a complete, documented `config.zig` carrying one value per
/// generation-time option.
///
/// This is the single source of truth for the config file's shape and
/// documentation. Both the CLI (project bootstrap) and the test harness's
/// parser-generation tool delegate here, so option flags expressed anywhere
/// materialize as edited constants in the written file rather than as
/// generator-side overrides.
///
/// The contract of the produced file: constants only, generation-time options
/// only; parse-time configuration belongs to session options instead.
pub fn write(
    writer: *std.Io.Writer,
    options: common.Options,
    indentation_syntax: bool,
) !void {
    try writer.writeAll(
        \\//! Parser-generation configuration.
        \\//!
        \\//! Contract of this file:
        \\//! - **Constants only.** Never define functions here.
        \\//! - **Generation-time options only.** Every value below is compiled
        \\//!   into the parser when the consuming project is built; changing a
        \\//!   value requires rebuilding the project, never regenerating the
        \\//!   parser.
        \\//! - **Parse-time configuration does not belong here.** Per-session
        \\//!   settings (maximum error count, dynamic message overrides,
        \\//!   reporters) are set through parse/session options in your code.
        \\
    );
    try writeBool(writer, "ast",
        \\/// Construct an abstract syntax tree while parsing.
        \\///
        \\/// true  - construct AST nodes and expose tree APIs.
        \\/// false - skip AST construction entirely for maximum throughput;
        \\///         procedure hooks still run.
        \\
    , options.with_ast);
    try writeBool(writer, "procedures",
        \\/// Enable grammar-annotated procedure hooks.
        \\///
        \\/// true  - procedures attached with @procedures(...) annotations run at
        \\///         their annotated positions.
        \\/// false - procedure hooks are never invoked.
        \\
    , options.with_procedures);
    try writeBool(writer, "allow_no_ast_tree_procedures",
        \\/// Allow standard tree-manipulation helper procedures to be called when
        \\/// AST construction is disabled.
        \\///
        \\/// true  - helpers become no-ops instead of failing to compile.
        \\/// false - calling them without an AST is a compile-time error.
        \\/// Only meaningful when ast = false.
        \\
    , options.allow_no_ast_tree_procedures);
    try writeBool(writer, "error_recovery",
        \\/// Enable syntax-error recovery.
        \\///
        \\/// true  - recovery runs automatically, or through the grammar's
        \\///         explicit @recovery(...) points when the grammar declares any.
        \\/// false - parsing stops at the first syntax error.
        \\
    , options.with_error_recovery);
    try writeBool(writer, "ast_for_terminals",
        \\/// Include terminal tokens as AST leaf nodes.
        \\///
        \\/// true  - terminals appear in the tree alongside variables.
        \\/// false - only variables produce AST nodes.
        \\
    , options.ast_for_terminals);
    try writer.print(
        \\/// Track line and column positions during lexing.
        \\///
        \\/// null - decide by build mode: tracking is enabled in Debug and
        \\///        ReleaseSafe (better diagnostics) and disabled in ReleaseFast
        \\///        (best throughput).
        \\/// true / false - force tracking on or off regardless of build mode.
        \\pub const position_tracking: ?bool = {s};
        \\
        \\/// Read large input files incrementally instead of loading them whole.
        \\///
        \\/// true  - input is streamed in chunks; useful for inputs larger than
        \\///         memory or when startup latency matters.
        \\/// false - complete files are loaded before parsing.
        \\pub const input_streaming = {};
        \\
        \\/// Enable indentation-aware lexing (Python-style significant
        \\/// indentation).
        \\///
        \\/// true  - the lexer emits indentation/deduction tokens derived from
        \\///         leading whitespace.
        \\/// false - whitespace is insignificant.
        \\pub const indentation_syntax = {};
        \\
        \\/// Static syntax-error message overrides baked into the generated
        \\/// parser.
        \\///
        \\/// Each entry replaces Galley's default message for one diagnostic
        \\/// site:
        \\/// - The key is the innermost variable name where the error occurs,
        \\///   or "*" to override every site that has no specific entry.
        \\/// - Non-identifier keys need @"..." quoting, e.g. .@"*".
        \\/// - Values may contain placeholders expanded against each diagnostic:
        \\///   {{line}}, {{column}}, {{unexpected}}, {{expected}}, {{context}}.
        \\///   Unknown placeholders are emitted verbatim.
        \\///
        \\/// Dynamic per-session overrides take precedence over these entries;
        \\/// entries here take precedence over the generated default-message
        \\/// hooks.
        \\pub const error_messages = .{{}};
        \\
        \\
    , .{
        if (options.with_position_tracking) |enabled| if (enabled) "true" else "false" else "null",
        options.with_input_streaming,
        indentation_syntax,
    });
}

fn writeBool(
    writer: *std.Io.Writer,
    comptime name: []const u8,
    comptime doc: []const u8,
    value: bool,
) !void {
    try writer.print("{s}pub const {s} = {};\n\n", .{ doc, name, value });
}
