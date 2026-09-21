package org.sanbus.galley;

/**
 * Diagnostic classifications reported by {@code galley_diagnostic_kind},
 * mirroring Python's {@code Kind} and the {@code galley_diagnostic_kind_*}
 * constants in the C ABI. Converted once at the FFI boundary via
 * {@link #fromCode}; branching code uses these names, never integers.
 */
public enum DiagnosticKind {
    NONE(0),
    SYNTAX(1),
    INDENTATION(2),
    SEMANTIC(3),
    /** Fallback for codes this binding does not know (newer native builds). */
    UNKNOWN(-1);

    private final int code;

    DiagnosticKind(int code) { this.code = code; }

    /** Raw {@code galley_diagnostic_kind} value. */
    public int getCode() { return code; }

    /**
     * Single converter for this category: known codes map to their member,
     * anything else maps to {@link #UNKNOWN}.
     */
    public static DiagnosticKind fromCode(long code) {
        for (DiagnosticKind value : values()) {
            if (value.code == code) return value;
        }
        return UNKNOWN;
    }
}
