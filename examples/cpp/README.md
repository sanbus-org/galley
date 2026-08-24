# Galley C++ example

Requires `cmake`, `zig`, and `git`.

```sh
cmake -S . -B build
cmake --build build
./build/bin/example
```

The build fetches Galley on its own; pass `-DGALLEY_CHECKOUT=/path/to/galley` to develop against a local Galley checkout instead. Pass a grammar-source file as an argument to parse that file instead of running the built-in demo.
