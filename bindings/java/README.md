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
# java --enable-native-access=ALL-UNNAMED -cp bindings/java/out:examples/java/out com.example.Demo
```

## Tests

```sh
# From repo root, after building the fixture library above;
# the suite locates the built file itself:
mvn -B -f bindings/java/pom.xml test
```

Library resolution: `Galley.load(path)` takes the artifact path explicitly, or a loud error names the exact path. Nothing is searched.

Environment overrides for the build tool: `ZIG_EXECUTABLE` (default `zig`), `GALLEY_CHECKOUT` (required). For convenience, `GALLEY_CHECKOUT=$(examples/scripts/fetch-galley.sh)` fetches one — that cache is examples-only, not part of the bindings.

## Usage

```java
import org.sanbus.galley.*;

Parser parser = Galley.load(path);
try (Session session = parser.openSession()) {
    session.parse("alpha:12,beta:3");
    Node root = session.rootNode();
    System.out.println(new String(session.text(root)));
}
```
