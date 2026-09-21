# Binding contracts

Rules every host binding follows. Grammar-level procedure semantics live in [procedures.md](../docs/procedures.md); this file covers loading, wiring, errors, and repo conventions. Shared values cross in host-idiomatic types, and host mechanics live in the language folders (`bindings/python/CONTRACTS.md`, `bindings/js/CONTRACTS.md`).

## Loading

- Importing a language package wires its bundled hooks automatically. Hook namespaces are imported from their hook file.
- Bare loads take an artifact and return a handle without scanning for hook files. Hooks arrive explicitly only.
- Loading acquires the artifact, and sessions open from the handle, so callers always have a moment to install hooks between the two steps.
- The same source always yields the identical handle object. Failed loads bind nothing and rebind nothing.

## Hooks

- Each artifact owns one hook table shared by its sessions, managed through functions that install, list, look up, and clear hooks.
- Hook names are `reduction`, `reduction_<Variable>`, and `hook_<name>`. Anything else is ignored, and names that look like mistyped hooks produce a warning naming the export and the rule.
- Later installs win per hook name, and explicit installs win over bundled scans.
- Unregistered hooks never cross into the host. Per-hook gates are checked on the native side and default to off.
- Hooks receive an arguments object or nothing. The channel exposes the current node, redirecting it, reading hook position, reporting semantic errors, and asking whether the session is closed. Tree edits inside hooks go through the session spelling.
- Installs and clears made mid-parse apply to later parses only. Nested parses restore the enclosing hook set on unwind. A throwing hook never aborts the parse.

## Walking and snapshots

- Walkers yield named steps with the node, the depth, and the semantic-error flag, starting at depth zero. Pruning skips the last yielded subtree.
- A walk from an invalid root yields the host empty value. A walker is bound to its parse generation: use after close and stepping after a re-parse raise a catchable host error, never a stale read. Parsing with an abandoned open walker still succeeds; the walker fails at its next step. Walkers close explicitly or through resource blocks, and closing stays idempotent.
- Snapshots bulk-read the last successful parse in a single crossing: parentage, child counts, variables, and spans. Sessions retain the last input that snapshot spans index, so bulk text extraction reads the snapshot plus the retained input instead of issuing one call per node.

## Names, values, and codes

- Grammar names arrive as host text, while token content stays raw bytes everywhere. Integers use wide types where addresses require them, sequences are arrays, mappings are records, and empty is null.
- Status codes, parser families, recovery modes, diagnostic kinds, recovery targets, resume sides, and the invalid-node sentinel are all named. Branching code never hard-codes integers.

## Failures

- One failure type carries a numeric code plus a frozen diagnostic snapshot. Its text is fixed at raise time; the snapshot carries structured detail.
- A missing artifact reports the path plus the exact build command, with a machine-readable code shared across hosts. Anything else surfaces the underlying error.
- Use after close raises a catchable error idiomatic to the host, naming the closed object. Closing is idempotent everywhere.

## Inputs and nodes

- Entries accept their host idiomatic input forms and reject the rest loudly at the boundary. Message inputs accept text or raw bytes without silent re-encoding.
- Handles come from sessions, and every session method also accepts a raw address wherever a handle is expected. Nodes expose their address through a named read-only accessor and compare by owning session plus address. Collection keying follows host semantics. Hook code reads the session from its arguments object.
- Tree edits are session operations, with a convenience sugar on nodes for the common pair. Parsing copies input into session ownership, and interior NUL bytes are data.

## Builds

- Every build links a dispatch shim generated from the metadata hook list (non-empty even when the grammar disables procedures), so a hook installed later fires without a rebuild.
- `procedures.c` / `procedures.cpp` next to a grammar is a fatal build error naming the host file to use instead.
- Every generated file carries its marker banner, and builders refuse to overwrite a file without it. Guards are checked before anything is written.
- Generated code uses explicit errors, never `assert`, for control flow. Library import writes nothing to stdout, and diagnostics go to stderr only when they say something no other channel carries.

## Examples and surface

- One grammar per package directory (`kv/`, `json/`), with containers per language. Example output is byte-identical across bindings on stdout and stderr separately, and comments never reference the other language files.
- Only documented entries are public API. Generated entries expose their surface through named exports, and artifact paths are always explicit.
