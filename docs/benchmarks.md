# Benchmarks

## Purpose

Galley benchmarks generated parser APIs directly. Each benchmark executable
reuses one `Session`, reads the input once into sentinel-terminated memory, and
times `Session.parseSentinelBytes`.

---

## Parser Throughput

The harness benchmarks the generated parser API directly. It reuses one
`Session`, reads the input once into sentinel-terminated memory, and times
`Session.parseSentinelBytes`. Stack-overflow recovery is disabled by default so
the result isolates raw generated-parser throughput.

Use it when:

- you want raw parser throughput
- you are comparing parser versions
- you are comparing Galley to other parser libraries

Run it like this:

```sh
./zig-out/bin/galley --parser-type ll --no-ast --no-error-recovery --input-size 32 languages/json
zig build -Doptimize=ReleaseFast run-ll-json -- languages/json/samples/code-02.json --iterations 100 --warmup-iterations 10
```

The 32-bit input size is required because `code-02.json` is larger than the default 16-bit cursor range.

General form:

```text
zig build -Doptimize=ReleaseFast run-<parser>-<language> -- <file> --iterations <n> --warmup-iterations <m>
```

---

## AST Memory Usage

An opt-in API benchmark can inspect AST allocator usage without recording timing. Generate an AST-enabled parser, then build the normal API benchmark target with the compile-time instrumentation enabled:

```sh
./zig-out/bin/galley --parser-type ll --with-ast --no-procedures languages/json
zig build -Dast-memory-benchmark=true run-ll-json -- languages/json/samples/code-01.json
```

It parses once and reports reachable nodes, the final and peak allocator counters, total node creations, sparsity, and pool capacity/utilization. The instrumentation is compiled out by default; `--iterations` and `--warmup-iterations` are intentionally unavailable in this mode.

---

## Benchmark Suite And Result Generation

This script is the repository’s benchmark pipeline. `scripts/benchmark.py`
generates raw result files under `benchmark_results/`, and
`scripts/generate_benchmarks_doc.py` turns those files into the published
benchmark markdown.

Use it when:

- you want repository benchmark result files
- you want a repeatable scripted benchmark sweep
- you want to refresh the published benchmark document

Run it like this:

```sh
python3 scripts/benchmark.py --language json --parser-type LL --no-ast --input-size 16 --no-ast-for-terminals
```

After collecting fresh result files, regenerate the benchmark markdown like this:

```sh
python3 scripts/generate_benchmarks_doc.py
```

---

## Third-Party Parser Comparison

The cross-parser harness is maintained as the
[`parser-benchmark`](https://github.com/sanbus-org/parser-benchmark)
submodule. Initialize it and its pinned parser dependencies with:

```sh
git submodule update --init --recursive
```

Benchmark fixtures are external assets. Selecting one downloads it only when
missing or invalid, verifies its pinned SHA-256 checksum, and keeps it ignored
by Git. No benchmark input is stored in the repository.

```sh
cd third_party/parser-benchmark
zig build -Doptimize=ReleaseFast run
zig build -Doptimize=ReleaseFast run -- twitter
zig build -Doptimize=ReleaseFast run -- canada
zig build -Doptimize=ReleaseFast run -- citm_catalog
```

Third-party results are written below the submodule’s
`benchmark_results/json/` directory. The documentation generator reads that
location in addition to Galley’s own `benchmark_results/` tree.

---

## Validation Without Benchmarking

This is for correctness checks, not throughput reporting.

Use it when:

- you only care that parsing still works
- you want the main repository test suite

Run them like this:

```sh
zig build test
```

---

## Reading Benchmark Output

Galley benchmark outputs report:

- **Parsed bytes**
  Total bytes parsed across timed iterations.
- **Duration**
  Total timed duration.
- **Throughput**
  Parsed bytes divided by duration.
- **Nodes allocated**
  AST node allocations during the run.

These numbers represent parser API capacity, not an application-specific input
or output pipeline.

---

## Measurement Rules

Always benchmark with:

```text
-Doptimize=ReleaseFast
```

Practical rules:

1. Use warmup iterations.
2. Use inputs large enough to drown timer noise.
3. Avoid background CPU noise during comparisons.
4. Compare equivalent parser configurations and input paths.

---

## Related Pages

- [Benchmark Layout Findings](/benchmark_layout_findings)
- [Benchmark Results](/benchmark_results)
- [Writing a Language](/writing_a_language#use-a-generated-parser-from-zig-code)
