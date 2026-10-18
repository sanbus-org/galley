package org.sanbus.galley;

// >>> generated file (bindings/abi_values.zon; regenerate: zig build abi-values)

/**
 * Status codes returned by parse and accessor functions. Non-negative values
 * are success; negative values are failures, and {@code galley_status_string}
 * renders each one's text for diagnostics.
 */
public enum Status {
    /**
     * Success: the call ran to its end (a parse answers the number of bytes
     * parsed).
     */
    OK(0, false),
    /**
     * A required argument is null: a session, a hook door, or a required
     * pointer.
     */
    ERROR_NULL_ARGUMENT(-1, false),
    /**
     * The parse recorded syntax errors. A parse that recovered and ran to its
     * end still publishes its tree, with the damaged regions flagged as
     * recovered nodes; a parse that could not recover publishes nothing.
     */
    ERROR_SYNTAX(-2, true),
    /**
     * The parse failed on indentation, which has no recovery; nothing is
     * published.
     */
    ERROR_INDENTATION(-3, true),
    /**
     * The parser stack exceeded its configured limit; nothing is published.
     */
    ERROR_STACK_OVERFLOW(-4, true),
    /**
     * AST storage ran out of its planned capacity; nothing is published.
     */
    ERROR_AST_CAPACITY_EXCEEDED(-5, true),
    /**
     * Input ended inside a raw string; nothing is published.
     */
    ERROR_UNTERMINATED_RAW_STRING(-6, true),
    /**
     * An allocation failed; nothing is published.
     */
    ERROR_OUT_OF_MEMORY(-7, true),
    /**
     * An internal invariant failed: a bug in the library, not a property of
     * the input.
     */
    ERROR_INTERNAL(-8, false),
    /**
     * The read needs a diagnostic and none matches: no diagnostic is
     * recorded, it is not of the requested kind, or a recorded-diagnostic
     * index is past its table.
     */
    ERROR_NO_DIAGNOSTIC(-9, false),
    /**
     * A tree position names no node of the tree the call addresses; an index
     * past any other table is {@code galley_error_out_of_range} instead.
     */
    ERROR_INVALID_NODE(-10, false),
    /**
     * Reading the input failed; nothing is published.
     */
    ERROR_IO(-11, false),
    /**
     * The parse recorded semantic errors; the tree is still published, with
     * the erroring nodes marked.
     */
    ERROR_SEMANTIC(-12, true),
    /**
     * A parse holds the session exclusively; the call is refused rather than
     * queued. Post-parse node/tree/diagnostic accessors return this while a
     * parse is in flight (hook code must use the {@code galley_hook_*} door).
     */
    ERROR_SESSION_IN_USE(-13, false),
    /**
     * A node, tree edit, snapshot, or walk cursor carries a generation that
     * is not the door's live tree's. On the session door: the session parsed
     * again, the last parse failed and published nothing, or nothing was ever
     * published; re-read the tree with {@code galley_root_node} and use its
     * nodes. {@code galley_last_input} and {@code galley_last_position}
     * follow the published tree the same way. On the hook door
     * ({@code galley_hook_*}, {@code galley_procedure_set_current_node}): the
     * generation is not the running parse's ({@code galley_hook_generation}).
     * Calls on both doors pass the generation they address; the check runs in
     * every build, because it is a lifetime contract, not a misuse check.
     */
    ERROR_STALE_TREE(-14, false),
    /**
     * A {@code galley_procedure_*} call made with the ticket of a hook that
     * returned: the arguments are valid only while their hook runs.
     */
    ERROR_STALE_HOOK(-15, false),
    /**
     * A hook's dispatch returned nonzero: the parse stopped where the hook
     * ran and published nothing. The diagnostic is of kind
     * {@code galley_diagnostic_kind_hook}; the host keeps the cause of the
     * failure.
     */
    ERROR_HOOK_FAILED(-16, true),
    /**
     * An index outside the table it was read from: a hook name, a grammar
     * symbol or variable name, or an expected-token or context-name index
     * past its diagnostic's table. An address outside the live node storage
     * is {@code galley_error_invalid_node} instead.
     */
    ERROR_OUT_OF_RANGE(-17, false),
    /**
     * A value in {@code GalleyCOptions} is outside its domain (a negative
     * {@code max_errors}, {@code recovery_window}, or {@code verbosity}, or a
     * non-finite {@code ast_preallocation_ratio}), or the enable-flag count
     * passed to {@code galley_session_set_hooks} does not match
     * {@code galley_hooks_count()}.
     */
    ERROR_INVALID_ARGUMENT(-18, false),
    /**
     * Fallback for codes this binding does not know.
     */
    UNKNOWN(Integer.MIN_VALUE, false);

    private final int code;
    private final boolean carriesDiagnostic;

    Status(int code, boolean carriesDiagnostic) {
        this.code = code;
        this.carriesDiagnostic = carriesDiagnostic;
    }
    /**
     * Raw status code.
     */
    public int getCode() { return code; }

    /**
     * Whether a failure with this status carries the session's diagnostic of
     * the parse it ended: true for the statuses that end a parse that ran,
     * false for every other status.
     */
    public boolean carriesDiagnostic() { return carriesDiagnostic; }

    /**
     * Single converter for this category: known codes map to their member,
     * anything else maps to {@code UNKNOWN}.
     */
    public static Status fromCode(long code) {
        for (Status value : values()) {
            if (value != UNKNOWN && value.code == code) return value;
        }
        return UNKNOWN;
    }
}
