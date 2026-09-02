package org.sanbus.galley;

import java.lang.foreign.MemorySegment;
import org.sanbus.galley.internal.GalleyLibrary;

/**
 * Parse-time arguments passed to a procedure hook.
 * Mirrors Go's galley.ProcedureArgs and Rust's procedure::ProcedureArguments.
 *
 * Tree queries use {@link #getSession()} with the ordinary Session APIs;
 * drop/replace use the dedicated methods on this object, not Session's
 * tree editing.
 */
public final class ProcedureArguments {
    private final MemorySegment argsSegment;
    private final GalleyLibrary lib;

    public ProcedureArguments(MemorySegment argsSegment, GalleyLibrary lib) {
        this.argsSegment = argsSegment;
        this.lib = lib;
    }

    public MemorySegment getSegment() { return argsSegment; }

    /**
     * The session currently parsing, or null.
     */
    public Session getSession() {
        MemorySegment sessAddr = lib.galley_procedure_session(argsSegment);
        if (sessAddr == null || sessAddr.equals(MemorySegment.NULL)) return null;
        return Session.fromNativeSegment(sessAddr, lib);
    }

    /**
     * The node being reduced, or null.
     */
    public Node currentNode() {
        long addr = lib.galley_procedure_current_node(argsSegment);
        if (addr == 0xFFFFFFFFFFFFFFFFL) return null;
        Session sess = getSession();
        if (sess == null) return null;
        return new Node(sess, addr);
    }

    public void setCurrentNode(Node node) {
        long addr = node != null ? node.getAddress() : 0xFFFFFFFFFFFFFFFFL;
        lib.galley_procedure_set_current_node(argsSegment, addr);
    }

    public long dropSelf() {
        long st = lib.galley_procedure_drop_self(argsSegment);
        if (st < 0) throw new GalleyException(lib.galley_status_string(st) != null ? lib.galley_status_string(st) : "procedure error", (int) st);
        return st;
    }

    public long dropChildren() {
        long st = lib.galley_procedure_drop_children(argsSegment);
        if (st < 0) throw new GalleyException(lib.galley_status_string(st) != null ? lib.galley_status_string(st) : "procedure error", (int) st);
        return st;
    }

    public long dropIfEmpty() {
        long st = lib.galley_procedure_drop_if_empty(argsSegment);
        if (st < 0) throw new GalleyException(lib.galley_status_string(st) != null ? lib.galley_status_string(st) : "procedure error", (int) st);
        return st;
    }

    public long replaceWithChildren() {
        long st = lib.galley_procedure_replace_with_children(argsSegment);
        if (st < 0) throw new GalleyException(lib.galley_status_string(st) != null ? lib.galley_status_string(st) : "procedure error", (int) st);
        return st;
    }

    public int currentLine() { return lib.galley_procedure_context_line(argsSegment); }
    public int currentColumn() { return lib.galley_procedure_context_column(argsSegment); }

    // Convenience delegations for tree editing via session
    public Node cleanChildren() {
        Node n = currentNode();
        if (n == null) return null;
        Session s = getSession();
        if (s == null) return null;
        return s.cleanChildren(n);
    }

    public void appendChildren(Node chain) {
        Node n = currentNode();
        Session s = getSession();
        if (n == null || s == null) return;
        s.appendChildren(n, chain);
    }
}
