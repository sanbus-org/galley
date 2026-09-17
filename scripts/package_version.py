#!/usr/bin/env python3
"""Run version for packaging: product version on v* tags, dev version otherwise.

Dev versions look like 0.1.3-dev.42.gabc123456789 (product, CI run number,
`g`-prefixed short SHA). The `g` prefix (git-describe convention) keeps the
final identifier non-numeric, which semver requires; the run number orders,
the SHA traces to the commit. Re-running the same commit yields the same
version, so retries hit the existing already-published skip paths.

Flavors (positional, default: npm):
  npm     npm/cargo/maven semver, used verbatim: 0.1.3-dev.42.gabc123456789
  pep440  Python wheels demand PEP 440 (no dashes): 0.1.3.dev42. The
          commit hash is dropped; the run number already makes it unique
          per CI run. Prerelease tags map exactly like the historical
          shell mapping: -alpha.N/aN, -beta.N/bN, -rc.N/rcN, -dev.N/.devN.

On a v* tag every flavor yields the product version (pep440-mapped), so
tag builds and stable publishes share one code path with dev builds.

Environment: GITHUB_REF, GITHUB_RUN_NUMBER, GITHUB_SHA when running in
Actions; locally the run number is 0 and the SHA comes from git HEAD.

Run: python3 scripts/package_version.py [--flavor npm|pep440]
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from product_version import REPO_ROOT, product_version


def git_head_sha(length: int = 12) -> str:
    listed = subprocess.run(
        ["git", "rev-parse", f"--short={length}", "HEAD"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    if listed.returncode != 0:
        print("package_version: git rev-parse HEAD failed", file=sys.stderr)
        raise SystemExit(1)
    return listed.stdout.strip()


def run_version() -> str:
    """The version for this run: product on v* tags, dev otherwise."""
    import os

    product = product_version()
    ref = os.environ.get("GITHUB_REF", "")
    if ref.startswith("refs/tags/v"):
        return product
    run = os.environ.get("GITHUB_RUN_NUMBER", "0")
    sha = os.environ.get("GITHUB_SHA", "")[:12] or git_head_sha()
    return f"{product}-dev.{run}.g{sha}"


def to_pep440(version: str) -> str:
    """Map a run version to PEP 440, failing loud on unknown suffixes.

    Dev suffixes compose with prerelease bases: 0.2.0-beta.1-dev.42.gsha
    maps the base first (0.2.0b1), then appends the dev segment
    (0.2.0b1.dev42).
    """
    dev = re.fullmatch(r"(.*)-dev\.(.+)", version)
    if dev is not None:
        base, suffix = dev.groups()
        run = re.match(r"[0-9]+", suffix)
        if run is None:
            print(
                f"package_version: dev suffix {suffix!r} starts with no run number",
                file=sys.stderr,
            )
            raise SystemExit(1)
        return f"{to_pep440(base)}.dev{run.group(0)}"
    if "-" not in version:
        return version
    match = re.fullmatch(r"(.*)-(alpha|beta|rc)\.(.+)", version)
    if match is None:
        print(
            f"package_version: prerelease {version!r} has no PEP 440 mapping",
            file=sys.stderr,
        )
        raise SystemExit(1)
    base, kind, suffix = match.groups()
    if kind == "alpha":
        return f"{base}a{suffix}"
    if kind == "beta":
        return f"{base}b{suffix}"
    return f"{base}rc{suffix}"


def main() -> None:
    flavor = "npm"
    explicit: str | None = None
    arguments = sys.argv[1:]
    if arguments[:1] == ["--flavor"]:
        if len(arguments) < 2:
            print("package_version: --flavor needs a value", file=sys.stderr)
            raise SystemExit(2)
        flavor = arguments[1]
        arguments = arguments[2:]
    if len(arguments) == 1:
        explicit = arguments[0]
    elif arguments:
        print("package_version: usage: package_version.py [--flavor npm|pep440] [VERSION]",
              file=sys.stderr)
        raise SystemExit(2)
    version = explicit if explicit is not None else run_version()
    if flavor == "npm":
        print(version)
    elif flavor == "pep440":
        print(to_pep440(version))
    else:
        print(f"package_version: unknown flavor {flavor!r}", file=sys.stderr)
        raise SystemExit(2)


if __name__ == "__main__":
    main()
