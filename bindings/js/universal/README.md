# Universal Galley JavaScript Bindings

`@sanbus/galley-core` over native libraries (Node, Bun, Deno) with WebAssembly
fallback, selected per runtime. No native dependencies beyond the built
parser artifacts.

Create parsers through the `galley` object — `load` (an explicit
artifact file), `loadBytes` (raw wasm bytes), or `loadUrl` (fetched,
the one async factory) — or through `openLanguageDirectory` in a
generated entry. A language directory with no native library falls
back to WebAssembly with a one-time performance notice; anything
missing explains how to build an artifact.

See `docs/bindings_javascript.md` for the consumer flow.

One module embeds one parser; sessions are not thread-safe.
