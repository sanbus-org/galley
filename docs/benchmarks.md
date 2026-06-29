# Benchmarks & Performance Methodology

## Table of Contents

- [Overview](#overview)
- [Running Benchmarks](#running-benchmarks)
- [Understanding Output Metrics](#understanding-output-metrics)
- [Reference Benchmark Results](#reference-benchmark-results)
- [Tips for Reliable Measurement](#tips-for-reliable-measurement)

---

## Overview

Galley is engineered from the ground up to maximize parsing throughput. To accurately evaluate performance and verify zero-overhead assertions across different hardware, every generated executable includes built-in benchmarking profiling support.

---

## Running Benchmarks

Always compile binaries with `-Doptimize=ReleaseFast` when measuring speed. Debug and ReleaseSafe builds include extensive safety checks and trace logging that significantly degrade throughput.

To execute a benchmark run, pass the target file along with the `-r` (`--iterations`) and `-w` (`--warmup-iterations`) flags:

```sh
# Run 100 benchmark iterations with 10 warmup passes on large JSON input
zig build -Doptimize=ReleaseFast ll-flat_json -- -r 100 -w 10 languages/json/large-sample-code.json
```

---

## Understanding Output Metrics

When invoked with `--verbosity 0` (the default), the parser executable prints a succinct benchmark summary to stdout:

```
Parsed 100 times in 6.5ms (avg: 65us) -> ~722.7 MB/s
```

- **Iterations (`Parsed N times`):** The exact number of timed parse repetitions.
- **Total & Average Duration:** Time elapsed across all timed iterations and average latency per parse pass.
- **Throughput (`MB/s`):** Calculated as `(FileSizeBytes * Iterations) / TotalTimeSeconds / 1_000_000`.

When invoked with `--verbosity 1`, additional statistics regarding AST allocations and memory pool usage are reported alongside throughput:

```
AST Nodes Allocated: 14,230
Node Pool Memory Footprint: 227.68 KB
```

---

## Reference Benchmark Results

All reference benchmarks below were recorded on an **Apple M1 Pro** executing against the bundled JSON input file using the `flat_json` grammar (`languages/json/sample-code.json`).

| Mode | LL Throughput | LR Throughput |
| :--- | :--- | :--- |
| **No AST** | **~723 MB/s** | **~285 MB/s** |
| **AST, no terminals in AST** | **~444 MB/s** | **~108 MB/s** |
| **AST, terminals in AST** | **~310 MB/s** | **~93 MB/s** |

---

## Tips for Reliable Measurement

1. **Always Use Warmup Passes (`-w 10`):** Modern CPUs throttle clock speeds when idle. Warmup iterations prime instruction caches (L1i/L2) and force CPU governor frequency scaling before timing begins.
2. **Use Large Input Files:** Parsing tiny files (< 1 KB) measures OS timer precision resolution rather than parsing throughput. Use inputs of at least 100 KB to obtain stable metrics.
3. **Isolate Background Noise:** Close CPU-heavy applications (browsers, background builds) during benchmark loops to minimize thread preemption variance.
