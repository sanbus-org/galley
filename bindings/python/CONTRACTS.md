# Python binding contracts

Host-specific rules for the Python binding. Shared behavior lives in [CONTRACTS.md](../CONTRACTS.md); this file is the contract wherever it spells a rule differently.

## Loading and wiring

- Everything is synchronous.
- Importing a language package scans the sibling hook file and wires hooks at import time.
- `galley.load` takes an explicit artifact path and returns the parser for that file; repeated loads of the same resolved path return that same parser, cached for the process lifetime.
- The module-level `install_procedure` / `install_procedures` / `list_procedures` / `procedure_hook` / `clear_procedures` manage the artifact's defaults; every `Session` owns its hooks (a copy of the defaults at open) and has the same five methods.
- A parse releases the GIL, so sessions on different threads parse in parallel; a hook takes the GIL back for the length of its call.

## Types and errors

- Grammar names arrive as `bytes`; token content stays `bytes`.
- Integers are plain `int`, sequences are tuples, mappings are dicts, and empty is `None`.
- Failures raise `GalleyError`; lifecycle misuse raises `ValueError`, including use after close.
- An operation that takes a node refuses one from another session, or of a parse generation that is no longer live, with `ValueError`; raw addresses carry no generation and pass unguarded by design.
- Every named category the shared contracts define is an integer enum.

## Inputs and resources

- Parsing accepts `str` plus the buffer protocol; file paths accept path-like objects; rejected interior-NUL paths raise `ValueError`.
- Sessions are not thread-safe; a parse releases the GIL and every other call holds it.
- Nodes are hashable with equality over owning session, core parse generation, and address, so they work as dict keys and set members; the door a node was reached through is not part of either.
- Nodes expose their address as a read-only attribute alongside `int` and `index` conversions.
- Walkers support explicit `close` plus context-manager blocks, with collection as the fallback; sessions support `with` blocks.
