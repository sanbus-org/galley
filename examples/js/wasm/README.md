# Galley JavaScript Example for WebAssembly

Requires `node` ≥ 22.6 and `zig` (only the fetch script uses `git`; the build itself needs `GALLEY_CHECKOUT`).

```sh
npm install --install-links
GALLEY_CHECKOUT=/path/to/galley npx galley-js-wasm .
npx tsx demo.ts
GALLEY_CHECKOUT=/path/to/galley npx galley-js-wasm benchmark
npx tsx benchmark.ts
```

`--install-links` copies the bindings with their dependencies (see
[JavaScript bindings](../../docs/bindings_javascript.md)). Contributors
editing binding sources use plain `npm install` plus `npm install` inside
`bindings/js/wasm` instead.

Build, run, and benchmark conventions: see [examples/README.md](../../README.md).
