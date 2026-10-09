# C and C++

Galley-generated parsers can be consumed from C and C++ through a small
application-binary interface: Galley compiles a generated parser into a
shared library (`lib<name>.dylib` / `.so`) together with the C header
[`bindings/c/galley.h`](https://github.com/sanbus-org/galley/blob/main/bindings/c/galley.h).
Complete, runnable consumers live in
[`examples/c`](https://github.com/sanbus-org/galley/tree/main/examples/c) and
[`examples/cpp`](https://github.com/sanbus-org/galley/tree/main/examples/cpp);
both are built and executed by CI on every push.

## Procedures

Grammars can use `@hook_name` annotations on RHS occurrences. When Galley's
`--emit-metadata` flag is passed during generation, it produces a
`procedures.zig` alongside the parser with extern declarations for every
hook. When `procedures.c` (or `procedures.cpp` for C++) lives next to the
parser, the consumer build compiles it automatically; otherwise pass its
location explicitly with `-Dprocedures-c-source=procedures.c`. Reduction
hooks keep their `reduction_<VariableName>` names (plus the general
`reduction`); author-defined grammar hooks are declared as `hook_<name>`,
namespacing them away from unrelated symbols:

```c
/* procedures.c */
#include <galley.h>
#include <stdio.h>

static GalleyNodeAddress current_node(GalleySession *session, unsigned long long hook) {
    long long node = galley_procedure_current_node(session, hook);
    return node < 0 ? GALLEY_INVALID_NODE : (GalleyNodeAddress)node;
}

void reduction_Pair(GalleySession *session, unsigned long long hook) {
    GalleyHookDoor *door = NULL;
    unsigned long long generation = 0;
    GalleyNodeAddress node = current_node(session, hook);
    const char *text = NULL;
    size_t len = 0;
    unsigned line = 0, column = 0;
    if (node == GALLEY_INVALID_NODE) return;
    galley_procedure_door(session, hook, &door);
    galley_hook_generation(door, &generation);
    galley_hook_node_text(door, generation, node, &text, &len);
    galley_hook_node_line_column(door, generation, node, &line, &column);
    fprintf(stderr, "Pair %.*s (%lld children) at %u:%u\n", (int)len, text,
            galley_hook_node_child_count(door, generation, node), line, column);
}
void reduction_KeyTail(GalleySession *session, unsigned long long hook) {
    galley_procedure_drop_if_empty(session, hook);
}
void hook_print(GalleySession *session, unsigned long long hook) {
    GalleyHookDoor *door = NULL;
    unsigned long long generation = 0;
    GalleyNodeAddress node = current_node(session, hook);
    const char *text = NULL;
    size_t len = 0;
    unsigned line = 0, column = 0;
    if (node == GALLEY_INVALID_NODE) return;
    galley_procedure_door(session, hook, &door);
    galley_hook_generation(door, &generation);
    galley_hook_node_text(door, generation, node, &text, &len);
    galley_hook_node_line_column(door, generation, node, &line, &column);
    fprintf(stderr, "@print \"%.*s\" at %u:%u\n", (int)len, text, line, column);
}
```

Each hook receives its session and a ticket (`unsigned long long`) the core
issues for that one call, never a pointer into the parser's stack. Every
`galley_procedure_*` function takes the pair and **the core checks it**: the
ticket of a hook that has returned is refused with `galley_error_stale_hook`,
from a later hook of the same parse and after the parse alike, in every build.
Tickets are never reused, so a later hook cannot revive an old one, and a
host keeps no expiry flag of its own. A call from a thread other than the one
running the parse overlaps that parse and gets `galley_error_session_in_use`
first, whatever its ticket. Tree access crosses the parse's door
instead: take it with `galley_procedure_door(session, hook, &door)` and
inspect nodes with the `galley_hook_*` twins, which take no lock while the
parse runs. The door is the same pointer for every hook of one parse and dies
when that parse ends, so a hook may keep it, and the nodes it reads, for later
hooks of the same parse. The session
door — `galley_node_*`,
`galley_tree_*`, diagnostics — refuses with `galley_error_session_in_use`
until the parse finishes, so a session stashed from a hook gains no
privilege. The core numbers parses: `galley_hook_generation(door, &g)` reports
the generation of the running parse, and `galley_root_node(session, &root,
&g)` the root and the generation of the published tree in one crossing (`0`
when nothing is published). **The core owns the check**: every session-door
node and tree call takes the generation of the tree it addresses and returns
a status, refusing anything but the published one with
`galley_error_stale_tree`. No host caches that generation, so no host-side
reading can disagree with the core about which tree is live. An operation that
takes a second node (`galley_tree_append_children`, `galley_tree_insert_before`,
`galley_tree_insert_after`, `galley_tree_insert_children_at`) takes each node's
own generation, and the core refuses a pair from two parses with
`galley_error_stale_tree`, so no host compares generations across nodes. The
hook twins take the same arguments as the session calls after the handle — the
door in place of the session, the node's generation next — and refuse the same
way: `galley_error_stale_tree` for a generation that is not the running
parse's (0 never is), `galley_error_invalid_node` for an address outside that
parse's node storage, `galley_error_null_argument` for a null door or output.
They have no `galley_error_session_in_use`, because the door is unshared by
construction. There is no validity probe: a real read is the answer, and it
refuses. The check runs in
every build — a lifetime contract, one integer compare per call.
`galley_procedure_set_current_node(session, hook, generation, node)` goes
through the same gate against the running parse (`galley_error_stale_tree`,
`galley_error_invalid_node`, `galley_error_null_argument`); a refused call
leaves the current node as it was, and `GALLEY_INVALID_NODE` clears it with no
generation check. Drop/replace the current node with
`galley_procedure_drop_*` / `galley_procedure_replace_with_children`; those
talk to the parser through the hook's own state and are not the same as
`galley_tree_remove_self`.

Semantic payloads remain unavailable through the C API.

### Host hooks

A library built with a host shim (`galley --emit-host-procedures`, used by the
Python, Java and JavaScript bindings) forwards its hooks to the host instead of
to C functions, per session. `galley_hooks_count()` and
`galley_hooks_name_data(i)` / `galley_hooks_name_length(i)` list the hooks;
`galley_session_set_hooks(session, dispatch, handle, enabled, count)` gives one
session its enabled set (one byte per hook), a dispatch callback and a handle.
Each enabled hook then calls `dispatch(handle, index, hook)` on the parsing
thread, with the ticket of that call; the others return before any call. `dispatch`
returns an `int`: zero lets the parse go on, anything else means the hook failed. The host keeps
the cause (a binding catches the exception at the upcall, never lets it cross into the core), the
parse stops where the hook ran, publishes nothing, and the parse call returns
`galley_error_hook_failed`. The diagnostic is of kind `galley_diagnostic_kind_hook`, with the
position, and the session parses again. Hooks compiled into the library from C or C++ return `void` and
cannot fail the parse yet. The call takes the session's
exclusive lease, so it returns `galley_error_session_in_use` while a parse is
in flight and the set a parse runs with is fixed for that parse. Sessions share
no hook state, so sessions of one library, and of different libraries, may
parse on different threads at the same time (see
`bindings/c/tests/test_concurrency.c`). Libraries built with C hooks report
zero hooks.

## Error Messages

Messages are customizable without any Zig: message **overrides** (fixed
strings with placeholders) and host-side **renderers** (dynamic
callbacks) cover virtually every need — see the two sections below.

The advanced escape hatch remains a generated Zig hook file: run
`galley --fill-error-messages examples/c`, edit any hook body (for
example `syntax_error_ll_Number__expected_generative_terminal_digit`);
when `ll_error_messages.zig` lives next to the parser the consumer build
picks it up automatically, otherwise pass it explicitly:

```cmake
"-Derror-messages-zig-source=/path/to/ll_error_messages.zig"
```

`galley_diagnostic_message` then returns the text your hooks render;
without the flag (or for un-customized grammars) it returns the built-in
generic renderer output. The `_ansi` accessor always renders generically.
LR grammars use the same flow with `lr_error_messages.zig` and
`syntax_error_lr_*` hook names.

### Message Overrides

To replace messages with fixed strings — no Zig file at all — register
overrides keyed by structured identity: the innermost in-progress
variable name (for example `"Number"`), or `"*"` for every syntax and
indentation error. Variable keys win over `"*"`; overrides take priority
over hooks. Placeholders expand against the failing diagnostic:

```c
galley_session_set_message_override(session,
    "Number", sizeof("Number") - 1,
    "expected a number after ':' (digits only) at line {line}",
    sizeof("expected a number after ':' (digits only) at line {line}") - 1);
```

Both strings are copied; overrides persist for the session's lifetime. The call
returns `galley_error_session_in_use`, changing nothing, while a parse runs
(from another thread or from a hook).

Placeholders inside override messages expand against the failing
diagnostic: `{line}`, `{column}`, `{unexpected}`, `{expected}` (rendered
as `'a', 'b'`), and `{context}` (innermost-first chain joined with
` <~ `). Unknown names pass through untouched.

## Build Model

Consumers drive two commands from whatever build system they prefer — no
Galley-side build knowledge is required:

1. **Generate** the parser from a grammar with the generator CLI (operating
   on a *language directory* containing `ll.grm` and/or `lr.grm`; boilerplate
   modules are created automatically):

   ```sh
   <galley>/zig-out/bin/galley --parser-type ll /path/to/language-dir
   # → /path/to/language-dir/_ll-parser.zig      (--parser-type lr → _lr-parser.zig)
   ```

2. **Compile** the generated parser into a shared library with Galley's
   generic consumer build file, directly next to the grammar:

   ```sh
   zig build --build-file <galley>/bindings/c/consumer/build.zig \
       "-Dlanguage-dir=/path/to/language-dir" \
       "-Dlib-name=mylang" \
       "-Doutput=libmylang.so" \
       --prefix /path/to/language-dir install
   # → /path/to/language-dir/libmylang.so (no lib/ layer, no header;
   #    read galley.h from <galley>/bindings/c, or pass -Dinstall-header)
   ```

   The library builds ReleaseFast unless you pass `-Doptimize=<mode>`;
   `-Doptimize=Debug` turns on the runtime's misuse checks (a failed check
   aborts the process), which release builds leave out. `--release=<mode>`
   is not honored.

   Both parser families work identically through this ABI: the consumer
   locates `_ll-parser.zig` vs `_lr-parser.zig` in the language dir and infers
   the family from the filename (`-Dparser-source` plus `-Dparser-type` only
   for non-standard filenames and layouts). One library embeds one parser.

Generation-time options come from [`config.zig`](/configuration) in the
language directory; CLI flags edit its constants in place.

The consumer build infers every language-owned source next to the parser
when no explicit flag is given — `config.zig`, `procedures.zig`,
`{ll,lr}_error_messages.zig` (when present, otherwise the built-in
template), and a `procedures.c` or `procedures.cpp` implementation when
present. Explicit flags (`-Dconfig-zig-source`, `-Dprocedures-zig-source`,
`-Dprocedures-c-source` / `-Dprocedures-object`,
`-Derror-messages-zig-source`, `-Dparser-source` / `-Dparser-type`) override inference and exist only for
non-standard layouts where those files live elsewhere. The reference
`examples/c` and `examples/cpp` builds pass only `parser-source` and rely
on inference for the rest.

### What the examples' CMake does

Both examples wire steps 1–2 into CMake so a plain
`cmake -S examples/c -B build -DCMAKE_BUILD_TYPE=Release -DGALLEY_CHECKOUT="$PWD" && cmake --build build` builds
its CLI, generates the parser from the example's own `ll.grm`, compiles the
library next to the grammar, builds `build/bin/demo` and `build/bin/benchmark`, and runs nothing else. Generation also
re-runs automatically whenever `ll.grm` or `config.zig` changes. Without
`GALLEY_CHECKOUT` the configure step fails loudly (for convenience,
`GALLEY_CHECKOUT=$(examples/scripts/fetch-galley.sh)` fetches one).

Useful variables:

| Variable | Purpose |
| --- | --- |
| `GALLEY_CHECKOUT` | Existing Galley working tree (required) |
| `GALLEY_OPTIMIZE` | Zig build mode of the parser libraries (`Debug`, `ReleaseSafe`, `ReleaseFast`, `ReleaseSmall`); unset builds ReleaseFast |

Generated files (`_ll-parser.zig`, `config.zig`, `procedures.zig`) and the
grammar library (`libkeyvalue-c.*`, `libbenchmark-c.*`) live in
the example directory and are gitignored.
After a build, `build/bin/` contains `demo` and `benchmark` — the
Galley CLI stays inside its own tree.

Both example directories also emit `compile_commands.json` next to their
sources and ship a `.clangd` fallback, so editors resolve `<galley.h>` and
offer completion before the first build.

Passing a file path as the only argument parses that file and nothing
else (exit status reports success; failures print a diagnostic):

```sh
./build/bin/demo path/to/input.file
```

## Runtime Concepts

### Sessions

```c
GalleySession *session = galley_session_create();
/* or with options: */
const GalleyCOptions options = { .max_errors = 10 };
GalleySession *session = galley_session_create_ex(&options);
/* ... */
if (galley_session_destroy(session) != galley_ok) {
    /* A parse is in flight (another thread or a hook): nothing was freed,
       the session still works. Retry once the parse is done. */
}
```

Destroy returns `galley_ok`, and `galley_session_destroy(NULL)` is a no-op
that also returns `galley_ok`, so a repeated close stays harmless. It takes
the session's exclusive lease, so `galley_error_session_in_use` means a parse
was running and **nothing was touched**: the session keeps parsing, reading
and closing.

Sessions are **not thread-safe** — use one per thread or guard externally,
including the handle's lifetime. Destroy refuses only while the core can see
a parse in flight: a caller holding the pointer before the core takes its
lock is invisible to the core and enters it afterwards, so no call may race a
`galley_session_destroy` that succeeds. Keep one owner per handle — or a
count checked before the pointer can go.

All result data (node addresses, text pointers, input pointers, diagnostic
strings) remains valid until the next parse on the same session or session
destruction; on the hook door, text and input pointers only until the calling
hook returns. A host copies them out before it hands anything to its users.

### Parsing

```c
long long parsed = galley_parse_sentinel(session, input);      /* NUL-terminated */
long long parsed = galley_parse(session, data, len);           /* arbitrary bytes */
long long parsed = galley_parse_file(session, "file.json");    /* from disk */
```

Returns the number of bytes parsed on success, or a negative
`galley_error_*` code (`galley_status_string` renders any code). Parsing copies
the input: the caller may reuse or release its buffer once the call returns.

### Walking the AST

Node handles are stable byte indices (`GalleyNodeAddress`); editing never
invalidates them. Walk depth-first through the shared walk cursor rather
than hand-rolling recursion, so order and depths match every binding. The
cursor is a 40-byte struct you own — no native allocation, so there is
nothing to destroy: zero it, set `root`, `generation`, and `options`, then
step once per node:

```c
GalleyWalkCursor cursor = {0};
unsigned long long generation = 0;
GalleyNodeAddress root = GALLEY_INVALID_NODE;
long long published = galley_root_node(session, &root, &generation);
if (published < 0) { /* a parse holds the session */ }
cursor.generation = generation;
cursor.root = root;
long long status;
while ((status = galley_walk_next(session, &cursor)) > 0) {
    GalleyNodeAddress n = cursor.current;
    unsigned int depth = cursor.depth;
    const char *name_data; size_t name_len;
    const char *text_data; size_t text_len;
    unsigned int line = 0, column = 0;
    galley_node_symbol_name(session, generation, n, &name_data, &name_len);
    galley_node_text(session, generation, n, &text_data, &text_len);
    galley_node_line_column(session, generation, n, &line, &column);
}
```

`galley_walk_next` returns 1 for a yielded node, 0 when the walk is done
(further steps keep returning 0 while the cursor's tree is live), or a
negative code: `galley_error_stale_tree` after a re-parse, a finished walk
included, `galley_error_session_in_use` while a parse runs, or
`galley_error_invalid_node` for a cursor that is not a walk position, an
invalid root, or a step whose position is no longer inside the walk's root
(removed, or moved elsewhere) — steps follow the live links, so edits
between steps are visible, and a detached step repeats that failure rather
than yielding anything past the detachment. Skipping is host-side —
write `cursor.state = GALLEY_WALK_STATE_YIELDED_SKIP_CHILDREN` and the next
step continues with the next sibling — and `GALLEY_WALK_SKIP_SEMANTIC_ERRORS`
and `GALLEY_WALK_SKIP_RECOVERED` in `cursor.options` prune subtrees rooted at
semantic-error nodes and at recovered nodes. After each step `cursor.flags`
carries `GALLEY_WALK_FLAG_SEMANTIC_ERROR` and `GALLEY_WALK_FLAG_RECOVERED` for
the yielded node.
`galley_hook_walk_next(door, &cursor)` is the same walk through the hook
door, for stepping inside a running parse's hook (stamp `generation` with
`galley_hook_generation`; a cursor of another generation is
`galley_error_stale_tree`).

`galley_node_first_child`, `galley_node_next_sibling`,
`galley_node_child_count`, `galley_node_last_child`,
`galley_node_prior_sibling`, `galley_node_parent`, `galley_node_span`, and
`galley_node_variable_index` complete the read surface. `galley_tree_snapshot`
reads the same columns for every node in one call into caller-owned flat
arrays (parent, first child, next sibling, child count, variable index,
span start, span length, semantic-error flag, recovered flag); it returns the
node count and writes up to `capacity` entries, so size with
`galley_node_count` first and pass null for columns you do not need. Spans
index the retained input, readable in one call with `galley_last_input`.

### Failed parses that publish

A parse that fails after running to its end publishes its tree: one that
only recorded semantic errors (`galley_error_semantic`) and one whose syntax
errors the parser recovered from (`galley_error_syntax`) both leave the tree
readable through `galley_root_node`, exactly as a success does, with the
failure's status as the parse's return value. The damaged regions are flagged
recovered nodes (`GALLEY_WALK_FLAG_RECOVERED`, snapshot column
`out_is_recovered`): under LL parsing the damaged variable's own node, with
the children parsed before the damage, and under LR parsing a placeholder
with no children — each spanning the input recovery skipped, attached where
the damage was. Walk with `GALLEY_WALK_SKIP_RECOVERED` to see only the
undamaged nodes. A parse the parser could not recover from, or that failed to
read, publishes nothing, and `galley_root_node` reports it; a published
failure may also have no root (recovery skipped everything before the first
symbol), reported as `GALLEY_INVALID_NODE` with a nonzero generation.

Node reads belong to the published parse. Every session-door node
and tree call takes the generation of the tree it addresses right after the
session, which `galley_root_node` reports together with the root (`0` when
nothing is published), and returns a `long long`. Calls with one result
(`galley_node_count`, `galley_node_child_count`, the five links,
`galley_node_variable_index`) return it directly: a value `>= 0` is the
answer and a negative value is the status; calls with several results keep
out-parameters. Once a later parse — published or not — has retired that
generation, every such call answers `galley_error_stale_tree`, and a parse in
flight answers `galley_error_session_in_use`. A missing link is the
non-negative `GALLEY_INVALID_NODE` (`INT64_MAX`) and a node without a
variable is `GALLEY_NO_VARIABLE` (also `INT64_MAX`, in `galley_node_variable_index`
and the snapshot's variable column): every address and both sentinels are
non-negative, so only statuses are negative. `galley_last_input` and
`galley_last_position` follow the published tree like every node read: they
answer `galley_error_stale_tree` whenever nothing is published — before the
first parse included — and `galley_error_session_in_use` mid-parse.

### Editing the Tree

Chains passed to edit functions must be detached orphans; edits never
invalidate other addresses. Indexes and counts must stay within the
siblings and children present. An index or count past the end returns
`galley_error_invalid_node` in every build. The other rules are checked only
in Debug builds, where a failed check aborts the process: in other builds,
passing an attached chain corrupts the tree.

```c
GalleyNodeAddress head;
galley_tree_clean_children(session, generation, parent, &head);
galley_tree_append_children(session, generation, parent, generation, head);
galley_tree_insert_before(session, generation, target, generation, chain);
galley_tree_insert_after(session, generation, target, generation, chain);
galley_tree_insert_children_at(session, generation, parent, index, generation, chain);
galley_tree_remove_siblings(session, generation, node, count, &head);
galley_tree_remove_self(session, generation, node, &head);
galley_tree_remove_children_at(session, generation, parent, index, count, &head);
```

### Diagnostics

When a parse fails, structured information is available until the next
parse:

```c
if (galley_has_diagnostic(session)) {
    long long kind = galley_diagnostic_kind(session); /* none/syntax/indentation/semantic */
    unsigned int line, column;
    galley_diagnostic_position(session, &line, &column);

    const char *msg;
    galley_diagnostic_message(session, &msg);        /* plain text */
    galley_diagnostic_message_ansi(session, &msg);   /* colored */

    long long count = galley_diagnostic_expected_count(session);
    for (long long i = 0; i < count; ++i) {
        const char *tok; size_t len;
        galley_diagnostic_expected_at(session, i, &tok, &len);
    }
    /* context chain: galley_diagnostic_context_count/_at */
    /* unexpected token: galley_diagnostic_unexpected_token */
    /* indentation details: galley_diagnostic_indentation */
    /* recovery target: galley_diagnostic_recovery_* */
}
```

`galley_syntax_error_count` reports how many errors a recovery-enabled
parse recorded.

Recovery-enabled parses retain every diagnostic they record, addressable by
index (0-based, in recording order) until the next parse:

```c
long long recorded = galley_recorded_diagnostic_count(session);
for (long long i = 0; i < recorded; ++i) {
    unsigned int line, column;
    galley_recorded_diagnostic_position(session, i, &line, &column);
    long long kind = galley_recorded_diagnostic_kind(session, i);
    /* plus recorded_{unexpected_token,expected_count,expected_token,
       context_count,context_name,indentation,recovery_*}, mirroring the
       singular accessors above; messages render generically via
       galley_recorded_diagnostic_message */
}
```

The singular accessors report the most recent diagnostic.

### Parser Metadata

`galley_parser_type`, `galley_error_recovery_mode`, `galley_has_ast`,
`galley_has_procedures`, `galley_source_retention_enabled`,
`galley_has_position_tracking`, `galley_has_input_streaming`,
`galley_uses_verbatim`, `galley_stack_overflow_recovery_available`, and the
grammar symbol table (`galley_symbol_count` / `_name` / `_is_terminal`,
`galley_variable_count` / `_name`) let embedders introspect exactly what the
library was built with.

## Storage Notes

AST nodes live in non-relocating storage (a reserved contiguous region on
macOS/Linux/BSD, fixed segments elsewhere), which is why node addresses and
pointers derived from them are stable across allocations. Node storage can
be preallocated with `galley_reserve_nodes`; `galley_node_capacity` reports
the current capacity, or `galley_error_session_in_use` while a parse runs.

## Development builds

Every green CI run uploads per-platform kits (`galley-c-<version>-<platform>.tar.gz`) as
workflow artifacts (Actions → the run → Artifacts → `pkg-c`), holding
the generator binary, `galley.h`, and the compile inputs — no repo
checkout needed. Each kit ships a README with the two commands; you
still need a Zig 0.17.0+ toolchain and a C compiler:

```sh
mkdir -p galley-c && tar xzf galley-c-<version>-linux-x64.tar.gz -C galley-c --strip-components=1
./galley-c/bin/galley --emit-metadata <language-dir>
zig build --build-file galley-c/share/galley/compile-kit/build.zig \
  -Dlanguage-dir=<language-dir> -Dlib-name=<name> \
  -Doutput=lib<name>.so \
  --prefix <language-dir> install
```

Versioned releases carry the same kits under versioned names for
anything durable. One kit serves C and C++ alike.

## Related Pages

- [Using Galley as a Library](/using-galley) — the language-directory
  generation flow in detail
- [Rust](/bindings_rust) and [Go](/bindings_go) — bindings over the same
  shared library
- [Grammar Guidelines](/grammar_guidelines)
- [Architecture](/architecture)
