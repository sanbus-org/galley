package org.sanbus.galley;

import java.lang.foreign.Arena;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.ValueLayout;
import java.nio.charset.StandardCharsets;
import org.sanbus.galley.internal.GalleyLibrary;

/**
 * Per-hook arguments passed to a procedure hook: the current node and its
 * redirect, the scanner position, drop and replace, and semantic errors.
 * Valid only while the hook runs: the core refuses every call made with the
 * arguments of a hook that has returned ({@link StatusCode#ERROR_STALE_HOOK}),
 * and this object keeps no expiry state of its own. The tree is not per
 * hook: nodes this object yields belong to the running parse's core
 * generation, stay usable from later hooks of the same parse and, when the
 * parse publishes its tree, until the session parses again. Drop/replace use
 * the dedicated methods here, not Session's tree editing.
 */
public final class ProcedureArguments {

    private final long hook;
    private final GalleyLibrary lib;
    private final Session session;
    /** The running parse's core generation: the stamp of the nodes this hook produces, never compared. */
    private final long generation;

    ProcedureArguments(long hook, GalleyLibrary lib, Session session, long generation) {
        this.hook = hook;
        this.lib = lib;
        this.session = session;
        this.generation = generation;
    }

    /** The session handle every call crosses with; a closed session is refused here. */
    private MemorySegment handle() {
        if (session.isClosed()) throw new GalleyClosedException("session");
        return session.handle();
    }

    /**
     * The node being reduced, or null.
     */
    public Node currentNode() {
        long address = succeeded(lib.galley_procedure_current_node(handle(), hook));
        if (address == Galley.INVALID_NODE) return null;
        return new Node(session, address, generation);
    }

    public void setCurrentNode(Node node) {
        MemorySegment handle = handle();
        if (node == null) {
            succeeded(lib.galley_procedure_set_current_node(handle, hook, 0, Galley.INVALID_NODE));
            return;
        }
        long address = session.address(node);
        succeeded(lib.galley_procedure_set_current_node(handle, hook, node.generation(), address));
    }

    public long dropSelf() {
        return succeeded(lib.galley_procedure_drop_self(handle(), hook));
    }

    public long dropChildren() {
        return succeeded(lib.galley_procedure_drop_children(handle(), hook));
    }

    public long dropIfEmpty() {
        return succeeded(lib.galley_procedure_drop_if_empty(handle(), hook));
    }

    public long replaceWithChildren() {
        return succeeded(lib.galley_procedure_replace_with_children(handle(), hook));
    }

    public int currentLine() { return (int) succeeded(lib.galley_procedure_context_line(handle(), hook)); }

    public int currentColumn() { return (int) succeeded(lib.galley_procedure_context_column(handle(), hook)); }

    /**
     * Records a semantic error on the current node and returns the running
     * total. Parsing continues; a syntax-clean parse with any semantic
     * error fails with {@link StatusCode#ERROR_SEMANTIC}.
     */
    public int reportSemanticError(String message) {
        MemorySegment handle = handle();
        byte[] bytes = message.getBytes(StandardCharsets.UTF_8);
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment seg = bytes.length == 0 ? MemorySegment.NULL : arena.allocateFrom(ValueLayout.JAVA_BYTE, bytes);
            return (int) succeeded(lib.galley_procedure_report_semantic_error(handle, hook, seg, bytes.length));
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
        if (status < 0) throw Session.statusFailure(lib, status, null);
        return status;
    }
}
