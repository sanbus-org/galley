# Python binding contracts

Host-specific rules for the Python binding. Shared behavior lives in [CONTRACTS.md](../CONTRACTS.md); this file is the contract wherever it spells a rule differently.

## Loading and wiring

- Everything is synchronous.
- Importing a language package scans the sibling hook file and wires hooks at import time.
- `galley.load` takes an explicit artifact path and returns the module for that file.
- Hook registries are module-global: installs target the module, not individual sessions.

## Types and errors

- Grammar names arrive as `bytes`; token content stays `bytes`.
- Integers are plain `int`, sequences are tuples, mappings are dicts, and empty is `None`.
- Failures raise `GalleyError`; lifecycle misuse raises `ValueError`, including use after close.
- Every named category the shared contracts define is an integer enum.

## Inputs and resources

- Parsing accepts `str` plus the buffer protocol; file paths accept path-like objects; rejected interior-NUL paths raise `ValueError`.
- Sessions are not thread-safe, and every call holds the GIL.
- Nodes are hashable by address with session-aware equality, so they work as dict keys and set members.
- Nodes expose their address as a read-only attribute alongside `int` and `index` conversions.
- Walkers support explicit `close` plus context-manager blocks, with collection as the fallback; sessions support `with` blocks.
