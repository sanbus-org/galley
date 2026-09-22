package org.sanbus.galley;

import java.lang.foreign.Arena;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.ValueLayout;
import java.lang.invoke.MethodHandles;
import java.nio.charset.StandardCharsets;
import java.util.ArrayDeque;
import java.util.Collections;
import java.util.Deque;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Consumer;

import org.sanbus.galley.internal.GalleyLibrary;

/**
 * Loaded parser handle: the artifact-level namespace sessions open from.
 *
 * Owns one hook table shared by every session of the artifact. Acquire with
 * {@link Galley#load}, install hooks, then open sessions. Parsers are cached
 * by canonical artifact path for the process lifetime and the native library
 * cannot unload, so this handle is not closeable.
 *
 * Threading: sessions are confined to one thread each, and two sessions of
 * one parser must never parse concurrently — native hook gates are
 * artifact-global, so concurrent same-parser parses would race regardless
 * of host-side locking.
 */
public final class Parser {

    private final String canonicalPath;
    private final GalleyLibrary lib;
    private final ConcurrentHashMap<String, Consumer<ProcedureArguments>> hooks = new ConcurrentHashMap<>();
    // Entry-dispatch stack: one snapshot per active parse level (innermost
    // last), mirroring Python's gate_snapshots and the JS entry table.
    // Dispatch reads the innermost snapshot so mid-parse installs and
    // clears apply to later parses only; nested parses push their own and
    // the enclosing table is restored on unwind.
    private final Deque<Map<String, Consumer<ProcedureArguments>>> dispatchStack = new ArrayDeque<>();
    // Reachability root: keeps this parser's upcall stub alive (the global arena pins it regardless).
    private MemorySegment dispatchStub = MemorySegment.NULL;

    private Parser(String canonicalPath, GalleyLibrary lib) {
        this.canonicalPath = canonicalPath;
        this.lib = lib;
    }

    /**
     * Fully-wired parser: the only construction path. Installs the upcall
     * stub before returning so no half-built parser (stubless, hooks inert)
     * can ever escape.
     */
    static Parser create(String canonicalPath, GalleyLibrary lib) {
        Parser parser = new Parser(canonicalPath, lib);
        parser.installDispatchStub();
        return parser;
    }

    /**
     * Installs this parser's upcall stub. Called once by {@link #create} for
     * the cache winner only, so racing loads never leave a loser's stub
     * installed natively.
     */
    private void installDispatchStub() {
        MemorySegment stub;
        try {
            var handle = MethodHandles.lookup().findVirtual(Parser.class, "dispatch",
                    java.lang.invoke.MethodType.methodType(void.class, MemorySegment.class, long.class, MemorySegment.class));
            stub = lib.createJavaDispatchStub(handle.bindTo(this), Arena.global());
            lib.galley_install_java_dispatch(stub);
        } catch (NoSuchMethodException | IllegalAccessException e) {
            throw new RuntimeException(e);
        } catch (Exception e) {
            // Library built without the Java shim: hooks stay inert.
            System.err.println("galley: no Java dispatch in " + canonicalPath + "; procedure hooks stay inert");
            stub = MemorySegment.NULL;
        }
        this.dispatchStub = stub;
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

    public void installProcedure(String name, Consumer<ProcedureArguments> hook) {
        if (name == null || hook == null) throw new IllegalArgumentException("name and hook required");
        if (!isHookName(name)) {
            warnIfNearMissHook(name);
            return;
        }
        hooks.put(name, hook);
    }

    public void installProcedure(String name, Runnable hook) {
        if (name == null || hook == null) throw new IllegalArgumentException("name and hook required");
        if (!isHookName(name)) {
            warnIfNearMissHook(name);
            return;
        }
        hooks.put(name, args -> hook.run());
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
            String name = entry.getKey();
            if (!isHookName(name)) {
                warnIfNearMissHook(name);
                continue;
            }
            Consumer<ProcedureArguments> hook = toHook(entry.getValue());
            if (hook == null) continue;
            hooks.put(name, hook);
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

    /**
     * Entry-table snapshot of the live hook table: one parse's dispatch
     * view. Installs and clears made mid-parse apply to later parses only.
     */
    Map<String, Consumer<ProcedureArguments>> snapshotHooks() {
        return new HashMap<>(hooks);
    }

    /** Pushes a parse level's entry table; restored by {@link #popDispatchTable}. */
    void pushDispatchTable(Map<String, Consumer<ProcedureArguments>> table) {
        dispatchStack.push(new HashMap<>(table));
    }

    /** Pops a parse level's entry table, restoring the enclosing one. */
    void popDispatchTable() {
        dispatchStack.poll();
    }

    /**
     * Selective dispatch sync (the single gate every parse leg calls):
     * clears every native procedure gate, then enables exactly the names
     * in the entry table. Missing symbols are no-ops.
     */
    void syncGates(Map<String, Consumer<ProcedureArguments>> table) {
        lib.galley_java_procedure_clear();
        if (table == null || table.isEmpty()) return;
        for (String name : table.keySet()) {
            byte[] bytes = name.getBytes(StandardCharsets.UTF_8);
            try (Arena arena = Arena.ofConfined()) {
                MemorySegment seg = arena.allocateFrom(ValueLayout.JAVA_BYTE, bytes);
                lib.galley_java_procedure_enable(seg, bytes.length);
            }
        }
    }

    GalleyLibrary library() { return lib; }

    String statusString(long status) { return lib.galley_status_string(status); }

    String statusString(StatusCode status) {
        if (status == null) return null;
        return lib.galley_status_string(status.getCode());
    }

    // Called by this parser's upcall stub.
    private void dispatch(MemorySegment namePtr, long nameLen, MemorySegment argsPtr) {
        try {
            if (namePtr.equals(MemorySegment.NULL) || argsPtr.equals(MemorySegment.NULL)) return;
            byte[] nameBytes = namePtr.reinterpret(nameLen).toArray(ValueLayout.JAVA_BYTE);
            String name = new String(nameBytes, StandardCharsets.UTF_8);
            // Dispatch reads the innermost entry snapshot (the live table
            // when no parse is active), so mid-parse installs and clears
            // stay invisible in-flight. Hook throwables are logged and
            // swallowed so a throwing hook never aborts the parse.
            Map<String, Consumer<ProcedureArguments>> table = dispatchStack.peek();
            if (table == null) table = hooks;
            if (table.isEmpty()) return;
            Consumer<ProcedureArguments> hook = table.get(name);
            if (hook == null) return;
            ProcedureArguments args = new ProcedureArguments(argsPtr, lib);
            try {
                hook.accept(args);
            } catch (Throwable t) {
                t.printStackTrace(System.err);
            }
        } catch (Throwable t) {
            t.printStackTrace(System.err);
        }
    }

    private static Consumer<ProcedureArguments> toHook(Object value) {
        if (value instanceof Consumer) {
            @SuppressWarnings("unchecked")
            Consumer<ProcedureArguments> hook = (Consumer<ProcedureArguments>) value;
            return hook;
        }
        if (value instanceof Runnable task) return args -> task.run();
        return null;
    }

    private static boolean isHookName(String name) {
        return name != null
                && (name.equals("reduction") || name.startsWith("reduction_") || name.startsWith("hook_"));
    }

    /**
     * True for names that look like mistyped hooks ({@code reductionPair},
     * {@code hookPrint}, {@code reducton_X}): a warning, not an install.
     * Anything else (helpers, data) stays silent. Mirrors the JS
     * {@code isNearMissHookName}.
     */
    private static boolean isNearMissHookName(String name) {
        if (name == null || isHookName(name)) return false;
        String lower = name.toLowerCase(Locale.ROOT);
        return lower.startsWith("reduct") || lower.startsWith("hook");
    }

    /** Warns on a skipped name that looks like a mistyped hook. */
    private static void warnIfNearMissHook(String name) {
        if (!isNearMissHookName(name)) return;
        System.err.println("galley: ignoring export \"" + name
                + "\": procedure hooks must be named reduction, reduction_*, or hook_*.");
    }
}
