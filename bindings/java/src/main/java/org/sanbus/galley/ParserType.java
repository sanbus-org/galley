package org.sanbus.galley;

// >>> generated file (bindings/abi_values.zon; regenerate: zig build abi-values)

/**
 * Parser families returned by {@code galley_parser_type}.
 */
public enum ParserType {
    /**
     * Predictive LL parser: recursive descent over the native call stack.
     */
    LL(0),
    /**
     * Canonical LR parser: recursive ascent over the native call stack.
     */
    LR(1),
    /**
     * Fallback for codes this binding does not know.
     */
    UNKNOWN(-1);

    private final int code;
    ParserType(int code) { this.code = code; }

    /**
     * Raw code value.
     */
    public int getCode() { return code; }

    /**
     * Single converter for this category: known codes map to their member,
     * anything else maps to {@code UNKNOWN}.
     */
    public static ParserType fromCode(long code) {
        for (ParserType value : values()) {
            if (value.code == code) return value;
        }
        return UNKNOWN;
    }
}
