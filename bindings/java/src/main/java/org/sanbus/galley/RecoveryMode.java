package org.sanbus.galley;

// >>> generated file (bindings/abi_values.zon; regenerate: zig build abi-values)

/**
 * Error-recovery modes returned by {@code galley_error_recovery_mode}.
 */
public enum RecoveryMode {
    /**
     * Recovery is disabled: the parser is fail-fast, and grammar annotations
     * are inert.
     */
    DISABLED(0),
    /**
     * Recovery is enabled for an unannotated grammar: the parser synchronizes
     * on its own.
     */
    AUTOMATIC(1),
    /**
     * Recovery is enabled for an annotated grammar: only committed annotated
     * scopes recover, with no automatic fallback.
     */
    EXPLICIT(2),
    /**
     * Fallback for codes this binding does not know.
     */
    UNKNOWN(-1);

    private final int code;
    RecoveryMode(int code) { this.code = code; }

    /**
     * Raw code value.
     */
    public int getCode() { return code; }

    /**
     * Single converter for this category: known codes map to their member,
     * anything else maps to {@code UNKNOWN}.
     */
    public static RecoveryMode fromCode(long code) {
        for (RecoveryMode value : values()) {
            if (value.code == code) return value;
        }
        return UNKNOWN;
    }
}
