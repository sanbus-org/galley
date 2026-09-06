# JavaScript Bindings for Bun

`galley-js-core` over `bun:ffi` and `bindings/c/galley.h`. No native
dependencies beyond the built parser library.

See `docs/bindings_js_bun.md` and `examples/js/bun` for the consumer flow.

One shared library embeds one parser; sessions are not thread-safe.
