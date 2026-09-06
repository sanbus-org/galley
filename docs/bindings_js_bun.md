# Bun

Galley-generated parsers can be consumed from Bun through a zero-dependency
`bun:ffi` layer over the same shared library as the C API
([`bindings/c/galley.h`](https://github.com/sanbus-org/galley/blob/main/bindings/c/galley.h)).
The package in
[`bindings/js/bun`](https://github.com/sanbus-org/galley/tree/main/bindings/js/bun)
binds the runtime-neutral
[`bindings/js/core`](https://github.com/sanbus-org/galley/tree/main/bindings/js/core)
(`Session`, `Node`, diagnostics, tree editing — shared with the Node and
Deno bindings) to Bun's FFI, with no native dependencies beyond the built
parser library.

A complete, runnable consumer lives in
[`examples/js/bun`](https://github.com/sanbus-org/galley/tree/main/examples/js/bun);
it is built and executed by CI on every push, byte-for-byte identical in
output to every other example.

Requires Bun 1. No extra permissions: unlike Deno, `bun:ffi` needs no
capability flags.

## Getting Started

Build the parser and shared library for a directory containing `ll.grm`
and `config.zig`:

```sh
cd examples/js/bun
GALLEY_CHECKOUT=/path/to/galley bun install
GALLEY_CHECKOUT=/path/to/galley bunx galley-js-bun .
bun demo.ts
```

The build generates the parser (`--emit-metadata`), compiles the shared
library through Galley's generic consumer build file, and copies
`libgalley-js-bun.{dylib,so}` next to your grammar. Import the bindings
from that directory:

```ts
import { Session, version, hasAst } from "galley-js-bun";
```

`ZIG_EXECUTABLE` selects zig. Bun runs TypeScript directly — the adapter
itself needs no build step to run, though `bun run build` typechecks (and
emits `dist/` for publishing) via `tsc`.

## Procedures

Hook files work exactly like the Node bindings (`export function
reduction_<Var>(args)` / `export function hook_<name>(args)` in
`procedures.ts`, dispatched through the shared `galley_install_js_dispatch`
shim). Bun loads TypeScript synchronously, so `procedures.*` in the
language directory is auto-discovered via `require()`, just like Node —
no explicit registration needed.

## Tests

```sh
cd examples/js/bun
bun install
bun ../../../bindings/js/bun/tests/test_bindings.mjs
```

The suite mirrors `bindings/js/node/tests/test_bindings.mjs` behavior by
behavior.

## Related Pages

- [TypeScript](/bindings_typescript) — the Node bindings over the same core
- [Deno](/bindings_js_deno) — the Deno bindings over the same core
- [C and C++](/bindings_c) — the underlying C ABI
