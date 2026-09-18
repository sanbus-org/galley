# Universal Galley JavaScript Bindings

`@sanbus/galley-core` over native libraries (Node, Bun, Deno) with WebAssembly
fallback, selected per runtime. No native dependencies beyond the built
parser artifacts.

Create sessions through async factories — `Session.fromDirectory` (a
language directory, native-first per runtime), `Session.fromBytes` (raw
wasm), or `Session.fromUrl` (fetched). When no native library is found
the WebAssembly backend serves instead (with a one-time performance
notice), otherwise the factory explains how to build one.

See `docs/bindings_javascript.md` for the consumer flow.

One module embeds one parser; sessions are not thread-safe.
