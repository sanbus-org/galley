# galley

Safe Rust bindings for [Galley](https://github.com/sanbus-org/galley)-generated parsers.

Galley is a parser generator and high-performance parser runtime written in
Zig. This crate provides the Rust session API over a generated parser's C
ABI, plus a build-script helper (`build_helper::generate_and_link`) that
generates the parser and links it into your binary.

```toml
[dependencies]
galley = "0"

[build-dependencies]
galley = "0"
```

```rust
// build.rs
fn main() {
    galley::build_helper::generate_and_link("language-dir");
}
```

Requires the `galley` crate and Zig at build time (no checkout needed:
the crate ships the generator and compile inputs).
Full guide: [Rust bindings](https://github.com/sanbus-org/galley/blob/main/docs/bindings_rust.md).

License: MIT © 2026 Sassan Haradji
