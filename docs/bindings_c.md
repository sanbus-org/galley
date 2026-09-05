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

void reduction_Pair(void *args) {
    GalleySession *session = galley_procedure_session(args);
    GalleyNodeAddress node = galley_procedure_current_node(args);
    const char *text = NULL;
    size_t len = 0;
    unsigned line = 0, column = 0;
    if (session == NULL) return;
    galley_node_text(session, node, &text, &len);
    galley_node_line_column(session, node, &line, &column);
    fprintf(stderr, "Pair %.*s (%u children) at %u:%u\n",
            (int)len, text, galley_node_child_count(session, node), line, column);
}
void reduction_KeyTail(void *args) {
    galley_procedure_drop_if_empty(args);
}
void hook_print(void *args) {
    GalleySession *session = galley_procedure_session(args);
    GalleyNodeAddress node = galley_procedure_current_node(args);
    const char *text = NULL;
    size_t len = 0;
    unsigned line = 0, column = 0;
    if (session == NULL) return;
    galley_node_text(session, node, &text, &len);
    galley_node_line_column(session, node, &line, &column);
    fprintf(stderr, "@print \"%.*s\" at %u:%u\n", (int)len, text, line, column);
}
```

Each hook receives an opaque `ProcedureArguments` pointer. Recover the
parsing session with `galley_procedure_session` and inspect nodes with the
ordinary `galley_node_*` functions. Drop/replace the current node with
`galley_procedure_drop_*` / `galley_procedure_replace_with_children`; those
talk to the parser through `args.node_address` and are not the same as
`galley_tree_remove_self`.

Semantic payloads remain unavailable through the C API.

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

Both strings are copied; overrides persist for the session's lifetime.

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
   generic consumer build file:

   ```sh
   zig build --build-file <galley>/bindings/c/consumer/build.zig \
       "-Dparser-source=/path/to/language-dir/_ll-parser.zig" \
       "-Dparser-type=ll" \
       "-Dlib-name=mylang" \
       "-Doptimize=ReleaseFast" \
       --prefix /out install
   # → /out/lib/libmylang.dylib|so and /out/include/galley.h
   ```

   Both parser families work identically through this ABI: pass the
   `_lr-parser.zig` source with `-Dparser-type=lr` for an LR grammar.
   One library embeds one parser.

Generation-time options come from [`config.zig`](/configuration) in the
language directory; CLI flags edit its constants in place.

The consumer build infers every language-owned source next to the parser
when no explicit flag is given — `config.zig`, `procedures.zig`,
`{ll,lr}_error_messages.zig` (when present, otherwise the built-in
template), and a `procedures.c` or `procedures.cpp` implementation when
present. Explicit flags (`-Dconfig-zig-source`, `-Dprocedures-zig-source`,
`-Dprocedures-c-source` / `-Dprocedures-object`,
`-Derror-messages-zig-source`) override inference and exist only for
non-standard layouts where those files live elsewhere. The reference
`examples/c` and `examples/cpp` builds rely entirely on inference and
pass only `parser-source` and `parser-type`.

### What the examples' CMake does

Both examples wire steps 1–2 into CMake so a plain
`cmake -S examples/c -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build` fetches Galley, builds
its CLI, generates the parser from the example's own `ll.grm`, compiles the
library, builds `build/bin/demo` and `build/bin/benchmark`, and runs nothing else. Generation also
re-runs automatically whenever `ll.grm` or `config.zig` changes.

Useful variables:

| Variable | Purpose |
| --- | --- |
| `GALLEY_REPOSITORY` | Repository fetched when no checkout is given |
| `GALLEY_TAG` | Revision to fetch (default `main`) |
| `GALLEY_CHECKOUT` | Existing Galley working tree; skips fetching |

Generated files (`_ll-parser.zig`, `config.zig`, `procedures.zig`) live in
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
galley_session_destroy(session);
```

Sessions are **not thread-safe** — use one per thread or guard externally.
All result data (node addresses, text pointers, diagnostic strings) remains
valid until the next parse on the same session or session destruction.

### Parsing

```c
long long parsed = galley_parse_sentinel(session, input);      /* NUL-terminated */
long long parsed = galley_parse(session, data, len);           /* arbitrary bytes */
long long parsed = galley_parse_file(session, "file.json");    /* from disk */
```

Returns the number of bytes parsed on success, or a negative
`galley_error_*` code (`galley_status_string` renders any code).

### Walking the AST

Node handles are stable byte indices (`GalleyNodeAddress`); editing never
invalidates them.

```c
GalleyNodeAddress root = galley_root_node(session);
for (GalleyNodeAddress n = galley_node_first_child(session, root);
     n != GALLEY_INVALID_NODE;
     n = galley_node_next_sibling(session, n)) {
    const char *name_data; size_t name_len;
    const char *text_data; size_t text_len;
    unsigned int line = 0, column = 0;
    galley_node_symbol_name(session, n, &name_data, &name_len);
    galley_node_text(session, n, &text_data, &text_len);
    galley_node_line_column(session, n, &line, &column);
}
```

`galley_node_child_count`, `galley_node_last_child`,
`galley_node_prior_sibling`, `galley_node_parent`, `galley_node_span`, and
`galley_node_variable_index` complete the read surface.

### Editing the Tree

Chains passed to edit functions must be detached orphans; edits never
invalidate other addresses.

```c
GalleyNodeAddress head;
galley_tree_clean_children(session, parent, &head);
galley_tree_append_children(session, parent, head);
galley_tree_insert_before(session, target, chain);
galley_tree_insert_after(session, target, chain);
galley_tree_insert_children_at(session, parent, index, chain);
galley_tree_remove_siblings(session, node, count, &head);
galley_tree_remove_self(session, node, &head);
galley_tree_remove_children_at(session, parent, index, count, &head);
galley_tree_promote_children_over_wrapper(session, wrapper, &head);
galley_tree_unlink_wrapper(session, wrapper);
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
the current capacity.

## Related Pages

- [Using Galley as a Library](/using-galley) — the language-directory
  generation flow in detail
- [Rust](/bindings_rust) and [Go](/bindings_go) — bindings over the same
  shared library
- [Grammar Guidelines](/grammar_guidelines)
- [Architecture](/architecture)
