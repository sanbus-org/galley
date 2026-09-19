#!/usr/bin/env python3
"""Build a PEP 503 simple index for Galley Python dev versions.

Layout in the bucket (all under the registry host, no server logic):
  simple/galley/index.html   the project page pip fetches (plus the
                             slashless and slash forms: R2 serves exact
                             keys only, no index.html fallback)
  simple/index.html          the root index (same variant scheme)
  python-files/<file>.whl/.tar.gz     version files (plain names, no
                                      encoding questions by construction)

Rules, in order:
  - The version comes from the input distributions (the package job built
    sdist+wheel from one run version; mixed versions fail loud).
  - A version already listed keeps its entries untouched
    (first-write-wins: files are never re-uploaded, so served bytes stay
    bit-identical forever).
  - Prune drops listed `.dev` versions older than MAX-AGE hours or beyond
    the newest KEEP; their files go on the delete list. Anything else is
    never deleted (stable versions would survive even if one ever landed).
  - Index pages whose canonical form matches the base are not re-uploaded,
    so retries and no-op pushes change nothing.

Usage: build_python_registry.py --dist-dir D --out-dir O
         --host U --now ISO --keep N --max-age-hours H
         [--base-index PATH] [--base-root-index PATH]
  Writes O/project.html, O/root.html plus O/plan.json:
    {"uploads": [{"key":..., "file":..., "content_type":...,
                  "cache_control":...}],
     "deletes": [key...], "packages": {"galley": {...notes...}}}
  Index pages are mutable: they upload with `no-cache` so pip revalidates
  on every install. Files are immutable and content-addressed by version,
  so they upload `immutable` and may edge-cache forever.
"""

from __future__ import annotations

import hashlib
import html
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from html.parser import HTMLParser
from pathlib import Path

PROJECT = "galley"
DIST_PREFIX = PROJECT + "-"
FILES_PREFIX = "python-files/"

VERSION_RE = re.compile(r"^(\d+(?:\.\d+)*)(?:(a|b|rc)(\d+))?(?:\.dev(\d+))?$")
PRE_ORDER = {"a": 0, "b": 1, "rc": 2}


def fail(message: str) -> None:
    print(f"build_python_registry: {message}", file=sys.stderr)
    raise SystemExit(1)


def version_key(version: str) -> tuple | None:
    """Ordering key, PEP 440-correct for our shapes. None when unparseable."""
    match = VERSION_RE.match(version)
    if match is None:
        return None
    release = tuple(int(part) for part in match.group(1).split("."))
    pre_kind, pre_num, dev_num = match.group(2), match.group(3), match.group(4)
    if pre_kind is None:
        pre = (3, 0)
    else:
        pre = (PRE_ORDER[pre_kind], int(pre_num))
    if dev_num is None:
        dev = (1, 0)
    else:
        dev = (0, int(dev_num))
    return (release, pre, dev)


def filename_version(filename: str) -> str:
    """Version carried by an sdist/wheel filename. Fails loud when alien."""
    if not filename.startswith(DIST_PREFIX):
        fail(f"{filename}: unexpected distribution prefix")
    rest = filename[len(DIST_PREFIX) :]
    if filename.endswith(".tar.gz"):
        version = rest[: -len(".tar.gz")]
        if not version or "-" in version:
            fail(f"{filename}: cannot read version")
        return version
    if filename.endswith(".whl"):
        # {dist}-{version}(-{build})?-{py}-{abi}-{plat}.whl; versions
        # never contain dashes, so the version is the first field.
        parts = rest.split("-")
        if len(parts) < 4 or not parts[0]:
            fail(f"{filename}: cannot read version")
        return parts[0]
    fail(f"{filename}: expected .tar.gz or .whl")


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_time(stamp: str) -> datetime | None:
    """Parse an upload timestamp. None when missing or unparseable."""
    try:
        candidate = stamp.strip()
        if candidate.endswith("Z"):
            candidate = candidate[:-1] + "+00:00"
        parsed = datetime.fromisoformat(candidate)
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed
    except ValueError:
        return None


class IndexParser(HTMLParser):
    """Collect file anchors: filename, sha256 fragment, upload time."""

    def __init__(self) -> None:
        super().__init__()
        self.entries: list[dict] = []
        self._current: dict | None = None
        self._text: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag != "a":
            return
        attributes = dict(attrs)
        href = attributes.get("href") or ""
        self._current = {
            "href": href,
            "upload_time": attributes.get("data-upload-time") or "",
        }
        self._text = []

    def handle_data(self, data: str) -> None:
        if self._current is not None:
            self._text.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag != "a" or self._current is None:
            return
        text = "".join(self._text).strip()
        href = self._current["href"]
        filename = text or href.split("#")[0].rsplit("/", 1)[-1]
        filename = filename.strip()
        sha256 = ""
        if "#sha256=" in href:
            sha256 = href.split("#sha256=", 1)[1].split("&")[0].split()[0]
        if filename.endswith((".whl", ".tar.gz")):
            self.entries.append(
                {
                    "filename": filename,
                    "sha256": sha256,
                    "upload_time": self._current["upload_time"],
                }
            )
        self._current = None
        self._text = []


def parse_index(text: str) -> list[dict]:
    parser = IndexParser()
    parser.feed(text)
    return parser.entries


def project_page(project: str, rows: list[tuple[str, str, str]]) -> str:
    """Canonical project page. Rows: (filename, href, upload_time)."""
    lines = [
        "<!DOCTYPE html>",
        "<html>",
        '  <head><meta charset="utf-8">'
        f"<title>Links for {html.escape(project)}</title></head>",
        "  <body>",
        f"    <h1>Links for {html.escape(project)}</h1>",
    ]
    for filename, href, upload_time in sorted(rows):
        lines.append(
            f'    <a href="{html.escape(href, quote=True)}"'
            f' data-upload-time="{html.escape(upload_time, quote=True)}">'
            f"{html.escape(filename)}</a><br/>"
        )
    lines += ["  </body>", "</html>", ""]
    return "\n".join(lines)


def root_page(host: str) -> str:
    base = host.rstrip("/")
    return "\n".join(
        [
            "<!DOCTYPE html>",
            "<html>",
            '  <head><meta charset="utf-8"><title>Simple index</title></head>',
            "  <body>",
            "    <h1>Simple index</h1>",
            f'    <a href="{html.escape(base + "/simple/galley/")}">{html.escape(PROJECT)}</a><br/>',
            "  </body>",
            "</html>",
            "",
        ]
    )


def content_type_for(filename: str) -> str:
    if filename.endswith(".tar.gz"):
        return "application/gzip"
    if filename.endswith(".whl"):
        return "application/octet-stream"
    return "application/octet-stream"


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--dist-dir", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--now", required=True)
    parser.add_argument("--keep", required=True, type=int)
    parser.add_argument("--max-age-hours", required=True, type=float)
    parser.add_argument("--base-index", default=None)
    parser.add_argument("--base-root-index", default=None)
    arguments = parser.parse_args()

    host = arguments.host.rstrip("/")
    dist_dir = Path(arguments.dist_dir)
    filenames = sorted(p.name for p in dist_dir.iterdir() if p.is_file())
    if not filenames:
        fail(f"no distributions in {dist_dir}")
    if len(filenames) != 2 or not (
        sum(n.endswith(".tar.gz") for n in filenames) == 1
        and sum(n.endswith(".whl") for n in filenames) == 1
    ):
        fail(f"expected sdist+wheel in {dist_dir}, found {sorted(filenames)}")
    versions = {filename_version(name) for name in filenames}
    if len(versions) != 1:
        fail(f"input distributions carry mixed versions: {sorted(versions)}")
    version = next(iter(versions))

    base_entries: list[dict] = []
    base_raw: str | None = None
    if arguments.base_index:
        base_raw = Path(arguments.base_index).read_text()
        base_entries = parse_index(base_raw)
    base_root_raw: str | None = None
    if arguments.base_root_index:
        base_root_raw = Path(arguments.base_root_index).read_text()

    # Merge: versions already listed keep their entries untouched.
    merged: dict[str, dict] = {}
    for entry in base_entries:
        merged.setdefault(entry["filename"], entry)
    listed_versions = {filename_version(name) for name in merged}
    new = version not in listed_versions
    if not new:
        print(
            f"build_python_registry: {PROJECT}@{version} already listed, keeping entries"
        )
    else:
        for name in filenames:
            merged[name] = {
                "filename": name,
                "sha256": file_sha256(dist_dir / name),
                "upload_time": arguments.now,
            }

    # Prune only what we host: `.dev` versions under our files prefix.
    # Every href we write points under FILES_PREFIX, so every parsed entry
    # qualifies by construction; the `.dev` guard keeps a hypothetical
    # stable file from ever landing on the delete list.
    def hosted_dev(ver: str) -> bool:
        return ".dev" in ver

    by_version: dict[str, list[str]] = {}
    for name in merged:
        by_version.setdefault(filename_version(name), []).append(name)
    dev_versions = sorted(
        (v for v in by_version if hosted_dev(v)),
        key=lambda v: version_key(v) or ((0,), (0, 0), (0, 0)),
        reverse=True,
    )
    keep = max(0, arguments.keep)
    condemned: set[str] = set(dev_versions[keep:])
    now_parsed = parse_time(arguments.now)
    if now_parsed is not None:
        cutoff = now_parsed - timedelta(hours=arguments.max_age_hours)
        for ver in dev_versions:
            if ver == version:
                continue
            stamps = [
                parse_time(merged[name].get("upload_time", ""))
                for name in by_version[ver]
            ]
            parsed = [s for s in stamps if s is not None]
            # Timestamps we cannot parse are kept rather than dropped blind.
            if parsed and all(stamp <= cutoff for stamp in parsed):
                condemned.add(ver)
    condemned.discard(version)
    dropped = [ver for ver in dev_versions if ver in condemned]
    dropped_files = sorted(name for ver in dropped for name in by_version[ver])
    for ver in dropped:
        for name in by_version[ver]:
            del merged[name]

    files_base = f"{host}/{FILES_PREFIX.rstrip('/')}"
    rows = [
        (
            name,
            f"{files_base}/{name}#sha256={merged[name]['sha256']}",
            merged[name].get("upload_time", "") or arguments.now,
        )
        for name in merged
    ]
    # Kept entries without a hash (hand-edited base) fail loud: pip
    # needs the fragment, and silently serving hashless links would be
    # worse than refusing.
    for name, href, _ in rows:
        if href.endswith("#sha256="):
            fail(f"{name}: listed entry carries no sha256")
    page = project_page(PROJECT, rows)
    root = root_page(host)

    out_dir = Path(arguments.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    project_file = out_dir / "project.html"
    root_file = out_dir / "root.html"
    project_file.write_text(page)
    root_file.write_text(root)

    plan: dict = {"uploads": [], "deletes": [], "packages": {}}
    file_uploads: list = []
    if new:
        for name in filenames:
            file_uploads.append(
                {
                    "key": f"{FILES_PREFIX}{name}",
                    "file": str(dist_dir / name),
                    "content_type": content_type_for(name),
                    "cache_control": "public, max-age=31536000, immutable",
                }
            )
    page_uploads: list = []
    if base_raw is None or page != base_raw:
        # R2 serves exact keys only (no index.html fallback), and
        # clients vary (trailing slash or not), so every form carries
        # the same bytes.
        for key in (
            "simple/galley/index.html",
            "simple/galley/",
            "simple/galley",
        ):
            page_uploads.append(
                {
                    "key": key,
                    "file": str(project_file),
                    "content_type": "text/html",
                    "cache_control": "no-cache",
                }
            )
    if base_root_raw is None or root != base_root_raw:
        for key in ("simple/index.html", "simple/", "simple"):
            page_uploads.append(
                {
                    "key": key,
                    "file": str(root_file),
                    "content_type": "text/html",
                    "cache_control": "no-cache",
                }
            )
    for name in dropped_files:
        key = f"{FILES_PREFIX}{name}"
        if not key.startswith(FILES_PREFIX):
            fail(f"refusing to delete non-file key {key!r}")
        plan["deletes"].append(key)
    plan["uploads"] = file_uploads + page_uploads
    plan["packages"][PROJECT] = {
        "version": version,
        "new": new,
        "pruned": sorted(dropped),
        "files": sorted(filenames),
    }
    (out_dir / "plan.json").write_text(json.dumps(plan, indent=2) + "\n")
    print(
        f"build_python_registry: {PROJECT}@{version}, "
        f"{len(plan['uploads'])} uploads, {len(plan['deletes'])} deletes"
    )


if __name__ == "__main__":
    main()
