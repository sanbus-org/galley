package org.sanbus.galley;

import java.lang.foreign.Arena;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.ValueLayout;
import org.sanbus.galley.internal.GalleyLibrary;

/**
 * The parse-time door over one parse's node storage. One per parse, so
 * every hook of that parse hands out nodes on the same door and two nodes
 * share a door exactly when they belong to the same parse. Reads and edits
 * cross the {@code galley_hook_*} twins on the native door, which stays
 * valid for the whole parse; the session's parse generation, stamped at
 * creation, shows when that parse has ended.
 */
final class HookDoor extends NodeDoor {
    private static final long INVALID_NODE = 0xFFFFFFFFFFFFFFFFL;

    private final GalleyLibrary lib;
    private final MemorySegment door;
    private final Session session;
    /** The parse generation this door belongs to, stamped at creation. */
    private final long generation;

    HookDoor(GalleyLibrary lib, MemorySegment door, Session session) {
        this.lib = lib;
        this.door = door;
        this.session = session;
        this.generation = session.parseGeneration();
    }

    /**
     * The host failure for a negative native status raised by a hook-door
     * or per-hook crossing. One place for the conversion, so no crossing
     * spells it out itself.
     */
    static GalleyException failure(GalleyLibrary lib, long status) {
        String message = lib.galley_status_string(status);
        return new GalleyException(message != null ? message : "procedure error", (int) status);
    }

    @Override
    void requireLive(Node node) {
        if (session.isClosed()) throw new GalleyClosedException("node's session");
        if (generation != session.parseGeneration()) throw GalleyClosedException.invalidated("node");
    }

    /** Wraps an address on this door; invalid becomes null. */
    Node node(long address) {
        return address == INVALID_NODE ? null : new Node(this, address, generation);
    }

    @Override
    boolean nodeValid(Node node) {
        return lib.galley_hook_node_is_valid(door, address(node)) != 0;
    }

    @Override
    int childCount(Node node) {
        return lib.galley_hook_node_child_count(door, address(node));
    }

    @Override
    Node firstChild(Node node) {
        return node(lib.galley_hook_node_first_child(door, address(node)));
    }

    @Override
    Node lastChild(Node node) {
        return node(lib.galley_hook_node_last_child(door, address(node)));
    }

    @Override
    Node nextSibling(Node node) {
        return node(lib.galley_hook_node_next_sibling(door, address(node)));
    }

    @Override
    Node priorSibling(Node node) {
        return node(lib.galley_hook_node_prior_sibling(door, address(node)));
    }

    @Override
    Node parent(Node node) {
        return node(lib.galley_hook_node_parent(door, address(node)));
    }

    @Override
    byte[] text(Node node) {
        long address = address(node);
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLength = arena.allocate(ValueLayout.JAVA_LONG);
            long status = lib.galley_hook_node_text(door, address, outData, outLength);
            return outBytes(status, outData, outLength);
        }
    }

    @Override
    byte[] symbolNameBytes(Node node) {
        long address = address(node);
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLength = arena.allocate(ValueLayout.JAVA_LONG);
            long status = lib.galley_hook_node_symbol_name(door, address, outData, outLength);
            return outBytes(status, outData, outLength);
        }
    }

    @Override
    long[] span(Node node) {
        long address = address(node);
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outStart = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outLength = arena.allocate(ValueLayout.JAVA_LONG);
            long status = lib.galley_hook_node_span(door, address, outStart, outLength);
            if (status < 0) return null;
            return new long[]{outStart.get(ValueLayout.JAVA_LONG, 0), outLength.get(ValueLayout.JAVA_LONG, 0)};
        }
    }

    @Override
    int[] lineColumn(Node node) {
        long address = address(node);
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outLine = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outColumn = arena.allocate(ValueLayout.JAVA_INT);
            long status = lib.galley_hook_node_line_column(door, address, outLine, outColumn);
            if (status < 0) return null;
            return new int[]{outLine.get(ValueLayout.JAVA_INT, 0), outColumn.get(ValueLayout.JAVA_INT, 0)};
        }
    }

    @Override
    Integer variableIndex(Node node) {
        long index = lib.galley_hook_node_variable_index(door, address(node));
        if (index == -1) return null;
        if (index < 0) throw failure(lib, index);
        return (int) index;
    }

    @Override
    Node cleanChildren(Node node) {
        long address = address(node);
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outHead = arena.allocate(ValueLayout.JAVA_LONG);
            long status = lib.galley_hook_tree_clean_children(door, address, outHead);
            if (status < 0) throw failure(lib, status);
            return node(outHead.get(ValueLayout.JAVA_LONG, 0));
        }
    }

    @Override
    void appendChildren(Node parent, Node chain) {
        long status = lib.galley_hook_tree_append_children(door, address(parent), address(chain));
        if (status < 0) throw failure(lib, status);
    }
}
