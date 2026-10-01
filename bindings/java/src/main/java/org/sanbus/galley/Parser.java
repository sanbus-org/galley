package org.sanbus.galley;

import java.lang.foreign.Arena;
import java.lang.foreign.MemorySegment;
import java.lang.invoke.MethodHandles;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.Consumer;

import org.sanbus.galley.internal.GalleyLibrary;

/**
 * Loaded parser: the artifact-level namespace sessions open from.
 *
 * Owns the default hook table: every session opened from the parser starts
 * with a copy and owns that copy from then on (see {@link Session}), so
 * installs here reach sessions opened later, never sessions already open.
 * Acquire with {@link Galley#load}, install hooks, then open sessions.
 * Parsers are cached by canonical artifact path for the process lifetime
 * and the native library cannot unload, so a parser is not closeable.
 *
 * Threading: sessions are confined to one thread each. Sessions of one
 * parser may parse concurrently on different threads: each carries its own
 * hooks, so nothing about hook dispatch is shared between them. Hooks run on
 * the parsing thread and must be thread-safe if they share state.
 */
public final class Parser {

    private final String canonicalPath;
    private final GalleyLibrary lib;
    private final ConcurrentHashMap<String, Consumer<ProcedureArguments>> hooks = new ConcurrentHashMap<>();
    /** Hook index by hook name, from the library's own hook list. */
    private final Map<String, Integer> hookIndexes;
    /** Open sessions by native handle, so the one dispatch stub routes each hook to its session. */
    private final ConcurrentHashMap<Long, Session> sessions = new ConcurrentHashMap<>();
    private final AtomicLong nextHandle = new AtomicLong(1);
    // Reachability root: keeps this parser's upcall stub alive (the global arena pins it regardless).
    private final MemorySegment dispatchStub;

    private Parser(String canonicalPath, GalleyLibrary lib) {
        this.canonicalPath = canonicalPath;
        this.lib = lib;
        Map<String, Integer> indexes = new HashMap<>();
        long count = lib.galley_hooks_count();
        for (int index = 0; index < count; index++) indexes.put(lib.galley_hooks_name(index), index);
        this.hookIndexes = Map.copyOf(indexes);
        if (count == 0) {
            System.err.println("galley: " + canonicalPath + " forwards no hooks to the host; procedure hooks stay inert");
        }
        try {
            var handle = MethodHandles.lookup().findVirtual(Parser.class, "dispatch",
                    java.lang.invoke.MethodType.methodType(void.class, MemorySegment.class, int.class, MemorySegment.class));
            this.dispatchStub = lib.createDispatchStub(handle.bindTo(this), Arena.global());
        } catch (NoSuchMethodException | IllegalAccessException e) {
            throw new RuntimeException(e);
        }
    }

    static Parser create(String canonicalPath, GalleyLibrary lib) {
        return new Parser(canonicalPath, lib);
    }

    /** Canonical artifact path this parser was loaded from. */
    public String canonicalPath() { return canonicalPath; }

    public Session openSession() { return new Session(this); }

    public Session openSession(SessionOptions options) { return new Session(this, options); }

    // -- parser metadata (bound to this artifact's own library) --

    public String version() { return lib.galley_version(); }

    public ParserType parserType() { return ParserType.fromCode(lib.galley_parser_type()); }

    public RecoveryMode errorRecoveryMode() { return RecoveryMode.fromCode(lib.galley_error_recovery_mode()); }

    public boolean hasAst() { return lib.galley_has_ast() != 0; }

    public boolean hasProcedures() { return lib.galley_has_procedures() != 0; }

    public boolean allowsNoAstTreeProcedures() { return lib.galley_allows_no_ast_tree_procedures() != 0; }

    public boolean sourceRetentionEnabled() { return lib.galley_source_retention_enabled() != 0; }

    public boolean hasPositionTracking() { return lib.galley_has_position_tracking() != 0; }

    public boolean hasInputStreaming() { return lib.galley_has_input_streaming() != 0; }

    public boolean usesVerbatim() { return lib.galley_uses_verbatim() != 0; }

    public boolean stackOverflowRecoveryAvailable() { return lib.galley_stack_overflow_recovery_available() != 0; }

    public long symbolCount() { return lib.galley_symbol_count(); }

    public long variableCount() { return lib.galley_variable_count(); }

    /** Installs a default hook: reaches sessions opened after this call. */
    public void installProcedure(String name, Consumer<ProcedureArguments> hook) {
        HookNames.require(name, hook);
        if (HookNames.accepts(name)) hooks.put(name, hook);
    }

    public void installProcedure(String name, Runnable hook) {
        HookNames.require(name, hook);
        if (HookNames.accepts(name)) hooks.put(name, args -> hook.run());
    }

    /**
     * Installs every hook-shaped entry ({@code reduction},
     * {@code reduction_*}, {@code hook_*}) whose value is a
     * {@code Consumer<ProcedureArguments>} or a {@code Runnable}.
     * Near-miss names warn and anything else is silently ignored.
     * Returns the number installed.
     */
    public int installProcedures(Map<String, ?> source) {
        if (source == null) return 0;
        int count = 0;
        for (Map.Entry<String, ?> entry : source.entrySet()) {
            if (!HookNames.accepts(entry.getKey())) continue;
            Consumer<ProcedureArguments> hook = HookNames.toHook(entry.getValue());
            if (hook == null) continue;
            hooks.put(entry.getKey(), hook);
            count++;
        }
        return count;
    }

    public Map<String, Consumer<ProcedureArguments>> listProcedures() {
        return Collections.unmodifiableMap(new HashMap<>(hooks));
    }

    public Consumer<ProcedureArguments> lookupProcedure(String name) {
        if (name == null) return null;
        return hooks.get(name);
    }

    public void clearProcedures() {
        hooks.clear();
    }

    /** A new session's starting hook table: a copy of the defaults, owned by that session. */
    Map<String, Consumer<ProcedureArguments>> defaultHooks() {
        return Map.copyOf(hooks);
    }

    /** Number of hooks the library forwards. */
    int hookCount() { return hookIndexes.size(); }

    /** The library's index for a hook name, or -1 when the grammar has no such hook. */
    int hookIndex(String name) {
        Integer index = hookIndexes.get(name);
        return index == null ? -1 : index;
    }

    MemorySegment dispatchStub() { return dispatchStub; }

    /** Registers an open session and returns the handle the library hands back with each of its hooks. */
    long register(Session session) {
        long handle = nextHandle.getAndIncrement();
        sessions.put(handle, session);
        return handle;
    }

    void unregister(long handle) {
        sessions.remove(handle);
    }

    GalleyLibrary library() { return lib; }

    String statusString(long status) { return lib.galley_status_string(status); }

    String statusString(StatusCode status) {
        if (status == null) return null;
        return lib.galley_status_string(status.getCode());
    }

    // Called by this parser's upcall stub on the parsing thread: routes the
    // hook to the session whose handle the library passed.
    private void dispatch(MemorySegment handle, int index, MemorySegment arguments) {
        try {
            if (arguments.equals(MemorySegment.NULL)) return;
            Session session = sessions.get(handle.address());
            if (session != null) session.dispatchHook(index, arguments);
        } catch (Throwable t) {
            t.printStackTrace(System.err);
        }
    }
}
