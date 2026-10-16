# Examples

Each directory is a consumer of the same key/value demo and parse
throughput benchmark.

- **Zig** (`examples/zig`) uses Galley's native runtime. The API manual is
  [`docs/using-galley.md`](../docs/using-galley.md). `--bootstrap-zig-project`
  is a stub for a new grammar, not a second API.
- **C, C++, Rust, Go, Python, TypeScript, Java** use the C ABI of that runtime.
  Their demo output matches the Zig example.

Zig is not a binding. The other examples are.

CI (`benchmark`) runs a matrix over parser configurations: seven JSON rows
covering AST, procedures, and error recovery, plus one row with
indentation syntax. Each row reconfigures the grammar
(`scripts/configure-benchmarks.sh`) and compares the Zig benchmark with
builds from the parent commit and the `performance-reference` tag: it
fails when Zig runs more than 0.5% more instructions, or loses more than
10% of its throughput.

The bindings run the parser Zig runs whatever the configuration, so only
the `json-base` row builds them: the python, js, and java benchmarks
compile `languages/<grammar>` directly, while the compiled examples keep
their own benchmark grammar directories pointed at the same grammar. That
row runs every binding interleaved with Zig on one machine and fails when
one falls below 90% of Zig's throughput.

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
instead of running the built-in demo. Every benchmark takes the sample
file as a required argument plus optional `[iterations]`; the python, js,
and java benchmarks additionally take the built parser package directory
first (any directory the matching binding build produced, e.g. `./json`
or `languages/json`). Fetch large samples first (from the repo root):
`bash scripts/fetch-large-samples.sh json`.
