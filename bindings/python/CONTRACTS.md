# Python binding contracts

Host-specific rules for the Python binding. Shared behavior lives in [CONTRACTS.md](../CONTRACTS.md); this file is the contract wherever it spells a rule differently.

## Loading and wiring

- Importing a language package scans the sibling hook file and wires hooks at import time.
- `galley.load` takes an explicit artifact path and returns the parser for that file; repeated loads of the same resolved path return that same parser, cached for the process lifetime.
- The module-level `install_procedure` / `install_procedures` / `list_procedures` / `procedure_hook` / `clear_procedures` manage the artifact's defaults; every `Session` owns its hooks (a copy of the defaults at open) and has the same five methods.
- A parse releases the GIL, so sessions on different threads parse in parallel; a hook takes the GIL back for the length of its call.

## Types and errors

- Grammar names arrive as `bytes`; token content stays `bytes`.
- Integers are plain `int`, sequences are tuples, mappings are dicts, and empty is `None`.
- Failures raise `GalleyError`; lifecycle misuse raises `ValueError`, including use after close.
- A handle whose tree is gone raises `StaleTreeError`, a `GalleyError` subclass with code `Status.ERROR_STALE_TREE`. It is distinct from use after close, which stays `ValueError`.
- Every refusal raises; no session-door read answers `None` or `0` for one. `Session.root_node()` returning `None` is the only "nothing here" answer, and `Session.node_count()` / `Session.snapshot()` / `Session.last_input()` / `Session.last_position()` with nothing published (before the first parse, or after a parse that published nothing) raise `StaleTreeError`.
- There is no validity probe: a real read is the answer, and it raises.
- An operation that takes a node refuses one from another session with `ValueError`, and one of a parse generation that is no longer live with `StaleTreeError` — on the hook door too, where the core does the check and no read answers `None` for a refusal; a raw address is refused with `TypeError` instead, because it carries no generation.
- Every node a call takes must carry the same generation, so an operation mixing two trees is refused rather than silently acting on whichever node was admitted last.
- Every named category the shared contracts define is an integer enum.

## Inputs and resources

- Parsing accepts `str` plus the buffer protocol; file paths accept path-like objects; rejected interior-NUL paths raise `ValueError`.
- Sessions are not thread-safe; a parse releases the GIL and every other call holds it.
- Nodes are hashable with equality over owning session, core parse generation, and address, so they work as dict keys and set members; the door a node was reached through is not part of either.
- Nodes expose their address as a read-only attribute for display; a session method takes a `Node`, and `Session.snapshot().node(index)` is the one conversion from a stored address back to a node, taking an `int` index only (`TypeError` for anything else, a `bool` included).
- A walk starts from the node: `node.walk(skip_semantic_errors=False, skip_recovered=False)` covers that node's subtree, the node itself at depth 0, and `Session` has no `walk`. Steps are immutable `WalkStep` objects with `node`, `depth`, `is_semantic_error`, and `is_recovered` read-only attributes, and the snapshot has an `is_recovered` column beside `is_semantic_error`; they cannot be constructed from Python, like `Node` and `Snapshot`.
- Walkers own no native resource — one cursor each — so they are never closed and take no context-manager block; sessions support `with` blocks. Steps follow the live links, so edits between steps are visible; `skip_children()` is only a state write, and a step whose position is no longer inside the walk's root (removed, or moved elsewhere) fails with the invalid-node error rather than yielding anything past that point. A step on a walk whose parse generation is gone raises `StaleTreeError`.

## Builds

- The build mode is `python -m galley <language-dir> --optimize <mode>`; without it the parser library builds ReleaseFast.
