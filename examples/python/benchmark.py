#!/usr/bin/env python3
"""Parse throughput through the Galley Python bindings: parses the given
sample on one session and reports bytes/s."""

from __future__ import annotations

import importlib
import sys
import time
from pathlib import Path

DEFAULT_ITERATIONS = 10


def main() -> int:
    if len(sys.argv) < 3:
        print(
            "usage: benchmark.py <parser-package-dir> <sample-file> [iterations]",
            file=sys.stderr,
        )
        return 1
    package_dir = Path(sys.argv[1]).resolve()
    if not (package_dir / "__init__.py").is_file():
        print(
            f"{package_dir} is not a built parser package (no __init__.py); "
            "run the binding build first",
            file=sys.stderr,
        )
        return 1
    sample = Path(sys.argv[2])
    iterations = DEFAULT_ITERATIONS
    if len(sys.argv) > 3:
        iterations = int(sys.argv[3])
        if iterations < 1:
            print("iterations must be >= 1", file=sys.stderr)
            return 1

    sys.path.insert(0, str(package_dir.parent))
    # The package takes its import name from its directory; a package
    # named json deliberately shadows the stdlib one (this script never
    # uses stdlib json).
    parser = importlib.import_module(package_dir.name)

    try:
        data = sample.read_bytes()
    except OSError:
        print(f"failed to read {sample}", file=sys.stderr)
        return 1

    try:
        session = parser.Session()
    except parser.GalleyError:
        print("failed to create a parser session", file=sys.stderr)
        return 1

    with session:
        # The first two parses are cold: the session arena grows during the first and is reallocated for the second.
        for _ in range(2):
            try:
                parsed = session.parse(data)
            except parser.GalleyError as error:
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
            except parser.GalleyError as error:
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
    print(f"input: {sample}")
    print(f"bytes: {len(data):,}")
    print(f"iterations: {iterations:,}")
    print(f"parsed_bytes: {total:,}")
    print(f"duration_ns: {elapsed:,}")
    print(f"bytes_per_second: {bps:,}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
