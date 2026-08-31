# Examples

Each directory is a consumer of the same key/value demo and JSON throughput
benchmark.

- **Zig** (`examples/zig`) uses Galley's native runtime. The API manual is
  [`docs/using-galley.md`](../docs/using-galley.md). `--bootstrap-zig-project`
  is a stub for a new grammar, not a second API.
- **C, C++, Rust, Go, Python, TypeScript** use the C ABI of that runtime.
  Their demo output matches the Zig example.

Zig is not a binding. The other examples are.
