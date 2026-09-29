package org.sanbus.galley;

import java.nio.charset.StandardCharsets;
import java.util.Iterator;
import java.util.List;
import java.util.Objects;

/**
 * Handle for a node in the non-relocating AST storage, bound to one of the
 * two doors: a {@link Session} (post-parse) or the parse's hook door
 * (parse-time, reached through a hook's {@link ProcedureArguments}). Every
 * accessor is one delegation to that door, which gates it: a session node
 * throws once its session closes or parses again, a hook node once the
 * parse it was handed out in ends.
 */
public final class Node implements Iterable<Node> {
    private final NodeDoor door;           // whichever door owns the storage
    private final long address;
    /**
     * Parse generation stamped at construction. The constructor is the
     * single creation gate: every node carries the generation it belongs
     * to, so no door can read storage from an older parse.
     */
    private final long generation;

    public Node(Session session, long address) {
        this(Objects.requireNonNull(session, "session"), address, session.parseGeneration());
    }

    Node(NodeDoor door, long address, long generation) {
        this.door = door;
        this.address = address;
        this.generation = generation;
    }

    public long getAddress() { return address; }

    NodeDoor door() { return door; }

    long generation() { return generation; }

    public byte[] text() {
        return door.text(this);
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
        return door.symbolNameBytes(this);
    }

    public long[] span() {
        return door.span(this);
    }

    public int[] lineColumn() {
        return door.lineColumn(this);
    }

    public Node parent() {
        return door.parent(this);
    }

    public Node firstChild() {
        return door.firstChild(this);
    }

    public Node lastChild() {
        return door.lastChild(this);
    }

    public Node nextSibling() {
        return door.nextSibling(this);
    }

    public Node priorSibling() {
        return door.priorSibling(this);
    }

    public Integer variableIndex() {
        return door.variableIndex(this);
    }

    public int childCount() {
        return door.childCount(this);
    }

    public boolean isValid() {
        return door.nodeValid(this);
    }

    public List<Node> children() {
        return door.children(this);
    }

    public Node cleanChildren() {
        return door.cleanChildren(this);
    }

    /**
     * Appends {@code chain} behind this node's last child. Both handles
     * must belong to the same door; the door's gate refuses one that does
     * not.
     *
     * @throws IllegalArgumentException if {@code chain} belongs to a
     *         different door (another session, or another parse's hook door)
     */
    public void appendChildren(Node chain) {
        door.appendChildren(this, chain);
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
        return address == node.address && door == node.door;
    }

    @Override
    public int hashCode() {
        return Objects.hash(System.identityHashCode(door), address);
    }

    @Override
    public String toString() {
        String name = null;
        try { name = symbolName(); } catch (Exception ignored) {}
        return "Node@" + Long.toHexString(address) + "(" + (name != null ? name : "?") + ")";
    }
}
