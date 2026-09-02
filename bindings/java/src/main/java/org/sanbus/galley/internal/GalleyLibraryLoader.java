package org.sanbus.galley.internal;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Loads the Galley shared library via Panama SymbolLookup, mirroring
 * bindings/typescript/src/ffi.ts and bindings/python/galley_bindings/build.py.
 * No JNA.
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

    private static String defaultCacheDir() {
        String os = System.getProperty("os.name", "").toLowerCase();
        String home = System.getProperty("user.home", "");
        if (os.contains("mac")) {
            return Paths.get(home, "Library", "Caches", "galley-bindings", "java", "capi").toString();
        }
        if (os.contains("win")) {
            String base = System.getenv("LOCALAPPDATA");
            if (base == null || base.isEmpty()) base = System.getProperty("java.io.tmpdir", "");
            return Paths.get(base, "galley-bindings", "java", "capi").toString();
        }
        String base = System.getenv("XDG_CACHE_HOME");
        if (base == null || base.isEmpty()) base = Paths.get(home, ".cache").toString();
        return Paths.get(base, "galley-bindings", "java", "capi").toString();
    }

    private static boolean exists(String path) {
        return path != null && Files.exists(Paths.get(path));
    }

    public static String findLibrary(String explicit) {
        if (explicit != null && !explicit.isEmpty() && exists(explicit)) {
            return Paths.get(explicit).toAbsolutePath().toString();
        }
        String env = System.getenv("GALLEY_LIBRARY_PATH");
        if (env != null && !env.isEmpty() && exists(env)) {
            return Paths.get(env).toAbsolutePath().toString();
        }
        String prop = System.getProperty("galley.library.path");
        if (prop != null && !prop.isEmpty() && exists(prop)) {
            return Paths.get(prop).toAbsolutePath().toString();
        }
        String cwd = System.getProperty("user.dir", ".");
        String[] candidates = {
                Paths.get(cwd, libFileName("galley-java")).toString(),
                Paths.get(cwd, libFileName("galley")).toString(),
                Paths.get(cwd, "libgalley-java.dylib").toString(),
                Paths.get(cwd, "libgalley-java.so").toString(),
        };
        for (String c : candidates) if (exists(c)) return c;

        try {
            Path cur = Paths.get(cwd).toAbsolutePath();
            for (int i = 0; i < 4; i++) {
                Path example = cur.resolve("examples/java").resolve(libFileName("galley-java"));
                if (Files.exists(example)) return example.toString();
                Path lang = cur.resolve("languages");
                if (Files.exists(lang)) break;
                cur = cur.getParent();
                if (cur == null) break;
            }
        } catch (Exception ignored) {}

        String cacheLib = Paths.get(defaultCacheDir(), "lib", libFileName("galley-java")).toString();
        if (exists(cacheLib)) return cacheLib;
        try {
            Path cacheBase = Paths.get(defaultCacheDir());
            if (Files.isDirectory(cacheBase)) {
                try (java.nio.file.DirectoryStream<Path> stream = Files.newDirectoryStream(cacheBase)) {
                    for (Path sub : stream) {
                        if (!Files.isDirectory(sub)) continue;
                        Path candidate = sub.resolve("lib").resolve(libFileName("galley-java"));
                        if (Files.exists(candidate)) return candidate.toString();
                    }
                }
            }
        } catch (Exception ignored) {}

        return cacheLib;
    }

    public static synchronized GalleyLibrary load(String explicitPath) {
        String libPath = findLibrary(explicitPath);
        if (explicitPath != null && !explicitPath.isEmpty()) {
            libPath = Paths.get(explicitPath).toAbsolutePath().toString();
        }
        if (cachedLibrary != null && libPath.equals(cachedPath)) return cachedLibrary;

        File f = new File(libPath);
        if (!f.exists()) {
            throw new IllegalStateException(
                    "Galley shared library not found at " + libPath + ".\n" +
                    "Build it first: java --enable-native-access=ALL-UNNAMED -cp bindings/java/out org.sanbus.galley.build.GalleyBuild <language-dir>\n" +
                    "or set GALLEY_LIBRARY_PATH=/path/to/" + libFileName("galley-java"));
        }

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
