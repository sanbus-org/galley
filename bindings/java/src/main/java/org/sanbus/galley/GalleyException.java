package org.sanbus.galley;

/**
 * Failure reported by a Galley operation: a status code plus a frozen
 * diagnostic snapshot.
 *
 * The message text is fixed when the failure is created and the
 * diagnostic is deep-copied eagerly, so later parses cannot mutate what
 * this exception carries.
 */
public class GalleyException extends RuntimeException {
    private final Status code;
    private final Diagnostic diagnostic;

    public GalleyException(String message, Status code, Diagnostic diagnostic) {
        super(message);
        this.code = code != null ? code : Status.UNKNOWN;
        this.diagnostic = diagnostic;
    }

    public GalleyException(String message, int code, Diagnostic diagnostic) {
        this(message, Status.fromCode(code), diagnostic);
    }

    public GalleyException(String message, Status code) {
        this(message, code, null);
    }

    public GalleyException(String message, int code) {
        this(message, code, null);
    }

    /** Raw {@code galley_status} value classified at the FFI boundary. */
    public Status getCode() { return code; }

    /** Snapshot of the session diagnostic at failure, or null. */
    public Diagnostic getDiagnostic() { return diagnostic; }
}
