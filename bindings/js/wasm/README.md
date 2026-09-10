# JavaScript Bindings for WebAssembly

`@sanbus/galley-core` over a WASI reactor module and `bindings/c/galley.h`. No
native dependencies beyond the built parser module.

See `docs/bindings_javascript.md` and `examples/js/wasm` for the consumer flow.

One module embeds one parser; sessions are not thread-safe.
