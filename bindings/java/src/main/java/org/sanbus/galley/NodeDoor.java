package org.sanbus.galley;

import java.lang.foreign.Arena;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.ValueLayout;
import org.sanbus.galley.internal.GalleyLibrary;

/**
 * One of the two doors over a parser's AST storage, as the address-level
 * crossing a {@link Session} call makes. The session door goes through
 * {@code galley_node_*} / {@code galley_tree_*}, which refuse while a parse
 * is in flight; the hook door goes through the {@code galley_hook_*} twins
 * over one parse's native door, unshared by construction. The session
 * picks the door per call ({@link Session}'s {@code door()}): a hook door
 * is created for one hook dispatch and only the thread running that hook
 * may cross it. A {@link Node} stores neither door: it carries the session,
 * the core's parse generation and the address.
 *
 * <p>Every native crossing for a node capability lives here once; the two
 * families differ only in the function called, so one implementation
 * marshals both.
 */
final class NodeDoor {
    static final long INVALID_NODE = 0xFFFFFFFFFFFFFFFFL;

    private final GalleyLibrary lib;
    private final Session session;
    /** The running parse's native door, or null for the session door. */
    private final MemorySegment hookDoor;
    /** The core generation of the parse that owns {@link #hookDoor}. */
    private final long hookGeneration;

    private NodeDoor(GalleyLibrary lib, Session session, MemorySegment hookDoor, long hookGeneration) {
        this.lib = lib;
        this.session = session;
        this.hookDoor = hookDoor;
        this.hookGeneration = hookGeneration;
    }

    /** The post-parse door of {@code session}. */
    static NodeDoor ofSession(GalleyLibrary lib, Session session) {
        return new NodeDoor(lib, session, null, 0);
    }

    /** The hook door of one parse, in the core generation {@code generation}. */
    static NodeDoor ofHook(GalleyLibrary lib, Session session, MemorySegment door, long generation) {
        return new NodeDoor(lib, session, door, generation);
    }

    boolean isHook() { return hookDoor != null; }

    /**
     * The core generation a node must carry to cross this door: the running
     * parse's on the hook door, the published tree's (as last read from the
     * core) on the session door.
     */
    long generation() {
        return hookDoor != null ? hookGeneration : session.publishedGeneration();
    }

    /**
     * The host failure for a negative native status: the session door's
     * carries the session's diagnostic snapshot, the hook door's only the
     * status text. One place for the conversion, so no crossing spells it
     * out itself.
     */
    GalleyException failure(long status) {
        return hookDoor != null ? hookFailure(lib, status) : session.errorFromStatus(status);
    }

    /** The host failure for a negative status from a hook door or per-hook crossing. */
    static GalleyException hookFailure(GalleyLibrary lib, long status) {
        String message = lib.galley_status_string(status);
        return new GalleyException(message != null ? message : "procedure error", (int) status);
    }

    private void check(long status) {
        if (status < 0) throw failure(status);
    }

    // -- reads --

    boolean nodeValid(long address) {
        return (hookDoor != null ? lib.galley_hook_node_is_valid(hookDoor, address)
                                 : lib.galley_node_is_valid(session.handle(), address)) != 0;
    }

    int childCount(long address) {
        return hookDoor != null ? lib.galley_hook_node_child_count(hookDoor, address)
                                : lib.galley_node_child_count(session.handle(), address);
    }

    long firstChild(long address) {
        return hookDoor != null ? lib.galley_hook_node_first_child(hookDoor, address)
                                : lib.galley_node_first_child(session.handle(), address);
    }

    long lastChild(long address) {
        return hookDoor != null ? lib.galley_hook_node_last_child(hookDoor, address)
                                : lib.galley_node_last_child(session.handle(), address);
    }

    long nextSibling(long address) {
        return hookDoor != null ? lib.galley_hook_node_next_sibling(hookDoor, address)
                                : lib.galley_node_next_sibling(session.handle(), address);
    }

    long priorSibling(long address) {
        return hookDoor != null ? lib.galley_hook_node_prior_sibling(hookDoor, address)
                                : lib.galley_node_prior_sibling(session.handle(), address);
    }

    long parent(long address) {
        return hookDoor != null ? lib.galley_hook_node_parent(hookDoor, address)
                                : lib.galley_node_parent(session.handle(), address);
    }

    byte[] text(long address) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLength = arena.allocate(ValueLayout.JAVA_LONG);
            long status = hookDoor != null ? lib.galley_hook_node_text(hookDoor, address, outData, outLength)
                                           : lib.galley_node_text(session.handle(), address, outData, outLength);
            return outBytes(status, outData, outLength);
        }
    }

    byte[] symbolNameBytes(long address) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLength = arena.allocate(ValueLayout.JAVA_LONG);
            long status = hookDoor != null ? lib.galley_hook_node_symbol_name(hookDoor, address, outData, outLength)
                                           : lib.galley_node_symbol_name(session.handle(), address, outData, outLength);
            return outBytes(status, outData, outLength);
        }
    }

    long[] span(long address) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outStart = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outLength = arena.allocate(ValueLayout.JAVA_LONG);
            long status = hookDoor != null ? lib.galley_hook_node_span(hookDoor, address, outStart, outLength)
                                           : lib.galley_node_span(session.handle(), address, outStart, outLength);
            if (status < 0) return null;
            return new long[]{outStart.get(ValueLayout.JAVA_LONG, 0), outLength.get(ValueLayout.JAVA_LONG, 0)};
        }
    }

    int[] lineColumn(long address) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outLine = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outColumn = arena.allocate(ValueLayout.JAVA_INT);
            long status = hookDoor != null ? lib.galley_hook_node_line_column(hookDoor, address, outLine, outColumn)
                                           : lib.galley_node_line_column(session.handle(), address, outLine, outColumn);
            if (status < 0) return null;
            return new int[]{outLine.get(ValueLayout.JAVA_INT, 0), outColumn.get(ValueLayout.JAVA_INT, 0)};
        }
    }

    Integer variableIndex(long address) {
        long index = hookDoor != null ? lib.galley_hook_node_variable_index(hookDoor, address)
                                      : lib.galley_node_variable_index(session.handle(), address);
        if (index == -1) return null;
        if (index < 0) throw failure(index);
        return (int) index;
    }

    // -- tree edits --

    void appendChildren(long parent, long chain) {
        check(hookDoor != null ? lib.galley_hook_tree_append_children(hookDoor, parent, chain)
                               : lib.galley_tree_append_children(session.handle(), parent, chain));
    }

    void insertBefore(long target, long chain) {
        check(hookDoor != null ? lib.galley_hook_tree_insert_before(hookDoor, target, chain)
                               : lib.galley_tree_insert_before(session.handle(), target, chain));
    }

    void insertAfter(long target, long chain) {
        check(hookDoor != null ? lib.galley_hook_tree_insert_after(hookDoor, target, chain)
                               : lib.galley_tree_insert_after(session.handle(), target, chain));
    }

    /** A tree edit that detaches a chain: runs {@code call} with an out-head and returns the head, {@link #INVALID_NODE} when empty. */
    private interface HeadCall {
        long run(MemorySegment outHead);
    }

    private long detachedHead(HeadCall call) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outHead = arena.allocate(ValueLayout.JAVA_LONG);
            outHead.set(ValueLayout.JAVA_LONG, 0, INVALID_NODE);
            check(call.run(outHead));
            return outHead.get(ValueLayout.JAVA_LONG, 0);
        }
    }

    long removeSiblings(long address, int count) {
        return detachedHead(outHead -> hookDoor != null
                ? lib.galley_hook_tree_remove_siblings(hookDoor, address, count, outHead)
                : lib.galley_tree_remove_siblings(session.handle(), address, count, outHead));
    }

    long removeSelf(long address) {
        return detachedHead(outHead -> hookDoor != null
                ? lib.galley_hook_tree_remove_self(hookDoor, address, outHead)
                : lib.galley_tree_remove_self(session.handle(), address, outHead));
    }

    long promoteChildrenOverWrapper(long wrapper) {
        return detachedHead(outHead -> hookDoor != null
                ? lib.galley_hook_tree_promote_children_over_wrapper(hookDoor, wrapper, outHead)
                : lib.galley_tree_promote_children_over_wrapper(session.handle(), wrapper, outHead));
    }

    long cleanChildren(long address) {
        return detachedHead(outHead -> hookDoor != null
                ? lib.galley_hook_tree_clean_children(hookDoor, address, outHead)
                : lib.galley_tree_clean_children(session.handle(), address, outHead));
    }

    void unlinkWrapper(long wrapper) {
        check(hookDoor != null ? lib.galley_hook_tree_unlink_wrapper(hookDoor, wrapper)
                               : lib.galley_tree_unlink_wrapper(session.handle(), wrapper));
    }

    void insertChildrenAt(long parent, int index, long chain) {
        check(hookDoor != null ? lib.galley_hook_tree_insert_children_at(hookDoor, parent, index, chain)
                               : lib.galley_tree_insert_children_at(session.handle(), parent, index, chain));
    }

    long removeChildrenAt(long parent, int index, int count) {
        return detachedHead(outHead -> hookDoor != null
                ? lib.galley_hook_tree_remove_children_at(hookDoor, parent, index, count, outHead)
                : lib.galley_tree_remove_children_at(session.handle(), parent, index, count, outHead));
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
