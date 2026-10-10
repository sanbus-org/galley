const std = @import("std");
const common = @import("generator_common");
const config_edit = @import("generator_config_edit");

// The constant-editing rules live in `build/config_edit.zig`, shared with
// the build script by sibling import (a src/ path would escape the
// build-tree module path); the generator reaches them by named module.
// Generator callers keep going through this module.
pub const editedConstantSource = config_edit.editedConstantSource;

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
    newline_after_block_end: bool,
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
        \\/// true  - procedures attached with @Name annotations run at
        \\///         their annotated positions.
        \\/// false - procedure hooks are never invoked.
        \\
    , options.with_procedures);
    try writeBool(writer, "error_recovery",
        \\/// Enable syntax-error recovery.
        \\///
        \\/// true  - recovery runs automatically, or through the grammar's
        \\///         explicit @!"..." points when the grammar declares any.
        \\/// false - parsing stops at the first syntax error.
        \\
    , options.with_error_recovery);
    try writeBool(writer, "ast_for_terminals",
        \\/// Include terminal tokens as AST leaf nodes.
        \\///
        \\/// true  - terminals appear in the tree alongside variables.
        \\/// false - only variables produce AST nodes.
        \\///
        \\/// Requires ast or procedures to be enabled.
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
        \\/// After each dedent, emit a control byte that `new_line` matches and
        \\/// every other expected terminal skips.
        \\///
        \\/// true  - a dedent yields `block_end` then that byte, so
        \\///         `new_line`-separated rows continue after a block while
        \\///         closers such as `}}` do not see a leftover newline.
        \\/// false - a dedent yields only `block_end` tokens (the default).
        \\///
        \\/// Requires indentation_syntax to be enabled.
        \\pub const newline_after_block_end = {};
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
        newline_after_block_end,
    });
}

test "write emits newline_after_block_end from its argument" {
    var off = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer off.deinit();
    try write(&off.writer, .{}, false, false);
    try std.testing.expect(std.mem.indexOf(u8, off.written(), "pub const newline_after_block_end = false;") != null);

    var on = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer on.deinit();
    try write(&on.writer, .{}, true, true);
    try std.testing.expect(std.mem.indexOf(u8, on.written(), "pub const newline_after_block_end = true;") != null);
}

fn writeBool(
    writer: *std.Io.Writer,
    comptime name: []const u8,
    comptime doc: []const u8,
    value: bool,
) !void {
    try writer.print("{s}pub const {s} = {};\n\n", .{ doc, name, value });
}
