# JavaScript binding contracts

Host-specific rules for the JavaScript binding. Shared behavior lives in [CONTRACTS.md](../CONTRACTS.md).

## Loading and wiring

- Everything artifact-shaped is asynchronous. Factories resolve a usable backend or reject, so no unready session state exists.
- The `Session` value is exported for namespace mirroring by generated language entries only; adapter and universal entries expose it type-only and construct sessions exclusively from language handles.
- The `galley` object loads explicit artifact files, raw module bytes, and fetched module URLs. Byte and URL forms compile off-thread through the shared module cache.
- The generated entry opens sessions on its own directory with bundled hooks, and `initialize` preloads those hooks where no synchronous scan exists. It is a no-op elsewhere so one program runs everywhere.
- The file form of a package import works on every runtime. Directory-form imports resolve only where the toolchain performs index resolution.

## Backends

- Two engine legs exist: native first with WebAssembly fallback, plus explicit pins at load time. Pins live on load calls only, never on session construction.
- Sessions report their leg through a read-only getter. Fallback prints a one-time process notice, silenced process-wide with `GALLEY_QUIET=1`.

## Types and errors

- Grammar names arrive as decoded strings with a raw-bytes primitive beside them, and token content stays byte arrays. Wide addresses are big integers, sequences are arrays or typed arrays, mappings are records, and empty is null with undefined for absent hook lookups.
- Failures throw `GalleyError` with a code plus a frozen diagnostic snapshot. Missing artifacts carry a machine-readable code, and use after close throws a dedicated closed-session error.
- Status codes, parser families, recovery modes, diagnostic kinds, recovery targets, resume sides, and the invalid-node sentinel are enums.

## Inputs and resources

- Parsing accepts strings and byte arrays plus idiomatic view and path forms, normalized through shared check helpers. File paths accept URL objects where the platform defines them.
- Nodes compare through an explicit equality method and expose their address as a bigint getter. Maps and sets keep reference identity, so memoizing code keys on the address explicitly.
- Walkers close explicitly or through `using` blocks before the session closes or parses again. Sessions close explicitly or through disposal blocks.
