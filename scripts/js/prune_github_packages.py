#!/usr/bin/env python3
"""Keep the newest KEEP dev versions of each @sanbus-org/* package on GitHub
Packages, deleting older ones. Only versions containing `-dev.` are ever
candidates; anything else is left alone by construction.

GitHub deletion has no maintainer-count or age criteria (only a 5,000
downloads cap on public versions, which dev builds never approach), so
unlike the npmjs prune this is exact, not best-effort: API/auth failures
are fatal, while a version that is already gone (404) is skipped.

Auth: PACKAGES_TOKEN, a classic PAT with read:packages and
delete:packages (the Packages REST API does not accept GITHUB_TOKEN).
DRY_RUN=1 lists what would go, deleting nothing.

Run: python3 scripts/js/prune_github_packages.py
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
JS_DIR = REPO_ROOT / "bindings" / "js"
API = "https://api.github.com"
ORG = "sanbus-org"
KEEP = int(os.environ.get("KEEP_DEV_VERSIONS", "20"))
DRY_RUN = os.environ.get("DRY_RUN", "0") == "1"


def fail(message: str) -> None:
    print(f"prune_github_packages: {message}", file=sys.stderr)
    raise SystemExit(1)


def api(method: str, path: str, token: str) -> object:
    request = urllib.request.Request(
        API + path,
        method=method,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(request) as response:
            return json.load(response) if method == "GET" else None
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        body = error.read().decode()[:300]
        fail(f"{method} {path}: HTTP {error.code}: {body}")


def package_names() -> list[str]:
    names = []
    for manifest in sorted(JS_DIR.glob("*/package.json")):
        if manifest.parent.name in ("test-fixture",):
            continue
        data = json.loads(manifest.read_text())
        name = data.get("name", "")
        if name.startswith("@sanbus-org/"):
            names.append(name)
        elif name.startswith("@sanbus/"):
            names.append("@sanbus-org/" + name.removeprefix("@sanbus/"))
    return names


def versions(package: str, token: str) -> list[dict] | None:
    """All versions, newest first. None when the package is not there yet."""
    # Scoped npm names go URL-encoded; fall back to the bare name, which
    # some API surfaces accept, before concluding the package is missing.
    candidates = [
        urllib.parse.quote(package, safe=""),
        urllib.parse.quote(package.split("/", 1)[1], safe=""),
    ]
    for candidate in candidates:
        found = api(
            "GET",
            f"/orgs/{ORG}/packages/npm/{candidate}/versions?per_page=100",
            token,
        )
        if found is not None:
            if candidate != candidates[0]:
                print(f"prune_github_packages: {package} resolves as {candidate}")
            return sorted(found, key=lambda v: v["created_at"], reverse=True)
    return None


def main() -> None:
    token = os.environ.get("PACKAGES_TOKEN", "")
    if not token:
        fail("PACKAGES_TOKEN is unset (classic PAT with read:packages, delete:packages)")
    deleted = 0
    for package in package_names():
        all_versions = versions(package, token)
        if all_versions is None:
            print(f"prune_github_packages: {package} not on GitHub Packages yet, skipping")
            continue
        dev = [v for v in all_versions if "-dev." in v["name"]]
        if len(all_versions) == 100:
            print(
                f"prune_github_packages: {package}: hit the 100-version page "
                "limit; older pages may hide prunable versions"
            )
        drop = dev[KEEP:]
        print(
            f"prune_github_packages: {package}: "
            f"{len(all_versions)} versions ({len(dev)} dev), dropping {len(drop)}"
        )
        for version in drop:
            label = f"{package}@{version['name']}"
            if DRY_RUN:
                print(f"prune_github_packages: would delete {label}")
                continue
            api(
                "DELETE",
                f"/orgs/{ORG}/packages/npm/"
                f"{urllib.parse.quote(package, safe='')}/versions/{version['id']}",
                token,
            )
            print(f"prune_github_packages: deleted {label}")
            deleted += 1
    print(f"prune_github_packages: deleted {deleted} dev versions")


if __name__ == "__main__":
    main()
