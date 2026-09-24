# Binding contracts

Rules every host binding follows. Grammar-level procedure semantics live in [procedures.md](../docs/procedures.md); this file covers loading, wiring, walking, failures, and repo conventions (the Builds and Examples sections constrain repo content, not runtime behavior). Cross-host values keep one meaning and take one shape per host: this file states what crosses, the language files (`bindings/<language>/CONTRACTS.md`) state how it is spelled, and a language file's spelling always wins where it differs.

## Artifacts and loading

- A load takes its artifact as an explicit argument; a language file that offers a defaulted form names what fills it.
- A language's bundled hooks are wired automatically on the host's language-use path, named in each language file.
- The same source always yields the identical parser, and repeated loads of the same source share one hook table.
- A failed load hands out no parser and invalidates none already handed out; retrying after the cause is fixed is a fresh attempt.
- A missing artifact reports the path and the exact build command, with a machine-readable code identical across hosts.
- A host that offers both dynamic and static forms of its artifact leaves the choice to the user.

Hosts that acquire native code at load time follow the load/open choreography:

- Bare loads take an artifact and yield the parser without scanning for hook files; hooks arrive explicitly only.
- Loading and opening are two steps: loading acquires the artifact and yields the parser — returns, or resolves where async — and sessions open from it, so hook installs fit between them.

## Hooks

- Each artifact owns one hook table, shared by all of its sessions.
- The table is managed through functions that install, list, look up, and clear hooks.
- Hook names are `reduction`, `reduction_<Variable>`, and `hook_<name>`.
- A scan ignores any other name; a scanned name that looks like a mistyped hook produces a warning naming the export and the rule.
- Later installs win per hook name; explicit installs win over bundled scans.
- Unregistered hooks never cross into the host; per-hook gates default to off.
- Hooks are called with an arguments object or with no arguments at all.
- The arguments object exposes the current node and a redirect for it, the hook's position, a way to report a semantic error, and a way to ask whether the session is closed.
- Hook code reads the session from its arguments object.
- Tree edits inside hooks are session operations.
- Installs and clears made mid-parse apply to later parses only.
- Nested parses restore the enclosing hook set on unwind.
- A failing hook never aborts the parse.

## Walking and snapshots

- Walkers yield named steps carrying the node, the depth, and the semantic-error flag; the first step is at depth zero.
- Pruning skips the last yielded subtree.
- A walk from an invalid root yields the host empty value.
- A walker belongs to the parse generation that created it: stepping it after a re-parse signals a failure to the caller, never a stale read.
- Parsing with an abandoned walker succeeds; the walker fails at its next step.
- Walkers and sessions that hold resources release them explicitly, through the mechanism the language file names; closing is idempotent in both.
- Snapshots bulk-read the last successful parse in a single crossing: parentage, child counts, variables, spans, and the semantic-error flag.
- A session retains the input of its most recent successful parse; snapshots index into that retained input.

## Names, values, and codes

- Grammar names cross in one canonical form per host; each language file names that form and any raw-bytes form beside it.
- A host that turns name bytes into text performs a UTF-8 charset decode, never an escape-unescape: it never throws and never modifies the raw bytes; hosts whose text type requires valid encoding replace with U+FFFD.
- Token content is raw bytes in every host.
- A node address crosses as a wide integer in every host.
- Sequences, mappings, and the empty value take each host's idiomatic types; the language files name them.
- Status codes, parser families, recovery modes, diagnostic kinds, recovery targets, resume sides, and the invalid-node sentinel cross as named values in every host, never as bare integers.

## Failures

- A failure signals to the caller as the host's failure type: a numeric code plus a frozen diagnostic snapshot, with its text fixed when the failure is created and structured detail in the snapshot.
- Failures other than a missing artifact surface the underlying error unchanged.
- Use after close signals a failure to the caller with an error idiomatic to the host, naming the closed object; the type each host uses is in its language file.

## Inputs and nodes

- Entries accept their host-idiomatic input forms and reject the rest at the earliest boundary the host offers — compile time where the type system catches it, otherwise call entry before the native crossing — with no silent coercion.
- Message inputs accept text or raw bytes without silent re-encoding.
- Handles come from sessions; every session method also accepts the same call with all handles replaced by raw addresses, obtained through the node's read-only accessor.
- Nodes expose their address through a named read-only accessor and compare by owning session plus address.
- A node handle is bound to the parse generation that created it: reading through it after a re-parse signals a failure to the caller, never a stale read.
- A raw address carries no generation and passes every such guard by design.
- Node keying in collections follows each host's default semantics; the language files spell it out.
- Tree edits are session operations, with a convenience sugar on nodes for the common pair.
- Parsing copies the input into session ownership, so the caller may reuse or release its own buffer afterward.
- Interior NUL bytes are data, not terminators.
- File paths with interior NUL bytes are rejected loudly at the boundary instead of truncated; each language file names the failure its host signals to the caller.

## Builds

- Every build links a dispatch shim generated from the metadata hook list (non-empty even when the grammar disables procedures), so a hook installed later fires without a rebuild.
- A `procedures.c` / `procedures.cpp` next to a grammar is a fatal build error naming the host file to use instead.
- Every generated file carries its marker banner, builders refuse to overwrite a file without it, and guards are checked before anything is written.
- Generated code reports explicit errors, never `assert`, for control flow.
- Library import writes nothing to stdout; a diagnostic goes to stderr only when no other channel carries it.

## Examples and surface

- One grammar per package directory (`kv/`, `json/`), with containers per language.
- Example output is byte-identical across bindings, comparing stdout and stderr separately.
- Comments in a binding never reference another binding — its files or its behavior; cross-binding guarantees live in this contract.
- Only documented entries are public API.
- Generated entries expose their surface through named exports.
- Artifact paths are always explicit.
