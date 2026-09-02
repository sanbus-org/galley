# Java Bindings

Panama FFI (Java 22+) bindings over `bindings/c/galley.h`. No third-party runtime.

See `docs/bindings_java.md` and `examples/java` for the consumer flow.

One shared library embeds one parser; sessions are not thread-safe.

## Build

```sh
# From repo root, build bindings:
javac --release 22 -d bindings/java/out $(find bindings/java/src/main/java -name "*.java")
java --enable-native-access=ALL-UNNAMED -cp bindings/java/out org.sanbus.galley.build.GalleyBuild <language-dir>

# Then use from Java:
# GALLEY_LIBRARY_PATH=/path/to/libgalley-java.dylib java --enable-native-access=ALL-UNNAMED -cp bindings/java/out:examples/java/out com.example.Demo
```

Library discovery order: `SessionOptions.libraryPath` (explicit) → `GALLEY_LIBRARY_PATH` env → `<language-dir>/libgalley-java.*` → `~/Library/Caches/galley-bindings/java/capi/lib/libgalley-java.*` (macOS) or `~/.cache/galley-bindings/java/capi/lib/libgalley-java.*`.

Environment overrides for the build tool: `ZIG_EXECUTABLE` (default `zig`), `GALLEY_CHECKOUT`, `GALLEY_REPOSITORY`, `GALLEY_TAG` (default `main`).

## Usage

```java
import org.sanbus.galley.*;

try (Session session = new Session()) {
    session.parse("alpha:12,beta:3");
    Node root = session.rootNode();
    System.out.println(new String(session.text(root)));
}
```
