package org.sanbus.galley;

/**
 * Flat bulk read of the most recent successful parse (see
 * {@link Session#snapshot()}): one entry per node address. Missing links
 * read as {@link Galley#INVALID_NODE}, missing variables as {@code -1L},
 * spans index {@link Session#lastInput()}, and
 * {@code isSemanticError} carries the flag {@link Walker.WalkStep} yields.
 *
 * <p>The columns are fixed at the parse they describe, and the snapshot
 * remembers that parse's generation: {@link #node(long)} is the one
 * conversion from a stored address back to a node, and the node it returns
 * belongs to that parse — stale once the session parses again.
 */
public final class TreeSnapshot {
    private final Session session;
    private final long generation;
    private final long count;
    private final long[] parent;
    private final long[] firstChild;
    private final long[] next;
    private final int[] childCount;
    private final long[] variable;
    private final long[] spanStart;
    private final long[] spanLen;
    private final boolean[] isSemanticError;

    /** One snapshot of {@code session}'s published tree in {@code generation}. */
    TreeSnapshot(Session session, long generation, long count, long[] parent,
            long[] firstChild, long[] next, int[] childCount, long[] variable,
            long[] spanStart, long[] spanLen, boolean[] isSemanticError) {
        this.session = session;
        this.generation = generation;
        this.count = count;
        this.parent = parent;
        this.firstChild = firstChild;
        this.next = next;
        this.childCount = childCount;
        this.variable = variable;
        this.spanStart = spanStart;
        this.spanLen = spanLen;
        this.isSemanticError = isSemanticError;
    }

    public long count() { return count; }

    public long[] parent() { return parent; }

    public long[] firstChild() { return firstChild; }

    public long[] next() { return next; }

    public int[] childCount() { return childCount; }

    public long[] variable() { return variable; }

    public long[] spanStart() { return spanStart; }

    public long[] spanLen() { return spanLen; }

    public boolean[] isSemanticError() { return isSemanticError; }

    /**
     * The node at {@code address} for the parse these columns describe, or
     * null for {@link Galley#INVALID_NODE}. The node carries this
     * snapshot's parse generation, so it reads as stale once the
     * session parses again.
     *
     * @throws IndexOutOfBoundsException if {@code address} is at or past
     *         {@link #count()}, or negative otherwise
     */
    public Node node(long address) {
        if (address == Galley.INVALID_NODE) return null;
        if (address < 0 || address >= count) {
            throw new IndexOutOfBoundsException("node address " + address
                    + " out of range for a snapshot of " + count + " nodes");
        }
        return new Node(session, address, generation);
    }
}
