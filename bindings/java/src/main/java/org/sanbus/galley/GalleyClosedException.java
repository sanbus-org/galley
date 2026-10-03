package org.sanbus.galley;

/**
 * Use after close: the named object is already closed. Thrown instead of a
 * generic {@link IllegalStateException} so catch sites can name the failure
 * instead of matching message text. Closes stay idempotent: closing twice
 * never throws. A handle whose tree is gone is a different failure and raises
 * {@link StaleTreeException}: the session is still open, its tree is not the
 * one the handle names.
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

    /** The closed object named by this failure. */
    public String getObjectName() { return objectName; }
}
