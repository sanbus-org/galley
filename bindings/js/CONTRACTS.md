# JavaScript binding contracts

Host-specific rules for the JavaScript binding. Shared behavior lives in [CONTRACTS.md](../CONTRACTS.md); this file is the contract wherever it spells a rule differently.

## Loading and wiring

- Everything artifact-shaped is asynchronous: a factory resolves a usable backend or rejects, so no unready session value can be observed.
- Generated language entries export the `Session` value for namespace mirroring; adapter and universal entries expose it type-only and construct sessions exclusively from language handles.
- The `galley` object loads explicit artifact files, raw module bytes, and fetched module URLs.
- Byte and URL forms compile off the event loop through a shared module cache, so a source is never built twice.
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
- Every named category the shared contracts define is a TypeScript enum.

## Inputs and resources

- Parsing accepts strings and byte arrays plus idiomatic view and path forms; file paths accept `URL` objects where the platform defines them; rejected interior-NUL paths throw `TypeError`.
- Nodes compare through an explicit equality method and expose their address as a `bigint` getter.
- `Map` and `Set` key nodes by reference identity; session-plus-address equality is available only through the explicit method.
- Walkers close explicitly or through `using` blocks; sessions close explicitly or through disposal blocks.
