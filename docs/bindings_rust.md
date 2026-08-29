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

Set `pub const procedures = true;` in your grammar's `config.zig` and implement the
hooks in a `procedures.rs` file next to your grammar — the build helper
compiles it with rustc into a static archive and links it into the shared
library. Hooks are ordinary Rust: no C anywhere on the consumer side.

```rust
/* procedures.rs */
#[no_mangle]
pub extern "C" fn reduction_Pair(_args: *mut core::ffi::c_void) {
    eprintln!("[hook] Pair");
}
```

Reduction hooks keep their `reduction_<VariableName>` names (plus the
general `reduction`); author-defined grammar hooks are declared as
`hook_<name>`. Each hook fires after the corresponding variable is reduced.
The helper compiles `procedures.rs` with `panic=abort`, so a panic inside a
hook aborts rather than unwinding through generated parser code. Semantic
payloads are unavailable through bindings.

Because the helper drives rustc directly, editors would see
`procedures.rs` as outside any module tree. The example's Cargo.toml
therefore declares it as a staticlib example target — mirroring exactly
what the helper builds — so rust-analyzer links it as its own crate and
`cargo test` keeps it compiling:

```toml
[[example]]
name = "procedures"
path = "procedures.rs"
crate-type = ["staticlib"]
```

## Error Messages

To replace messages with fixed strings — no Zig file at all — pass
`message_overrides` in `SessionOptions`. Keys are structured identities:
the innermost in-progress variable name (for example `"Number"`), or
`"*"` for every syntax and indentation error. Variable keys win over
`"*"`, and overrides take priority over hooks. Placeholders expand
against the failing diagnostic:

```rust
let options = galley_bindings::SessionOptions {
    message_overrides: vec![(
        "Number".into(),
        "expected a number after ':' (digits only) at line {line}".into(),
    )],
    ..Default::default()
};
```

Override messages may contain `{line}`, `{column}`, `{unexpected}`,
`{expected}`, and `{context}` placeholders, expanded against the failing
diagnostic.

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
grammar's `ll.grm`, compiles the C-API shared library,
and emits the cargo directives that link your binary against it.

Generation-time options come from
[`config.zig`](/configuration) in the language directory — edit it and
rebuild; the build script re-runs when either `ll.grm` or `config.zig`
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
- [Go](/bindings_go) — cgo bindings over the same shared library
- [Configuration](/configuration) — the config.zig contract
- [Grammar Guidelines](/grammar_guidelines)
