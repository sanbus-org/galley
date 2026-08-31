# Galley TypeScript example

Requires `node` ≥ 22.6, `zig`, and `git`.

```sh
npm install
npx galley-typescript-bindings .
npx tsx demo.ts
npx galley-typescript-bindings benchmark
npx tsx benchmark.ts
```

The build fetches Galley on its own; set `GALLEY_CHECKOUT=/path/to/galley` to develop against a local Galley checkout instead. Pass a grammar-source file as an argument to parse that file instead of running the built-in demo. `benchmark.ts` parses `languages/json/samples/code-01.json` 50,000 times through a no-AST, no-procedures, no-error-recovery JSON parser and prints bytes/s.
