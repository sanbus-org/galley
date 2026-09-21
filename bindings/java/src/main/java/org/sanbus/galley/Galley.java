package org.sanbus.galley;

import java.util.concurrent.ConcurrentHashMap;

import org.sanbus.galley.internal.GalleyLibraryLoader;

/**
 * Module-level queries mirroring galley.h and the Python/TypeScript bindings.
 */
public final class Galley {
    public static final int PARSER_TYPE_LL = 0;
    public static final int PARSER_TYPE_LR = 1;

    public static final int RECOVERY_MODE_DISABLED = 0;
    public static final int RECOVERY_MODE_AUTOMATIC = 1;
    public static final int RECOVERY_MODE_EXPLICIT = 2;

    public static final int KIND_NONE = 0;
    public static final int KIND_SYNTAX = 1;
    public static final int KIND_INDENTATION = 2;

    public static final int RECOVERY_TARGET_NONE = 0;
    public static final int RECOVERY_TARGET_LHS_VARIABLE = 1;
    public static final int RECOVERY_TARGET_PRODUCTION = 2;
    public static final int RECOVERY_TARGET_OCCURRENCE = 3;

    public static final int RESUME_BEFORE = 0;
    public static final int RESUME_AFTER = 1;

    public static final long INVALID_NODE = 0xFFFFFFFFFFFFFFFFL;

    private Galley() {}

    private static final ConcurrentHashMap<String, Parser> PARSER_CACHE = new ConcurrentHashMap<>();

    /**
     * Loads the parser artifact at {@code path} and returns its handle.
     * Handles are cached by canonical artifact path for the process
     * lifetime: the same source always yields the identical object, and a
     * failed load binds and caches nothing. A null path resolves through
     * {@code GALLEY_LIBRARY_PATH} / {@code galley.library.path}, else a
     * loud error naming the exact path. Bare loads wire no hooks.
     */
    public static Parser load(String path) {
        return PARSER_CACHE.computeIfAbsent(GalleyLibraryLoader.findLibrary(path), Parser::new);
    }

    /** Loads through {@code GALLEY_LIBRARY_PATH} / {@code galley.library.path}. */
    public static Parser load() { return load(null); }

    public static String version() { return load().version(); }
    public static String version(String libraryPath) { return load(libraryPath).version(); }

    public static int parserType() { return load().parserType(); }
    public static int parserType(String libraryPath) { return load(libraryPath).parserType(); }

    public static int errorRecoveryMode() { return load().errorRecoveryMode(); }
    public static int errorRecoveryMode(String libraryPath) { return load(libraryPath).errorRecoveryMode(); }

    public static boolean hasAst() { return load().hasAst(); }
    public static boolean hasAst(String libraryPath) { return load(libraryPath).hasAst(); }

    public static boolean hasProcedures() { return load().hasProcedures(); }
    public static boolean hasProcedures(String libraryPath) { return load(libraryPath).hasProcedures(); }

    public static boolean allowsNoAstTreeProcedures() { return load().allowsNoAstTreeProcedures(); }
    public static boolean sourceRetentionEnabled() { return load().sourceRetentionEnabled(); }
    public static boolean hasPositionTracking() { return load().hasPositionTracking(); }
    public static boolean hasInputStreaming() { return load().hasInputStreaming(); }
    public static boolean usesVerbatim() { return load().usesVerbatim(); }
    public static boolean stackOverflowRecoveryAvailable() { return load().stackOverflowRecoveryAvailable(); }

    public static long symbolCount() { return load().symbolCount(); }
    public static long variableCount() { return load().variableCount(); }

    public static String statusString(long status) { return load().statusString(status); }

    // Snake_case aliases for Python-doc parity; not unused duplicates.
    public static boolean has_ast() { return hasAst(); }
    public static boolean has_procedures() { return hasProcedures(); }
    public static boolean has_position_tracking() { return hasPositionTracking(); }
}
