package org.sanbus.galley;

import java.io.File;
import java.nio.file.Path;
import java.lang.foreign.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.function.Consumer;

import org.sanbus.galley.internal.GalleyLibrary;

/**
 * Parsing session bound to this library's parser over bindings/c/galley.h.
 * Not thread-safe. Panama FFI (Java 22+, no JNA).
 *
 * Owns its hook table: it starts as a copy of the parser's defaults and
 * every change is applied to the library at once, so the hooks a parse
 * runs with are fixed for that parse. Changing hooks from a hook, or from
 * another thread during a parse, throws a {@link GalleyException} with
 * {@code ERROR_SESSION_IN_USE}.
 */
public final class Session implements AutoCloseable {

    private MemorySegment handle;
    private final GalleyLibrary lib;
    private boolean closed = false;
    private final Parser parser;
    /** The session door: post-parse access, refused by the core while a parse runs. */
    private final NodeDoor sessionDoor;
    /** Handle the library passes back with this session's hooks; routes the parser's one dispatch stub here. */
    private long handleId;
    /** This session's hooks by name: replaced whole, never mutated. */
    private volatile Map<String, Consumer<ProcedureArguments>> hooks = Map.of();
    /** The same hooks by the library's hook index, the dispatch lookup. */
    private volatile Consumer<ProcedureArguments>[] hooksByIndex;
    /**
     * The running parse's hook door, learned from its first dispatch (the
     * native door and the parse's core generation are constant for the
     * parse) and dropped by the parse's finish gate; null between parses.
     */
    private volatile NodeDoor parseDoor;
    /**
     * The thread running the hook in progress, or null between hooks. Only
     * that thread may cross {@link #parseDoor}; every other thread crosses
     * the session door.
     */
    private volatile Thread dispatchThread;

    public Session(Parser parser) {
        this(parser, SessionOptions.defaults());
    }

    public Session(Parser parser, SessionOptions options) {
        if (parser == null) throw new IllegalArgumentException("parser is null");
        if (options == null) options = SessionOptions.defaults();
        this.parser = parser;
        this.lib = parser.library();
        this.sessionDoor = NodeDoor.ofSession(lib, this);

        MemorySegment h;
        boolean hasNonDefault = options.getMaxErrors() != 10 ||
                options.getRecoveryWindow() != 500 ||
                options.isStackOverflowRecovery() ||
                options.getSyntaxErrorStackDepth() != 0 ||
                options.getVerbosity() != 0 ||
                options.getAstPreallocationRatio() != -1.0 ||
                options.getAstPreallocationCap() != 0;

        if (hasNonDefault) {
            try (Arena arena = Arena.ofConfined()) {
                MemorySegment opts = arena.allocate(GalleyLibrary.GALLEY_COPTIONS_SIZE);
                opts.set(ValueLayout.JAVA_INT, GalleyLibrary.OFF_MAX_ERRORS, options.getMaxErrors());
                opts.set(ValueLayout.JAVA_INT, GalleyLibrary.OFF_RECOVERY_WINDOW, options.getRecoveryWindow());
                opts.set(ValueLayout.JAVA_INT, GalleyLibrary.OFF_STACK_OVERFLOW_RECOVERY, options.isStackOverflowRecovery() ? 1 : 0);
                opts.set(ValueLayout.JAVA_INT, GalleyLibrary.OFF_SYNTAX_ERROR_STACK_DEPTH, options.getSyntaxErrorStackDepth());
                opts.set(ValueLayout.JAVA_INT, GalleyLibrary.OFF_VERBOSITY, options.getVerbosity());
                opts.set(ValueLayout.JAVA_DOUBLE, GalleyLibrary.OFF_AST_PREALLOCATION_RATIO, options.getAstPreallocationRatio());
                opts.set(ValueLayout.JAVA_LONG, GalleyLibrary.OFF_AST_PREALLOCATION_CAP, options.getAstPreallocationCap());
                h = lib.galley_session_create_ex(opts);
            }
        } else {
            h = lib.galley_session_create();
        }
        if (h == null || h.equals(MemorySegment.NULL) || h.address() == 0) {
            throw new GalleyException("out of memory", StatusCode.ERROR_OUT_OF_MEMORY);
        }
        this.handle = h;
        this.handleId = parser.register(this);
        try {
            commitHooks(parser.defaultHooks());
        } catch (RuntimeException e) {
            close();
            throw e;
        }

        for (Map.Entry<String, byte[]> e : options.getMessageOverrides().entrySet()) {
            setMessageOverride(e.getKey(), e.getValue());
        }
    }

    /** The native session handle; the session door crosses it. */
    MemorySegment handle() { return handle; }

    private void requireOpen() {
        if (closed || handle == null || handle.equals(MemorySegment.NULL)) throw new GalleyClosedException("session");
    }

    /**
     * The door a call crosses, chosen now: from inside a hook dispatch of
     * this session's running parse, on the thread running that hook, the
     * parse's hook door; everywhere else the session door, which the core
     * refuses while a parse runs. The only place the choice is made.
     */
    private NodeDoor door() {
        requireOpen();
        if (dispatchThread == Thread.currentThread()) {
            NodeDoor hook = parseDoor;
            if (hook != null) return hook;
        }
        return sessionDoor;
    }

    /**
     * The single gate for a node argument crossing {@code door}: the node
     * must belong to this session, and it carries the generation every call
     * of this operation hands the core. On the session door the core refuses
     * a generation that is not the published tree's, so the session keeps no
     * cached copy of it and cannot disagree with the core. On the hook door
     * the generation is checked here, because the hook twins take none: the
     * door serves one parse, so a node of another generation would alias
     * whichever node holds that index in that parse. Either way a bare
     * address would alias storage unchecked, which is why only a {@link Node}
     * reaches this gate.
     *
     * @throws IllegalArgumentException if {@code node} belongs to another session
     * @throws StaleTreeException if its generation is not the door's
     */
    long address(Node node, NodeDoor door) {
        Session home = node.session();
        if (home.isClosed()) throw new GalleyClosedException("node's session");
        if (home != this) {
            throw new IllegalArgumentException("node belongs to a different session than this operation");
        }
        if (door.isHook() && node.generation() != door.generation()) {
            throw new StaleTreeException("node");
        }
        return node.getAddress();
    }

    /**
     * What one node operation crosses with, fixed by {@link #cross}: the
     * door, the one generation every node of the operation carries (the
     * first node's own, which on the hook door {@link #address} has just
     * proved is the running parse's), and that node's address.
     */
    private record Crossing(NodeDoor door, long generation, long address) {}

    /**
     * The one gate of a node operation: closed checks and door choice
     * ({@link #door(Node)}), then the node's admission to that door
     * ({@link #address}). Nothing crosses without coming through here.
     */
    private Crossing cross(Node node) {
        NodeDoor door = door(node);
        return new Crossing(door, node.generation(), address(node, door));
    }

    /**
     * The address of a second node of the same operation. A call hands the
     * core one generation, so the second node must carry it: an edit mixing
     * two trees is refused here instead of acting on a chain from another
     * parse.
     *
     * @throws StaleTreeException if {@code chain} does not carry the crossing's generation
     */
    private long second(Crossing crossing, Node chain) {
        long address = address(chain, crossing.door());
        if (chain.generation() != crossing.generation()) throw new StaleTreeException("node");
        return address;
    }

    /** Wraps an address read through a crossing; invalid becomes null. */
    private Node node(long address, long generation) {
        return address == Galley.INVALID_NODE ? null : new Node(this, address, generation);
    }

    /**
     * {@link #door()} for a call that takes {@code node}. A null handle is a
     * missing argument, not a refusal about the tree's lifetime, so it fails
     * as one: an empty answer here would be indistinguishable from "this node
     * really has no children". A node whose own session is closed reports that
     * before its door is chosen.
     *
     * @throws NullPointerException if {@code node} is null
     */
    private NodeDoor door(Node node) {
        Objects.requireNonNull(node, "node");
        if (node.session().isClosed()) throw new GalleyClosedException("node's session");
        return door();
    }

    /**
     * The host failure for a negative status the core reported on the session
     * door, with the session's diagnostic snapshot when one exists.
     */
    GalleyException errorFromStatus(long status) {
        Diagnostic diagnostic = null;
        try {
            if (handle != null && !handle.equals(MemorySegment.NULL) && lib.galley_has_diagnostic(handle) != 0) {
                diagnostic = buildDiagnosticSingular();
            }
        } catch (Exception ignored) {}
        return statusFailure(lib, status, diagnostic);
    }

    /**
     * The one mapper from a negative core status to the host failure, for
     * every door and every crossing. A stale tree is one failure however it
     * arrived — the core's own stale status on the session door, a hook
     * crossing, or a walk step — so it is always the {@link StaleTreeException}
     * subclass, and {@code catch (GalleyException)} still catches it.
     * {@code diagnostic} may be null.
     */
    static GalleyException statusFailure(GalleyLibrary lib, long status, Diagnostic diagnostic) {
        if (status == StatusCode.ERROR_STALE_TREE.getCode()) {
            return new StaleTreeException("tree");
        }
        String message = lib.galley_status_string(status);
        if (message == null) message = "unknown galley error";
        if (diagnostic != null && diagnostic.getMessage() != null && !diagnostic.getMessage().isEmpty()) {
            message = diagnostic.getMessage();
        }
        return new GalleyException(message, (int) status, diagnostic);
    }

    private void checkStatus(long status) {
        if (status < 0) throw errorFromStatus(status);
    }

    /**
     * Single gate ending every parse leg: drops the parse's door, which dies
     * with the parse, then throws or returns the parsed byte count. The
     * handles of earlier parses need no bookkeeping here — the core refuses
     * their generation at their next read. A parse the core refused with
     * {@code ERROR_SESSION_IN_USE} started nothing, so it leaves the running
     * parse's door alone. Parsing itself never throws merely because a
     * walker is open.
     */
    private int completeParse(long status) {
        if (status != StatusCode.ERROR_SESSION_IN_USE.getCode()) {
            parseDoor = null;
        }
        if (status < 0) throw errorFromStatus(status);
        return (int) status;
    }

    /** One native parse call. */
    private interface NativeParse {
        long run();
    }

    /**
     * Single gate for every parse leg: runs the native call, then ends the
     * parse. The hooks were fixed by the last commit, so nothing is
     * synchronized here.
     */
    private int runParse(NativeParse nativeParse) {
        long status;
        try {
            status = nativeParse.run();
        } catch (Throwable thrown) {
            parseDoor = null;
            throw thrown;
        }
        return completeParse(status);
    }

    public boolean isClosed() { return closed || handle == null || handle.equals(MemorySegment.NULL); }

    @Override
    public void close() {
        if (handle != null && !handle.equals(MemorySegment.NULL)) {
            try { lib.galley_session_destroy(handle); } catch (Exception ignored) {}
            handle = MemorySegment.NULL;
            parser.unregister(handleId);
        }
        closed = true;
        parseDoor = null;
    }

    // -- hooks --

    /** Installs a hook on this session only. Takes effect from the next parse. */
    public void installProcedure(String name, Consumer<ProcedureArguments> hook) {
        HookNames.require(name, hook);
        if (!HookNames.accepts(name)) return;
        Map<String, Consumer<ProcedureArguments>> next = new HashMap<>(hooks);
        next.put(name, hook);
        commitHooks(Map.copyOf(next));
    }

    public void installProcedure(String name, Runnable hook) {
        HookNames.require(name, hook);
        installProcedure(name, (Consumer<ProcedureArguments>) args -> hook.run());
    }

    /**
     * Installs every hook-shaped entry ({@code reduction},
     * {@code reduction_*}, {@code hook_*}) whose value is a
     * {@code Consumer<ProcedureArguments>} or a {@code Runnable}, in one
     * step. Near-miss names warn and anything else is silently ignored.
     * Returns the number installed.
     */
    public int installProcedures(Map<String, ?> source) {
        if (source == null) return 0;
        Map<String, Consumer<ProcedureArguments>> next = new HashMap<>(hooks);
        int count = 0;
        for (Map.Entry<String, ?> entry : source.entrySet()) {
            if (!HookNames.accepts(entry.getKey())) continue;
            Consumer<ProcedureArguments> hook = HookNames.toHook(entry.getValue());
            if (hook == null) continue;
            next.put(entry.getKey(), hook);
            count++;
        }
        if (count > 0) commitHooks(Map.copyOf(next));
        return count;
    }

    public Map<String, Consumer<ProcedureArguments>> listProcedures() {
        return hooks;
    }

    public Consumer<ProcedureArguments> lookupProcedure(String name) {
        if (name == null) return null;
        return hooks.get(name);
    }

    public void clearProcedures() {
        commitHooks(Map.of());
    }

    /**
     * Single gate for every hook change: hands the library the enabled set
     * first, so a refusal (a parse in flight) leaves the table and the
     * library exactly as they were, then publishes the table and its
     * by-index view.
     */
    private void commitHooks(Map<String, Consumer<ProcedureArguments>> table) {
        requireOpen();
        int count = parser.hookCount();
        @SuppressWarnings("unchecked")
        Consumer<ProcedureArguments>[] byIndex = new Consumer[count];
        for (Map.Entry<String, Consumer<ProcedureArguments>> entry : table.entrySet()) {
            int index = parser.hookIndex(entry.getKey());
            if (index >= 0) byIndex[index] = entry.getValue();
        }
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment enabled = arena.allocate(Math.max(count, 1));
            for (int index = 0; index < count; index++) {
                enabled.set(ValueLayout.JAVA_BYTE, index, (byte) (byIndex[index] != null ? 1 : 0));
            }
            checkStatus(lib.galley_session_set_hooks(handle, parser.dispatchStub(), MemorySegment.ofAddress(handleId), enabled, count));
        }
        hooksByIndex = byIndex;
        hooks = table;
    }

    /**
     * Runs hook {@code index} of the current parse, on the parsing thread.
     * Hook throwables are logged and swallowed so a throwing hook never
     * aborts the parse.
     */
    void dispatchHook(int index, MemorySegment argumentsPointer) {
        Consumer<ProcedureArguments> hook = hooksByIndex[index];
        if (hook == null) return;
        // The parse's native door and core generation are constant for the
        // parse: read them on its first dispatch, drop them in the finish
        // gate. Only the thread running the hook is recorded per dispatch,
        // which is what lets a call choose its door when it is made.
        NodeDoor hookDoor = parseDoor;
        if (hookDoor == null) {
            MemorySegment door = lib.galley_procedure_door(argumentsPointer);
            try (Arena arena = Arena.ofConfined()) {
                MemorySegment out = arena.allocate(ValueLayout.JAVA_LONG);
                if (lib.galley_hook_generation(door, out) >= 0) {
                    hookDoor = NodeDoor.ofHook(lib, this, door, out.get(ValueLayout.JAVA_LONG, 0));
                    parseDoor = hookDoor;
                }
            }
        }
        dispatchThread = hookDoor == null ? null : Thread.currentThread();
        ProcedureArguments arguments = new ProcedureArguments(argumentsPointer, lib, this, hookDoor);
        try {
            hook.accept(arguments);
        } catch (Throwable t) {
            t.printStackTrace(System.err);
        } finally {
            // The native arguments die when this hook call returns; expire
            // the Java reference with them. The tree outlives the hook: its
            // nodes carry the parse's generation, not the hook door.
            arguments.expire();
            dispatchThread = null;
        }
    }

    // -- parsing --

    /**
     * Parses {@code input}, returning bytes parsed. Null is rejected
     * loudly. The input crosses by length-prefixed pointer, never a C
     * string; audit note: the native runtime currently stops at interior
     * NUL bytes, so NUL-as-data holds only up to the binding boundary.
     */
    public int parse(byte[] input) {
        requireOpen();
        if (input == null) throw new IllegalArgumentException("input is null");
        if (input.length == 0) {
            return runParse(() -> lib.galley_parse(handle, MemorySegment.NULL, 0));
        }
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment dataSeg = arena.allocateFrom(ValueLayout.JAVA_BYTE, input);
            long len = input.length;
            return runParse(() -> lib.galley_parse(handle, dataSeg, len));
        }
    }

    public int parse(ByteBuffer buffer) {
        requireOpen();
        if (buffer == null) throw new IllegalArgumentException("buffer is null");
        int len = buffer.remaining();
        if (len == 0) {
            return runParse(() -> lib.galley_parse(handle, MemorySegment.NULL, 0));
        }
        if (buffer.isDirect()) {
            MemorySegment dataSeg = MemorySegment.ofBuffer(buffer);
            return runParse(() -> lib.galley_parse(handle, dataSeg, len));
        } else {
            // Heap ByteBuffer: copy to native via arena
            byte[] tmp;
            if (buffer.hasArray()) {
                // Avoid modifying buffer position; copy slice
                int pos = buffer.position();
                int lim = buffer.limit();
                tmp = new byte[len];
                if (buffer.hasArray()) {
                    System.arraycopy(buffer.array(), buffer.arrayOffset() + pos, tmp, 0, len);
                } else {
                    ByteBuffer dup = buffer.duplicate();
                    dup.get(tmp);
                }
            } else {
                tmp = new byte[len];
                ByteBuffer dup = buffer.duplicate();
                dup.get(tmp);
            }
            try (Arena arena = Arena.ofConfined()) {
                MemorySegment dataSeg = arena.allocateFrom(ValueLayout.JAVA_BYTE, tmp);
                return runParse(() -> lib.galley_parse(handle, dataSeg, len));
            }
        }
    }

    public int parse(String input) {
        requireOpen();
        if (input == null) throw new IllegalArgumentException("input is null");
        byte[] bytes = input.getBytes(StandardCharsets.UTF_8);
        return parse(bytes);
    }

    public int parseSentinel(String input) {
        return parse(input);
    }

    public int parseSentinel(byte[] input) {
        return parse(input);
    }

    public int parseSentinel(ByteBuffer buffer) {
        return parse(buffer);
    }

    public int parseFile(String path) {
        requireOpen();
        if (path == null) throw new IllegalArgumentException("path is null");
        if (path.indexOf('\0') >= 0) throw new IllegalArgumentException("path contains NUL");
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment cPath = arena.allocateFrom(path, StandardCharsets.UTF_8);
            return runParse(() -> lib.galley_parse_file(handle, cPath));
        }
    }

    public int parseFile(File file) {
        requireOpen();
        if (file == null) throw new IllegalArgumentException("file is null");
        return parseFile(file.getAbsolutePath());
    }

    public int parseFile(Path path) {
        requireOpen();
        if (path == null) throw new IllegalArgumentException("path is null");
        return parseFile(path.toAbsolutePath().toString());
    }

    // -- arena --

    /**
     * Number of AST nodes in the published tree.
     *
     * @throws StaleTreeException when nothing is published
     */
    public long nodeCount() {
        requireOpen();
        return nodeCount(published()[1]);
    }

    /**
     * The count of the tree {@code generation} names. The core refuses a
     * generation it does not hold, 0 (nothing published) included, so
     * nothing published is never a zero.
     */
    long nodeCount(long generation) {
        long count = lib.galley_node_count(handle, generation);
        checkStatus(count);
        return count;
    }

    /**
     * The published tree's generation, read from the core in the same call
     * that reads its root. 0 when nothing is published.
     */
    private long[] published() {
        Scratch scratch = Scratch.local();
        checkStatus(lib.galley_root_node(handle, scratch.first, scratch.second));
        return new long[]{scratch.firstLong(), scratch.secondLong()};
    }

    public void reserveNodes(long capacity) {
        requireOpen();
        long st = lib.galley_reserve_nodes(handle, capacity);
        checkStatus(st);
    }

    public long nodeCapacity() {
        requireOpen();
        return lib.galley_node_capacity(handle);
    }

    // -- navigation --

    /**
     * Root of the published tree, or null when nothing is published — the
     * one "is there a tree here" probe. The node carries the core generation
     * that tree has, which every later read hands back to the core.
     *
     * @throws GalleyException with {@code ERROR_SESSION_IN_USE} while a parse runs
     */
    public Node rootNode() {
        requireOpen();
        long[] tree = published();
        if (tree[0] == Galley.INVALID_NODE) return null;
        return new Node(this, tree[0], tree[1]);
    }

    public int childCount(Node node) {
        Crossing crossing = cross(node);
        return crossing.door().childCount(crossing.generation(), crossing.address());
    }

    public List<Node> children(Node node) {
        return children(cross(node));
    }

    /**
     * The one children iteration: count-bounded, first to last, every step
     * crossing the same door. A child count that moves mid-iteration throws
     * instead of yielding a torn walk.
     */
    private List<Node> children(Crossing crossing) {
        NodeDoor door = crossing.door();
        long generation = crossing.generation();
        int count = door.childCount(generation, crossing.address());
        List<Node> out = new ArrayList<>(count);
        long child = door.link(NodeDoor.Link.FIRST_CHILD, generation, crossing.address());
        for (int i = 0; i < count; i++) {
            if (child == Galley.INVALID_NODE) throw new IllegalStateException("child count changed during iteration");
            out.add(node(child, generation));
            child = door.link(NodeDoor.Link.NEXT_SIBLING, generation, child);
        }
        return out;
    }

    /** The one link reader behind the five link methods. */
    private Node link(Node node, NodeDoor.Link which) {
        Crossing crossing = cross(node);
        return node(crossing.door().link(which, crossing.generation(), crossing.address()), crossing.generation());
    }

    public Node firstChild(Node node) { return link(node, NodeDoor.Link.FIRST_CHILD); }

    public Node lastChild(Node node) { return link(node, NodeDoor.Link.LAST_CHILD); }

    public Node nextSibling(Node node) { return link(node, NodeDoor.Link.NEXT_SIBLING); }

    public Node priorSibling(Node node) { return link(node, NodeDoor.Link.PRIOR_SIBLING); }

    public Node parent(Node node) { return link(node, NodeDoor.Link.PARENT); }

    /**
     * Flat bulk read of the published tree in a single call: one entry per
     * node address. Missing links read as {@link Galley#INVALID_NODE}, missing
     * variables as -1, and spans index
     * {@link #lastInput()}. Walk {@code parent}/{@code firstChild}/
     * {@code next} directly instead of one call per node;
     * {@link TreeSnapshot#node(long)} is the one conversion from a stored
     * address back to a node.
     *
     * Every leg carries one generation, so a parse that runs in between
     * raises instead of returning columns that mix two trees.
     *
     * @throws StaleTreeException when nothing is published
     */
    public TreeSnapshot snapshot() {
        requireOpen();
        long generation = published()[1];
        long count = nodeCount(generation);
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment parent = arena.allocate(ValueLayout.JAVA_LONG, count);
            MemorySegment firstChild = arena.allocate(ValueLayout.JAVA_LONG, count);
            MemorySegment next = arena.allocate(ValueLayout.JAVA_LONG, count);
            MemorySegment childCount = arena.allocate(ValueLayout.JAVA_INT, count);
            MemorySegment variable = arena.allocate(ValueLayout.JAVA_LONG, count);
            MemorySegment spanStart = arena.allocate(ValueLayout.JAVA_LONG, count);
            MemorySegment spanLen = arena.allocate(ValueLayout.JAVA_LONG, count);
            MemorySegment semantic = arena.allocate(ValueLayout.JAVA_INT, count);
            long total = lib.galley_tree_snapshot(handle, generation, parent, firstChild, next,
                    childCount, variable, spanStart, spanLen, semantic, count);
            if (total < 0) throw errorFromStatus(total);
            if (total != count) throw new IllegalStateException("node count changed during snapshot");
            long[] parentArray = parent.toArray(ValueLayout.JAVA_LONG);
            long[] firstChildArray = firstChild.toArray(ValueLayout.JAVA_LONG);
            long[] nextArray = next.toArray(ValueLayout.JAVA_LONG);
            int[] childCountArray = childCount.toArray(ValueLayout.JAVA_INT);
            long[] variableArray = variable.toArray(ValueLayout.JAVA_LONG);
            // The core's non-negative "no variable" becomes this API's -1.
            for (int i = 0; i < variableArray.length; i++) {
                if (variableArray[i] == Galley.NO_VARIABLE) variableArray[i] = -1;
            }
            long[] spanStartArray = spanStart.toArray(ValueLayout.JAVA_LONG);
            long[] spanLenArray = spanLen.toArray(ValueLayout.JAVA_LONG);
            boolean[] semanticArray = new boolean[(int) count];
            for (int i = 0; i < semanticArray.length; i++) {
                semanticArray[i] = semantic.get(ValueLayout.JAVA_INT, (long) i * Integer.BYTES) != 0;
            }
            return new TreeSnapshot(this, generation, count, parentArray,
                    firstChildArray, nextArray, childCountArray, variableArray,
                    spanStartArray, spanLenArray, semanticArray);
        }
    }

    /**
     * Retained input of the most recent successful parse: the buffer
     * snapshot spans index. Empty before the first parse.
     */
    public byte[] lastInput() {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            checkStatus(lib.galley_last_input(handle, outData, outLen));
            MemorySegment data = outData.get(ValueLayout.ADDRESS, 0);
            long length = outLen.get(ValueLayout.JAVA_LONG, 0);
            if (length == 0) return new byte[0];
            return data.reinterpret(length).toArray(ValueLayout.JAVA_BYTE);
        }
    }

    /**
     * Creates the walker {@link Node#walk} hands out: the one place a walk
     * is started. Closed checks and door choice come from {@link #cross}. The
     * walk is bound to the tree the node came from: its cursor carries the
     * node's own generation, and on the session door nothing asks the core
     * until the first step, which refuses a generation that is gone.
     */
    Walker startWalk(Node node, boolean skipSemanticErrors) {
        Crossing crossing = cross(node);
        return new Walker(this, crossing.address(), crossing.generation(), skipSemanticErrors);
    }

    /**
     * One step of a walk: crosses the door of the calling context — the
     * hook door inside a hook dispatch of this session's running parse,
     * the session door everywhere else — and maps the status onto the
     * walker's contract: null at the end of the walk, {@code door.failure}
     * (which maps a stale tree to {@link StaleTreeException}) for a refusal.
     */
    Walker.WalkStep walkerStep(MemorySegment cursor, long generation) {
        requireOpen();
        NodeDoor door = door();
        long status = door.walkStep(cursor);
        if (status < 0) throw door.failure(status);
        if (status == 0) return null;
        return new Walker.WalkStep(
            new Node(this, WalkCursor.current(cursor), generation),
            WalkCursor.depth(cursor),
            WalkCursor.isSemanticError(cursor));
    }

    /**
     * Grammar name of the node's symbol, decoded as UTF-8 with replacement
     * for malformed input. Null for invalid nodes. Token content stays raw
     * bytes: use {@link #text} for that.
     */
    public String symbolName(Node node) {
        byte[] bytes = symbolNameBytes(node);
        return bytes == null ? null : new String(bytes, StandardCharsets.UTF_8);
    }

    /** Raw bytes behind {@link #symbolName(Node)}. */
    public byte[] symbolNameBytes(Node node) {
        Crossing crossing = cross(node);
        return crossing.door().symbolNameBytes(crossing.generation(), crossing.address());
    }

    public byte[] text(Node node) {
        Crossing crossing = cross(node);
        return crossing.door().text(crossing.generation(), crossing.address());
    }

    public long[] span(Node node) {
        Crossing crossing = cross(node);
        return crossing.door().span(crossing.generation(), crossing.address());
    }

    public int[] lineColumn(Node node) {
        Crossing crossing = cross(node);
        return crossing.door().lineColumn(crossing.generation(), crossing.address());
    }

    /** Raw variable index, or null when the node has no variable. */
    public Integer variableIndex(Node node) {
        Crossing crossing = cross(node);
        return crossing.door().variableIndex(crossing.generation(), crossing.address());
    }

    public int[] lastPosition() {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outLine = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outCol = arena.allocate(ValueLayout.JAVA_INT);
            long st = lib.galley_last_position(handle, outLine, outCol);
            if (st < 0) return null;
            return new int[]{outLine.get(ValueLayout.JAVA_INT, 0), outCol.get(ValueLayout.JAVA_INT, 0)};
        }
    }

    public boolean hasDiagnostic() {
        requireOpen();
        return lib.galley_has_diagnostic(handle) != 0;
    }

    /**
     * Registers one message override: text form, encoded as UTF-8 once.
     * Nulls are rejected loudly. See {@link SessionOptions} for the UTF-8 policy.
     */
    public void setMessageOverride(String name, String message) {
        if (name == null || message == null) throw new IllegalArgumentException("name and message required");
        setMessageOverride(name, message.getBytes(StandardCharsets.UTF_8));
    }

    /**
     * Registers one message override: raw-byte form, passed through
     * unmodified with no re-encoding. Nulls are rejected loudly.
     */
    public void setMessageOverride(String name, byte[] message) {
        requireOpen();
        if (name == null || message == null) throw new IllegalArgumentException("name and message required");
        try (Arena arena = Arena.ofConfined()) {
            byte[] nameBytes = name.getBytes(StandardCharsets.UTF_8);
            MemorySegment nameSeg = nameBytes.length == 0 ? MemorySegment.NULL : arena.allocateFrom(ValueLayout.JAVA_BYTE, nameBytes);
            MemorySegment msgSeg = message.length == 0 ? MemorySegment.NULL : arena.allocateFrom(ValueLayout.JAVA_BYTE, message);
            long st = lib.galley_session_set_message_override(handle,
                    nameSeg, nameBytes.length,
                    msgSeg, message.length);
            checkStatus(st);
        }
    }

    // -- diagnostics helpers --

    private Diagnostic buildDiagnosticSingular() {
        long kind = lib.galley_diagnostic_kind(handle);
        int line, col;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outLine = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outCol = arena.allocate(ValueLayout.JAVA_INT);
            lib.galley_diagnostic_position(handle, outLine, outCol);
            line = outLine.get(ValueLayout.JAVA_INT, 0);
            col = outCol.get(ValueLayout.JAVA_INT, 0);
        }

        String message = "";
        String messageAnsi = "";
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outMsg = arena.allocate(ValueLayout.ADDRESS);
            if (lib.galley_diagnostic_message(handle, outMsg) == 0) {
                MemorySegment p = outMsg.get(ValueLayout.ADDRESS, 0);
                if (!p.equals(MemorySegment.NULL)) message = p.reinterpret(Long.MAX_VALUE).getString(0);
            }
        }
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outMsg = arena.allocate(ValueLayout.ADDRESS);
            if (lib.galley_diagnostic_message_ansi(handle, outMsg) == 0) {
                MemorySegment p = outMsg.get(ValueLayout.ADDRESS, 0);
                if (!p.equals(MemorySegment.NULL)) messageAnsi = p.reinterpret(Long.MAX_VALUE).getString(0);
            }
        }

        byte[] unexpected = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_diagnostic_unexpected_token(handle, outData, outLen) == 0) {
                MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                if (!ptr.equals(MemorySegment.NULL) && len > 0) unexpected = ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
            }
        }

        List<byte[]> expected = new ArrayList<>();
        long expCount = lib.galley_diagnostic_expected_count(handle);
        if (expCount > 0) {
            for (long i = 0; i < expCount; i++) {
                try (Arena arena = Arena.ofConfined()) {
                    MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
                    MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
                    if (lib.galley_diagnostic_expected_at(handle, i, outData, outLen) == 0) {
                        MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                        long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                        if (!ptr.equals(MemorySegment.NULL)) {
                            byte[] b = len == 0 ? new byte[0] : ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                            expected.add(b);
                        }
                    }
                }
            }
        }

        List<String> context = new ArrayList<>();
        List<byte[]> contextBytes = new ArrayList<>();
        long ctxCount = lib.galley_diagnostic_context_count(handle);
        if (ctxCount > 0) {
            for (long i = 0; i < ctxCount; i++) {
                try (Arena arena = Arena.ofConfined()) {
                    MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
                    MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
                    if (lib.galley_diagnostic_context_at(handle, i, outData, outLen) == 0) {
                        MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                        long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                        if (!ptr.equals(MemorySegment.NULL)) {
                            byte[] b = len == 0 ? new byte[0] : ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                            contextBytes.add(b);
                            context.add(new String(b, StandardCharsets.UTF_8));
                        }
                    }
                }
            }
        }

        long sec = lib.galley_syntax_error_count(handle);
        int syntaxErrorCount = sec < 0 ? 0 : (int) sec;

        long semc = lib.galley_semantic_error_count(handle);
        int semanticErrorCount = semc < 0 ? 0 : (int) semc;

        String[] semantic = readSemantic(-1, false);

        int[] indentation = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outSpaces = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outWidth = arena.allocate(ValueLayout.JAVA_INT);
            if (lib.galley_diagnostic_indentation(handle, outSpaces, outWidth) == 0) {
                indentation = new int[]{outSpaces.get(ValueLayout.JAVA_INT, 0), outWidth.get(ValueLayout.JAVA_INT, 0)};
            }
        }

        RecoveryTarget recoveryKind = null;
        long rk = lib.galley_diagnostic_recovery_kind(handle);
        if (rk != 0) recoveryKind = RecoveryTarget.fromCode(rk);

        // Absent stays null: same rule as the recorded builder below.
        byte[] recoveryTerminal = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_diagnostic_recovery_terminal(handle, outData, outLen) == 0) {
                MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                if (!ptr.equals(MemorySegment.NULL) && len > 0) recoveryTerminal = ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
            }
        }

        ResumeSide recoveryResume = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outResume = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_diagnostic_recovery_resume(handle, outResume) == 0) {
                recoveryResume = ResumeSide.fromCode(outResume.get(ValueLayout.JAVA_LONG, 0));
            }
        }

        String recoveryLhs = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_diagnostic_recovery_lhs_variable(handle, outData, outLen) == 0) {
                MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                if (!ptr.equals(MemorySegment.NULL)) {
                    byte[] b = len == 0 ? new byte[0] : ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                    recoveryLhs = new String(b, StandardCharsets.UTF_8);
                }
            }
        }

        Diagnostic.RecoveryProduction recoveryProd = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outVar = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outVarLen = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outIdx = arena.allocate(ValueLayout.JAVA_INT);
            if (lib.galley_diagnostic_recovery_production(handle, outVar, outVarLen, outIdx) == 0) {
                MemorySegment ptr = outVar.get(ValueLayout.ADDRESS, 0);
                long len = outVarLen.get(ValueLayout.JAVA_LONG, 0);
                int idx = outIdx.get(ValueLayout.JAVA_INT, 0);
                if (!ptr.equals(MemorySegment.NULL)) {
                    byte[] b = len == 0 ? new byte[0] : ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                    recoveryProd = new Diagnostic.RecoveryProduction(new String(b, StandardCharsets.UTF_8), idx);
                }
            }
        }

        Diagnostic.RecoveryOccurrence recoveryOcc = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outParent = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outParentLen = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outRhs = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outSym = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outVar = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outVarLen = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_diagnostic_recovery_occurrence(handle, outParent, outParentLen, outRhs, outSym, outVar, outVarLen) == 0) {
                MemorySegment pb = outParent.get(ValueLayout.ADDRESS, 0);
                long pl = outParentLen.get(ValueLayout.JAVA_LONG, 0);
                MemorySegment vb = outVar.get(ValueLayout.ADDRESS, 0);
                long vl = outVarLen.get(ValueLayout.JAVA_LONG, 0);
                byte[] pbytes = pb.equals(MemorySegment.NULL) || pl == 0 ? new byte[0] : pb.reinterpret(pl).toArray(ValueLayout.JAVA_BYTE);
                byte[] vbytes = vb.equals(MemorySegment.NULL) || vl == 0 ? new byte[0] : vb.reinterpret(vl).toArray(ValueLayout.JAVA_BYTE);
                recoveryOcc = new Diagnostic.RecoveryOccurrence(
                        new String(pbytes, StandardCharsets.UTF_8), outRhs.get(ValueLayout.JAVA_INT, 0), outSym.get(ValueLayout.JAVA_INT, 0), new String(vbytes, StandardCharsets.UTF_8));
            }
        }

        return new Diagnostic(DiagnosticKind.fromCode(kind), line, col, message, messageAnsi, unexpected, expected, context,
                contextBytes,
                syntaxErrorCount, semanticErrorCount, semantic, indentation, recoveryKind, recoveryTerminal, recoveryResume,
                recoveryLhs, recoveryProd, recoveryOcc);
    }

    private Diagnostic buildRecordedDiagnostic(long diagIndex) {
        int line, col;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outLine = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outCol = arena.allocate(ValueLayout.JAVA_INT);
            long st = lib.galley_recorded_diagnostic_position(handle, diagIndex, outLine, outCol);
            if (st < 0) return null;
            line = outLine.get(ValueLayout.JAVA_INT, 0);
            col = outCol.get(ValueLayout.JAVA_INT, 0);
        }

        long kind = lib.galley_recorded_diagnostic_kind(handle, diagIndex);

        String message = "";
        String messageAnsi = "";
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outMsg = arena.allocate(ValueLayout.ADDRESS);
            if (lib.galley_recorded_diagnostic_message(handle, diagIndex, outMsg) == 0) {
                MemorySegment p = outMsg.get(ValueLayout.ADDRESS, 0);
                if (!p.equals(MemorySegment.NULL)) message = p.reinterpret(Long.MAX_VALUE).getString(0);
                // No recorded-ANSI entry in the C ABI; the plain message stands in.
                messageAnsi = message;
            }
        }

        byte[] unexpected = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_recorded_unexpected_token(handle, diagIndex, outData, outLen) == 0) {
                MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                if (!ptr.equals(MemorySegment.NULL) && len > 0) unexpected = ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
            }
        }

        List<byte[]> expected = new ArrayList<>();
        long expCount = lib.galley_recorded_expected_count(handle, diagIndex);
        if (expCount > 0) {
            for (long i = 0; i < expCount; i++) {
                try (Arena arena = Arena.ofConfined()) {
                    MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
                    MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
                    if (lib.galley_recorded_expected_token(handle, diagIndex, i, outData, outLen) == 0) {
                        MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                        long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                        if (!ptr.equals(MemorySegment.NULL)) {
                            byte[] b = len == 0 ? new byte[0] : ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                            expected.add(b);
                        }
                    }
                }
            }
        }

        List<String> context = new ArrayList<>();
        List<byte[]> contextBytes = new ArrayList<>();
        long ctxCount = lib.galley_recorded_context_count(handle, diagIndex);
        if (ctxCount > 0) {
            for (long i = 0; i < ctxCount; i++) {
                try (Arena arena = Arena.ofConfined()) {
                    MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
                    MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
                    if (lib.galley_recorded_context_name(handle, diagIndex, i, outData, outLen) == 0) {
                        MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                        long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                        if (!ptr.equals(MemorySegment.NULL)) {
                            byte[] b = len == 0 ? new byte[0] : ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                            contextBytes.add(b);
                            context.add(new String(b, StandardCharsets.UTF_8));
                        }
                    }
                }
            }
        }

        int[] indentation = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outSpaces = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outWidth = arena.allocate(ValueLayout.JAVA_INT);
            if (lib.galley_recorded_indentation(handle, diagIndex, outSpaces, outWidth) == 0) {
                indentation = new int[]{outSpaces.get(ValueLayout.JAVA_INT, 0), outWidth.get(ValueLayout.JAVA_INT, 0)};
            }
        }

        RecoveryTarget recoveryKind = null;
        long rk = lib.galley_recorded_diagnostic_recovery_kind(handle, diagIndex);
        if (rk != 0) recoveryKind = RecoveryTarget.fromCode(rk);

        byte[] recoveryTerminal = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_recorded_recovery_terminal(handle, diagIndex, outData, outLen) == 0) {
                MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                if (!ptr.equals(MemorySegment.NULL) && len > 0) recoveryTerminal = ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
            }
        }

        ResumeSide recoveryResume = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outResume = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_recorded_recovery_resume(handle, diagIndex, outResume) == 0) {
                recoveryResume = ResumeSide.fromCode(outResume.get(ValueLayout.JAVA_LONG, 0));
            }
        }

        String recoveryLhs = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_recorded_recovery_lhs_variable(handle, diagIndex, outData, outLen) == 0) {
                MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                if (!ptr.equals(MemorySegment.NULL)) {
                    byte[] b = len == 0 ? new byte[0] : ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                    recoveryLhs = new String(b, StandardCharsets.UTF_8);
                }
            }
        }

        Diagnostic.RecoveryProduction recoveryProd = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outVar = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outVarLen = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outIdx = arena.allocate(ValueLayout.JAVA_INT);
            if (lib.galley_recorded_recovery_production(handle, diagIndex, outVar, outVarLen, outIdx) == 0) {
                MemorySegment ptr = outVar.get(ValueLayout.ADDRESS, 0);
                long len = outVarLen.get(ValueLayout.JAVA_LONG, 0);
                int idx = outIdx.get(ValueLayout.JAVA_INT, 0);
                if (!ptr.equals(MemorySegment.NULL)) {
                    byte[] b = len == 0 ? new byte[0] : ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
                    recoveryProd = new Diagnostic.RecoveryProduction(new String(b, StandardCharsets.UTF_8), idx);
                }
            }
        }

        Diagnostic.RecoveryOccurrence recoveryOcc = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outParent = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outParentLen = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outRhs = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outSym = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outVar = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outVarLen = arena.allocate(ValueLayout.JAVA_LONG);
            if (lib.galley_recorded_recovery_occurrence(handle, diagIndex, outParent, outParentLen, outRhs, outSym, outVar, outVarLen) == 0) {
                MemorySegment pb = outParent.get(ValueLayout.ADDRESS, 0);
                long pl = outParentLen.get(ValueLayout.JAVA_LONG, 0);
                MemorySegment vb = outVar.get(ValueLayout.ADDRESS, 0);
                long vl = outVarLen.get(ValueLayout.JAVA_LONG, 0);
                byte[] pbytes = pb.equals(MemorySegment.NULL) || pl == 0 ? new byte[0] : pb.reinterpret(pl).toArray(ValueLayout.JAVA_BYTE);
                byte[] vbytes = vb.equals(MemorySegment.NULL) || vl == 0 ? new byte[0] : vb.reinterpret(vl).toArray(ValueLayout.JAVA_BYTE);
                recoveryOcc = new Diagnostic.RecoveryOccurrence(
                        new String(pbytes, StandardCharsets.UTF_8), outRhs.get(ValueLayout.JAVA_INT, 0), outSym.get(ValueLayout.JAVA_INT, 0), new String(vbytes, StandardCharsets.UTF_8));
            }
        }

        return new Diagnostic(DiagnosticKind.fromCode(kind), line, col, message, messageAnsi, unexpected, expected, context,
                contextBytes,
                0, 0, readSemantic(diagIndex, true), indentation, recoveryKind, recoveryTerminal, recoveryResume,
                recoveryLhs, recoveryProd, recoveryOcc);
    }

    private String[] readSemantic(long diagIndex, boolean recorded) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outVar = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outVarLen = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outMsg = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outMsgLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = recorded
                    ? lib.galley_recorded_semantic(handle, diagIndex, outVar, outVarLen, outMsg, outMsgLen)
                    : lib.galley_diagnostic_semantic(handle, outVar, outVarLen, outMsg, outMsgLen);
            if (st != 0) return null;
            MemorySegment vb = outVar.get(ValueLayout.ADDRESS, 0);
            long vl = outVarLen.get(ValueLayout.JAVA_LONG, 0);
            MemorySegment mb = outMsg.get(ValueLayout.ADDRESS, 0);
            long ml = outMsgLen.get(ValueLayout.JAVA_LONG, 0);
            if (vb.equals(MemorySegment.NULL) || mb.equals(MemorySegment.NULL)) return null;
            return new String[]{
                    new String(vb.reinterpret(vl).toArray(ValueLayout.JAVA_BYTE), StandardCharsets.UTF_8),
                    new String(mb.reinterpret(ml).toArray(ValueLayout.JAVA_BYTE), StandardCharsets.UTF_8)};
        }
    }

    public Diagnostic diagnostic() {
        requireOpen();
        if (lib.galley_has_diagnostic(handle) == 0) return null;
        return buildDiagnosticSingular();
    }

    public List<Diagnostic> diagnostics() {
        requireOpen();
        long count = lib.galley_recorded_diagnostic_count(handle);
        if (count <= 0) return new ArrayList<>();
        List<Diagnostic> out = new ArrayList<>((int) count);
        for (long i = 0; i < count; i++) {
            Diagnostic d = buildRecordedDiagnostic(i);
            if (d != null) out.add(d);
        }
        return out;
    }

    // -- tree editing --

    public void appendChildren(Node parent, Node chain) {
        Crossing crossing = cross(parent);
        crossing.door().appendChildren(crossing.generation(), crossing.address(), second(crossing, chain));
    }

    public void insertBefore(Node target, Node chain) {
        Crossing crossing = cross(target);
        crossing.door().insertBefore(crossing.generation(), crossing.address(), second(crossing, chain));
    }

    public void insertAfter(Node target, Node chain) {
        Crossing crossing = cross(target);
        crossing.door().insertAfter(crossing.generation(), crossing.address(), second(crossing, chain));
    }

    public Node removeSiblings(Node node, int count) {
        Crossing crossing = cross(node);
        return node(crossing.door().removeSiblings(crossing.generation(), crossing.address(), count), crossing.generation());
    }

    public Node removeSelf(Node node) {
        Crossing crossing = cross(node);
        return node(crossing.door().removeSelf(crossing.generation(), crossing.address()), crossing.generation());
    }

    public Node cleanChildren(Node node) {
        Crossing crossing = cross(node);
        return node(crossing.door().cleanChildren(crossing.generation(), crossing.address()), crossing.generation());
    }

    public void insertChildrenAt(Node parent, int index, Node chain) {
        Crossing crossing = cross(parent);
        crossing.door().insertChildrenAt(crossing.generation(), crossing.address(), index, second(crossing, chain));
    }

    public Node removeChildrenAt(Node parent, int index, int count) {
        Crossing crossing = cross(parent);
        return node(crossing.door().removeChildrenAt(crossing.generation(), crossing.address(), index, count), crossing.generation());
    }

    // -- symbol table --

    /**
     * Grammar name of the symbol at table {@code index}, decoded as UTF-8
     * with replacement for malformed input. Null for out-of-range indices.
     */
    public String symbolNameAt(long index) {
        byte[] bytes = symbolNameAtBytes(index);
        return bytes == null ? null : new String(bytes, StandardCharsets.UTF_8);
    }

    /** Raw bytes behind {@link #symbolNameAt(long)}. Null for out-of-range indices. */
    public byte[] symbolNameAtBytes(long index) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = lib.galley_symbol_name(handle, index, outData, outLen);
            if (st < 0) return null;
            MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
            long len = outLen.get(ValueLayout.JAVA_LONG, 0);
            if (ptr.equals(MemorySegment.NULL) || len == 0) return new byte[0];
            return ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
        }
    }

    public boolean symbolIsTerminal(long index) {
        requireOpen();
        return lib.galley_symbol_is_terminal(handle, index) != 0;
    }

    /**
     * Grammar name of the variable at table {@code index}, decoded as UTF-8
     * with replacement for malformed input. Null for out-of-range indices.
     */
    public String variableNameAt(long index) {
        byte[] bytes = variableNameAtBytes(index);
        return bytes == null ? null : new String(bytes, StandardCharsets.UTF_8);
    }

    /** Raw bytes behind {@link #variableNameAt(long)}. Null for out-of-range indices. */
    public byte[] variableNameAtBytes(long index) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = lib.galley_variable_name(handle, index, outData, outLen);
            if (st < 0) return null;
            MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
            long len = outLen.get(ValueLayout.JAVA_LONG, 0);
            if (ptr.equals(MemorySegment.NULL) || len == 0) return new byte[0];
            return ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
        }
    }

    // -- parser metadata (answered by the owning parser) --

    public String version() { return parser.version(); }

    public ParserType parserType() { return parser.parserType(); }

    public RecoveryMode errorRecoveryMode() { return parser.errorRecoveryMode(); }

    public boolean hasAst() { return parser.hasAst(); }

    public boolean hasProcedures() { return parser.hasProcedures(); }

    public boolean allowsNoAstTreeProcedures() { return parser.allowsNoAstTreeProcedures(); }

    public boolean sourceRetentionEnabled() { return parser.sourceRetentionEnabled(); }

    public boolean hasPositionTracking() { return parser.hasPositionTracking(); }

    public boolean hasInputStreaming() { return parser.hasInputStreaming(); }

    public boolean usesVerbatim() { return parser.usesVerbatim(); }

    public boolean stackOverflowRecoveryAvailable() { return parser.stackOverflowRecoveryAvailable(); }

    public long symbolCount() { return parser.symbolCount(); }

    public long variableCount() { return parser.variableCount(); }

    public String statusString(long status) { return parser.statusString(status); }

    public String statusString(StatusCode status) { return parser.statusString(status); }

    // Expose handle for internal use
    MemorySegment getHandle() { return handle; }
    GalleyLibrary getLibrary() { return lib; }
}
