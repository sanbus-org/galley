# Galley JavaScript example (universal)

Requires `node` ≥ 22 (or Bun 1, or Deno 2) and `zig` (only the fetch
script uses `git`; the build itself needs `GALLEY_CHECKOUT`).

```sh
npm install --install-links
GALLEY_CHECKOUT=/path/to/galley npx galley build .
npx tsx demo.ts
bun demo.ts
deno task demo
GALLEY_CHECKOUT=/path/to/galley npx galley build benchmark
npx tsx benchmark.ts
bun benchmark.ts
deno task benchmark
```

`GALLEY_WASM=1` (or a path to a `.wasm` module) runs the same demo
through the WebAssembly backend instead of native — same output,
byte for byte:

```sh
GALLEY_WASM=1 npx tsx demo.ts
GALLEY_WASM=1 bun demo.ts
GALLEY_WASM=1 deno run --allow-ffi --allow-read --allow-write --allow-env demo.ts
```

`--install-links` copies the bindings with their dependencies (see
[JavaScript bindings](../../docs/bindings_javascript.md)). Contributors
editing binding sources use plain `npm install` plus `npm install` inside
`bindings/js/universal` instead.

One demo runs on every runtime: `await init()` resolves the native
library on Node, Bun, and Deno, and the same code parses through the
wasm fallback wherever native is absent. Build, run, and benchmark
conventions: see [examples/README.md](../../README.md).
