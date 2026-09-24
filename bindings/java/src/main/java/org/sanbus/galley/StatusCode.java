package org.sanbus.galley;

/**
 * Status codes returned by parse and accessor functions, per the
 * {@code galley_ok} / {@code galley_error_*} constants in the C ABI.
 * Non-negative values are success; negative values are failures. Converted
 * once at the FFI boundary via {@link #fromCode}; branching code uses
 * these names, never integers.
 */
public enum StatusCode {
    OK(0),
    ERROR_NULL_ARGUMENT(-1),
    ERROR_SYNTAX(-2),
    ERROR_INDENTATION(-3),
    ERROR_STACK_OVERFLOW(-4),
    ERROR_AST_CAPACITY_EXCEEDED(-5),
    ERROR_UNTERMINATED_RAW_STRING(-6),
    ERROR_OUT_OF_MEMORY(-7),
    ERROR_INTERNAL(-8),
    ERROR_NO_DIAGNOSTIC(-9),
    ERROR_INVALID_NODE(-10),
    ERROR_IO(-11),
    ERROR_SEMANTIC(-12),
    /** Fallback for codes this binding does not know (newer native builds). */
    UNKNOWN(Integer.MIN_VALUE);

    private final int code;

    StatusCode(int code) { this.code = code; }

    /**
     * Raw {@code galley_status} value. {@link #UNKNOWN} carries
     * {@link Integer#MIN_VALUE} since every nearby value is taken.
     */
    public int getCode() { return code; }

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
