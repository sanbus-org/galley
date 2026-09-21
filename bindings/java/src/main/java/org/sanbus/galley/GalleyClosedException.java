package org.sanbus.galley;

/**
 * Use after close: the named object is already closed. Thrown instead of a
 * generic {@link IllegalStateException} so catch sites can name the failure
 * instead of matching message text. Mirrors Python's closed-session
 * {@code ValueError} and the JS {@code SessionClosedError}. Closes stay
 * idempotent: closing twice never throws.
 */
public class GalleyClosedException extends IllegalStateException {
    private final String objectName;

    /**
     * @param objectName the closed object, e.g. {@code "session"},
     *                   {@code "walker"}, {@code "walker's session"}, or
     *                   {@code "node's session"}.
     */
    public GalleyClosedException(String objectName) {
        super(objectName + " is closed");
        this.objectName = objectName;
    }

    /** The closed object named by this failure. */
    public String getObjectName() { return objectName; }
}
