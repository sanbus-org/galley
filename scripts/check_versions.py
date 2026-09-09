#!/usr/bin/env python3
"""Version-field gate: product version in VERSION, sentinel in manifests.

Discovers every git-tracked Cargo.toml, pyproject.toml, pom.xml,
build.zig.zon, and package.json. Each must carry 0.0.0, except the
JavaScript workspace root and JavaScript examples, which must omit
version. A new tracked manifest is gated automatically.

VERSION itself is checked by product_version (non-empty, not the sentinel).

Run: python3 scripts/check_versions.py (also wired into the
bindings-consistency CI job; publish jobs require that job via test).
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from product_version import REPO_ROOT, SENTINEL, product_version


def fail(message: str) -> None:
    print(f"check_versions: {message}", file=sys.stderr)
    raise SystemExit(1)


def toml_package_version(path: Path) -> str | None:
    match = re.search(r'^version\s*=\s*"([^"]+)"', path.read_text(), re.MULTILINE)
    return match.group(1) if match else None


def maven_project_version(path: Path) -> str | None:
    root = ET.parse(path).getroot()
    namespace = "{http://maven.apache.org/POM/4.0.0}"
    element = root.find(f"{namespace}version")
    if element is None or not (element.text or "").strip():
        return None
    return element.text.strip()


def zig_package_version(path: Path) -> str | None:
    match = re.search(r'\.version\s*=\s*"([^"]+)"', path.read_text())
    return match.group(1) if match else None


def json_package_version(path: Path) -> str | None:
    data = json.loads(path.read_text())
    if "version" not in data:
        return None
    version = data["version"]
    if not isinstance(version, str):
        fail(f"{path}: version is not a string")
    return version


def omits_version(relative: Path) -> bool:
    if relative == Path("bindings/js/package.json"):
        return True
    parts = relative.parts
    return (
        len(parts) >= 3
        and parts[0] == "examples"
        and parts[1] == "js"
        and parts[-1] == "package.json"
    )


def discovered_manifests() -> list[tuple[Path, Path, object]]:
    readers = {
        "Cargo.toml": toml_package_version,
        "pyproject.toml": toml_package_version,
        "package.json": json_package_version,
        "pom.xml": maven_project_version,
        "build.zig.zon": zig_package_version,
    }
    listed = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=REPO_ROOT,
        capture_output=True,
    )
    if listed.returncode != 0:
        fail("git ls-files failed")
    found: list[tuple[Path, Path, object]] = []
    for raw in listed.stdout.split(b"\0"):
        if not raw:
            continue
        relative = Path(raw.decode())
        reader = readers.get(relative.name)
        if reader is None:
            continue
        found.append((REPO_ROOT / relative, relative, reader))
    return found


def main() -> None:
    product = product_version()
    errors: list[str] = []
    for path, relative, reader in discovered_manifests():
        actual = reader(path)
        if omits_version(relative):
            if actual is not None:
                errors.append(f"{relative}: must not carry a version")
            continue
        if actual is None:
            errors.append(
                f"{relative}: missing version (must be the sentinel {SENTINEL!r})"
            )
            continue
        if actual != SENTINEL:
            errors.append(
                f"{relative}: version {actual!r} is not the sentinel {SENTINEL!r}"
            )
    if errors:
        for error in errors:
            print(f"check_versions: {error}", file=sys.stderr)
        raise SystemExit(1)
    print(f"Product version {product}; every manifest version is {SENTINEL}")


if __name__ == "__main__":
    main()
