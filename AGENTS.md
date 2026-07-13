# Project Guidelines

## Commit Messages

- Use the **Conventional Commits** format: `<type>(<scope>): <description>` or `<type>: <description>`
  - Examples: `docs: ...`, `feat(scope): ...`, `refactor(scope): ...`, `chore: ...`
- Match recent project history when choosing scopes, for example `feat(generator): ...`, `test(generator): ...`, `perf(runtime): ...`, and `refactor(language): ...`.
- When committing from the command line, use exactly one `-m` for the subject and one additional `-m` for the full body. Do not split body lines across multiple `-m` flags.
  - Example: `git commit -m "test(generator): add generated parser matrix validation" -m "Generate parser variants through the galley_generator API.\nRun library/API and CLI smoke validation.\nFold benchmark validation into zig build test."`
- Commit bodies should be concise, typically 1-4 lines.
- Never commit unless explicitly instructed by the user.

## Testing

- Avoid running the full `zig build test` matrix unless the change broadly affects all generated parsers.
- Prefer typed filters for focused validation, for example `zig build test -Dtest-filter=case:ll-sanbus`, `zig build test -Dtest-filter=suite:runtime`, or `zig build test -Dtest-filter=suite:runtime -Dtest-filter=name:dropIfEmpty`.
- Available suites are `build`, `generator`, `runtime`, `matrix`, `matrix-compile`, `matrix-api`, `matrix-error`, `matrix-cli`, and `galley-parity`. Repeat filters to OR values within one type; `suite:`, `case:`, and `name:` types combine with AND semantics.
