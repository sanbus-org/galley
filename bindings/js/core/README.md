# galley-js-core

Runtime-neutral core for the Galley JavaScript bindings. Pure TypeScript:
no `node:`, `bun:`, or `Deno` imports (enforced by `"types": []` in
`tsconfig.json` — only `TextEncoder`/`TextDecoder`/`console` from standard
lib). Each runtime ships a thin adapter package implementing `FfiPort`
(`src/port.ts`) over the same `bindings/c/galley.h` shared library:

- `bindings/js/node` — Node via koffi
- `bindings/js/bun` — Bun via `bun:ffi`
- `bindings/js/deno` — Deno via `Deno.dlopen`

`Session`, `Node`, `Walker`, diagnostics, and the procedure registry live
here exactly once. Adapters own library discovery, memory copying, native
callback installation, and the public package surface.
