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
    // >>> generated: sentinels (bindings/abi_values.zon; regenerate: zig build abi-values)
    /**
     * Returned by tree queries when no node exists at that position. Every
     * node address and this sentinel are non-negative ({@code INT64_MAX}), so
     * a call that returns an address can report a negative status in the same
     * {@code long long}.
     */
    public static final long INVALID_NODE = 0x7FFFFFFFFFFFFFFFL;

    /**
     * Returned by {@code galley_node_variable_index} and written to the
     * snapshot's variable column for a node that has no variable.
     * Non-negative like {@code GALLEY_INVALID_NODE}: only statuses are
     * negative.
     */
    public static final long NO_VARIABLE = 0x7FFFFFFFFFFFFFFFL;
    // <<< generated: sentinels

    private Galley() {}

    /** The loaded native library per canonical artifact path: shared, never unloaded. */
    private static final ConcurrentHashMap<String, GalleyLibrary> LIBRARIES = new ConcurrentHashMap<>();

    /**
     * Loads the parser artifact at {@code path} and returns a new parser.
     * Every load returns a new parser whose default hooks are its own (none
     * after a bare load): loading one artifact twice never shares hook
     * state. A failed load hands out no parser and affects none already
     * handed out; retrying after the cause is fixed is a fresh attempt. The
     * loaded native library is shared across the parsers of one artifact
     * and never unloads, so a parser is not closeable. The artifact path is
     * explicit: a null or empty one is a loud error, never a search. Bare
     * loads wire no hooks. Sessions opened from the parser stay confined to
     * one thread each, and sessions on different threads parse concurrently
     * (see {@link Parser}).
     *
     * @throws MissingArtifactException when no artifact is where it was told.
     */
    public static Parser load(String path) throws MissingArtifactException {
        String canonical = GalleyLibraryLoader.findLibrary(path);
        GalleyLibrary library = LIBRARIES.computeIfAbsent(canonical, GalleyLibrary::new);
        return Parser.create(canonical, library);
    }
}
