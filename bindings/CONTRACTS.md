# Binding contracts

Rules every host binding follows. Grammar-level procedure semantics live in [procedures.md](../docs/procedures.md). This file covers loading, wiring, walking, failures, and repo conventions (the Builds and Examples sections constrain repo content, not runtime behavior). Cross-host values keep one meaning and take one shape per host: this file states what crosses, the binding contracts (`bindings/<language>/CONTRACTS.md`) state how it is spelled, and a binding contract's spelling always wins where it differs.

Since this document addresses different programming languages, name of artifacts like functions, classes, etc are written quoted. They are expected to be converted to the casing of the programming language.

## Artifacts and loading

- Bindings offer two methods for loading a parser:
  1. Loading a language package with native language syntax for importing an artifact embraced in a package/module.
  1. A bare load function to solely and directly import an artifact.

- As far as the binding host allows, either approach is idempotent: a failed one changes nothing, and retrying a factory call after the cause is fixed is a fresh attempt. Importing an entry constructs it.
- Both yield an instance of a "parser" which includes:
  - A function for opening new sessions.
  - Hook management functions: "install procedure", "install procedures", "procedure hook", "clear procedures", "list procedures"
  - Introspection functions: "version", "parser type", "has ast", "has procedures", "symbol count", "variable count", "status string"
- The same source-method combo always yields the identical parser, and repeated loads of the same source-method share one default hook table.
- A failed load hands out no parser and invalidates none already handed out. Retrying a factory call after the cause is fixed is a fresh attempt.
- A missing artifact reports the path and the exact build command, with a machine-readable code identical across hosts.
- A host that offers both dynamic and static forms of its artifact leaves the choice to the user.
- Loading a parser and opening a session are two steps: sessions open from the loaded parser.

### Loading language as a package

- Bundled hooks of a parser package are considered a part of it and they are automatically installed upon import.
- A host that scans at runtime imports the sibling procedures module; a host that bakes hooks at build wires the list the build recorded.

### Bare loading

- A bare load wires nothing. Hooks arrive explicitly only.

## Hooks

- Each artifact owns a default hook table; each session owns its own hooks, a copy of the defaults taken when the session opens. A default installed later reaches only sessions opened later.
- Both are managed through functions that install, list, look up, and clear hooks: on the parser for the defaults, on the session for its own.
- Hook names are `reduction`, `reduction_<Variable>`, and `hook_<name>`.
- A scan ignores any other name; a scanned name that looks like a mistyped hook produces a warning naming the export and the rule.
- Later installs win per hook name; explicit installs win over bundled scans.
- Unregistered hooks never cross into the host: a session hands the library its enabled set whenever its hooks change, and every hook starts disabled.
- Hooks are called with an arguments object or with no arguments at all.
- The arguments object exposes the current node and a redirect for it, the hook's position, and a way to report a semantic error. It is per-hook state: valid only while its hook runs, and refusing once the hook returns.
- Hook code reaches the tree through the session, not the arguments object: the host chooses the door when each call is made. A call made inside a hook dispatch of the session's running parse, on the thread running that hook, crosses the `galley_hook_*` twins over that parse's door in C (each host's named equivalents elsewhere), lock-free while the parse runs; every other call crosses the post-parse door. The two doors differ only in what they are opened on, never in shape or rules: the twins take the node's generation, return the same statuses, and each host implements a capability once, with the door as data (the handle and which family to call).
- A node is valid by the core's parse generation, never by a host counter: the core stamps one generation per parse when the parse starts, hooks see that generation (`galley_hook_generation`), and a parse that publishes its tree does so under it, which `galley_root_node` reports. The core checks it inside every call, on both doors: a node is valid when its generation is the door's live tree's — the running parse's on the hook door, the published tree's on the session door — and no host compares a generation with the parse's. So a node a hook yields stays usable from later hooks of the same parse and, when the parse publishes, until the next parse; nodes of a parse that published nothing are refused afterwards. A parse the core refuses with `session in use` changes nothing: no node, walker, or running hook loses its validity.
- The core owns the generation check, not the host. Every call that reads or edits a node, on the post-parse door and on the hook door alike, takes the generation it addresses and returns a status (a call with one result, such as a link, a count or the variable index, returns it in the same value: `>= 0` is the answer, negative is the status); the core refuses a generation that is not the door's live tree's with `stale tree` — the published tree's on the session door, the running parse's on the hook door. `galley_procedure_set_current_node` goes through the same check. No host keeps a cached copy of either generation to compare against, so no host-side check can disagree with the core.
- A parse publishes its tree when it ran to its end: a success does, and so does a failure that only recorded errors — semantic errors, or syntax errors the parser recovered from. `parse()` raises that failure all the same, and the published tree is complete: the semantic-error and recovered nodes are marked (see Walking and snapshots). A parse the parser could not recover from (the error limit reached, or no recovery point in LR and explicit LL recovery), a read or indentation failure, a stack overflow, or running out of memory publishes nothing; so does a parse that was refused. Publishing does not need a tree: without AST construction a published failure still answers `last_input` and `last_position`, and `root_node()` answers the host empty value as it does for every parse there.
- `galley_root_node` is the one source of the published generation and the one "is there a tree here" probe: it writes the root and the generation together under one guard, answers `GALLEY_INVALID_NODE` and `0` when nothing is published (a published failure whose recovery left no root answers `GALLEY_INVALID_NODE` with its generation), and refuses with `session in use` mid-parse. There is no separate validity probe on the session door.
- The post-parse door (session node reads, tree edits, walkers, snapshots) refuses with `session in use` while a parse holds the session — including a hook node used from a thread other than the one running the hook — and with `stale tree` once a later parse — published or not — has retired the generation the call carries; an address outside the live tree's storage is still `invalid node`. No stashed handle bypasses it. A node of another session is refused, never read as a bare address.
- Every node address and the two "nothing here" sentinels, `GALLEY_INVALID_NODE` (no node at that link) and `GALLEY_NO_VARIABLE` (a node without a variable), are non-negative (`INT64_MAX`); only statuses are negative. Hosts map the sentinels to their own spelling at their public boundary.
- The generation check runs in every build. It is a lifetime contract memory-safe hosts depend on, not a misuse check, and it costs one integer comparison per call.
- A session's hooks are fixed for the length of a parse: a change attempted while a parse is in flight — from a hook, or from another thread — is refused with `session in use` and leaves the hooks as they were.
- A nested parse is a parse of another session, so each parse runs with its own session's hooks and neither sees the other's.
- Sessions of one artifact, and of different artifacts, may parse at the same time on different threads: nothing in hook dispatch is shared between sessions. A hook runs on the thread that parses and must be thread-safe if it shares state with other hooks.
- A failing hook never aborts the parse.

## Walking and snapshots

- A walk covers the subtree of its root, the root included at depth zero. Python, Java, and JavaScript start it from the root node itself (`node.walk`); every other host takes the root as an argument.
- Walkers yield named steps carrying the node, the depth, and the semantic-error and recovered flags; the first step is at depth zero. Python's steps are a read-only `WalkStep` type; Java and JavaScript yield their `WalkStep` values. Go yields the semantic-error flag only and has no recovered flag yet.
- The recovered flag marks a node syntax-error recovery kept in place of damaged input; its span covers the input recovery skipped. Under LL parsing it is the damaged variable's own node, with the children parsed before the damage; under LR parsing, which builds no node before a rule completes, it is a placeholder with no children (and no variable under automatic recovery). Either way it sits where the damage was, as a child of the node covering it, so a walk that skips recovered subtrees yields only undamaged nodes. The damaged variable's hooks never ran, and the hooks of the nodes around it see it flagged.
- A walk takes two skip options, one per flag: skipping semantic-error subtrees and skipping recovered subtrees. They are independent and combine; each prunes whole subtrees without yielding them. Go has the first only.
- A walker owns no native resource: it is one host-side cursor, one native call per step, nothing to close. Abandoning a walker is free; sessions still release their resources explicitly, through the mechanism the binding contract names, and that closing stays idempotent.
- Pruning is host-side too: it changes the cursor's state without a native call, and skips the last yielded subtree.
- Steps follow the live tree: `galley_tree_*` edits between steps are visible to later steps.
- Where a host can name an invalid root, a walk from it hands back a walker whose first step fails with the host's stale-tree error. Python, Java, and JavaScript cannot: a node handle is never an invalid address.
- A walker belongs to the core's parse generation of the tree it was created over: stepping it after a re-parse raises the stale-tree error, never a stale read. Parsing with an abandoned walker succeeds; the walker fails at its next step.
- Each step crosses through the door a node call of the same session would choose: the session door otherwise, which refuses with `session in use` mid-parse, and — where the binding offers a walk through the hook door — the hook door from the dispatching thread of the running parse, so that walk matches the post-parse walk.
- A step whose position is no longer inside the walk's root (removed, or moved elsewhere) raises invalid node, and repeats that failure rather than yielding anything past the detached point.
- Snapshots bulk-read the published tree in a single crossing: parentage, child counts, variables, spans, and the semantic-error and recovered flags (Go's has neither column yet). Every leg of a snapshot carries one generation, so a parse that runs in between raises the stale-tree error instead of returning columns that mix two trees.
- A snapshot remembers the parse generation it describes, and `snapshot.node(i)` is the one conversion from a stored address back to a node: the host empty value for the invalid-node sentinel, the host's index error for an out-of-range `i`, and nodes of that parse — stale after a re-parse, never the later parse's nodes at the same address.
- A session retains the input of its published parse (a success, or a failure that ran to its end); snapshots and node spans index into that retained input. The input and the end position follow the published tree like every node read: `last_input` and `last_position` raise the stale-tree error whenever nothing is published — before the first parse, after a parse that published nothing, or once a later parse has begun — and `session in use` mid-parse. Neither answers an empty value or zeros for a refusal.

## Names, values, and codes

- Grammar names cross in one canonical form per host; each binding contract names that form and any raw-bytes form beside it.
- A host that turns name bytes into text performs a UTF-8 charset decode, never an escape-unescape: it never throws and never modifies the raw bytes; hosts whose text type requires valid encoding replace with U+FFFD.
- Token content is raw bytes in every host.
- A node address crosses as a wide integer in every host.
- Sequences, mappings, and the empty value take each host's idiomatic types; the binding contracts name them.
- Status codes, parser families, recovery modes, diagnostic kinds, recovery targets, resume sides, and the invalid-node sentinel cross as named values in every host, never as bare integers.

## Failures

- A failure signals to the caller as the host's failure type: a numeric code plus a frozen diagnostic snapshot, with its text fixed when the failure is created and structured detail in the snapshot.
- Failures other than a missing artifact surface the underlying error unchanged.
- Use after close signals a failure to the caller with an error idiomatic to the host, naming the closed object; the type each host uses is in its binding contract.
- One stale-tree error per host, distinct from use after close, raised by every source that can find a handle's tree gone: the core's stale status on either door and a stale walk step. A refusal on the hook door raises exactly as on the session door; no hook read answers `None`/`null`/an empty value for a refusal. Each binding contract names the type.
- Every refusal raises. A session-door read never answers an empty value or a zero for a refusal: `root_node()` returning the host empty value is the only "nothing here" answer, and `node_count` / `snapshot` / `last_input` / `last_position` with nothing published raise the stale-tree error. An empty value means really empty.

## Inputs and nodes

- Entries accept their host-idiomatic input forms and reject the rest at the earliest boundary the host offers — compile time where the type system catches it, otherwise call entry before the native crossing — with no silent coercion.
- Message inputs accept text or raw bytes without silent re-encoding.
- Handles come from sessions; a session method takes the host's node type and nothing else, because a raw address carries no generation to check.
- Nodes expose their address through a named read-only accessor for display, never as an argument where a node is expected, and compare by owning session, core parse generation, plus address; the door a node was reached through is neither stored in it nor part of its identity.
- Hosts may narrow object identity to the live generation, as the JavaScript binding does: one object per (session, generation, address) while the generation is live, and a fresh handle after it is superseded — value identity itself is unchanged.
- A node handle is bound to the core's parse generation it was created in: reading through it once that generation is no longer live signals a failure to the caller, never a stale read.
- No public validity probe: whether a handle is usable is answered by a real read, which raises. Asking separately would only report what the next real call reports anyway.
- Node keying in collections follows each host's default semantics; the binding contracts spell it out.
- Tree edits cross the door chosen when they are made: the parse's hook door inside a hook dispatch on the dispatching thread, the post-parse door everywhere else, for session methods and node sugar alike.
- Parsing copies the input into session ownership, so the caller may reuse or release its own buffer afterward.
- Interior NUL bytes are data, not terminators.
- File paths with interior NUL bytes are rejected loudly at the boundary instead of truncated; each binding contract names the failure its host signals to the caller.

## Builds

- Every builder builds the parser library ReleaseFast by default and accepts a Zig build mode (`Debug`, `ReleaseSafe`, `ReleaseFast`, `ReleaseSmall`), passed to zig verbatim and forwarded only when the user chose one. Debug builds enable the runtime's misuse checks and a failed check aborts the process; release builds do not check. The one exception is the index and count of the tree-edit calls (insert children at, remove children at, remove siblings): they are range-checked in every build and an out-of-range value fails with the invalid-node error.
- Every build links the host shim the generator writes (`--emit-host-procedures`; non-empty even when the grammar disables procedures), so a hook installed later fires without a rebuild.
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
