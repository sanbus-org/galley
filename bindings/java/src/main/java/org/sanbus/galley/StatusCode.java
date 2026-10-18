package org.sanbus.galley;

/**
 * Status codes returned by parse and accessor functions, per the
 * {@code galley_ok} / {@code galley_error_*} constants in the C ABI.
 * Non-negative values are success; negative values are failures. Converted
 * once at the FFI boundary via {@link #fromCode}; branching code uses
 * these names, never integers.
 */
public enum StatusCode {
    OK(0, false),
    ERROR_NULL_ARGUMENT(-1, false),
    ERROR_SYNTAX(-2, true),
    ERROR_INDENTATION(-3, true),
    ERROR_STACK_OVERFLOW(-4, true),
    ERROR_AST_CAPACITY_EXCEEDED(-5, true),
    ERROR_UNTERMINATED_RAW_STRING(-6, true),
    ERROR_OUT_OF_MEMORY(-7, true),
    ERROR_INTERNAL(-8, false),
    ERROR_NO_DIAGNOSTIC(-9, false),
    ERROR_INVALID_NODE(-10, false),
    ERROR_IO(-11, false),
    ERROR_SEMANTIC(-12, true),
    /** A parse holds the session; a post-parse accessor was called mid-parse. */
    ERROR_SESSION_IN_USE(-13, false),
    /** The walker's generation is not the tree's anymore: its session parsed again. */
    ERROR_STALE_TREE(-14, false),
    /** A hook's arguments were used after its hook returned. */
    ERROR_STALE_HOOK(-15, false),
    /** A hook raised: the parse stopped there and published nothing; the failure's cause is the hook's exception. */
    ERROR_HOOK_FAILED(-16, true),
    /** An index outside the table it was read from: a hook name, or a grammar symbol or variable name. */
    ERROR_OUT_OF_RANGE(-17, false),
    /** A session option value outside its domain, or a hook-flag count that does not match the hook count. */
    ERROR_INVALID_ARGUMENT(-18, false),
    /** Fallback for codes this binding does not know (newer native builds). */
    UNKNOWN(Integer.MIN_VALUE, false);

    private final int code;
    private final boolean carriesDiagnostic;

    StatusCode(int code, boolean carriesDiagnostic) {
        this.code = code;
        this.carriesDiagnostic = carriesDiagnostic;
    }

    /**
     * Raw {@code galley_status} value. {@link #UNKNOWN} carries
     * {@link Integer#MIN_VALUE} since every nearby value is taken.
     */
    public int getCode() { return code; }

    /**
     * Whether a failure with this status carries the session's diagnostic:
     * exactly syntax, semantic, indentation, stack overflow, AST capacity,
     * unterminated raw string, out of memory, and hook failure. Those are
     * the statuses that end a parse that ran, and the session's diagnostic
     * then belongs to that attempt. A failure built from any other status
     * carries none.
     */
    public boolean carriesDiagnostic() { return carriesDiagnostic; }

    /**
     * Single converter for this category: known codes map to their member,
     * anything else maps to {@link #UNKNOWN}.
     */
    public static StatusCode fromCode(long code) {
        for (StatusCode value : values()) {
            if (value != UNKNOWN && value.code == code) return value;
        }
        return UNKNOWN;
    }
}
