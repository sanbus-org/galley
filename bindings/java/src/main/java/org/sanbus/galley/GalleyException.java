package org.sanbus.galley;

/**
 * Failure reported by a Galley operation. Mirrors Python's galley.Error and
 * the negative status codes in galley.h.
 */
public class GalleyException extends RuntimeException {
    private final int code;
    private final Diagnostic diagnostic;

    public GalleyException(String message, int code, Diagnostic diagnostic) {
        super(message);
        this.code = code;
        this.diagnostic = diagnostic;
    }

    public GalleyException(String message, int code) {
        this(message, code, null);
    }

    public int getCode() { return code; }

    public Diagnostic getDiagnostic() { return diagnostic; }
}
