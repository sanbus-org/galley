package org.sanbus.galley;

// >>> generated file (bindings/abi_values.zon; regenerate: zig build abi-values)

/**
 * Diagnostic kinds returned by {@code galley_diagnostic_kind}.
 */
public enum DiagnosticKind {
    /**
     * No diagnostic: the previous parse succeeded, or no parse has run.
     */
    NONE(0),
    /**
     * A syntax error. A parse that recovered from its syntax errors still
     * publishes its tree, with the damaged regions flagged as recovered
     * nodes.
     */
    SYNTAX(1),
    /**
     * An indentation error, reported where the input's indentation does not
     * fit the grammar.
     */
    INDENTATION(2),
    /**
     * A semantic error recorded by a reduction or a hook; the parse continues
     * and the node is marked.
     */
    SEMANTIC(3),
    /**
     * A hook raised or its dispatch returned failure: the parse stopped at
     * that hook and published nothing.
     */
    HOOK(4),
    /**
     * Fallback for codes this binding does not know.
     */
    UNKNOWN(-1);

    private final int code;
    DiagnosticKind(int code) { this.code = code; }

    /**
     * Raw code value.
     */
    public int getCode() { return code; }

    /**
     * Single converter for this category: known codes map to their member,
     * anything else maps to {@code UNKNOWN}.
     */
    public static DiagnosticKind fromCode(long code) {
        for (DiagnosticKind value : values()) {
            if (value.code == code) return value;
        }
        return UNKNOWN;
    }
}
