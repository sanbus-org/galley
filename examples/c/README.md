# Galley C example

Requires `cmake`, `zig`, and `git`.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/bin/demo
./build/bin/benchmark
```

The build fetches Galley on its own; pass `-DGALLEY_CHECKOUT=/path/to/galley` to develop against a local Galley checkout instead. Pass a grammar-source file as an argument to parse that file instead of running the built-in demo. `benchmark` parses `languages/json/samples/code-01.json` 50,000 times through a no-AST, no-procedures, no-error-recovery JSON parser and prints bytes/s.
