package org.sanbus.galley;

/**
 * A handle left over from an older parse generation: unusable after its
 * session parses again, never a stale read. Extends
 * {@link GalleyClosedException} so existing catch sites keep working while
 * new code can discriminate by type instead of matching message text.
 * One shared type for walkers and nodes: invalidation is a single
 * generation concept, and the failing object rides in
 * {@link GalleyClosedException#getObjectName()}.
 */
public class GenerationInvalidatedException extends GalleyClosedException {
    public GenerationInvalidatedException(String objectName) {
        super(objectName, objectName + " is invalidated");
    }
}
