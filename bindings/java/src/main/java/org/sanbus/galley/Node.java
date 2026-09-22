package org.sanbus.galley;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Objects;

/**
 * Session-bound handle for a node in the non-relocating AST storage.
 * Keeps a strong reference to its Session, mirroring Python's galley.Node
 * and TypeScript's Node.
 */
public final class Node implements Iterable<Node> {
    private final Session session;
    private final long address;
    /**
     * Parse generation stamped at construction. The constructor is the
     * single creation gate: every node carries the generation it belongs
     * to, so no accessor can read storage from an older parse.
     */
    private final long generation;

    public Node(Session session, long address) {
        this.session = Objects.requireNonNull(session, "session");
        this.address = address;
        this.generation = session.parseGeneration();
    }

    public Session getSession() { return session; }
    public long getAddress() { return address; }

    private void requireOpen() {
        if (session.isClosed()) throw new GalleyClosedException("node's session");
        if (generation != session.parseGeneration()) throw GalleyClosedException.invalidated("node");
    }

    /**
     * Single gate for session crossings that accept a node handle:
     * validates the handle (a closed session or an older parse generation
     * raises instead of reading stale storage) and yields the raw address.
     * Raw addresses carry no generation and pass unguarded by design.
     */
    long validatedAddress() {
        requireOpen();
        return address;
    }

    // Delegated accessors

    public byte[] text() { requireOpen(); return session.text(this); }
    /**
     * Grammar name of this node's symbol, decoded as UTF-8 with replacement
     * for malformed input. Null for invalid nodes. Token content stays raw
     * bytes: use {@link #text} for that.
     */
    public String symbolName() { requireOpen(); return session.symbolName(this); }
    /** Raw bytes behind {@link #symbolName()}. Null for invalid nodes. */
    public byte[] symbolNameBytes() { requireOpen(); return session.symbolNameBytes(this); }
    public long[] span() { requireOpen(); return session.span(this); }
    public int[] lineColumn() { requireOpen(); return session.lineColumn(this); }
    public Node parent() { requireOpen(); return session.parent(this); }
    public Node firstChild() { requireOpen(); return session.firstChild(this); }
    public Node lastChild() { requireOpen(); return session.lastChild(this); }
    public Node nextSibling() { requireOpen(); return session.nextSibling(this); }
    public Node priorSibling() { requireOpen(); return session.priorSibling(this); }
    public Integer variableIndex() { requireOpen(); return session.variableIndex(this); }
    public int childCount() { requireOpen(); return session.childCount(this); }
    public boolean isValid() { return session.nodeValid(this); }

    public List<Node> children() { requireOpen(); return session.children(this); }

    public Node cleanChildren() { requireOpen(); return session.cleanChildren(this); }
    public void appendChildren(Node chain) { requireOpen(); session.appendChildren(this, chain); }

    public int length() { return childCount(); }

    public Node at(int index) {
        requireOpen();
        List<Node> kids = children();
        int size = kids.size();
        int idx = index < 0 ? size + index : index;
        if (idx < 0 || idx >= size) throw new IndexOutOfBoundsException("node index " + index + " out of range " + size);
        return kids.get(idx);
    }

    @Override
    public Iterator<Node> iterator() {
        requireOpen();
        List<Node> kids = children();
        return kids.iterator();
    }

    // Java equivalent of Python's __len__, __getitem__, __iter__
    public int size() { return length(); }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof Node)) return false;
        Node node = (Node) o;
        return address == node.address && session == node.session;
    }

    @Override
    public int hashCode() {
        return Objects.hash(System.identityHashCode(session), address);
    }

    @Override
    public String toString() {
        String name = null;
        try { name = symbolName(); } catch (Exception ignored) {}
        return "Node@" + Long.toHexString(address) + "(" + (name != null ? name : "?") + ")";
    }

    // For JNA convenience, allow passing Node where long expected
    public long addressForNative() { return address; }
}
