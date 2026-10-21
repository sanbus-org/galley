#!/usr/bin/env python3
"""Repository size report: lines of code, comments and blanks by area.

Counts git-tracked files only, so build outputs, caches and installed
packages never enter. Submodules (third_party/parser-benchmark) are not
Galley's code and stay out; lock files are generated and stay out.

tokei classifies and counts every file it knows: it parses string literals,
so a comment marker inside a string is code. Galley grammars (.grm) are
unknown to tokei and counted here: a line whose first non-blank character
is `#` is a comment.

Each file has an area (core, one binding, languages, ...), a role (source or
test) and a kind: code, docs (Markdown and plain text, reported as lines),
data (language samples and fixtures) or config (TOML, YAML, ZON,
package JSON). The code tables
count code kinds only, so prose and sample inputs never inflate them.

Requires tokei (brew install tokei).
Run: python3 scripts/line_counts.py [--top N]
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath

REPO_ROOT = Path(__file__).resolve().parent.parent

DOCS_LANGUAGES = {"Markdown", "Plain Text"}
CONFIG_LANGUAGES = {"TOML", "YAML", "XML", "Makefile", "CMake"}
DATA_LANGUAGES = {"JSON", "SVG", "HTML", "CSS"}
GRAMMAR = "Galley grammar"
# tokei names `.tmpl` Templ; the one tracked template renders Go.
LANGUAGE_NAMES = {"Templ": "Go template"}
EXCLUDED_NAMES = {"Cargo.lock", "package-lock.json"}
JS_RUNTIMES = ("core", "node", "deno", "bun", "wasm")
TEST_DIRECTORIES = {"tests", "test", "test-fixture", "test-fixture-second", "testfixture"}


@dataclass
class Counts:
    files: int = 0
    code: int = 0
    comments: int = 0
    blanks: int = 0

    @property
    def lines(self) -> int:
        return self.code + self.comments + self.blanks

    def add(self, other: "Counts") -> None:
        self.files += other.files
        self.code += other.code
        self.comments += other.comments
        self.blanks += other.blanks


@dataclass
class FileRecord:
    path: PurePosixPath
    language: str
    counts: Counts
    area: str = ""
    detail: str = ""
    role: str = ""
    kind: str = ""
    extra: dict = field(default_factory=dict)


def fail(message: str) -> None:
    print(f"line_counts: {message}", file=sys.stderr)
    raise SystemExit(1)


def tracked_files() -> list[str]:
    """Tracked blobs, without submodule entries."""
    listing = subprocess.run(
        ["git", "ls-files", "-s", "-z"], cwd=REPO_ROOT, check=True, capture_output=True, text=True
    ).stdout
    files = []
    for entry in listing.split("\0"):
        if not entry:
            continue
        metadata, path = entry.split("\t", 1)
        if metadata.split()[0] == "160000":
            continue
        if PurePosixPath(path).name in EXCLUDED_NAMES:
            continue
        if (REPO_ROOT / path).is_file():
            files.append(path)
    return files


def tokei_records(paths: list[str]) -> list[FileRecord]:
    if shutil.which("tokei") is None:
        fail("tokei not found; install it with `brew install tokei`")
    report = subprocess.run(
        ["tokei", "--files", "--output", "json", "--", *paths],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    records = []
    for language, entry in json.loads(report).items():
        if language == "Total":
            continue
        for file_report in entry["reports"]:
            stats = file_report["stats"]
            counts = Counts(1, stats["code"], stats["comments"], stats["blanks"])
            # Embedded languages (code blocks in Markdown, for example) are
            # reported as blobs inside their file; count them with the file.
            for blob in stats.get("blobs", {}).values():
                counts.code += blob["code"]
                counts.comments += blob["comments"]
                counts.blanks += blob["blanks"]
            name = PurePosixPath(file_report["name"].removeprefix("./"))
            records.append(FileRecord(name, LANGUAGE_NAMES.get(language, language), counts))
    return records


def grammar_record(path: str) -> FileRecord:
    counts = Counts(files=1)
    for line in (REPO_ROOT / path).read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped:
            counts.blanks += 1
        elif stripped.startswith("#"):
            counts.comments += 1
        else:
            counts.code += 1
    return FileRecord(PurePosixPath(path), GRAMMAR, counts)


def classify(record: FileRecord) -> None:
    """Sets the record's area, detail (sub-area), role and kind from its path."""
    parts = record.path.parts
    top = parts[0]
    second = parts[1] if len(parts) > 2 else ""

    if top == "src":
        record.area = "core"
        record.detail = second or "(root)"
    elif top == "bindings":
        if second in {"c", "python", "go", "java", "rust", "js"}:
            record.area = f"bindings/{second}"
            if second == "js":
                runtime = parts[2] if len(parts) > 3 else ""
                record.detail = runtime if runtime in JS_RUNTIMES else "shared"
        else:
            record.area = "bindings/shared"
    elif top == "languages":
        record.area = "languages"
        record.detail = second
    elif top in {"tests", "examples", "scripts", "docs"}:
        record.area = top
    elif top in {"build", ".github"} or record.path.name.startswith("build"):
        record.area = "build"
    else:
        record.area = "root"

    is_test = (
        record.detail == "tests"
        or any(part in TEST_DIRECTORIES for part in parts[:-1])
        or record.path.name.endswith("_test.go")
        or record.path.name.startswith("test_")
        or (record.area.startswith("bindings/java") and "src/test" in str(record.path))
    )
    record.role = "test" if is_test or record.area == "tests" else "source"

    # JSON outside languages/ is package and compiler configuration.
    if record.language == "JSON" and record.area != "languages":
        record.kind = "config"
    elif "samples" in parts or record.language in DATA_LANGUAGES:
        record.kind = "data"
    elif record.language in DOCS_LANGUAGES:
        record.kind = "docs"
    elif record.language in CONFIG_LANGUAGES or record.path.suffix == ".zon":
        record.kind = "config"
    else:
        record.kind = "code"


def percent(part: int, whole: int) -> str:
    return f"{100 * part / whole:5.1f}%" if whole else "    -"


def with_percent(part: int, whole: int) -> str:
    """`part/percent`: the count and its share of `whole`."""
    return f"{part}/{percent(part, whole).strip()}"


def print_table(title: str, rows: list[tuple[str, Counts]], total: Counts) -> None:
    """Code, comments and blanks carry their percent of the row's lines;
    share is the row's lines as a percent of the table's total lines."""
    print(f"\n{title}")
    header = (
        f"  {'':28} {'files':>6} {'lines':>9} {'share':>7} {'code':>15} {'comments':>14} {'blanks':>13}"
    )
    rule = "  " + "-" * (len(header) - 2)
    print(header)
    print(rule)

    def line(label: str, counts: Counts) -> str:
        return (
            f"  {label:28} {counts.files:6} {counts.lines:9} {percent(counts.lines, total.lines):>7}"
            f" {with_percent(counts.code, counts.lines):>15}"
            f" {with_percent(counts.comments, counts.lines):>14}"
            f" {with_percent(counts.blanks, counts.lines):>13}"
        )

    for label, counts in rows:
        print(line(label, counts))
    print(rule)
    print(line("total", total))


def print_roles(title: str, rows: list[tuple[str, Counts, Counts]]) -> None:
    print(f"\n{title}")
    header = f"  {'':28} {'source code':>12} {'test code':>10} {'test share':>11}"
    print(header)
    print("  " + "-" * (len(header) - 2))
    for label, source, test in rows:
        print(f"  {label:28} {source.code:12} {test.code:10} {percent(test.code, source.code + test.code):>11}")


def print_line_table(title: str, rows: list[tuple[str, Counts]]) -> None:
    """Share is the row's lines as a percent of the table's total lines."""
    print(f"\n{title}")
    header = f"  {'':28} {'files':>6} {'lines':>9} {'share':>7}"
    print(header)
    print("  " + "-" * (len(header) - 2))
    total = Counts()
    for _, counts in rows:
        total.add(counts)
    for label, counts in rows:
        print(f"  {label:28} {counts.files:6} {counts.lines:9} {percent(counts.lines, total.lines):>7}")


def summed(records: list[FileRecord], key) -> dict[str, Counts]:
    groups: dict[str, Counts] = defaultdict(Counts)
    for record in records:
        groups[key(record)].add(record.counts)
    return groups


def total_of(records: list[FileRecord]) -> Counts:
    total = Counts()
    for record in records:
        total.add(record.counts)
    return total


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--top", type=int, default=15, help="largest code files to list (0 for none)")
    arguments = parser.parse_args()

    paths = tracked_files()
    grammars = [path for path in paths if path.endswith(".grm")]
    records = tokei_records([path for path in paths if not path.endswith(".grm")])
    records += [grammar_record(path) for path in grammars]
    for record in records:
        classify(record)

    code = [record for record in records if record.kind == "code"]
    area_order = ["core"] + sorted({r.area for r in code if r.area.startswith("bindings/")}) + [
        "languages", "tests", "examples", "scripts", "build", "docs", "root"
    ]

    print("Galley repository size (git-tracked files; third_party submodule and lock files excluded)")

    by_area = summed(code, lambda r: r.area)
    print_table(
        "Code by area (code kinds only: no prose, samples or config)",
        [(area, by_area[area]) for area in area_order if area in by_area],
        total_of(code),
    )

    def role_row(label: str, selected: list[FileRecord]) -> tuple[str, Counts, Counts]:
        return (
            label,
            total_of([r for r in selected if r.role == "source"]),
            total_of([r for r in selected if r.role == "test"]),
        )

    print_roles(
        "Source versus tests (code lines)",
        [role_row(area, [r for r in code if r.area == area]) for area in area_order if area in by_area]
        + [
            role_row("all bindings", [r for r in code if r.area.startswith("bindings/")]),
            role_row("total", code),
        ],
    )

    bindings = [r for r in code if r.area.startswith("bindings/")]
    by_binding_role = summed(bindings, lambda r: f"{r.area.removeprefix('bindings/')} {r.role}")
    rows = []
    for area in area_order:
        if not area.startswith("bindings/"):
            continue
        name = area.removeprefix("bindings/")
        for role in ("source", "test"):
            if f"{name} {role}" in by_binding_role:
                rows.append((f"{name} {role}", by_binding_role[f"{name} {role}"]))
    print_table("Bindings: source and tests", rows, total_of(bindings))

    javascript = [r for r in code if r.area == "bindings/js"]
    by_runtime = summed(javascript, lambda r: f"{r.detail} {r.role}")
    print_table(
        "JavaScript bindings by package",
        sorted(by_runtime.items(), key=lambda item: item[0]),
        total_of(javascript),
    )

    core = [r for r in code if r.area == "core"]
    by_core = summed(core, lambda r: r.detail)
    print_table("Core (src/) by directory", sorted(by_core.items(), key=lambda item: -item[1].code), total_of(core))

    by_language = summed(code, lambda r: r.language)
    print_table(
        "Code by language",
        sorted(by_language.items(), key=lambda item: -item[1].code),
        total_of(code),
    )

    others = [r for r in records if r.kind != "code"]
    for kind, title in (
        ("docs", "Docs (Markdown and plain text) by area"),
        ("config", "Config (TOML, YAML, XML, ZON, package JSON, Make) by area"),
        ("data", "Data (language samples and fixtures, web assets) by area"),
    ):
        by_area_of_kind = summed([r for r in others if r.kind == kind], lambda r: r.area)
        print_line_table(title, sorted(by_area_of_kind.items(), key=lambda item: -item[1].lines))

    if arguments.top > 0:
        print(f"\nLargest {arguments.top} code files")
        for record in sorted(code, key=lambda r: -r.counts.code)[: arguments.top]:
            print(f"  {record.counts.code:7} code  {record.counts.lines:7} lines  {record.path}")


if __name__ == "__main__":
    main()
