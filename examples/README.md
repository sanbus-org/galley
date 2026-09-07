# Examples

Each directory is a consumer of the same key/value demo and JSON throughput
benchmark.

- **Zig** (`examples/zig`) uses Galley's native runtime. The API manual is
  [`docs/using-galley.md`](../docs/using-galley.md). `--bootstrap-zig-project`
  is a stub for a new grammar, not a second API.
- **C, C++, Rust, Go, Python, TypeScript** use the C ABI of that runtime.
  Their demo output matches the Zig example.

Zig is not a binding. The other examples are.

CI (`example-benchmarks`) builds every example's JSON throughput binary
ReleaseFast, runs interleaved rounds on one machine, and fails if a C-ABI
example lags native Zig by a wide margin.

## Building a binding example

Every binding example needs `GALLEY_CHECKOUT` pointing at a Galley checkout:

```sh
GALLEY_CHECKOUT=/path/to/galley <build command>
```

For convenience, `GALLEY_CHECKOUT=$(examples/scripts/fetch-galley.sh)`
(run from the repo root) fetches a checkout into the system cache — that
cache is examples-only, not part of the bindings. The CMake examples (`c`,
`cpp`) take `-DGALLEY_CHECKOUT=/path/to/galley` instead of the env var.

Each build compiles the grammar library directly next to the grammar.
Regenerate after changing the grammar; commit nothing the build generates.

## Running demos and benchmarks

Every demo parses an optional grammar-source file passed as its argument
instead of running the built-in demo. Every benchmark prints JSON parse
throughput with no AST, no procedures, and no error recovery, and takes
optional `[path] [iterations]` arguments. Fetch large samples first (from
the repo root): `bash scripts/fetch-large-samples.sh json`.
