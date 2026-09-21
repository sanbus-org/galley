package org.sanbus.galley;

import java.lang.foreign.Arena;
import java.lang.foreign.MemorySegment;
import java.lang.foreign.ValueLayout;
import java.lang.invoke.MethodHandles;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Consumer;

import org.sanbus.galley.internal.GalleyLibrary;
import org.sanbus.galley.internal.GalleyLibraryLoader;

/**
 * Loaded parser handle: the artifact-level namespace sessions open from.
 *
 * Owns one hook table shared by every session of the artifact. Acquire with
 * {@link Galley#load}, install hooks, then open sessions. Parsers are cached
 * by canonical artifact path for the process lifetime and the native library
 * cannot unload, so this handle is not closeable.
 */
public final class Parser {

    private final String canonicalPath;
    private final GalleyLibrary lib;
    private final ConcurrentHashMap<String, Consumer<ProcedureArguments>> hooks = new ConcurrentHashMap<>();
    // Reachability root: keeps this parser's upcall stub alive (the global arena pins it regardless).
    private final MemorySegment dispatchStub;

    Parser(String canonicalPath) {
        this.canonicalPath = canonicalPath;
        this.lib = GalleyLibraryLoader.load(canonicalPath);
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

    public int parserType() { return (int) lib.galley_parser_type(); }

    public int errorRecoveryMode() { return (int) lib.galley_error_recovery_mode(); }

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
        hooks.put(name, hook);
    }

    public void installProcedure(String name, Runnable hook) {
        if (name == null || hook == null) throw new IllegalArgumentException("name and hook required");
        hooks.put(name, args -> hook.run());
    }

    /**
     * Installs every hook-shaped entry ({@code reduction},
     * {@code reduction_*}, {@code hook_*}) whose value is a
     * {@code Consumer<ProcedureArguments>} or a {@code Runnable}.
     * Anything else is ignored. Returns the number installed.
     */
    public int installProcedures(Map<String, ?> source) {
        if (source == null) return 0;
        int count = 0;
        for (Map.Entry<String, ?> entry : source.entrySet()) {
            String name = entry.getKey();
            Consumer<ProcedureArguments> hook = toHook(entry.getValue());
            if (hook == null || !isHookName(name)) continue;
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
     * Selective dispatch sync (the single gate every parse leg calls):
     * clears every native procedure gate, then enables exactly the
     * registered names. Missing symbols are no-ops.
     */
    void syncGates() {
        lib.galley_java_procedure_clear();
        if (hooks.isEmpty()) return;
        for (String name : hooks.keySet()) {
            byte[] bytes = name.getBytes(StandardCharsets.UTF_8);
            try (Arena arena = Arena.ofConfined()) {
                MemorySegment seg = arena.allocateFrom(ValueLayout.JAVA_BYTE, bytes);
                lib.galley_java_procedure_enable(seg, bytes.length);
            }
        }
    }

    GalleyLibrary library() { return lib; }

    String statusString(long status) { return lib.galley_status_string(status); }

    // Called by this parser's upcall stub.
    private void dispatch(MemorySegment namePtr, long nameLen, MemorySegment argsPtr) {
        try {
            if (hooks.isEmpty() || namePtr.equals(MemorySegment.NULL) || argsPtr.equals(MemorySegment.NULL)) return;
            byte[] nameBytes = namePtr.reinterpret(nameLen).toArray(ValueLayout.JAVA_BYTE);
            String name = new String(nameBytes, StandardCharsets.UTF_8);
            Consumer<ProcedureArguments> hook = hooks.get(name);
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
}
