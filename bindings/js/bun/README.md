# JavaScript Bindings for Bun

`@sanbus/galley-core` over `bun:ffi` and `bindings/c/galley.h`. No native
dependencies beyond the built parser library.

See `docs/bindings_javascript.md` and `examples/js/bun` for the consumer flow.

One shared library embeds one parser; sessions are not thread-safe.
