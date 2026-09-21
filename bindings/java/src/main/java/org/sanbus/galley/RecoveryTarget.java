package org.sanbus.galley;

/**
 * Recovery targets reported by {@code galley_diagnostic_recovery_kind},
 * mirroring Python's {@code RecoveryTarget} and the
 * {@code galley_recovery_target_*} constants in the C ABI. Converted once
 * at the FFI boundary via {@link #fromCode}; branching code uses these
 * names, never integers.
 */
public enum RecoveryTarget {
    NONE(0),
    LHS_VARIABLE(1),
    PRODUCTION(2),
    OCCURRENCE(3),
    /** Fallback for codes this binding does not know (newer native builds). */
    UNKNOWN(-1);

    private final int code;

    RecoveryTarget(int code) { this.code = code; }

    /** Raw {@code galley_diagnostic_recovery_kind} value. */
    public int getCode() { return code; }

    /**
     * Single converter for this category: known codes map to their member,
     * anything else maps to {@link #UNKNOWN}.
     */
    public static RecoveryTarget fromCode(long code) {
        for (RecoveryTarget value : values()) {
            if (value.code == code) return value;
        }
        return UNKNOWN;
    }
}
