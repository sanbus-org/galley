// >>> generated file (bindings/abi_values.zon; regenerate: zig build abi-values)

/**
 * Returned by tree queries when no node exists at that position. Every node
 * address and this sentinel are non-negative (`INT64_MAX`), so a call that
 * returns an address can report a negative status in the same `long long`.
 */
export const INVALID_NODE = 0x7fffffffffffffffn;

/**
 * Returned by `galley_node_variable_index` and written to the snapshot's
 * variable column for a node that has no variable. Non-negative like
 * `GALLEY_INVALID_NODE`: only statuses are negative.
 */
export const NO_VARIABLE = 0x7fffffffffffffffn;

/**
 * Parser families returned by `galley_parser_type`.
 */
export enum ParserType {
  /**
   * Predictive LL parser: recursive descent over the native call stack.
   */
  Ll = 0,
  /**
   * Canonical LR parser: recursive ascent over the native call stack.
   */
  Lr = 1,
}

/**
 * Error-recovery modes returned by `galley_error_recovery_mode`.
 */
export enum RecoveryMode {
  /**
   * Recovery is disabled: the parser is fail-fast, and grammar annotations
   * are inert.
   */
  Disabled = 0,
  /**
   * Recovery is enabled for an unannotated grammar: the parser synchronizes
   * on its own.
   */
  Automatic = 1,
  /**
   * Recovery is enabled for an annotated grammar: only committed annotated
   * scopes recover, with no automatic fallback.
   */
  Explicit = 2,
}

/**
 * Diagnostic kinds returned by `galley_diagnostic_kind`.
 */
export enum DiagnosticKind {
  /**
   * No diagnostic: the previous parse succeeded, or no parse has run.
   */
  None = 0,
  /**
   * A syntax error. A parse that recovered from its syntax errors still
   * publishes its tree, with the damaged regions flagged as recovered nodes.
   */
  Syntax = 1,
  /**
   * An indentation error, reported where the input's indentation does not fit
   * the grammar.
   */
  Indentation = 2,
  /**
   * A semantic error recorded by a reduction or a hook; the parse continues
   * and the node is marked.
   */
  Semantic = 3,
  /**
   * A hook raised or its dispatch returned failure: the parse stopped at that
   * hook and published nothing.
   */
  Hook = 4,
}

/**
 * Recovery target kinds returned by `galley_diagnostic_recovery_kind`.
 */
export enum RecoveryTarget {
  /**
   * No recovery information: the diagnostic did not come from a recovery, or
   * recovery could not attribute a target.
   */
  None = 0,
  /**
   * The recovery synchronized at a left-hand-side variable.
   */
  LhsVariable = 1,
  /**
   * The recovery synchronized at a committed production.
   */
  Production = 2,
  /**
   * The recovery synchronized at an annotated right-hand-side occurrence.
   */
  Occurrence = 3,
}

/**
 * Resume sides returned by `galley_diagnostic_recovery_resume`.
 */
export enum ResumeSide {
  /**
   * The recovery terminal is preserved for the parser to match.
   */
  Before = 0,
  /**
   * The recovery terminal is consumed by the recovery.
   */
  After = 1,
}

/**
 * Status codes returned by parse and accessor functions. Non-negative values
 * are success; negative values are failures, and `galley_status_string`
 * renders each one's text for diagnostics.
 */
export enum Status {
  /**
   * Success: the call ran to its end (a parse answers the number of bytes
   * parsed).
   */
  Ok = 0,
  /**
   * A required argument is null: a session, a hook door, or a required
   * pointer.
   */
  ErrorNullArgument = -1,
  /**
   * The parse recorded syntax errors. A parse that recovered and ran to its
   * end still publishes its tree, with the damaged regions flagged as
   * recovered nodes; a parse that could not recover publishes nothing.
   */
  ErrorSyntax = -2,
  /**
   * The parse failed on indentation, which has no recovery; nothing is
   * published.
   */
  ErrorIndentation = -3,
  /**
   * The parser stack exceeded its configured limit; nothing is published.
   */
  ErrorStackOverflow = -4,
  /**
   * AST storage ran out of its planned capacity; nothing is published.
   */
  ErrorAstCapacityExceeded = -5,
  /**
   * Input ended inside a raw string; nothing is published.
   */
  ErrorUnterminatedRawString = -6,
  /**
   * An allocation failed; nothing is published.
   */
  ErrorOutOfMemory = -7,
  /**
   * An internal invariant failed: a bug in the library, not a property of the
   * input.
   */
  ErrorInternal = -8,
  /**
   * The read needs a diagnostic and none matches: no diagnostic is recorded,
   * it is not of the requested kind, or a recorded-diagnostic index is past
   * its table.
   */
  ErrorNoDiagnostic = -9,
  /**
   * A tree position names no node of the tree the call addresses; an index
   * past any other table is `galley_error_out_of_range` instead.
   */
  ErrorInvalidNode = -10,
  /**
   * Reading the input failed; nothing is published.
   */
  ErrorIo = -11,
  /**
   * The parse recorded semantic errors; the tree is still published, with the
   * erroring nodes marked.
   */
  ErrorSemantic = -12,
  /**
   * A parse holds the session exclusively; the call is refused rather than
   * queued. Post-parse node/tree/diagnostic accessors return this while a
   * parse is in flight (hook code must use the `galley_hook_*` door).
   */
  ErrorSessionInUse = -13,
  /**
   * A node, tree edit, snapshot, or walk cursor carries a generation that is
   * not the door's live tree's. On the session door: the session parsed
   * again, the last parse failed and published nothing, or nothing was ever
   * published; re-read the tree with `galley_root_node` and use its nodes.
   * `galley_last_input` and `galley_last_position` follow the published tree
   * the same way. On the hook door (`galley_hook_*`,
   * `galley_procedure_set_current_node`): the generation is not the running
   * parse's (`galley_hook_generation`). Calls on both doors pass the
   * generation they address; the check runs in every build, because it is a
   * lifetime contract, not a misuse check.
   */
  ErrorStaleTree = -14,
  /**
   * A `galley_procedure_*` call made with the ticket of a hook that returned:
   * the arguments are valid only while their hook runs.
   */
  ErrorStaleHook = -15,
  /**
   * A hook's dispatch returned nonzero: the parse stopped where the hook ran
   * and published nothing. The diagnostic is of kind
   * `galley_diagnostic_kind_hook`; the host keeps the cause of the failure.
   */
  ErrorHookFailed = -16,
  /**
   * An index outside the table it was read from: a hook name, a grammar
   * symbol or variable name, or an expected-token or context-name index past
   * its diagnostic's table. An address outside the live node storage is
   * `galley_error_invalid_node` instead.
   */
  ErrorOutOfRange = -17,
  /**
   * A value in `GalleyCOptions` is outside its domain (a negative
   * `max_errors`, `recovery_window`, or `verbosity`, or a non-finite
   * `ast_preallocation_ratio`), or the enable-flag count passed to
   * `galley_session_set_hooks` does not match `galley_hooks_count()`.
   */
  ErrorInvalidArgument = -18,
}

/**
 * The statuses that end a parse that ran: a failure with one of them carries
 * the session's diagnostic of that attempt. Every other status carries none.
 */
const CARRIES_DIAGNOSTIC: ReadonlySet<number> = new Set([
  Status.ErrorSyntax,
  Status.ErrorIndentation,
  Status.ErrorStackOverflow,
  Status.ErrorAstCapacityExceeded,
  Status.ErrorUnterminatedRawString,
  Status.ErrorOutOfMemory,
  Status.ErrorSemantic,
  Status.ErrorHookFailed,
]);

/**
 * True when a failure with `status` carries the session's diagnostic: exactly
 * the statuses that ended a parse that ran, whose diagnostic then belongs to
 * that attempt. Every other status carries none.
 */
export function statusCarriesDiagnostic(status: number): boolean {
  return CARRIES_DIAGNOSTIC.has(status);
}
