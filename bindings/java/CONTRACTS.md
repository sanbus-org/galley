# Java binding contracts

Host-specific rules for the Java binding. Shared behavior lives in [CONTRACTS.md](../CONTRACTS.md); this file is the contract wherever it spells a rule differently.

## Loading and wiring

- Everything is synchronous.
- `Galley.load` takes an explicit artifact path and returns the `Parser` for that file; the no-arg form resolves through `GALLEY_LIBRARY_PATH` / `galley.library.path`.
- Parsers are cached by canonical artifact path for the process lifetime: the same source always yields the identical handle object, and a failed load binds nothing.
- Sessions open from the handle via `parser.openSession()`, with `SessionOptions` for the non-default shape, so hook installs fit between load and open.
- `Parser` is not closeable: it owns no unloadable native state. `Session` and `Walker` are `AutoCloseable`.
- Hook registries are per-artifact instance state on the `Parser`: `installProcedure` / `installProcedures` / `listProcedures` / `lookupProcedure` / `clearProcedures`.
- Bulk installs take a `Map<String, hook>`; single installs take a name plus a hook. Hooks are `Consumer<ProcedureArguments>` or zero-arg `Runnable`.
- The generated `Parser` per grammar wires bundled hooks inside its `load()` method from the `metadata.json` hook list. Bare `Galley.load` performs no scan, and explicit installs win over bundled ones.
- A mistyped-hook name warns to `System.err`, naming the export and the rule; anything else is ignored.

## Types and errors

- Grammar names arrive as `String` decoded from UTF-8 with replacement (U+FFFD), never a throw; `symbolNameBytes` exposes the raw bytes beside them. Token content stays `byte[]`.
- Node addresses are `long`, sequences are `List`, mappings are `Map`, and empty is `null`.
- Every named category the shared contracts define is a Java enum with `getCode()`; branching code never hard-codes integers. The invalid-node sentinel is the named constant `Galley.INVALID_NODE`.
- Failures raise `GalleyException`: a numeric code plus a frozen diagnostic snapshot. A missing artifact raises `MissingArtifactException` with the path, the exact build command, and the shared machine-readable code. Lifecycle misuse raises `GalleyClosedException`, including use after close and generation invalidation.
- Snake-case aliases (`has_ast()` and siblings) exist beside the camelCase queries for Python-doc parity; both spellings are documented API.

## Inputs and resources

- Parsing accepts `byte[]`, `String` (UTF-8), and `ByteBuffer`; file parses accept `Path`, `File`, and `String`. Anything else is rejected loudly at the boundary. File paths with interior NUL bytes are rejected with `IllegalArgumentException` instead of truncated.
- Parse inputs cross length-prefixed: audit note — the native runtime currently stops at interior NUL bytes, so shared "NUL is data" holds only up to the binding boundary (upstream defect, not a binding truncation).
- Message overrides accept text (`String`, encoded once as UTF-8) or raw bytes (`byte[]`, passed through unmodified).
- Every session method also accepts a raw `long` address wherever a `Node` is expected; raw addresses carry no generation and pass every guard by design.
- Nodes expose their address via `getAddress()` and compare by owning session plus address, so they work as `Map` keys and set members. Identity ignores generation by design: a stale handle equals its fresh counterpart, but reads through it still raise.
- A node handle is bound to the parse generation that created it: reading through it after a re-parse raises `GalleyClosedException`, never a stale read.
- Tree edits are `Session` operations, with `cleanChildren` / `appendChildren` sugar on `Node`.
- Sessions are not thread-safe.
- Sessions and walkers close explicitly or through try-with-resources, and closing is idempotent. A walk from an invalid root returns `null`.
