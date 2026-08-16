# Testing

Galley's repository tests are split into focused unit suites and a generated-parser matrix. Use typed filters to run the smallest suite that covers a change.

## Run All Tests

```sh
zig build test --summary all --test-timeout 30m
```

The full command runs build-logic, generator, runtime, generated-parser matrix, and Galley bootstrap-parity tests. The timeout applies to each individual test process, not to the entire build.

`--summary all` is optional. When provided, it applies directly to the test graph and reports individual test counts; when omitted, Zig uses its normal summary mode.

## Test Selectors

Pass one or more typed selectors with `-Dtest-filter`:

```sh
zig build test -Dtest-filter=suite:runtime
zig build test -Dtest-filter=case:ll-json
zig build test \
  -Dtest-filter=suite:matrix-api \
  -Dtest-filter=case:ll-json \
  -Dtest-filter='name:parse bytes'
```

Selectors of the same type are combined with OR. Different selector types are combined with AND. For example, two `case:` selectors select either case, while adding `suite:matrix-api` limits both cases to API tests.

Bare filters such as `-Dtest-filter=ll-json` are invalid. Use `case:ll-json` instead.

### Suites

| Selector | Runs |
| --- | --- |
| `suite:build` | Test-selector and build-logic unit tests |
| `suite:generator` | Parser-generator unit tests |
| `suite:runtime` | Configuration-independent runtime, Node, and standard-procedure tests |
| `suite:matrix` | All generated-parser matrix phases |
| `suite:matrix-compile` | Parser generation and API benchmark-harness compilation |
| `suite:matrix-api` | Generated-parser Zig API tests against language samples |
| `suite:matrix-error` | Diagnostic and recovery tests for JSON, Unicode JSON, and augmented-JSON variants |
| `suite:galley-parity` | LL-versus-LR Galley bootstrap output comparison |

### Cases

A case is an exact parser-type and language pair, such as `case:ll-json`, `case:lr-json-unicode`, or `case:ll-lua`. A `case:` selector without a `suite:` selector runs every matrix phase for that case.

Each selected case is tested across six parser configurations covering AST, procedures, and terminal AST nodes. The no-AST-with-procedures configuration is skipped for grammars whose reduction procedures require the AST. Cases do not select `suite:galley-parity`; request that suite explicitly.

### Test Names

Use `name:` to apply Zig's test-name substring filtering. It requires an explicit Zig test suite: `build`, `generator`, `runtime`, `matrix-api`, or `matrix-error`.

```sh
zig build test \
  -Dtest-filter=suite:runtime \
  -Dtest-filter=name:dropIfEmpty
```

The command fails if the name matches no tests.

## Dedicated Steps

Run the generated-parser matrix or bootstrap parity directly when no other suite is needed:

```sh
zig build test-generated-parser-matrix -Dtest-filter=case:ll-json
zig build test-generated-parser-matrix -Dtest-filter=case:lr-json-unicode
zig build test-galley-bootstrap-parity -Dtest-filter=suite:galley-parity
```

Typed filters apply directly to these dedicated steps and follow the same validation rules.

## Understanding Matrix Work

Zig test cases and build checks are reported separately:

- API tests exercise byte, sentinel, file, reusable-session, capacity, concurrency, and language-specific behavior for every eligible variant/sample combination.
- Error tests validate fail-fast diagnostics for every JSON, Unicode JSON or augmented-JSON variant. Focused recovery-enabled LL/LR variants additionally cover multiple diagnostics, limits, recovery windows, and reusable sessions.
- The `ll-json-unicode` and `lr-json-unicode` API cases additionally validate raw UTF-8 scalar boundaries, malformed UTF-8 rejection, JSON Unicode escape decoding, and surrogate pairs.
- Generation and benchmark-harness compilation validate that each selected parser configuration can be generated and consumed through its API; they are build steps, not additional Zig test cases.

Samples up to 5 MiB run on every parser configuration. Larger samples run on
the representative no-AST/no-procedures configuration for each LL/LR language
case. Focused input-streaming tests separately cover large AST input, sliding
windows, complete-file non-streaming input, and indentation boundaries.
