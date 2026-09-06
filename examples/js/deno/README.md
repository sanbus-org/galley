# Galley JavaScript Example for Deno

Requires `deno` 2, `zig`, and `git`.

```sh
deno task build
deno task demo
deno task benchmark
```

The build fetches Galley on its own; set `GALLEY_CHECKOUT=/path/to/galley` to develop against a local Galley checkout instead. Pass a grammar-source file to `deno task demo -- <file>` to parse that file instead of running the built-in demo. `deno task benchmark` prints JSON parse throughput (no AST, no procedures, no error recovery). Optional benchmark arguments are `[path] [iterations]`. Fetch large samples first: `bash scripts/fetch-large-samples.sh json`. The binding suite lives in `bindings/js/deno`: `deno task test`.
