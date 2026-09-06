# Galley JavaScript Example for Bun

Requires `bun`, `zig`, and `git`.

```sh
bun install
bunx galley-js-bun .
bun demo.ts
bun benchmark.ts
```

The build fetches Galley on its own; set `GALLEY_CHECKOUT=/path/to/galley` to develop against a local Galley checkout instead. Pass a grammar-source file as an argument to parse that file instead of running the built-in demo. `bun benchmark.ts` prints JSON parse throughput (no AST, no procedures, no error recovery). Optional arguments are `[path] [iterations]`. Fetch large samples first: `bash scripts/fetch-large-samples.sh json`.
