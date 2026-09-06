# Galley JavaScript Example for WebAssembly

Requires `node` ≥ 22.6, `zig`, and `git`.

```sh
npm install --install-links
npx galley-js-wasm .
npx tsx demo.ts
npx galley-js-wasm benchmark
npx tsx benchmark.ts
```

`--install-links` copies the bindings with their dependencies (see
[TypeScript bindings](../../docs/bindings_typescript.md)). Contributors
editing binding sources use plain `npm install` plus `npm install` inside
`bindings/js/wasm` instead.

Build, run, and benchmark conventions: see [examples/README.md](../../README.md).
