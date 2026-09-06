package com.example;

import org.sanbus.galley.GalleyException;
import org.sanbus.galley.Session;
import org.sanbus.galley.SessionOptions;
import org.sanbus.galley.internal.GalleyLibraryLoader;

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
        return Paths.get(System.getProperty("user.dir", "."), LOGICAL_INPUT).toString();
    }

    // The one parser file this benchmark runs: exact name, no searching.
    private static String benchmarkLibraryPath() {
        String env = System.getenv("GALLEY_LIBRARY_PATH");
        if (env != null && !env.isEmpty()) return env;
        String prop = System.getProperty("galley.library.path");
        if (prop != null && !prop.isEmpty()) return prop;
        return Paths.get(System.getProperty("user.dir", "."),
                "examples", "java", "benchmark", GalleyLibraryLoader.libFileName()).toString();
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
        if (!Files.isRegularFile(Paths.get(libPath))) {
            System.err.println("missing " + libPath);
            System.exit(1);
            return;
        }
        SessionOptions opts = SessionOptions.builder().libraryPath(libPath).build();

        Session session;
        try {
            session = new Session(opts);
        } catch (GalleyException | IllegalStateException e) {
            System.err.println("failed to create a parser session: " + e.getMessage());
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
