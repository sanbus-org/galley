# Galley JavaScript Example for Bun

Requires `bun` and `zig` (only the fetch script uses `git`; the build itself needs `GALLEY_CHECKOUT`).

```sh
bun install
(cd ../../bindings/js/bun && bun install && bun run build)
GALLEY_CHECKOUT=/path/to/galley bunx galley-js-bun .
bun demo.ts
GALLEY_CHECKOUT=/path/to/galley bunx galley-js-bun benchmark
bun benchmark.ts
```

Build, run, and benchmark conventions: see [examples/README.md](../../README.md).
