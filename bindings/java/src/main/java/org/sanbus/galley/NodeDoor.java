package org.sanbus.galley;

import java.lang.foreign.MemorySegment;
import java.lang.foreign.ValueLayout;
import java.util.function.LongFunction;
import org.sanbus.galley.internal.GalleyLibrary;
import org.sanbus.galley.internal.NodeCalls;

/**
 * A door over a parser's AST storage, as the address-level crossing a
 * {@link Session} call makes. The session door goes through
 * {@code galley_node_*} / {@code galley_tree_*} over the session handle,
 * which the core refuses while a parse is in flight; the hook door goes
 * through the {@code galley_hook_*} twins over one parse's native door,
 * unshared by construction. The two differ only in what they are opened on,
 * so a door is data: the family of downcalls ({@link NodeCalls}, two sets of
 * handles with identical types), the handle to call it on, and how to turn
 * a refusal into the host's failure. Every crossing claims the session
 * handle through {@link Session#gate}, so close cannot free the session
 * under a call in flight. The core checks the node's generation inside
 * every call on either door. The session picks the door per call
 * ({@link Session}'s {@code door()}): a hook door is created for one parse
 * and only the thread running its hook may cross it. A {@link Node} stores
 * neither door: it carries the session, the core's parse generation and the
 * address.
 *
 * <p>Every native crossing for a node capability lives here once.
 */
final class NodeDoor {
    private final NodeCalls calls;
    private final Session session;
    /** The parse's own door for a hook door; {@link MemorySegment#NULL} for the session door. */
    private final MemorySegment hookDoor;
    private final LongFunction<GalleyException> failure;

    private NodeDoor(NodeCalls calls, Session session, MemorySegment hookDoor, LongFunction<GalleyException> failure) {
        this.calls = calls;
        this.session = session;
        this.hookDoor = hookDoor;
        this.failure = failure;
    }

    /** The post-parse door of {@code session}; refusals carry its diagnostic snapshot. */
    static NodeDoor ofSession(GalleyLibrary lib, Session session) {
        return new NodeDoor(lib.sessionCalls, session, MemorySegment.NULL, session::errorFromStatus);
    }

    /** The hook door of one parse; refusals carry only the status text. */
    static NodeDoor ofHook(GalleyLibrary lib, Session session, MemorySegment door) {
        return new NodeDoor(lib.hookCalls, session, door, status -> Session.statusFailure(lib, status, null));
    }

    /**
     * The one crossing for this door: claims the session handle through
     * {@link Session#gate}, the count close refuses on, and hands the call
     * the segment this door opens on — the parse's own door for a hook
     * door, the claimed handle for the session door.
     */
    private <T> T cross(Session.HandleCall<T> call) {
        return session.gate(handle -> call.run(hookDoor.equals(MemorySegment.NULL) ? handle : hookDoor));
    }

    /**
     * The host failure for a negative native status. Both doors map through
     * {@link Session#statusFailure}, the one mapper, so a stale tree is the
     * same exception whichever door found it.
     */
    GalleyException failure(long status) {
        return failure.apply(status);
    }

    /** Throws on a negative status; otherwise returns it, which for a value-returning call is the value. */
    private long check(long status) {
        if (status < 0) throw failure(status);
        return status;
    }

    // -- reads --
    //
    // Every crossing takes the generation of the tree it addresses, which the
    // core compares against the door's tree: a mismatch is a stale tree,
    // never a read.
    //
    // Calls with one result (count, links, variable index) return it directly:
    // non-negative is the answer, negative the status. Calls with several
    // results write them through the calling thread's {@link Scratch}: reads
    // run on several threads at once, so nothing here allocates per call or
    // shares a segment between threads.

    int childCount(long generation, long address) {
        return (int) check(cross(handle -> calls.childCount(handle, generation, address)));
    }

    /** The five tree links. */
    enum Link { FIRST_CHILD, LAST_CHILD, NEXT_SIBLING, PRIOR_SIBLING, PARENT }

    /** One link through this door; {@link Galley#INVALID_NODE} when it does not exist. */
    long link(Link which, long generation, long address) {
        return check(cross(handle -> switch (which) {
            case FIRST_CHILD -> calls.firstChild(handle, generation, address);
            case LAST_CHILD -> calls.lastChild(handle, generation, address);
            case NEXT_SIBLING -> calls.nextSibling(handle, generation, address);
            case PRIOR_SIBLING -> calls.priorSibling(handle, generation, address);
            case PARENT -> calls.parent(handle, generation, address);
        }));
    }

    byte[] text(long generation, long address) {
        Scratch scratch = Scratch.local();
        check(cross(handle -> calls.text(handle, generation, address, scratch.first, scratch.second)));
        return copyBytes(scratch);
    }

    byte[] symbolNameBytes(long generation, long address) {
        Scratch scratch = Scratch.local();
        check(cross(handle -> calls.symbolName(handle, generation, address, scratch.first, scratch.second)));
        return copyBytes(scratch);
    }

    long[] span(long generation, long address) {
        Scratch scratch = Scratch.local();
        check(cross(handle -> calls.span(handle, generation, address, scratch.first, scratch.second)));
        return new long[]{scratch.firstLong(), scratch.secondLong()};
    }

    int[] lineColumn(long generation, long address) {
        Scratch scratch = Scratch.local();
        check(cross(handle -> calls.lineColumn(handle, generation, address, scratch.first, scratch.second)));
        return new int[]{scratch.firstInt(), scratch.secondInt()};
    }

    Integer variableIndex(long generation, long address) {
        long index = check(cross(handle -> calls.variableIndex(handle, generation, address)));
        return index == Galley.NO_VARIABLE ? null : (int) index;
    }

    // -- walking --

    /**
     * One step of a walk over the host-owned cursor: 1 yields a node, 0
     * ends the walk (and keeps ending it while the cursor's tree is live),
     * negative is a failure
     * (stale tree, session in use, invalid cursor bytes).
     */
    long walkStep(MemorySegment cursor) {
        return cross(handle -> calls.walkNext(handle, cursor));
    }

    // -- tree edits --

    // The edits with a second node pass its own generation beside the first:
    // the core refuses a pair from two parses.

    void appendChildren(long generation, long parent, long chainGeneration, long chain) {
        check(cross(handle -> calls.appendChildren(handle, generation, parent, chainGeneration, chain)));
    }

    void insertBefore(long generation, long target, long chainGeneration, long chain) {
        check(cross(handle -> calls.insertBefore(handle, generation, target, chainGeneration, chain)));
    }

    void insertAfter(long generation, long target, long chainGeneration, long chain) {
        check(cross(handle -> calls.insertAfter(handle, generation, target, chainGeneration, chain)));
    }

    /** A native edit that detaches a chain: runs with an out-head and returns the head, {@link Galley#INVALID_NODE} when empty. */
    private interface HeadCall {
        long run(MemorySegment handle, MemorySegment outHead);
    }

    private long detachedHead(HeadCall call) {
        Scratch scratch = Scratch.local();
        scratch.first.set(ValueLayout.JAVA_LONG, 0, Galley.INVALID_NODE);
        check(cross(handle -> call.run(handle, scratch.first)));
        return scratch.firstLong();
    }

    long removeSiblings(long generation, long address, int count) {
        return detachedHead((handle, outHead) -> calls.removeSiblings(handle, generation, address, count, outHead));
    }

    long removeSelf(long generation, long address) {
        return detachedHead((handle, outHead) -> calls.removeSelf(handle, generation, address, outHead));
    }

    long cleanChildren(long generation, long address) {
        return detachedHead((handle, outHead) -> calls.cleanChildren(handle, generation, address, outHead));
    }

    void insertChildrenAt(long generation, long parent, int index, long chainGeneration, long chain) {
        check(cross(handle -> calls.insertChildrenAt(handle, generation, parent, index, chainGeneration, chain)));
    }

    long removeChildrenAt(long generation, long parent, int index, int count) {
        return detachedHead((handle, outHead) -> calls.removeChildrenAt(handle, generation, parent, index, count, outHead));
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
