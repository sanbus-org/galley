# Galley Rust example

Requires `cargo`, `zig`, and `git`.

```sh
cargo run --release
cargo run --release -p galley-rust-benchmark
```

The build fetches Galley on its own; set `GALLEY_CHECKOUT=/path/to/galley` to develop against a local Galley checkout instead. Pass a grammar-source file as an argument to parse that file instead of running the built-in demo. The benchmark package parses `languages/json/samples/code-01.json` 50,000 times through a no-AST, no-procedures, no-error-recovery JSON parser and prints bytes/s.
