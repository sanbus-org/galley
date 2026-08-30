# Galley TypeScript example

Requires `node` ≥ 22.6, `zig`, and `git`.

```sh
npm install
npx galley-typescript-bindings .
npx tsx main.ts
```

The build fetches Galley on its own; set `GALLEY_CHECKOUT=/path/to/galley` to develop against a local Galley checkout instead. Pass a grammar-source file as an argument to parse that file instead of running the built-in demo.
