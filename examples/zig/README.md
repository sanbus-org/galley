# Galley Zig example

Native runtime of the same key/value demo and JSON throughput program as
`examples/c`. This is not a binding; the API is [`docs/using-galley.md`](../../docs/using-galley.md).
`--bootstrap-zig-project` writes a stub runner for *your* grammar and is not a
second API.

Requires `zig` 0.16+. This directory is meant to be run from a Galley checkout
(the `build.zig.zon` path dependency points at `../..`). Copied out of the
repository, change that dependency to a `url` and `hash`.

`demo.zig` pins `syntax_error_stack_depth = 1` and a no-op
`syntax_error_reporter` so stdout/stderr match the C-ABI examples. That is
not required native usage; defaults are in the API manual above.

```sh
zig build run
zig build -Doptimize=ReleaseFast run-benchmark
```

Pass a grammar-source file as an argument to parse that file instead of running
the built-in demo. `run-benchmark` parses `languages/json/samples/code-01.json`
50,000 times through a no-AST, no-procedures, no-error-recovery JSON parser and
prints bytes/s.
