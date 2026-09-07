# Galley C++ example

Requires `cmake` and `zig` (only the fetch script uses `git`; the build itself needs `GALLEY_CHECKOUT`).

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DGALLEY_CHECKOUT=/path/to/galley
cmake --build build
./build/bin/demo
./build/bin/benchmark
```

Build, run, and benchmark conventions: see [examples/README.md](../README.md).
