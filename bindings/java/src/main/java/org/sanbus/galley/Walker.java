package org.sanbus.galley;

import java.lang.foreign.Arena;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.ValueLayout;
import java.util.Iterator;
import java.util.NoSuchElementException;
import java.util.Objects;

/**
 * Pre-order tree walker over the published parse, yielding one
 * {@link WalkStep} per node with the walk's root at depth 0. Created by
 * {@link Node#walk}.
 *
 * <p>The walker owns no native resource: it is one host-side 40-byte
 * cursor, so abandoning it is free and parsing again with one open never
 * disturbs the parse — the walker fails at its next step instead. Each
 * step picks its door like any node call, so a walk created inside a hook
 * of a running parse walks that parse's in-flight tree, and the same walk
 * replayed after the parse publishes reproduces it. Steps follow the live
 * links, so edits between steps are visible; a step whose position is no
 * longer inside the walk's root (removed, or moved elsewhere) throws
 * {@code invalid node}.
 *
 * <p>Single-pass: iteration resumes, never restarts — a second loop
 * continues where the first left off. Bound to the core's parse generation
 * of the tree it was created over: stepping after the session parses again
 * or closes throws instead of reading stale storage.
 */
public final class Walker implements Iterator<Walker.WalkStep>, Iterable<Walker.WalkStep> {
    /**
     * One pre-order step: the node, its depth, its semantic-error flag, and
     * whether it is a node syntax-error recovery kept in place of damaged
     * input (its span covers the input recovery skipped).
     */
    public static final class WalkStep {
        public final Node node;
        public final int depth;
        public final boolean isSemanticError;
        public final boolean isRecovered;
        public WalkStep(Node node, int depth, boolean isSemanticError, boolean isRecovered) {
            this.node = node;
            this.depth = depth;
            this.isSemanticError = isSemanticError;
            this.isRecovered = isRecovered;
        }
    }

    private final Session session;
    /** Owns the cursor bytes; reclaimed with the walker, no close needed. */
    private final Arena arena;
    private final MemorySegment cursor;
    private final long generation;
    private WalkStep next;
    private boolean done;

    Walker(Session session, long root, long generation, boolean skipSemanticErrors, boolean skipRecovered) {
        this.session = Objects.requireNonNull(session, "session");
        this.generation = generation;
        this.arena = Arena.ofAuto();
        this.cursor = arena.allocate(WalkCursor.BYTES, WalkCursor.ALIGNMENT);
        cursor.set(ValueLayout.JAVA_LONG, WalkCursor.GENERATION_OFFSET, generation);
        cursor.set(ValueLayout.JAVA_LONG, WalkCursor.ROOT_OFFSET, root);
        cursor.set(ValueLayout.JAVA_LONG, WalkCursor.CURRENT_OFFSET, 0L);
        cursor.set(ValueLayout.JAVA_INT, WalkCursor.DEPTH_OFFSET, 0);
        cursor.set(ValueLayout.JAVA_SHORT, WalkCursor.STATE_OFFSET, WalkCursor.STATE_NOT_STARTED);
        cursor.set(ValueLayout.JAVA_BYTE, WalkCursor.OPTIONS_OFFSET,
                (byte) ((skipSemanticErrors ? WalkCursor.OPTION_SKIP_SEMANTIC_ERRORS : 0)
                        | (skipRecovered ? WalkCursor.OPTION_SKIP_RECOVERED : 0)));
        cursor.set(ValueLayout.JAVA_BYTE, WalkCursor.FLAG_OFFSET, (byte) 0);
        cursor.set(ValueLayout.JAVA_LONG, WalkCursor.STRUCTURE_VERSION_OFFSET, 0L);
    }

    /**
     * Prunes the children of the last yielded step; iteration continues with
     * its next sibling. No effect without a last step. A pure host-side
     * state write: staleness is the next step's answer, not this one's.
     */
    public void skipChildren() {
        if (session.isClosed()) throw new GalleyClosedException("walker's session");
        if (cursor.get(ValueLayout.JAVA_SHORT, WalkCursor.STATE_OFFSET) == WalkCursor.STATE_YIELDED)
            cursor.set(ValueLayout.JAVA_SHORT, WalkCursor.STATE_OFFSET, WalkCursor.STATE_YIELDED_SKIP_CHILDREN);
    }

    @Override
    public boolean hasNext() {
        if (session.isClosed()) throw new GalleyClosedException("walker's session");
        if (done) return false;
        if (next != null) return true;
        next = session.walkerStep(cursor, generation);
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
}
