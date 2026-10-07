# JavaScript Bindings for Node

`@sanbus/galley-core` over a per-grammar NAPI addon and `bindings/c/galley.h`.

See `docs/bindings_javascript.md` and `examples/js` for the consumer flow.

A loaded library serves every parser of that artifact; parsers are never shared. Sessions are not thread-safe.
