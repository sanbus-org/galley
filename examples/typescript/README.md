# Galley TypeScript example

Requires `node` ≥ 22.6, `zig`, and `git`.

```sh
node ../../bindings/typescript/build.mjs .
npm install
npx tsx main.ts
```

`build.mjs` generates the parser and builds the shared library. `procedures.ts` is the native-language hook file, mirroring Python's `procedures.py`; legacy `procedures.c` still works. Pass a file as an argument to parse it instead of the demo.
