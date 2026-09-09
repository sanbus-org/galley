#!/usr/bin/env python3
"""The product version: contents of the root VERSION file.

Manifests in git carry the sentinel 0.0.0 instead. Publish scripts pin a
temp copy to this value. A VERSION equal to the sentinel is refused so it
cannot be tagged or shipped.
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
VERSION_FILE = REPO_ROOT / "VERSION"
SENTINEL = "0.0.0"


def product_version() -> str:
    text = VERSION_FILE.read_text() if VERSION_FILE.is_file() else ""
    version = text.strip()
    if not version:
        print("product_version: VERSION is empty", file=sys.stderr)
        raise SystemExit(1)
    if version == SENTINEL:
        print(
            f"product_version: VERSION must not be the manifest sentinel {SENTINEL}",
            file=sys.stderr,
        )
        raise SystemExit(1)
    return version


if __name__ == "__main__":
    print(product_version())
