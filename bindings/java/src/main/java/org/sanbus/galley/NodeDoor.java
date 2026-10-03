package org.sanbus.galley;

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
     * The generation a node must carry to cross the hook door: the running
     * parse's. The session door has none — every crossing there passes the
     * node's own generation to the core, which owns the comparison.
     */
    long generation() {
        return hookGeneration;
    }

    /**
     * The host failure for a negative native status: the session door's
     * carries the session's diagnostic snapshot, the hook door's only the
     * status text. Both go through {@link Session#statusFailure}, the one
     * mapper, so a stale tree is the same exception whichever door found it.
     */
    GalleyException failure(long status) {
        return hookDoor != null ? Session.statusFailure(lib, status, null) : session.errorFromStatus(status);
    }

    /** Throws on a negative status; otherwise returns it, which for a value-returning call is the value. */
    private long check(long status) {
        if (status < 0) throw failure(status);
        return status;
    }

    // -- reads --
    //
    // Every session-door crossing takes the generation of the tree it
    // addresses, which the core compares against the published one: a
    // mismatch is a stale tree, never a read. The hook twins take none —
    // their door exists only while its parse runs, and every node it can
    // address belongs to that parse.
    //
    // Calls with one result (count, links, variable index) return it directly:
    // non-negative is the answer, negative the status. Calls with several
    // results write them through the calling thread's {@link Scratch}: reads
    // run on several threads at once, so nothing here allocates per call or
    // shares a segment between threads.

    int childCount(long generation, long address) {
        if (hookDoor != null) return lib.galley_hook_node_child_count(hookDoor, address);
        return (int) check(lib.galley_node_child_count(session.handle(), generation, address));
    }

    /** The five tree links; one crossing, one switch per door. */
    enum Link { FIRST_CHILD, LAST_CHILD, NEXT_SIBLING, PRIOR_SIBLING, PARENT }

    /** One link through this door; {@link Galley#INVALID_NODE} when it does not exist. */
    long link(Link which, long generation, long address) {
        if (hookDoor != null) {
            return switch (which) {
                case FIRST_CHILD -> lib.galley_hook_node_first_child(hookDoor, address);
                case LAST_CHILD -> lib.galley_hook_node_last_child(hookDoor, address);
                case NEXT_SIBLING -> lib.galley_hook_node_next_sibling(hookDoor, address);
                case PRIOR_SIBLING -> lib.galley_hook_node_prior_sibling(hookDoor, address);
                case PARENT -> lib.galley_hook_node_parent(hookDoor, address);
            };
        }
        MemorySegment handle = session.handle();
        return check(switch (which) {
            case FIRST_CHILD -> lib.galley_node_first_child(handle, generation, address);
            case LAST_CHILD -> lib.galley_node_last_child(handle, generation, address);
            case NEXT_SIBLING -> lib.galley_node_next_sibling(handle, generation, address);
            case PRIOR_SIBLING -> lib.galley_node_prior_sibling(handle, generation, address);
            case PARENT -> lib.galley_node_parent(handle, generation, address);
        });
    }

    byte[] text(long generation, long address) {
        Scratch scratch = Scratch.local();
        if (hookDoor != null) {
            if (lib.galley_hook_node_text(hookDoor, address, scratch.first, scratch.second) < 0) return null;
        } else {
            check(lib.galley_node_text(session.handle(), generation, address, scratch.first, scratch.second));
        }
        return copyBytes(scratch);
    }

    byte[] symbolNameBytes(long generation, long address) {
        Scratch scratch = Scratch.local();
        if (hookDoor != null) {
            if (lib.galley_hook_node_symbol_name(hookDoor, address, scratch.first, scratch.second) < 0) return null;
        } else {
            check(lib.galley_node_symbol_name(session.handle(), generation, address, scratch.first, scratch.second));
        }
        return copyBytes(scratch);
    }

    long[] span(long generation, long address) {
        Scratch scratch = Scratch.local();
        if (hookDoor != null) {
            if (lib.galley_hook_node_span(hookDoor, address, scratch.first, scratch.second) < 0) return null;
        } else {
            check(lib.galley_node_span(session.handle(), generation, address, scratch.first, scratch.second));
        }
        return new long[]{scratch.firstLong(), scratch.secondLong()};
    }

    int[] lineColumn(long generation, long address) {
        Scratch scratch = Scratch.local();
        if (hookDoor != null) {
            if (lib.galley_hook_node_line_column(hookDoor, address, scratch.first, scratch.second) < 0) return null;
        } else {
            check(lib.galley_node_line_column(session.handle(), generation, address, scratch.first, scratch.second));
        }
        return new int[]{scratch.firstInt(), scratch.secondInt()};
    }

    Integer variableIndex(long generation, long address) {
        long index = hookDoor != null
                ? lib.galley_hook_node_variable_index(hookDoor, address)
                : check(lib.galley_node_variable_index(session.handle(), generation, address));
        return index < 0 || index == Galley.NO_VARIABLE ? null : (int) index;
    }

    // -- walking --

    /**
     * One step of a walk over the host-owned cursor: 1 yields a node, 0
     * ends the walk (and keeps ending it), negative is a failure
     * (stale tree, session in use, invalid cursor bytes).
     */
    long walkStep(MemorySegment cursor) {
        return hookDoor != null ? lib.galley_hook_walk_next(hookDoor, cursor)
                                : lib.galley_walk_next(session.handle(), cursor);
    }

    // -- tree edits --

    void appendChildren(long generation, long parent, long chain) {
        check(hookDoor != null ? lib.galley_hook_tree_append_children(hookDoor, parent, chain)
                               : lib.galley_tree_append_children(session.handle(), generation, parent, chain));
    }

    void insertBefore(long generation, long target, long chain) {
        check(hookDoor != null ? lib.galley_hook_tree_insert_before(hookDoor, target, chain)
                               : lib.galley_tree_insert_before(session.handle(), generation, target, chain));
    }

    void insertAfter(long generation, long target, long chain) {
        check(hookDoor != null ? lib.galley_hook_tree_insert_after(hookDoor, target, chain)
                               : lib.galley_tree_insert_after(session.handle(), generation, target, chain));
    }

    /** A tree edit that detaches a chain: runs {@code call} with an out-head and returns the head, {@link Galley#INVALID_NODE} when empty. */
    private interface HeadCall {
        long run(MemorySegment outHead);
    }

    private long detachedHead(HeadCall call) {
        Scratch scratch = Scratch.local();
        scratch.first.set(ValueLayout.JAVA_LONG, 0, Galley.INVALID_NODE);
        check(call.run(scratch.first));
        return scratch.firstLong();
    }

    long removeSiblings(long generation, long address, int count) {
        return detachedHead(outHead -> hookDoor != null
                ? lib.galley_hook_tree_remove_siblings(hookDoor, address, count, outHead)
                : lib.galley_tree_remove_siblings(session.handle(), generation, address, count, outHead));
    }

    long removeSelf(long generation, long address) {
        return detachedHead(outHead -> hookDoor != null
                ? lib.galley_hook_tree_remove_self(hookDoor, address, outHead)
                : lib.galley_tree_remove_self(session.handle(), generation, address, outHead));
    }

    long cleanChildren(long generation, long address) {
        return detachedHead(outHead -> hookDoor != null
                ? lib.galley_hook_tree_clean_children(hookDoor, address, outHead)
                : lib.galley_tree_clean_children(session.handle(), generation, address, outHead));
    }

    void insertChildrenAt(long generation, long parent, int index, long chain) {
        check(hookDoor != null ? lib.galley_hook_tree_insert_children_at(hookDoor, parent, index, chain)
                               : lib.galley_tree_insert_children_at(session.handle(), generation, parent, index, chain));
    }

    long removeChildrenAt(long generation, long parent, int index, int count) {
        return detachedHead(outHead -> hookDoor != null
                ? lib.galley_hook_tree_remove_children_at(hookDoor, parent, index, count, outHead)
                : lib.galley_tree_remove_children_at(session.handle(), generation, parent, index, count, outHead));
    }

    /**
     * Copies the out-pointer/out-length pair a successful call wrote: an
     * empty array for a null pointer or zero length, otherwise the bytes.
     */
    private static byte[] copyBytes(Scratch scratch) {
        MemorySegment pointer = scratch.first.get(ValueLayout.ADDRESS, 0);
        long length = scratch.secondLong();
        if (pointer.equals(MemorySegment.NULL) || length == 0) return new byte[0];
        return pointer.reinterpret(length).toArray(ValueLayout.JAVA_BYTE);
    }
}
