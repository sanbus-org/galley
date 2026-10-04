package org.sanbus.galley;

import java.util.concurrent.ConcurrentHashMap;

import org.sanbus.galley.internal.GalleyLibrary;
import org.sanbus.galley.internal.GalleyLibraryLoader;

/**
 * Loads parser artifacts and holds the shared sentinel constants.
 * Module-level queries (version, parser type, counts, status text) are
 * methods on the {@link Parser} a load returns.
 */
public final class Galley {
    /** {@code GALLEY_INVALID_NODE}: no node at that position. Non-negative, like every address. */
    public static final long INVALID_NODE = 0x7FFFFFFFFFFFFFFFL;
    /** {@code GALLEY_NO_VARIABLE}: the core's answer for a node without a variable. */
    public static final long NO_VARIABLE = 0x7FFFFFFFFFFFFFFFL;

    private Galley() {}

    private static final ConcurrentHashMap<String, Parser> PARSER_CACHE = new ConcurrentHashMap<>();
    private static final ConcurrentHashMap<String, Object> LOAD_LOCKS = new ConcurrentHashMap<>();

    /**
     * Loads the parser artifact at {@code path} and returns the parser.
     * Parsers are cached by canonical artifact path for the process
     * lifetime: the same source always yields the identical object, and a
     * failed load binds and caches nothing. The artifact path is explicit:
     * a null or empty one is a loud error, never a search. Bare loads wire
     * no hooks.
     * Same-path loads serialize against each other; sessions opened from
     * the parser stay confined to one thread each, and sessions on different
     * threads parse concurrently (see {@link Parser}).
     *
     * @throws MissingArtifactException when no artifact is where it was told.
     */
    public static Parser load(String path) throws MissingArtifactException {
        String canonical = GalleyLibraryLoader.findLibrary(path);
        Object lock = LOAD_LOCKS.computeIfAbsent(canonical, key -> new Object());
        synchronized (lock) {
            Parser existing = PARSER_CACHE.get(canonical);
            if (existing != null) return existing;
            Parser created = Parser.create(canonical, new GalleyLibrary(canonical));
            PARSER_CACHE.put(canonical, created);
            return created;
        }
    }
}
