#!/usr/bin/env python3
"""JSON throughput through the Galley Python bindings: no AST, no procedures,
no error recovery. Parses languages/json/samples/code-01.json 50,000 times
on one session and reports bytes/s."""

from __future__ import annotations

import os
import sys
import time
from pathlib import Path

LOGICAL_INPUT = "languages/json/samples/code-01.json"
DEFAULT_ITERATIONS = 50_000


def resolve_input(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit)
    checkout = os.environ.get("GALLEY_CHECKOUT")
    if checkout:
        candidate = Path(checkout) / LOGICAL_INPUT
        if candidate.is_file():
            return candidate
    candidate = Path(__file__).resolve().parent.parent.parent / LOGICAL_INPUT
    if candidate.is_file():
        return candidate
    raise SystemExit(f"missing {LOGICAL_INPUT}")


def main() -> int:
    arguments = sys.argv[1:]
    iterations = DEFAULT_ITERATIONS
    explicit: str | None = None
    if len(arguments) > 0:
        explicit = arguments[0]
    if len(arguments) > 1:
        iterations = int(arguments[1])
        if iterations < 1:
            print("iterations must be >= 1", file=sys.stderr)
            return 1

    language_dir = Path(__file__).resolve().parent / "benchmark"
    sys.path.insert(0, str(language_dir))
    import galley

    path = resolve_input(explicit)
    try:
        data = path.read_bytes()
    except OSError:
        print(f"failed to read {LOGICAL_INPUT}", file=sys.stderr)
        return 1

    try:
        session = galley.Session()
    except galley.Error:
        print("failed to create a parser session", file=sys.stderr)
        return 1

    with session:
        try:
            parsed = session.parse(data)
        except galley.Error as error:
            print(f"warmup parse failed: {error} ({error.code})", file=sys.stderr)
            return 1
        if parsed != len(data):
            print(
                f"warmup parse failed: parsed {parsed} of {len(data)} bytes",
                file=sys.stderr,
            )
            return 1

        start = time.perf_counter_ns()
        for index in range(iterations):
            try:
                parsed = session.parse(data)
            except galley.Error as error:
                print(
                    f"parse failed at iteration {index}: {error} ({error.code})",
                    file=sys.stderr,
                )
                return 1
            if parsed != len(data):
                print(
                    f"parse failed at iteration {index}: parsed {parsed} of {len(data)} bytes",
                    file=sys.stderr,
                )
                return 1
        elapsed = time.perf_counter_ns() - start

    total = len(data) * iterations
    bps = 0 if elapsed == 0 else total * 1_000_000_000 // elapsed
    print(f"input: {LOGICAL_INPUT}")
    print(f"bytes: {len(data):,}")
    print(f"iterations: {iterations:,}")
    print(f"parsed_bytes: {total:,}")
    print(f"duration_ns: {elapsed:,}")
    print(f"bytes_per_second: {bps:,}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
