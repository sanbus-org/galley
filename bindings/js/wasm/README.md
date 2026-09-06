# JavaScript Bindings for WebAssembly

`galley-js-core` over a WASI reactor module and `bindings/c/galley.h`. No
native dependencies beyond the built parser module.

See `docs/bindings_js_wasm.md` and `examples/js/wasm` for the consumer flow.

One module embeds one parser; sessions are not thread-safe.
