# C and C++

Galley-generated parsers can be consumed from C and C++ through a small
application-binary interface: Galley compiles a generated parser into a
shared library (`lib<name>.dylib` / `.so`) together with the C header
[`bindings/c/galley.h`](https://github.com/sanbus-org/galley/blob/main/bindings/c/galley.h).
Complete, runnable consumers live in
[`examples/c`](https://github.com/sanbus-org/galley/tree/main/examples/c) and
[`examples/cpp`](https://github.com/sanbus-org/galley/tree/main/examples/cpp);
both are built and executed by CI on every push.

## Phase-One Scope

- Grammars must be **procedure-hook-free**: `@` annotations are tolerated by
  generation but stay inert, and hooks cannot be implemented in C yet
  (procedure dispatch is compile-time Zig). Semantic payloads are therefore
  unavailable.
- Error messages use the built-in generic renderer; custom error-message
  hooks are not exposed.
- One shared library corresponds to one grammar. Regenerating for a changed
  grammar re-runs the build steps below.

## Build Model

Generation and compilation are separate steps. **The build system never
generates anything** — you run the generator CLI yourself, then point your
build at the produced parser source.

1. **Obtain Galley** — fetch the repository (the examples use CMake
   `ExternalProject` with `GIT_SHALLOW` and skip benchmarking submodules),
   or point `-DGALLEY_CHECKOUT=/path/to/galley` at an existing working tree
   when developing Galley itself.
2. **Build the generator CLI** once inside that tree:
   ```sh
   zig build -Doptimize=ReleaseFast install
   # → <galley>/zig-out/bin/galley
   ```
3. **Generate the parser** from your grammar. The CLI operates on a
   *language directory* containing `ll.grm` (or `lr.grm`); boilerplate
   modules (`config.zig`, `procedures.zig`, error messages) are created
   automatically on first run if missing:
   ```sh
   <galley>/zig-out/bin/galley \
       --parser-type ll --with-ast --with-position-tracking --no-procedures \
       /path/to/language-dir
   # → /path/to/language-dir/_ll-parser.zig
   ```

   Generator flags are ordinary CLI options (`--with-ast` / `--no-ast`,
   `--with-position-tracking`, `--no-procedures`, ...).
4. **Build the C library** with Galley's generic consumer build file:
   ```sh
   zig build --build-file <galley>/bindings/c/consumer/build.zig \
       "-Dparser-source=/path/to/language-dir/_ll-parser.zig" \
       "-Dparser-type=ll" \
       "-Dlib-name=mylang" \
       "-Doptimize=ReleaseFast" \
       --prefix /out install
   # → /out/lib/libmylang.dylib|so and /out/include/galley.h
   ```
5. **Compile and link** your sources against the library with
   `include/galley.h` on the include path.

### What the examples' CMake does

The examples' `CMakeLists.txt` covers only steps 4–5 (plus step 1): it uses
Galley's runtime sources, compiles the library from `-Dparser-source`
(default `_ll-parser.zig` next to the grammar), and builds `bin/example`.
Regenerating after a grammar edit is your explicit step 3; rebuild picks up
the new parser.

Useful variables:

| Variable | Purpose |
| --- | --- |
| `GALLEY_REPOSITORY` | Repository fetched when no checkout is given |
| `GALLEY_TAG` | Revision to fetch (default `main`) |
| `GALLEY_CHECKOUT` | Existing Galley working tree; skips fetching |
| `PARSER_SOURCE` | Generated parser source (default `_ll-parser.zig` beside the grammar) |

After a build, `build/bin/` contains just the example executable — the
Galley CLI stays inside its own tree.

Passing a file path as the only argument parses that file and nothing
else (exit status reports success; failures print a diagnostic):

```sh
./build/bin/example path/to/input.file
```

Both example directories also emit `compile_commands.json` next to their
sources and ship a `.clangd` fallback, so editors resolve `<galley.h>` and
offer completion before the first build.

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
    long long kind = galley_diagnostic_kind(session); /* none/syntax/indentation */
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
- [Grammar Guidelines](/grammar_guidelines)
- [Architecture](/architecture)
