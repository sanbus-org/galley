package com.example;

import org.sanbus.galley.Galley;
import org.sanbus.galley.GalleyException;
import org.sanbus.galley.MissingArtifactException;
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
 * Parse throughput through the Galley Java bindings: parses the given
 * sample on one session and reports bytes/s.
 */
public final class Benchmark {

    private static final int DEFAULT_ITERATIONS = 10;

    private Benchmark() {}

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
        if (args.length < 2) {
            System.err.println("usage: com.example.Benchmark <parser-dir> <sample-file> [iterations]");
            System.exit(1);
            return;
        }
        String parserDir = args[0];
        String inputPath = args[1];
        int iterations = DEFAULT_ITERATIONS;
        if (args.length > 2) {
            try {
                iterations = Integer.parseInt(args[2]);
                if (iterations < 1) {
                    System.err.println("iterations must be >= 1");
                    System.exit(1);
                }
            } catch (NumberFormatException e) {
                System.err.println("iterations must be >= 1");
                System.exit(1);
            }
        }

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
                System.err.println("failed to read " + inputPath + ": short read");
                System.exit(1);
                return;
            }
            data.flip();
        } catch (IOException e) {
            System.err.println("failed to read " + inputPath);
            System.exit(1);
            return;
        }

        // The one parser library this benchmark runs: exact name inside the
        // given directory, no searching.
        String libPath = Paths.get(parserDir, GalleyLibraryLoader.libFileName()).toString();
        if (!Files.isRegularFile(Paths.get(libPath))) {
            System.err.println("missing " + libPath);
            System.exit(1);
            return;
        }
        SessionOptions opts = SessionOptions.builder().build();

        Session session;
        try {
            session = Galley.load(libPath).openSession(opts);
        } catch (GalleyException | MissingArtifactException e) {
            System.err.println("failed to create a parser session: " + e.getMessage());
            System.exit(1);
            return;
        }

        try {
            int parsed = 0;
            // The first two parses are cold: the session arena grows during the first and is reallocated for the second.
            for (int warmup = 0; warmup < 2; warmup++) {
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

            System.out.println("input: " + inputPath);
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
