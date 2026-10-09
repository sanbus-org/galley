# Python checker language (docs page)

Stats-annotated copy of `languages/python` for the docs Python checker
page. Same language, byte for byte; the only difference is `@count*`
hooks on statement and literal variables (`countFunction`,
`countClass`, `countImport`, `countIf`, `countLoop`, `countWith`,
`countTry`, `countMatch`, `countCase`, `countString`, `countNumber` —
one fire per construct). Hook annotations sit on the variable headers
(LHS hooks fire identically with and without AST, and — unlike
production annotations — never block the generator's left-factoring of
prefix-sharing alternatives such as `Except`). `config.zig` keeps
`procedures = true` so the page reports live totals; the host side
lives in `procedures.js`, registered explicitly by the page (browsers
cannot auto-scan `procedures.*`).

Stock tree-manipulation annotations (`@flattenLists` and friends) stay
untouched and compile to no-ops in this no-AST config via
`allow_no_ast_tree_procedures`. Error recovery stays off as in stock
(the grammar is untested with recovery on); everything else mirrors the
lean validation configs. The AST twin (`python-ast.wasm`) is built from
this same directory by `docs/scripts/build-checker-wasm.mjs`.

If the stock Python grammar changes, re-copy `ll.grm` here and re-apply
the `@count*` header annotations.

- `config.zig`: no AST, procedures on for the counting hooks, position
  tracking on, indentation config as in stock.
- `procedures.zig`: stub; the wasm builder generates its dispatch shim
  from metadata and uses that instead.
