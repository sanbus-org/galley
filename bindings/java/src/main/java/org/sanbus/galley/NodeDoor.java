package org.sanbus.galley;

import java.lang.foreign.MemorySegment;
import java.lang.foreign.ValueLayout;
import java.util.ArrayList;
import java.util.List;

/**
 * One of the two node doors over a parser's AST storage: the post-parse
 * {@link Session} handle or the parse's {@link HookDoor}. Every node
 * capability crosses exactly one native call — the session door goes
 * through {@code galley_node_*}, which refuses while a parse is in flight;
 * the hook door goes through {@code galley_hook_*}, unshared by
 * construction. {@link Node} is a handle that delegates each accessor to
 * its door, and each door gates its own crossings through {@link #address},
 * so no accessor can cross without passing it.
 *
 * <p>An abstract class rather than an interface so the gate and the
 * liveness hook stay package-private instead of widening {@link Session}'s
 * public surface.
 */
abstract class NodeDoor {
    /**
     * Door-specific liveness of a node that belongs to this door: throws
     * when the door's session is closed or the node outlived the parse
     * generation it was created in.
     */
    abstract void requireLive(Node node);

    /**
     * The single gate for a node argument: the node must be live on the
     * door it belongs to, and that door must be this one. The crossing sends
     * a bare address and native storage only bounds-checks it, so a node
     * from another door would silently alias whichever node holds that
     * index here. A node's own liveness is judged first, so a dead handle
     * reports that it is dead whichever door it is offered to. Raw-address
     * overloads receive no handle to compare and stay unguarded by design.
     *
     * @throws IllegalArgumentException if {@code node} belongs to another
     *         door (another session, or a parse's hook door)
     */
    final long address(Node node) {
        NodeDoor home = node.door();
        home.requireLive(node);
        if (home != this) {
            throw new IllegalArgumentException("node belongs to a different door than this operation");
        }
        return node.getAddress();
    }

    abstract boolean nodeValid(Node node);

    abstract int childCount(Node node);

    abstract Node firstChild(Node node);

    abstract Node lastChild(Node node);

    abstract Node nextSibling(Node node);

    abstract Node priorSibling(Node node);

    abstract Node parent(Node node);

    abstract byte[] text(Node node);

    abstract byte[] symbolNameBytes(Node node);

    abstract long[] span(Node node);

    abstract int[] lineColumn(Node node);

    abstract Integer variableIndex(Node node);

    abstract Node cleanChildren(Node node);

    abstract void appendChildren(Node parent, Node chain);

    /** Child chain of {@code node}, in birth order. */
    List<Node> children(Node node) {
        return collectChildren(childCount(node), firstChild(node));
    }

    /**
     * The one children iteration, shared by both doors and by raw-address
     * entry points: count-bounded, first to last, every step crossing this
     * door's own primitives. A child count that moves mid-iteration throws
     * instead of yielding a torn walk.
     */
    final List<Node> collectChildren(int count, Node first) {
        List<Node> out = new ArrayList<>(count);
        Node child = first;
        for (int i = 0; i < count; i++) {
            if (child == null) throw new IllegalStateException("child count changed during iteration");
            out.add(child);
            child = nextSibling(child);
        }
        return out;
    }

    /**
     * Decodes an out-pointer/out-length result pair written by a native
     * call: null for a negative status, an empty array for a null pointer
     * or zero length, otherwise a copy of the bytes.
     */
    static byte[] outBytes(long status, MemorySegment outData, MemorySegment outLen) {
        if (status < 0) return null;
        MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
        long len = outLen.get(ValueLayout.JAVA_LONG, 0);
        if (ptr.equals(MemorySegment.NULL) || len == 0) return new byte[0];
        return ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
    }
}
