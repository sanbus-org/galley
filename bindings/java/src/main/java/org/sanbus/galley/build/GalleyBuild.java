package org.sanbus.galley.build;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.util.*;

/**
 * Builds a Galley parser and its shared library for a Java consumer.
 *
 * Usage: java -jar galley-bindings.jar &lt;language-dir&gt;
 *
 * The language dir must contain ll.grm and may contain config.zig,
 * procedures.java (Java hooks dispatched through generated shim),
 * procedures.c (legacy C hooks), ll_error_messages.zig, etc, mirroring
 * the other bindings.
 *
 * Environment overrides: ZIG_EXECUTABLE (default zig), GALLEY_LIBRARY_PATH,
 *   GALLEY_CHECKOUT (required: existing Galley working tree).
 *
 * Generates parser (--emit-metadata), builds shared library through generic
 * consumer build directly next to the grammar, so the consumer can name it
 * outright via SessionOptions.libraryPath or GALLEY_LIBRARY_PATH. To fetch
 * a checkout for convenience, use examples/scripts/fetch-galley.sh — that
 * cache is an examples-only convenience, not part of the bindings.
 */
public final class GalleyBuild {

    private static final String LIBRARY_NAME = "galley-java";

    private GalleyBuild() {}

    private static void fatal(String msg) {
        System.err.println("galley-bindings: " + msg);
        System.exit(1);
    }

    private static void run(List<String> cmd, Path cwd) {
        System.out.println("+ " + String.join(" ", cmd));
        try {
            ProcessBuilder pb = new ProcessBuilder(cmd);
            if (cwd != null) pb.directory(cwd.toFile());
            pb.inheritIO();
            Process p = pb.start();
            int code = p.waitFor();
            if (code != 0) fatal("command failed: " + String.join(" ", cmd) + " (exit " + code + ")");
        } catch (IOException e) {
            fatal("executable not found: " + cmd.get(0) + " (" + e.getMessage() + ")");
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            fatal("interrupted");
        }
    }

    private static String capture(List<String> cmd) {
        try {
            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.redirectErrorStream(false);
            Process p = pb.start();
            String out = new String(p.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
            String err = new String(p.getErrorStream().readAllBytes(), StandardCharsets.UTF_8);
            int code = p.waitFor();
            if (code != 0) fatal("command failed: " + String.join(" ", cmd));
            return out;
        } catch (IOException e) {
            fatal("failed to probe " + cmd.get(0) + ": " + e.getMessage());
            return "";
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            fatal("interrupted");
            return "";
        }
    }

    private static String zigExecutable() {
        String v = System.getenv("ZIG_EXECUTABLE");
        return (v != null && !v.isEmpty()) ? v : "zig";
    }

    private static Path resolveGalley() {
        String checkoutEnv = System.getenv("GALLEY_CHECKOUT");
        if (checkoutEnv == null || checkoutEnv.isEmpty()) {
            fatal("GALLEY_CHECKOUT is not set; point it at a Galley checkout (examples/scripts/fetch-galley.sh can fetch one)");
        }
        Path checkout = Paths.get(checkoutEnv);
        if (!Files.exists(checkout.resolve("build.zig"))) {
            fatal("GALLEY_CHECKOUT=" + checkout + " is not a Galley repository checkout (no build.zig)");
        }
        return checkout.toAbsolutePath();
    }

    private static String libFileName(String base) {
        String os = System.getProperty("os.name", "").toLowerCase();
        if (os.contains("mac")) return "lib" + base + ".dylib";
        if (os.contains("win")) return base + ".dll";
        return "lib" + base + ".so";
    }

    private static Path findJavaProceduresFile(Path languageDir) {
        Path candidate = languageDir.resolve("procedures.java");
        if (Files.isRegularFile(candidate)) return candidate;
        return null;
    }

    // Reads the generator's hook list from metadata.json, written alongside
    // procedures.zig. Minimal scanner for one string array (the file is
    // machine-written by the generator); the stdlib has no JSON parser.
    // The generator owns the hook list; this tool renders it.
    private static List<String> readProcedureHooks(Path languageDir) {
        Path metadataPath = languageDir.resolve("metadata.json");
        String metadata;
        try { metadata = Files.readString(metadataPath, StandardCharsets.UTF_8); } catch (IOException e) { fatal("failed to read " + metadataPath + ": " + e.getMessage()); return null; }
        int key = metadata.indexOf("\"procedures\"");
        if (key < 0) fatal(metadataPath + " has no procedure hook list; update the Galley checkout");
        int open = metadata.indexOf('[', key);
        if (open < 0) fatal(metadataPath + " has no procedure hook list; update the Galley checkout");
        List<String> hooks = new ArrayList<>();
        StringBuilder current = null;
        boolean escape = false;
        for (int i = open + 1; i < metadata.length(); i++) {
            char ch = metadata.charAt(i);
            if (current == null) {
                if (ch == '"') { current = new StringBuilder(); escape = false; }
                else if (ch == ']') break;
                continue;
            }
            if (escape) { current.append(ch); escape = false; }
            else if (ch == '\\') escape = true;
            else if (ch == '"') { hooks.add(current.toString()); current = null; }
            else current.append(ch);
        }
        if (current != null || hooks.isEmpty()) fatal(metadataPath + " has no procedure hook list; update the Galley checkout");
        return hooks;
    }

    private static void emitJavaProcedureShim(List<String> hooks, Path outputPath) {
        List<String> builder = new ArrayList<>();
        builder.add("// Generated by galley-bindings; DO NOT EDIT.");
        builder.add("// Procedure hooks dispatch through a Java callback registered");
        builder.add("// by the host's JVM; unregistered slots are no-ops.");
        builder.add("const std = @import(\"std\");");
        builder.add("const root = @import(\"galley\");");
        builder.add("pub const Payload = struct {};");
        builder.add("");
        builder.add("var java_dispatch_target: ?*const fn ([*]const u8, usize, ?*anyopaque) callconv(.c) void = null;");
        builder.add("");
        builder.add("fn dispatch(comptime name: []const u8, args: *root.data_structures.ProcedureArguments) void {");
        builder.add("    if (java_dispatch_target) |target| {");
        builder.add("        target(name.ptr, name.len, @ptrCast(args));");
        builder.add("    }");
        builder.add("}");
        builder.add("");
        for (String name : hooks) {
            builder.add("pub fn " + name + "(args: *root.data_structures.ProcedureArguments) void {");
            builder.add("    dispatch(\"" + name + "\", args);");
            builder.add("}");
            builder.add("");
        }
        builder.add("export fn galley_install_java_dispatch(target: *const fn ([*]const u8, usize, ?*anyopaque) callconv(.c) void) void {");
        builder.add("    java_dispatch_target = target;");
        builder.add("}");
        builder.add("");
        try { Files.writeString(outputPath, String.join("\n", builder), StandardCharsets.UTF_8); } catch (IOException e) { fatal("failed to write shim: " + e.getMessage()); }
    }

    public static void main(String[] args) {
        if (args.length != 1) fatal("usage: galley-java <language-dir>");
        String os = System.getProperty("os.name", "").toLowerCase();
        if (os.contains("win")) fatal("the java bindings target POSIX platforms");
        Path languageDir = Paths.get(args[0]).toAbsolutePath().normalize();
        if (!Files.isRegularFile(languageDir.resolve("ll.grm"))) fatal(languageDir + " does not contain ll.grm");

        Path galleySource = resolveGalley();
        Path cli = galleySource.resolve("zig-out").resolve("bin").resolve("galley");
        if (!Files.exists(cli)) {
            run(Arrays.asList(zigExecutable(), "build", "-Doptimize=ReleaseFast", "install"), galleySource);
        }

        String help = capture(Arrays.asList(cli.toString(), "--help"));
        if (!help.contains("--emit-metadata")) {
            fatal("the Galley at " + galleySource + " is too old for the bindings workflow (no --emit-metadata support); update the checkout");
        }

        run(Arrays.asList(cli.toString(), "--emit-metadata", languageDir.toString()), null);

        // One library embeds one parser; the consumer build locates the file
        // generation produced from -Dlanguage-dir and infers the family
        // from the filename.
        List<String> procedureHooks = readProcedureHooks(languageDir);

        Path javaProceduresFile = findJavaProceduresFile(languageDir);
        String proceduresZigSource = null;
        String proceduresCSource = null;
        boolean hasCProcedures = Files.isRegularFile(languageDir.resolve("procedures.c")) || Files.isRegularFile(languageDir.resolve("procedures.cpp"));

        if (javaProceduresFile != null) {
            if (hasCProcedures) System.err.println("galley-bindings: both Java (" + javaProceduresFile + ") and C procedures found — using Java");
            System.err.println("galley-bindings: using Java procedures from " + javaProceduresFile);
            Path shimPath = languageDir.resolve("procedures_java.zig");
            emitJavaProcedureShim(procedureHooks, shimPath);
            proceduresZigSource = shimPath.toString();
        } else if (hasCProcedures) {
            if (Files.isRegularFile(languageDir.resolve("procedures.zig"))) proceduresZigSource = languageDir.resolve("procedures.zig").toString();
            if (Files.isRegularFile(languageDir.resolve("procedures.c"))) proceduresCSource = languageDir.resolve("procedures.c").toString();
            else if (Files.isRegularFile(languageDir.resolve("procedures.cpp"))) proceduresCSource = languageDir.resolve("procedures.cpp").toString();
        } else {
            if (Files.isRegularFile(languageDir.resolve("procedures.zig"))) {
                Path shimPath = languageDir.resolve("procedures_java.zig");
                emitJavaProcedureShim(procedureHooks, shimPath);
                proceduresZigSource = shimPath.toString();
            }
        }

        List<String> consumerArgs = new ArrayList<>(Arrays.asList(
                zigExecutable(), "build",
                "--build-file", galleySource.resolve("bindings").resolve("c").resolve("consumer").resolve("build.zig").toString(),
                "-Dlanguage-dir=" + languageDir.toString(),
                "-Dlib-name=" + LIBRARY_NAME,
                "-Doutput=" + libFileName(LIBRARY_NAME),
                "-Doptimize=ReleaseFast",
                "--prefix", languageDir.toString(),
                "install"
        ));
        // Insert procedures before "install" arg (last)
        int insertPos = consumerArgs.size() - 1;
        if (proceduresZigSource != null) {
            consumerArgs.add(insertPos, "-Dprocedures-zig-source=" + proceduresZigSource);
            insertPos++;
        }
        if (proceduresCSource != null) {
            consumerArgs.add(insertPos, "-Dprocedures-c-source=" + proceduresCSource);
            insertPos++;
        }
        // config.zig and {ll,lr}_error_messages.zig are inferred by the
        // consumer build from the parser location.
        run(consumerArgs, galleySource);

        Path dest = languageDir.resolve(libFileName(LIBRARY_NAME));
        if (!Files.exists(dest)) fatal("expected library not found at " + dest);
        System.out.println("galley-bindings: built " + dest + "; import from " + languageDir + " (or set GALLEY_LIBRARY_PATH)");
    }
}
