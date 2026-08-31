#!/usr/bin/env python3
"""Same-machine interleaved example-benchmark comparison vs examples/zig.

Build the example benchmark binaries first (see .github/workflows/ci.yml).
This script runs them round-robin, scores the best of the non-warmup rounds,
and fails if a C-ABI example is below --min-ratio of Zig's median.
"""

from __future__ import annotations

import argparse
import os
import re
import statistics
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

BPS_RE = re.compile(r"^bytes_per_second:\s*([0-9,]+)\s*$")
DEFAULT_ROUNDS = 3
DEFAULT_WARMUP = 1
DEFAULT_ITERATIONS = 10_000
DEFAULT_MIN_RATIO = 0.94
INFO_RATIO = 0.97
LANGUAGE_ORDER = ("zig", "c", "cpp", "rust", "go", "python", "typescript")


@dataclass(frozen=True)
class Runner:
    name: str
    argv: list[str]
    cwd: Path | None = None


@dataclass
class Report:
    rounds: dict[str, list[int]]
    scored: dict[str, list[int]]
    scores: dict[str, int]
    zig_median: float
    failures: list[str] = field(default_factory=list)
    info_band_misses: list[str] = field(default_factory=list)


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


def evaluate(
    rounds: dict[str, list[int]],
    *,
    warmup: int,
    min_ratio: float,
    info_ratio: float = INFO_RATIO,
    reference: str = "zig",
) -> Report:
    if reference not in rounds:
        raise ValueError(f"missing reference language {reference!r}")
    scored = {name: values[warmup:] for name, values in rounds.items()}
    for name, values in scored.items():
        if not values:
            raise ValueError(f"{name}: no scored rounds (warmup={warmup})")
    scores = {name: max(values) for name, values in scored.items()}
    zig_median = median(scored[reference])
    if zig_median <= 0:
        raise ValueError(f"{reference} median throughput is {zig_median}")
    failures: list[str] = []
    info_band_misses: list[str] = []
    for name, score in scores.items():
        if name == reference:
            continue
        ratio = score / zig_median
        if ratio < min_ratio:
            failures.append(name)
        if ratio < info_ratio:
            info_band_misses.append(name)
    return Report(
        rounds=rounds,
        scored=scored,
        scores=scores,
        zig_median=zig_median,
        failures=failures,
        info_band_misses=info_band_misses,
    )


def default_runners(root: Path) -> list[Runner]:
    rust_bench = root / "examples" / "rust" / "target" / "release" / "benchmark"
    return [
        Runner("zig", [str(root / "examples" / "zig" / "zig-out" / "bin" / "benchmark")]),
        Runner("c", [os.environ.get("BENCH_C", "/tmp/build-c/bin/benchmark")]),
        Runner("cpp", [os.environ.get("BENCH_CPP", "/tmp/build-cpp/bin/benchmark")]),
        Runner("rust", [os.environ.get("BENCH_RUST", str(rust_bench))]),
        Runner("go", [os.environ.get("BENCH_GO", "/tmp/galley-go-benchmark")]),
        Runner(
            "python",
            [sys.executable, "benchmark.py"],
            cwd=root / "examples" / "python",
        ),
        Runner(
            "typescript",
            ["npx", "tsx", "benchmark.ts"],
            cwd=root / "examples" / "typescript",
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


def print_report(report: Report, *, min_ratio: float, info_ratio: float) -> None:
    names = [name for name in LANGUAGE_ORDER if name in report.rounds]
    print("round  language       bytes_per_second")
    for index in range(len(next(iter(report.rounds.values())))):
        for name in names:
            print(f"{index + 1:>5}  {name:<13} {format_int(report.rounds[name][index])}")
    print()
    print(f"zig median (scored rounds): {format_int(report.zig_median)}")
    print(f"fail below {min_ratio:.0%} of zig median; {info_ratio:.0%} band is informational")
    print("language       best        vs zig")
    for name in names:
        score = report.scores[name]
        if name == "zig":
            print(f"{name:<13} {format_int(score):>11}  reference")
            continue
        ratio = score / report.zig_median
        note = ""
        if name in report.failures:
            note = "  FAIL"
        elif name in report.info_band_misses:
            note = f"  outside {1 - info_ratio:.0%} band (info)"
        print(f"{name:<13} {format_int(score):>11}  {ratio:6.1%}{note}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write("### Example benchmark throughput vs examples/zig\n\n")
            handle.write("| language | best bytes/s | vs zig |\n")
            handle.write("| --- | ---: | ---: |\n")
            for name in names:
                score = report.scores[name]
                if name == "zig":
                    handle.write(f"| {name} | {format_int(score)} | reference |\n")
                else:
                    handle.write(
                        f"| {name} | {format_int(score)} | {score / report.zig_median:.1%} |\n"
                    )
            handle.write(
                f"\nFail below {min_ratio:.0%} of zig median. "
                f"{info_ratio:.0%} band is informational.\n"
            )


def self_test() -> None:
    assert parse_bps("bytes_per_second: 1,234,567\n") == 1_234_567
    rounds = {
        "zig": [100, 200, 180],
        "c": [90, 190, 185],
        "rust": [80, 180, 180],
        "python": [10, 20, 30],
    }
    report = evaluate(
        rounds,
        warmup=1,
        min_ratio=DEFAULT_MIN_RATIO,
        info_ratio=INFO_RATIO,
    )
    assert report.scores["zig"] == 200
    assert report.zig_median == 190
    assert report.scores["c"] == 190
    assert "c" not in report.failures
    assert "c" not in report.info_band_misses
    assert "rust" not in report.failures
    assert "rust" in report.info_band_misses
    assert "python" in report.failures
    assert "python" in report.info_band_misses
    print("self-test ok")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--root", type=Path, default=None)
    parser.add_argument("--sample", type=Path, default=None)
    parser.add_argument("--rounds", type=int, default=DEFAULT_ROUNDS)
    parser.add_argument("--warmup", type=int, default=DEFAULT_WARMUP)
    parser.add_argument("--iterations", type=int, default=DEFAULT_ITERATIONS)
    parser.add_argument("--min-ratio", type=float, default=DEFAULT_MIN_RATIO)
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if args.rounds < 1:
        print("rounds must be >= 1", file=sys.stderr)
        return 1
    if args.warmup < 0 or args.warmup >= args.rounds:
        print("warmup must be >= 0 and < rounds", file=sys.stderr)
        return 1
    if args.iterations < 1:
        print("iterations must be >= 1", file=sys.stderr)
        return 1

    root = (args.root or Path(__file__).resolve().parent.parent).resolve()
    sample = (args.sample or root / "languages" / "json" / "samples" / "code-01.json").resolve()
    if not sample.is_file():
        print(f"missing sample {sample}", file=sys.stderr)
        return 1

    runners = {runner.name: runner for runner in default_runners(root)}
    missing = []
    for name in LANGUAGE_ORDER:
        runner = runners[name]
        if name == "python":
            script = (runner.cwd or root) / "benchmark.py"
            if not script.is_file():
                missing.append(f"{name}: {script}")
            continue
        if name == "typescript":
            script = (runner.cwd or root) / "benchmark.ts"
            if not script.is_file():
                missing.append(f"{name}: {script}")
            continue
        program = Path(runner.argv[0])
        if not program.is_file():
            missing.append(f"{name}: {program}")
    if missing:
        print("missing benchmark binaries:\n  " + "\n  ".join(missing), file=sys.stderr)
        return 1

    print(
        f"interleaved {args.rounds} rounds "
        f"(warmup {args.warmup}), {args.iterations} iterations, sample {sample}"
    )
    rounds: dict[str, list[int]] = {name: [] for name in LANGUAGE_ORDER}
    for round_index in range(args.rounds):
        for name in LANGUAGE_ORDER:
            bps = run_one(runners[name], sample, args.iterations)
            rounds[name].append(bps)
            print(f"round {round_index + 1} {name}: {format_int(bps)} bytes/s", flush=True)

    report = evaluate(
        rounds,
        warmup=args.warmup,
        min_ratio=args.min_ratio,
        info_ratio=INFO_RATIO,
    )
    print()
    print_report(report, min_ratio=args.min_ratio, info_ratio=INFO_RATIO)
    if report.info_band_misses:
        print(
            f"info: outside {1 - INFO_RATIO:.0%} of zig median: "
            + ", ".join(report.info_band_misses),
            flush=True,
        )
    if report.failures:
        names = ", ".join(report.failures)
        message = (
            f"example-benchmarks: {names} below {args.min_ratio:.0%} of zig median "
            f"({format_int(report.zig_median)} bytes/s)"
        )
        print(f"::error::{message}")
        print(message, file=sys.stderr)
        return 1
    print(
        f"all C-ABI examples are >= {args.min_ratio:.0%} of zig median "
        f"({format_int(report.zig_median)} bytes/s)"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"::error::example-benchmarks: {error}")
        print(error, file=sys.stderr)
        sys.exit(1)
