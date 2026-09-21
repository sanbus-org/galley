package org.sanbus.galley;

/**
 * Parser families reported by {@code galley_parser_type}, mirroring
 * Python's {@code ParserType} and the {@code galley_parser_type_*}
 * constants in the C ABI. Converted once at the FFI boundary via
 * {@link #fromCode}; branching code uses these names, never integers.
 */
public enum ParserType {
    LL(0),
    LR(1),
    /** Fallback for codes this binding does not know (newer native builds). */
    UNKNOWN(-1);

    private final int code;

    ParserType(int code) { this.code = code; }

    /** Raw {@code galley_parser_type} value. */
    public int getCode() { return code; }

    /**
     * Single converter for this category: known codes map to their member,
     * anything else maps to {@link #UNKNOWN}.
     */
    public static ParserType fromCode(long code) {
        for (ParserType value : values()) {
            if (value.code == code) return value;
        }
        return UNKNOWN;
    }
}
