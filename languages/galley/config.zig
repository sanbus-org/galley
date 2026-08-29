//! Parser-generation configuration.
//!
//! Contract of this file:
//! - **Constants only.** Never define functions here.
//! - **Generation-time options only.** Every value below is compiled
//!   into the parser when the consuming project is built; changing a
//!   value requires rebuilding the project, never regenerating the
//!   parser.
//! - **Parse-time configuration does not belong here.** Per-session
//!   settings (maximum error count, dynamic message overrides,
//!   reporters) are set through parse/session options in your code.
/// Construct an abstract syntax tree while parsing.
///
/// true  - construct AST nodes and expose tree APIs.
/// false - skip AST construction entirely for maximum throughput;
///         procedure hooks still run.
pub const ast = true;

/// Enable grammar-annotated procedure hooks.
///
/// true  - procedures attached with @procedures(...) annotations run at
///         their annotated positions.
/// false - procedure hooks are never invoked.
pub const procedures = true;

/// Allow standard tree-manipulation helper procedures to be called when
/// AST construction is disabled.
///
/// true  - helpers become no-ops instead of failing to compile.
/// false - calling them without an AST is a compile-time error.
/// Only meaningful when ast = false.
pub const allow_no_ast_tree_procedures = false;

/// Enable syntax-error recovery.
///
/// true  - recovery runs automatically, or through the grammar's
///         explicit @recovery(...) points when the grammar declares any.
/// false - parsing stops at the first syntax error.
pub const error_recovery = true;

/// Include terminal tokens as AST leaf nodes.
///
/// true  - terminals appear in the tree alongside variables.
/// false - only variables produce AST nodes.
pub const ast_for_terminals = false;

/// Track line and column positions during lexing.
///
/// null - decide by build mode: tracking is enabled in Debug and
///        ReleaseSafe (better diagnostics) and disabled in ReleaseFast
///        (best throughput).
/// true / false - force tracking on or off regardless of build mode.
pub const position_tracking: ?bool = null;

/// Read large input files incrementally instead of loading them whole.
///
/// true  - input is streamed in chunks; useful for inputs larger than
///         memory or when startup latency matters.
/// false - complete files are loaded before parsing.
pub const input_streaming = false;

/// Enable indentation-aware lexing (Python-style significant
/// indentation).
///
/// true  - the lexer emits indentation/deduction tokens derived from
///         leading whitespace.
/// false - whitespace is insignificant.
pub const indentation_syntax = false;

/// Static syntax-error message overrides baked into the generated
/// parser.
///
/// Each entry replaces Galley's default message for one diagnostic
/// site:
/// - The key is the innermost variable name where the error occurs,
///   or "*" to override every site that has no specific entry.
/// - Non-identifier keys need @"..." quoting, e.g. .@"*".
/// - Values may contain placeholders expanded against each diagnostic:
///   {line}, {column}, {unexpected}, {expected}, {context}.
///   Unknown placeholders are emitted verbatim.
///
/// Dynamic per-session overrides take precedence over these entries;
/// entries here take precedence over the generated default-message
/// hooks.
pub const error_messages = .{};
