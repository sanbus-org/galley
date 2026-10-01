package org.sanbus.galley;

import java.nio.charset.StandardCharsets;
import java.util.Iterator;
import java.util.List;
import java.util.Objects;

/**
 * Handle for a node in the non-relocating AST storage: its owning
 * {@link Session}, the core's parse generation it belongs to, and its
 * address. Every accessor is one delegation to the session, which chooses
 * the door when the call is made (the parse's hook door from inside a hook
 * of its running parse on the thread running that hook, the post-parse door
 * everywhere else) and gates it: a node throws once its session closes or
 * its generation is gone. Nodes handed out by the hooks of a parse that
 * publishes its tree stay valid until the session parses again; nodes of a
 * failed parse are gone.
 */
public final class Node implements Iterable<Node> {
    private final Session session;
    private final long address;
    /**
     * The core's parse generation, stamped at construction. The constructor
     * is the single creation gate: every node carries the generation it
     * belongs to, so no door can read storage from another parse.
     */
    private final long generation;

    /**
     * Wraps a raw address, stamped with the generation of the door a call
     * made now would cross. A raw address carries no generation of its own,
     * so this is the explicit conversion and the caller vouches for it.
     */
    public Node(Session session, long address) {
        this(Objects.requireNonNull(session, "session"), address, session.currentGeneration());
    }

    Node(Session session, long address, long generation) {
        this.session = session;
        this.address = address;
        this.generation = generation;
    }

    public long getAddress() { return address; }

    Session session() { return session; }

    long generation() { return generation; }

    public byte[] text() {
        return session.text(this);
    }

    /**
     * Grammar name of this node's symbol, decoded as UTF-8 with replacement
     * for malformed input. Null for invalid nodes. Token content stays raw
     * bytes: use {@link #text} for that.
     */
    public String symbolName() {
        byte[] bytes = symbolNameBytes();
        return bytes == null ? null : new String(bytes, StandardCharsets.UTF_8);
    }

    /** Raw bytes behind {@link #symbolName()}. Null for invalid nodes. */
    public byte[] symbolNameBytes() {
        return session.symbolNameBytes(this);
    }

    public long[] span() {
        return session.span(this);
    }

    public int[] lineColumn() {
        return session.lineColumn(this);
    }

    public Node parent() {
        return session.parent(this);
    }

    public Node firstChild() {
        return session.firstChild(this);
    }

    public Node lastChild() {
        return session.lastChild(this);
    }

    public Node nextSibling() {
        return session.nextSibling(this);
    }

    public Node priorSibling() {
        return session.priorSibling(this);
    }

    public Integer variableIndex() {
        return session.variableIndex(this);
    }

    public int childCount() {
        return session.childCount(this);
    }

    public boolean isValid() {
        return session.nodeValid(this);
    }

    public List<Node> children() {
        return session.children(this);
    }

    public Node cleanChildren() {
        return session.cleanChildren(this);
    }

    /**
     * Appends {@code chain} behind this node's last child. Both handles
     * must belong to the same session and be live for the same door; the
     * session's gate refuses one that is not.
     *
     * @throws IllegalArgumentException if {@code chain} belongs to another session
     * @throws GenerationInvalidatedException if {@code chain}'s generation is gone
     */
    public void appendChildren(Node chain) {
        session.appendChildren(this, chain);
    }

    public int length() { return childCount(); }

    public Node at(int index) {
        List<Node> kids = children();
        int size = kids.size();
        int idx = index < 0 ? size + index : index;
        if (idx < 0 || idx >= size) throw new IndexOutOfBoundsException("node index " + index + " out of range " + size);
        return kids.get(idx);
    }

    @Override
    public Iterator<Node> iterator() {
        return children().iterator();
    }

    // Collection spelling of length(); not an unused duplicate.
    public int size() { return length(); }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof Node)) return false;
        Node node = (Node) o;
        return address == node.address && generation == node.generation && session == node.session;
    }

    @Override
    public int hashCode() {
        return Objects.hash(System.identityHashCode(session), generation, address);
    }

    @Override
    public String toString() {
        String name = null;
        try { name = symbolName(); } catch (Exception ignored) {}
        return "Node@" + Long.toHexString(address) + "(" + (name != null ? name : "?") + ")";
    }
}
