# TypeScript

Galley-generated parsers can be consumed from TypeScript / Node.js through a
`koffi`-based FFI layer over the same shared library as the C API
([`bindings/c/galley.h`](https://github.com/sanbus-org/galley/blob/main/bindings/c/galley.h)).
The package in
[`bindings/js/node`](https://github.com/sanbus-org/galley/tree/main/bindings/js/node)
wraps that API directly — sessions, `Node` objects, structured diagnostics,
and tree editing — with no subprocess or code-generation at runtime.

A complete, runnable consumer lives in
[`examples/js/node`](https://github.com/sanbus-org/galley/tree/main/examples/js/node);
it is built and executed by CI on every push, byte-for-byte identical in
output to the C, C++, Rust, Go, and Python examples.

## Getting Started

Add the bindings package to your `package.json` and point it at a Galley
checkout:

```json
{
  "dependencies": {
    "galley-js-node": "file:../../../bindings/js/node"
  }
}
```

Then generate the parser for your language directory (a directory
containing `ll.grm` and `config.zig`):

```sh
npm install
npx galley-js-node <language-dir>
```

The command generates the parser (`--emit-metadata`), builds the shared
library through Galley's generic consumer build file, detects optional hook
files next to your grammar (`procedures.ts` for native TypeScript hooks,
`procedures.c` for legacy C hooks, `procedures.zig`,
`ll_error_messages.zig`), and copies `libgalley-js-node.{dylib,so}` next
to your grammar. Import the bindings from that directory:

```ts
import { Session, version, hasAst } from "galley-js-node";
```

`ZIG_EXECUTABLE` selects zig. The TypeScript package targets Node 18+.
`GALLEY_CHECKOUT` uses an existing Galley working tree; otherwise the
command clones `GALLEY_REPOSITORY` at `GALLEY_TAG` (default `main`),
matching the Rust, Go, and Python consumers. Regenerate after changing the
grammar; commit nothing the command generates. One shared library embeds one
parser — split grammars across language directories exactly like the other
bindings.

`GALLEY_LIBRARY_PATH` overrides the discovery of `libgalley-js-node.*`
when the library lives elsewhere (e.g. in a cache dir).

## Performance Notes

The FFI boundary is the only overhead over the C API:

- Every method is a direct `koffi` call; no JSON or subprocess marshalling.
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
import type { ProcedureArguments } from "galley-js-node";

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

They are auto-discovered at first `Session` construction — the runtime tries
`procedures`/`procedures.js`/`procedures.ts` next to the shared library, in
`process.cwd()`, and next to the entry script (whichever is found first) and
registers any `reduction`/`reduction_*`/`hook_*` exports, exactly like
Python's `import procedures` at extension load. Explicit registration composes
with auto-discovery and takes precedence:

```ts
import * as procedures from "./procedures.js";
import { Session, installProcedures } from "galley-js-node";

// explicit is optional when procedures.* is auto-discoverable:
installProcedures(procedures);
// or for a single hook:
// installProcedure("reduction_KeyTail", (args) => args.dropIfEmpty());
```

The build command `npx galley-js-node <language-dir>` detects
`procedures.ts` / `procedures.js` and generates a `procedures_js.zig`
shim that routes every grammar hook
through a single JS callback (`galley_install_js_dispatch`), exactly like
Python's `procedures_python.zig` and Go's `procedures_go.zig`. Unregistered hooks
are silent no-ops. You can also manage hooks at runtime:

```ts
import { installProcedure, installProcedures, clearProcedures, listProcedures } from "galley-js-node";
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
import { Session, GalleyError } from "galley-js-node";

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

## Tests

The bindings ship a behavioral suite that runs against any built module:

```sh
npm install --prefix examples/js/node
npx --prefix examples/js/node galley-js-node examples/js/node
node bindings/js/node/tests/test_bindings.mjs
```

## Related Pages

- [C and C++](/bindings_c) — the underlying C ABI
- [Deno](/bindings_js_deno), [Bun](/bindings_js_bun), [WebAssembly](/bindings_js_wasm) — the Deno, Bun, and wasm bindings over the same JS core
- [Universal (npm)](/bindings_js_universal) — one package selecting between them at runtime
- [Python](/bindings_python), [Rust](/bindings_rust) and [Go](/bindings_go) — bindings over the same shared library
- [Configuration](/configuration) — config.zig schema
- [Grammar Guidelines](/grammar_guidelines)
