# Galley C++ example

Requires `cmake`, `zig`, and `git`.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/bin/demo
./build/bin/benchmark
```

The build fetches Galley on its own; pass `-DGALLEY_CHECKOUT=/path/to/galley` to develop against a local Galley checkout instead. Pass a grammar-source file as an argument to parse that file instead of running the built-in demo. `benchmark` prints JSON parse throughput (no AST, no procedures, no error recovery). Optional arguments are `[path] [iterations]`. Fetch large samples first: `bash scripts/fetch-large-samples.sh json`.
