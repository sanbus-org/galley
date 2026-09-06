#!/usr/bin/env python3
"""Lockstep version gate for the JavaScript packages.

Single source of truth: bindings/js/VERSION. Every bindings/js/*/package.json
must carry exactly that version, and internal `file:` dependencies may only
reference sibling packages inside the set. A new package directory with a
package.json fails loudly until it is added to EXPECTED below.

To release a new version: edit bindings/js/VERSION once, run this script,
fix every mismatch it reports. Never bump individual package.json files.

Run: python3 scripts/check_js_versions.py (also wired into the
bindings-consistency CI job).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
JS_DIR = REPO_ROOT / "bindings" / "js"
VERSION_FILE = JS_DIR / "VERSION"

# Directory -> expected npm package name. Closed set on purpose.
EXPECTED: dict[str, str] = {
    "core": "galley-js-core",
    "node": "galley-js-node",
    "bun": "galley-js-bun",
    "deno": "galley-js-deno",
    "wasm": "galley-js-wasm",
    "universal": "@sanbus-org/galley",
}


def fail(message: str) -> None:
    print(f"check_js_versions: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    expected_version = VERSION_FILE.read_text().strip()
    if not expected_version:
        fail(f"{VERSION_FILE} is empty")
    errors: list[str] = []
    for directory, name in sorted(EXPECTED.items()):
        manifest = JS_DIR / directory / "package.json"
        if not manifest.is_file():
            errors.append(f"missing {manifest}")
            continue
        data = json.loads(manifest.read_text())
        if data.get("name") != name:
            errors.append(f"{manifest}: name {data.get('name')!r} != {name!r}")
        if data.get("version") != expected_version:
            errors.append(
                f"{manifest}: version {data.get('version')!r} != VERSION {expected_version!r}"
            )
        for scope in ("dependencies", "devDependencies", "optionalDependencies"):
            for dep, spec in (data.get(scope) or {}).items():
                if isinstance(spec, str) and spec.startswith("file:"):
                    target = (JS_DIR / directory / spec.removeprefix("file:")).resolve()
                    try:
                        sibling = target.relative_to(JS_DIR.resolve())
                    except ValueError:
                        errors.append(
                            f"{manifest}: {scope}.{dep} escapes bindings/js: {spec}"
                        )
                        continue
                    if sibling.parts[0] not in EXPECTED:
                        errors.append(
                            f"{manifest}: {scope}.{dep} references {spec}, "
                            "outside the lockstep set"
                        )
    found = {path.parent.name for path in JS_DIR.glob("*/package.json")}
    for extra in sorted(found - set(EXPECTED)):
        errors.append(f"bindings/js/{extra}/package.json is outside the lockstep set")
    if errors:
        for error in errors:
            print(f"check_js_versions: {error}", file=sys.stderr)
        raise SystemExit(1)
    print(
        f"JavaScript packages share lockstep version {expected_version} ({len(EXPECTED)} packages)"
    )


if __name__ == "__main__":
    main()
