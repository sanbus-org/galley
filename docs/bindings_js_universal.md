# Universal (npm)

One package for Node, Bun, Deno, and browsers:
[`@sanbus-org/galley`](https://github.com/sanbus-org/galley/tree/main/bindings/js/universal)
binds the runtime-neutral
[`bindings/js/core`](https://github.com/sanbus-org/galley/tree/main/bindings/js/core)
(`Session`, `Node`, diagnostics, tree editing) to a native backend where
one loads (Node, Bun, Deno) and to WebAssembly otherwise, with no native
dependencies beyond the built parser artifacts.

Call `await init()` once, then use the synchronous `Session` API. Under
Node and Bun the backend also resolves synchronously on first use, so
scripts keep working with no changes. When no native library is found the
WebAssembly backend serves instead, with a one-time performance notice
(opt out with `{ quiet: true }`); when nothing is found at all, `init()`
explains how to build an artifact. A `.wasm` `libraryPath` pins the wasm
backend explicitly.

```ts
import { Session, init, backend } from "@sanbus-org/galley";

await init();
console.log(backend()); // "native" or "wasm"
const session = new Session();
```

`init()` accepts `{ libraryPath, wasmPath, url, wasmBytes, quiet }`.
Sessions accept the same options per instance; `new Session()` with no
options uses the initialized backend (or resolves synchronously under
Node and Bun).

## Related Pages

- [TypeScript](/bindings_typescript) — the Node backend over the same core
- [Deno](/bindings_js_deno) — the Deno backend over the same core
- [Bun](/bindings_js_bun) — the Bun backend over the same core
- [WebAssembly](/bindings_js_wasm) — the wasm backend over the same core
- [C and C++](/bindings_c) — the underlying C ABI
