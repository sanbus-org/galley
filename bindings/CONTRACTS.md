# Binding contracts

A binding has two interfaces, and each has its contract. **With the user**: what a host's users can depend on. **With the core**: what a binding does, and refrains from doing, when it crosses into the galley core. Spelling in a language (class names, types, build commands) is documentation, not contract; how a binding is built inside, beyond what crosses these two interfaces, is not contract either. Names in code spans (`open_session`, `root_node`) are written in snake_case and indicate the call; each host spells it in its own idiom. Applies to Python, Java and JavaScript. Grammar-level hook semantics live in [procedures.md](../docs/procedures.md).

## With the user

### Loading

- A parser comes from a package import (the language's own import of a generated package, with its bundled hooks already installed) or from `load(path)` (an explicit artifact, with no hooks installed). Artifact paths are always explicit: no environment variable or search path fills one in.
- Every `load(path)` returns a new parser whose default hooks are its own (none after a bare load). Loading one artifact twice never shares hook state. A package import gives the package's one parser.
- A failed `load` hands out no parser and affects none already handed out; retrying after the cause is fixed is a fresh attempt.
- A missing artifact reports the path and the build command that produces it, with a machine-readable code identical across hosts.
- Loading and opening are two steps, so hooks can be installed in between: sessions open from a parser.
- A parser offers `open_session`; hook management (`install_procedure`, `install_procedures`, `procedure_hook`, `list_procedures`, `clear_procedures`); and introspection (`version`, `parser_type`, `has_ast`, `has_procedures`, `symbol_count`, `variable_count`, `status_string`).
- Loading writes nothing to stdout. A diagnostic goes to stderr only when no other channel carries it; a host's one-time notice, such as falling back to a slower engine, is the only other thing written there.

### Sessions

- A session opens with options for the parser's tunables, including whether it retains the input of the parse it publishes (it does by default), and owns its hooks: a copy of its parser's defaults taken when it opens. A default installed later reaches only sessions opened later. Message overrides replace the text of diagnostic messages and, like hooks, are fixed while a parse runs.
- Parsing copies the input, so the caller may reuse or release its buffer afterwards. Interior NUL bytes are data. Message inputs accept text or raw bytes without silent re-encoding. A file path with an interior NUL is rejected, never truncated.
- A call with an input form the host does not accept is rejected at the earliest point the host allows (compile time where the type system catches it, otherwise at call entry), with no silent coercion.
- Sessions close explicitly or through the host's scoped-resource form, and closing is idempotent. Use after close fails with an error that names the closed object and is distinct from the stale-tree error.
- Sessions of one parser, and of different parsers, parse at the same time on different threads, and no hook or session state is shared between them.
- A session serves one parse at a time. Any use that overlaps a running parse (another parse, close, a hook or message-override change, a node read or edit, a walk step, a snapshot, from another thread or from a hook) is refused with `session in use` and changes nothing: no node, walker or running hook loses its validity. The one exception is the running hook, on the thread that dispatches it, whose node reads, node edits and walk steps address the running parse's tree. Overlapping use never leaves a host with undefined behavior.
- A parse belongs to one session and runs on one thread, from the start of its `parse` call to its end. It is never paused, moved to another thread, or resumed. A session has at most one parse at a time. A thread has at most one parse at a time, with one exception: a hook may start a parse of a different session on its own thread, with that session's hooks, and that parse ends before the hook returns. So the parses in progress on a thread form a chain in which no session appears twice.

### Hooks

- Hooks are managed on the parser, for its defaults, and on the session, for its own, through the same five functions: install, install many, look up, list, clear. Later installs win per hook name.
- A hook name is `reduction`, `reduction_<Variable>` or `hook_<name>`, and it must be a name the artifact defines. Installing any other name raises; an artifact without procedures defines none. A scan of a module considers only exports whose names begin with `reduction`, or with `hook` followed by `_` or an uppercase letter, and warns, naming the export, when it is not one the artifact defines. An install is deliberate, so it raises; a scan sees every export, so it warns about the ones that look like hooks.
- A hook is called with the arguments object. A hook that declares no positional parameter (a variadic parameter alone does not count) is called with none; a host whose language ignores a surplus argument may pass the object anyway.
- The arguments object exposes the current node and a redirect for it, the hook's position, and a way to report a semantic error. It is valid only while its hook runs and refuses afterwards.
- A hook reaches the tree through the session, never through the arguments object.
- A hook that raises aborts the parse. The parse fails, publishing nothing, and `parse` raises the host's failure with the original exception as its cause. A hook that wants the parse to go on reports a semantic error instead.
- Hooks run on the thread that parses. A hook that shares state with other hooks or sessions must be thread-safe.

### Trees and nodes

- A node belongs to the parse that produced it, and it is valid while that parse's tree is live: the running parse's during its hooks, the published tree afterwards. A node a hook yields stays usable from later hooks of the same parse and, when the parse publishes its tree, until the next parse begins. Nodes of a parse that published nothing are refused afterwards.
- A parse publishes its tree when it ran to its end. A success does, and so does a failure that only recorded errors: semantic errors, or syntax errors the parser recovered from. `parse` raises that failure all the same, and the published tree is complete, with its semantic-error and recovered nodes marked. A parse the parser could not recover from (the error limit reached, or no recovery point in LR and explicit LL recovery), a read or indentation failure, a stack overflow, running out of memory, a parse aborted by a hook that raised, or a refusal publishes nothing. Without AST construction a published failure still answers `last_input` and `last_position`, and `root_node` answers empty, as it does after every parse in such a build.
- A node read or edit, or a walk, addresses the running parse's tree when it is made inside a hook, on the thread that dispatches it, and the published tree everywhere else. The user never chooses which. What describes a finished parse (`root_node`, `node_count`, `snapshot`, `last_input`, `last_position`) has no running-parse form: inside a hook it is refused with `session in use`.
- Nodes come from sessions. A session method takes the host's node type and nothing else, because a raw address cannot say which parse it belongs to. It refuses a node of another session, and an operation given nodes of two different parses is refused with the stale-tree error.
- Nodes are equal, and key collections alike, when they have the same session, parse and position. A handle of an earlier parse never equals the node that now holds its position.
- A node exposes its address through a read-only accessor, for display only. Addresses are 64-bit integers wherever they are exposed.

### Walking and snapshots

- A walk starts from a node (`node.walk`) and covers its subtree, the node itself at depth zero. Each step yields the node, its depth, and its semantic-error and recovered flags. Two options skip semantic-error subtrees and skip recovered subtrees; they are independent, they combine, and each prunes whole subtrees without yielding them. A walker can also skip the subtree it just yielded.
- A walker holds no resource: abandoning it is free and it has nothing to close.
- A walk covers the tree the tree-choice rule in Trees and nodes names. Steps follow the live links, so edits between steps are visible. A step whose position is no longer inside the walk's root (removed, or moved elsewhere) raises `invalid node`, and repeats that failure rather than yielding anything past the detached point.
- A walker belongs to the parse of the tree it was created over: stepping it after a re-parse raises the stale-tree error. Parsing with an abandoned walker succeeds; the walker fails at its next step.
- The recovered flag marks a node that syntax-error recovery kept in place of damaged input, spanning the input recovery skipped. Under LL parsing it is the damaged variable's own node, with the children parsed before the damage. Under LR parsing, which builds no node before a rule completes, it is a placeholder with no children, and no variable under automatic recovery. Either way it sits where the damage was, as a child of the node covering it, so a walk that skips recovered subtrees yields only undamaged nodes. The damaged variable's hooks never ran, and the hooks of the nodes around it see it flagged.
- A snapshot reads the published tree in one call: parent and sibling links, child counts, variables, spans, and the semantic-error and recovered flags, all of one parse. A parse that runs in between raises the stale-tree error rather than returning columns of two trees. `snapshot.node(i)` converts a stored address back to a node: the empty value for "no node", the host's index error for an out-of-range `i`, and otherwise a node of the snapshot's parse, stale after a re-parse.
- Unless its option says otherwise, a session retains the input of its published parse, and node text and `last_input` read it. Without retention they raise `input not retained`; spans, snapshots and `last_position` need no input and still answer. `last_input` and `last_position` follow the published tree like every node read. When several refusals apply, `session in use` comes first, then `stale tree`, then `input not retained`.

### Failures, refusals and absence

- A failure is the host's failure type and carries a status code, a named value that also has its numeric value. A parse failure, a hook failure included, also carries a frozen diagnostic snapshot of where the parse stopped, its text fixed when the failure is created.
- Every refusal raises, and no read answers an empty value or zero for one:
  - `session in use` (see Sessions). It takes precedence while a parse runs: a finished-parse query made inside a hook raises it even when nothing is published yet.
  - `stale tree`: the node's parse is no longer live, or a query that needs a published tree finds none (`node_count`, `snapshot`, `last_input` and `last_position`, before the first parse included). The stale-tree error is a subtype of the failure type carrying the stale-tree status code, and every way a tree can be gone raises it; use after close is neither.
  - `invalid node`: a node whose position was removed or moved out of the walk's root, or a tree edit with an out-of-range index, in every build.
  - `input not retained`: the session's option dropped the input, so `last_input` and node text have nothing to read.
- No handle has a validity probe: a real read is the answer.
- Absence is not a refusal. `root_node` answers the host's empty value when nothing is published or the published tree has no root, and is the one "is there a tree here" probe; a link query with no node there and `snapshot.node(i)` of the invalid-node constant answer the empty value too. A node without a variable answers `-1` in every host, from the variable query and the snapshot's variable column, and snapshot link columns hold the invalid-node constant. An empty value means really empty.
- Argument errors (a node of another session, a raw address where a node is expected, a missing argument, an unsupported input form, a path with an interior NUL) use the host's own argument error and are never answered with an empty value.

### Names and values

- Grammar names cross in one canonical form per host, with the raw-bytes form beside it. Token content is raw bytes. Name bytes decode as UTF-8 and the decode never throws and never alters the raw bytes: invalid sequences become U+FFFD.
- Sequences, mappings and the empty value take each host's idiomatic types. Status codes, parser families, recovery modes, diagnostic kinds, recovery targets and resume sides are named values, never bare integers.

### Building

- Every builder builds the parser library ReleaseFast by default, and accepts a Zig build mode (`Debug`, `ReleaseSafe`, `ReleaseFast`, `ReleaseSmall`) that it passes to zig as given.
- Debug builds check every misuse, and a failed check aborts the process. Release builds skip every check inside the parser's per-byte loop. During hook dispatch they run a check only if it is a single comparison or load, or if omitting it could corrupt memory or leave bad state; a check whose absence merely crashes is skipped, since a crash fails loudly. Every other check runs in every build.
- A hook installed later fires without a rebuild.
- A `procedures.c` or `procedures.cpp` next to a grammar fails the build, naming the host file to use instead.
- A builder checks every guard before it writes anything. Every generated file carries a marker banner, and a builder never overwrites a file without it.

## With the core

The core is the single owner of validity, locking and publication. A binding translates; it never decides anything the core decides.

- **Generations belong to the core.** The core stamps each parse with a generation. A binding keeps no generation counter and no liveness state, and counts no parses; a node merely carries the generation the core issued. It passes the node's generation on every call that reads or edits a node and lets the core refuse a generation that is not live with `stale tree`; the check runs in every build and a binding adds no liveness check of its own. An operation given nodes of different parses is refused by the core too, so no binding compares generations across nodes. It learns the published generation and root together from `galley_root_node`, and a running parse's generation from `galley_hook_generation`.
- **Only a node and its generation cross.** A binding's public boundary never accepts a raw address, and nothing but a node (session, generation, address) is turned into a call.
- **One capability, two paths.** Inside a hook dispatch, on the dispatching thread, a binding calls the `galley_hook_*` family over the door `galley_procedure_door` gives the running parse; everywhere else it calls the `galley_node_*`, `galley_tree_*` and `galley_walk_next` family. The families have one shape, one set of statuses and one set of rules, so a binding implements each capability once, with the path as data (the handle and which family to call).
- **Statuses are never absorbed.** A call returns its answer when it is `>= 0` and a status when it is negative. Every status becomes the host's failure of that kind (`session in use`, `stale tree`, `invalid node`, and the rest), and none becomes an empty or zero answer. The core's "no node" and "no variable" sentinels are non-negative (`INT64_MAX`) and are mapped at the public boundary as the absence rules say.
- **The core keeps no walker.** A binding owns a small cursor and calls `galley_walk_next` once per step, passing the cursor, which holds the generation it expects. Skipping a subtree is a write to the cursor.
- **Locking belongs to the core.** A binding takes no lock of its own around session state and does not hold a host-wide lock across a parse, so parses run in parallel. It relies on the core's `session in use` refusal for every overlapping use, hook changes and message overrides included, and does not pre-check.
- **Hooks cross by name and only when enabled.** A binding validates hook names against the library's own list (`galley_hooks_count`, `galley_hooks_name_*`) and hands the library the enabled set through `galley_session_set_hooks` whenever a session's hooks change. Every hook starts disabled, so an uninstalled hook never calls into the host.
- **A hook failure crosses as a status.** An exception never escapes an upcall into the core. The binding catches it at the upcall, keeps it, and returns the hook-failure status; the core aborts the parse with that status, and the binding raises its failure from `parse` with the kept exception as the cause.
- **Hook arguments are borrowed.** The core checks every `galley_procedure_*` call, and refuses one made with the arguments of a hook that has returned; a binding turns that refusal into the host's failure and keeps no expiry flag of its own. Text and input pointers the core returns are borrowed too: valid until the next parse, and on the hook path only until the hook returns, so a binding copies them out.
- **The core copies input.** A binding may release its buffer when the parse call returns.
