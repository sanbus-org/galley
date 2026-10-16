#!/usr/bin/env python3
"""Same-machine benchmark comparison vs examples/zig.

Build the benchmark binaries first (see .github/workflows/ci.yml), and
pass --parser-dir at the built parser package for the hosts that load one
(python, js, java). This script runs them interleaved, shuffling the
language order randomly within each round (--seed pins the order; the
seed in use is printed at start), and scores the best of the non-warmup
rounds.

Bindings run the parser zig runs, so their rows measure what each binding
adds around a parse: the input handoff, the call and the result. A
binding fails below --min-ratio of zig's second-best scored round; that
only catches large losses, such as a copy of the input on every parse,
since placement alone moves identical code by a few percent.
Per-language bars (--min-ratio-override) replace the global bar for the
named languages; currently only the WebAssembly example uses one, since it
runs the same parser compiled to wasm, which trails native codegen. The
informational band has the same per-language overrides
(INFO_RATIO_OVERRIDES). --no-bindings runs zig and its references only.

When --zig-parent-binary or --zig-ref-binary names an examples/zig build
from the parent commit or from the performance-reference tag, that binary
runs interleaved in every round. On pull_request the checkout is the
merge commit, so zig-parent compares against the PR base rather than the
commit's own parent. Zig fails against a reference in two ways:
- instructions: given counting builds (--zig-count-binary and the
  references' --*-count-binary), each runs once under callgrind, and zig
  fails when it runs more than INSTRUCTION_TOLERANCE more instructions
  than the reference. Counts repeat exactly from run to run, so this
  catches small regressions timing cannot tell from noise. Counting
  builds target one CPU (x86-64-v3), so every machine runs the same code.
- time: zig fails when the median of its per-round throughput ratios to
  the reference is below REFERENCE_MIN_RATIO; that only catches large
  effects instruction counts cannot see, such as layout, caches or SIMD.
The step-summary table's status column marks failures red and misses
inside the informational band yellow.
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
# Every runner's total rounds; 1 warmup leaves 6 scored ones. The warmup
# only has to put the sample in page cache and the CPU at frequency, so
# one round covers it.
DEFAULT_ROUNDS = 7
DEFAULT_WARMUP = 1
DEFAULT_ITERATIONS = 10
DEFAULT_MIN_RATIO = 0.90
# Per-language bars replacing the global --min-ratio for the named
# languages. Only wasm uses one today.
DEFAULT_MIN_RATIO_OVERRIDES: dict[str, float] = {
    "wasm": 0.68,
}
# Per-language round counts replacing --rounds for the named languages.
DEFAULT_ROUNDS_OVERRIDES: dict[str, int] = {}
INFO_RATIO = 0.97
# Per-language info bands replacing INFO_RATIO for the named languages.
# Only wasm uses one today.
INFO_RATIO_OVERRIDES: dict[str, float] = {
    "wasm": 0.70,
}
# Zig reference builds compared with zig: rows exempt from the bar, checked
# against zig's instructions and time instead.
PARENT_NAME = "zig-parent"
REF_NAME = "zig-ref"
REFERENCE_NAMES = (PARENT_NAME, REF_NAME)
# What each reference row builds, for the step-summary footnote.
REFERENCE_SOURCES = {
    PARENT_NAME: "this build's HEAD^ (the PR base on pull_request)",
    REF_NAME: "the performance-reference tag",
}
# Zig fails when its median per-round throughput ratio to a reference is
# below this.
REFERENCE_MIN_RATIO = 0.90
# Zig fails when it runs more than this share more instructions than a
# reference.
INSTRUCTION_TOLERANCE = 0.005
# Parses in one counted run: the benchmark's 2 warmups and 1 timed parse.
COUNTED_PARSES = 3
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
BINDING_NAMES = tuple(
    name for name in LANGUAGE_ORDER if name != "zig" and name not in REFERENCE_NAMES
)


@dataclass(frozen=True)
class Runner:
    name: str
    argv: list[str]
    cwd: Path | None = None


@dataclass(frozen=True)
class ReferenceStats:
    """Zig against one reference build."""

    pairs: int
    # Median over the scored rounds of zig's throughput / the reference's.
    time_ratio: float
    # Zig's instruction count / the reference's; None without counts.
    instruction_ratio: float | None

    @property
    def slower(self) -> bool:
        return self.time_ratio < REFERENCE_MIN_RATIO

    @property
    def more_instructions(self) -> bool:
        return (
            self.instruction_ratio is not None
            and self.instruction_ratio > 1 + INSTRUCTION_TOLERANCE
        )

    @property
    def regression(self) -> bool:
        return self.slower or self.more_instructions


@dataclass
class Report:
    rounds: dict[str, list[int]]
    scored: dict[str, list[int]]
    scores: dict[str, int]
    medians: dict[str, float]
    zig_second_best: int
    failures: list[str] = field(default_factory=list)
    info_band_misses: list[str] = field(default_factory=list)
    # The informational band each scored binding was held to.
    info_bands: dict[str, float] = field(default_factory=dict)
    # Results per reference row present in the run.
    references: dict[str, ReferenceStats] = field(default_factory=dict)
    # Instruction counts of zig and its references, when counted, and the
    # bytes each counted run parsed.
    instructions: dict[str, int] = field(default_factory=dict)
    counted_bytes: int = 0


def parse_bps(stdout: str) -> int:
    for line in stdout.splitlines():
        match = BPS_RE.match(line)
        if match:
            return int(match.group(1).replace(",", ""))
    raise RuntimeError("no bytes_per_second line in benchmark stdout")


def parse_instruction_count(profile: str) -> int:
    """The total instruction count in a callgrind output file."""
    for line in profile.splitlines():
        if line.startswith("summary:"):
            return int(line.split()[1])
    raise RuntimeError("no summary line in callgrind output")


def count_instructions(binary: Path, sample: Path) -> int:
    """Instructions one parse of `sample` runs, warmups included, under callgrind."""
    with tempfile.TemporaryDirectory() as directory:
        profile = Path(directory) / "callgrind.out"
        argv = [
            "valgrind",
            "--tool=callgrind",
            f"--callgrind-out-file={profile}",
            str(binary),
            str(sample),
            "1",
        ]
        result = subprocess.run(
            argv,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if result.returncode != 0:
            sys.stderr.write(result.stderr)
            raise RuntimeError(
                f"callgrind exited {result.returncode}: {' '.join(argv)}"
            )
        return parse_instruction_count(profile.read_text(encoding="utf-8"))


def median(values: list[int] | list[float]) -> float:
    if not values:
        raise ValueError("median of empty sample")
    return float(statistics.median(values))


def second_best(values: list[int]) -> int:
    """Highest scored round after the best one; the only round if there is one."""
    if not values:
        raise ValueError("second-best of empty sample")
    ordered = sorted(values, reverse=True)
    return ordered[1] if len(ordered) > 1 else ordered[0]


def evaluate(
    rounds: dict[str, list[int]],
    *,
    warmup: int,
    min_ratio: float,
    min_ratio_overrides: dict[str, float] | None = None,
    info_ratio: float = INFO_RATIO,
    info_ratio_overrides: dict[str, float] | None = None,
    instructions: dict[str, int] | None = None,
    counted_bytes: int = 0,
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
    info_overrides = dict(INFO_RATIO_OVERRIDES)
    if info_ratio_overrides:
        for name in info_ratio_overrides:
            if name not in LANGUAGE_ORDER:
                raise ValueError(f"unknown language in info-ratio override: {name!r}")
        info_overrides.update(info_ratio_overrides)
    instructions = dict(instructions or {})
    if any(name in instructions for name in REFERENCE_NAMES) and (
        reference not in instructions
    ):
        raise ValueError(f"reference instruction counts need {reference!r}'s count")
    if instructions and counted_bytes <= 0:
        raise ValueError("instruction counts need the bytes the counted runs parsed")
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
        ratios = [
            current / other for current, other in zip(scored[reference], scored[name])
        ]
        references[name] = ReferenceStats(
            pairs=len(ratios),
            time_ratio=median(ratios),
            instruction_ratio=(
                instructions[reference] / instructions[name]
                if name in instructions
                else None
            ),
        )
    failures: list[str] = []
    info_band_misses: list[str] = []
    info_bands: dict[str, float] = {}
    for name, score in scores.items():
        if name == reference or name in REFERENCE_NAMES:
            continue
        bar = overrides.get(name, min_ratio)
        info_bands[name] = info_overrides.get(name, info_ratio)
        ratio = score / zig_second_best
        if ratio < bar:
            failures.append(name)
        if ratio < info_bands[name]:
            info_band_misses.append(name)
    return Report(
        rounds=rounds,
        scored=scored,
        scores=scores,
        medians=medians,
        zig_second_best=zig_second_best,
        failures=failures,
        info_band_misses=info_band_misses,
        info_bands=info_bands,
        references=references,
        instructions=instructions,
        counted_bytes=counted_bytes,
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
    """Name the runners whose round count differs from zig's, for run lines.

    Yields nothing when every count matches.
    """
    differing = {
        name: count
        for name, count in round_counts.items()
        if name not in REFERENCE_NAMES and count != zig_rounds
    }
    if not differing:
        return ""
    return "; round counts: " + format_rounds_overrides(differing)


def format_instructions_per_byte(report: Report, name: str) -> str:
    count = report.instructions.get(name)
    return f"{count / report.counted_bytes:.3f}" if count is not None else "—"


def format_reference_status(stats: ReferenceStats) -> str:
    time = f"time {stats.time_ratio:.1%}"
    if stats.slower:
        time = f"**{time}**"
    parts = [time]
    if stats.instruction_ratio is not None:
        instructions = f"instructions {stats.instruction_ratio - 1:+.2%}"
        if stats.more_instructions:
            instructions = f"**{instructions}**"
        parts.append(instructions)
    return ("🔴 " if stats.regression else "🟢 ") + ", ".join(parts)


def reference_failure(name: str, stats: ReferenceStats) -> str:
    reasons = []
    if stats.more_instructions:
        reasons.append(
            f"{stats.instruction_ratio - 1:+.2%} instructions, above "
            f"{INSTRUCTION_TOLERANCE:+.1%}"
        )
    if stats.slower:
        reasons.append(
            f"median time ratio {stats.time_ratio:.1%}, below {REFERENCE_MIN_RATIO:.0%}"
        )
    return f"{name} ({'; '.join(reasons)})"


def print_report(
    report: Report,
    *,
    min_ratio: float,
    min_ratio_overrides: dict[str, float],
    info_ratio: float,
    info_ratio_overrides: dict[str, float],
    rounds: int,
    round_counts: dict[str, int],
    warmup: int,
    label: str | None = None,
) -> None:
    names = [name for name in LANGUAGE_ORDER if name in report.rounds]
    bindings = [name for name in names if name in BINDING_NAMES]
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
    bars = ""
    if bindings:
        bars = f"bindings fail below {min_ratio:.0%} of zig second-best"
        if min_ratio_overrides:
            bars += f" (overrides: {format_overrides(min_ratio_overrides)})"
        bars += f"; {info_ratio:.0%} band is informational"
        if info_ratio_overrides:
            bars += f" (overrides: {format_overrides(info_ratio_overrides)})"
        print(bars)
    print(
        f"{'language':<13} {'best':>11} {'median':>11}  "
        f"{'vs zig best':>13}  {'vs zig median':>13}  {'instr/byte':>10}"
    )
    for name in names:
        score = report.scores[name]
        median_bytes = report.medians[name]
        prefix = f"{name:<13} {format_int(score):>11} {format_int(median_bytes):>11}  "
        count = f"  {format_instructions_per_byte(report, name):>10}"
        if name == "zig":
            print(prefix + f"{'reference':>13}  {'reference':>13}" + count)
            continue
        note = ""
        if name in report.references:
            note = "  " + format_reference_status(report.references[name]).replace(
                "**", ""
            )
        elif name in report.failures:
            note = "  FAIL"
        elif name in report.info_band_misses:
            note = f"  outside {1 - report.info_bands[name]:.0%} band (info)"
        best_ratio = score / report.scores["zig"]
        median_ratio = score / report.medians["zig"]
        print(prefix + f"{best_ratio:>13.1%}  {median_ratio:>13.1%}" + count + note)

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
        print(f"  median time ratio: {stats.time_ratio:.2%}")
        if stats.instruction_ratio is not None:
            print(
                f"  instructions: zig {format_int(report.instructions['zig'])}, "
                f"{name} {format_int(report.instructions[name])} "
                f"({stats.instruction_ratio - 1:+.3%})"
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
                "| vs zig best | vs zig median | instructions/byte | status |\n"
            )
            handle.write("| --- | ---: | ---: | ---: | ---: | ---: | --- |\n")
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
                    status = "🔴 **below bar**"
                elif name in report.info_band_misses:
                    status = "🟡 outside band"
                else:
                    status = "🟢"
                handle.write(
                    f"| {name} | {format_int(score)} "
                    f"| {format_int(median_bytes)} "
                    f"| {best_ratio:.1%} "
                    f"| {median_ratio:.1%} "
                    f"| {format_instructions_per_byte(report, name)} "
                    f"| {status} |\n"
                )
            if warmup == 0:
                warmup_text = "no warmup"
            elif warmup == 1:
                warmup_text = "round 1 is warmup"
            else:
                warmup_text = f"first {warmup} rounds are warmup"
            handle.write(
                f"\n{rounds} interleaved rounds{rounds_note(round_counts, rounds)}; "
                f"{warmup_text}; score and median are over the remaining "
                "rounds, and the vs-zig columns divide by zig's best and "
                "median of those rounds."
            )
            if bindings:
                handle.write(
                    f" Bindings fail below {min_ratio:.0%} of zig's second-best "
                    f"scored round ({format_int(report.zig_second_best)} bytes/s)"
                )
                if min_ratio_overrides:
                    handle.write(
                        f" (overrides: {format_overrides(min_ratio_overrides)})"
                    )
                handle.write(f"; {info_ratio:.0%} band is informational")
                if info_ratio_overrides:
                    handle.write(
                        f" (overrides: {format_overrides(info_ratio_overrides)})"
                    )
                handle.write(".")
            handle.write("\n")
            if report.instructions:
                handle.write(
                    "\nInstructions per byte come from one run of each "
                    "counting build under callgrind, built for x86-64-v3: "
                    f"{COUNTED_PARSES} parses of the sample (2 warmups and 1 "
                    f"timed), {format_int(report.counted_bytes)} bytes.\n"
                )
            present = [name for name in REFERENCE_NAMES if name in report.references]
            if present:
                sources = ", ".join(
                    f"{name} ({REFERENCE_SOURCES[name]})" for name in present
                )
                handle.write(
                    f"\n{sources} build examples/zig on the same inputs, "
                    "interleaved in every round. Zig fails against a "
                    "reference when it runs more than "
                    f"{INSTRUCTION_TOLERANCE:.1%} more instructions, or when "
                    "the median of its per-round throughput ratios is below "
                    f"{REFERENCE_MIN_RATIO:.0%}.\n"
                )


def capture_report(report: Report, round_counts: dict[str, int]) -> tuple[str, str]:
    """The step-summary table and console output print_report writes."""
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
                    info_ratio_overrides=dict(INFO_RATIO_OVERRIDES),
                    rounds=3,
                    round_counts=round_counts,
                    warmup=1,
                    label="self-test",
                )
        finally:
            if previous is None:
                os.environ.pop("GITHUB_STEP_SUMMARY", None)
            else:
                os.environ["GITHUB_STEP_SUMMARY"] = previous
        return summary.read_text(encoding="utf-8"), console.getvalue()


def self_test_report_table(report: Report) -> None:
    table, output = capture_report(
        report,
        {
            "zig": 3,
            "zig-parent": 3,
            "zig-ref": 3,
            "c": 3,
            "rust": 3,
            "python": 3,
            "wasm": 3,
        },
    )
    assert (
        "| language | best bytes/s | median bytes/s | vs zig best "
        "| vs zig median | instructions/byte | status |" in table
    )
    assert "| zig | 200 | 190 | 100.0% | 105.3% | 10.000 | — |" in table
    assert (
        "| zig-parent | 190 | 190 | 95.0% | 100.0% | 10.000 "
        "| 🟢 time 100.0%, instructions +0.00% |" in table
    )
    assert (
        "| zig-ref | 195 | 190 | 97.5% | 102.6% | 10.100 "
        "| 🟢 time 99.9%, instructions -0.99% |" in table
    )
    assert "| c | 190 | 188 | 95.0% | 100.0% | — | 🟢 |" in table
    assert "| rust | 174 | 172 | 87.0% | 91.6% | — | 🟡 outside band |" in table
    assert "| python | 30 | 25 | 15.0% | 15.8% | — | 🔴 **below bar** |" in table
    assert "zig's second-best scored round (180 bytes/s)" in table
    assert "### 🔴 Example benchmark throughput vs examples/zig (self-test)" in table
    assert "zig-parent (this build's HEAD^ (the PR base on pull_request))" in table
    assert "zig-ref (the performance-reference tag)" in table
    assert "more than 0.5% more instructions" in table
    assert "3 parses of the sample (2 warmups and 1 timed), 100 bytes." in table
    assert "vs zig best" in output
    assert "FAIL" in output
    assert "outside 3% band (info)" in output
    assert "zig vs zig-parent, paired over 2 scored rounds" in output
    assert "round 2: zig 200, zig-parent 190" in output
    assert "instructions: zig 1,000, zig-ref 1,010 (-0.990%)" in output


def self_test() -> None:
    assert parse_bps("bytes_per_second: 1,234,567\n") == 1_234_567
    assert parse_instruction_count("events: Ir\nsummary: 1500378697\ntotals: 1\n") == (
        1_500_378_697
    )
    assert second_best([180]) == 180
    rounds = {
        "zig": [100, 200, 180],
        "zig-parent": [150, 190, 190],
        "zig-ref": [150, 195, 185],
        "c": [90, 190, 185],
        "rust": [80, 174, 170],
        "python": [10, 20, 30],
        "wasm": [60, 160, 155],
    }
    instructions = {"zig": 1000, "zig-parent": 1000, "zig-ref": 1010}
    report = evaluate(
        rounds,
        warmup=1,
        min_ratio=DEFAULT_MIN_RATIO,
        info_ratio=INFO_RATIO,
        instructions=instructions,
        counted_bytes=100,
    )
    assert report.scores["zig"] == 200
    assert report.medians["zig"] == 190
    assert report.zig_second_best == 180
    assert report.scores["c"] == 190
    assert report.medians["c"] == 187.5
    # Zig against its references: the median of the per-round ratios, and
    # the instruction counts. zig [200, 180] vs parent [190, 190] gives
    # ratios 1.053 and 0.947, median 1.0.
    assert report.references.keys() == {"zig-parent", "zig-ref"}
    assert report.references[PARENT_NAME].pairs == 2
    assert report.references[PARENT_NAME].time_ratio == 1.0
    assert report.references[PARENT_NAME].instruction_ratio == 1.0
    assert report.references[REF_NAME].instruction_ratio == 1000 / 1010
    for name in REFERENCE_NAMES:
        assert not report.references[name].regression
        assert name not in report.failures
        assert name not in report.info_band_misses
    # Time fails below the reference ratio, by size alone.
    slower = evaluate(
        {"zig": [100] + [85] * 6, "zig-parent": [100] + [100] * 6},
        warmup=1,
        min_ratio=DEFAULT_MIN_RATIO,
    )
    assert slower.references[PARENT_NAME].slower
    assert slower.references[PARENT_NAME].regression
    assert slower.references[PARENT_NAME].instruction_ratio is None
    at_ratio = evaluate(
        {"zig": [100] + [90] * 6, "zig-parent": [100] + [100] * 6},
        warmup=1,
        min_ratio=DEFAULT_MIN_RATIO,
    )
    assert not at_ratio.references[PARENT_NAME].regression

    # Instructions fail above the tolerance, whatever the time says.
    def instruction_verdict(zig_count: int) -> bool:
        return (
            evaluate(
                {"zig": [100, 120], REF_NAME: [100, 100]},
                warmup=1,
                min_ratio=DEFAULT_MIN_RATIO,
                instructions={"zig": zig_count, REF_NAME: 1000},
                counted_bytes=100,
            )
            .references[REF_NAME]
            .regression
        )

    assert instruction_verdict(1006)
    assert not instruction_verdict(1004)
    assert not instruction_verdict(900)
    # A failure names every reason it has.
    both = ReferenceStats(pairs=6, time_ratio=0.85, instruction_ratio=1.02)
    assert reference_failure(PARENT_NAME, both) == (
        "zig-parent (+2.00% instructions, above +0.5%; "
        "median time ratio 85.0%, below 90%)"
    )
    try:
        evaluate(
            {"zig": [100, 100], REF_NAME: [100, 100]},
            warmup=1,
            min_ratio=DEFAULT_MIN_RATIO,
            instructions={REF_NAME: 1000},
            counted_bytes=100,
        )
    except ValueError as error:
        assert "'zig'" in str(error)
    else:
        raise AssertionError("reference counts without zig's were accepted")
    assert "c" not in report.failures
    assert "c" not in report.info_band_misses
    # rust's 174 clears the 90% bar against zig's second-best (174/180)
    # but misses the 97% info band.
    assert "rust" not in report.failures
    assert "rust" in report.info_band_misses
    assert "python" in report.failures
    assert "python" in report.info_band_misses
    # wasm's own 70% info band replaces the global 97% one: its 160
    # against zig's second-best (180) is 89%, a miss under the global
    # band but clear of the override. The report keeps each band it used.
    assert "wasm" not in report.failures
    assert "wasm" not in report.info_band_misses
    assert report.info_bands["wasm"] == INFO_RATIO_OVERRIDES["wasm"]
    assert report.info_bands["c"] == INFO_RATIO
    overridden = evaluate(
        rounds,
        warmup=1,
        min_ratio=DEFAULT_MIN_RATIO,
        min_ratio_overrides={"python": 0.10},
    )
    assert "python" not in overridden.failures
    assert "python" in overridden.info_band_misses
    # An explicit info override replaces the built-in band: 0.99 flags
    # wasm's 89%; the band is exclusive, so 126/180 = 70% exactly clears
    # while 125 misses.
    strict = evaluate(
        rounds,
        warmup=1,
        min_ratio=DEFAULT_MIN_RATIO,
        info_ratio_overrides={"wasm": 0.99},
    )
    assert "wasm" in strict.info_band_misses
    at_band = evaluate(
        {"zig": [100, 200, 180], "wasm": [60, 126, 120]},
        warmup=1,
        min_ratio=DEFAULT_MIN_RATIO,
    )
    assert "wasm" not in at_band.info_band_misses
    below_band = evaluate(
        {"zig": [100, 200, 180], "wasm": [60, 125, 120]},
        warmup=1,
        min_ratio=DEFAULT_MIN_RATIO,
    )
    assert "wasm" in below_band.info_band_misses
    self_test_report_table(report)
    # Without bindings the report has zig and its references only, and no
    # bindings bar to state.
    zig_only = evaluate(
        {"zig": [100, 200, 180], "zig-parent": [150, 190, 190]},
        warmup=1,
        min_ratio=DEFAULT_MIN_RATIO,
    )
    table, output = capture_report(zig_only, {"zig": 3, "zig-parent": 3})
    assert "Bindings fail" not in table
    assert "Instructions per byte" not in table
    assert "bindings fail" not in output
    assert "| zig-parent | 190 | 190 | 95.0% | 100.0% | — | 🟢 time 100.0% |" in table
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
    print("self-test ok")


def parse_override(text: str) -> tuple[str, float]:
    name, separator, value = text.partition("=")
    if not separator or not name:
        raise ValueError(f"override must be LANG=RATIO, got {text!r}")
    if name in REFERENCE_NAMES:
        raise ValueError(
            f"{name} is exempt from the bar; a min-ratio override has no "
            f"effect on it (reference rows fail only against zig's "
            f"instructions and time)"
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
        help=f"every runner's total rounds (default: {DEFAULT_ROUNDS})",
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
        "--no-bindings",
        action="store_true",
        help="run zig and its references only",
    )
    parser.add_argument(
        "--zig-parent-binary",
        type=Path,
        default=None,
        help=(
            "benchmark binary built from the parent commit's examples/zig; "
            "adds a zig-parent row interleaved in every round and compared "
            "with zig (default: no parent comparison)"
        ),
    )
    parser.add_argument(
        "--zig-ref-binary",
        type=Path,
        default=None,
        help=(
            "benchmark binary built from the performance-reference tag's "
            "examples/zig; adds a zig-ref row interleaved in every round "
            "and compared with zig (default: no tag comparison)"
        ),
    )
    for name in ("zig", PARENT_NAME, REF_NAME):
        parser.add_argument(
            f"--{name}-count-binary",
            type=Path,
            default=None,
            help=(
                f"{name}'s benchmark built for counting (x86-64-v3); run "
                "once under callgrind for its instruction count"
            ),
        )
    parser.add_argument("--min-ratio", type=float, default=DEFAULT_MIN_RATIO)
    parser.add_argument(
        "--rounds-override",
        action="append",
        default=[],
        metavar="LANG=COUNT",
        help=(
            "per-language total round count replacing --rounds, e.g. "
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
    required = ("zig",) if args.no_bindings else ("zig", *BINDING_NAMES)
    round_counts = {
        name: count
        for name, count in {**DEFAULT_ROUNDS_OVERRIDES, **cli_rounds}.items()
        if name in required
    }
    for name in required:
        round_counts.setdefault(name, args.rounds)
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

    runner_list = [
        runner
        for runner in default_runners(root, parser_dir)
        if runner.name in required
    ]
    reference_binaries = {
        PARENT_NAME: args.zig_parent_binary,
        REF_NAME: args.zig_ref_binary,
    }
    for name, binary in reference_binaries.items():
        if binary is not None:
            runner_list.append(Runner(name, [str(binary.resolve())]))
    runners = {runner.name: runner for runner in runner_list}
    for name in REFERENCE_NAMES:
        if name in runners:
            # References run exactly zig's rounds, so every scored round pairs.
            round_counts[name] = round_counts["zig"]
    count_binaries = {
        "zig": args.zig_count_binary,
        PARENT_NAME: args.zig_parent_count_binary,
        REF_NAME: args.zig_ref_count_binary,
    }
    count_binaries = {
        name: binary for name, binary in count_binaries.items() if binary is not None
    }
    for name in count_binaries:
        if name in REFERENCE_NAMES and name not in runners:
            print(f"--{name}-count-binary needs --{name}-binary", file=sys.stderr)
            return 1
    if any(name in REFERENCE_NAMES for name in count_binaries) and (
        "zig" not in count_binaries
    ):
        print("reference counting builds need --zig-count-binary", file=sys.stderr)
        return 1
    try:
        cli_overrides = dict(parse_override(text) for text in args.min_ratio_override)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    overrides = {
        name: ratio
        for name, ratio in {**DEFAULT_MIN_RATIO_OVERRIDES, **cli_overrides}.items()
        if name in required
    }
    info_overrides = {
        name: ratio for name, ratio in INFO_RATIO_OVERRIDES.items() if name in required
    }
    missing = []
    for name in required:
        if name not in runners:
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
    for name, binary in count_binaries.items():
        if not binary.is_file():
            missing.append(f"{name} counting build: {binary}")
    if missing:
        print("missing benchmark binaries:\n  " + "\n  ".join(missing), file=sys.stderr)
        return 1

    start = f"interleaved {args.rounds} rounds"
    if args.label:
        start += f" [{args.label}]"
    start += rounds_note(round_counts, round_counts["zig"])
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
    instructions: dict[str, int] = {}
    counted_bytes = COUNTED_PARSES * sample.stat().st_size if count_binaries else 0
    for name, binary in count_binaries.items():
        instructions[name] = count_instructions(binary.resolve(), sample)
        print(f"instructions {name}: {format_int(instructions[name])}", flush=True)

    report = evaluate(
        rounds,
        warmup=args.warmup,
        min_ratio=args.min_ratio,
        min_ratio_overrides=overrides,
        info_ratio=INFO_RATIO,
        info_ratio_overrides=info_overrides,
        instructions=instructions,
        counted_bytes=counted_bytes,
    )
    print()
    print_report(
        report,
        min_ratio=args.min_ratio,
        min_ratio_overrides=overrides,
        info_ratio=INFO_RATIO,
        info_ratio_overrides=info_overrides,
        rounds=round_counts["zig"],
        round_counts=round_counts,
        warmup=args.warmup,
        label=args.label,
    )
    if report.info_band_misses:
        bands: dict[float, list[str]] = {}
        for name in report.info_band_misses:
            bands.setdefault(report.info_bands[name], []).append(name)
        parts = [
            f"outside {1 - band:.0%} of zig second-best: {', '.join(names)}"
            for band, names in sorted(bands.items(), reverse=True)
        ]
        print("info: " + "; ".join(parts), flush=True)
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
    regressed = [
        reference_failure(name, stats)
        for name, stats in report.references.items()
        if stats.regression
    ]
    if regressed:
        errors.append(f"benchmark: zig regressed against {', '.join(regressed)}")
    for message in errors:
        # Report every failing gate, not just the first one that fires.
        print(f"::error::{message}")
        print(message, file=sys.stderr)
    if errors:
        return 1
    print("benchmark: every row passed")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"::error::benchmark: {error}")
        print(error, file=sys.stderr)
        sys.exit(1)
