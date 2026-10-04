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
- A handle whose tree is gone throws `StaleTreeError`, a `GalleyError` with code `Status.ErrorStaleTree`. It is distinct from `SessionClosedError`: the session is still open, its tree is not the one the handle names. Every source that can find a tree gone throws it — the core's stale status on either door and a stale walk step. A refusal on the hook door throws the same way; no hook read returns `null` for a refusal.
- Every refusal throws; no session-door read answers `null` or a zero for one. `Session.rootNode()` returning `null` is the only "nothing here" answer, and `nodeCount()` / `snapshot()` with nothing published throw `StaleTreeError`.
- There is no validity probe: whether a handle is usable is answered by a real read, which throws.
- An operation that takes a node refuses one from another session with `TypeError`, and one whose parse generation is no longer live with `StaleTreeError`; a raw address is refused with `TypeError` at call entry, because it carries neither session nor generation. Every node one call takes must carry the same generation, so an edit mixing two trees throws instead of acting on whichever node was admitted last.
- Every named category the shared contracts define is a TypeScript enum.

## Inputs and resources

- Parsing accepts strings and byte arrays plus idiomatic view and path forms; file paths accept `URL` objects where the platform defines them; rejected interior-NUL paths throw `TypeError`.
- Nodes are interned one object per (session, core parse generation, address) while that generation is the newest the session has seen — the published tree's, or a running parse's during its hooks — so `===` compares owning session, generation, and address by construction; they expose their address as a display-only `bigint` getter, never accepted where a node is expected.
- `Map` and `Set` key nodes by reference identity, which is exactly session, generation, plus address: one object serves each node of the newest parse — links, children, `rootNode`, hook arguments, snapshot `node()`, and walker steps all return the same handle. An older generation is dead: the core refuses every read through its handles, and a fresh, uninterned handle answers each `node()` call rather than joining the table. A parse that publishes nothing leaves the table holding the dead generation until the next one takes it over; the core, not this table, decides what is live.
- A node's parse generation is a plain `number` end to end (it becomes a `BigInt` only where wasm's `i64` parameters require one); addresses stay `bigint`. `INVALID_NODE` is `2n ** 63n - 1n`, like the core's sentinel, and the snapshot's `variable` column spells "no variable" `-1n`.
- A `TreeSnapshot` from `snapshot()` remembers the parse generation it describes; `node(address)` is the one conversion from a stored address back to a node, taking a `bigint` or safe-integer number (`TypeError` for anything else), returning `null` for `INVALID_NODE`, throwing `RangeError` at or past `count` or when negative, and returning nodes of that parse — reads through them throw `StaleTreeError` once a later parse retires it.
- A call is inside a hook dispatch exactly while a hook of the session's parse runs: one thread per session and a synchronous parse leave no other code to run.
- A walk starts from the node: `node.walk(skipSemanticErrors = false)` covers that node's subtree, the node itself at depth 0, and `Session` has no public `walk`. A walk binds its cursor to the node's generation, so a stale node's walk fails at its first step with `StaleTreeError`, where every other read of it fails.
- Sessions close explicitly or through disposal blocks; walkers own no native resource — one cursor each — so they carry no `close` or `using`. Steps follow the live links, so edits between steps are visible; `skipChildren()` is only a state write, and a step whose position is no longer inside the walk's root (removed, or moved elsewhere) throws the invalid-node error rather than yielding anything past that point.

## Builds

- The build mode is `galley build <language-dir> --optimize <mode>`, or the `optimize` option of `buildParserArtifact`; without it the parser libraries build ReleaseFast. The per-adapter builders stay flag-free.
