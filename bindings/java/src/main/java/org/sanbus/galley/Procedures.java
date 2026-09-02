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
 * Registry for Java procedure hooks. Mirrors Python's galley.install_procedure
 * and TypeScript's installProcedure.
 *
 * Hooks are registered per library load (global). The underlying shared
 * library's shim contains one dispatch slot; this class installs a single
 * Panama upcall stub that looks up the name and invokes the Java hook.
 */
public final class Procedures {

    private static final ConcurrentHashMap<String, Consumer<ProcedureArguments>> TABLE = new ConcurrentHashMap<>();
    private static volatile MemorySegment dispatchStub = MemorySegment.NULL;
    private static volatile Arena dispatchArena = null;
    private static volatile GalleyLibrary installedLib = null;
    private static final Object LOCK = new Object();

    static final ConcurrentHashMap<Long, Session> SESSION_MAP = new ConcurrentHashMap<>();

    private Procedures() {}

    // Called by upcall stub
    public static void dispatch(MemorySegment namePtr, long nameLen, MemorySegment argsPtr) {
        try {
            if (TABLE.isEmpty() || namePtr.equals(MemorySegment.NULL) || argsPtr.equals(MemorySegment.NULL)) return;
            byte[] nameBytes = namePtr.reinterpret(nameLen).toArray(ValueLayout.JAVA_BYTE);
            String name = new String(nameBytes, StandardCharsets.UTF_8);
            Consumer<ProcedureArguments> hook = TABLE.get(name);
            if (hook == null) return;
            // Need lib reference for ProcedureArguments — use installedLib global or lookup via session
            GalleyLibrary lib = installedLib;
            if (lib == null) {
                try { lib = GalleyLibraryLoader.load(); } catch (Exception ignored) { return; }
            }
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

    private static void ensureDispatchFor(GalleyLibrary lib) {
        if (lib == null) return;
        synchronized (LOCK) {
            if (dispatchStub != null && !dispatchStub.equals(MemorySegment.NULL) && lib == installedLib) return;
            try {
                if (dispatchArena == null || !dispatchArena.scope().isAlive()) {
                    dispatchArena = Arena.global();
                }
                var mh = MethodHandles.lookup().findStatic(Procedures.class, "dispatch",
                        java.lang.invoke.MethodType.methodType(void.class, MemorySegment.class, long.class, MemorySegment.class));
                MemorySegment stub = lib.createJavaDispatchStub(mh, dispatchArena);
                lib.galley_install_java_dispatch(stub);
                dispatchStub = stub;
                installedLib = lib;
            } catch (NoSuchMethodException | IllegalAccessException e) {
                throw new RuntimeException(e);
            } catch (Exception e) {
                // Library was built without Java shim (C procedure or no-procedures) - leave no-op
            }
        }
    }

    public static void ensureDispatchForCurrentLibrary() {
        try {
            GalleyLibrary lib = GalleyLibraryLoader.load();
            ensureDispatchFor(lib);
        } catch (Exception ignored) {}
    }

    public static void ensureDispatchFor(GalleyLibrary lib, String libPath) {
        ensureDispatchFor(lib);
    }

    public static void installProcedure(String name, Consumer<ProcedureArguments> callable) {
        if (name == null || callable == null) throw new IllegalArgumentException("name and callable required");
        TABLE.put(name, callable);
        try {
            GalleyLibrary lib = GalleyLibraryLoader.load();
            ensureDispatchFor(lib);
        } catch (Exception e) {
        }
    }

    public static void installProcedure(String name, Runnable callable) {
        installProcedure(name, args -> callable.run());
    }

    public static int installProcedures(Object source) {
        if (source == null) return 0;
        int count = 0;
        Map<String, Object> map = null;
        if (source instanceof Map) {
            @SuppressWarnings("unchecked")
            Map<String, Object> m = (Map<String, Object>) source;
            map = m;
        } else {
            map = new HashMap<>();
            Class<?> cls = source.getClass();
            for (java.lang.reflect.Field f : cls.getFields()) {
                try {
                    Object val = f.get(source);
                    if (val != null) map.put(f.getName(), val);
                } catch (Exception ignored) {}
            }
            for (java.lang.reflect.Method m : cls.getMethods()) {
                String n = m.getName();
                if (n.startsWith("reduction_") || n.equals("reduction") || n.startsWith("hook_")) {
                    try {
                        map.putIfAbsent(n, (Consumer<ProcedureArguments>) args -> {
                            try {
                                if (m.getParameterCount() == 0) m.invoke(source);
                                else if (m.getParameterCount() == 1) m.invoke(source, args);
                                else m.invoke(source);
                            } catch (Exception e) { throw new RuntimeException(e); }
                        });
                    } catch (Exception ignored) {}
                }
            }
            if (map.isEmpty()) {
                for (java.lang.reflect.Field f : cls.getDeclaredFields()) {
                    try {
                        f.setAccessible(true);
                        Object val = f.get(source);
                        if (val != null && val instanceof Consumer) {
                            map.put(f.getName(), val);
                        }
                    } catch (Exception ignored) {}
                }
            }
        }
        for (Map.Entry<String, Object> e : map.entrySet()) {
            String name = e.getKey();
            Object val = e.getValue();
            if (!(val instanceof Consumer)) continue;
            boolean isHook = name.equals("reduction") || name.startsWith("reduction_") || name.startsWith("hook_");
            if (!isHook) continue;
            @SuppressWarnings("unchecked")
            Consumer<ProcedureArguments> c = (Consumer<ProcedureArguments>) val;
            TABLE.put(name, c);
            count++;
        }
        if (count > 0) {
            try {
                GalleyLibrary lib = GalleyLibraryLoader.load();
                ensureDispatchFor(lib);
            } catch (Exception ignored) {}
        }
        return count;
    }

    public static void clearProcedures() {
        TABLE.clear();
    }

    public static Map<String, Consumer<ProcedureArguments>> listProcedures() {
        return Collections.unmodifiableMap(new HashMap<>(TABLE));
    }

    static void ensureForLibrary(GalleyLibrary lib) {
        ensureDispatchFor(lib);
    }

    static void registerSession(long ptrValue, Session session) {
        SESSION_MAP.put(ptrValue, session);
    }

    static void unregisterSession(long ptrValue) {
        SESSION_MAP.remove(ptrValue);
    }

    static Session findSession(MemorySegment seg) {
        if (seg == null || seg.equals(MemorySegment.NULL)) return null;
        long v = seg.address();
        return SESSION_MAP.get(v);
    }

    static Session findSessionByAddress(long address) {
        return SESSION_MAP.get(address);
    }
}
