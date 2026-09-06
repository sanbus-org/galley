# Universal Galley JavaScript Bindings

`galley-js-core` over native libraries (Node, Bun, Deno) with WebAssembly
fallback, selected per runtime. No native dependencies beyond the built
parser artifacts.

Call `await init()` once, then use the synchronous `Session` API; under
Node and Bun the backend also resolves synchronously on first use. When no
native library is found the WebAssembly backend serves instead (with a
one-time performance notice), otherwise `init()` explains how to build one.

See `docs/bindings_js_universal.md` for the consumer flow.

One module embeds one parser; sessions are not thread-safe.
