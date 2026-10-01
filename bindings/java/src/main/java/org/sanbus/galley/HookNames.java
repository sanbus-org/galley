package org.sanbus.galley;

import java.util.Locale;
import java.util.function.Consumer;

/**
 * Hook naming and coercion shared by every hook table: the parser's defaults
 * and each session's own.
 */
final class HookNames {
    private HookNames() {}

    /** True for {@code reduction}, {@code reduction_*}, and {@code hook_*}. */
    static boolean isHook(String name) {
        return name != null
                && (name.equals("reduction") || name.startsWith("reduction_") || name.startsWith("hook_"));
    }

    /**
     * True when {@code name} may be installed. A name that looks like a
     * mistyped hook ({@code reductionPair}, {@code hookPrint},
     * {@code reducton_X}) warns and is refused; anything else (helpers,
     * data) is refused silently.
     */
    static boolean accepts(String name) {
        if (isHook(name)) return true;
        if (name != null) {
            String lower = name.toLowerCase(Locale.ROOT);
            if (lower.startsWith("reduct") || lower.startsWith("hook")) {
                System.err.println("galley: ignoring export \"" + name
                        + "\": procedure hooks must be named reduction, reduction_*, or hook_*.");
            }
        }
        return false;
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

    /** Rejects a null name or hook loudly: the single argument check of every install. */
    static void require(String name, Object hook) {
        if (name == null || hook == null) throw new IllegalArgumentException("name and hook required");
    }
}
