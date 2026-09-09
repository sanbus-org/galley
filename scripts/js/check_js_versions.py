#!/usr/bin/env python3
"""JavaScript package-name and file:-dependency gate.

Version fields are owned by scripts/check_versions.py. This script polices
npm names, the closed set of bindings/js/*/package.json, and that internal
`file:` dependencies stay inside that set. A new package directory with a
package.json fails until it is added to EXPECTED.

Run: python3 scripts/js/check_js_versions.py (also wired into the
bindings-consistency CI job).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
JS_DIR = REPO_ROOT / "bindings" / "js"

# Directory -> expected npm package name. Closed set on purpose.
EXPECTED: dict[str, str] = {
    "core": "@sanbus/galley-core",
    "node": "@sanbus/galley-node",
    "bun": "@sanbus/galley-bun",
    "deno": "@sanbus/galley-deno",
    "wasm": "@sanbus/galley-wasm",
    "universal": "@sanbus/galley",
}

# Example manifests (repo-relative) -> expected name. Version fields on
# these files are gated by scripts/check_versions.py (they must omit one).
EXAMPLES: dict[str, str] = {
    "examples/js/node/package.json": "galley-js-node-example",
    "examples/js/bun/package.json": "galley-js-bun-example",
    "examples/js/wasm/package.json": "galley-js-wasm-example",
}


def main() -> None:
    errors: list[str] = []
    for directory, name in sorted(EXPECTED.items()):
        manifest = JS_DIR / directory / "package.json"
        if not manifest.is_file():
            errors.append(f"missing {manifest}")
            continue
        data = json.loads(manifest.read_text())
        if data.get("name") != name:
            errors.append(f"{manifest}: name {data.get('name')!r} != {name!r}")
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
    for relative, name in sorted(EXAMPLES.items()):
        manifest = REPO_ROOT / relative
        if not manifest.is_file():
            errors.append(f"missing {manifest}")
            continue
        data = json.loads(manifest.read_text())
        if data.get("name") != name:
            errors.append(f"{manifest}: name {data.get('name')!r} != {name!r}")
    if errors:
        for error in errors:
            print(f"check_js_versions: {error}", file=sys.stderr)
        raise SystemExit(1)
    print(f"JavaScript package names match the closed set ({len(EXPECTED)} packages)")


if __name__ == "__main__":
    main()
