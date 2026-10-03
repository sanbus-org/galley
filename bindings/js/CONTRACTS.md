# JavaScript binding contracts

Host-specific rules for the JavaScript binding. Shared behavior lives in [CONTRACTS.md](../CONTRACTS.md); this file is the contract wherever it spells a rule differently.

## Loading and wiring

- Everything artifact-shaped is asynchronous: a factory resolves a usable backend or rejects, so no unready session value can be observed.
- Generated language entries export the `Session` value for namespace mirroring; adapter and universal entries expose it type-only and construct sessions exclusively from parsers.
- The `galley` object loads explicit artifact files, raw module bytes, and fetched module URLs.
- Byte and URL forms compile off the event loop through a shared module cache, so a source is never built twice.
- The same source always resolves to the identical parser, and repeated loads of that source share one default hook table.
- The generated entry opens sessions against its own directory with bundled hooks. `initialize` preloads those hooks where no synchronous scan exists and is a no-op elsewhere, so it can be called unconditionally.
- The file form of a package import works on every runtime; directory-form imports resolve only where the toolchain performs index resolution.

## Backends

- Two engine legs: native first, WebAssembly as fallback, with explicit pins accepted at load time. Pins live on load calls only, never on session construction.
- Sessions report their leg through a read-only getter.
- Fallback prints a one-time process notice, silenced process-wide with `GALLEY_QUIET=1`.

## Types and errors

- Grammar names arrive as UTF-8-decoded strings — replacement character U+FFFD on invalid bytes, never a throw — with a raw-bytes primitive beside them; token content stays byte arrays.
- Wide addresses are big integers, sequences are arrays or typed arrays, mappings are records, and empty is `null`, with `undefined` reserved for absent hook lookups.
- Failures throw `GalleyError`; lifecycle misuse throws `SessionClosedError`, including use after close.
- An operation that takes a node refuses one from another session with `TypeError`, and one whose parse generation is no longer live with `SessionClosedError`; a raw address is refused with `TypeError` at call entry, because it carries neither session nor generation.
- Every named category the shared contracts define is a TypeScript enum.

## Inputs and resources

- Parsing accepts strings and byte arrays plus idiomatic view and path forms; file paths accept `URL` objects where the platform defines them; rejected interior-NUL paths throw `TypeError`.
- Nodes are interned one object per (session, core parse generation, address) while that generation is the session's live one — the published tree's, or a running parse's during its hooks — so `===` compares owning session, generation, and address by construction; they expose their address as a display-only `bigint` getter, never accepted where a node is expected.
- `Map` and `Set` key nodes by reference identity, which is exactly session, generation, plus address: one object serves each node of the live parse — links, children, `rootNode`, hook arguments, snapshot `node()`, and walker steps all return the same handle. A superseded generation keeps no table: a stale read, such as a snapshot's `node()` after a re-parse or a failed parse, answers with a fresh, uninterned handle each call.
- A `TreeSnapshot` from `snapshot()` remembers the parse generation it describes; `node(address)` is the one conversion from a stored address back to a node, taking a `bigint` or safe-integer number (`TypeError` for anything else), returning `null` for `INVALID_NODE`, throwing `RangeError` at or past `count` or when negative, and returning nodes of that parse — the same shared handle while that parse publishes, a fresh one per call after it stops, reading as invalidated.
- A call is inside a hook dispatch exactly while a hook of the session's parse runs: one thread per session and a synchronous parse leave no other code to run.
- A walk starts from the node: `node.walk(skipSemanticErrors = false)` covers that node's subtree, the node itself at depth 0, and `Session` has no public `walk`.
- Sessions close explicitly or through disposal blocks; walkers own no native resource — one cursor each — so they carry no `close` or `using`. Steps follow the live links, so edits between steps are visible; `skipChildren()` is only a state write, and a step whose position is no longer inside the walk's root (removed, or moved elsewhere) throws the invalid-node error rather than yielding anything past that point.

## Builds

- The build mode is `galley build <language-dir> --optimize <mode>`, or the `optimize` option of `buildParserArtifact`; without it the parser libraries build ReleaseFast. The per-adapter builders stay flag-free.
