# Deno

Galley-generated parsers can be consumed from Deno through a zero-dependency
`Deno.dlopen` layer over the same shared library as the C API
([`bindings/c/galley.h`](https://github.com/sanbus-org/galley/blob/main/bindings/c/galley.h)).
The package in
[`bindings/js/deno`](https://github.com/sanbus-org/galley/tree/main/bindings/js/deno)
binds the runtime-neutral
[`bindings/js/core`](https://github.com/sanbus-org/galley/tree/main/bindings/js/core)
(`Session`, `Node`, diagnostics, tree editing — shared with the Node
bindings) to Deno's FFI, with no subprocess or code-generation at runtime.

A complete, runnable consumer lives in
[`examples/js/deno`](https://github.com/sanbus-org/galley/tree/main/examples/js/deno);
it is built and executed by CI on every push, byte-for-byte identical in
output to every other example.

Requires Deno 2. Three permissions: `--allow-ffi` (loading the library),
`--allow-read` (library discovery, `parseFile`), `--allow-env` (library
discovery).

## Getting Started

Build the parser and shared library for a directory containing `ll.grm`
and `config.zig`:

```sh
cd examples/js/deno
GALLEY_CHECKOUT=/path/to/galley deno task build
deno task demo
```

The build generates the parser (`--emit-metadata`), compiles the shared
library through Galley's generic consumer build file, and copies
`libgalley-js-deno.{dylib,so}` next to your grammar. Import the bindings
via the example's import map:

```ts
import { Session, version, hasAst } from "galley-js-deno";
```

`ZIG_EXECUTABLE` selects zig. Deno runs the adapter's TypeScript sources
directly — no build step. The core sources use Node-style `.js` import
specifiers, so invocations pass `--sloppy-imports` (already wired into the
`deno task` entries).

## Procedures

Hook files work exactly like the Node bindings (`export function
reduction_<Var>(args)` / `export function hook_<name>(args)` in
`procedures.ts`, dispatched through the shared `galley_install_js_dispatch`
shim). One difference: Deno has no synchronous module load, so there is no
`require()`-based auto-discovery — register explicitly:

```ts
import { installProcedures } from "galley-js-deno";
import * as procedures from "./procedures.ts";

installProcedures(procedures);
```

## Tests

```sh
cd bindings/js/deno
deno task test
```

The suite mirrors `bindings/js/node/tests/test_bindings.mjs` behavior by
behavior. It typechecks the adapter (`deno check src/index.ts`) and runs
the suite with `--no-check`, matching the Node setup where tests are
excluded from `tsconfig.json`.

## Related Pages

- [TypeScript](/bindings_typescript) — the Node bindings over the same core
- [Bun](/bindings_js_bun) — the Bun bindings over the same core
- [WebAssembly](/bindings_js_wasm) — the wasm bindings over the same core
- [C and C++](/bindings_c) — the underlying C ABI
