# Rust binding test fixture

Keyvalue `procedures.rs` copied from `examples/rust` for the `tests/` suite in
this package; `ll.grm` and `config.zig` are symlinks to the one shared grammar in `bindings/test-fixture` for the `tests/` suite in
this package. Hook-shim types come from the `galley` crate itself:
`generate_and_link` writes them to `OUT_DIR/galley_procedure_types.rs`,
which `procedures.rs` opens with `include!` — no checkout paths involved.

The parser (`_ll-parser.zig`, `procedures.zig`, `metadata.json`,
`libgalley-rust.*`) is built into this directory by this package's own
`build.rs` (over the one shared `build_helper` gate) on every
`cargo build` / `cargo test`:

    GALLEY_CHECKOUT=<checkout> cargo test --manifest-path bindings/rust/test-fixture/Cargo.toml

Edit these sources and the Rust suite picks the change up on its next run.
