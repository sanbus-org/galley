package org.sanbus.galley;

// >>> generated file (bindings/abi_values.zon; regenerate: zig build abi-values)

/**
 * Resume sides returned by {@code galley_diagnostic_recovery_resume}.
 */
public enum ResumeSide {
    /**
     * The recovery terminal is preserved for the parser to match.
     */
    BEFORE(0),
    /**
     * The recovery terminal is consumed by the recovery.
     */
    AFTER(1),
    /**
     * Fallback for codes this binding does not know.
     */
    UNKNOWN(-1);

    private final int code;
    ResumeSide(int code) { this.code = code; }

    /**
     * Raw code value.
     */
    public int getCode() { return code; }

    /**
     * Single converter for this category: known codes map to their member,
     * anything else maps to {@code UNKNOWN}.
     */
    public static ResumeSide fromCode(long code) {
        for (ResumeSide value : values()) {
            if (value.code == code) return value;
        }
        return UNKNOWN;
    }
}
