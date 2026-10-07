# JavaScript binding contracts

What JavaScript promises beyond [CONTRACTS.md](../CONTRACTS.md).

- Importing a generated language package is synchronous, with no initialization call, and works with both `import` and CommonJS `require()`. The package is its parser, and an entry whose import failed stays failed for the process.
- `load` accepts an explicit artifact file, raw module bytes, or a URL. Only the URL form is async, because the fetch is; every other load returns synchronously.
- Two engines run a parser: native first, WebAssembly as the fallback. The user cannot pin one. A session reports which it uses, and falling back to WebAssembly prints one notice to stderr.
