#!/usr/bin/env python3
"""Same-machine interleaved example-benchmark comparison vs examples/zig.

Build the example benchmark binaries first (see .github/workflows/ci.yml).
This script runs them round-robin, scores the best of the non-warmup rounds,
and fails if a C-ABI example is below --min-ratio of Zig's second-best scored
round. The report shows each language's best and median against Zig's best and
median; those display ratios never decide pass or fail.
Per-language bars (--min-ratio-override) replace the global bar for the
named languages; currently only the WebAssembly example uses one, since it
runs the same parser compiled to wasm, which trails native codegen.
Per-language round counts (--rounds-override) replace --rounds for the
named languages.
"""

from __future__ import annotations

import argparse
import contextlib
import io
import os
import re
import statistics
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

BPS_RE = re.compile(r"^bytes_per_second:\s*([0-9,]+)\s*$")
DEFAULT_ROUNDS = 7
DEFAULT_WARMUP = 1
DEFAULT_ITERATIONS = 10
DEFAULT_MIN_RATIO = 0.94
# Per-language bars replacing the global --min-ratio for the named
# languages. Only wasm uses one today.
DEFAULT_MIN_RATIO_OVERRIDES: dict[str, float] = {"wasm": 0.7}
# Per-language round counts replacing --rounds for the named languages.
# zig is the reference every other language is divided by, so its
# second-best scored round has to be stable; extra runs pin the baseline
# down. wasm has measured noisier than the rest in CI, so it gets extra
# runs too.
DEFAULT_ROUNDS_OVERRIDES: dict[str, int] = {}
INFO_RATIO = 0.97
LANGUAGE_ORDER = (
    "zig",
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


@dataclass
class Report:
    rounds: dict[str, list[int]]
    scored: dict[str, list[int]]
    scores: dict[str, int]
    medians: dict[str, float]
    zig_second_best: int
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
    failures: list[str] = []
    info_band_misses: list[str] = []
    for name, score in scores.items():
        if name == reference:
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
    )


def default_runners(root: Path) -> list[Runner]:
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
            [sys.executable, "benchmark.py"],
            cwd=root / "examples" / "python",
        ),
        Runner(
            "typescript",
            ["npx", "tsx", "benchmark.ts"],
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
            ],
            cwd=root / "examples" / "js",
        ),
        Runner(
            "bun",
            ["bun", "benchmark.ts"],
            cwd=root / "examples" / "js",
        ),
        Runner(
            "wasm",
            ["npx", "tsx", "benchmark.ts", "--wasm"],
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


def print_report(
    report: Report,
    *,
    min_ratio: float,
    min_ratio_overrides: dict[str, float],
    info_ratio: float,
    rounds: int,
    round_counts: dict[str, int],
    warmup: int,
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
        if name in report.failures:
            note = "  FAIL"
        elif name in report.info_band_misses:
            note = f"  outside {1 - info_ratio:.0%} band (info)"
        best_ratio = score / report.scores["zig"]
        median_ratio = score / report.medians["zig"]
        print(prefix + f"{best_ratio:>13.1%}  {median_ratio:>13.1%}{note}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write("### Example benchmark throughput vs examples/zig\n\n")
            handle.write(
                "| language | best bytes/s | median bytes/s "
                "| vs zig best | vs zig median |\n"
            )
            handle.write("| --- | ---: | ---: | ---: | ---: |\n")
            for name in names:
                score = report.scores[name]
                median_bytes = report.medians[name]
                if name == "zig":
                    handle.write(
                        f"| {name} | {format_int(score)} "
                        f"| {format_int(median_bytes)} "
                        f"| reference | reference |\n"
                    )
                else:
                    handle.write(
                        f"| {name} | {format_int(score)} "
                        f"| {format_int(median_bytes)} "
                        f"| {score / report.scores['zig']:.1%} "
                        f"| {score / report.medians['zig']:.1%} |\n"
                    )
            if warmup == 0:
                warmup_text = "no warmup"
            elif warmup == 1:
                warmup_text = "round 1 is warmup"
            else:
                warmup_text = f"first {warmup} rounds are warmup"
            shown = {
                name: count
                for name, count in round_counts.items()
                if name in names and count != rounds
            }
            rounds_text = f"{rounds} interleaved rounds"
            if shown:
                rounds_text += f" (overrides: {format_rounds_overrides(shown)})"
            handle.write(
                f"\n{rounds_text} including zig; {warmup_text}; "
                f"score and median are over the remaining rounds, and the "
                f"vs-zig columns divide by zig's best and median of those "
                f"rounds. Fail below {min_ratio:.0%} of zig's second-best "
                f"scored round ({format_int(report.zig_second_best)} bytes/s)"
            )
            if min_ratio_overrides:
                handle.write(f" (overrides: {format_overrides(min_ratio_overrides)})")
            handle.write(f". {info_ratio:.0%} band is informational.\n")


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
                    round_counts={"zig": 5, "c": 3, "rust": 3, "python": 3},
                    warmup=1,
                )
        finally:
            if previous is None:
                os.environ.pop("GITHUB_STEP_SUMMARY", None)
            else:
                os.environ["GITHUB_STEP_SUMMARY"] = previous
        table = summary.read_text(encoding="utf-8")
        output = console.getvalue()
    assert (
        "| language | best bytes/s | median bytes/s | vs zig best | vs zig median |"
        in table
    )
    assert "| zig | 200 | 190 | reference | reference |" in table
    assert "| c | 190 | 188 | 95.0% | 100.0% |" in table
    assert "| rust | 174 | 172 | 87.0% | 91.6% |" in table
    assert "zig's second-best scored round (180 bytes/s)" in table
    assert "vs zig best" in output
    assert "vs zig median" in output
    assert "FAIL" in output
    assert "outside 3% band (info)" in output


def self_test() -> None:
    assert parse_bps("bytes_per_second: 1,234,567\n") == 1_234_567
    assert second_best([180]) == 180
    rounds = {
        "zig": [100, 200, 180],
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
    for bad in ("zig", "=6", "cobol=6", "zig=six", "zig=0", "zig=-2"):
        try:
            parse_rounds_override(bad)
        except ValueError:
            pass
        else:
            raise AssertionError(f"parse_rounds_override accepted {bad!r}")
    print("self-test ok")


def parse_override(text: str) -> tuple[str, float]:
    name, separator, value = text.partition("=")
    if not separator or not name:
        raise ValueError(f"override must be LANG=RATIO, got {text!r}")
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
    parser.add_argument("--rounds", type=int, default=DEFAULT_ROUNDS)
    parser.add_argument("--warmup", type=int, default=DEFAULT_WARMUP)
    parser.add_argument("--iterations", type=int, default=DEFAULT_ITERATIONS)
    parser.add_argument("--min-ratio", type=float, default=DEFAULT_MIN_RATIO)
    parser.add_argument(
        "--rounds-override",
        action="append",
        default=[],
        metavar="LANG=COUNT",
        help=(
            "per-language round count replacing --rounds, e.g. zig=6 "
            "(repeatable; built-in: "
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

    runners = {runner.name: runner for runner in default_runners(root)}
    try:
        cli_overrides = dict(parse_override(text) for text in args.min_ratio_override)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    overrides = {**DEFAULT_MIN_RATIO_OVERRIDES, **cli_overrides}
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
        if name == "deno":
            script = (runner.cwd or root) / "benchmark.ts"
            if not script.is_file():
                missing.append(f"{name}: {script}")
            continue
        if name == "bun":
            script = (runner.cwd or root) / "benchmark.ts"
            if not script.is_file():
                missing.append(f"{name}: {script}")
            continue
        if name == "wasm":
            script = (runner.cwd or root) / "benchmark.ts"
            if not script.is_file():
                missing.append(f"{name}: {script}")
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
                not (
                    root / "examples" / "java" / "json" / "libgalley-java.so"
                ).is_file()
                and not (
                    root / "examples" / "java" / "json" / "libgalley-java.dylib"
                ).is_file()
            ):
                missing.append(f"{name}: examples/java/json/libgalley-java.*")
            continue
        program = Path(runner.argv[0])
        if not program.is_file():
            missing.append(f"{name}: {program}")
    if missing:
        print("missing benchmark binaries:\n  " + "\n  ".join(missing), file=sys.stderr)
        return 1

    start = f"interleaved {args.rounds} rounds"
    extra_rounds = {
        name: count for name, count in round_counts.items() if count != args.rounds
    }
    if extra_rounds:
        start += f" (overrides: {format_rounds_overrides(extra_rounds)})"
    print(
        f"{start} (warmup {args.warmup}), {args.iterations} iterations, sample {sample}"
    )
    rounds: dict[str, list[int]] = {name: [] for name in LANGUAGE_ORDER}
    for round_index in range(max(round_counts.values())):
        for name in LANGUAGE_ORDER:
            if round_index >= round_counts[name]:
                continue
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
    )
    if report.info_band_misses:
        print(
            f"info: outside {1 - INFO_RATIO:.0%} of zig second-best: "
            + ", ".join(report.info_band_misses),
            flush=True,
        )
    if report.failures:
        parts = []
        for name in report.failures:
            bar = overrides.get(name, args.min_ratio)
            parts.append(f"{name} below {bar:.0%}")
        message = (
            f"example-benchmarks: {', '.join(parts)} of zig second-best "
            f"({format_int(report.zig_second_best)} bytes/s)"
        )
        print(f"::error::{message}")
        print(message, file=sys.stderr)
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
        print(f"::error::example-benchmarks: {error}")
        print(error, file=sys.stderr)
        sys.exit(1)
