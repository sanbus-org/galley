# Try-it languages (docs page)

One directory per language on the Try it page, each compiled twice by
`docs/scripts/build-checker-wasm.mjs`: `<name>.wasm` from the directory
itself (the hooks setup below) and `<name>-ast.wasm` from a scratch
copy with AST on and procedures off. The tracked config is never
rewritten; both builds share one grammar and one config.

- `json/`: stats-annotated copy of the unicode JSON grammar (see its
  README.txt). Hook-counting setup: procedures on, no AST; totals fire
  during the parse via `procedures.js`. Snapshot-counting setup comes
  from the AST twin plus a host walk (`snapshot-stats.js`). The page
  lets the user pick either setup.
- `lisp/`, `lua/`, `galley/`: stock grammars with `@count*` production
  annotations added and procedures on (see each `procedures.js`);
  otherwise the lean validation configs (no AST, error recovery and
  position tracking on). If a stock grammar changes, re-copy its
  `ll.grm` here and re-apply the annotations.
- `python/`: stats-annotated copy of `languages/python` (see its
  README.txt). Same hooks setup; the AST twin inherits the
  indentation config. Stock tree-manipulation annotations stay as-is
  and compile to no-ops in the hooks build via
  `allow_no_ast_tree_procedures`.
