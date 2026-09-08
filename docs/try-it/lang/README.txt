# Try-it languages (docs page)

One directory per language on the Try it page, each built to its own
wasm next to its grammar and copied under `docs/public/try-it/` by
`docs/scripts/build-checker-wasm.mjs`.

- `json/`: stats-annotated copy of `languages/json` (see its README.txt).
  Hook-counting setup: procedures on, no AST; totals fire during the
  parse via `procedures.js`.
- `json-ast/`: same grammar with AST on and procedures off.
  Snapshot-counting setup: one snapshot crossing plus a host walk
  (`snapshot-stats.js`). The page lets the user pick either setup.
- `lisp/`, `lua/`, `galley/`: verbatim copies of `languages/lisp`,
  `languages/lua`, and `languages/galley` with lean validation configs
  (no AST, no procedures,
  error recovery and position tracking on). If a stock grammar changes,
  re-copy its `ll.grm` here.
