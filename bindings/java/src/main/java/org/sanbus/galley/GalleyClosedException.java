package org.sanbus.galley;

/**
 * Use after close: the named object is already closed. Thrown instead of a
 * generic {@link IllegalStateException} so catch sites can name the failure
 * instead of matching message text. Closes stay idempotent: closing twice
 * never throws.
 */
public class GalleyClosedException extends IllegalStateException {
    private final String objectName;

    /**
     * @param objectName the closed object, e.g. {@code "session"},
     *                   {@code "walker"}, {@code "walker's session"}, or
     *                   {@code "node's session"}.
     */
    public GalleyClosedException(String objectName) {
        this(objectName, objectName + " is closed");
    }

    protected GalleyClosedException(String objectName, String message) {
        super(message);
        this.objectName = objectName;
    }

    /**
     * A handle bound to an older parse generation: unusable after its
     * session parsed again, never a stale read. Prefer
     * {@link GenerationInvalidatedException} at throw sites so callers can
     * discriminate by type.
     */
    public static GalleyClosedException invalidated(String objectName) {
        return new GenerationInvalidatedException(objectName);
    }

    /** The closed object named by this failure. */
    public String getObjectName() { return objectName; }
}
