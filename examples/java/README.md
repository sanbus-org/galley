# Galley Java example

Requires `java` ≥ 22, `javac`, `zig` 0.16, and `git` (only the fetch script uses `git`; the build itself needs `GALLEY_CHECKOUT`).

```sh
# from repo root
javac --release 22 -d bindings/java/out $(find bindings/java/src/main/java -name "*.java")
java --enable-native-access=ALL-UNNAMED -cp bindings/java/out org.sanbus.galley.build.GalleyBuild examples/java
javac --release 22 -cp bindings/java/out -d examples/java/out $(find examples/java/src/main/java -name "*.java")
java --enable-native-access=ALL-UNNAMED -cp bindings/java/out:examples/java/out com.example.Demo
java --enable-native-access=ALL-UNNAMED -cp bindings/java/out org.sanbus.galley.build.GalleyBuild examples/java/benchmark
java --enable-native-access=ALL-UNNAMED -cp bindings/java/out:examples/java/out com.example.Benchmark
```

Build, run, and benchmark conventions: see [examples/README.md](../README.md).
