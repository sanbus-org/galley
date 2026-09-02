# Galley Java example

Requires `java` ≥ 22, `javac`, `zig` 0.16, and `git` (`GALLEY_CHECKOUT` skips `git`).

```sh
# from repo root
javac --release 22 -d bindings/java/out $(find bindings/java/src/main/java -name "*.java")
java --enable-native-access=ALL-UNNAMED -cp bindings/java/out org.sanbus.galley.build.GalleyBuild examples/java
javac --release 22 -cp bindings/java/out -d examples/java/out $(find examples/java/src/main/java -name "*.java")
java --enable-native-access=ALL-UNNAMED -cp bindings/java/out:examples/java/out com.example.Demo
java --enable-native-access=ALL-UNNAMED -cp bindings/java/out org.sanbus.galley.build.GalleyBuild examples/java/benchmark
java --enable-native-access=ALL-UNNAMED -cp bindings/java/out:examples/java/out com.example.Benchmark
```

The build fetches Galley on its own; set `GALLEY_CHECKOUT=/path/to/galley` to develop against a local Galley checkout instead. Pass a grammar-source file as an argument to `com.example.Demo` instead of running the built-in demo. `com.example.Benchmark` prints JSON parse throughput (no AST, no procedures, no error recovery). Optional arguments are `[path] [iterations]`. Fetch large samples first: `bash scripts/fetch-large-samples.sh json`.
