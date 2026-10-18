package org.sanbus.galley;

// >>> generated file (bindings/abi_values.zon; regenerate: zig build abi-values)

/**
 * Recovery target kinds returned by {@code galley_diagnostic_recovery_kind}.
 */
public enum RecoveryTarget {
    /**
     * No recovery information: the diagnostic did not come from a recovery,
     * or recovery could not attribute a target.
     */
    NONE(0),
    /**
     * The recovery synchronized at a left-hand-side variable.
     */
    LHS_VARIABLE(1),
    /**
     * The recovery synchronized at a committed production.
     */
    PRODUCTION(2),
    /**
     * The recovery synchronized at an annotated right-hand-side occurrence.
     */
    OCCURRENCE(3),
    /**
     * Fallback for codes this binding does not know.
     */
    UNKNOWN(-1);

    private final int code;
    RecoveryTarget(int code) { this.code = code; }

    /**
     * Raw code value.
     */
    public int getCode() { return code; }

    /**
     * Single converter for this category: known codes map to their member,
     * anything else maps to {@code UNKNOWN}.
     */
    public static RecoveryTarget fromCode(long code) {
        for (RecoveryTarget value : values()) {
            if (value.code == code) return value;
        }
        return UNKNOWN;
    }
}
