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
npx tsx benchmark.ts ../../languages/json/samples/code-02.json
bun benchmark.ts ../../languages/json/samples/code-02.json
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
conventions: see [examples/README.md](../README.md).

`demo-browser.ts` runs the same grammar and the same procedures as
`demo.ts` through the wasm-only browser entry (`@sanbus/galley/browser`,
`init({ url })`), with the same output rows except the file-parse ones
(`fs` exists only on the runtime side). Bundle with
vite and serve the bundle beside the wasm module and its page:

```sh
./node_modules/.bin/vite build
cp index.html libgalley-js-wasm.wasm dist-browser/
python3 -m http.server 8123 -d dist-browser &
```

Open `http://127.0.0.1:8123/` in a browser (the demo resolves the wasm
module beside the page) and read its console output. Automation drives
the same page in headless Chromium and asserts the console rows:

```sh
./node_modules/.bin/playwright install --only-shell chromium
node run-browser.mjs http://127.0.0.1:8123/index.html
```

The demo logs to the console. (CI runs the same flow headless and
asserts the console rows in order.)
