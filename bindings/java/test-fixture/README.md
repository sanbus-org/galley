# Java binding test fixture

Keyvalue `procedures.java` copied from `examples/java/kv`; `ll.grm` and `config.zig` are symlinks to the one shared grammar in `bindings/test-fixture` when the binding suite
was decoupled from the user-facing examples. No rewrites: the hooks
only ever import `org.sanbus.galley.*`.

The hook source lives in the `test_fixture` package (the packaged
layout is canonical: only it yields the generated `Parser` alongside the
shim); the builder emits the banner-guarded `test_fixture/Parser`, which
installs every hook the class defines, next to it, and refuses to
overwrite a foreign file there.

The parser (`_ll-parser.zig`, `procedures.zig`,
`host_procedures.zig`, `libgalley-java.*`) is built
into this directory with the stock builder class:

    javac --release 22 -d bindings/java/out $(find bindings/java/src/main/java -name "*.java")
    GALLEY_CHECKOUT=<checkout> java --enable-native-access=ALL-UNNAMED \
      -cp bindings/java/out org.sanbus.galley.build.GalleyBuild bindings/java/test-fixture

and the suite runs against it, locating the built file itself:

    mvn -B -f bindings/java/pom.xml test

Edit these sources and the Java suite picks the change up on its next run.
