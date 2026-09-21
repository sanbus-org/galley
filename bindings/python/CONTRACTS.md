# Python binding contracts

Host-specific rules for the Python binding. Shared behavior lives in [CONTRACTS.md](../CONTRACTS.md).

## Loading and wiring

- Everything is synchronous. Importing a language package scans the sibling hook file and wires hooks at import time.
- `galley.load` takes an explicit artifact path and returns the cached module for that file.
- Hook registries are module-global. Every session of the artifact shares one table, and installs target the module.

## Types and errors

- Grammar names arrive as `bytes`, and token content stays `bytes`. Integers are plain `int`, sequences are tuples, mappings are dicts, and empty is `None`.
- Failures raise `GalleyError` with a code plus a frozen diagnostic snapshot. Lifecycle misuse raises `ValueError`, including use after close.
- Status codes, parser families, recovery modes, diagnostic kinds, recovery targets, resume sides, and the invalid-node sentinel are integer enums.

## Inputs and resources

- Parsing accepts `str` plus the buffer protocol, and file paths accept path-like objects. Sessions are not thread-safe, and every call holds the GIL.
- Nodes are hashable by address with session-aware equality, so they work as dict keys and set members. Nodes expose their address as a read-only attribute alongside `int` and `index` conversion.
- Walkers support explicit `close` plus context-manager blocks, with collection as the fallback. Stepping a walker after close or a re-parse raises `ValueError`, and nodes read only the parse generation that created them. Sessions support `with` blocks.
