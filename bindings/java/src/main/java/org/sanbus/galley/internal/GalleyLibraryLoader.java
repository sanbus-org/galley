package org.sanbus.galley.internal;

import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Loads the Galley shared library via Panama SymbolLookup, mirroring
 * bindings/js/node/src/ffi.ts. No JNA.
 *
 * One place, named up front: an explicit path or GALLEY_LIBRARY_PATH
 * (or the -Dgalley.library.path equivalent). Anything else is a loud
 * error, never a search.
 */
public final class GalleyLibraryLoader {

    private static final ConcurrentHashMap<String, GalleyLibrary> CACHE = new ConcurrentHashMap<>();
    private static String cachedPath = null;
    private static GalleyLibrary cachedLibrary = null;

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

    private static String buildHint() {
        return "Build it first: java --enable-native-access=ALL-UNNAMED -cp bindings/java/out org.sanbus.galley.build.GalleyBuild <language-dir>\n"
                + "or set GALLEY_LIBRARY_PATH=/path/to/" + libFileName();
    }

    public static String findLibrary(String explicit) {
        String chosen = (explicit != null && !explicit.isEmpty()) ? explicit : null;
        if (chosen == null) {
            String env = System.getenv("GALLEY_LIBRARY_PATH");
            if (env != null && !env.isEmpty()) chosen = env;
        }
        if (chosen == null) {
            String prop = System.getProperty("galley.library.path");
            if (prop != null && !prop.isEmpty()) chosen = prop;
        }
        if (chosen == null) {
            throw new IllegalStateException(
                    "galley: parser artifact not found: no parser artifact given; pass libraryPath or set GALLEY_LIBRARY_PATH.\n"
                    + buildHint());
        }
        String resolved = Paths.get(chosen).toAbsolutePath().toString();
        if (!Files.exists(Paths.get(resolved))) {
            throw new IllegalStateException(
                    "galley: parser artifact not found: at " + resolved + ".\n"
                    + buildHint());
        }
        return resolved;
    }

    public static synchronized GalleyLibrary load(String explicitPath) {
        String libPath = findLibrary(explicitPath);
        if (cachedLibrary != null && libPath.equals(cachedPath)) return cachedLibrary;

        GalleyLibrary lib = CACHE.get(libPath);
        if (lib != null) {
            cachedLibrary = lib;
            cachedPath = libPath;
            return lib;
        }

        lib = new GalleyLibrary(libPath);
        CACHE.put(libPath, lib);
        cachedLibrary = lib;
        cachedPath = libPath;
        return lib;
    }

    public static synchronized GalleyLibrary load() {
        return load(null);
    }

    public static synchronized void clearCache() {
        CACHE.clear();
        cachedLibrary = null;
        cachedPath = null;
    }
}
