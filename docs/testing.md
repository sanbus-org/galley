# Testing

Galley's repository tests are split into standalone unit suites and a generated-parser matrix. Use typed filters to run the smallest suite that covers a change.

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
zig build test -Dtest-filter=case:ll-sanbus
zig build test \
  -Dtest-filter=suite:matrix-api \
  -Dtest-filter=case:ll-sanbus \
  -Dtest-filter='name:parse bytes'
```

Selectors of the same type are combined with OR. Different selector types are combined with AND. For example, two `case:` selectors select either case, while adding `suite:matrix-api` limits both cases to API tests.

Bare filters such as `-Dtest-filter=ll-sanbus` are invalid. Use `case:ll-sanbus` instead.

### Suites

| Selector | Runs |
| --- | --- |
| `suite:build` | Test-selector and build-logic unit tests |
| `suite:generator` | Parser-generator unit tests |
| `suite:runtime` | Configuration-independent runtime, ASTNode, and standard-procedure tests |
| `suite:matrix` | All generated-parser matrix phases |
| `suite:matrix-compile` | Parser generation and production CLI compilation |
| `suite:matrix-api` | Generated-parser Zig API tests against language samples |
| `suite:matrix-error` | Diagnostic and recovery tests for 16-bit JSON, augmented-JSON, and Sanbus variants |
| `suite:matrix-cli` | Generated parser CLI validation against language samples |
| `suite:galley-parity` | LL-versus-LR Galley bootstrap output comparison |

### Cases

A case is an exact parser-type and language pair, such as `case:ll-json`, `case:lr-json`, or `case:ll-lua`. A `case:` selector without a `suite:` selector runs every matrix phase for that case.

Each selected case is tested across ten parser configurations covering AST, procedures, terminal AST nodes, and 16-bit versus 32-bit input sizes. Cases do not select `suite:galley-parity`; request that suite explicitly.

### Test Names

Use `name:` to apply Zig's test-name substring filtering. It requires an explicit Zig test suite: `build`, `generator`, `runtime`, `matrix-api`, or `matrix-error`.

```sh
zig build test \
  -Dtest-filter=suite:runtime \
  -Dtest-filter=name:dropIfEmpty
```

The command fails if the name matches no tests.

## Dedicated Steps

Run the generated-parser matrix or bootstrap parity directly when no standalone suite is needed:

```sh
zig build test-generated-parser-matrix -Dtest-filter=case:ll-json
zig build test-galley-bootstrap-parity -Dtest-filter=suite:galley-parity
```

Typed filters apply directly to these dedicated steps and follow the same validation rules.

## Understanding Matrix Work

Zig test cases and build checks are reported separately:

- API tests run five Zig test functions for every eligible variant/sample combination.
- Error tests validate fail-fast diagnostics for every 16-bit JSON, augmented-JSON, or Sanbus variant. Focused recovery-enabled LL/LR variants additionally cover multiple diagnostics, limits, recovery windows, and reusable sessions.
- CLI validation runs each eligible sample through the generated executable once.
- Generation and production compilation validate that each selected parser configuration can be generated and built; they are build steps, not additional Zig test cases.

Samples that exceed a 16-bit parser's input limit run only on 32-bit configurations.
