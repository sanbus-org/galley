# Benchmark Layout Findings

## Summary

Galley benchmarks exposed a real code-layout sensitivity in ReleaseFast builds. Small source changes that do not execute in the timed parser loop can still move generated parser functions in the final executable and change measured throughput substantially.

The important conclusion is not that CLI features add per-iteration parsing overhead. The issue is that executable text layout can place hot parser code in faster or slower address regions on modern CPUs.

## Local Findings

The JSON LL no-AST parser showed stable high throughput around 700+ MB/s in one layout, then dropped to roughly 640-670 MB/s after unrelated source changes. Symbol inspection showed that hot parser functions moved in the final binary.

Controlled padding experiments found narrow bad address windows near the generated JSON `parse_Value` entrypoint:

| `parse_Value` address | Observed behavior |
| --- | --- |
| `0x10003ff6c` | Fast, roughly 700-711 MB/s |
| `0x10003ffc4` | Fast, roughly 703 MB/s steady-state |
| `0x10003fff8` | Slow, roughly 640-648 MB/s steady-state |
| `0x100040034` | Fast again, roughly 697-706 MB/s |
| `0x100040068` | Slow again, roughly 652-664 MB/s |
| `0x100040154` | Fast again, roughly 707-710 MB/s |
| `0x1000405xx` to `0x100040axx` | Several slower pockets |
| `0x100040b1c` | Recovered, roughly 697-706 MB/s |

An exact-address reproduction for this tuple:

```text
parse_Value          = 0x10003fc30
parse_OptionalBlank  = 0x100045ff4
parse__StringContent = 0x1000484e4
```

measured around 644-646 MB/s steady-state. That proved these three function addresses alone do not fully explain the fastest layout; nearby hot functions, call sites, branch targets, and broader text layout also matter.

## Decision

Galley should not use CPU-specific padding or alignment tricks to chase a fast address family. Those fixes would be fragile across Apple Silicon generations, Intel, Linux, and future compiler/linker versions.

Instead, raw parser throughput should be measured through the lean ReleaseFast parser API path:

- CLI behavior remains ergonomic and unchanged.
- ReleaseFast generated parser modules use a smaller parser-library root internally.
- API benchmarks should avoid CLI process/layout noise and use sentinel byte input through `parseSentinelBytes`.
- Existing safe byte APIs remain available and keep their copying/sentinel behavior.

CLI benchmark output is still useful as an end-to-end executable measurement, but it is not the canonical raw parser throughput measurement.

## Practical Guidance

Use CLI benchmarks to check generated executable behavior and basic throughput. Use the ReleaseFast API sentinel path for raw parser capacity and comparisons against other parser libraries.

When investigating performance regressions, record hot parser symbol addresses with `nm -an zig-out/bin/<parser>` and compare them alongside throughput. Address changes do not prove a parser-code regression; they may indicate a layout-induced frontend effect.
