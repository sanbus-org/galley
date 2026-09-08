# Java binding test fixture

Keyvalue `procedures.java` copied from `examples/java`; `ll.grm` and `config.zig` are symlinks to the one shared grammar in `bindings/test-fixture` when the binding suite
was decoupled from the user-facing examples. No rewrites: the hooks
only ever import `org.sanbus.galley.*`.

The parser (`_ll-parser.zig`, `procedures.zig`,
`procedures_java.zig`, `metadata.json`, `libgalley-java.*`) is built
into this directory with the stock builder class:

    javac --release 22 -d bindings/java/out $(find bindings/java/src/main/java -name "*.java")
    GALLEY_CHECKOUT=<checkout> java --enable-native-access=ALL-UNNAMED \
      -cp bindings/java/out org.sanbus.galley.build.GalleyBuild bindings/java/test-fixture

and the suite runs against it with (library suffix is platform-specific:
`libgalley-java.so` on Linux, `libgalley-java.dylib` on macOS):

    GALLEY_LIBRARY_PATH=bindings/java/test-fixture/libgalley-java.so \
      mvn -B -f bindings/java/pom.xml test

Edit these sources and the Java suite picks the change up on its next run.
