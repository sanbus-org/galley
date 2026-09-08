# JSON checker language (docs page)

Stats-annotated copy of `languages/json` for the docs JSON checker page.
Same language, byte for byte; the only difference is `@count*` production
hooks (`countObject`, `countArray`, `countNumber`, `countString`,
`countNull`, `countBoolean` on the `Value` alternatives, plus `countKey`
on the two non-empty member productions — one fire per member, hence one
per key). `config.zig` keeps `procedures = true` so the page reports
live totals; the host side lives in `procedures.js`, registered
explicitly by the page (browsers cannot auto-scan `procedures.*`).
Occurrence-level annotations are intentionally
unused: they only fire when symbols return AST nodes, and this config
builds no AST.

If the stock JSON grammar changes, mirror the change here (or re-copy
`ll.grm` and re-apply the annotations).

- `config.zig`: lean validation — no AST, procedures on for the
  counting hooks, error recovery and position tracking on.
- `procedures.zig`: stub; the wasm builder generates its dispatch shim
  from metadata and uses that instead.
