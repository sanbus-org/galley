# JavaScript Bindings for WebAssembly

`@sanbus/galley-core` over a WASI reactor module and `bindings/c/galley.h`. No
native dependencies beyond the built parser module.

See `docs/bindings_javascript.md` and `examples/js` for the consumer flow.

A loaded module serves every parser of that artifact; parsers are never shared. Sessions are not thread-safe.
