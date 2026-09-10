# JavaScript

One package for Node, Bun, Deno, and browsers:
[`@sanbus/galley`](https://github.com/sanbus-org/galley/tree/main/bindings/js/universal)
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
import { Session, init, backend } from "@sanbus/galley";

await init();
console.log(backend()); // "native" or "wasm"
const session = new Session();
```

`init()` accepts `{ libraryPath, wasmPath, url, wasmBytes, quiet }`.
Sessions accept the same options per instance; `new Session()` with no
options uses the initialized backend (or resolves synchronously under
Node and Bun).

Browsers use the wasm-only entry, resolved automatically through the
`browser` export condition (verified under vite and webpack with no
shims), or imported explicitly:

```ts
import { Session, init } from "@sanbus/galley/browser";

await init({ url: "/parsers/language.wasm" });
const session = new Session();
```

## Build

One entry builds both artifacts next to the grammar — the shared native
library (serves Node, Bun, and Deno) and the wasm module (serves browsers
and the fallback leg):

```sh
npx galley build <language-dir>              # both legs
npx galley build <language-dir> --native-only
npx galley build <language-dir> --wasm-only
```

Requires `zig` (`ZIG_EXECUTABLE` overrides) and `GALLEY_CHECKOUT` pointing
at a Galley working tree. The per-adapter builders (`npx galley-js-node`,
`npx galley-js-bun`, `npx galley-js-wasm`, the Deno `build.ts`) remain as
thin wrappers over the same shared gate for single-leg builds.

The command generates the parser (`--emit-metadata`), builds the artifact
through Galley's generic consumer build file, and detects optional hook
files next to your grammar (`procedures.ts` for TypeScript hooks,
`procedures.c` for legacy C hooks, `procedures.zig`,
`ll_error_messages.zig`). Regenerate after changing the grammar; commit
nothing the command generates. One shared library embeds one parser —
split grammars across language directories exactly like the other
bindings.

Pass the built file with `libraryPath`, or name it once with
`GALLEY_LIBRARY_PATH`. Nothing is searched: a missing file is a loud error.

Two ways to install, depending on what you are doing:

```sh
npm install --install-links   # consuming: self-contained copy, nothing else to install
npm install                   # contributing: live symlink into the checkout
```

A plain `npm install` links the bindings without their dependencies, so a
contributor must also install inside the adapter package. With
`--install-links` the package is copied with its whole subtree and works
with no second install. Copies go stale: after changing binding sources,
delete the copied `@sanbus` directory under `node_modules` and install
again.

## Performance Notes

The FFI boundary is the only overhead over the C API:

- Every method is a direct call into the backend; no JSON or subprocess
  marshalling.
- Node handles are `Node` objects that wrap a stable address in the
  library's non-relocating storage and keep a strong reference to their
  owning `Session`; plain `bigint` addresses are also accepted wherever a
  `Node` is expected, and `Number(node)` / `BigInt(node)` recovers the
  address. Iteration and indexing are zero-copy (`for (const child of node)`, `node.at(0)`, `node.length`).
- Text accessors (`text`, `symbolNameBytes`, diagnostic tokens) return
  `Uint8Array` copies with no UTF-8 decoding; decode on demand via
  `Buffer.from(bytes).toString("utf-8")`.
- `parse()` and `parseSentinel()` accept `string`, `Buffer`, or `Uint8Array`.
  Bytes are passed by pointer and length with no UTF-16 transcode; a
  `string` is encoded to UTF-8 once per call. The session still copies
  into its own storage so node text stays valid after return.
- All calls are synchronous and hold no additional threads; sessions are not
  thread-safe. Use one session per thread or guard externally.

Node text, diagnostics, and expected-token data remain valid only until the
next parse on the same session; every accessor copies before returning.
`Node` methods check that their session is still open and throw after
`session.close()` or exiting a `using` block.

## Procedures

Set `pub const procedures = true;` in your grammar's `config.zig` and
implement the hooks in TypeScript in a `procedures.ts` file next to your
grammar — an ordinary TypeScript module imported by your project and
dispatched through a generated shim at runtime. No C anywhere on the
consumer side, mirroring Python's `procedures.py`
and Rust's `procedures.rs`:

```ts
// procedures.ts
import type { ProcedureArguments } from "@sanbus/galley";

export function reduction_Pair(args: ProcedureArguments): void {
  const node = args.currentNode();
  if (node === null) return;
  const [line, column] = node.lineColumn() ?? [0, 0];
  const text = Buffer.from(node.text() ?? []).toString("utf-8");
  process.stderr.write(`Pair ${text} (${node.length} children) at ${line}:${column}\n`);
}

export function reduction_KeyTail(args: ProcedureArguments): void {
  args.dropIfEmpty();
}

export function hook_print(args: ProcedureArguments): void {
  const node = args.currentNode();
  if (node === null) return;
  const [line, column] = node.lineColumn() ?? [0, 0];
  const text = Buffer.from(node.text() ?? []).toString("utf-8");
  process.stderr.write(`@print "${text}" at ${line}:${column}\n`);
}
```

Native backends load `procedures.*` from the directory holding the shared
library at first `Session` construction, registering any
`reduction`/`reduction_*`/`hook_*` exports, exactly like Python's
`import procedures` at extension load. Explicit registration composes
with that and takes precedence (required on Deno and browsers, which
have no auto-discovery):

```ts
import * as procedures from "./procedures.js";
import { Session, installProcedures } from "@sanbus/galley";

// explicit registration, e.g. for hooks living elsewhere:
installProcedures(procedures);
// or for a single hook:
// installProcedure("reduction_KeyTail", (args) => args.dropIfEmpty());
```

The build detects `procedures.ts` / `procedures.js` and generates a
shim that routes every grammar hook through one callback, exactly like
Python's `procedures_python.zig` and Go's `procedures_go.zig`.
Unregistered hooks are silent no-ops. You can also manage hooks at runtime:

```ts
import { installProcedure, installProcedures, clearProcedures, listProcedures } from "@sanbus/galley";
installProcedure("reduction_Pair", (args) => { args.currentNode()?.text(); });
listProcedures(); // ["reduction_Pair", ...]
clearProcedures();
```

Reduction hooks keep their `reduction_<VariableName>` names (plus the
general `reduction`); author-defined grammar hooks are declared as
`hook_<name>`. Legacy `procedures.c` / `procedures.cpp` files are still
accepted and compiled into the shared library when no TypeScript file is
present, exactly like the C/C++ consumers. Semantic payloads are unavailable
through bindings.

## Semantic Errors

A hook reports a semantic error when the input parses but its meaning is
invalid. `reportSemanticError` records the diagnostic, marks the node, and
returns the running total so hooks can limit themselves. Parsing continues;
a syntax-clean parse with any semantic error throws with code
`STATUS_ERROR_SEMANTIC` (-12):

```ts
if (value > 999) {
  args.reportSemanticError("value out of range");
}
```

Read them through `session.diagnostic()` / `session.diagnostics()`; the
snapshot carries `kind === KIND_SEMANTIC` and a `semantic` pair of
`[variable, message]`.

## Tree Walking

`session.walk(root)` returns a pre-order `Walker` over the last successful
parse, yielding one `{ node, depth, isSemanticError }` per step with the
root at depth 0 — the shared runtime walker, so order and depths match
every other binding. The walker is iterable and closable (`using`
supported); `skipChildren()` prunes the last yielded node's children.
Pass `true` to prune semantic-error subtrees:

```ts
using walker = session.walk(session.rootNode()!)!;
for (const step of walker) {
  console.error(`${"  ".repeat(step.depth)}${step.node.symbolName()}`);
}
```

## Error Messages

Run `galley --fill-error-messages <language-dir>` and edit the generated
`ll_error_messages.zig` next to your grammar. The build command detects it
and compiles it into the shared library;
`session.diagnostic().message` then returns your hooks' text instead of the
built-in generic renderer. LR grammars use `lr_error_messages.zig`.

## Sessions

```ts
import { Session, GalleyError } from "@sanbus/galley";

using session = new Session({ maxErrors: 10, recoveryWindow: 500 });
try {
  const parsed = session.parse("alpha:12,beta:3");
} catch (err) {
  const galleyErr = err as GalleyError;
  console.error(`${galleyErr.diagnostic?.line}:${galleyErr.diagnostic?.column}: ${galleyErr.diagnostic?.message}`);
}
```

Options mirror the runtime defaults: `maxErrors: 10`,
`recoveryWindow: 500`, `stackOverflowRecovery: false`,
`syntaxErrorStackDepth: 0`, `verbosity: 0`,
`astPreallocationRatio: -1.0`, `astPreallocationCap: 0`.
`messageOverrides` registers per-session overrides:

```ts
const session = new Session({
  messageOverrides: { Number: "expected a number after ':' (digits only) at line {line}" },
});
// or later:
session.setMessageOverride("Number", "expected a number at {line}:{column}");
```

Failures throw `GalleyError`, whose `code` and `diagnostic` carry the raw
status code and the snapshot for that failure (`error.diagnostic` is `null`
when no diagnostic, otherwise a `Diagnostic`; `session.diagnostic()` returns
the last diagnostic).

`Session` implements `Symbol.dispose` so `using`/`await using` closes on
exit, and `close()` is idempotent. Every session method that takes a node
also accepts `Node | bigint`; session methods that return nodes return
`Node`. Nodes are bound to their session:
`root = session.rootNode()` then `root.text()`, `root.symbolName()`,
`root.span()`, `root.lineColumn()`, `root.parent()`,
`root.firstChild()` / `root.lastChild()` / `root.nextSibling()` /
`root.priorSibling()`, `root.children()` (`Node[]`), `root.length`,
`root.at(i)`, and `for (const child of root)` all read directly from the
node. Editing helpers are available both ways:
`root.cleanChildren()` / `session.cleanChildren(root)` and
`root.appendChildren(chain)` / `session.appendChildren(root, chain)`
(where `chain` is a detached head); the remaining tree edits
(`insertBefore`, `removeSelf`, `removeSiblings`, `insertChildrenAt`,
`removeChildrenAt`, `promoteChildrenOverWrapper`, `unlinkWrapper`)
live on `Session` and accept `Node | bigint`. Missing links return `null`.
`session.diagnostics()` returns every recorded diagnostic. Nodes compare by
identity (`a.equals(b)` checks same session and address), and support
`Number(node)` / `BigInt(node)` to recover the raw address.

`session.diagnostic()` returns a frozen snapshot (`Diagnostic`) with `kind`,
`line`, `column`, `message`, `messageAnsi`,
`unexpectedToken`, `expectedTokens`, `context`, `syntaxErrorCount`,
indentation details, and the full structured recovery information — or
`null` when the last parse succeeded.

## Appendix: backends

### Node

[`@sanbus/galley-node`](https://github.com/sanbus-org/galley/tree/main/bindings/js/node)
over a per-grammar NAPI addon (`bindings/js/node/addon.c`, raw `node_api.h`,
compiled by the builder with `zig cc`); TypeScript keeps the neutral
`FfiPort` over the addon. Requires Node 18+. A complete consumer lives in
[`examples/js/node`](https://github.com/sanbus-org/galley/tree/main/examples/js/node),
built and executed by CI on every push, byte-for-byte identical in output
to the C, C++, Rust, Go, and Python examples.

```sh
npm install
npx galley-js-node <language-dir>
```

```ts
import { Session, version, hasAst } from "@sanbus/galley-node";
```

`ZIG_EXECUTABLE` selects zig. `GALLEY_CHECKOUT` (required) points at a
Galley working tree — for convenience,
`GALLEY_CHECKOUT=$(examples/scripts/fetch-galley.sh)` fetches one into
the system cache, but that cache is examples-only, not part of the
bindings. The suite mirrors the universal behavior claim for claim:

```sh
node ../../../bindings/js/node/tests/test_bindings.mjs
```

### Bun

[`@sanbus/galley-bun`](https://github.com/sanbus-org/galley/tree/main/bindings/js/bun)
over zero-dependency `bun:ffi`, with no native dependencies beyond the
built parser library. Requires Bun 1. No extra permissions: unlike Deno,
`bun:ffi` needs no capability flags. A complete consumer lives in
[`examples/js/bun`](https://github.com/sanbus-org/galley/tree/main/examples/js/bun),
built and executed by CI on every push, byte-for-byte identical in output
to every other example.

```sh
cd examples/js/bun
GALLEY_CHECKOUT=/path/to/galley bun install
GALLEY_CHECKOUT=/path/to/galley bunx galley-js-bun .
bun demo.ts
```

```ts
import { Session, version, hasAst } from "@sanbus/galley-bun";
```

`ZIG_EXECUTABLE` selects zig. Bun runs TypeScript directly — the adapter
itself needs no build step to run, though `bun run build` typechecks (and
emits `dist/` for publishing) via `tsc`. Hook files work exactly like
Node; Bun loads TypeScript synchronously, so `procedures.*` next to the
shared library loads at first `Session` — no explicit registration
needed. The suite mirrors the Node suite behavior by behavior:

```sh
cd examples/js/bun
bun install
bun ../../../bindings/js/bun/tests/test_bindings.mjs
```

### Deno

[`@sanbus/galley-deno`](https://github.com/sanbus-org/galley/tree/main/bindings/js/deno)
over zero-dependency `Deno.dlopen`, with no subprocess or code-generation
at runtime. Requires Deno 2. Three permissions: `--allow-ffi` (loading
the library), `--allow-read` (library discovery, `parseFile`),
`--allow-env` (library discovery). A complete consumer lives in
[`examples/js/deno`](https://github.com/sanbus-org/galley/tree/main/examples/js/deno),
built and executed by CI on every push, byte-for-byte identical in output
to every other example.

```sh
cd examples/js/deno
GALLEY_CHECKOUT=/path/to/galley deno task build
deno task demo
```

```ts
import { Session, version, hasAst } from "@sanbus/galley-deno";
```

`ZIG_EXECUTABLE` selects zig. Deno runs the adapter's TypeScript sources
directly — no build step. Sources use explicit `.ts` import specifiers, so
plain strict `deno run` / `deno check` work with no extra flags (already
wired into the `deno task` entries). One difference from Node: Deno has
no synchronous module load, so there is no `require()`-based
auto-discovery — register explicitly:

```ts
import { installProcedures } from "@sanbus/galley-deno";
import * as procedures from "./procedures.ts";

installProcedures(procedures);
```

The suite mirrors the Node suite behavior by behavior. It typechecks the
adapter (`deno check src/index.ts`) and runs the suite with `--no-check`,
matching the Node setup where tests are excluded from `tsconfig.json`:

```sh
cd bindings/js/deno
deno task test
```

### WebAssembly

[`@sanbus/galley-wasm`](https://github.com/sanbus-org/galley/tree/main/bindings/js/wasm)
over a WASI reactor module built from the same C API. Requires Node 18.
No extra permissions and no WASI runtime: the adapter embeds a minimal
`wasi_snapshot_preview1` stub (real entropy and clocks; filesystem calls
report unavailable — the file is read by the host and parsed from
memory). It runs anywhere WebAssembly runs. A complete consumer lives in
[`examples/js/wasm`](https://github.com/sanbus-org/galley/tree/main/examples/js/wasm),
built and executed by CI on every push, byte-for-byte identical in output
to every other example.

```sh
cd examples/js/wasm
GALLEY_CHECKOUT=/path/to/galley npm install
GALLEY_CHECKOUT=/path/to/galley npx galley-js-wasm .
npx tsx demo.ts
```

```ts
import { Session, version, hasAst } from "@sanbus/galley-wasm";
```

`ZIG_EXECUTABLE` selects zig. Under Node the module auto-initializes
synchronously on first use; elsewhere (browsers) call `await init()` first
— `await init({ url })` or `await init({ bytes })` — then use the
synchronous `Session` API. `initSync()` is available for Node-only scripts.
Under Node `procedures.*` next to the shared library loads via
`require()`; elsewhere register explicitly with `installProcedures` from
`@sanbus/galley-core` before parsing. The suite mirrors the Node suite
behavior by behavior:

```sh
cd examples/js/wasm
npm install
node ../../../bindings/js/wasm/tests/test_bindings.mjs
```

### Browsers (wasm only)

No FFI exists in browsers, so the browser entry is a separate wasm-only
surface (same `Session` API, its own `init` since it never attempts
native legs) with no `node:` specifier anywhere in its graph, so vite
and webpack resolve it with no shims (verified: both bundlers pick the
browser file for the default import too). `@sanbus/galley-wasm` ships
the matching `@sanbus/galley-wasm/browser` entry.

```ts
import { Session, init } from "@sanbus/galley/browser";

await init({ url: "/parsers/language.wasm" });
const session = new Session();
```

`init()` accepts `{ libraryPath, wasmPath, url, wasmBytes, quiet }` —
the same names as the default entry. Hooks register explicitly with
`installProcedures` before parsing.

## Related Pages

- [C and C++](/bindings_c) — the underlying C ABI
- [Python](/bindings_python), [Rust](/bindings_rust) and [Go](/bindings_go) — bindings over the same shared library
- [Configuration](/configuration) — config.zig schema
- [Grammar Guidelines](/grammar_guidelines)
