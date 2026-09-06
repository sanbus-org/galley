# JavaScript Bindings for Deno

`galley-js-core` over `Deno.dlopen` and `bindings/c/galley.h`. Zero
dependencies; the adapter is plain TypeScript run directly by Deno.

See `docs/bindings_js_deno.md` and `examples/js/deno` for the consumer flow.

One shared library embeds one parser; sessions are not thread-safe.
