package org.sanbus.galley;

import java.lang.foreign.Arena;
import java.lang.foreign.MemorySegment;
import java.lang.invoke.MethodHandles;
import java.lang.ref.WeakReference;
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
 * Every load yields a parser of its own, so two parsers of one artifact
 * never share their default hook tables. The native library is shared
 * across the parsers of one artifact and cannot unload, so a parser is not
 * closeable.
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
    // This parser's upcall stub, in an automatic arena the stub's segment keeps alive: the parser
    // holds it, and the stub is freed once the parser is unreachable.
    private final MemorySegment dispatchStub;

    private Parser(String canonicalPath, GalleyLibrary lib) {
        this.canonicalPath = canonicalPath;
        this.lib = lib;
        Map<String, Integer> indexes = new HashMap<>();
        long count = lib.galley_hooks_count();
        for (int index = 0; index < count; index++) indexes.put(lib.galley_hooks_name(index), index);
        this.hookIndexes = Map.copyOf(indexes);
        try {
            var handle = MethodHandles.lookup().findVirtual(Router.class, "dispatch",
                    java.lang.invoke.MethodType.methodType(int.class, MemorySegment.class, int.class, long.class));
            this.dispatchStub = lib.createDispatchStub(handle.bindTo(new Router(this)), Arena.ofAuto());
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

    /** The library's text for a status code, or {@code null} when it names none. */
    public String statusString(long status) { return lib.galley_status_string(status); }

    public String statusString(StatusCode status) {
        if (status == null) return null;
        return lib.galley_status_string(status.getCode());
    }

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

    // Called through this parser's upcall stub on the parsing thread: routes
    // the hook to the session whose handle the library passed. Returns zero
    // to let the parse go on and nonzero when the hook failed; nothing
    // escapes into the core, because the session keeps what its hook threw.
    private int dispatch(MemorySegment handle, int index, long hook) {
        Session session = sessions.get(handle.address());
        return session == null ? 1 : session.dispatchHook(index, hook);
    }

    /**
     * The stub's call target. The runtime keeps a stub's target strongly
     * reachable until the stub is freed, so the target must not own the
     * parser or the stub would pin it forever. A hook can only arrive from
     * an open session, which keeps its parser reachable, so the reference
     * is live whenever a hook fires.
     */
    private static final class Router {
        private final WeakReference<Parser> parser;

        Router(Parser parser) { this.parser = new WeakReference<>(parser); }

        int dispatch(MemorySegment handle, int index, long hook) {
            Parser target = parser.get();
            return target == null ? 1 : target.dispatch(handle, index, hook);
        }
    }
}
