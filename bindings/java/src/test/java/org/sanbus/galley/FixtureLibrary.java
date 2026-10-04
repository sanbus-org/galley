package org.sanbus.galley;

import java.net.URISyntaxException;
import java.nio.file.Files;
import java.nio.file.Path;

import org.sanbus.galley.internal.GalleyLibraryLoader;

/**
 * The fixture libraries this suite loads: one directory per fixture
 * beside the binding's own sources, each holding the artifact file name
 * for this platform. The suite derives the path itself — nothing reads
 * the environment, and a missing fixture is a loud error naming the path.
 */
final class FixtureLibrary {

    private FixtureLibrary() {}

    /** Where this suite's classes were compiled, as a directory. */
    private static Path classLocation() {
        try {
            var source = FixtureLibrary.class.getProtectionDomain().getCodeSource();
            if (source == null) {
                throw new IllegalStateException("the test classes have no code source");
            }
            return Path.of(source.getLocation().toURI());
        } catch (URISyntaxException e) {
            throw new IllegalStateException("the test classes have an unreadable location", e);
        }
    }

    /**
     * Absolute path of {@code bindings/java/<fixtureName>/<artifact file name>},
     * derived from where this suite's classes were compiled.
     *
     * @throws IllegalStateException when the binding directory cannot be
     *                               derived or the fixture was not built.
     */
    static String path(String fixtureName) {
        Path classes = classLocation();
        Path target = classes.getParent();
        Path bindingDirectory = target != null ? target.getParent() : null;
        if (bindingDirectory == null || !Files.isRegularFile(bindingDirectory.resolve("pom.xml"))) {
            throw new IllegalStateException("cannot derive the binding directory from the test classes at "
                    + classes + "; expected them under bindings/java/target");
        }
        Path library = bindingDirectory.resolve(fixtureName)
                .resolve(GalleyLibraryLoader.libFileName());
        if (!Files.isRegularFile(library)) {
            throw new IllegalStateException("fixture library missing: " + library
                    + "; build it with GalleyBuild bindings/java/" + fixtureName);
        }
        return library.toString();
    }
}
