package com.example;

import org.sanbus.galley.GalleyException;
import org.sanbus.galley.Session;
import org.sanbus.galley.SessionOptions;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;

/**
 * JSON throughput through the Galley Java bindings: no AST, no procedures,
 * no error recovery. Parses languages/json/samples/code-02.json 10 times
 * on one session and reports bytes/s.
 *
 * Mirrors examples/python/benchmark.py, examples/go/benchmark/benchmark.go,
 * examples/js/node/benchmark.ts, and examples/rust/src/benchmark.rs.
 */
public final class Benchmark {

    private static final String LOGICAL_INPUT = "languages/json/samples/code-02.json";
    private static final int DEFAULT_ITERATIONS = 10;

    private Benchmark() {}

    private static String resolveInput(String explicit) {
        if (explicit != null && !explicit.isEmpty()) return explicit;
        String checkout = System.getenv("GALLEY_CHECKOUT");
        if (checkout != null && !checkout.isEmpty()) {
            Path candidate = Paths.get(checkout, LOGICAL_INPUT);
            if (Files.isRegularFile(candidate)) return candidate.toString();
        }
        // from class location: examples/java/benchmark is two levels up from ... but we are in examples/java
        // Try walking up from cwd
        Path cwd = Paths.get(System.getProperty("user.dir", ".")).toAbsolutePath();
        for (int i = 0; i < 5; i++) {
            Path candidate = cwd.resolve(LOGICAL_INPUT);
            if (Files.isRegularFile(candidate)) return candidate.toString();
            Path parent = cwd.getParent();
            if (parent == null) break;
            cwd = parent;
        }
        // fallback from source file location (when run via mvn exec, cwd is examples/java)
        Path viaBenchmarkDir = Paths.get("benchmark").toAbsolutePath().getParent();
        if (viaBenchmarkDir != null) {
            Path candidate = viaBenchmarkDir.getParent().resolve(LOGICAL_INPUT);
            if (Files.isRegularFile(candidate)) return candidate.toString();
        }
        return Paths.get("..", "..", LOGICAL_INPUT).toString();
    }

    private static String benchmarkLibraryPath() {
        String os = System.getProperty("os.name", "").toLowerCase();
        String name = os.contains("mac") ? "libgalley-java.dylib" : os.contains("win") ? "galley-java.dll" : "libgalley-java.so";
        // Check GALLEY_LIBRARY_PATH first (explicit override)
        String env = System.getenv("GALLEY_LIBRARY_PATH");
        if (env != null && Files.isRegularFile(Paths.get(env))) return env;
        String prop = System.getProperty("galley.library.path");
        if (prop != null && Files.isRegularFile(Paths.get(prop))) return prop;
        Path cwd = Paths.get(System.getProperty("user.dir", ".")).toAbsolutePath();
        // 1) cwd is examples/java (when run from that dir)
        Path candidate = cwd.resolve("benchmark").resolve(name);
        if (Files.isRegularFile(candidate)) return candidate.toString();
        // 2) cwd is project root with -f flag: examples/java/benchmark/...
        candidate = cwd.resolve("examples/java/benchmark").resolve(name);
        if (Files.isRegularFile(candidate)) return candidate.toString();
        // 3) Walk up looking for examples/java/benchmark
        Path cur = cwd;
        for (int i = 0; i < 5; i++) {
            candidate = cur.resolve("examples/java/benchmark").resolve(name);
            if (Files.isRegularFile(candidate)) return candidate.toString();
            candidate = cur.resolve("benchmark").resolve(name);
            if (Files.isRegularFile(candidate)) return candidate.toString();
            Path parent = cur.getParent();
            if (parent == null) break;
            cur = parent;
        }
        // Fallback to regular discovery (demo lib will be found via GalleyLibraryLoader, but we return null to let it handle)
        return null;
    }

    private static String withThousands(long n) {
        String digits = Long.toString(n);
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < digits.length(); i++) {
            if (i > 0 && (digits.length() - i) % 3 == 0) out.append(',');
            out.append(digits.charAt(i));
        }
        return out.toString();
    }

    public static void main(String[] args) throws IOException {
        String explicit = null;
        int iterations = DEFAULT_ITERATIONS;
        if (args.length > 0) explicit = args[0];
        if (args.length > 1) {
            try {
                iterations = Integer.parseInt(args[1]);
                if (iterations < 1) {
                    System.err.println("iterations must be >= 1");
                    System.exit(1);
                }
            } catch (NumberFormatException e) {
                System.err.println("iterations must be >= 1");
                System.exit(1);
            }
        }

        String inputPath = resolveInput(explicit);
        Path path = Paths.get(inputPath);
        ByteBuffer data;
        int expected;
        try (FileChannel channel = FileChannel.open(path, StandardOpenOption.READ)) {
            long size = channel.size();
            if (size > Integer.MAX_VALUE) {
                System.err.println("input too large: " + size);
                System.exit(1);
                return;
            }
            expected = (int) size;
            data = ByteBuffer.allocateDirect(expected);
            while (data.hasRemaining()) {
                int n = channel.read(data);
                if (n < 0) break;
            }
            if (data.position() != expected) {
                System.err.println("failed to read " + LOGICAL_INPUT + ": short read");
                System.exit(1);
                return;
            }
            data.flip();
        } catch (IOException e) {
            System.err.println("failed to read " + LOGICAL_INPUT);
            System.exit(1);
            return;
        }

        String libPath = benchmarkLibraryPath();
        SessionOptions opts = SessionOptions.builder().build();
        // If benchmark lib exists, use it explicitly
        if (libPath != null) {
            opts = SessionOptions.builder().libraryPath(libPath).build();
        }

        Session session;
        try {
            session = new Session(opts);
        } catch (GalleyException e) {
            System.err.println("failed to create a parser session");
            System.exit(1);
            return;
        }

        try {
            int parsed;
            try {
                data.rewind();
                parsed = session.parse(data);
            } catch (GalleyException e) {
                System.err.println("warmup parse failed: " + e.getMessage() + " (" + e.getCode() + ")");
                System.exit(1);
                return;
            }
            if (parsed != expected) {
                System.err.println("warmup parse failed: parsed " + parsed + " of " + expected + " bytes");
                System.exit(1);
                return;
            }

            long start = System.nanoTime();
            int index = 0;
            for (; index < iterations; index++) {
                try {
                    data.rewind();
                    parsed = session.parse(data);
                } catch (GalleyException e) {
                    System.err.println("parse failed at iteration " + index + ": " + e.getMessage() + " (" + e.getCode() + ")");
                    System.exit(1);
                    return;
                }
                if (parsed != expected) {
                    System.err.println("parse failed at iteration " + index + ": parsed " + parsed + " of " + expected + " bytes");
                    System.exit(1);
                    return;
                }
            }
            long elapsed = System.nanoTime() - start;
            long total = (long) expected * iterations;
            long bps = elapsed == 0 ? 0 : total * 1_000_000_000L / elapsed;

            System.out.println("input: " + LOGICAL_INPUT);
            System.out.println("bytes: " + withThousands(expected));
            System.out.println("iterations: " + withThousands(iterations));
            System.out.println("parsed_bytes: " + withThousands(total));
            System.out.println("duration_ns: " + withThousands(elapsed));
            System.out.println("bytes_per_second: " + withThousands(bps));
        } finally {
            session.close();
        }
    }
}
