const std = @import("std");
const common = @import("generator_common");

/// Rewrites one constant's value inside an existing `config.zig`, preserving
/// every other byte of the file (comments, ordering, formatting). The file
/// must follow the layout this module documents and writes: the constant
/// appears as a single `pub const <name> = <value>;` line.
///
/// This is the CLI's only mechanism for honoring option flags: a flag edits
/// the constant in place, and regeneration is never required for the edit
/// itself — consumers recompile against the new value.
///
/// Returns error.MissingConstant when the file does not contain the
/// expected line, so typos in flag wiring surface immediately.
pub fn editedConstantSource(
    allocator: std.mem.Allocator,
    existing: []const u8,
    comptime name: []const u8,
    value_text: []const u8,
) ![]const u8 {
    const prefix = "pub const " ++ name ++ " = ";
    var line_start: usize = 0;
    while (std.mem.indexOfScalarPos(u8, existing, line_start, '\n')) |line_end| {
        const line = existing[line_start..line_end];
        if (std.mem.startsWith(u8, line, prefix) and line[line.len - 1] == ';') {
            return rewriteConstantLine(allocator, existing, line_start, line_end, prefix, value_text);
        }
        line_start = line_end + 1;
    }
    // Final line without trailing newline.
    if (std.mem.startsWith(u8, existing[line_start..], prefix)) {
        const line = existing[line_start..];
        if (line[line.len - 1] == ';') {
            return rewriteConstantLine(allocator, existing, line_start, existing.len, prefix, value_text);
        }
    }
    return error.MissingConstant;
}

/// Emits `existing` with the constant line between `start` and `end`
/// rewritten, as caller-owned freshly allocated memory.
fn rewriteConstantLine(
    allocator: std.mem.Allocator,
    existing: []const u8,
    start: usize,
    end: usize,
    prefix: []const u8,
    value_text: []const u8,
) ![]const u8 {
    var output = std.Io.Writer.Allocating.init(allocator);
    defer output.deinit();
    try output.writer.print("{s}{s}{s};{s}", .{
        existing[0..start],
        prefix,
        value_text,
        existing[end..],
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
