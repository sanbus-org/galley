# Project Guidelines

## Commit Messages

- Use the **Conventional Commits** format: `<type>(<scope>): <description>` or `<type>: <description>`
  - Examples: `docs: ...`, `feat(scope): ...`, `refactor(scope): ...`, `chore: ...`
- Match recent project history when choosing scopes, for example `feat(generator): ...`, `test(generator): ...`, `perf(runtime): ...`, and `refactor(language): ...`.
- When committing from the command line, use exactly one `-m` for the subject and one additional `-m` for the full body. Do not split body lines across multiple `-m` flags.
  - Example: `git commit -m "test(generator): add generated parser matrix validation" -m $'Generate parser variants through the galley_generator API.\nRun parser API and error-path validation.\nFold benchmark compilation into zig build test.'`
- Commit bodies should be concise, typically 1-4 lines.

## Workflow

- A commit is one meaningful, self-contained iteration, not a chunk of work. A fix to what the last commit introduced or claimed is amended into it, not added as a follow-up commit.
- "Ready to push" means the commit is complete and coherent. It does not mean the full test matrix ran locally: CI owns running the full suites, so run only the narrowest relevant checks locally (see Testing).
- History rewrites are routine: while pre-alpha, amend and force-push `main` freely, including after a CI failure. Once alpha begins, `main` stays linear and changes go through branches; rewriting non-main branches stays routine.
- Still ask before committing, amending, or pushing, as the global guidelines require; this section only says that rewriting is acceptable, not that it is pre-approved.

## Compatibility

We are pre-alpha and seek ZERO backward compatibility while in alpha. Public surfaces — the C ABI, host-language APIs, generated wrappers — evolve in place: change signatures, rename, delete. Never add `_ex` twins, legacy variants, or deprecation shims to spare old callers; every consumer in the repo moves in lockstep in the same change.

## Testing

- Avoid running the full `zig build test` matrix unless the change broadly affects all generated parsers.
- Prefer typed filters for focused validation, for example `zig build test -Dtest-filter=case:ll-json`, `zig build test -Dtest-filter=suite:runtime`, or `zig build test -Dtest-filter=suite:runtime -Dtest-filter=name:dropIfEmpty`.
- Available suites are `build`, `generator`, `runtime`, `matrix`, `matrix-compile`, `matrix-api`, `matrix-error`, and `galley-parity`. Repeat filters to OR values within one type; `suite:`, `case:`, and `name:` types combine with AND semantics.

## Grammar Implementation

- Treat Galley's parsed AST as the authoritative representation of grammar source. When implementing grammar semantics, prefer variable identities, production identities, child relationships, and source positions from the AST over searching, splitting, or otherwise recognizing patterns in raw source text.
- Raw text is appropriate only for leaf values that the grammar intentionally represents as text, such as identifier contents and decoded terminal bytes. Do not infer surrounding syntax, annotation placement, production shape, or semantic structure from those strings when the AST already expresses it.
- Keep Galley's own grammar and bootstrap parser exemplary: Galley is both the product and its largest real-world demonstration, so new language features should be parsed and interpreted through normal generated-parser AST mechanisms rather than ad hoc source scanning.

## Investigation Discipline

- Stop after the first contradictory result and report uncertainty.
