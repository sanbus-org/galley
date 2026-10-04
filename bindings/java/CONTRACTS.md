# Java binding contracts

Host-specific rules for the Java binding. Shared behavior lives in [CONTRACTS.md](../CONTRACTS.md); this file is the contract wherever it spells a rule differently.

## Loading and wiring

- Everything is synchronous.
- `Galley.load` takes an explicit artifact path and returns the `Parser` for that file; the no-arg form resolves through `GALLEY_LIBRARY_PATH` / `galley.library.path`.
- Parsers are cached by canonical artifact path for the process lifetime.
- Sessions open from the `Parser` via `parser.openSession()`, with `SessionOptions` for the non-default shape.
- `Parser` is not closeable: it owns no unloadable native state. `Session` is `AutoCloseable`; `Walker` owns no native resource and is never closed.
- The `Parser` holds the artifact's default hooks and every `Session` owns its own copy, taken at open: both have `installProcedure` / `installProcedures` / `listProcedures` / `lookupProcedure` / `clearProcedures`.
- Bulk installs take a `Map<String, hook>`; single installs take a name plus a hook. Hooks are `Consumer<ProcedureArguments>` or zero-arg `Runnable`.
- The generated `Parser` per grammar wires bundled hooks inside its `load()` method from the `metadata.json` hook list.
- A mistyped-hook name warns to `System.err`, naming the export and the rule; anything else is ignored.

## Types and errors

- Grammar names arrive as `String` decoded from UTF-8 with replacement (U+FFFD), never a throw; `symbolNameBytes` exposes the raw bytes beside them. Token content stays `byte[]`.
- Node addresses are `long`, sequences are `List`, mappings are `Map`, and empty is `null`.
- Every named category the shared contracts define is a Java enum with `getCode()`; branching code never hard-codes integers. The invalid-node sentinel is the named constant `Galley.INVALID_NODE` (`Long.MAX_VALUE`, like the core's), and the snapshot's `variable()` column spells "no variable" `-1`.
- Failures throw `GalleyException`: a numeric code plus a frozen diagnostic snapshot. A missing artifact throws `MissingArtifactException` with the path, the exact build command, and the shared machine-readable code. Use after close throws `GalleyClosedException`.
- A handle whose tree is gone throws `StaleTreeException`, a `GalleyException` with code `ERROR_STALE_TREE`. It is distinct from `GalleyClosedException`: the session is still open, its tree is not the one the handle names. Every source that can find a tree gone raises it — the core's stale status on either door and a stale walk step. A refusal on the hook door raises the same way, without a diagnostic snapshot; no hook read returns `null` for a refusal.
- Every refusal throws; no session-door read answers an empty value or zero for one. `Session.rootNode()` returning `null` is the only "nothing here" answer, and `nodeCount()` / `snapshot()` with nothing published throw `StaleTreeException`.
- There is no validity probe: whether a handle is usable is answered by a real read, which throws.
- A `null` handle argument throws `NullPointerException`: it is a missing argument, not an empty answer.
- Snake-case aliases (`has_ast()` and siblings) exist beside the camelCase queries; both spellings are documented API.

## Inputs and resources

- Parsing accepts `byte[]`, `String` (UTF-8), and `ByteBuffer`; file parses accept `Path`, `File`, and `String`. Anything else is rejected at the earliest boundary Java offers — compile time where an overload catches it, otherwise call entry before the native crossing — with no silent coercion. File paths with interior NUL bytes are rejected with `IllegalArgumentException` instead of truncated.
- Message overrides accept text (`String`, encoded once as UTF-8) or raw bytes (`byte[]`, passed through unmodified).
- Nodes expose their address via `getAddress()` for display, never as an argument where a node is expected, and compare by owning session, core parse generation, and address, so they work as `Map` keys and set members; the door a node was reached through is neither stored in it nor part of its identity, and a stale handle never equals the node at the same address of a later parse.
- A `TreeSnapshot` remembers the parse generation it describes; `node(long)` is the one conversion from a stored address back to a node, returning `null` for `Galley.INVALID_NODE`, throwing `IndexOutOfBoundsException` at or past `count()`, and returning nodes of that parse — stale after a re-parse.
- A node handle is bound to the core's parse generation it was created in: reading through it once that generation is no longer live throws `StaleTreeException`, never a stale read. The core owns that check on the post-parse door, so the session keeps no cached copy of the generation and cannot disagree with the core about it.
- Tree edits cross the door chosen when they are made, for `Session` methods and `Node` sugar alike: the parse's hook door inside a hook dispatch on the dispatching thread, the post-parse door everywhere else, where the core refuses with `ERROR_SESSION_IN_USE` while a parse runs. Every entry that takes a node refuses one from another session with `IllegalArgumentException`, and every node one call takes must carry the same generation, so an edit mixing two trees throws instead of acting on whichever node arrived last.
- Sessions are not thread-safe.
- Sessions close explicitly or through try-with-resources, and closing is idempotent. A walk starts from the node: `node.walk(skipSemanticErrors)` covers that node's subtree, the node itself at depth 0, and `Session` has no `walk`. A step whose position is no longer inside the walk's root (removed, or moved elsewhere) fails with the invalid-node error; steps otherwise follow the live links, so edits between steps are visible, and `skipChildren()` is only a state write.

## Builds

- The build mode is `GalleyBuild <language-dir> --optimize <mode>`; without it the parser library builds ReleaseFast.
