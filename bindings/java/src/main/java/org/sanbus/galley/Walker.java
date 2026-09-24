package org.sanbus.galley;

import java.lang.foreign.MemorySegment;
import java.util.Iterator;
import java.util.NoSuchElementException;
import java.util.Objects;

/**
 * Pre-order tree walker over the last successful parse, yielding one
 * {@link WalkStep} per node with the root at depth 0. Shares the session's
 * node storage: close the walker (try-with-resources) before closing the
 * session or parsing again. Created by {@link Session#walk}.
 *
 * Single-pass: iteration resumes, never restarts — a second loop
 * continues where the first left off. Bound to the parse generation that
 * created it: stepping after the session parses again or closes throws
 * instead of reading stale storage.
 */
public final class Walker implements Iterator<Walker.WalkStep>, Iterable<Walker.WalkStep>, AutoCloseable {
    /** One pre-order step: the node, its depth, and its semantic-error flag. */
    public static final class WalkStep {
        public final Node node;
        public final int depth;
        public final boolean isSemanticError;
        public WalkStep(Node node, int depth, boolean isSemanticError) {
            this.node = node;
            this.depth = depth;
            this.isSemanticError = isSemanticError;
        }
    }

    private final Session session;
    private MemorySegment handle;
    private final long generation;
    private WalkStep next;
    private boolean done;

    Walker(Session session, MemorySegment handle, long generation) {
        this.session = Objects.requireNonNull(session, "session");
        this.handle = Objects.requireNonNull(handle, "handle");
        this.generation = generation;
    }

    /**
     * Single gate for steps: closed walkers, closed sessions, and walkers
     * left over from a previous parse generation all throw instead of
     * touching reallocated storage.
     */
    private void requireOpen() {
        if (handle == null) throw new GalleyClosedException("walker");
        if (session.isClosed()) throw new GalleyClosedException("walker's session");
        if (generation != session.parseGeneration()) throw GalleyClosedException.invalidated("walker");
    }

    /**
     * Prunes the children of the last yielded step; iteration continues with
     * its next sibling. No effect without a last step.
     */
    public void skipChildren() {
        requireOpen();
        session.walkerSkipChildren(handle);
    }

    @Override
    public boolean hasNext() {
        requireOpen();
        if (done) return false;
        if (next != null) return true;
        next = session.walkerNext(handle);
        if (next == null) done = true;
        return next != null;
    }

    @Override
    public WalkStep next() {
        if (!hasNext()) throw new NoSuchElementException("walk is done");
        WalkStep step = next;
        next = null;
        return step;
    }

    @Override
    public Iterator<WalkStep> iterator() {
        return this;
    }

    @Override
    public void close() {
        if (handle != null) {
            session.walkerDestroy(handle);
            handle = null;
        }
    }
}
