package org.sanbus.galley.internal;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;

import org.sanbus.galley.MissingArtifactException;

/**
 * Loads the Galley shared library via Panama SymbolLookup, mirroring
 * bindings/js/node/src/ffi.ts. No JNA.
 *
 * One place, named up front: the explicit path the caller gave. Anything
 * else is a loud error, never a search.
 */
public final class GalleyLibraryLoader {

    private GalleyLibraryLoader() {}

    private static String libFileName(String base) {
        String os = System.getProperty("os.name", "").toLowerCase();
        if (os.contains("mac")) return "lib" + base + ".dylib";
        if (os.contains("win")) return base + ".dll";
        return "lib" + base + ".so";
    }

    /** Exact file name of the parser artifact for this binding. */
    public static String libFileName() {
        return libFileName("galley-java");
    }

    /**
     * @throws MissingArtifactException when no artifact is where it was told.
     */
    public static String findLibrary(String explicit) throws MissingArtifactException {
        if (explicit == null || explicit.isEmpty()) {
            throw new MissingArtifactException(null);
        }
        String absolute = Paths.get(explicit).toAbsolutePath().toString();
        if (!Files.exists(Paths.get(absolute))) {
            throw new MissingArtifactException(absolute);
        }
        return canonicalPath(absolute);
    }

    private static String canonicalPath(String absolute) {
        try {
            return Paths.get(absolute).toRealPath().toString();
        } catch (IOException e) {
            return absolute;
        }
    }
}
