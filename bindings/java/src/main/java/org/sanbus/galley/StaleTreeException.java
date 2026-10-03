package org.sanbus.galley;

/**
 * A handle left over from a tree that no longer exists: the session parsed
 * again since, the last parse published nothing, or nothing was ever
 * published. Never a stale read — the core refuses the generation the handle
 * carries, so nothing is read through it.
 *
 * <p>A {@link GalleyException} with code {@code ERROR_STALE_TREE}, distinct
 * from {@link GalleyClosedException}: use after close is that error, and this
 * one never stands in for it. One type for nodes and walkers, because
 * staleness is one concept.
 */
public class StaleTreeException extends GalleyException {
    public StaleTreeException(String objectName) {
        super(objectName + " is stale: the session parsed again since; read rootNode() for a current node",
                StatusCode.ERROR_STALE_TREE);
    }
}
