package org.sanbus.galley;

import java.io.FileNotFoundException;

/**
 * The parser artifact a binding was told to load is not where it was told.
 * Thrown by artifact resolution instead of searching elsewhere: carries
 * the machine-readable code and the message shape (path plus the exact
 * build command for this binding).
 */
public class MissingArtifactException extends FileNotFoundException {
    /**
     * Machine-readable failure code: {@code galley:missing-artifact}.
     */
    public static final String CODE = "galley:missing-artifact";

    private final String artifactPath;

    private static String buildMessage(String detail) {
        return "galley: parser artifact not found: " + detail + ".\n"
                + "Build it first: java --enable-native-access=ALL-UNNAMED -cp bindings/java/out"
                + " org.sanbus.galley.build.GalleyBuild <language-dir>\n"
                + "or set GALLEY_LIBRARY_PATH=/path/to/" + org.sanbus.galley.internal.GalleyLibraryLoader.libFileName();
    }

    /**
     * @param artifactPath exact path that held no artifact; null or empty
     *                     when no path was given at all.
     */
    public MissingArtifactException(String artifactPath) {
        super(buildMessage(artifactPath == null || artifactPath.isEmpty()
                ? "no parser artifact given; pass a path to Galley.load or set GALLEY_LIBRARY_PATH"
                : "at " + artifactPath));
        this.artifactPath = artifactPath;
    }

    /** Machine-readable failure code ({@link #CODE}). */
    public String getCode() { return CODE; }

    /** Exact path that held no artifact; null when no path was given. */
    public String getArtifactPath() { return artifactPath; }
}
