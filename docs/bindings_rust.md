# Rust

Galley-generated parsers can be consumed from Rust through a safe wrapper
crate: [`bindings/rust`](https://github.com/sanbus-org/galley/tree/main/bindings/rust).
It links against the same shared library as the C API and provides RAII
session management, borrowed text slices, iterator-based tree traversal, and
typed diagnostics.

A complete consumer lives in
[`examples/rust`](https://github.com/sanbus-org/galley/tree/main/examples/rust);
it is built and executed by CI on every push.

## Procedures

Set `"procedures": true` in your grammar's galley.json and implement the
hooks in a `procedures.c` file next to your grammar — the build helper
compiles it into the shared library, mirroring the C and C++ consumers:

```c
/* procedures.c */
#include <stdio.h>

void reduction_Pair(void *args) {
    fprintf(stderr, "[hook] Pair\n");
}
```

Reduction hooks keep their `reduction_<VariableName>` names (plus the
general `reduction`); author-defined grammar hooks are declared as
`hook_<name>`. Each hook fires after the corresponding variable is reduced.
Semantic payloads are unavailable through bindings.

## Error Messages

Run `galley --fill-error-messages <language-dir>` and edit the generated
`ll_error_messages.zig` next to your grammar. The build helper detects it
and compiles it into the shared library; `Session::diagnostic().message`
then returns your hooks' text instead of the built-in generic renderer.

## Build Model

Add the bindings crate to your `Cargo.toml`:

```toml
[dependencies]
galley-bindings = { path = "../../bindings/rust" }

[build-dependencies]
galley-bindings = { path = "../../bindings/rust" }
```

Then call `generate_and_link` from your `build.rs`:

```rust
fn main() {
    galley_bindings::build_helper::generate_and_link("language-dir");
}
```

The helper resolves Galley (`GALLEY_CHECKOUT` env var wins; otherwise it
shallow-clones `GALLEY_REPOSITORY` at `GALLEY_TAG`, skipping benchmarking
submodules), builds the generator CLI, generates the parser from your
grammar's `ll.grm` and `galley.json`, compiles the C-API shared library,
and emits the cargo directives that link your binary against it.

Generation options come from an optional
[`galley.json`](/configuration) in the language directory — edit it and
rebuild; the build script re-runs when either `ll.grm` or `galley.json`
changes.

## Usage

```rust
use galley_bindings::{Session, NodeHandle};

let mut session = Session::new().expect("session");

// Parse a string.
let bytes = session.parse_sentinel(r#"{"key": "value"}"#).expect("parse");

// Walk the AST.
if let Some(root) = session.root_node() {
    for child in session.children(root) {
        if let Some(name) = session.symbol_name(child) {
            println!("{}", String::from_utf8_lossy(name));
        }
        if let Some(text) = session.text(child) {
            println!("  → {}", String::from_utf8_lossy(text));
        }
    }
}

// Diagnostics on failure.
if session.parse_sentinel("bad input").is_err() {
    if let Some(d) = session.diagnostic() {
        eprintln!("{}:{} {}", d.line, d.column, d.message);
    }
}
```

Tree editing follows the same address-stable model as the C API:
addresses never invalidate across edits or allocations.

```rust
let head = session.tree_clean_children(root).unwrap();
session.tree_append_children(root, head.unwrap()).unwrap();
```

## Session Options

```rust
use galley_bindings::SessionOptions;

let opts = SessionOptions {
    max_errors: 20,
    recovery_window: 1000,
    stack_overflow_recovery: true,
    syntax_error_stack_depth: 3,
};
let mut session = Session::with_options(opts).expect("session");
```

## Related Pages

- [C and C++](/bindings_c) — the underlying C ABI
- [Configuration](/configuration) — galley.json schema
- [Grammar Guidelines](/grammar_guidelines)
