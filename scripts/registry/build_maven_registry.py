#!/usr/bin/env python3
"""Build a static Maven repository leg for Galley Java dev versions.

Layout in the bucket (all under the registry host, no server logic):
  maven/<group-path>/<artifact>/<version>/<artifact>-<version>.jar
  maven/<group-path>/<artifact>/<version>/<artifact>-<version>.pom
  maven/.../<version>/<artifact>-<version>.jar.sha1 (+ .pom.sha1)
  maven/<group-path>/<artifact>/maven-metadata.xml
    the metadata Maven resolves (group + artifact + <latest> + the full
    <versions> list)

Rules, in order:
  - Coordinates come from the input jar's embedded
    META-INF/maven/**/pom.properties (the package job built the jar from
    one run version; anything else fails loud, and filenames are never
    parsed).
  - The .pom is the repo pom re-pinned to the run version through
    scripts/java/pin_pom.py onto a temp copy (never hand-written XML).
  - A version already listed keeps its files untouched
    (first-write-wins: files are never re-uploaded, so served bytes stay
    bit-identical forever).
  - Prune drops listed `-dev.` versions older than MAX-AGE hours or beyond
    the newest KEEP (union), plus listed `-dev.` versions with no hosted
    files left, so the metadata stops advertising versions the bucket
    lifecycle already deleted. Anything else is never deleted (stable
    versions would survive even if one ever landed). The version just
    published is exempt from every prune; timestamps that cannot be
    parsed are kept rather than dropped blind.
  - Metadata identical to the hosted file is not re-uploaded, so retries
    and no-op pushes change nothing; a hosted file that parses but is not
    canonical is repaired.

Usage: build_maven_registry.py --dist-dir D --out-dir O
         --now ISO --keep N --max-age-hours H
         [--base-metadata PATH] [--hosted PATH]
  hosted: a JSON list of {"key":..., "last_modified":...} from a bucket
    listing under the artifact dir; versions with no listed files carry
    no stamps. When --hosted is absent (local runs), age pruning keeps
    everything, only the count prune applies, and the gone rule is
    skipped — unknown hosting must never read as deleted.
  Writes O/metadata.xml, O/<artifact>-<version>.pom (+ .sha1 files) plus
  O/plan.json:
    {"uploads": [{"key":..., "file":..., "content_type":...,
                  "cache_control":...}],
     "deletes": [key...], "packages": {"galley": {...notes...}}}
  Metadata is mutable: it uploads with `no-cache` so Maven revalidates on
  every resolve. Files are immutable and content-addressed by version,
  so they upload `immutable` and may edge-cache forever.
"""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from xml.etree import ElementTree
from xml.sax.saxutils import escape as xml_escape

FILES_PREFIX = "maven/"
METADATA_FILENAME = "maven-metadata.xml"
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
REPO_POM = REPO_ROOT / "bindings" / "java" / "pom.xml"
PIN_POM = REPO_ROOT / "scripts" / "java" / "pin_pom.py"
POM_NAMESPACE = "{http://maven.apache.org/POM/4.0.0}"

VERSION_RE = re.compile(
    r"^(\d+(?:\.\d+)*)(?:-(alpha|beta|rc)\.(\d+))?(?:-dev\.(\d+)\.g([0-9A-Za-z]+))?$"
)
PRE_ORDER = {"alpha": 0, "beta": 1, "rc": 2}


def fail(message: str) -> None:
    print(f"build_maven_registry: {message}", file=sys.stderr)
    raise SystemExit(1)


def version_key(version: str) -> tuple | None:
    """Ordering key, newest last. None when unparseable."""
    match = VERSION_RE.match(version)
    if match is None:
        return None
    release = tuple(int(part) for part in match.group(1).split("."))
    pre_kind, pre_num, dev_run = match.group(2), match.group(3), match.group(4)
    if pre_kind is None:
        # (3, 0) sits above every prerelease kind (alpha=0, beta=1,
        # rc=2), matching the Python sibling: a final release always
        # orders above its own prereleases.
        pre = (3, 0)
    else:
        pre = (PRE_ORDER[pre_kind], int(pre_num))
    if dev_run is None:
        dev = (1, 0)
    else:
        dev = (0, int(dev_run))
    return (release, pre, dev)


def read_coordinates(jar: Path) -> tuple[str, str, str]:
    """Group, artifact, version from the jar's embedded pom.properties."""
    try:
        archive = zipfile.ZipFile(jar)
    except zipfile.BadZipFile as error:
        fail(f"{jar}: not a readable jar ({error})")
    with archive:
        candidates = [
            name
            for name in archive.namelist()
            if name.startswith("META-INF/maven/") and name.endswith("/pom.properties")
        ]
        if len(candidates) != 1:
            fail(
                f"{jar}: expected one META-INF/maven/**/pom.properties, found {sorted(candidates)}"
            )
        properties: dict[str, str] = {}
        with archive.open(candidates[0]) as handle:
            for line in handle.read().decode("utf-8").splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                field, value = line.split("=", 1)
                properties[field.strip()] = value.strip()
    group, artifact, version = (
        properties.get("groupId", ""),
        properties.get("artifactId", ""),
        properties.get("version", ""),
    )
    if not group or not artifact or not version:
        fail(
            f"{jar}: pom.properties carries no usable coordinates: {sorted(properties)}"
        )
    return group, artifact, version


def pinned_pom(version: str, destination: Path) -> tuple[str, str, str]:
    """Re-pin the repo pom to the run version; the pin script is the gate."""
    if not REPO_POM.is_file():
        fail(f"repo pom is absent: {REPO_POM}")
    with tempfile.TemporaryDirectory(prefix="maven-registry-pom") as staging:
        staged = Path(staging) / "pom.xml"
        staged.write_bytes(REPO_POM.read_bytes())
        completed = subprocess.run(
            [sys.executable, str(PIN_POM), str(staged), version],
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            fail(f"pin_pom.py failed: {completed.stderr.strip()}")
        root = ElementTree.parse(str(staged)).getroot()
        coordinates = (
            (root.findtext(f"{POM_NAMESPACE}groupId") or "").strip(),
            (root.findtext(f"{POM_NAMESPACE}artifactId") or "").strip(),
            (root.findtext(f"{POM_NAMESPACE}version") or "").strip(),
        )
        if not coordinates[2]:
            fail(f"pinned pom has no usable version: {destination}")
        destination.write_bytes(staged.read_bytes())
    return coordinates


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


def parse_metadata(text: str) -> tuple[str, str, list[str], str]:
    """Group, artifact, versions, lastUpdated from base metadata XML."""
    try:
        root = ElementTree.fromstring(text)
    except ElementTree.ParseError as error:
        fail(f"base metadata is not parseable XML ({error})")
    if root.tag != "metadata":
        fail(f"base metadata has root {root.tag!r}, expected 'metadata'")
    group = (root.findtext("groupId") or "").strip()
    artifact = (root.findtext("artifactId") or "").strip()
    versioning = root.find("versioning")
    versions: list[str] = []
    last_updated = ""
    if versioning is not None:
        container = versioning.find("versions")
        if container is not None:
            for entry in container.findall("version"):
                if entry.text and entry.text.strip():
                    versions.append(entry.text.strip())
        last_updated = (versioning.findtext("lastUpdated") or "").strip()
    return group, artifact, versions, last_updated


def metadata_document(
    group: str, artifact: str, versions: list[str], latest: str, last_updated: str
) -> str:
    """Canonical metadata bytes. Sorted versions, one shape every run."""
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        "<metadata>",
        f"  <groupId>{xml_escape(group)}</groupId>",
        f"  <artifactId>{xml_escape(artifact)}</artifactId>",
        "  <versioning>",
        f"    <latest>{xml_escape(latest)}</latest>",
        "    <versions>",
    ]
    for version in versions:
        lines.append(f"      <version>{xml_escape(version)}</version>")
    lines += [
        "    </versions>",
        f"    <lastUpdated>{xml_escape(last_updated)}</lastUpdated>",
        "  </versioning>",
        "</metadata>",
        "",
    ]
    return "\n".join(lines)


def file_sha1(path: Path) -> str:
    digest = hashlib.sha1()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def order_key(version: str) -> tuple:
    return version_key(version) or ((0,), (0, 0), (0, 0))


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--dist-dir", required=True)
    parser.add_argument("--out-dir", required=False, default=None)
    parser.add_argument("--now", required=False, default=None)
    parser.add_argument("--keep", required=False, default=None, type=int)
    parser.add_argument("--max-age-hours", required=False, default=None, type=float)
    parser.add_argument("--base-metadata", default=None)
    parser.add_argument("--hosted", default=None)
    parser.add_argument(
        "--print-coordinates",
        action="store_true",
        help="print '<group-path> <artifact> <version>' and exit: the single "
        "coordinate reader shell consumers use instead of re-parsing jars",
    )
    arguments = parser.parse_args()

    dist_dir = Path(arguments.dist_dir)
    entries = sorted(path.name for path in dist_dir.iterdir() if path.is_file())
    jars = [name for name in entries if name.endswith(".jar")]
    if len(jars) != 1 or len(entries) != 1:
        fail(f"expected exactly one jar in {dist_dir}, found {sorted(entries)}")
    jar = dist_dir / jars[0]
    group, artifact, version = read_coordinates(jar)
    group_path = group.replace(".", "/")
    if not group_path or ".." in group_path.split("/"):
        fail(f"{jar}: group {group!r} maps to no usable path")
    if arguments.print_coordinates:
        print(f"{group_path} {artifact} {version}")
        return
    for field in ("out_dir", "now", "keep", "max_age_hours"):
        if getattr(arguments, field) is None:
            fail(f"--{field.replace('_', '-')} is required without --print-coordinates")
    artifact_dir = f"{FILES_PREFIX}{group_path}/{artifact}/"
    metadata_key = f"{artifact_dir}{METADATA_FILENAME}"
    jar_filename = f"{artifact}-{version}.jar"
    pom_filename = f"{artifact}-{version}.pom"

    base_versions: list[str] = []
    base_last_updated = ""
    if arguments.base_metadata:
        base_raw = Path(arguments.base_metadata).read_text()
        base_group, base_artifact, base_versions, base_last_updated = parse_metadata(
            base_raw
        )
        if (base_group, base_artifact) != (group, artifact):
            fail(
                f"base metadata is {base_group}:{base_artifact}, "
                f"input jar is {group}:{artifact}"
            )

    hosted: dict[str, str] = {}
    if arguments.hosted:
        listing = json.loads(Path(arguments.hosted).read_text())
        for record in listing:
            key = record.get("key", "")
            stamp = record.get("last_modified", "")
            if isinstance(key, str) and isinstance(stamp, str):
                hosted[key] = stamp
        if base_versions and not hosted:
            fail("base metadata lists versions but the bucket listing is empty")

    # Merge: versions already listed stay listed verbatim.
    merged = list(dict.fromkeys(base_versions + [version]))
    new = version not in base_versions
    if not new:
        print(
            f"build_maven_registry: {artifact}@{version} already listed, keeping files"
        )

    # Prune only what we host: `-dev.` versions under our artifact dir.
    def hosted_dev(candidate: str) -> bool:
        return "-dev." in candidate

    stamps_by_version: dict[str, list[str]] = {}
    for key, stamp in hosted.items():
        if not key.startswith(artifact_dir) or key == metadata_key:
            continue
        rest = key[len(artifact_dir) :]
        version_dir, _, filename = rest.partition("/")
        if not version_dir or not filename:
            continue
        stamps_by_version.setdefault(version_dir, []).append(stamp)

    dev_versions = sorted(
        (candidate for candidate in merged if hosted_dev(candidate)),
        key=order_key,
        reverse=True,
    )
    keep = max(0, arguments.keep)
    condemned: set[str] = set(dev_versions[keep:])
    now_parsed = parse_time(arguments.now)
    if now_parsed is not None:
        cutoff = now_parsed - timedelta(hours=arguments.max_age_hours)
        for candidate in dev_versions:
            if candidate == version:
                continue
            stamps = [
                parse_time(stamp) for stamp in stamps_by_version.get(candidate, [])
            ]
            parsed = [stamp for stamp in stamps if stamp is not None]
            # Timestamps that cannot be parsed are kept, never dropped blind;
            # versions with no stamps at all are kept here too (the gone
            # rule below handles the files-already-deleted case).
            if parsed and all(stamp <= cutoff for stamp in parsed):
                condemned.add(candidate)
    # Versions whose files are already gone stop being advertised, so the
    # metadata never points at what the bucket lifecycle already deleted.
    # The version just published is exempt everywhere: its files only land
    # after this merge. Without hosting knowledge (--hosted absent) unknown
    # must never read as deleted, so the gone rule is skipped entirely.
    hosting_known = arguments.hosted is not None
    gone = (
        {
            candidate
            for candidate in dev_versions
            if candidate != version and candidate not in stamps_by_version
        }
        if hosting_known
        else set()
    )
    condemned.discard(version)
    dropped = [
        candidate
        for candidate in dev_versions
        if candidate in condemned or candidate in gone
    ]
    kept = [
        candidate
        for candidate in merged
        if candidate not in condemned and candidate not in gone
    ]

    ordered = sorted(kept, key=order_key)
    latest = max(ordered, key=order_key)
    if set(kept) == set(base_versions) and base_last_updated:
        last_updated = base_last_updated
    else:
        moment = parse_time(arguments.now)
        if moment is None:
            fail(f"cannot stamp metadata from unparseable --now {arguments.now!r}")
        last_updated = moment.astimezone(timezone.utc).strftime("%Y%m%d%H%M%S")
    document = metadata_document(group, artifact, ordered, latest, last_updated)

    out_dir = Path(arguments.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    metadata_file = out_dir / "metadata.xml"
    metadata_file.write_text(document)

    plan: dict = {"uploads": [], "deletes": [], "packages": {}}
    file_uploads: list = []
    staged_names: list[str] = []
    if new:
        pom_file = out_dir / pom_filename
        pinned = pinned_pom(version, pom_file)
        if pinned != (group, artifact, version):
            fail(
                f"pinned pom is {pinned[0]}:{pinned[1]}:{pinned[2]}, "
                f"input jar is {group}:{artifact}:{version}"
            )
        jar_digest = file_sha1(jar)
        pom_digest = file_sha1(pom_file)
        jar_sha_file = out_dir / f"{jar_filename}.sha1"
        pom_sha_file = out_dir / f"{pom_filename}.sha1"
        jar_sha_file.write_text(jar_digest + "\n")
        pom_sha_file.write_text(pom_digest + "\n")
        version_dir = f"{artifact_dir}{version}/"
        staged = [
            (str(jar), f"{version_dir}{jar_filename}", "application/java-archive"),
            (str(pom_file), f"{version_dir}{pom_filename}", "application/xml"),
            (str(jar_sha_file), f"{version_dir}{jar_filename}.sha1", "text/plain"),
            (str(pom_sha_file), f"{version_dir}{pom_filename}.sha1", "text/plain"),
        ]
        for local, key, content_type in staged:
            file_uploads.append(
                {
                    "key": key,
                    "file": local,
                    "content_type": content_type,
                    "cache_control": "public, max-age=31536000, immutable",
                }
            )
        staged_names = [jar_filename, pom_filename]
    metadata_uploads: list = []
    # Compare against the raw fetched bytes (like both siblings), so a
    # hosted file that parses but is not canonical gets repaired instead
    # of silently kept.
    reupload_metadata = True
    if arguments.base_metadata:
        reupload_metadata = document != Path(arguments.base_metadata).read_text()
    if reupload_metadata:
        metadata_uploads.append(
            {
                "key": metadata_key,
                "file": str(metadata_file),
                "content_type": "application/xml",
                "cache_control": "no-cache",
            }
        )
    for candidate in dropped:
        for filename in (
            f"{artifact}-{candidate}.jar",
            f"{artifact}-{candidate}.pom",
            f"{artifact}-{candidate}.jar.sha1",
            f"{artifact}-{candidate}.pom.sha1",
        ):
            key = f"{artifact_dir}{candidate}/{filename}"
            if not key.startswith(FILES_PREFIX):
                fail(f"refusing to delete non-file key {key!r}")
            plan["deletes"].append(key)
    plan["uploads"] = file_uploads + metadata_uploads
    plan["packages"][artifact] = {
        "version": version,
        "new": new,
        "pruned": sorted(dropped),
        "files": sorted(staged_names),
        "latest": latest,
    }
    (out_dir / "plan.json").write_text(json.dumps(plan, indent=2) + "\n")
    print(
        f"build_maven_registry: {artifact}@{version}, "
        f"{len(plan['uploads'])} uploads, {len(plan['deletes'])} deletes"
    )


if __name__ == "__main__":
    main()
