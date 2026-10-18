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

    /**
     * The native session. Read only inside {@link #gate}, in {@link #close},
     * and in the constructor: every other crossing takes it from the gate, so
     * no native call can be handed a handle its close has already freed.
     */
    private MemorySegment handle;
    private final GalleyLibrary lib;
    /** Volatile so the lock-free {@link #isClosed()} probes are answered with the latest truth; the gate re-reads it under {@link #lifetime}. */
    private volatile boolean closed = false;
    /** Guards {@link #handle} and {@link #inFlight}: the one lock no native call runs under. */
    private final Object lifetime = new Object();
    /** Calls in flight against {@link #handle}. A counter, not a flag: a hook's call nests inside its parse's. */
    private int inFlight;
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
     * native door is constant for the parse) and dropped by the parse's
     * finish gate; null between parses.
     */
    private volatile NodeDoor parseDoor;
    /**
     * The core generation of the running parse, read through
     * {@code galley_hook_generation} on its first dispatch: only the stamp of
     * the nodes its hooks produce, never compared with anything — the core
     * checks every node it is handed.
     */
    private volatile long parseGeneration;
    /**
     * The thread running the hook in progress, or null between hooks. Only
     * that thread may cross {@link #parseDoor}; every other thread crosses
     * the session door.
     */
    private volatile Thread dispatchThread;
    /**
     * What one parse call keeps of its hooks: the throwable a hook threw. It
     * belongs to the call that runs the parse, so another thread that starts a
     * parse on this session the moment the core releases it can neither
     * overwrite nor take it. Hooks run on the parsing thread, so the upcall
     * finds its parse's holder through that thread's own chain (nested parses
     * of other sessions stack up).
     */
    private static final class ParseHolder {
        final Session session;
        final ParseHolder outer;
        Throwable failure;

        ParseHolder(Session session, ParseHolder outer) {
            this.session = session;
            this.outer = outer;
        }
    }

    private static final ThreadLocal<ParseHolder> INNERMOST_HOLDER = new ThreadLocal<>();

    public Session(Parser parser) {
        this(parser, SessionOptions.defaults());
    }

    public Session(Parser parser, SessionOptions options) {
        if (parser == null) throw new IllegalArgumentException("parser is null");
        if (options == null) options = SessionOptions.defaults();
        this.parser = parser;
        this.lib = parser.library();
        this.sessionDoor = NodeDoor.ofSession(lib, this);

        boolean hasNonDefault = options.getMaxErrors() != 10 ||
                options.getRecoveryWindow() != 500 ||
                options.isStackOverflowRecovery() ||
                options.getSyntaxErrorStackDepth() != 0 ||
                options.getVerbosity() != 0 ||
                options.getAstPreallocationRatio() != -1.0 ||
                options.getAstPreallocationCap() != 0;

        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outSession = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment opts = MemorySegment.NULL;
            if (hasNonDefault) {
                opts = arena.allocate(GalleyLibrary.GALLEY_COPTIONS_SIZE);
                opts.set(ValueLayout.JAVA_INT, GalleyLibrary.OFF_MAX_ERRORS, options.getMaxErrors());
                opts.set(ValueLayout.JAVA_INT, GalleyLibrary.OFF_RECOVERY_WINDOW, options.getRecoveryWindow());
                opts.set(ValueLayout.JAVA_INT, GalleyLibrary.OFF_STACK_OVERFLOW_RECOVERY, options.isStackOverflowRecovery() ? 1 : 0);
                opts.set(ValueLayout.JAVA_INT, GalleyLibrary.OFF_SYNTAX_ERROR_STACK_DEPTH, options.getSyntaxErrorStackDepth());
                opts.set(ValueLayout.JAVA_INT, GalleyLibrary.OFF_VERBOSITY, options.getVerbosity());
                opts.set(ValueLayout.JAVA_DOUBLE, GalleyLibrary.OFF_AST_PREALLOCATION_RATIO, options.getAstPreallocationRatio());
                opts.set(ValueLayout.JAVA_LONG, GalleyLibrary.OFF_AST_PREALLOCATION_CAP, options.getAstPreallocationCap());
            }
            checkStatus(lib.galley_session_create(opts, outSession));
            this.handle = outSession.get(ValueLayout.ADDRESS, 0);
        }
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

    /** One native call, made with the session handle it is given. */
    @FunctionalInterface
    interface HandleCall<T> {
        T run(MemorySegment handle);
    }

    /**
     * The one crossing over the handle: claims it for a single native call so
     * {@link #close} cannot free the session while that call is in flight.
     * Increments the count first and reads the session open under the same
     * lock close transitions on — a call either starts before close wins it,
     * or finds the session closed — then runs outside the lock, because a
     * native call must never hold {@code lifetime} (a hook's crossing would
     * then wait on its own parse's). The count drops in a finally, and nests:
     * a hook's call sits inside its parse's count, which is why close refuses
     * with {@code session in use} rather than waiting.
     */
    <T> T gate(HandleCall<T> body) {
        MemorySegment claimed;
        boolean open;
        synchronized (lifetime) {
            inFlight++;
            open = !closed && handle != null && !handle.equals(MemorySegment.NULL);
            claimed = handle;
        }
        try {
            if (!open) throw new GalleyClosedException("session");
            return body.run(claimed);
        } finally {
            synchronized (lifetime) { inFlight--; }
        }
    }

    private void requireOpen() {
        if (closed) throw new GalleyClosedException("session");
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
     * The single gate for a node argument: the node must belong to this
     * session. It carries the generation every call of this operation hands
     * the core, which refuses one that is not the live tree's on either door
     * ({@link StaleTreeException}), so the session keeps no copy of it and
     * cannot disagree with the core. A bare address would alias storage
     * unchecked, which is why only a {@link Node} reaches this gate.
     *
     * @throws IllegalArgumentException if {@code node} belongs to another session
     */
    long address(Node node) {
        Session home = node.session();
        if (home.isClosed()) throw new GalleyClosedException("node's session");
        if (home != this) {
            throw new IllegalArgumentException("node belongs to a different session than this operation");
        }
        return node.getAddress();
    }

    /**
     * What one node operation crosses with, fixed by {@link #cross}: the
     * door, the first node's own generation, and that node's address. A
     * second node crosses with its own generation beside it.
     */
    private record Crossing(NodeDoor door, long generation, long address) {}

    /**
     * The one gate of a node operation: closed checks and door choice
     * ({@link #door(Node)}), then the node's admission to that door
     * ({@link #address}). Nothing crosses without coming through here.
     */
    private Crossing cross(Node node) {
        NodeDoor door = door(node);
        return new Crossing(door, node.generation(), address(node));
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
     * door. Only a parse failure carries a diagnostic ({@link #parseFailure}).
     */
    GalleyException errorFromStatus(long status) {
        return statusFailure(lib, status, null);
    }

    /**
     * The failure of a parse, with that parse's diagnostic snapshot attached
     * exactly when its status carries one
     * ({@link Status#carriesDiagnostic}): the statuses that end a parse
     * that ran, whose diagnostic then belongs to that attempt. A failure
     * built from any other status carries none. {@code ERROR_SESSION_IN_USE}
     * is also the one refusal the attach may skip, because another thread's
     * parse took the session in the window between this parse and the
     * attach. A {@link GalleyClosedException} from the attach is that same
     * race with a concurrent {@code close()} winning it: the attach is
     * skipped too, so the parse's own failure stands — never the close's.
     * Every other refusal from the attach path is the failure.
     */
    private GalleyException parseFailure(long status) {
        Diagnostic diagnostic = null;
        if (Status.fromCode(status).carriesDiagnostic()) {
            try {
                if (gate(this::hasDiagnosticWith)) {
                    diagnostic = buildDiagnosticSingular();
                }
            } catch (GalleyException refusal) {
                if (refusal.getCode() != Status.ERROR_SESSION_IN_USE) throw refusal;
            } catch (GalleyClosedException closed) {
                // close() won the in-flight window: the parse's failure stands.
            }
        }
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
        if (status == Status.ERROR_STALE_TREE.getCode()) {
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

    /** {@link #checkStatus} for a call whose non-negative return is the answer. */
    private long statusValue(long status) {
        checkStatus(status);
        return status;
    }

    /**
     * The one reading of "this field does not apply": a field read that
     * reported {@code no_diagnostic} (no diagnostic, or a diagnostic of
     * another kind) leaves the field null or empty. Every other refusal
     * raises.
     */
    private boolean fieldAbsent(long status) {
        if (status == Status.ERROR_NO_DIAGNOSTIC.getCode()) return true;
        checkStatus(status);
        return false;
    }

    /**
     * The one {@code galley_has_diagnostic} read: checks the status and
     * answers the flag; the out-parameter is read only on success.
     */
    private boolean hasDiagnosticWith(MemorySegment sessionHandle) {
        checkStatus(lib.galley_has_diagnostic(sessionHandle, Scratch.local().first));
        return Scratch.local().firstInt() != 0;
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
    private int completeParse(long status, ParseHolder holder) {
        if (status != Status.ERROR_SESSION_IN_USE.getCode()) {
            parseDoor = null;
        }
        Throwable cause = holder.failure;
        if (status < 0) {
            GalleyException failure = parseFailure(status);
            if (status == Status.ERROR_HOOK_FAILED.getCode() && cause != null) failure.initCause(cause);
            throw failure;
        }
        return (int) status;
    }

    /**
     * Single gate for every parse leg: the native call runs through
     * {@link #gate} — the count close refuses on — and the parse is ended
     * afterwards. The hooks were fixed by the last commit, so nothing is
     * synchronized here.
     */
    private int runParse(HandleCall<Long> nativeParse) {
        long status;
        ParseHolder holder = new ParseHolder(this, INNERMOST_HOLDER.get());
        INNERMOST_HOLDER.set(holder);
        try {
            status = gate(nativeParse);
        } catch (Throwable thrown) {
            parseDoor = null;
            throw thrown;
        } finally {
            if (holder.outer == null) INNERMOST_HOLDER.remove();
            else INNERMOST_HOLDER.set(holder.outer);
        }
        return completeParse(status, holder);
    }

    public boolean isClosed() { return closed; }

    /**
     * Calls in flight against the handle: the claim a test waits on before
     * it closes, read under {@code lifetime} so another thread's claim is
     * visible.
     */
    int inFlightCount() {
        synchronized (lifetime) {
            return inFlight;
        }
    }

    /**
     * Closes the session: one transition, under the lock the gate claims on,
     * from open-with-nothing-in-flight to closed. While any call is in flight
     * — a parse from another thread, a node read, a hook's own crossing — it
     * refuses with {@code session in use} and changes nothing: the handle, the
     * registration and the running parse's hook state stay as they were, and
     * the session keeps working. Closing twice is free.
     */
    @Override
    public void close() {
        long refusal = 0;
        boolean closedNow = false;
        synchronized (lifetime) {
            if (closed) return;
            if (inFlight > 0) {
                refusal = Status.ERROR_SESSION_IN_USE.getCode();
            } else if (handle != null && !handle.equals(MemorySegment.NULL)) {
                long status = lib.galley_session_destroy(handle);
                if (status < 0) {
                    refusal = status;
                } else {
                    handle = MemorySegment.NULL;
                    closed = closedNow = true;
                }
            } else {
                closed = closedNow = true;
            }
        }
        if (closedNow) {
            parser.unregister(handleId);
            parseDoor = null;
        }
        if (refusal != 0) throw errorFromStatus(refusal);
    }

    // -- hooks --

    /**
     * Installs a hook on this session only. Takes effect from the next parse.
     * Raises when the artifact does not define {@code name} — an artifact
     * without procedure hooks defines none.
     */
    public void installProcedure(String name, Consumer<ProcedureArguments> hook) {
        HookNames.require(name, hook);
        parser.requireArtifactHook(name);
        Map<String, Consumer<ProcedureArguments>> next = new HashMap<>(hooks);
        next.put(name, hook);
        commitHooks(Map.copyOf(next));
    }

    public void installProcedure(String name, Runnable hook) {
        HookNames.require(name, hook);
        installProcedure(name, (Consumer<ProcedureArguments>) args -> hook.run());
    }

    /**
     * Installs every entry of a scanned map the artifact defines, in one
     * step: only exports whose names begin with {@code reduction}, or with
     * {@code hook} followed by {@code _} or an uppercase letter, are
     * considered; each considered name the artifact does not define is
     * skipped with a warning naming the export, and everything else
     * (helpers, data) is skipped without a word. Returns the number
     * installed.
     */
    public int installProcedures(Map<String, ?> source) {
        if (source == null) return 0;
        Map<String, Consumer<ProcedureArguments>> next = new HashMap<>(hooks);
        int count = parser.installScannedHooks(source, next);
        if (count > 0) commitHooks(Map.copyOf(next));
        return count;
    }

    /**
     * Scans the public static methods of {@code hooks} like a map of its
     * exports, as {@link Parser#installProcedures(Class)} does, onto this
     * session. Returns the number installed.
     */
    public int installProcedures(Class<?> hooks) {
        if (hooks == null) return 0;
        return installProcedures(HookNames.exports(hooks));
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
            checkStatus(gate(sessionHandle -> lib.galley_session_set_hooks(sessionHandle,
                    parser.dispatchStub(), MemorySegment.ofAddress(handleId), enabled, count)));
        }
        hooksByIndex = byIndex;
        hooks = table;
    }

    /**
     * Runs hook {@code index} of the current parse, on the parsing thread.
     * Returns zero, or one when the hook threw: nothing may escape an upcall
     * into the core, so the throwable is kept and the core aborts the parse.
     */
    int dispatchHook(int index, long hook) {
        try {
            runHook(index, hook);
            return 0;
        } catch (Throwable thrown) {
            ParseHolder holder = INNERMOST_HOLDER.get();
            while (holder != null && holder.session != this) holder = holder.outer;
            if (holder != null) holder.failure = thrown;
            return 1;
        }
    }

    private void runHook(int index, long hook) {
        Consumer<ProcedureArguments> callback = hooksByIndex[index];
        if (callback == null) return;
        // The parse's native door and core generation are constant for the
        // parse: read them on its first dispatch, drop them in the finish
        // gate. Only the thread running the hook is recorded per dispatch,
        // which is what lets a call choose its door when it is made.
        NodeDoor hookDoor = parseDoor;
        if (hookDoor == null) {
            try (Arena arena = Arena.ofConfined()) {
                MemorySegment outDoor = arena.allocate(ValueLayout.ADDRESS);
                MemorySegment out = arena.allocate(ValueLayout.JAVA_LONG);
                // A live hook on its own dispatching thread cannot reach this refusal.
                checkStatus(gate(sessionHandle -> lib.galley_procedure_door(sessionHandle, hook, outDoor)));
                MemorySegment door = outDoor.get(ValueLayout.ADDRESS, 0);
                checkStatus(gate(sessionHandle -> lib.galley_hook_generation(door, out)));
                parseGeneration = out.get(ValueLayout.JAVA_LONG, 0);
                hookDoor = NodeDoor.ofHook(lib, this, door);
                parseDoor = hookDoor;
            }
        }
        dispatchThread = hookDoor == null ? null : Thread.currentThread();
        ProcedureArguments arguments = new ProcedureArguments(hook, lib, this, parseGeneration);
        try {
            callback.accept(arguments);
        } finally {
            // The hook's ticket stops naming anything in the core when this
            // call returns, so a kept reference is refused there; nothing to
            // expire here. The tree outlives the hook: its nodes carry the
            // parse's generation, not the hook door.
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
            return runParse(sessionHandle -> lib.galley_parse(sessionHandle, MemorySegment.NULL, 0));
        }
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment dataSeg = arena.allocateFrom(ValueLayout.JAVA_BYTE, input);
            long len = input.length;
            return runParse(sessionHandle -> lib.galley_parse(sessionHandle, dataSeg, len));
        }
    }

    public int parse(ByteBuffer buffer) {
        requireOpen();
        if (buffer == null) throw new IllegalArgumentException("buffer is null");
        int len = buffer.remaining();
        if (len == 0) {
            return runParse(sessionHandle -> lib.galley_parse(sessionHandle, MemorySegment.NULL, 0));
        }
        if (buffer.isDirect()) {
            MemorySegment dataSeg = MemorySegment.ofBuffer(buffer);
            return runParse(sessionHandle -> lib.galley_parse(sessionHandle, dataSeg, len));
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
                return runParse(sessionHandle -> lib.galley_parse(sessionHandle, dataSeg, len));
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
            return runParse(sessionHandle -> lib.galley_parse_file(sessionHandle, cPath));
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
     * Number of AST nodes in the published tree — 0 in a parser built
     * without AST construction, where a live tree has no nodes.
     *
     * @throws StaleTreeException when nothing is published
     */
    public long nodeCount() {
        requireOpen();
        return nodeCount(published()[1]);
    }

    /**
     * The count of the tree {@code generation} names — 0 in a parser built
     * without AST construction, where a live tree has no nodes. The core
     * refuses a generation it does not hold, 0 (nothing published)
     * included, so nothing published is never a zero.
     */
    long nodeCount(long generation) {
        long count = gate(sessionHandle -> lib.galley_node_count(sessionHandle, generation));
        checkStatus(count);
        return count;
    }

    /**
     * The published tree's generation, read from the core in the same call
     * that reads its root. 0 when nothing is published.
     */
    private long[] published() {
        Scratch scratch = Scratch.local();
        checkStatus(gate(sessionHandle -> lib.galley_root_node(sessionHandle, scratch.first, scratch.second)));
        return new long[]{scratch.firstLong(), scratch.secondLong()};
    }

    public void reserveNodes(long capacity) {
        requireOpen();
        long st = gate(sessionHandle -> lib.galley_reserve_nodes(sessionHandle, capacity));
        checkStatus(st);
    }

    /**
     * Current node storage capacity in nodes.
     *
     * @throws GalleyException with {@code ERROR_SESSION_IN_USE} while a parse runs
     */
    public long nodeCapacity() {
        requireOpen();
        long capacity = gate(sessionHandle -> lib.galley_node_capacity(sessionHandle));
        checkStatus(capacity);
        return capacity;
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
     * variables as -1, the flags as in {@link Walker.WalkStep}, and spans index
     * {@link #lastInput()}. Walk {@code parent}/{@code firstChild}/
     * {@code next} directly instead of one call per node;
     * {@link TreeSnapshot#node(long)} is the one conversion from a stored
     * address back to a node.
     *
     * Every leg carries one generation, so a parse that runs in between
     * raises instead of returning columns that mix two trees. In a parser
     * built without AST construction the snapshot is empty: a live tree
     * has no nodes.
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
            MemorySegment recovered = arena.allocate(ValueLayout.JAVA_INT, count);
            long total = gate(sessionHandle -> lib.galley_tree_snapshot(sessionHandle, generation, parent, firstChild, next,
                    childCount, variable, spanStart, spanLen, semantic, recovered, count));
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
            boolean[] recoveredArray = new boolean[(int) count];
            for (int i = 0; i < semanticArray.length; i++) {
                semanticArray[i] = semantic.get(ValueLayout.JAVA_INT, (long) i * Integer.BYTES) != 0;
                recoveredArray[i] = recovered.get(ValueLayout.JAVA_INT, (long) i * Integer.BYTES) != 0;
            }
            return new TreeSnapshot(this, generation, count, parentArray,
                    firstChildArray, nextArray, childCountArray, variableArray,
                    spanStartArray, spanLenArray, semanticArray, recoveredArray);
        }
    }

    /**
     * Retained input of the published parse: the buffer snapshot spans index.
     * Follows the published tree like every node read.
     *
     * @throws StaleTreeException whenever nothing is published, before the
     *         first parse included
     */
    public byte[] lastInput() {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            checkStatus(gate(sessionHandle -> lib.galley_last_input(sessionHandle, outData, outLen)));
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
    Walker startWalk(Node node, boolean skipSemanticErrors, boolean skipRecovered) {
        Crossing crossing = cross(node);
        return new Walker(this, crossing.address(), crossing.generation(), skipSemanticErrors, skipRecovered);
    }

    /**
     * One step of a walk: crosses the door of the calling context — the
     * hook door inside a hook dispatch of this session's running parse,
     * the session door everywhere else — and maps the step onto the
     * walker's contract: the cursor's current address is the yielded node,
     * or {@link Galley#INVALID_NODE} once the walk is done (null), and
     * {@code door.failure} (which maps a stale tree to
     * {@link StaleTreeException}) for a refusal.
     */
    Walker.WalkStep walkerStep(MemorySegment cursor, long generation) {
        requireOpen();
        NodeDoor door = door();
        long status = door.walkStep(cursor);
        if (status < 0) throw door.failure(status);
        long current = WalkCursor.current(cursor);
        if (current == Galley.INVALID_NODE) return null;
        return new Walker.WalkStep(
            new Node(this, current, generation),
            WalkCursor.depth(cursor),
            WalkCursor.isSemanticError(cursor),
            WalkCursor.isRecovered(cursor));
    }

    /**
     * Grammar name of the node's symbol, decoded as UTF-8 with replacement
     * for malformed input. A refused node throws, never answers null. Token
     * content stays raw bytes: use {@link #text} for that.
     */
    public String symbolName(Node node) {
        return new String(symbolNameBytes(node), StandardCharsets.UTF_8);
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

    /**
     * The {line, column} where the published parse ended (zeros when the
     * parser was built without position tracking). Follows the published
     * tree like {@link #lastInput()}.
     *
     * @throws StaleTreeException whenever nothing is published, before the
     *         first parse included
     */
    public int[] lastPosition() {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outLine = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outCol = arena.allocate(ValueLayout.JAVA_INT);
            checkStatus(gate(sessionHandle -> lib.galley_last_position(sessionHandle, outLine, outCol)));
            return new int[]{outLine.get(ValueLayout.JAVA_INT, 0), outCol.get(ValueLayout.JAVA_INT, 0)};
        }
    }

    public boolean hasDiagnostic() {
        requireOpen();
        return gate(this::hasDiagnosticWith);
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
            long st = gate(sessionHandle -> lib.galley_session_set_message_override(sessionHandle,
                    nameSeg, nameBytes.length,
                    msgSeg, message.length));
            checkStatus(st);
        }
    }

    // -- diagnostics helpers --

    /**
     * One diagnostic the snapshot builder reads: the current (last)
     * diagnostic of the published parse, or the diagnostic recorded at
     * {@code index} of it.
     */
    private record DiagnosticSource(boolean recorded, long index) {
        static final DiagnosticSource CURRENT = new DiagnosticSource(false, 0);
        static DiagnosticSource recorded(long index) { return new DiagnosticSource(true, index); }
    }

    private Diagnostic buildDiagnosticSingular() {
        return buildDiagnostic(DiagnosticSource.CURRENT);
    }

    private Diagnostic buildRecordedDiagnostic(long diagIndex) {
        return buildDiagnostic(DiagnosticSource.recorded(diagIndex));
    }

    private Diagnostic buildDiagnostic(DiagnosticSource source) {
        return gate(sessionHandle -> buildDiagnosticWith(source, sessionHandle));
    }

    /**
     * The one diagnostic snapshot builder, for every source: one handle the
     * gate claimed, held for every read the snapshot makes, so the handle
     * stays valid across them. A read the core refuses raises; the one
     * absence a field read may report ({@code no_diagnostic}: no diagnostic,
     * or a diagnostic of another kind) leaves that field null or empty
     * ({@link #fieldAbsent}). Kind, position, and message belong to every
     * diagnostic: their {@code no_diagnostic} is a refusal, never an
     * absence, so they raise like every other status.
     */
    private Diagnostic buildDiagnosticWith(DiagnosticSource source, MemorySegment sessionHandle) {
        boolean recorded = source.recorded();
        long diagIndex = source.index();

        long kind = recorded
                ? statusValue(lib.galley_recorded_diagnostic_kind(sessionHandle, diagIndex))
                : statusValue(lib.galley_diagnostic_kind(sessionHandle));

        long offset;
        int line, col;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outOffset = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outLine = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outCol = arena.allocate(ValueLayout.JAVA_INT);
            checkStatus(recorded
                    ? lib.galley_recorded_diagnostic_position(sessionHandle, diagIndex, outOffset, outLine, outCol)
                    : lib.galley_diagnostic_position(sessionHandle, outOffset, outLine, outCol));
            offset = outOffset.get(ValueLayout.JAVA_LONG, 0);
            line = outLine.get(ValueLayout.JAVA_INT, 0);
            col = outCol.get(ValueLayout.JAVA_INT, 0);
        }

        String message = "";
        String messageAnsi = "";
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outMsg = arena.allocate(ValueLayout.ADDRESS);
            checkStatus(recorded
                    ? lib.galley_recorded_diagnostic_message(sessionHandle, diagIndex, outMsg)
                    : lib.galley_diagnostic_message(sessionHandle, outMsg));
            MemorySegment p = outMsg.get(ValueLayout.ADDRESS, 0);
            if (!p.equals(MemorySegment.NULL)) message = p.reinterpret(Long.MAX_VALUE).getString(0);

            MemorySegment outAnsi = arena.allocate(ValueLayout.ADDRESS);
            checkStatus(recorded
                    ? lib.galley_recorded_diagnostic_message_ansi(sessionHandle, diagIndex, outAnsi)
                    : lib.galley_diagnostic_message_ansi(sessionHandle, outAnsi));
            p = outAnsi.get(ValueLayout.ADDRESS, 0);
            if (!p.equals(MemorySegment.NULL)) messageAnsi = p.reinterpret(Long.MAX_VALUE).getString(0);
        }

        byte[] unexpected = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = recorded
                    ? lib.galley_recorded_unexpected_token(sessionHandle, diagIndex, outData, outLen)
                    : lib.galley_diagnostic_unexpected_token(sessionHandle, outData, outLen);
            if (!fieldAbsent(st)) {
                MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                if (!ptr.equals(MemorySegment.NULL) && len > 0) unexpected = ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
            }
        }

        List<byte[]> expected = new ArrayList<>();
        long expCount = recorded
                ? lib.galley_recorded_expected_count(sessionHandle, diagIndex)
                : lib.galley_diagnostic_expected_count(sessionHandle);
        if (!fieldAbsent(expCount)) {
            for (long i = 0; i < expCount; i++) {
                try (Arena arena = Arena.ofConfined()) {
                    MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
                    MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
                    long st = recorded
                            ? lib.galley_recorded_expected_token(sessionHandle, diagIndex, i, outData, outLen)
                            : lib.galley_diagnostic_expected_at(sessionHandle, i, outData, outLen);
                    if (!fieldAbsent(st)) {
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
        long ctxCount = recorded
                ? lib.galley_recorded_context_count(sessionHandle, diagIndex)
                : lib.galley_diagnostic_context_count(sessionHandle);
        if (!fieldAbsent(ctxCount)) {
            for (long i = 0; i < ctxCount; i++) {
                try (Arena arena = Arena.ofConfined()) {
                    MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
                    MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
                    long st = recorded
                            ? lib.galley_recorded_context_name(sessionHandle, diagIndex, i, outData, outLen)
                            : lib.galley_diagnostic_context_at(sessionHandle, i, outData, outLen);
                    if (!fieldAbsent(st)) {
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

        int syntaxErrorCount = (int) statusValue(lib.galley_syntax_error_count(sessionHandle));
        int semanticErrorCount = (int) statusValue(lib.galley_semantic_error_count(sessionHandle));

        String[] semantic = readSemantic(source, sessionHandle);

        int[] indentation = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outSpaces = arena.allocate(ValueLayout.JAVA_INT);
            MemorySegment outWidth = arena.allocate(ValueLayout.JAVA_INT);
            long st = recorded
                    ? lib.galley_recorded_indentation(sessionHandle, diagIndex, outSpaces, outWidth)
                    : lib.galley_diagnostic_indentation(sessionHandle, outSpaces, outWidth);
            if (!fieldAbsent(st)) {
                indentation = new int[]{outSpaces.get(ValueLayout.JAVA_INT, 0), outWidth.get(ValueLayout.JAVA_INT, 0)};
            }
        }

        RecoveryTarget recoveryKind = null;
        long rk = statusValue(recorded
                ? lib.galley_recorded_diagnostic_recovery_kind(sessionHandle, diagIndex)
                : lib.galley_diagnostic_recovery_kind(sessionHandle));
        if (rk != 0) recoveryKind = RecoveryTarget.fromCode(rk);

        // Absent stays null: a field read that reports no_diagnostic is the
        // field not applying, and anything else it reports raises.
        byte[] recoveryTerminal = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = recorded
                    ? lib.galley_recorded_recovery_terminal(sessionHandle, diagIndex, outData, outLen)
                    : lib.galley_diagnostic_recovery_terminal(sessionHandle, outData, outLen);
            if (!fieldAbsent(st)) {
                MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
                long len = outLen.get(ValueLayout.JAVA_LONG, 0);
                if (!ptr.equals(MemorySegment.NULL) && len > 0) recoveryTerminal = ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
            }
        }

        ResumeSide recoveryResume = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outResume = arena.allocate(ValueLayout.JAVA_LONG);
            long st = recorded
                    ? lib.galley_recorded_recovery_resume(sessionHandle, diagIndex, outResume)
                    : lib.galley_diagnostic_recovery_resume(sessionHandle, outResume);
            if (!fieldAbsent(st)) {
                recoveryResume = ResumeSide.fromCode(outResume.get(ValueLayout.JAVA_LONG, 0));
            }
        }

        String recoveryLhs = null;
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = recorded
                    ? lib.galley_recorded_recovery_lhs_variable(sessionHandle, diagIndex, outData, outLen)
                    : lib.galley_diagnostic_recovery_lhs_variable(sessionHandle, outData, outLen);
            if (!fieldAbsent(st)) {
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
            long st = recorded
                    ? lib.galley_recorded_recovery_production(sessionHandle, diagIndex, outVar, outVarLen, outIdx)
                    : lib.galley_diagnostic_recovery_production(sessionHandle, outVar, outVarLen, outIdx);
            if (!fieldAbsent(st)) {
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
            long st = recorded
                    ? lib.galley_recorded_recovery_occurrence(sessionHandle, diagIndex, outParent, outParentLen, outRhs, outSym, outVar, outVarLen)
                    : lib.galley_diagnostic_recovery_occurrence(sessionHandle, outParent, outParentLen, outRhs, outSym, outVar, outVarLen);
            if (!fieldAbsent(st)) {
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

        return new Diagnostic(DiagnosticKind.fromCode(kind), offset, line, col, message, messageAnsi, unexpected, expected, context,
                contextBytes,
                syntaxErrorCount, semanticErrorCount, semantic, indentation, recoveryKind, recoveryTerminal, recoveryResume,
                recoveryLhs, recoveryProd, recoveryOcc);
    }

    /**
     * The semantic variable and message of the snapshot's diagnostic, or
     * null when the source has no diagnostic or it is not a semantic error
     * ({@link #fieldAbsent}); every other refusal raises.
     */
    private String[] readSemantic(DiagnosticSource source, MemorySegment sessionHandle) {
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outVar = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outVarLen = arena.allocate(ValueLayout.JAVA_LONG);
            MemorySegment outMsg = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outMsgLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = source.recorded()
                    ? lib.galley_recorded_semantic(sessionHandle, source.index(), outVar, outVarLen, outMsg, outMsgLen)
                    : lib.galley_diagnostic_semantic(sessionHandle, outVar, outVarLen, outMsg, outMsgLen);
            if (fieldAbsent(st)) return null;
            MemorySegment vb = outVar.get(ValueLayout.ADDRESS, 0);
            long vl = outVarLen.get(ValueLayout.JAVA_LONG, 0);
            MemorySegment mb = outMsg.get(ValueLayout.ADDRESS, 0);
            long ml = outMsgLen.get(ValueLayout.JAVA_LONG, 0);
            // Contract: on success both written pointers are non-null — the
            // variable is grammar-static, the message arena-copied. A null
            // pointer is a core contract violation, never absence.
            if (vb.equals(MemorySegment.NULL) || mb.equals(MemorySegment.NULL)) {
                throw new IllegalStateException("galley answered a semantic diagnostic with a null payload pointer");
            }
            return new String[]{
                    new String(vb.reinterpret(vl).toArray(ValueLayout.JAVA_BYTE), StandardCharsets.UTF_8),
                    new String(mb.reinterpret(ml).toArray(ValueLayout.JAVA_BYTE), StandardCharsets.UTF_8)};
        }
    }

    /**
     * The most recent parse's diagnostic, or null when none was recorded.
     * The error counts are the parse's totals, read from the session door
     * ({@code galley_syntax_error_count} / {@code galley_semantic_error_count}),
     * never a per-diagnostic tally.
     */
    public Diagnostic diagnostic() {
        requireOpen();
        if (!gate(this::hasDiagnosticWith)) return null;
        return buildDiagnosticSingular();
    }

    /**
     * Every diagnostic the most recent parse recorded, in recording order.
     * Each snapshot carries the parse's totals in
     * {@link Diagnostic#getSyntaxErrorCount()} / {@link Diagnostic#getSemanticErrorCount()}:
     * the session-door values, identical to the current snapshot's.
     */
    public List<Diagnostic> diagnostics() {
        requireOpen();
        long count = statusValue(gate(sessionHandle -> lib.galley_recorded_diagnostic_count(sessionHandle)));
        List<Diagnostic> out = new ArrayList<>((int) count);
        for (long i = 0; i < count; i++) {
            out.add(buildRecordedDiagnostic(i));
        }
        return out;
    }

    // -- tree editing --

    public void appendChildren(Node parent, Node chain) {
        Crossing crossing = cross(parent);
        crossing.door().appendChildren(crossing.generation(), crossing.address(), chain.generation(), address(chain));
    }

    public void insertBefore(Node target, Node chain) {
        Crossing crossing = cross(target);
        crossing.door().insertBefore(crossing.generation(), crossing.address(), chain.generation(), address(chain));
    }

    public void insertAfter(Node target, Node chain) {
        Crossing crossing = cross(target);
        crossing.door().insertAfter(crossing.generation(), crossing.address(), chain.generation(), address(chain));
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
        crossing.door().insertChildrenAt(crossing.generation(), crossing.address(), index, chain.generation(), address(chain));
    }

    public Node removeChildrenAt(Node parent, int index, int count) {
        Crossing crossing = cross(parent);
        return node(crossing.door().removeChildrenAt(crossing.generation(), crossing.address(), index, count), crossing.generation());
    }

    // -- symbol table --

    /**
     * Grammar name of the symbol at table {@code index}, decoded as UTF-8
     * with replacement for malformed input. A refused read throws, never
     * answers null.
     *
     * @throws GalleyException with {@code ERROR_OUT_OF_RANGE} for an index at
     *         or past {@link #symbolCount()}
     */
    public String symbolNameAt(long index) {
        return new String(symbolNameAtBytes(index), StandardCharsets.UTF_8);
    }

    /** Raw bytes behind {@link #symbolNameAt(long)}. */
    public byte[] symbolNameAtBytes(long index) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = gate(sessionHandle -> lib.galley_symbol_name(sessionHandle, index, outData, outLen));
            statusValue(st);
            MemorySegment ptr = outData.get(ValueLayout.ADDRESS, 0);
            long len = outLen.get(ValueLayout.JAVA_LONG, 0);
            if (ptr.equals(MemorySegment.NULL) || len == 0) return new byte[0];
            return ptr.reinterpret(len).toArray(ValueLayout.JAVA_BYTE);
        }
    }

    /**
     * Whether the symbol at table {@code index} is a terminal.
     *
     * @throws GalleyException with {@code ERROR_OUT_OF_RANGE} for an index at
     *         or past {@link #symbolCount()}
     */
    public boolean symbolIsTerminal(long index) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outIsTerminal = arena.allocate(ValueLayout.JAVA_INT);
            checkStatus(gate(sessionHandle -> lib.galley_symbol_is_terminal(sessionHandle, index, outIsTerminal)));
            return outIsTerminal.get(ValueLayout.JAVA_INT, 0) != 0;
        }
    }

    /**
     * Grammar name of the variable at table {@code index}, decoded as UTF-8
     * with replacement for malformed input. A refused read throws, never
     * answers null.
     *
     * @throws GalleyException with {@code ERROR_OUT_OF_RANGE} for an index at
     *         or past {@link #variableCount()}
     */
    public String variableNameAt(long index) {
        return new String(variableNameAtBytes(index), StandardCharsets.UTF_8);
    }

    /** Raw bytes behind {@link #variableNameAt(long)}. */
    public byte[] variableNameAtBytes(long index) {
        requireOpen();
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment outData = arena.allocate(ValueLayout.ADDRESS);
            MemorySegment outLen = arena.allocate(ValueLayout.JAVA_LONG);
            long st = gate(sessionHandle -> lib.galley_variable_name(sessionHandle, index, outData, outLen));
            statusValue(st);
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

    public boolean sourceRetentionEnabled() { return parser.sourceRetentionEnabled(); }

    public boolean hasPositionTracking() { return parser.hasPositionTracking(); }

    public boolean hasInputStreaming() { return parser.hasInputStreaming(); }

    public boolean usesVerbatim() { return parser.usesVerbatim(); }

    public boolean stackOverflowRecoveryAvailable() { return parser.stackOverflowRecoveryAvailable(); }

    public long symbolCount() { return parser.symbolCount(); }

    public long variableCount() { return parser.variableCount(); }

    public String statusString(long status) { return parser.statusString(status); }

    public String statusString(Status status) { return parser.statusString(status); }

    GalleyLibrary getLibrary() { return lib; }
}
