package org.sanbus.galley;

/**
 * Resume sides reported by {@code galley_diagnostic_recovery_resume},
 * per the {@code galley_resume_*} constants in the C ABI. Converted once
 * at the FFI boundary via {@link #fromCode}; branching code uses these
 * names, never integers.
 */
public enum ResumeSide {
    BEFORE(0),
    AFTER(1),
    /** Fallback for codes this binding does not know (newer native builds). */
    UNKNOWN(-1);

    private final int code;

    ResumeSide(int code) { this.code = code; }

    /** Raw {@code galley_diagnostic_recovery_resume} value. */
    public int getCode() { return code; }

    /**
     * Single converter for this category: known codes map to their member,
     * anything else maps to {@link #UNKNOWN}.
     */
    public static ResumeSide fromCode(long code) {
        for (ResumeSide value : values()) {
            if (value.code == code) return value;
        }
        return UNKNOWN;
    }
}
