# Benchmarks

## Purpose

Galley has more than one benchmark route because it can answer more than one performance question.

The main split is:

- **Parser-only throughput**
  This tries to measure the parser itself with as little wrapper noise as possible.
- **Executable throughput**
  This measures the full generated executable, including its CLI path and executable-level layout effects.

Use parser-only numbers for parser comparisons. Use executable numbers when you care about the real shipped binary as a whole.

See [Benchmark Layout Findings](/benchmark_layout_findings) for the code-layout issue behind this split.

---

## Parser-only Throughput

This route benchmarks the generated parser API directly. It reuses one `Session`, reads the input once into sentinel-terminated memory, and times `Session.parseSentinelBytes`.

Use it when:

- you want raw parser throughput
- you are comparing parser versions
- you are comparing Galley to other parser libraries

Run it like this:

```sh
./zig-out/bin/galley --parser-type ll --no-ast --no-error-recovery --input-size 32 languages/json
zig build -Doptimize=ReleaseFast run-api-bench-ll-json -- languages/json/samples/code-02.json --iterations 100 --warmup-iterations 10
```

The 32-bit input size is required because `code-02.json` is larger than the default 16-bit cursor range.

General form:

```text
zig build -Doptimize=ReleaseFast run-api-bench-<parser>-<language> -- <file> --iterations <n> --warmup-iterations <m>
```

---

## AST Memory Usage

An opt-in API benchmark can inspect AST allocator usage without recording timing. Generate an AST-enabled parser, then build the normal API benchmark target with the compile-time instrumentation enabled:

```sh
./zig-out/bin/galley --parser-type ll --with-ast --no-procedures languages/json
zig build -Dast-memory-benchmark=true run-api-bench-ll-json -- languages/json/samples/code-01.json
```

It parses once and reports reachable nodes, the final and peak allocator counters, total node creations, sparsity, and pool capacity/utilization. The instrumentation is compiled out by default; `--iterations` and `--warmup-iterations` are intentionally unavailable in this mode.

---

## Executable Throughput

This route benchmarks the normal generated executable. It includes the CLI path and executable-level layout effects.

Use it when:

- you care about the real shipped binary
- you want end-to-end executable timing
- you suspect an executable-level change affected throughput

Run it like this:

```sh
./zig-out/bin/galley --parser-type ll --no-ast --no-error-recovery --input-size 32 languages/json
zig build -Doptimize=ReleaseFast run-ll-json -- languages/json/samples/code-02.json --iterations 100 --warmup-iterations 10
```

General form:

```text
zig build -Doptimize=ReleaseFast run-<parser>-<language> -- <file> --iterations <n> --warmup-iterations <m>
```

---

## Benchmark Suite And Result Generation

This route is the repository’s benchmark pipeline. `scripts/benchmark.py` generates raw result files under `benchmark_results/`, and `scripts/generate_benchmarks_doc.py` turns those files into the published benchmark markdown.

Use it when:

- you want repository benchmark result files
- you want a repeatable scripted benchmark sweep
- you want to refresh the published benchmark document

Run it like this:

```sh
python3 scripts/benchmark.py --language json --parser-type LL --no-ast --input-size 16 --no-ast-for-terminals
```

If you intentionally want executable-level suite results instead:

```sh
python3 scripts/benchmark.py --route cli --language json --parser-type LL --no-ast --input-size 16 --no-ast-for-terminals
```

After collecting fresh result files, regenerate the benchmark markdown like this:

```sh
python3 scripts/generate_benchmarks_doc.py
```

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

Interpretation depends on route:

- parser-only route means these numbers are intended to represent parser capacity
- executable route means these numbers represent the full generated executable path

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
4. Compare parser-only with parser-only, and executable with executable.

---

## Related Pages

- [Benchmark Layout Findings](/benchmark_layout_findings)
- [Benchmark Results](/benchmark_results)
- [Writing a Language](/writing_a_language#use-a-generated-parser-from-zig-code)
