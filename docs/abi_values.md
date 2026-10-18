# ABI Values

<!-- >>> generated file (bindings/abi_values.zon; regenerate: zig build abi-values) -->

Every named value shared by the C ABI and the language bindings is
declared once in
[`bindings/abi_values.zon`](https://github.com/sanbus-org/galley/blob/main/bindings/abi_values.zon)
and rendered into each binding's idiom by
[`src/tools/abi_values_gen.zig`](https://github.com/sanbus-org/galley/blob/main/src/tools/abi_values_gen.zig).
The copies are checked in; `zig build abi-values` regenerates them, and
the `build` test suite fails when one drifts.

## Statuses

Status codes returned by parse and accessor functions. Non-negative values are success; negative values are failures, and `galley_status_string` renders each one's text for diagnostics.

| Name | Value | Text | Python | JavaScript | Java | Rust | Go |
| --- | ---: | --- | --- | --- | --- | --- | --- |
| `galley_ok` | 0 | `ok` | `Status.OK` | `Status.Ok` | `Status.OK` | — | — |
| `galley_error_null_argument` | -1 | `null argument` | `Status.ERROR_NULL_ARGUMENT` | `Status.ErrorNullArgument` | `Status.ERROR_NULL_ARGUMENT` | `Error::NullArgument` | `ErrNullArgument` |
| `galley_error_syntax` | -2 | `syntax error` | `Status.ERROR_SYNTAX` | `Status.ErrorSyntax` | `Status.ERROR_SYNTAX` | `Error::Syntax` | `ErrSyntax` |
| `galley_error_indentation` | -3 | `indentation error` | `Status.ERROR_INDENTATION` | `Status.ErrorIndentation` | `Status.ERROR_INDENTATION` | `Error::Indentation` | `ErrIndentation` |
| `galley_error_stack_overflow` | -4 | `parser stack overflow` | `Status.ERROR_STACK_OVERFLOW` | `Status.ErrorStackOverflow` | `Status.ERROR_STACK_OVERFLOW` | `Error::StackOverflow` | `ErrStackOverflow` |
| `galley_error_ast_capacity_exceeded` | -5 | `AST capacity exceeded` | `Status.ERROR_AST_CAPACITY_EXCEEDED` | `Status.ErrorAstCapacityExceeded` | `Status.ERROR_AST_CAPACITY_EXCEEDED` | `Error::AstCapacityExceeded` | `ErrASTCapacityExceeded` |
| `galley_error_unterminated_raw_string` | -6 | `unterminated raw string` | `Status.ERROR_UNTERMINATED_RAW_STRING` | `Status.ErrorUnterminatedRawString` | `Status.ERROR_UNTERMINATED_RAW_STRING` | `Error::UnterminatedRawString` | `ErrUnterminatedRawString` |
| `galley_error_out_of_memory` | -7 | `out of memory` | `Status.ERROR_OUT_OF_MEMORY` | `Status.ErrorOutOfMemory` | `Status.ERROR_OUT_OF_MEMORY` | `Error::OutOfMemory` | `ErrOutOfMemory` |
| `galley_error_internal` | -8 | `internal error` | `Status.ERROR_INTERNAL` | `Status.ErrorInternal` | `Status.ERROR_INTERNAL` | `Error::Internal` | `ErrInternal` |
| `galley_error_no_diagnostic` | -9 | `no diagnostic available` | `Status.ERROR_NO_DIAGNOSTIC` | `Status.ErrorNoDiagnostic` | `Status.ERROR_NO_DIAGNOSTIC` | `Error::NoDiagnostic` | `ErrNoDiagnostic` |
| `galley_error_invalid_node` | -10 | `invalid node address` | `Status.ERROR_INVALID_NODE` | `Status.ErrorInvalidNode` | `Status.ERROR_INVALID_NODE` | `Error::InvalidNode` | `ErrInvalidNode` |
| `galley_error_io` | -11 | `I/O error` | `Status.ERROR_IO` | `Status.ErrorIo` | `Status.ERROR_IO` | `Error::Io` | `ErrIO` |
| `galley_error_semantic` | -12 | `semantic error` | `Status.ERROR_SEMANTIC` | `Status.ErrorSemantic` | `Status.ERROR_SEMANTIC` | `Error::Semantic` | `ErrSemantic` |
| `galley_error_session_in_use` | -13 | `session in use` | `Status.ERROR_SESSION_IN_USE` | `Status.ErrorSessionInUse` | `Status.ERROR_SESSION_IN_USE` | `Error::SessionInUse` | `ErrSessionInUse` |
| `galley_error_stale_tree` | -14 | `stale tree` | `Status.ERROR_STALE_TREE` | `Status.ErrorStaleTree` | `Status.ERROR_STALE_TREE` | `Error::StaleTree` | `ErrStaleTree` |
| `galley_error_stale_hook` | -15 | `stale hook` | `Status.ERROR_STALE_HOOK` | `Status.ErrorStaleHook` | `Status.ERROR_STALE_HOOK` | `Error::StaleHook` | `ErrStaleHook` |
| `galley_error_hook_failed` | -16 | `hook failed` | `Status.ERROR_HOOK_FAILED` | `Status.ErrorHookFailed` | `Status.ERROR_HOOK_FAILED` | `Error::HookFailed` | `ErrHookFailed` |
| `galley_error_out_of_range` | -17 | `out of range` | `Status.ERROR_OUT_OF_RANGE` | `Status.ErrorOutOfRange` | `Status.ERROR_OUT_OF_RANGE` | `Error::OutOfRange` | `ErrOutOfRange` |
| `galley_error_invalid_argument` | -18 | `invalid argument` | `Status.ERROR_INVALID_ARGUMENT` | `Status.ErrorInvalidArgument` | `Status.ERROR_INVALID_ARGUMENT` | `Error::InvalidArgument` | `ErrInvalidArgument` |

- **`galley_ok`** — Success: the call ran to its end (a parse answers the number of bytes parsed).
- **`galley_error_null_argument`** — A required argument is null: a session, a hook door, or a required pointer.
- **`galley_error_syntax`** — The parse recorded syntax errors. A parse that recovered and ran to its end still publishes its tree, with the damaged regions flagged as recovered nodes; a parse that could not recover publishes nothing.
- **`galley_error_indentation`** — The parse failed on indentation, which has no recovery; nothing is published.
- **`galley_error_stack_overflow`** — The parser stack exceeded its configured limit; nothing is published.
- **`galley_error_ast_capacity_exceeded`** — AST storage ran out of its planned capacity; nothing is published.
- **`galley_error_unterminated_raw_string`** — Input ended inside a raw string; nothing is published.
- **`galley_error_out_of_memory`** — An allocation failed; nothing is published.
- **`galley_error_internal`** — An internal invariant failed: a bug in the library, not a property of the input.
- **`galley_error_no_diagnostic`** — The read needs a diagnostic and none matches: no diagnostic is recorded, it is not of the requested kind, or a recorded-diagnostic index is past its table.
- **`galley_error_invalid_node`** — A tree position names no node of the tree the call addresses; an index past any other table is `galley_error_out_of_range` instead.
- **`galley_error_io`** — Reading the input failed; nothing is published.
- **`galley_error_semantic`** — The parse recorded semantic errors; the tree is still published, with the erroring nodes marked.
- **`galley_error_session_in_use`** — A parse holds the session exclusively; the call is refused rather than queued. Post-parse node/tree/diagnostic accessors return this while a parse is in flight (hook code must use the `galley_hook_*` door).
- **`galley_error_stale_tree`** — A node, tree edit, snapshot, or walk cursor carries a generation that is not the door's live tree's. On the session door: the session parsed again, the last parse failed and published nothing, or nothing was ever published; re-read the tree with `galley_root_node` and use its nodes. `galley_last_input` and `galley_last_position` follow the published tree the same way. On the hook door (`galley_hook_*`, `galley_procedure_set_current_node`): the generation is not the running parse's (`galley_hook_generation`). Calls on both doors pass the generation they address; the check runs in every build, because it is a lifetime contract, not a misuse check.
- **`galley_error_stale_hook`** — A `galley_procedure_*` call made with the ticket of a hook that returned: the arguments are valid only while their hook runs.
- **`galley_error_hook_failed`** — A hook's dispatch returned nonzero: the parse stopped where the hook ran and published nothing. The diagnostic is of kind `galley_diagnostic_kind_hook`; the host keeps the cause of the failure.
- **`galley_error_out_of_range`** — An index outside the table it was read from: a hook name, a grammar symbol or variable name, or an expected-token or context-name index past its diagnostic's table. An address outside the live node storage is `galley_error_invalid_node` instead.
- **`galley_error_invalid_argument`** — A value in `GalleyCOptions` is outside its domain (a negative `max_errors`, `recovery_window`, or `verbosity`, or a non-finite `ast_preallocation_ratio`), or the enable-flag count passed to `galley_session_set_hooks` does not match `galley_hooks_count()`.

## Diagnostic kinds

Diagnostic kinds returned by `galley_diagnostic_kind`.

| Name | Value | Python | JavaScript | Java | Rust | Go |
| --- | ---: | --- | --- | --- | --- | --- |
| `galley_diagnostic_kind_none` | 0 | `DiagnosticKind.NONE` | `DiagnosticKind.None` | `DiagnosticKind.NONE` | `DiagnosticKind::None` | `DiagnosticKindNone` |
| `galley_diagnostic_kind_syntax` | 1 | `DiagnosticKind.SYNTAX` | `DiagnosticKind.Syntax` | `DiagnosticKind.SYNTAX` | `DiagnosticKind::Syntax` | `DiagnosticKindSyntax` |
| `galley_diagnostic_kind_indentation` | 2 | `DiagnosticKind.INDENTATION` | `DiagnosticKind.Indentation` | `DiagnosticKind.INDENTATION` | `DiagnosticKind::Indentation` | `DiagnosticKindIndentation` |
| `galley_diagnostic_kind_semantic` | 3 | `DiagnosticKind.SEMANTIC` | `DiagnosticKind.Semantic` | `DiagnosticKind.SEMANTIC` | `DiagnosticKind::Semantic` | `DiagnosticKindSemantic` |
| `galley_diagnostic_kind_hook` | 4 | `DiagnosticKind.HOOK` | `DiagnosticKind.Hook` | `DiagnosticKind.HOOK` | `DiagnosticKind::Hook` | `DiagnosticKindHook` |

- **`galley_diagnostic_kind_none`** — No diagnostic: the most recent parse call recorded none (it succeeded, or failed before its parse ran), or no parse has run.
- **`galley_diagnostic_kind_syntax`** — A syntax error. A parse that recovered from its syntax errors still publishes its tree, with the damaged regions flagged as recovered nodes.
- **`galley_diagnostic_kind_indentation`** — An indentation error, reported where the input's indentation does not fit the grammar.
- **`galley_diagnostic_kind_semantic`** — A semantic error recorded by a reduction or a hook; the parse continues and the node is marked.
- **`galley_diagnostic_kind_hook`** — A hook raised or its dispatch returned failure: the parse stopped at that hook and published nothing.

## Recovery targets

Recovery target kinds returned by `galley_diagnostic_recovery_kind`.

| Name | Value | Python | JavaScript | Java | Rust | Go |
| --- | ---: | --- | --- | --- | --- | --- |
| `galley_recovery_target_none` | 0 | `RecoveryTarget.NONE` | `RecoveryTarget.None` | `RecoveryTarget.NONE` | — | `RecoveryTargetNone` |
| `galley_recovery_target_lhs_variable` | 1 | `RecoveryTarget.LHS_VARIABLE` | `RecoveryTarget.LhsVariable` | `RecoveryTarget.LHS_VARIABLE` | — | `RecoveryTargetLHSVariable` |
| `galley_recovery_target_production` | 2 | `RecoveryTarget.PRODUCTION` | `RecoveryTarget.Production` | `RecoveryTarget.PRODUCTION` | — | `RecoveryTargetProduction` |
| `galley_recovery_target_occurrence` | 3 | `RecoveryTarget.OCCURRENCE` | `RecoveryTarget.Occurrence` | `RecoveryTarget.OCCURRENCE` | — | `RecoveryTargetOccurrence` |

- **`galley_recovery_target_none`** — No recovery information: the diagnostic did not come from a recovery, or recovery could not attribute a target.
- **`galley_recovery_target_lhs_variable`** — The recovery synchronized at a left-hand-side variable.
- **`galley_recovery_target_production`** — The recovery synchronized at a committed production.
- **`galley_recovery_target_occurrence`** — The recovery synchronized at an annotated right-hand-side occurrence.

## Resume sides

Resume sides returned by `galley_diagnostic_recovery_resume`.

| Name | Value | Python | JavaScript | Java | Rust | Go |
| --- | ---: | --- | --- | --- | --- | --- |
| `galley_resume_before` | 0 | `ResumeSide.BEFORE` | `ResumeSide.Before` | `ResumeSide.BEFORE` | — | — |
| `galley_resume_after` | 1 | `ResumeSide.AFTER` | `ResumeSide.After` | `ResumeSide.AFTER` | — | — |

- **`galley_resume_before`** — The recovery terminal is preserved for the parser to match.
- **`galley_resume_after`** — The recovery terminal is consumed by the recovery.

## Parser types

Parser families returned by `galley_parser_type`.

| Name | Value | Python | JavaScript | Java | Rust | Go |
| --- | ---: | --- | --- | --- | --- | --- |
| `galley_parser_type_ll` | 0 | `ParserType.LL` | `ParserType.Ll` | `ParserType.LL` | — | — |
| `galley_parser_type_lr` | 1 | `ParserType.LR` | `ParserType.Lr` | `ParserType.LR` | — | — |

- **`galley_parser_type_ll`** — Predictive LL parser: recursive descent over the native call stack.
- **`galley_parser_type_lr`** — Canonical LR parser: recursive ascent over the native call stack.

## Recovery modes

Error-recovery modes returned by `galley_error_recovery_mode`.

| Name | Value | Python | JavaScript | Java | Rust | Go |
| --- | ---: | --- | --- | --- | --- | --- |
| `galley_recovery_mode_disabled` | 0 | `RecoveryMode.DISABLED` | `RecoveryMode.Disabled` | `RecoveryMode.DISABLED` | — | — |
| `galley_recovery_mode_automatic` | 1 | `RecoveryMode.AUTOMATIC` | `RecoveryMode.Automatic` | `RecoveryMode.AUTOMATIC` | — | — |
| `galley_recovery_mode_explicit` | 2 | `RecoveryMode.EXPLICIT` | `RecoveryMode.Explicit` | `RecoveryMode.EXPLICIT` | — | — |

- **`galley_recovery_mode_disabled`** — Recovery is disabled: the parser is fail-fast, and grammar annotations are inert.
- **`galley_recovery_mode_automatic`** — Recovery is enabled for an unannotated grammar: the parser synchronizes on its own.
- **`galley_recovery_mode_explicit`** — Recovery is enabled for an annotated grammar: only committed annotated scopes recover, with no automatic fallback.

## Sentinels

Both sentinels are `INT64_MAX`; only statuses are negative.

| Name | Value | Python | JavaScript | Java | Rust | Go |
| --- | ---: | --- | --- | --- | --- | --- |
| `GALLEY_INVALID_NODE` | 9223372036854775807 | `INVALID_NODE` | `INVALID_NODE` | `Galley.INVALID_NODE` | `INVALID_NODE` | `invalidNode` |
| `GALLEY_NO_VARIABLE` | 9223372036854775807 | — | `NO_VARIABLE` | `Galley.NO_VARIABLE` | `NO_VARIABLE` | `noVariable` |

- **`GALLEY_INVALID_NODE`** — Returned by tree queries when no node exists at that position. Every node address and this sentinel are non-negative (`INT64_MAX`), so a call that returns an address can report a negative status in the same `long long`.
- **`GALLEY_NO_VARIABLE`** — Returned by `galley_node_variable_index` and written to the snapshot's variable column for a node that has no variable. Non-negative like `GALLEY_INVALID_NODE`: only statuses are negative.
