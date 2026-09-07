# Galley JavaScript Example for Deno

Requires `deno` 2 and `zig` (only the fetch script uses `git`; the build itself needs `GALLEY_CHECKOUT`).

```sh
GALLEY_CHECKOUT=/path/to/galley deno task build
deno task demo
deno task benchmark
```

Build, run, and benchmark conventions: see [examples/README.md](../../README.md). The binding suite lives in `bindings/js/deno`: `deno task test`.
