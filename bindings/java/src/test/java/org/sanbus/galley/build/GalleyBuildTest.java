package org.sanbus.galley.build;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * The real entry point runs with a fake generator and a fake zig that records its arguments
 * and fails, so nothing builds. {@code -Doptimize} must reach the consumer build only when a
 * mode was chosen.
 */
class GalleyBuildTest {

    @TempDir Path root;

    private List<String> consumerBuildArguments(String... extraArguments) throws Exception {
        Path checkout = root.resolve("checkout");
        Files.createDirectories(checkout.resolve("zig-out").resolve("bin"));
        Files.writeString(checkout.resolve("build.zig"), "");
        Path generator = checkout.resolve("zig-out").resolve("bin").resolve("galley");
        Files.writeString(generator, "#!/bin/sh\n[ \"$1\" = --help ] && echo --emit-host-procedures\nexit 0\n");
        generator.toFile().setExecutable(true);
        Path recorded = root.resolve("recorded.txt");
        Path fakeZig = root.resolve("zig");
        Files.writeString(fakeZig, "#!/bin/sh\nprintf '%s\\n' \"$@\" > '" + recorded + "'\nexit 1\n");
        fakeZig.toFile().setExecutable(true);
        Path languageDir = root.resolve("language");
        Files.createDirectories(languageDir);
        Files.writeString(languageDir.resolve("ll.grm"), "");

        List<String> command = new ArrayList<>(List.of(
                Path.of(System.getProperty("java.home"), "bin", "java").toString(),
                "-cp", System.getProperty("java.class.path"),
                "org.sanbus.galley.build.GalleyBuild", languageDir.toString()));
        command.addAll(List.of(extraArguments));
        ProcessBuilder builder = new ProcessBuilder(command).redirectErrorStream(true);
        builder.environment().put("GALLEY_CHECKOUT", checkout.toString());
        builder.environment().put("ZIG_EXECUTABLE", fakeZig.toString());
        Process process = builder.start();
        String output = new String(process.getInputStream().readAllBytes());
        assertEquals(1, process.waitFor(), output);
        assertTrue(Files.exists(recorded), output);
        return Files.readAllLines(recorded);
    }

    private static boolean hasOptimizeArgument(List<String> arguments) {
        return arguments.stream().anyMatch(argument -> argument.startsWith("-Doptimize"));
    }

    @Test
    void noOptionPassesNoOptimizeArgument() throws Exception {
        List<String> arguments = consumerBuildArguments();
        assertTrue(arguments.contains("--build-file"));
        assertFalse(hasOptimizeArgument(arguments));
    }

    @Test
    void emptyModeCountsAsNotChosen() throws Exception {
        assertFalse(hasOptimizeArgument(consumerBuildArguments("--optimize", "")));
    }

    @Test
    void chosenModeIsPassedThroughVerbatim() throws Exception {
        assertTrue(consumerBuildArguments("--optimize", "Debug").contains("-Doptimize=Debug"));
    }
}
