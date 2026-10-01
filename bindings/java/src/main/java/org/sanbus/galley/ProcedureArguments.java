package org.sanbus.galley;

import java.lang.foreign.Arena;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.ValueLayout;
import java.nio.charset.StandardCharsets;
import org.sanbus.galley.internal.GalleyLibrary;

/**
 * Per-hook arguments passed to a procedure hook: the current node and its
 * redirect, the scanner position, drop and replace, and semantic errors.
 * Valid only while the hook runs — the dispatcher expires them when it
 * returns, so a reference kept past that throws instead of reading a frame
 * that is gone. The tree is not per hook: nodes this object yields belong
 * to the running parse's core generation, stay usable from later hooks of the
 * same parse and, when the parse publishes its tree, until the session
 * parses again. Drop/replace use the dedicated methods here, not Session's
 * tree editing.
 */
public final class ProcedureArguments {
    private static final long INVALID_NODE = 0xFFFFFFFFFFFFFFFFL;

    private final MemorySegment argsSegment;
    private final GalleyLibrary lib;
    private final Session session;
    /** The running parse's hook door for this dispatch, or null when its generation could not be read. */
    private final NodeDoor door;
    private boolean expired;

    ProcedureArguments(MemorySegment argsSegment, GalleyLibrary lib, Session session, NodeDoor door) {
        this.argsSegment = argsSegment;
        this.lib = lib;
        this.session = session;
        this.door = door;
    }

    /** Dispatcher hook: the native arguments no longer exist past this call. */
    void expire() { expired = true; }

    /**
     * The single gate for per-hook state: every accessor takes the native
     * arguments from here and nowhere else.
     */
    private MemorySegment live() {
        if (expired) throw GalleyClosedException.invalidated("procedure arguments");
        return argsSegment;
    }

    private NodeDoor requireDoor() {
        if (door == null) throw GalleyClosedException.invalidated("procedure arguments");
        return door;
    }

    /**
     * The node being reduced, or null.
     */
    public Node currentNode() {
        long address = lib.galley_procedure_current_node(live());
        if (address == INVALID_NODE) return null;
        return new Node(session, address, requireDoor().generation());
    }

    public void setCurrentNode(Node node) {
        MemorySegment args = live();
        lib.galley_procedure_set_current_node(args, node == null ? INVALID_NODE : session.address(node, requireDoor()));
    }

    public long dropSelf() {
        return succeeded(lib.galley_procedure_drop_self(live()));
    }

    public long dropChildren() {
        return succeeded(lib.galley_procedure_drop_children(live()));
    }

    public long dropIfEmpty() {
        return succeeded(lib.galley_procedure_drop_if_empty(live()));
    }

    public long replaceWithChildren() {
        return succeeded(lib.galley_procedure_replace_with_children(live()));
    }

    public int currentLine() { return lib.galley_procedure_context_line(live()); }

    public int currentColumn() { return lib.galley_procedure_context_column(live()); }

    /**
     * Records a semantic error on the current node and returns the running
     * total. Parsing continues; a syntax-clean parse with any semantic
     * error fails with {@link StatusCode#ERROR_SEMANTIC}.
     */
    public int reportSemanticError(String message) {
        MemorySegment args = live();
        byte[] bytes = message.getBytes(StandardCharsets.UTF_8);
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment seg = bytes.length == 0 ? MemorySegment.NULL : arena.allocateFrom(ValueLayout.JAVA_BYTE, bytes);
            return (int) succeeded(lib.galley_procedure_report_semantic_error(args, seg, bytes.length));
        }
    }

    // Convenience tree editing of the current node through the parse's door.

    public Node cleanChildren() {
        Node current = currentNode();
        return current == null ? null : current.cleanChildren();
    }

    public void appendChildren(Node chain) {
        Node current = currentNode();
        if (current == null) return;
        current.appendChildren(chain);
    }

    private long succeeded(long status) {
        if (status < 0) throw NodeDoor.hookFailure(lib, status);
        return status;
    }
}
