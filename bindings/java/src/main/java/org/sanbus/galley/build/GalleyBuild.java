package org.sanbus.galley.build;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

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
 *   GALLEY_CHECKOUT, GALLEY_REPOSITORY, GALLEY_TAG (default main).
 *
 * Generates parser (--emit-metadata), builds shared library through generic
 * consumer build, and copies libgalley-java.* into language dir so
 * Session can locate it via cwd or GALLEY_LIBRARY_PATH.
 */
public final class GalleyBuild {

    private static final String LIBRARY_NAME = "galley-java";
    private static final String DEFAULT_GALLEY_REPOSITORY = "https://github.com/sanbus-org/galley.git";
    private static final String DEFAULT_GALLEY_TAG = "main";

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

    private static Path cacheDir() {
        String os = System.getProperty("os.name", "").toLowerCase();
        String home = System.getProperty("user.home", "");
        Path base;
        if (os.contains("mac")) {
            base = Paths.get(home, "Library", "Caches");
        } else if (os.contains("win")) {
            String env = System.getenv("LOCALAPPDATA");
            base = (env != null && !env.isEmpty()) ? Paths.get(env) : Paths.get(System.getProperty("java.io.tmpdir"));
        } else {
            String env = System.getenv("XDG_CACHE_HOME");
            base = (env != null && !env.isEmpty()) ? Paths.get(env) : Paths.get(home, ".cache");
        }
        Path dir = base.resolve("galley-bindings").resolve("java");
        try { Files.createDirectories(dir); } catch (IOException e) { fatal("failed to create cache dir: " + e.getMessage()); }
        return dir;
    }

    private static Path resolveGalley(Path cacheDirPath) {
        String checkoutEnv = System.getenv("GALLEY_CHECKOUT");
        if (checkoutEnv != null && !checkoutEnv.isEmpty()) {
            Path checkout = Paths.get(checkoutEnv);
            if (!Files.exists(checkout.resolve("build.zig"))) {
                fatal("GALLEY_CHECKOUT=" + checkout + " is not a Galley repository checkout (no build.zig)");
            }
            return checkout.toAbsolutePath();
        }
        String tag = System.getenv("GALLEY_TAG");
        if (tag == null || tag.isEmpty()) tag = DEFAULT_GALLEY_TAG;
        String repository = System.getenv("GALLEY_REPOSITORY");
        if (repository == null || repository.isEmpty()) repository = DEFAULT_GALLEY_REPOSITORY;
        Path dir = cacheDirPath != null ? cacheDirPath : cacheDir();
        Path sourceDir = dir.resolve("galley-src");
        Path stamp = dir.resolve("galley-tag");
        String previous = "";
        try {
            if (Files.exists(stamp)) previous = Files.readString(stamp, StandardCharsets.UTF_8).trim();
        } catch (IOException ignored) {}
        if (Files.exists(sourceDir) && previous.equals(tag)) return sourceDir;
        try {
            if (Files.exists(sourceDir)) deleteRecursive(sourceDir);
        } catch (IOException ignored) {}
        run(Arrays.asList("git", "clone", "--depth", "1", "--branch", tag, "--single-branch", "--recurse-submodules=false", repository, sourceDir.toString()), null);
        try { Files.writeString(stamp, tag, StandardCharsets.UTF_8); } catch (IOException e) { fatal("failed to write tag stamp: " + e.getMessage()); }
        return sourceDir;
    }

    private static void deleteRecursive(Path p) throws IOException {
        if (!Files.exists(p)) return;
        Files.walk(p).sorted(Comparator.reverseOrder()).forEach(path -> {
            try { Files.delete(path); } catch (IOException ignored) {}
        });
    }

    private static String[] detectParser(Path languageDir) {
        boolean hasLL = Files.exists(languageDir.resolve("_ll-parser.zig"));
        boolean hasLR = Files.exists(languageDir.resolve("_lr-parser.zig"));
        if (hasLL && !hasLR) return new String[]{"_ll-parser.zig", "ll"};
        if (!hasLL && hasLR) return new String[]{"_lr-parser.zig", "lr"};
        if (hasLL && hasLR) fatal("both _ll-parser.zig and _lr-parser.zig exist in " + languageDir + "; one library embeds one parser — split the language dirs");
        fatal("generation produced no parser in " + languageDir);
        return null;
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

    private static void emitJavaProcedureShim(Path templatePath, Path outputPath) {
        String template;
        try { template = Files.readString(templatePath, StandardCharsets.UTF_8); } catch (IOException e) { fatal("failed to read " + templatePath + ": " + e.getMessage()); return; }
        Pattern pattern = Pattern.compile("pub\\s+extern\\s+fn\\s+(\\w+)\\s*\\((.*)\\)\\s*(\\w+)\\s*;");
        List<String[]> hooks = new ArrayList<>();
        List<String> passthrough = new ArrayList<>();
        for (String line : template.split("\n", -1)) {
            Matcher m = pattern.matcher(line.trim());
            if (m.matches()) {
                hooks.add(new String[]{m.group(1), m.group(2), m.group(3)});
                continue;
            }
            String trimmed = line.trim();
            if (trimmed.startsWith("pub extern") || trimmed.startsWith("// Auto-generated") || trimmed.startsWith("// Implement these functions")) {
                continue;
            }
            passthrough.add(line);
        }
        List<String> builder = new ArrayList<>();
        builder.add("// Generated by galley-bindings; DO NOT EDIT.");
        builder.add("// Procedure hooks dispatch through a Java callback registered");
        builder.add("// by the host's JVM; unregistered slots are no-ops.");
        builder.add("const std = @import(\"std\");");
        for (String line : passthrough) builder.add(line);
        if (!builder.isEmpty() && !builder.get(builder.size()-1).trim().isEmpty()) builder.add("");
        builder.add("var java_dispatch_target: ?*const fn ([*]const u8, usize, ?*anyopaque) callconv(.c) void = null;");
        builder.add("");
        builder.add("fn dispatch(comptime name: []const u8, args: *root.data_structures.ProcedureArguments) void {");
        builder.add("    if (java_dispatch_target) |target| {");
        builder.add("        target(name.ptr, name.len, @ptrCast(args));");
        builder.add("    }");
        builder.add("}");
        builder.add("");
        for (String[] h : hooks) {
            builder.add("pub fn " + h[0] + "(args: " + h[1] + ") " + h[2] + " {");
            builder.add("    dispatch(\"" + h[0] + "\", args);");
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

        Path cache = cacheDir();
        Path galleySource = resolveGalley(cache);
        Path cli = galleySource.resolve("zig-out").resolve("bin").resolve("galley");
        if (!Files.exists(cli)) {
            run(Arrays.asList(zigExecutable(), "build", "-Doptimize=ReleaseFast", "install"), galleySource);
        }

        String help = capture(Arrays.asList(cli.toString(), "--help"));
        if (!help.contains("--emit-metadata")) {
            fatal("the Galley at " + galleySource + " is too old for the bindings workflow (no --emit-metadata support); update the checkout");
        }

        run(Arrays.asList(cli.toString(), "--emit-metadata", languageDir.toString()), null);

        String[] parserInfo = detectParser(languageDir);
        String parserSource = parserInfo[0];
        String parserType = parserInfo[1];

        // Compute prefix hash for cache
        String hash;
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] digest = md.digest(languageDir.toString().getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < 8; i++) sb.append(String.format("%02x", digest[i]));
            hash = sb.toString();
        } catch (Exception e) { hash = "default"; }
        Path prefix = cache.resolve("capi").resolve(hash);

        Path javaProceduresFile = findJavaProceduresFile(languageDir);
        String proceduresZigSource = null;
        String proceduresCSource = null;
        boolean hasCProcedures = Files.isRegularFile(languageDir.resolve("procedures.c")) || Files.isRegularFile(languageDir.resolve("procedures.cpp"));

        if (javaProceduresFile != null) {
            if (hasCProcedures) System.err.println("galley-bindings: both Java (" + javaProceduresFile + ") and C procedures found — using Java");
            System.err.println("galley-bindings: using Java procedures from " + javaProceduresFile);
            Path shimPath = languageDir.resolve("procedures_java.zig");
            Path templatePath = languageDir.resolve("procedures.zig");
            emitJavaProcedureShim(templatePath, shimPath);
            proceduresZigSource = shimPath.toString();
        } else if (hasCProcedures) {
            if (Files.isRegularFile(languageDir.resolve("procedures.zig"))) proceduresZigSource = languageDir.resolve("procedures.zig").toString();
            if (Files.isRegularFile(languageDir.resolve("procedures.c"))) proceduresCSource = languageDir.resolve("procedures.c").toString();
            else if (Files.isRegularFile(languageDir.resolve("procedures.cpp"))) proceduresCSource = languageDir.resolve("procedures.cpp").toString();
        } else {
            if (Files.isRegularFile(languageDir.resolve("procedures.zig"))) {
                Path shimPath = languageDir.resolve("procedures_java.zig");
                Path templatePath = languageDir.resolve("procedures.zig");
                emitJavaProcedureShim(templatePath, shimPath);
                proceduresZigSource = shimPath.toString();
            }
        }

        List<String> consumerArgs = new ArrayList<>(Arrays.asList(
                zigExecutable(), "build",
                "--build-file", galleySource.resolve("bindings").resolve("c").resolve("consumer").resolve("build.zig").toString(),
                "-Dparser-source=" + languageDir.resolve(parserSource).toString(),
                "-Dparser-type=" + parserType,
                "-Dlib-name=" + LIBRARY_NAME,
                "-Doptimize=ReleaseFast",
                "--prefix", prefix.toString(),
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
        Path errMsgCandidate = languageDir.resolve(parserType + "_error_messages.zig");
        if (Files.isRegularFile(errMsgCandidate)) {
            consumerArgs.add(insertPos, "-Derror-messages-zig-source=" + errMsgCandidate.toString());
        }
        run(consumerArgs, galleySource);

        Path builtLib = prefix.resolve("lib").resolve(libFileName(LIBRARY_NAME));
        if (!Files.exists(builtLib)) fatal("expected library not found at " + builtLib);
        Path dest = languageDir.resolve(libFileName(LIBRARY_NAME));
        try { Files.copy(builtLib, dest, StandardCopyOption.REPLACE_EXISTING); } catch (IOException e) { fatal("failed to copy library: " + e.getMessage()); }
        System.out.println("galley-bindings: built " + dest + "; import from " + languageDir + " (or set GALLEY_LIBRARY_PATH)");
        System.out.println("  cache: " + builtLib);
    }
}
