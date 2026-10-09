# JSON checker language (docs page)

Stats-annotated unicode JSON grammar for the docs JSON checker page.
The only difference from a plain grammar is `@count*` production
hooks (`countObject`, `countArray`, `countNumber`, `countString`,
`countNull`, `countBoolean` on the `Value` alternatives, plus `countKey`
on the two non-empty member productions — one fire per member, hence one
per key). `config.zig` keeps `procedures = true` so the page reports
live totals; the host side lives in `procedures.js`, registered
explicitly by the page (browsers cannot auto-scan `procedures.*`).
Occurrence-level annotations are intentionally
unused: they only fire when symbols return AST nodes, and this config
builds no AST.

The AST twin (`json-ast.wasm`) is built from this same directory by
`docs/scripts/build-checker-wasm.mjs`, which compiles a scratch copy
with AST on and procedures off. Host-side snapshot counting lives in
`snapshot-stats.js` (one snapshot crossing plus a host walk). The page
lets the user pick either setup per parse.

- `config.zig`: lean validation — no AST, procedures on for the
  counting hooks, error recovery and position tracking on.
- `procedures.zig`: stub; the wasm builder generates its dispatch shim
  from metadata and uses that instead.
