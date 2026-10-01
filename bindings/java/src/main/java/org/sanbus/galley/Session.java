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
public final class Session extends NodeDoor implements AutoCloseable {

    private static final long INVALID_NODE = 0xFFFFFFFFFFFFFFFFL;

    private MemorySegment handle;
    private final GalleyLibrary lib;
    private boolean closed = false;
    private final Parser parser;
    /**
     * Parse generation, bumped by every parse and close. Walkers stamp it
     * at creation and refuse to step once it moves, so no step ever reads
     * reallocated storage.
     */
    private long generation = 0;
    /** Handle the library passes back with this session's hooks; routes the parser's one dispatch stub here. */
    private long handleId;
    /** This session's hooks by name: replaced whole, never mutated. */
    private volatile Map<String, Consumer<ProcedureArguments>> hooks = Map.of();
    /** The same hooks by the library's hook index, the dispatch lookup. */
    private volatile Consumer<ProcedureArguments>[] hooksByIndex;
    /** The running parse's door, learned from its first hook; reset around every parse. */
    private HookDoor parseDoor;

    public Session(Parser parser) {
        this(parser, SessionOptions.defaults());
    }

    public Session(Parser parser, SessionOptions options) {
        if (parser == null) throw new IllegalArgumentException("parser is null");
        if (options == null) options = SessionOptions.defaults();
        this.parser = parser;
        this.lib = parser.library();

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

    /** Current parse generation. Walkers stamp it at creation and Nodes stamp it at construction; both refuse older generations. */
    long parseGeneration() { return generation; }

    private void requireOpen() {
        if (closed || handle == null || handle.equals(MemorySegment.NULL)) throw new GalleyClosedException("session");
    }

    /**
     * The session door's liveness: the session must be open and the node
     * must belong to the current parse generation, so a node never reads
     * storage a later parse reset.
     */
    @Override
    void requireLive(Node node) {
        if (isClosed()) throw new GalleyClosedException("node's session");
        if (node.generation() != generation) throw GalleyClosedException.invalidated("node");
    }

    private GalleyException errorFromStatus(long status) {
        String msg = lib.galley_status_string(status);
        if (msg == null) msg = "unknown galley error";
        Diagnostic diag = null;
        try {
            if (handle != null && !handle.equals(MemorySegment.NULL) && lib.galley_has_diagnostic(handle) != 0) {
                diag = buildDiagnosticSingular();
                if (diag.getMessage() != null && !diag.getMessage().isEmpty()) msg = diag.getMessage();
            }
        } catch (Exception ignored) {}
        return new GalleyException(msg, (int) status, diag);
    }

    private void checkStatus(long status) {
        if (status < 0) throw errorFromStatus(status);
    }

    /**
     * Single gate ending every parse leg: bumps the parse generation on
     * any status (success or failure, so pre-parse walkers fail at their
     * next step instead of reading reallocated storage), then throws or
     * returns the parsed byte count. Parsing itself never throws merely
     * because a walker is open.
     */
    private int completeParse(long status) {
        generation++;
        if (status < 0) throw errorFromStatus(status);
        return (int) status;
    }

    /** One native parse call. */
    private interface NativeParse {
        long run();
    }

    /**
     * Single gate for every parse leg: runs the native call with a fresh
     * parse door slot, then ends the parse. The hooks were fixed by the
     * last commit, so nothing is synchronized here.
     */
    private int runParse(NativeParse nativeParse) {
        parseDoor = null;
        try {
            return completeParse(nativeParse.run());
        } finally {
            parseDoor = null;
        }
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
        generation++;
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
        if (parseDoor == null) parseDoor = new HookDoor(lib, lib.galley_procedure_door(argumentsPointer), this);
        ProcedureArguments arguments = new ProcedureArguments(argumentsPointer, lib, parseDoor);
        try {
            hook.accept(arguments);
        } catch (Throwable t) {
            t.printStackTrace(System.err);
        } finally {
            // The native arguments die when this hook call returns; expire
            // the Java reference with them. The tree outlives the hook on
            // the parse's door.
            arguments.expire();
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

    public long nodeCount() {
        requireOpen();
        return lib.galley_node_count(handle);
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

    public Node rootNode() {
        requireOpen();
        long addr = lib.galley_root_node(handle);
        if (addr == INVALID_NODE) return null;
        return new Node(this, addr);
    }

    public boolean nodeValid(long address) {
        requireOpen();
        return lib.galley_node_is_valid(handle, address) != 0;
    }

    public boolean nodeValid(Node node) {
        if (node == null) return false;
        return nodeValid(address(node));
    }

    public int childCount(long address) {
        requireOpen();
        return lib.galley_node_child_count(handle, address);
    }

    public int childCount(Node node) {
        if (node == null) return 0;
        return childCount(address(node));
    }

    @Override
    public List<Node> children(Node node) {
        if (node == null) return new ArrayList<>();
        return super.children(node);
    }

    /** Children of a raw address; the iteration is the one both doors share. */
    public List<Node> children(long address) {
        requireOpen();
        return collectChildren(childCount(address), firstChild(address));
    }

    private Node optNode(long addr) {
        if (addr == INVALID_NODE) return null;
        return new Node(this, addr);
    }

    public Node firstChild(Node node) {
        return optNode(lib.galley_node_first_child(handle, address(node)));
    }

    public Node firstChild(long address) {
        requireOpen();
        return optNode(lib.galley_node_first_child(handle, address));
    }

    public Node lastChild(Node node) {
        return optNode(lib.galley_node_last_child(handle, address(node)));
    }

    public Node lastChild(long address) {
        requireOpen();
        return optNode(lib.galley_node_last_child(handle, address));
    }

    public Node nextSibling(Node node) {
        return optNode(lib.galley_node_next_sibling(handle, address(node)));
    }

    public Node nextSibling(long address) {
        requireOpen();
        return optNode(lib.galley_node_next_sibling(handle, address));
    }

    public Node priorSibling(Node node) {
        return optNode(lib.galley_node_prior_sibling(handle, address(node)));
    }

    public Node priorSibling(long address) {
        requireOpen();
        return optNode(lib.galley_node_prior_sibling(handle, address));
    }

    public Node parent(Node node) {
        return optNode(lib.galley_node_parent(handle, address(node)));
    }

    public Node parent(long address) {
        requireOpen();
        return optNode(lib.galley_node_parent(handle, address));
    }

    /**
     * Flat bulk read of the most recent successful parse in a single call:
     * one entry per node address. Missing links read as {@code -1}
     * (matching {@link #INVALID_NODE} bits), missing variables as -1, and
     * spans index {@link #lastInput()}. Walk {@code parent}/
     * {@code firstChild}/{@code next} directly instead of one call per
     * node.
     */
    public TreeSnapshot snapshot() {
        requireOpen();
        long count = lib.galley_node_count(handle);
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment parent = arena.allocate(ValueLayout.JAVA_LONG, count);
            MemorySegment firstChild = arena.allocate(ValueLayout.JAVA_LONG, count);
            MemorySegment next = arena.allocate(ValueLayout.JAVA_LONG, count);
            MemorySegment childCount = arena.allocate(ValueLayout.JAVA_INT, count);
            MemorySegment variable = arena.allocate(ValueLayout.JAVA_LONG, count);
            MemorySegment spanStart = arena.allocate(ValueLayout.JAVA_LONG, count);
            MemorySegment spanLen = arena.allocate(ValueLayout.JAVA_LONG, count);
            MemorySegment semantic = arena.allocate(ValueLayout.JAVA_INT, count);
            long total = lib.galley_tree_snapshot(handle, parent, firstChild, next,
                    childCount, variable, spanStart, spanLen, semantic, count);
            if (total < 0) throw errorFromStatus(total);
            if (total != count) throw new IllegalStateException("node count changed during snapshot");
            long[] parentArray = parent.toArray(ValueLayout.JAVA_LONG);
            long[] firstChildArray = firstChild.toArray(ValueLayout.JAVA_LONG);
            long[] nextArray = next.toArray(ValueLayout.JAVA_LONG);
            int[] childCountArray = childCount.toArray(ValueLayout.JAVA_INT);
            long[] variableArray = variable.toArray(ValueLayout.JAVA_LONG);
            long[] spanStartArray = spanStart.toArray(ValueLayout.JAVA_LONG);
            long[] spanLenArray = spanLen.toArray(ValueLayout.JAVA_LONG);
            boolean[] semanticArray = new boolean[(int) count];
            for (int i = 0; i < semanticArray.length; i++) {
                semanticArray[i] = semantic.get(ValueLayout.JAVA_INT, (long) i * Integer.BYTES) != 0;
            }
            return new TreeSnapshot(count, parentArray, firstChildArray, nextArray,
                    childCountArray, variableArray, spanStartArray, spanLenArray,
                    semanticArray);
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
     * Pre-order walker over the subtree rooted at {@code node}, with the
     * root at depth 0. Pass true to prune subtrees rooted at semantic-error
     * nodes. Returns null for invalid roots and builds without AST
     * construction. Close the walker before closing the session or parsing
     * again.
     */
    public Walker walk(Node node, boolean skipSemanticErrors) {
        if (node == null) return null;
        return walk(address(node), skipSemanticErrors);
    }

    public Walker walk(long address, boolean skipSemanticErrors) {
        requireOpen();
        MemorySegment walker = lib.galley_walker_create(handle, address, skipSemanticErrors ? 1 : 0);
        if (walker.equals(MemorySegment.NULL)) return null;
        return new Walker(this, walker, generation);
    }

    Walker.WalkStep walkerNext(MemorySegment walker) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outNode = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outDepth = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outFlag = arena.allocate(ValueLayout.JAVA_INT);
            if (lib.galley_walker_next(walker, outNode, outDepth, outFlag) == 0) return null;
            return new Walker.WalkStep(
                new Node(this, outNode.get(ValueLayout.JAVA_LONG, 0)),
                outDepth.get(ValueLayout.JAVA_INT, 0),
                outFlag.get(ValueLayout.JAVA_INT, 0) != 0);
        }
    }

    void walkerSkipChildren(MemorySegment walker) {
        requireOpen();
        lib.galley_walker_skip_children(walker);
    }

    void walkerDestroy(MemorySegment walker) {
        lib.galley_walker_destroy(walker);
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

    /**
     * Grammar name of the node's symbol, decoded as UTF-8 with replacement
     * for malformed input. Null for invalid nodes.
     */
    public String symbolName(long address) {
        byte[] bytes = symbolNameBytes(address);
        return bytes == null ? null : new String(bytes, StandardCharsets.UTF_8);
    }

    /** Raw bytes behind {@link #symbolName(Node)}. Null for invalid nodes. */
    public byte[] symbolNameBytes(Node node) {
        if (node == null) return null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = lib.galley_node_symbol_name(handle, address(node), outData, outLen);
            return NodeDoor.outBytes(st, outData, outLen);
        }
    }

    /** Raw bytes behind {@link #symbolName(long)}. Null for invalid nodes. */
    public byte[] symbolNameBytes(long address) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = lib.galley_node_symbol_name(handle, address, outData, outLen);
            return NodeDoor.outBytes(st, outData, outLen);
        }
    }

    public byte[] text(Node node) {
        if (node == null) return null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = lib.galley_node_text(handle, address(node), outData, outLen);
            return NodeDoor.outBytes(st, outData, outLen);
        }
    }

    public byte[] text(long address) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = lib.galley_node_text(handle, address, outData, outLen);
            return NodeDoor.outBytes(st, outData, outLen);
        }
    }

    public long[] span(Node node) {
        if (node == null) return null;
        return span(address(node));
    }

    public long[] span(long address) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outStart = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = lib.galley_node_span(handle, address, outStart, outLen);
            if (st < 0) return null;
            return new long[]{outStart.get(ValueLayout.JAVA_LONG, 0), outLen.get(ValueLayout.JAVA_LONG, 0)};
        }
    }

    public int[] lineColumn(Node node) {
        if (node == null) return null;
        return lineColumn(address(node));
    }

    public int[] lineColumn(long address) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outLine = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outCol = arena.allocate(ValueLayout.JAVA_INT);
            long st = lib.galley_node_line_column(handle, address, outLine, outCol);
            if (st < 0) return null;
            return new int[]{outLine.get(ValueLayout.JAVA_INT, 0), outCol.get(ValueLayout.JAVA_INT, 0)};
        }
    }

    public Integer variableIndex(Node node) {
        if (node == null) return null;
        long idx = lib.galley_node_variable_index(handle, address(node));
        if (idx == -1) return null;
        if (idx < 0) throw errorFromStatus(idx);
        return (int) idx;
    }

    public Integer variableIndex(long address) {
        requireOpen();
        long idx = lib.galley_node_variable_index(handle, address);
        if (idx == -1) return null;
        if (idx < 0) throw errorFromStatus(idx);
        return (int) idx;
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
        appendChildren(address(parent), address(chain));
    }

    public void appendChildren(long parentAddr, long chainAddr) {
        requireOpen();
        checkStatus(lib.galley_tree_append_children(handle, parentAddr, chainAddr));
    }

    public void insertBefore(Node target, Node chain) {
        insertBefore(address(target), address(chain));
    }

    public void insertBefore(long targetAddr, long chainAddr) {
        requireOpen();
        checkStatus(lib.galley_tree_insert_before(handle, targetAddr, chainAddr));
    }

    public void insertAfter(Node target, Node chain) {
        insertAfter(address(target), address(chain));
    }

    public void insertAfter(long targetAddr, long chainAddr) {
        requireOpen();
        checkStatus(lib.galley_tree_insert_after(handle, targetAddr, chainAddr));
    }

    public Node removeSiblings(Node node, int count) {
        return removeSiblings(address(node), count);
    }

    public Node removeSiblings(long nodeAddr, int count) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outHead = arena.allocate(ValueLayout.JAVA_LONG);
            outHead.set(ValueLayout.JAVA_LONG, 0, INVALID_NODE);
            long st = lib.galley_tree_remove_siblings(handle, nodeAddr, count, outHead);
            checkStatus(st);
            long head = outHead.get(ValueLayout.JAVA_LONG, 0);
            if (head == INVALID_NODE) return null;
            return new Node(this, head);
        }
    }

    public Node removeSelf(Node node) {
        return removeSelf(address(node));
    }

    public Node removeSelf(long nodeAddr) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outHead = arena.allocate(ValueLayout.JAVA_LONG);
            outHead.set(ValueLayout.JAVA_LONG, 0, INVALID_NODE);
            long st = lib.galley_tree_remove_self(handle, nodeAddr, outHead);
            checkStatus(st);
            long head = outHead.get(ValueLayout.JAVA_LONG, 0);
            if (head == INVALID_NODE) return null;
            return new Node(this, head);
        }
    }

    public Node promoteChildrenOverWrapper(Node wrapper) {
        return promoteChildrenOverWrapper(address(wrapper));
    }

    public Node promoteChildrenOverWrapper(long wrapperAddr) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outHead = arena.allocate(ValueLayout.JAVA_LONG);
            outHead.set(ValueLayout.JAVA_LONG, 0, INVALID_NODE);
            long st = lib.galley_tree_promote_children_over_wrapper(handle, wrapperAddr, outHead);
            checkStatus(st);
            long head = outHead.get(ValueLayout.JAVA_LONG, 0);
            if (head == INVALID_NODE) return null;
            return new Node(this, head);
        }
    }

    public Node cleanChildren(Node node) {
        return cleanChildren(address(node));
    }

    public Node cleanChildren(long nodeAddr) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outHead = arena.allocate(ValueLayout.JAVA_LONG);
            outHead.set(ValueLayout.JAVA_LONG, 0, INVALID_NODE);
            long st = lib.galley_tree_clean_children(handle, nodeAddr, outHead);
            checkStatus(st);
            long head = outHead.get(ValueLayout.JAVA_LONG, 0);
            if (head == INVALID_NODE) return null;
            return new Node(this, head);
        }
    }

    public void unlinkWrapper(Node wrapper) {
        unlinkWrapper(address(wrapper));
    }

    public void unlinkWrapper(long wrapperAddr) {
        requireOpen();
        checkStatus(lib.galley_tree_unlink_wrapper(handle, wrapperAddr));
    }

    public void insertChildrenAt(Node parent, int index, Node chain) {
        insertChildrenAt(address(parent), index, address(chain));
    }

    public void insertChildrenAt(long parentAddr, int index, long chainAddr) {
        requireOpen();
        checkStatus(lib.galley_tree_insert_children_at(handle, parentAddr, index, chainAddr));
    }

    public Node removeChildrenAt(Node parent, int index, int count) {
        return removeChildrenAt(address(parent), index, count);
    }

    public Node removeChildrenAt(long parentAddr, int index, int count) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outHead = arena.allocate(ValueLayout.JAVA_LONG);
            outHead.set(ValueLayout.JAVA_LONG, 0, INVALID_NODE);
            long st = lib.galley_tree_remove_children_at(handle, parentAddr, index, count, outHead);
            checkStatus(st);
            long head = outHead.get(ValueLayout.JAVA_LONG, 0);
            if (head == INVALID_NODE) return null;
            return new Node(this, head);
        }
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
