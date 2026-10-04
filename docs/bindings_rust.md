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
mod procedure {
    include!(concat!(env!("OUT_DIR"), "/galley_procedure_types.rs"));
}
use procedure::ProcedureArguments;

#[no_mangle]
pub extern "C" fn reduction_Pair(arguments: &mut ProcedureArguments) {
    let door = arguments.door();
    let Ok(Some(node)) = arguments.current_node() else { return };
    let text = door.text(node).unwrap_or(b"");
    let (line, column) = door.line_column(node).unwrap_or((0, 0));
    eprintln!(
        "Pair {} ({} children) at {line}:{column}",
        String::from_utf8_lossy(text),
        door.child_count(node)
    );
}

#[no_mangle]
pub extern "C" fn reduction_KeyTail(arguments: &mut ProcedureArguments) {
    let _ = arguments.drop_if_empty();
}

#[no_mangle]
pub extern "C" fn hook_print(arguments: &mut ProcedureArguments) {
    let door = arguments.door();
    let Ok(Some(node)) = arguments.current_node() else { return };
    let text = door.text(node).unwrap_or(b"");
    let (line, column) = door.line_column(node).unwrap_or((0, 0));
    eprintln!("@print \"{}\" at {line}:{column}", String::from_utf8_lossy(text));
}
```

Tree reads go through the parse's door, `arguments.door()`; the arguments
themselves hold per-hook state and are valid only while the hook runs. A door
read returns the same types as the session's: `Result<_, Error>`, with the
core refusing a handle of an earlier parse as `Error::StaleTree` and an
address outside the parse as `Error::InvalidNode`.

Reduction hooks keep their `reduction_<VariableName>` names (plus the
general `reduction`); author-defined grammar hooks are declared as
`hook_<name>`. Each hook fires after the corresponding variable is reduced.
The helper compiles `procedures.rs` with `panic=abort`, so a panic inside a
hook aborts rather than unwinding through generated parser code. Semantic
payloads are unavailable through bindings.

## Semantic Errors

A hook reports a semantic error when the input parses but its meaning is
invalid. `report_semantic_error` records the diagnostic, marks the node,
and returns the running total so hooks can limit themselves. Parsing
continues; a syntax-clean parse with any semantic error fails with
`Error::Semantic`:

```rust
if value > 999 {
    let _ = arguments.report_semantic_error("value out of range");
}
```

Read them through `Session::diagnostic` / `Session::diagnostics`; the
snapshot carries `kind == DiagnosticKind::Semantic` and
`semantic == Some((variable, message))`.

## Tree Walking

`Session::walk` returns a borrowing pre-order `Walker` over the published
parse, yielding one `Result<WalkStep { node, depth, is_semantic_error,
is_recovered }>` per node with the root at depth 0 — the shared
runtime walker, so order and depths match every other binding. The walker
owns no native resource: one host-side cursor, nothing dropped, and its
borrow of the session keeps a parse from starting mid-walk. A failed step
comes back as `Err(Error::InvalidNode)` — an invalid root, or a position
no longer inside the walk's root (removed, or moved elsewhere) — and ends
the iteration; steps otherwise follow the live links, so edits between
steps are visible. `skip_children` prunes the last
yielded node's children host-side; the two booleans of `walk` prune
semantic-error subtrees and recovered subtrees (the nodes syntax-error
recovery kept in place of damaged input). A parse that fails after running to
its end — semantic errors only, or syntax errors the parser recovered from —
publishes its tree like a success, `parse` still returning the failure, and
`last_input()` is that input; `TreeSnapshot` carries `is_recovered` beside
`is_semantic_error`. A parse that publishes nothing counts as a later parse:
`Session::snapshot`, `Session::node_count`, `Session::info`, `last_input()`
and every node accessor return `Err(Error::StaleTree)` until a parse
publishes, and so do they before the first parse. `last_input()` returns a
`Result` for that reason, like every read:

```rust
let root = session.root_node().expect("root read").expect("root");
for step in session.walk(root, false, false) {
    let step = step.expect("walk step");
    println!("{:width$}{:?}", "", step.node, width = step.depth as usize * 2);
}
```

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
let options = galley::SessionOptions {
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
galley = { path = "../../bindings/rust" }

[build-dependencies]
galley = { path = "../../bindings/rust" }
```

Then call `generate_and_link` from your `build.rs`:

```rust
fn main() {
    galley::build_helper::generate_and_link("language-dir");
}
```

No checkout is needed: the published crate carries the generator CLI for
every platform and the compile inputs, so only the crate plus zig are
required — for convenience, `GALLEY_CHECKOUT=$(examples/scripts/fetch-galley.sh)` fetches
one into the system cache for contributors, but that cache is examples-only, not part of the
bindings. It generates the parser from your
grammar's `ll.grm`, compiles the C-API shared library directly next to the
grammar, and emits the cargo directives
that link your binary against it.

Generation-time options come from
[`config.zig`](/configuration) in the language directory — edit it and
rebuild; the build script re-runs when either `ll.grm` or `config.zig`
changes. Only the parser-type selection travels as a build-script option
(it is not file-config): `Options::new` generates every parser type,
`.parser_type(ParserType::Ll)` or `.parser_type(ParserType::Lr)` generates
one.

The parser library builds ReleaseFast. `.optimize("Debug")` builds it in
Debug with the runtime's misuse checks instead (a failed check aborts the process); it takes any Zig build mode
(`Debug`, `ReleaseSafe`, `ReleaseFast`, `ReleaseSmall`).

## Usage

```rust
use galley::{Session, NodeHandle};

let mut session = Session::new().expect("session");

// Parse a string.
let bytes = session.parse_sentinel(r#"{"key": "value"}"#).expect("parse");

// Walk the AST.
if let Some(root) = session.root_node().expect("root read") {
    for child in session.children(root).expect("children") {
        let child = child.expect("child");
        let name = session.symbol_name(child).expect("symbol name");
        println!("{}", String::from_utf8_lossy(name));
        let text = session.text(child).expect("text");
        println!("  → {}", String::from_utf8_lossy(text));
    }
}

// Diagnostics on failure.
if session.parse_sentinel("bad input").is_err() {
    if let Some(d) = session.diagnostic() {
        eprintln!("{}:{} {}", d.line, d.column, d.message);
    }
}
```

A `NodeHandle` carries the core's parse generation and its address, and every
read and edit hands that generation to the core, which refuses one it no
longer holds with `Err(Error::StaleTree)`. `Session::root_node` is the one
"is there a tree here" probe and stamps the generation it reports; links,
walk steps, and `TreeSnapshot::node` carry their source's. It answers
`Ok(Some(root))` for a published tree, `Ok(None)` when nothing is published,
and `Err` when the core refuses (`Error::SessionInUse` while a parse runs),
while `node_count` and the accessors report `Err(Error::StaleTree)`. Nothing is cached, and there is no validity probe: a
real read is the answer, and it fails.

Tree editing follows the same address-stable model as the C API:
addresses never invalidate across edits or allocations, and every edit carries
its nodes' generation (a chain of another parse is refused with `StaleTree`),
so a retired tree is never edited by mistake.

```rust
let head = session.tree_clean_children(root).unwrap();
session.tree_append_children(root, head.unwrap()).unwrap();
```

## Session Options

```rust
use galley::SessionOptions;

let opts = SessionOptions {
    max_errors: 20,
    recovery_window: 1000,
    stack_overflow_recovery: true,
    syntax_error_stack_depth: 3,
};
let mut session = Session::with_options(opts).expect("session");
```

## Development builds

Every green CI run uploads the publish-equivalent `.crate` as a workflow
artifact (Actions → the run → Artifacts → `pkg-rust`), carrying that
commit's generator and compile kit. Download, extract, and depend by
path — no Zig toolchain needed, same as a crates.io release:

```toml
[dependencies]
galley = { path = "../galley-0.1.3-dev.42.gabc123456789" }
```

Contributors with a checkout can alternatively pin a git dependency to a
rev, but that path builds the generator from source and needs Zig
installed. Versioned releases go to crates.io as usual.

## Related Pages

- [C and C++](/bindings_c) — the underlying C ABI
- [Go](/bindings_go) — cgo bindings over the same shared library
- [Configuration](/configuration) — the config.zig contract
- [Grammar Guidelines](/grammar_guidelines)
