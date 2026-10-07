# JavaScript Bindings for Deno

`@sanbus/galley-core` over `Deno.dlopen` and `bindings/c/galley.h`. Zero
dependencies; the adapter is plain TypeScript run directly by Deno.

See `docs/bindings_javascript.md` and `examples/js` for the consumer flow.

A loaded library serves every parser of that artifact; parsers are never shared. Sessions are not thread-safe.
