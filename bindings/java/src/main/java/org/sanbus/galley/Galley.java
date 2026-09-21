package org.sanbus.galley;

import java.util.concurrent.ConcurrentHashMap;

import org.sanbus.galley.internal.GalleyLibraryLoader;

/**
 * Module-level queries mirroring galley.h and the Python/TypeScript bindings.
 */
public final class Galley {
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
     * Loads are not thread-safe: load each artifact once at startup.
     *
     * @throws MissingArtifactException when no artifact is where it was told.
     */
    public static Parser load(String path) throws MissingArtifactException {
        String canonical = GalleyLibraryLoader.findLibrary(path);
        Parser existing = PARSER_CACHE.get(canonical);
        if (existing != null) return existing;
        Parser created = new Parser(canonical);
        Parser raced = PARSER_CACHE.putIfAbsent(canonical, created);
        return raced != null ? raced : created;
    }

    /**
     * Loads through {@code GALLEY_LIBRARY_PATH} / {@code galley.library.path}.
     *
     * @throws MissingArtifactException when no artifact is where it was told.
     */
    public static Parser load() throws MissingArtifactException { return load(null); }

    public static String version() throws MissingArtifactException { return load().version(); }
    public static String version(String libraryPath) throws MissingArtifactException { return load(libraryPath).version(); }

    public static ParserType parserType() throws MissingArtifactException { return load().parserType(); }
    public static ParserType parserType(String libraryPath) throws MissingArtifactException { return load(libraryPath).parserType(); }

    public static RecoveryMode errorRecoveryMode() throws MissingArtifactException { return load().errorRecoveryMode(); }
    public static RecoveryMode errorRecoveryMode(String libraryPath) throws MissingArtifactException { return load(libraryPath).errorRecoveryMode(); }

    public static boolean hasAst() throws MissingArtifactException { return load().hasAst(); }
    public static boolean hasAst(String libraryPath) throws MissingArtifactException { return load(libraryPath).hasAst(); }

    public static boolean hasProcedures() throws MissingArtifactException { return load().hasProcedures(); }
    public static boolean hasProcedures(String libraryPath) throws MissingArtifactException { return load(libraryPath).hasProcedures(); }

    public static boolean allowsNoAstTreeProcedures() throws MissingArtifactException { return load().allowsNoAstTreeProcedures(); }
    public static boolean sourceRetentionEnabled() throws MissingArtifactException { return load().sourceRetentionEnabled(); }
    public static boolean hasPositionTracking() throws MissingArtifactException { return load().hasPositionTracking(); }
    public static boolean hasInputStreaming() throws MissingArtifactException { return load().hasInputStreaming(); }
    public static boolean usesVerbatim() throws MissingArtifactException { return load().usesVerbatim(); }
    public static boolean stackOverflowRecoveryAvailable() throws MissingArtifactException { return load().stackOverflowRecoveryAvailable(); }

    public static long symbolCount() throws MissingArtifactException { return load().symbolCount(); }
    public static long variableCount() throws MissingArtifactException { return load().variableCount(); }

    public static String statusString(long status) throws MissingArtifactException { return load().statusString(status); }
    public static String statusString(StatusCode status) throws MissingArtifactException { return load().statusString(status); }

    // Snake_case aliases for Python-doc parity; not unused duplicates.
    public static boolean has_ast() throws MissingArtifactException { return hasAst(); }
    public static boolean has_procedures() throws MissingArtifactException { return hasProcedures(); }
    public static boolean has_position_tracking() throws MissingArtifactException { return hasPositionTracking(); }
}
