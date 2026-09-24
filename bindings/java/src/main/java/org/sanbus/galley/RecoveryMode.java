package org.sanbus.galley;

/**
 * Error-recovery modes reported by {@code galley_error_recovery_mode},
 * per the {@code galley_recovery_mode_*} constants in the C ABI. Converted
 * once at the FFI boundary via {@link #fromCode}; branching code uses
 * these names, never integers.
 */
public enum RecoveryMode {
    DISABLED(0),
    AUTOMATIC(1),
    EXPLICIT(2),
    /** Fallback for codes this binding does not know (newer native builds). */
    UNKNOWN(-1);

    private final int code;

    RecoveryMode(int code) { this.code = code; }

    /** Raw {@code galley_error_recovery_mode} value. */
    public int getCode() { return code; }

    /**
     * Single converter for this category: known codes map to their member,
     * anything else maps to {@link #UNKNOWN}.
     */
    public static RecoveryMode fromCode(long code) {
        for (RecoveryMode value : values()) {
            if (value.code == code) return value;
        }
        return UNKNOWN;
    }
}
