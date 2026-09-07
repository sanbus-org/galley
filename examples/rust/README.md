# Galley Rust example

Requires `cargo` and `zig` (only the fetch script uses `git`; the build itself needs `GALLEY_CHECKOUT`).

```sh
GALLEY_CHECKOUT=/path/to/galley cargo run --release
GALLEY_CHECKOUT=/path/to/galley cargo run --release -p galley-rust-benchmark
```

Build, run, and benchmark conventions: see [examples/README.md](../README.md).
