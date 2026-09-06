# Galley TypeScript example

Requires `node` ≥ 22.6, `zig`, and `git`.

```sh
npm install
npx galley-js-node .
npx tsx demo.ts
npx galley-js-node benchmark
npx tsx benchmark.ts
```

The build fetches Galley on its own; set `GALLEY_CHECKOUT=/path/to/galley` to develop against a local Galley checkout instead. Pass a grammar-source file as an argument to parse that file instead of running the built-in demo. `benchmark.ts` prints JSON parse throughput (no AST, no procedures, no error recovery). Optional arguments are `[path] [iterations]`. Fetch large samples first: `bash scripts/fetch-large-samples.sh json`.
