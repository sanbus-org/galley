#!/usr/bin/env python3
"""Same-machine interleaved benchmark comparison vs examples/zig.

Build the benchmark binaries first (see .github/workflows/ci.yml), and
pass --parser-dir at the built parser package for the hosts that load one
(python, js, java). This script runs them interleaved, shuffling the
language order randomly within each round (--seed pins the order; the
seed in use is printed at start), scores the best of
the non-warmup rounds, and fails if a C-ABI example is below --min-ratio
of Zig's second-best scored round. The report shows each language's best
and median against Zig's best and median; those display ratios never
decide pass or fail.
Per-language bars (--min-ratio-override) replace the global bar for the
named languages; currently only the WebAssembly example uses one, since it
runs the same parser compiled to wasm, which trails native codegen.
Per-language round counts (--rounds-override) replace the default count
for the named languages. --rounds sets zig's count and the references
mirror it for pairing; every other runner counts as a binding and runs
fewer total rounds, since bindings need only the best-of bar, not the
paired tests' depth.
The step-summary table's status column marks rows below their bar
(bindings that have not caught up with zig) and misses inside the
informational band.
When --zig-parent-binary or --zig-ref-binary names an examples/zig
build from the parent commit or from the performance-reference tag, that
binary runs interleaved in every round, pairing each scored round's zig
reading against the reference's. On pull_request the checkout is the
merge commit, so zig-parent compares against the PR base rather than the
commit's own parent. The zig-parent and zig-ref rows are exempt from the
bar: each fails only when exact one-sided paired permutation and
Wilcoxon signed-rank tests on the paired differences both judge zig
significantly slower than that reference (p < 0.01). Significant
speedups show an up arrow and never fail; the rows' ratios still divide
by zig's best and median like every other row's.
"""

from __future__ import annotations

import argparse
import contextlib
import io
import os
import random
import re
import statistics
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

BPS_RE = re.compile(r"^bytes_per_second:\s*([0-9,]+)\s*$")
# zig's round count, shared by the references that pair against it: 18
# interleaved rounds minus 1 warmup leave 17 scored pairs for the
# reference tests below — the exact tests' power grows with the scored
# count, and their false-alarm rate does not shrink with it (see
# REFERENCE_ALPHA). The warmup only has to put the sample in page cache
# and the CPU at frequency — system state the interleaved runs neither
# create nor destroy — so one round covers it.
DEFAULT_ROUNDS = 18
# Bindings never feed the paired tests, only the best-of bar, so they
# need no statistical depth: 7 total rounds leave 6 scored ones. Zig
# (and its references) run DEFAULT_ROUNDS; bindings run this many.
BINDING_ROUNDS = 7
DEFAULT_WARMUP = 1
DEFAULT_ITERATIONS = 10
DEFAULT_MIN_RATIO = 0.94
# Per-language bars replacing the global --min-ratio for the named
# languages. Only wasm uses one today.
DEFAULT_MIN_RATIO_OVERRIDES: dict[str, float] = {
    "wasm": 0.68,
}
# Per-language round counts replacing --rounds for the named languages.
# zig is the reference every other language is divided by, so its
# second-best scored round has to be stable; extra runs pin the baseline
# down. wasm has measured noisier than the rest in CI, so it gets extra
# runs too.
DEFAULT_ROUNDS_OVERRIDES: dict[str, int] = {}
INFO_RATIO = 0.97
# Zig reference builds paired against zig round by round: rows exempt
# from the bar, checked with the exact paired tests below instead.
PARENT_NAME = "zig-parent"
REF_NAME = "zig-ref"
REFERENCE_NAMES = (PARENT_NAME, REF_NAME)
# What each reference row builds, for the step-summary footnote.
REFERENCE_SOURCES = {
    PARENT_NAME: "this build's HEAD^ (the PR base on pull_request)",
    REF_NAME: "the performance-reference tag",
}
# One-sided significance level for the paired zig-reference tests. Both
# tests must reject at this level for a row to fail. An exact test at
# level alpha rejects about alpha of perf-neutral rows, and that share
# barely moves with the round count, so the level sets the flake rate:
# simulated over these exact tests, 0.05 gives ~4%/row (~30% per push
# across 9 rows) and 0.01 ~1%/row (~8% per push).
REFERENCE_ALPHA = 0.01
# Bound on scored rounds per reference row: the exact tests enumerate
# 2^n sign assignments, so beyond this count they get exponentially
# slower without adding decision resolution the alpha level can use.
MAX_SCORED_ROUNDS = 20
LANGUAGE_ORDER = (
    "zig",
    "zig-parent",
    "zig-ref",
    "c",
    "cpp",
    "rust",
    "go",
    "python",
    "typescript",
    "deno",
    "bun",
    "wasm",
    "java",
)


@dataclass(frozen=True)
class Runner:
    name: str
    argv: list[str]
    cwd: Path | None = None


@dataclass(frozen=True)
class ReferenceStats:
    """Paired zig-vs-reference results over the scored rounds."""

    pairs: int
    # Non-zero pairs: the count the Wilcoxon signed-rank test works over,
    # since it drops exact ties (the sign-flip test keeps them).
    wilcoxon_pairs: int
    permutation_p: float  # one-sided: zig slower than this reference
    wilcoxon_p: float
    speedup_permutation_p: float
    speedup_wilcoxon_p: float

    @property
    def regression(self) -> bool:
        return (
            self.permutation_p < REFERENCE_ALPHA and self.wilcoxon_p < REFERENCE_ALPHA
        )

    @property
    def speedup(self) -> bool:
        return (
            self.speedup_permutation_p < REFERENCE_ALPHA
            and self.speedup_wilcoxon_p < REFERENCE_ALPHA
        )


@dataclass
class Report:
    rounds: dict[str, list[int]]
    scored: dict[str, list[int]]
    scores: dict[str, int]
    medians: dict[str, float]
    zig_second_best: int
    failures: list[str] = field(default_factory=list)
    info_band_misses: list[str] = field(default_factory=list)
    # Paired-test results per reference row present in the run.
    references: dict[str, ReferenceStats] = field(default_factory=dict)


def parse_bps(stdout: str) -> int:
    for line in stdout.splitlines():
        match = BPS_RE.match(line)
        if match:
            return int(match.group(1).replace(",", ""))
    raise RuntimeError("no bytes_per_second line in benchmark stdout")


def median(values: list[int]) -> float:
    if not values:
        raise ValueError("median of empty sample")
    return float(statistics.median(values))


def second_best(values: list[int]) -> int:
    """Highest scored round after the best one; the only round if there is one."""
    if not values:
        raise ValueError("second-best of empty sample")
    ordered = sorted(values, reverse=True)
    return ordered[1] if len(ordered) > 1 else ordered[0]


def paired_sign_flip_pvalues(differences: list[float]) -> tuple[float, float]:
    """Exact paired permutation (sign-flip) test on the mean difference.

    Returns the (regression, speedup) one-sided p-values: the shares of
    the 2^n sign assignments whose mean is at most / at least the
    observed one, so a small first value means "zig slower than parent"
    and a small second value the opposite.
    """
    count = len(differences)
    if count == 0:
        return 1.0, 1.0
    observed = sum(differences) / count
    below = 0
    above = 0
    total = 1 << count
    for mask in range(total):
        permuted = (
            sum(
                value if mask & (1 << index) else -value
                for index, value in enumerate(differences)
            )
            / count
        )
        if permuted <= observed:
            below += 1
        if permuted >= observed:
            above += 1
    return below / total, above / total


def wilcoxon_signed_rank_pvalues(differences: list[float]) -> tuple[float, float]:
    """Exact Wilcoxon signed-rank test; same (regression, speedup) pair.

    Zero differences drop out, equal magnitudes share average ranks, and
    the exact null enumerates all 2^n sign assignments of the ranks.
    """
    nonzero = [value for value in differences if value != 0]
    count = len(nonzero)
    if count == 0:
        return 1.0, 1.0
    order = sorted(range(count), key=lambda index: abs(nonzero[index]))
    ranks = [0.0] * count
    position = 0
    while position < count:
        end = position
        while end + 1 < count and abs(nonzero[order[end + 1]]) == abs(
            nonzero[order[position]]
        ):
            end += 1
        average = (position + 1 + end + 1) / 2.0
        for offset in range(position, end + 1):
            ranks[order[offset]] = average
        position = end + 1
    observed = sum(rank for rank, value in zip(ranks, nonzero) if value > 0)
    below = 0
    above = 0
    total = 1 << count
    for mask in range(total):
        w_plus = sum(rank for index, rank in enumerate(ranks) if mask & (1 << index))
        if w_plus <= observed:
            below += 1
        if w_plus >= observed:
            above += 1
    return below / total, above / total


def evaluate(
    rounds: dict[str, list[int]],
    *,
    warmup: int,
    min_ratio: float,
    min_ratio_overrides: dict[str, float] | None = None,
    info_ratio: float = INFO_RATIO,
    reference: str = "zig",
) -> Report:
    if reference not in rounds:
        raise ValueError(f"missing reference language {reference!r}")
    overrides = dict(DEFAULT_MIN_RATIO_OVERRIDES)
    if min_ratio_overrides:
        for name in min_ratio_overrides:
            if name not in LANGUAGE_ORDER:
                raise ValueError(f"unknown language in min-ratio override: {name!r}")
        overrides.update(min_ratio_overrides)
    scored = {name: values[warmup:] for name, values in rounds.items()}
    for name, values in scored.items():
        if not values:
            raise ValueError(f"{name}: no scored rounds (warmup={warmup})")
    scores = {name: max(values) for name, values in scored.items()}
    medians = {name: median(values) for name, values in scored.items()}
    zig_second_best = second_best(scored[reference])
    if zig_second_best <= 0:
        raise ValueError(f"{reference} second-best throughput is {zig_second_best}")
    references: dict[str, ReferenceStats] = {}
    for name in REFERENCE_NAMES:
        if name not in scored:
            continue
        if len(scored[name]) != len(scored[reference]):
            raise ValueError(f"{name}: scored round count must mirror {reference!r}")
        if len(scored[name]) > MAX_SCORED_ROUNDS:
            raise ValueError(
                f"{name}: {len(scored[name])} scored rounds exceed the exact "
                f"tests' bound of {MAX_SCORED_ROUNDS} (lower --rounds)"
            )
        differences = [
            current - other for current, other in zip(scored[reference], scored[name])
        ]
        permutation_p, speedup_permutation_p = paired_sign_flip_pvalues(differences)
        wilcoxon_p, speedup_wilcoxon_p = wilcoxon_signed_rank_pvalues(differences)
        references[name] = ReferenceStats(
            pairs=len(differences),
            wilcoxon_pairs=sum(1 for value in differences if value != 0),
            permutation_p=permutation_p,
            wilcoxon_p=wilcoxon_p,
            speedup_permutation_p=speedup_permutation_p,
            speedup_wilcoxon_p=speedup_wilcoxon_p,
        )
    failures: list[str] = []
    info_band_misses: list[str] = []
    for name, score in scores.items():
        if name == reference or name in REFERENCE_NAMES:
            continue
        bar = overrides.get(name, min_ratio)
        ratio = score / zig_second_best
        if ratio < bar:
            failures.append(name)
        if ratio < info_ratio:
            info_band_misses.append(name)
    return Report(
        rounds=rounds,
        scored=scored,
        scores=scores,
        medians=medians,
        zig_second_best=zig_second_best,
        failures=failures,
        info_band_misses=info_band_misses,
        references=references,
    )


def default_runners(root: Path, parser_dir: Path) -> list[Runner]:
    rust_bench = root / "examples" / "rust" / "target" / "release" / "benchmark"
    return [
        Runner(
            "zig", [str(root / "examples" / "zig" / "zig-out" / "bin" / "benchmark")]
        ),
        Runner("c", [os.environ.get("BENCH_C", "/tmp/build-c/bin/benchmark")]),
        Runner("cpp", [os.environ.get("BENCH_CPP", "/tmp/build-cpp/bin/benchmark")]),
        Runner("rust", [os.environ.get("BENCH_RUST", str(rust_bench))]),
        Runner("go", [os.environ.get("BENCH_GO", "/tmp/galley-go-benchmark")]),
        Runner(
            "python",
            [sys.executable, "benchmark.py", str(parser_dir)],
            cwd=root / "examples" / "python",
        ),
        Runner(
            "typescript",
            ["npx", "tsx", "benchmark.ts", str(parser_dir)],
            cwd=root / "examples" / "js",
        ),
        Runner(
            "deno",
            [
                "deno",
                "run",
                "--allow-ffi",
                "--allow-read",
                "--allow-env",
                "benchmark.ts",
                str(parser_dir),
            ],
            cwd=root / "examples" / "js",
        ),
        Runner(
            "bun",
            ["bun", "benchmark.ts", str(parser_dir)],
            cwd=root / "examples" / "js",
        ),
        Runner(
            "wasm",
            ["npx", "tsx", "benchmark.ts", "--wasm", str(parser_dir)],
            cwd=root / "examples" / "js",
        ),
        Runner(
            "java",
            [
                "java",
                "--enable-native-access=ALL-UNNAMED",
                "-cp",
                "bindings/java/out:examples/java/out",
                "com.example.Benchmark",
                str(parser_dir),
            ],
            cwd=root,
        ),
    ]


def run_one(runner: Runner, sample: Path, iterations: int) -> int:
    argv = [*runner.argv, str(sample), str(iterations)]
    result = subprocess.run(
        argv,
        cwd=runner.cwd,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        raise RuntimeError(
            f"{runner.name} exited {result.returncode}: {' '.join(argv)}"
        )
    try:
        return parse_bps(result.stdout)
    except RuntimeError as error:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise RuntimeError(f"{runner.name}: {error}") from error


def format_int(value: int | float) -> str:
    return f"{int(round(value)):,}"


def format_overrides(overrides: dict[str, float]) -> str:
    return ", ".join(f"{name}={ratio:.0%}" for name, ratio in sorted(overrides.items()))


def format_rounds_overrides(overrides: dict[str, int]) -> str:
    return ", ".join(f"{name}={count}" for name, count in sorted(overrides.items()))


def rounds_note(round_counts: dict[str, int], zig_rounds: int) -> str:
    """Describe round counts that differ from the nominal ones, for run lines.

    Yields nothing when every count matches. Bindings run BINDING_ROUNDS
    by default rather than zig's count, so a uniform binding count reads
    as one clause instead of a per-name listing; mixed counts (from
    per-language overrides) are listed per name, and a zig override is
    named separately.
    """
    note = ""
    zig_count = round_counts.get("zig")
    if zig_count is not None and zig_count != zig_rounds:
        note += f"; zig runs {zig_count} rounds"
    bindings = {
        name: count
        for name, count in round_counts.items()
        if name != "zig" and name not in REFERENCE_NAMES
    }
    if not bindings:
        return note
    counts = set(bindings.values())
    if len(counts) == 1:
        count = next(iter(counts))
        if count != zig_count:
            note += f"; bindings run {count} rounds"
    else:
        note += "; round counts: " + format_rounds_overrides(bindings)
    return note


def format_pvalue(p: float) -> str:
    return f"{p:.2f}" if p >= 0.01 else "<0.01"


def format_reference_status(stats: ReferenceStats) -> str:
    if stats.regression:
        return (
            f"🔴 p={format_pvalue(stats.permutation_p)}"
            f"/{format_pvalue(stats.wilcoxon_p)}"
        )
    if stats.speedup:
        return (
            "🟢↑ p="
            f"{format_pvalue(stats.speedup_permutation_p)}"
            f"/{format_pvalue(stats.speedup_wilcoxon_p)}"
        )
    return (
        f"🟢 p={format_pvalue(stats.permutation_p)}/{format_pvalue(stats.wilcoxon_p)}"
    )


def print_report(
    report: Report,
    *,
    min_ratio: float,
    min_ratio_overrides: dict[str, float],
    info_ratio: float,
    rounds: int,
    round_counts: dict[str, int],
    warmup: int,
    label: str | None = None,
) -> None:
    names = [name for name in LANGUAGE_ORDER if name in report.rounds]
    print("round  language       bytes_per_second")
    width = max(len(report.rounds[name]) for name in names)
    for index in range(width):
        for name in names:
            values = report.rounds[name]
            cell = format_int(values[index]) if index < len(values) else "-"
            print(f"{index + 1:>5}  {name:<13} {cell}")
    print()
    print(f"zig median (scored rounds): {format_int(report.medians['zig'])}")
    print(f"zig second-best (scored rounds): {format_int(report.zig_second_best)}")
    bars = f"fail below {min_ratio:.0%} of zig second-best"
    if min_ratio_overrides:
        bars += f" (overrides: {format_overrides(min_ratio_overrides)})"
    bars += f"; {info_ratio:.0%} band is informational"
    print(bars)
    print(
        f"{'language':<13} {'best':>11} {'median':>11}  "
        f"{'vs zig best':>13}  {'vs zig median':>13}"
    )
    for name in names:
        score = report.scores[name]
        median_bytes = report.medians[name]
        prefix = f"{name:<13} {format_int(score):>11} {format_int(median_bytes):>11}  "
        if name == "zig":
            print(prefix + f"{'reference':>13}  {'reference':>13}")
            continue
        note = ""
        if name in report.references:
            note = "  " + format_reference_status(report.references[name])
        elif name in report.failures:
            note = "  FAIL"
        elif name in report.info_band_misses:
            note = f"  outside {1 - info_ratio:.0%} band (info)"
        best_ratio = score / report.scores["zig"]
        median_ratio = score / report.medians["zig"]
        print(prefix + f"{best_ratio:>13.1%}  {median_ratio:>13.1%}{note}")

    for name in REFERENCE_NAMES:
        stats = report.references.get(name)
        if stats is None:
            continue
        print()
        print(f"zig vs {name}, paired over {stats.pairs} scored rounds:")
        for index, (current, other) in enumerate(
            zip(report.scored["zig"], report.scored[name])
        ):
            print(
                f"  round {index + warmup + 1}: "
                f"zig {format_int(current)}, {name} {format_int(other)}"
            )
        print(
            f"  permutation p: slower {stats.permutation_p:.4f}, "
            f"faster {stats.speedup_permutation_p:.4f}"
        )
        tie_note = ""
        if stats.wilcoxon_pairs != stats.pairs:
            # The signed-rank test drops exact ties, the sign-flip test does not.
            tie_note = f" (over {stats.wilcoxon_pairs} non-tie pairs)"
        print(
            f"  Wilcoxon p: slower {stats.wilcoxon_p:.4f}, "
            f"faster {stats.speedup_wilcoxon_p:.4f}{tie_note}"
        )

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        failed = bool(report.failures) or any(
            stats.regression for stats in report.references.values()
        )
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(
                f"### {'🔴' if failed else '🟢'}"
                " Example benchmark throughput vs examples/zig"
            )
            if label:
                handle.write(f" ({label})")
            handle.write("\n\n")
            handle.write(
                "| language | best bytes/s | median bytes/s "
                "| vs zig best | vs zig median | status |\n"
            )
            handle.write("| --- | ---: | ---: | ---: | ---: | --- |\n")
            for name in names:
                score = report.scores[name]
                median_bytes = report.medians[name]
                best_ratio = score / report.scores["zig"]
                median_ratio = score / report.medians["zig"]
                if name == "zig":
                    status = "—"
                elif name in report.references:
                    status = format_reference_status(report.references[name])
                elif name in report.failures:
                    status = "🟡 **below bar**"
                elif name in report.info_band_misses:
                    status = "🟡 outside band"
                else:
                    status = "🟢"
                handle.write(
                    f"| {name} | {format_int(score)} "
                    f"| {format_int(median_bytes)} "
                    f"| {best_ratio:.1%} "
                    f"| {median_ratio:.1%} "
                    f"| {status} |\n"
                )
            if warmup == 0:
                warmup_text = "no warmup"
            elif warmup == 1:
                warmup_text = "round 1 is warmup"
            else:
                warmup_text = f"first {warmup} rounds are warmup"
            rounds_text = f"{rounds} interleaved rounds"
            handle.write(
                f"\n{rounds_text} including zig{rounds_note(round_counts, rounds)}; "
                f"{warmup_text}; "
                f"score and median are over the remaining rounds, and the "
                f"vs-zig columns divide by zig's best and median of those "
                f"rounds. Fail below {min_ratio:.0%} of zig's second-best "
                f"scored round ({format_int(report.zig_second_best)} bytes/s)"
            )
            if min_ratio_overrides:
                handle.write(f" (overrides: {format_overrides(min_ratio_overrides)})")
            handle.write(f". {info_ratio:.0%} band is informational.\n")
            present = [name for name in REFERENCE_NAMES if name in report.references]
            if present:
                sources = ", ".join(
                    f"{name} ({REFERENCE_SOURCES[name]})" for name in present
                )
                handle.write(
                    f"\n{sources} build examples/zig on the same inputs, "
                    "interleaved in every round. Each reference row divides "
                    "by zig's best and median like every row, but its status "
                    "comes from exact one-sided paired permutation and "
                    "Wilcoxon signed-rank tests over the "
                    f"{report.references[present[0]].pairs} scored rounds: "
                    "it fails only when both judge zig significantly slower "
                    f"(p < {REFERENCE_ALPHA:g}); significant speedups show "
                    "an up arrow and never fail.\n"
                )


def self_test_report_table(report: Report) -> None:
    with tempfile.TemporaryDirectory() as directory:
        summary = Path(directory) / "summary.md"
        previous = os.environ.get("GITHUB_STEP_SUMMARY")
        os.environ["GITHUB_STEP_SUMMARY"] = str(summary)
        try:
            with contextlib.redirect_stdout(io.StringIO()) as console:
                print_report(
                    report,
                    min_ratio=DEFAULT_MIN_RATIO,
                    min_ratio_overrides=dict(DEFAULT_MIN_RATIO_OVERRIDES),
                    info_ratio=INFO_RATIO,
                    rounds=3,
                    round_counts={
                        "zig": 5,
                        "zig-parent": 3,
                        "zig-ref": 3,
                        "c": 3,
                        "rust": 3,
                        "python": 3,
                    },
                    warmup=1,
                    label="self-test",
                )
        finally:
            if previous is None:
                os.environ.pop("GITHUB_STEP_SUMMARY", None)
            else:
                os.environ["GITHUB_STEP_SUMMARY"] = previous
        table = summary.read_text(encoding="utf-8")
        output = console.getvalue()
    assert (
        "| language | best bytes/s | median bytes/s | vs zig best "
        "| vs zig median | status |" in table
    )
    assert "| zig | 200 | 190 | 100.0% | 105.3% | — |" in table
    assert "| zig-parent | 190 | 190 | 95.0% | 100.0% | 🟢 p=0.75/0.75 |" in table
    assert "| zig-ref | 195 | 190 | 97.5% | 102.6% | 🟢 p=0.75/0.75 |" in table
    assert "| c | 190 | 188 | 95.0% | 100.0% | 🟢 |" in table
    assert "| rust | 174 | 172 | 87.0% | 91.6% | 🟡 outside band |" in table
    assert "| python | 30 | 25 | 15.0% | 15.8% | 🟡 **below bar** |" in table
    assert "zig's second-best scored round (180 bytes/s)" in table
    assert "### 🔴 Example benchmark throughput vs examples/zig (self-test)" in table
    assert "zig-parent (this build's HEAD^ (the PR base on pull_request))" in table
    assert "zig-ref (the performance-reference tag)" in table
    assert "fails only when both judge zig significantly slower" in table
    assert "vs zig best" in output
    assert "vs zig median" in output
    assert "FAIL" in output
    assert "outside 3% band (info)" in output
    assert "zig vs zig-parent, paired over 2 scored rounds" in output
    assert "round 2: zig 200, zig-parent 190" in output
    assert "zig vs zig-ref, paired over 2 scored rounds" in output
    assert "round 2: zig 200, zig-ref 195" in output


def self_test() -> None:
    assert parse_bps("bytes_per_second: 1,234,567\n") == 1_234_567
    assert second_best([180]) == 180
    rounds = {
        "zig": [100, 200, 180],
        "zig-parent": [150, 190, 190],
        "zig-ref": [150, 195, 185],
        "c": [90, 190, 185],
        "rust": [80, 174, 170],
        "python": [10, 20, 30],
    }
    report = evaluate(
        rounds,
        warmup=1,
        min_ratio=DEFAULT_MIN_RATIO,
        info_ratio=INFO_RATIO,
    )
    assert report.scores["zig"] == 200
    assert report.medians["zig"] == 190
    assert report.zig_second_best == 180
    assert report.scores["c"] == 190
    assert report.medians["c"] == 187.5
    # Paired zig-reference tests: exact known answers, both directions.
    assert paired_sign_flip_pvalues([-1.0] * 7) == (1 / 128, 1.0)
    assert paired_sign_flip_pvalues([1.0] * 7) == (1.0, 1 / 128)
    assert paired_sign_flip_pvalues([10.0, -10.0]) == (0.75, 0.75)
    assert wilcoxon_signed_rank_pvalues([-1.0] * 7) == (1 / 128, 1.0)
    assert wilcoxon_signed_rank_pvalues([1.0] * 7) == (1.0, 1 / 128)
    assert wilcoxon_signed_rank_pvalues([10.0, -10.0]) == (0.75, 0.75)
    assert wilcoxon_signed_rank_pvalues([0.0, 0.0]) == (1.0, 1.0)
    # Magnitudes not already in difference order: ranks must follow each
    # difference, not the sorted magnitudes.
    assert wilcoxon_signed_rank_pvalues([-3.0, 1.0, 5.0, -5.0, -4.0]) == (
        11 / 32,
        23 / 32,
    )
    # The scored pairs here are zig [200, 180] vs parent [190, 190] and
    # ref [195, 185]: mixed differences, no verdict either way for either
    # reference, and both stay out of the bar logic.
    assert report.references.keys() == {"zig-parent", "zig-ref"}
    assert report.references[PARENT_NAME].pairs == 2
    assert report.references[PARENT_NAME].permutation_p == 0.75
    assert not report.references[PARENT_NAME].regression
    assert not report.references[PARENT_NAME].speedup
    assert report.references[REF_NAME].permutation_p == 0.75
    assert not report.references[REF_NAME].regression
    assert not report.references[REF_NAME].speedup
    for name in REFERENCE_NAMES:
        assert name not in report.failures
        assert name not in report.info_band_misses
    # All-negative pairs fail as a regression; all-positive as a speedup.
    slower = evaluate(
        {"zig": [100] + [90] * 7, "zig-parent": [100] + [100] * 7},
        warmup=1,
        min_ratio=DEFAULT_MIN_RATIO,
    )
    assert slower.references[PARENT_NAME].regression
    assert not slower.references[PARENT_NAME].speedup
    faster = evaluate(
        {"zig": [100] + [110] * 7, REF_NAME: [100] + [100] * 7},
        warmup=1,
        min_ratio=DEFAULT_MIN_RATIO,
    )
    assert faster.references[REF_NAME].speedup
    assert not faster.references[REF_NAME].regression
    assert PARENT_NAME not in faster.references
    assert "c" not in report.failures
    assert "c" not in report.info_band_misses
    # rust's 174 clears the 94% bar against zig's second-best (174/180) but
    # misses the 97% info band; against zig's median (174/190) it would fail.
    assert "rust" not in report.failures
    assert "rust" in report.info_band_misses
    assert "python" in report.failures
    assert "python" in report.info_band_misses
    overridden = evaluate(
        rounds,
        warmup=1,
        min_ratio=DEFAULT_MIN_RATIO,
        min_ratio_overrides={"python": 0.10},
    )
    assert "python" not in overridden.failures
    assert "python" in overridden.info_band_misses
    self_test_report_table(report)
    assert parse_rounds_override("zig=6") == ("zig", 6)
    for bad in (
        "zig",
        "=6",
        "cobol=6",
        "zig=six",
        "zig=0",
        "zig=-2",
        "zig-parent=6",
        "zig-ref=6",
    ):
        try:
            parse_rounds_override(bad)
        except ValueError:
            pass
        else:
            raise AssertionError(f"parse_rounds_override accepted {bad!r}")
    assert parse_override("wasm=0.60") == ("wasm", 0.60)
    for bad in ("zig", "=0.9", "cobol=0.9", "zig-parent=0.9", "zig-ref=0.9"):
        try:
            parse_override(bad)
        except ValueError:
            pass
        else:
            raise AssertionError(f"parse_override accepted {bad!r}")
    # Exact ties pair but drop out of the signed-rank count.
    tied = evaluate(
        {"zig": [100, 100], "zig-parent": [100, 100]},
        warmup=1,
        min_ratio=DEFAULT_MIN_RATIO,
    )
    assert tied.references[PARENT_NAME].pairs == 1
    assert tied.references[PARENT_NAME].wilcoxon_pairs == 0
    # Scored rounds beyond the exact tests' enumeration bound are rejected.
    try:
        evaluate(
            {"zig": [100] * 22, "zig-parent": [90] * 22},
            warmup=1,
            min_ratio=DEFAULT_MIN_RATIO,
        )
    except ValueError as error:
        assert "bound" in str(error)
    else:
        raise AssertionError("scored-round bound did not fire")
    print("self-test ok")


def parse_override(text: str) -> tuple[str, float]:
    name, separator, value = text.partition("=")
    if not separator or not name:
        raise ValueError(f"override must be LANG=RATIO, got {text!r}")
    if name in REFERENCE_NAMES:
        raise ValueError(
            f"{name} is exempt from the bar; a min-ratio override has no "
            f"effect on it (reference rows fail only on paired tests)"
        )
    if name not in LANGUAGE_ORDER:
        raise ValueError(f"unknown language in min-ratio override: {name!r}")
    try:
        ratio = float(value)
    except ValueError:
        raise ValueError(f"invalid ratio in min-ratio override: {text!r}") from None
    if not 0 < ratio <= 1:
        raise ValueError(f"ratio must be in (0, 1], got {text!r}")
    return name, ratio


def parse_rounds_override(text: str) -> tuple[str, int]:
    name, separator, value = text.partition("=")
    if not separator or not name:
        raise ValueError(f"override must be LANG=COUNT, got {text!r}")
    if name in REFERENCE_NAMES:
        raise ValueError(
            f"{name} runs exactly zig's rounds so every scored round pairs; "
            f"a rounds override would break the pairing"
        )
    if name not in LANGUAGE_ORDER:
        raise ValueError(f"unknown language in rounds override: {name!r}")
    try:
        count = int(value)
    except ValueError:
        raise ValueError(f"invalid count in rounds override: {text!r}") from None
    if count < 1:
        raise ValueError(f"count must be >= 1, got {text!r}")
    return name, count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--root", type=Path, default=None)
    parser.add_argument("--sample", type=Path, default=None)
    parser.add_argument(
        "--parser-dir",
        type=Path,
        default=None,
        help=(
            "built parser package the python, js, and java benchmarks load "
            "(default: languages/json)"
        ),
    )
    parser.add_argument("--label", type=str, default=None)
    parser.add_argument(
        "--rounds",
        type=int,
        default=DEFAULT_ROUNDS,
        help=(
            "zig's total rounds, mirrored by its reference rows; bindings "
            f"run {BINDING_ROUNDS} instead (default: {DEFAULT_ROUNDS})"
        ),
    )
    parser.add_argument("--warmup", type=int, default=DEFAULT_WARMUP)
    parser.add_argument("--iterations", type=int, default=DEFAULT_ITERATIONS)
    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        help=(
            "seed for the randomly shuffled run order within each round "
            "(default: random; the seed in use is printed at start)"
        ),
    )
    parser.add_argument(
        "--zig-parent-binary",
        type=Path,
        default=None,
        help=(
            "benchmark binary built from the parent commit's examples/zig; "
            "adds a zig-parent row interleaved in every round and paired "
            "against zig (default: no parent comparison)"
        ),
    )
    parser.add_argument(
        "--zig-ref-binary",
        type=Path,
        default=None,
        help=(
            "benchmark binary built from the performance-reference tag's "
            "examples/zig; adds a zig-ref row interleaved in every round "
            "and paired against zig (default: no tag comparison)"
        ),
    )
    parser.add_argument("--min-ratio", type=float, default=DEFAULT_MIN_RATIO)
    parser.add_argument(
        "--rounds-override",
        action="append",
        default=[],
        metavar="LANG=COUNT",
        help=(
            "per-language total round count replacing that language's "
            "default (zig: --rounds; bindings: the binding count), e.g. "
            "zig=6 (repeatable; built-in: "
            + format_rounds_overrides(DEFAULT_ROUNDS_OVERRIDES)
            + ")"
        ),
    )
    parser.add_argument(
        "--min-ratio-override",
        action="append",
        default=[],
        metavar="LANG=RATIO",
        help=(
            "per-language bar replacing --min-ratio, e.g. wasm=0.80 "
            "(repeatable; built-in: "
            + format_overrides(DEFAULT_MIN_RATIO_OVERRIDES).replace("%", "%%")
            + ")"
        ),
    )
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if args.rounds < 1:
        print("rounds must be >= 1", file=sys.stderr)
        return 1
    try:
        cli_rounds = dict(parse_rounds_override(text) for text in args.rounds_override)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    round_counts = dict(DEFAULT_ROUNDS_OVERRIDES)
    round_counts.update(cli_rounds)
    for name in LANGUAGE_ORDER:
        # Zig runs --rounds (its references are pinned to zig below);
        # bindings run the smaller binding count unless overridden.
        round_counts.setdefault(name, args.rounds if name == "zig" else BINDING_ROUNDS)
    if args.warmup < 0 or args.warmup >= min(round_counts.values()):
        print(
            "warmup must be >= 0 and below every language round count", file=sys.stderr
        )
        return 1
    if args.iterations < 1:
        print("iterations must be >= 1", file=sys.stderr)
        return 1

    root = (args.root or Path(__file__).resolve().parent.parent).resolve()
    sample = (
        args.sample or root / "languages" / "json" / "samples" / "code-02.json"
    ).resolve()
    if not sample.is_file():
        print(f"missing sample {sample}", file=sys.stderr)
        print(
            "fetch it with: bash scripts/fetch-large-samples.sh json", file=sys.stderr
        )
        return 1
    parser_dir = (root / (args.parser_dir or Path("languages/json"))).resolve()

    runner_list = default_runners(root, parser_dir)
    reference_binaries = {
        PARENT_NAME: args.zig_parent_binary,
        REF_NAME: args.zig_ref_binary,
    }
    for name, binary in reference_binaries.items():
        if binary is not None:
            runner_list.append(Runner(name, [str(binary.resolve())]))
    runners = {runner.name: runner for runner in runner_list}
    for name in REFERENCE_NAMES:
        if name not in runners:
            round_counts.pop(name, None)
        else:
            # References run exactly zig's rounds, so every scored round pairs.
            round_counts[name] = round_counts["zig"]
    try:
        cli_overrides = dict(parse_override(text) for text in args.min_ratio_override)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    overrides = {**DEFAULT_MIN_RATIO_OVERRIDES, **cli_overrides}
    missing = []
    for name in LANGUAGE_ORDER:
        if name not in runners:
            if name in REFERENCE_NAMES:
                # Reference rows are optional, added only by their flags.
                continue
            raise AssertionError(f"no runner built for required language {name!r}")
        runner = runners[name]
        if name == "python":
            script = (runner.cwd or root) / "benchmark.py"
            if not script.is_file():
                missing.append(f"{name}: {script}")
            elif not (parser_dir / "__init__.py").is_file():
                missing.append(f"{name}: {parser_dir}/__init__.py")
            continue
        if name in ("typescript", "deno", "bun"):
            script = (runner.cwd or root) / "benchmark.ts"
            if not script.is_file():
                missing.append(f"{name}: {script}")
            elif not (parser_dir / "index.mjs").is_file():
                missing.append(f"{name}: {parser_dir}/index.mjs")
            continue
        if name == "wasm":
            script = (runner.cwd or root) / "benchmark.ts"
            if not script.is_file():
                missing.append(f"{name}: {script}")
            elif not (parser_dir / "libgalley-js-wasm.wasm").is_file():
                missing.append(f"{name}: {parser_dir}/libgalley-js-wasm.wasm")
            continue
        if name == "java":
            if not (
                root
                / "bindings"
                / "java"
                / "out"
                / "org"
                / "sanbus"
                / "galley"
                / "build"
                / "GalleyBuild.class"
            ).is_file():
                missing.append(f"{name}: bindings/java/out")
            elif not (
                root
                / "examples"
                / "java"
                / "out"
                / "com"
                / "example"
                / "Benchmark.class"
            ).is_file():
                missing.append(f"{name}: examples/java/out")
            elif (
                not (parser_dir / "libgalley-java.so").is_file()
                and not (parser_dir / "libgalley-java.dylib").is_file()
            ):
                missing.append(f"{name}: {parser_dir}/libgalley-java.*")
            continue
        program = Path(runner.argv[0])
        if not program.is_file():
            missing.append(f"{name}: {program}")
    if missing:
        print("missing benchmark binaries:\n  " + "\n  ".join(missing), file=sys.stderr)
        return 1

    start = f"interleaved {args.rounds} rounds"
    if args.label:
        start += f" [{args.label}]"
    start += rounds_note(round_counts, args.rounds)
    paired = [name for name in REFERENCE_NAMES if name in round_counts]
    if paired:
        start += f"; references paired against zig: {', '.join(paired)}"
    print(
        f"{start} (warmup {args.warmup}), {args.iterations} iterations, sample {sample}"
    )
    seed = args.seed if args.seed is not None else random.randrange(1 << 32)
    print(f"order seed: {seed} (replay with --seed {seed})")
    rng = random.Random(seed)
    rounds: dict[str, list[int]] = {
        name: [] for name in LANGUAGE_ORDER if name in runners
    }
    for round_index in range(max(round_counts.values())):
        # Fresh shuffled order every round, so no language keeps the same
        # position (heat, cache, and neighbor effects) across rounds.
        order = [
            name
            for name in LANGUAGE_ORDER
            if name in runners and round_index < round_counts[name]
        ]
        rng.shuffle(order)
        for name in order:
            bps = run_one(runners[name], sample, args.iterations)
            rounds[name].append(bps)
            print(
                f"round {round_index + 1} {name}: {format_int(bps)} bytes/s", flush=True
            )

    report = evaluate(
        rounds,
        warmup=args.warmup,
        min_ratio=args.min_ratio,
        min_ratio_overrides=overrides,
        info_ratio=INFO_RATIO,
    )
    print()
    print_report(
        report,
        min_ratio=args.min_ratio,
        min_ratio_overrides=overrides,
        info_ratio=INFO_RATIO,
        rounds=args.rounds,
        round_counts=round_counts,
        warmup=args.warmup,
        label=args.label,
    )
    if report.info_band_misses:
        print(
            f"info: outside {1 - INFO_RATIO:.0%} of zig second-best: "
            + ", ".join(report.info_band_misses),
            flush=True,
        )
    errors: list[str] = []
    if report.failures:
        parts = [
            f"{name} below {overrides.get(name, args.min_ratio):.0%}"
            for name in report.failures
        ]
        errors.append(
            f"benchmark: {', '.join(parts)} of zig second-best "
            f"({format_int(report.zig_second_best)} bytes/s)"
        )
    regressed = [name for name, stats in report.references.items() if stats.regression]
    if regressed:
        parts = []
        for name in regressed:
            stats = report.references[name]
            parts.append(
                f"{name} (permutation p={stats.permutation_p:.4f}, "
                f"Wilcoxon p={stats.wilcoxon_p:.4f})"
            )
        errors.append(f"benchmark: zig significantly slower than {', '.join(parts)}")
    for message in errors:
        # Report every failing gate, not just the first one that fires.
        print(f"::error::{message}")
        print(message, file=sys.stderr)
    if errors:
        return 1
    print(
        f"all C-ABI examples are >= {args.min_ratio:.0%} of zig second-best "
        f"({format_int(report.zig_second_best)} bytes/s)"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"::error::benchmark: {error}")
        print(error, file=sys.stderr)
        sys.exit(1)
