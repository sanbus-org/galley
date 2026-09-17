#!/usr/bin/env python3
"""Build merged npm packuments for the static R2 registry.

Layout in the bucket (all under the registry host, no server logic):
  @sanbus/<name> and @sanbus%2F<name>   the packument (both keys: S3-style
                                        hosts disagree on %2F decoding, so
                                        both forms resolve deterministically)
  tarballs/<file>.tgz                   version tarballs (plain names, no
                                        encoding questions by construction)

Rules, in order:
  - Versions come from the input tarballs (the package job built them all
    from one run version; mixed versions fail loud, since the dependency
    graph pins exact versions).
  - Stable versions merge verbatim from npmjs (their tarballs stay on
    npmjs).
  - A version already listed in the R2 base keeps its entry untouched
    (first-write-wins: tarballs are never re-uploaded, so served bytes
    stay bit-identical forever).
  - dist-tags start from npmjs and only gain `dev` (newest -dev.
    version); `latest` is synthesized only when neither source has one.
  - Prune drops hosted `-dev.` versions older than MAX-AGE hours or
    beyond the newest KEEP; their tarballs go on the delete list.
    Anything else is never deleted.
  - Packuments whose canonical form matches the base are not re-uploaded,
    so retries and no-op pushes change nothing.

Usage: build_registry.py --tgz-dir D --packages JSON --out-dir O
         --tarball-base-url U --now ISO --keep N --max-age-hours H
  packages: [{"name": ..., "tgz": path, "base": path-or-null,
              "npmjs": path-or-null}]
  Writes O/<index>.json per package plus O/plan.json:
    {"uploads": [{"key":..., "file":..., "content_type":...,
                  "cache_control":...}],
     "deletes": [key...], "packages": {name: {...per-package notes...}}}
  Packuments are mutable: they upload with `no-cache` so consumers
  revalidate on every install (304 when unchanged). Tarballs are
  immutable and content-addressed by version, so they upload
  `immutable` and may edge-cache forever.
"""

from __future__ import annotations

import base64
import hashlib
import json
import re
import sys
import tarfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import quote, urlparse

MANIFEST_FIELDS = (
    "description",
    "license",
    # Install-significant fields arborist reads from the packument (not
    # the tarball) at resolve/reify time: dropping `bin` silently
    # unlinks every binary on registry installs (file installs still
    # work, which is why this only bites the registry path).
    "bin",
    "dependencies",
    "optionalDependencies",
    "peerDependencies",
    "peerDependenciesMeta",
    "bundleDependencies",
    "deprecated",
    "engines",
    "os",
    "cpu",
)

SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+.*)?$")


def fail(message: str) -> None:
    print(f"build_registry: {message}", file=sys.stderr)
    raise SystemExit(1)


def semver_key(version: str) -> tuple | None:
    """Ordering key, semver-correct for prereleases. None when unparseable."""
    match = SEMVER_RE.match(version)
    if match is None:
        return None
    numbers = tuple(int(group) for group in match.groups()[:3])
    prerelease = match.group(4)
    if prerelease is None:
        return (numbers, (1,))
    identifiers: list[tuple[int, object]] = []
    for identifier in prerelease.split("."):
        if identifier.isdigit():
            identifiers.append((0, int(identifier)))
        else:
            identifiers.append((1, identifier))
    return (numbers, (0, tuple(identifiers)))


def manifest_of(tgz: Path) -> dict:
    try:
        with tarfile.open(tgz, "r:gz") as archive:
            member = archive.getmember("package/package.json")
            extracted = archive.extractfile(member)
            assert extracted is not None
            return json.load(extracted)
    except (tarfile.TarError, KeyError, AssertionError, ValueError) as error:
        fail(f"{tgz}: cannot read package/package.json ({error})")


def file_hashes(path: Path) -> tuple[str, str]:
    """(sha1 hex, sha512-based integrity) of the exact bytes served."""
    digest = hashlib.sha512()
    sha1 = hashlib.sha1()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
            sha1.update(chunk)
    integrity = "sha512-" + base64.b64encode(digest.digest()).decode()
    return sha1.hexdigest(), integrity


def parse_time(stamp: str) -> datetime | None:
    """Parse a packument timestamp. None when missing or unparseable."""
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


def build_package(spec: dict, tarball_base_url: str, now: str, keep: int,
                  max_age_hours: float) -> tuple[dict, dict]:
    name = spec["name"]
    tgz = Path(spec["tgz"])
    manifest = manifest_of(tgz)
    if manifest.get("name") != name:
        fail(f"{tgz}: manifest name {manifest.get('name')!r} != {name!r}")
    version = manifest.get("version")
    if not isinstance(version, str) or not version:
        fail(f"{tgz}: manifest has no usable version")
    shasum, integrity = file_hashes(tgz)
    tarball_url = f"{tarball_base_url}/tarballs/{tgz.name}"

    base: dict = {}
    if spec.get("base"):
        base = json.loads(Path(spec["base"]).read_text())
    npmjs: dict = {}
    if spec.get("npmjs"):
        npmjs = json.loads(Path(spec["npmjs"]).read_text())

    merged: dict[str, dict] = {}
    for source in (npmjs.get("versions", {}), base.get("versions", {})):
        merged.update(source)
    if version in merged:
        print(f"build_registry: {name}@{version} already listed, keeping entry")
    else:
        entry: dict = {"name": name, "version": version}
        for field in MANIFEST_FIELDS:
            if field in manifest:
                entry[field] = manifest[field]
        entry["dist"] = {
            "tarball": tarball_url,
            "integrity": integrity,
            "shasum": shasum,
        }
        merged[version] = entry

    # Prune only what we host: -dev. versions under our tarball prefix.
    def hosted_dev(item: tuple[str, dict]) -> bool:
        ver, meta = item
        tarball = ((meta.get("dist") or {}).get("tarball") or "")
        return "-dev." in ver and tarball.startswith(tarball_base_url + "/tarballs/")

    prunable = [ver for ver, meta in merged.items() if hosted_dev((ver, meta))]
    prunable.sort(key=lambda v: semver_key(v) or ((0, 0, 0), (0, ())), reverse=True)
    # Count prune plus age prune (union): hosted dev versions older than
    # MAX-AGE hours go even when under KEEP, so the packument stops
    # advertising versions the bucket lifecycle already deleted. The
    # version just published is exempt from both; timestamps we cannot
    # parse are kept rather than dropped blind.
    condemned: set[str] = set(prunable[keep:])
    now_parsed = parse_time(now)
    if now_parsed is not None:
        cutoff = now_parsed - timedelta(hours=max_age_hours)
        stamps: dict[str, str] = dict(npmjs.get("time") or {})
        stamps.update(base.get("time") or {})
        for ver in prunable:
            if ver == version:
                continue
            stamp = stamps.get(ver)
            parsed = parse_time(stamp) if isinstance(stamp, str) else None
            if parsed is not None and parsed <= cutoff:
                condemned.add(ver)
    condemned.discard(version)
    dropped = [ver for ver in prunable if ver in condemned]
    dropped_tarballs = [merged[ver]["dist"]["tarball"] for ver in dropped]
    for ver in dropped:
        del merged[ver]

    tags: dict[str, str] = dict(npmjs.get("dist-tags") or base.get("dist-tags") or {})
    dev_versions = sorted(
        (v for v in merged if "-dev." in v),
        key=lambda v: semver_key(v) or ((0, 0, 0), (0, ())),
        reverse=True,
    )
    if dev_versions:
        tags["dev"] = dev_versions[0]
    if "latest" not in tags:
        stables = [v for v in merged if semver_key(v) and semver_key(v)[1] == (1,)]
        if stables:
            tags["latest"] = sorted(stables, key=semver_key, reverse=True)[0]
        elif dev_versions:
            tags["latest"] = dev_versions[0]

    times: dict[str, str] = dict(base.get("time") or {})
    # npmjs owns its per-version stamps, but `modified`/`created` are
    # registry metadata owned here: overlaying them would flap `modified`
    # to npmjs's value on every run and re-upload every packument.
    npmjs_times = dict(npmjs.get("time") or {})
    npmjs_times.pop("modified", None)
    npmjs_times.pop("created", None)
    times.update(npmjs_times)
    base_versions = set((base.get("versions") or {}))
    if version not in base_versions:
        times[version] = now
    for ver in dropped:
        times.pop(ver, None)
    if set(merged) != base_versions or "modified" not in times:
        times["modified"] = now
    if "created" not in times:
        times["created"] = now

    packument: dict = {"name": name}
    description = manifest.get("description") or npmjs.get("description")
    if description:
        packument["description"] = description
    license_value = manifest.get("license") or npmjs.get("license")
    if license_value:
        packument["license"] = license_value
    packument["versions"] = merged
    packument["dist-tags"] = tags
    packument["time"] = times

    notes: dict = {
        "version": version,
        "new": version not in base_versions,
        "pruned": dropped,
        "pruned_tarballs": dropped_tarballs,
        "tags": tags,
    }
    return packument, notes


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--tgz-dir", required=True)
    parser.add_argument("--packages", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--tarball-base-url", required=True)
    parser.add_argument("--now", required=True)
    parser.add_argument("--keep", required=True, type=int)
    parser.add_argument("--max-age-hours", required=True, type=float)
    arguments = parser.parse_args()

    specs = json.loads(Path(arguments.packages).read_text())
    out_dir = Path(arguments.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    keep = max(0, arguments.keep)

    seen_versions = set()
    for spec in specs:
        manifest = manifest_of(Path(spec["tgz"]))
        seen_versions.add(manifest.get("version"))
    if len(seen_versions) != 1:
        fail(f"input tarballs carry mixed versions: {sorted(seen_versions)}")

    # Uploads run tarballs before packuments (every packument only ever
    # references tarballs already stored), deletes last. Collected
    # separately here because the per-package loop below naturally meets
    # the packument before it knows whether its tarball is new.
    plan: dict = {"uploads": [], "deletes": [], "packages": {}}
    tarball_uploads: list = []
    packument_uploads: list = []
    for index, spec in enumerate(specs):
        name = spec["name"]
        packument, notes = build_package(
            spec, arguments.tarball_base_url.rstrip("/"), arguments.now, keep,
            arguments.max_age_hours,
        )
        out_file = out_dir / f"{index}.json"
        canonical = json.dumps(packument, sort_keys=True, separators=(",", ":"))
        base_raw = Path(spec["base"]).read_text() if spec.get("base") else None
        base_canonical = None
        if base_raw:
            try:
                base_canonical = json.dumps(
                    json.loads(base_raw), sort_keys=True, separators=(",", ":")
                )
            except ValueError:
                base_canonical = None
        # Always materialized (dry-run inspection, debugging); uploaded
        # only on change, so no-op pushes stay quiet.
        out_file.write_text(canonical + "\n")
        if canonical != base_canonical:
            packument_uploads.append(
                {
                    "key": name,
                    "file": str(out_file),
                    "content_type": "application/json",
                    "cache_control": "no-cache",
                }
            )
            # S3-style hosts disagree on %2F decoding; publish under both
            # key forms so the encoded and literal routes resolve alike.
            encoded = quote(name, safe="")
            if encoded != name:
                packument_uploads.append(
                    {
                        "key": encoded,
                        "file": str(out_file),
                        "content_type": "application/json",
                        "cache_control": "no-cache",
                    }
                )
        if notes["new"]:
            tgz = Path(spec["tgz"])
            tarball_uploads.append(
                {
                    "key": f"tarballs/{tgz.name}",
                    "file": str(tgz),
                    "content_type": "application/octet-stream",
                    "cache_control": "public, max-age=31536000, immutable",
                }
            )
        for tarball_url in notes["pruned_tarballs"]:
            # Keys come from live dist.tarball URLs of pruned entries, so
            # only our own tarballs can ever land here. urlparse needs a
            # scheme; the URLs we wrote always have one.
            key = urlparse(tarball_url).path.lstrip("/")
            if not key.startswith("tarballs/"):
                fail(f"refusing to delete non-tarball key {key!r}")
            plan["deletes"].append(key)
        plan["packages"][name] = notes

    plan["uploads"] = tarball_uploads + packument_uploads
    (out_dir / "plan.json").write_text(json.dumps(plan, indent=2) + "\n")
    print(f"build_registry: {len(specs)} packuments, "
          f"{len(plan['uploads'])} uploads, {len(plan['deletes'])} deletes")


if __name__ == "__main__":
    main()
