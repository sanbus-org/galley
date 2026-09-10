# JavaScript Bindings for Node

`@sanbus/galley-core` over a per-grammar NAPI addon and `bindings/c/galley.h`.

See `docs/bindings_javascript.md` and `examples/js/node` for the consumer flow.

One shared library embeds one parser; sessions are not thread-safe.
