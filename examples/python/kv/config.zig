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
/// true  - procedures attached with @Name annotations run at
///         their annotated positions.
/// false - procedure hooks are never invoked.
pub const procedures = true;

/// Enable syntax-error recovery.
///
/// true  - recovery runs automatically, or through the grammar's
///         explicit @!"..." points when the grammar declares any.
/// false - parsing stops at the first syntax error.
pub const error_recovery = true;

/// Include terminal tokens as AST leaf nodes.
///
/// true  - terminals appear in the tree alongside variables.
/// false - only variables produce AST nodes.
///
/// Requires ast or procedures to be enabled.
pub const ast_for_terminals = true;

/// Track line and column positions during lexing.
///
/// null - decide by build mode: tracking is enabled in Debug and
///        ReleaseSafe (for debugging) and disabled in ReleaseFast and
///        ReleaseSmall (best throughput).
/// true / false - force tracking on or off regardless of build mode.
pub const position_tracking: ?bool = true;

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

/// After each dedent, emit a control byte that `new_line` matches and
/// every other expected terminal skips.
///
/// true  - a dedent yields `block_end` then that byte, so
///         `new_line`-separated rows continue after a block while
///         closers such as `}` do not see a leftover newline.
/// false - a dedent yields only `block_end` tokens (the default).
///
/// Requires indentation_syntax to be enabled.
pub const newline_after_block_end = false;

/// Skip a decision an LL parser has already made.
///
/// true  - where a rule starts with a variable that has one
///         non-nullable rule, the decision that selected the rule
///         selects the variable's rule too, and the variable's parser
///         skips its own decision.
/// false - every variable parser makes its own decision.
///
/// LR parsers ignore this option.
pub const fold_decisions = true;

/// How much code forcing an LL variable parser inline into its callers
/// may add, in the generator's units of about one decision prong or rule
/// symbol.
///
/// 0        - every variable parser stays a function.
/// a number - a parser is forced inline when its copies beyond the first,
///            one per caller, add less code than this. A parser with
///            one caller adds none.
/// null     - every parser is forced inline.
///
/// Inlined parsers make fewer calls, but many copies of a large parser
/// can slow a parser down. On a recursion cycle, the few rules chosen to
/// break it keep their own functions, so one nesting level costs one
/// frame. Debug builds keep every parser a function, since unoptimized
/// inlined parsers cost far more stack. LR parsers ignore this option.
pub const inlining_cap: ?usize = 0;

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
pub const error_messages = .{ .@"*" = "parse failed at {line}:{column} near {unexpected}" };
