package org.sanbus.galley;

import java.lang.invoke.LambdaMetafactory;
import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.HashMap;
import java.util.Map;
import java.util.function.Consumer;

/**
 * Hook naming and coercion shared by every hook table: the parser's defaults
 * and each session's own. Whether a name may be installed is the artifact's
 * own hook list to answer (see {@link Parser#definesHook}); this class only
 * decides what a scan of a map considers.
 */
final class HookNames {
    private HookNames() {}

    /**
     * True for export names a scan considers: names beginning with
     * {@code reduction}, or with {@code hook} followed by {@code _} or an
     * ASCII uppercase letter (the same shape rule the C and JavaScript
     * hosts use). An install is deliberate and validates against the
     * artifact's list directly; a scan sees every export of a map, so it
     * filters to the names that could be hooks first.
     */
    static boolean isScanCandidate(String name) {
        if (name == null) return false;
        if (name.startsWith("reduction")) return true;
        if (name.length() <= 4 || !name.startsWith("hook")) return false;
        char afterHook = name.charAt(4);
        return afterHook == '_' || (afterHook >= 'A' && afterHook <= 'Z');
    }

    /** The hook a map value stands for, or null when it is neither a {@code Consumer} nor a {@code Runnable}. */
    static Consumer<ProcedureArguments> toHook(Object value) {
        if (value instanceof Consumer) {
            @SuppressWarnings("unchecked")
            Consumer<ProcedureArguments> hook = (Consumer<ProcedureArguments>) value;
            return hook;
        }
        if (value instanceof Runnable task) return args -> task.run();
        return null;
    }

    /**
     * The exports of a hook class as a scan source: its public static methods
     * a scan considers, by name, as a {@code Consumer} when the method takes
     * a {@code ProcedureArguments} and as a {@code Runnable} when it takes
     * nothing; the arguments overload wins when both exist. Each is bound the
     * way a method reference is, so a hook call is a direct call. A considered
     * method with any other signature raises: its name says it is a hook.
     */
    static Map<String, Object> exports(Class<?> hooks) {
        Map<String, Object> exports = new HashMap<>();
        for (Method method : hooks.getDeclaredMethods()) {
            int modifiers = method.getModifiers();
            if (!Modifier.isPublic(modifiers) || !Modifier.isStatic(modifiers)) continue;
            String name = method.getName();
            if (!isScanCandidate(name)) continue;
            Class<?>[] parameters = method.getParameterTypes();
            boolean takesArguments = parameters.length == 1 && parameters[0] == ProcedureArguments.class;
            if (method.getReturnType() != void.class || !(takesArguments || parameters.length == 0)) {
                throw new IllegalArgumentException("hook " + hooks.getName() + "." + name
                        + " must return void and take a ProcedureArguments or nothing");
            }
            if (takesArguments) {
                exports.put(name, bind(method, Consumer.class, "accept", MethodType.methodType(void.class, Object.class)));
            } else {
                exports.putIfAbsent(name, bind(method, Runnable.class, "run", MethodType.methodType(void.class)));
            }
        }
        return exports;
    }

    private static final MethodHandles.Lookup LOOKUP = MethodHandles.lookup();

    /** An instance of {@code face} whose single method {@code name} calls {@code method}. */
    private static Object bind(Method method, Class<?> face, String name, MethodType erased) {
        try {
            MethodHandle target = LOOKUP.unreflect(method);
            return LambdaMetafactory.metafactory(LOOKUP, name, MethodType.methodType(face), erased, target, target.type())
                    .getTarget()
                    .invoke();
        } catch (IllegalAccessException e) {
            throw new IllegalArgumentException("hook " + method.getDeclaringClass().getName() + "." + method.getName()
                    + " is not accessible: its class must be public", e);
        } catch (Throwable e) {
            throw new IllegalStateException("cannot bind hook " + method.getDeclaringClass().getName() + "."
                    + method.getName(), e);
        }
    }

    /** Rejects a null name or hook loudly: the single argument check of every install. */
    static void require(String name, Object hook) {
        if (name == null || hook == null) throw new IllegalArgumentException("name and hook required");
    }
}
