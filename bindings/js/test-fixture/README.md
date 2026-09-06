# Shared JS binding test fixture

Verbatim keyvalue grammar sources (`ll.grm`, `config.zig`,
`procedures.zig`, `procedures.ts`) copied from `examples/js/node` when the
binding suites were decoupled from the user-facing examples. One copy serves
all five JS suites through `../core/build/fixture.mjs`, which copies these
files to a temp workdir and builds them with each adapter's own builder.

Only file *presence* affects the build (`procedures.ts` selects the JS
dispatch path; its type-only import is never resolved at build time).
`_ll-parser.zig`, `metadata.json`, `procedures_js.zig`, and the built
libraries are generated into the temp workdir, never here.

Edit these sources and every JS suite picks the change up on its next run.
