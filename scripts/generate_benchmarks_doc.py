#!/usr/bin/env python3
"""
scripts/generate_benchmarks_doc.py

Reads Galley benchmark results from benchmark_results/ and third-party results
from third_party/parser-benchmark/benchmark_results/, then produces two documents:
BENCHMARKS.md (external comparison against third-party parsers) and
BENCHMARKS_INTERNAL.md (Galley's own per-grammar throughput for tracking progress
and regressions).
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ─────────────────────────────────────────────
# Data models
# ─────────────────────────────────────────────


@dataclass
class ParserResult:
    name: str  # "LL", "Tree-sitter (C)", etc.
    mode: str  # "no-ast", "CST", etc.
    throughput: float  # MB/s
    duration_ns: int
    parsed_mb: float
    nodes: Optional[int]
    skipped: bool = False
    skip_reason: str = ""

    @property
    def display_name(self) -> str:
        return f"{self.name} ({self.mode})" if self.mode else self.name


@dataclass
class BenchmarkFile:
    path: str
    source: str  # "galley" or "third_party"
    language: str  # "json", "galley", "augmented-json", etc.
    input_file: str  # e.g. "languages/json/samples/code-01.json"
    ast_mode: str  # "no-ast", "no-procedures", "" (third_party)
    terminal_ast: str  # "ast-for-terminals", "no-ast-for-terminals", ""
    results: List[ParserResult] = field(default_factory=list)


# ─────────────────────────────────────────────
# Parsers
# ─────────────────────────────────────────────


def _int_from_str(s: str) -> int:
    return int(s.replace(",", "").replace(" ", ""))


def _float_from_str(s: str) -> float:
    return float(s.replace(",", "").split()[0])


def parse_result_block(header: str, body: str, source: str) -> ParserResult:
    """Parse a single [Name - Mode] or [Name] block."""
    # Header formats:
    #   third_party: [Tree-sitter (C) - CST]
    #   galley:      [LL]  or  [LR]
    header = header.strip("[]")
    if " - " in header:
        name, mode = header.split(" - ", 1)
    else:
        name = header
        mode = ""

    if "SKIPPED" in body:
        reason = re.search(r"SKIPPED.*", body)
        return ParserResult(
            name=name,
            mode=mode,
            throughput=0.0,
            duration_ns=0,
            parsed_mb=0.0,
            nodes=None,
            skipped=True,
            skip_reason=reason.group(0) if reason else "SKIPPED",
        )

    throughput = 0.0
    duration_ns = 0
    parsed_mb = 0.0
    nodes: Optional[int] = None

    for line in body.splitlines():
        line = line.strip()
        if line.startswith("Throughput:"):
            throughput = _float_from_str(line.split(":", 1)[1].strip().split()[0])
        elif line.startswith("Duration:"):
            raw = line.split(":", 1)[1].strip().replace(" ns", "")
            duration_ns = _int_from_str(raw)
        elif line.startswith("Parsed bytes:"):
            raw = line.split(":", 1)[1].strip().split()[0]
            parsed_mb = _float_from_str(raw)
        elif line.startswith("Nodes allocated:"):
            raw = line.split(":", 1)[1].strip()
            nodes = _int_from_str(raw) if raw != "0" else 0

    return ParserResult(
        name=name,
        mode=mode,
        throughput=throughput,
        duration_ns=duration_ns,
        parsed_mb=parsed_mb,
        nodes=nodes,
    )


def parse_benchmark_file(path: Path) -> Optional[BenchmarkFile]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()

    meta: dict[str, str] = {}
    sep_idx = -1
    for i, line in enumerate(lines):
        if line.startswith("---"):
            sep_idx = i
            break
        if ":" in line:
            k, _, v = line.partition(":")
            meta[k.strip()] = v.strip()

    if sep_idx < 0:
        return None

    body = "\n".join(lines[sep_idx + 1 :])

    # Determine source from path
    rel = str(path)
    if "/third_party/" in rel:
        source = "third_party"
    else:
        source = "galley"

    # Parse result blocks: lines starting with [
    blocks = re.split(r"(?=^\[)", body, flags=re.MULTILINE)
    results: List[ParserResult] = []
    for block in blocks:
        block = block.strip()
        if not block or not block.startswith("["):
            continue
        m = re.match(r"(\[[^\]]+\])(.*)", block, re.DOTALL)
        if not m:
            continue
        header, content = m.group(1), m.group(2)
        results.append(parse_result_block(header, content, source))

    return BenchmarkFile(
        path=str(path),
        source=source,
        language=meta.get("Language", ""),
        input_file=meta.get("Input", ""),
        ast_mode=meta.get("AST Mode", ""),
        terminal_ast=meta.get("Terminal AST", ""),
        results=results,
    )


def collect_all(root: Path) -> List[BenchmarkFile]:
    files: List[BenchmarkFile] = []
    for p in sorted(root.rglob("*.txt")):
        bf = parse_benchmark_file(p)
        if bf and bf.results:
            files.append(bf)
    return files


# ─────────────────────────────────────────────
# Rendering helpers
# ─────────────────────────────────────────────

AST_MODE_LABEL: Dict[str, str] = {
    "no-ast": "no-ast",
    "no-procedures": "with-ast",
}

BAR_WIDTH = 40
BAR_CHAR = "█"
HALF_CHAR = "▌"
EMPTY_CHAR = "░"


def bar_chart(entries: List[Tuple[str, float]], unit: str = "MB/s") -> str:
    """Render a horizontal bar chart. entries = [(label, value), ...]"""
    if not entries:
        return ""
    max_val = max(v for _, v in entries)
    if max_val == 0:
        return ""
    max_label = max(len(l) for l, _ in entries)
    lines = []
    for label, val in sorted(entries, key=lambda x: x[1], reverse=True):
        filled = int(BAR_WIDTH * val / max_val)
        bar = BAR_CHAR * filled + EMPTY_CHAR * (BAR_WIDTH - filled)
        lines.append(f"  {label:<{max_label}}  {bar}  {val:>8.1f} {unit}")
    return "\n".join(lines)


def _visible_width(s: str) -> int:
    """Width of a cell as rendered: markdown `**` and backticks take no room."""
    return len(s.replace("**", "").replace("`", ""))


def _pad_visible(s: str, width: int) -> str:
    return s + " " * max(0, width - _visible_width(s))


def md_table(headers: List[str], rows: List[List[str]]) -> str:
    """Render a Markdown table with raw-pipe alignment by visible width."""
    widths = [
        max(
            _visible_width(h),
            max((_visible_width(r[i]) for r in rows), default=0),
        )
        for i, h in enumerate(headers)
    ]
    sep = "| " + " | ".join("-" * w for w in widths) + " |"
    header_row = (
        "| "
        + " | ".join(_pad_visible(h, widths[i]) for i, h in enumerate(headers))
        + " |"
    )
    data_rows = [
        "| "
        + " | ".join(_pad_visible(str(r[i]), widths[i]) for i in range(len(headers)))
        + " |"
        for r in rows
    ]
    return "\n".join([header_row, sep] + data_rows)


def fmt_throughput(mbps: float) -> str:
    if mbps == 0:
        return "—"
    if mbps >= 1000:
        return f"**{mbps:,.0f} MB/s**"
    return f"{mbps:,.1f} MB/s"


def fmt_ns(ns: int) -> str:
    if ns == 0:
        return "—"
    if ns >= 1_000_000_000:
        return f"{ns / 1e9:.2f} s"
    if ns >= 1_000_000:
        return f"{ns / 1e6:.1f} ms"
    return f"{ns / 1e3:.1f} µs"


# ─────────────────────────────────────────────
# Analysis helpers
# ─────────────────────────────────────────────


# Comparison labels for the Galley rows timed inside the submodule harness.
SUBMODULE_GALLEY_MODES = {
    "LL No AST": "Galley LL  (no-ast)",
    "LL AST": "Galley LL  (with-ast)",
    "LR No AST": "Galley LR  (no-ast)",
    "LR AST": "Galley LR  (with-ast)",
}


def submodule_galley_entries(
    tp: Dict[str, ParserResult],
) -> Dict[str, ParserResult]:
    """Return {comparison label: result} for Galley rows timed in the submodule.

    The submodule benchmarks Galley itself in the same harness on the same
    inputs as every competitor, so these are the apples-to-apples figures for
    the comparison. (`third_party_results` already keeps the best run per
    name+mode across datasets.)
    """
    entries: Dict[str, ParserResult] = {}
    for r in tp.values():
        if r.name == "Galley (Zig)" and r.mode in SUBMODULE_GALLEY_MODES:
            entries[SUBMODULE_GALLEY_MODES[r.mode]] = r
    return entries


def third_party_results(files: List[BenchmarkFile]) -> Dict[str, ParserResult]:
    """Return {display_name: result} from third_party data (best throughput per name+mode)."""
    best: Dict[str, ParserResult] = {}
    for bf in files:
        if bf.source != "third_party":
            continue
        if "smoke" in bf.path.lower():
            continue
        for r in bf.results:
            if r.skipped:
                continue
            key = r.display_name
            if key not in best or r.throughput > best[key].throughput:
                best[key] = r
    return best


# ─────────────────────────────────────────────
# Section generators
# ─────────────────────────────────────────────


def section_bundled_grammar_coverage() -> str:
    """Summarize bundled benchmark grammars without implying cross-language equivalence."""
    headers = ["Grammar", "What it exercises", "Parsers"]
    rows = [
        [
            "JSON",
            "Recursive data, strings, numbers, arrays, objects, third-party comparison baseline",
            "LL + LR",
        ],
        [
            "Lisp",
            "Nested S-expressions, symbols, strings, integers, multiple top-level forms",
            "LL",
        ],
        [
            "Lua",
            "Keyword-led statements, functions, calls, returns, keyed table constructors",
            "LL",
        ],
        [
            "Galley Grammar",
            "The `.grm` language used to define Galley grammars",
            "LL + LR",
        ],
    ]

    return "\n".join(
        [
            "## Bundled Grammar Coverage\n",
            "Galley benchmarks track parser throughput across grammar shapes. "
            "JSON is also the head-to-head comparison target because mature third-party parsers "
            "exist for it (see [BENCHMARKS.md](BENCHMARKS.md)); Lisp, Lua, and the grammar parser "
            "exercise different language shapes and should not be read as direct comparisons "
            "against JSON.\n",
            md_table(headers, rows),
            "",
        ]
    )


def section_json_comparison(files: List[BenchmarkFile]) -> str:
    """Head-to-head JSON parsing with proper category grouping and framing."""
    # One table per dataset: {dataset: [(name, mode, mbps)]} using raw harness
    # names. Every parser in a table ran on that exact input in the same
    # harness, so rows within a table are directly comparable; tables are not
    # comparable with each other. Columns are split at render time.
    datasets: Dict[str, List[Tuple[str, str, float]]] = defaultdict(list)
    for bf in files:
        if bf.source != "third_party":
            continue
        if "smoke" in bf.path.lower():
            continue
        dataset = Path(bf.path).name
        if dataset.endswith(".txt"):
            dataset = dataset[: -len(".txt")]
        for r in bf.results:
            if r.skipped or r.throughput <= 0:
                continue
            datasets[dataset].append((r.name, r.mode, r.throughput))

    lines: List[str] = []
    lines.append("## JSON Parsing — Throughput Comparison\n")

    lines.append(
        """\
### What are we comparing?

The parsers below fall into two distinct categories:

**General-purpose parser generators / tools** — you describe a grammar and the tool
produces a parser for any language matching that grammar. Bison, LALRPOP, Nom, and
Tree-sitter all belong here. **Galley is in this category.**

**Specialised JSON libraries** — simdjson, yyjson, and RapidJSON are hand-written
libraries optimised exclusively for JSON. They exploit structural properties unique
to JSON with SIMD intrinsics and two-pass parsing that is not generalisable to
arbitrary grammars. They are reference points showing what a single-purpose native
implementation can achieve, not direct competitors to a parser generator.
"""
    )

    if not datasets:
        lines.append("_No results available._\n")
        return "\n".join(lines)

    # Headline ratios use the canonical twitter.json fixture; every dataset
    # below carries its own table for the full picture.
    headline_key = "twitter.json" if "twitter.json" in datasets else sorted(datasets)[0]
    headline = {(parser, mode): mbps for parser, mode, mbps in datasets[headline_key]}

    def h(parser: str, mode: str) -> float:
        return headline.get((parser, mode), 0.0)

    galley_ll = h("Galley (Zig)", "LL No AST")
    galley_ll_ast = h("Galley (Zig)", "LL AST")
    lalrpop = h("LALRPOP (Rust)", "No AST")
    bison = h("Bison / Flex (C)", "No AST")
    nom = h("Nom (Rust)", "AST")
    rapidjson_sax = h("RapidJSON (C++)", "SAX Validate")
    if galley_ll > 0 and lalrpop > 0 and bison > 0 and nom > 0:
        lines.append(
            f"""\
> On `{headline_key}`, **within the parser-generator category**, Galley LL is
> **{galley_ll / lalrpop:.1f}× faster than LALRPOP** (Rust),
> **{galley_ll / bison:.1f}× faster than Bison/Flex** (C), and
> **{galley_ll / nom:.1f}× faster than Nom** (Rust) — with full AST construction
> ({galley_ll_ast:.0f} MB/s) still outpacing LALRPOP's non-AST mode ({lalrpop:.0f} MB/s).
"""
        )
    if galley_ll > 0 and rapidjson_sax > 0:
        gap = abs(1 - galley_ll / rapidjson_sax) * 100
        lines.append(
            f"""\
Notably, Galley's no-ast throughput of **{galley_ll:.0f} MB/s** is within ~{gap:.0f}% of
RapidJSON's SAX mode ({rapidjson_sax:.0f} MB/s) — a hand-tuned C++ library with SIMD
acceleration — despite Galley being a general-purpose parser generated from a grammar
specification with no JSON-specific optimisations.
"""
        )

    lines.append(
        "Each table below runs every parser on one shared input in the same harness "
        "(2 warmup + best of 5 runs) — Galley included. Grammars and tree shapes "
        "still differ per parser (see Methodology), so small gaps should not be "
        "over-read.\n"
    )

    headers = ["Parser", "Lang", "SIMD", "Category", "Mode", "Throughput"]
    for dataset in sorted(datasets):
        rows = sorted(
            (comparison_row(n, m, v) for n, m, v in datasets[dataset]),
            key=lambda row: row[5],
            reverse=True,
        )
        lines.append(f"### `{dataset}`\n")
        lines.append(
            md_table(
                headers,
                [
                    [parser, lang, simd, cat, mode, fmt_throughput(mbps)]
                    for parser, lang, simd, cat, mode, mbps in rows
                ],
            )
        )
        lines.append("")

    return "\n".join(lines)


# Display columns for one harness row: language leaves the parser name, SIMD
# mirrors the harness table marker, and Mode uses a shared vocabulary so rows
# stay comparable instead of each carrying its own bespoke mode string.
COMPARISON_PARSERS = {
    "Bison / Flex (C)": (
        "Bison / Flex",
        "C",
        "",
        "General",
        {
            "No AST": "No AST",
            "Simple AST": "AST (simple)",
            "Advanced AST": "AST (advanced)",
            "Payload AST": "AST (payload)",
        },
    ),
    "LALRPOP (Rust)": (
        "LALRPOP",
        "Rust",
        "",
        "General",
        {"No AST": "No AST", "AST": "AST"},
    ),
    "Nom (Rust)": ("Nom", "Rust", "", "General", {"AST": "AST"}),
    "Tree-sitter (C)": ("Tree-sitter", "C", "", "General", {"CST": "CST"}),
    "simdjson (C++)": (
        "simdjson",
        "C++",
        "✓",
        "JSON-specific",
        {"Validate": "Validate", "DOM AST": "AST"},
    ),
    "yyjson (C)": ("yyjson", "C", "✓", "JSON-specific", {"DOM AST": "AST"}),
    "RapidJSON (C++)": (
        "RapidJSON",
        "C++",
        "✓",
        "JSON-specific",
        {"DOM AST": "AST", "SAX Validate": "SAX"},
    ),
}


def comparison_row(
    name: str, mode: str, mbps: float
) -> Tuple[str, str, str, str, str, float]:
    """Split a harness row into Parser/Lang/SIMD/Category/Mode columns."""
    if name == "Galley (Zig)":
        # Harness modes are "LL No AST", "LL AST", "LR No AST", "LR AST".
        variant, _, rest = mode.partition(" ")
        return (f"Galley {variant}", "Zig", "", "General", rest, mbps)
    if name in COMPARISON_PARSERS:
        parser, lang, simd, cat, modes = COMPARISON_PARSERS[name]
        return (parser, lang, simd, cat, modes.get(mode, mode), mbps)
    return (name, "", "", "General", mode, mbps)


GRAMMAR_DESCRIPTIONS: Dict[str, str] = {
    "json": (
        "Standard JSON (RFC 8259). This is the benchmark JSON grammar: it parses full "
        "recursive JSON while keeping the grammar factored with few non-terminals for "
        "maximum generated parser throughput."
    ),
    "json-structured-ast": (
        "A full JSON grammar with extra intermediate non-terminals for a more structured "
        "AST shape. It is useful when tree shape matters more than headline throughput."
    ),
    "json-augmented": (
        "JSON extended with a custom prefix notation: `*value` and `(expr)` wrappers. "
        "Demonstrates how a standard grammar can be incrementally extended with new syntax "
        "without touching the original JSON rules — an LL-only grammar due to prefix ambiguity."
    ),
    "galley": (
        "Galley's own grammar file format (`.grm`). This is the self-hosting grammar: "
        "Galley uses itself to parse the grammar files that define its languages, including "
        "this one. Exercises nested rules, procedure annotations, comment syntax, and "
        "indentation-sensitive constructs."
    ),
    "lisp": (
        "A Lisp grammar that exercises lists, symbols, numbers, strings, reader macros, "
        "comments, vectors, arrays, and multiple top-level forms."
    ),
    "lua": (
        "A Lua grammar that exercises keyword-led statements, function declarations, "
        "returns, function-call expressions, integer literals, strings, comments, "
        "and keyed table constructors."
    ),
    "indentation": (
        "A procedure-free indentation-sensitive grammar whose delimiter tokens make "
        "every decision point unambiguous with one token of lookahead. Used to exercise "
        "and benchmark indentation handling in LL and LR parsers."
    ),
}


GRAMMAR_SECTION_ORDER = [
    "lua",
    "lisp",
    "json",
    "galley",
    "json-augmented",
    "json-structured-ast",
    "indentation",
]


GRAMMAR_SECTION_LABELS = {
    "lua": "Lua",
    "lisp": "Lisp",
    "json": "JSON",
    "galley": "Galley",
    "json-augmented": "JSON Augmented",
    "json-structured-ast": "JSON with Structured AST",
    "indentation": "Indentation",
}


def section_galley_language(files: List[BenchmarkFile], grammar: str) -> str:
    """Per-language breakdown for Galley across all configurations."""
    lines: List[str] = []

    label = GRAMMAR_SECTION_LABELS.get(
        grammar,
        grammar.replace("_", " ").replace("-", " ").title(),
    )
    lines.append(f"## {label}\n")

    desc = GRAMMAR_DESCRIPTIONS.get(grammar)
    if desc:
        lines.append(f"_{desc}_\n")

    # Group by (ast_mode, terminal_ast, input_file)
    configs: Dict[Tuple, Dict[str, List[ParserResult]]] = defaultdict(
        lambda: defaultdict(list)
    )

    for bf in files:
        if bf.source != "galley" or bf.language != grammar:
            continue
        key = (bf.ast_mode, bf.terminal_ast, bf.input_file)
        for r in bf.results:
            if not r.skipped and r.throughput > 0:
                configs[key][r.name].append(r)

    if not configs:
        lines.append("_No results available._\n")
        return "\n".join(lines)

    seen_configs: Dict[Tuple[str, str, str], Tuple[float, float]] = {}
    for (ast_mode, terminal_ast, input_file), parsers in sorted(configs.items()):
        ll_best = max((r.throughput for r in parsers.get("LL", [])), default=0)
        lr_best = max((r.throughput for r in parsers.get("LR", [])), default=0)
        seen_configs[(ast_mode, terminal_ast, input_file)] = (
            ll_best,
            lr_best,
        )

    def ast_sym(mode: str) -> str:
        return "✓" if mode == "no-procedures" else "✗"

    def term_sym(t: str) -> str:
        return "✓" if t == "ast-for-terminals" else "✗"

    inputs = sorted({input_file for (_, _, input_file) in seen_configs})

    def input_configs_for(input_file: str):
        return [
            (ast_mode, terminal_ast, ll, lr)
            for (ast_mode, terminal_ast, cfg_input), (
                ll,
                lr,
            ) in seen_configs.items()
            if cfg_input == input_file
        ]

    # Columns with no data anywhere in this section stay hidden; they reappear
    # automatically when a run produces such data.
    section_show_term = any(
        terminal_ast == "ast-for-terminals"
        for input_file in inputs
        for (_, terminal_ast, _, _) in input_configs_for(input_file)
    )
    if section_show_term:
        lines.append(
            "_AST = build syntax tree · Term. = include terminal nodes in tree_\n"
        )
    else:
        lines.append("_AST = build syntax tree_\n")

    for input_file in inputs:
        rel_input = input_file
        lines.append(f"### `{rel_input}`\n")

        rows = []
        bar_entries: List[Tuple[str, float]] = []
        input_configs = input_configs_for(input_file)
        show_term = any(t == "ast-for-terminals" for (_, t, _, _) in input_configs)
        show_lr = any(lr > 0 for (_, _, _, lr) in input_configs)

        headers = ["AST"]
        if show_term:
            headers.append("Term.")
        headers.append("LL")
        if show_lr:
            headers.extend(["LR", "LL/LR"])

        for ast_mode, terminal_ast, ll, lr in sorted(input_configs):
            row = [ast_sym(ast_mode)]
            if show_term:
                row.append(term_sym(terminal_ast))
            row.append(fmt_throughput(ll))
            label = f"{ast_sym(ast_mode)}ast"
            if show_term:
                label += f" {term_sym(terminal_ast)}term"
            bar_entries.append((f"LL  {label}", ll))
            if show_lr:
                ratio = f"{ll / lr:.2f}×" if lr > 0 else "—"
                row.extend([fmt_throughput(lr), ratio])
                bar_entries.append((f"LR  {label}", lr))
            rows.append(row)

        lines.append(md_table(headers, rows))
        lines.append("")

        lines.append("```")
        lines.append(bar_chart(bar_entries))
        lines.append("```\n")

    return "\n".join(lines)


def section_methodology_galley() -> str:
    return """\
## Methodology

- Benchmarks are run by `scripts/benchmark.py`.
- Each result file lives under `benchmark_results/galley/{grammar}/{ast_mode}/{terminal_ast}/{input_lang}/{input_file}.txt`.
- **Parsed bytes** reflects repeated parsing of the input until a stable total is reached.
- **LL** = generated LL parser; **LR** = generated LR parser.
- Each figure uses 6 measured process runs with the first discarded.

### Environment
Results will vary by machine. All numbers were recorded on an Apple M1 Pro.
"""


def section_methodology_third_party() -> str:
    return """\
## Methodology

- Benchmarks are run by the `third_party/parser-benchmark/` submodule.
- Each parser runs 2 untimed warmup iterations plus 5 timed iterations per
  dataset; the best run is reported.
- Results are written below `third_party/parser-benchmark/benchmark_results/json/`.
- The standard `twitter`, `canada`, and `citm_catalog` inputs are downloaded on
  demand, checksum-verified, ignored external assets.
- No benchmark input is stored in either repository.
- Every parser except Tree-sitter validates string escapes and UTF-8 with the
  same strictness as Galley's unicode grammar: the Flex lexer, both LALRPOP
  grammars, and Nom were tightened to match, and RapidJSON runs with encoding
  validation enabled. Tree-sitter runs upstream as-is, with laxer string
  rules.
- Parsers included: Tree-sitter (C, CST), Bison/Flex (C, multiple AST modes),
  LALRPOP (Rust, Non-AST & AST), simdjson (C++, Validate & DOM), Nom (Rust, AST),
  RapidJSON (C++, DOM & SAX), yyjson (C, DOM AST).
- Galley rows are timed in this same harness from its unicode JSON grammar.
  Galley's long-term tracking numbers across all grammars live in
  `BENCHMARKS_INTERNAL.md` and come from `scripts/benchmark.py`, a different
  harness — expect them to differ.

### Environment
Results will vary by machine. All numbers were recorded on an Apple M1 Pro.
"""


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    results_root = repo_root / "benchmark_results"

    if not results_root.exists():
        print(f"ERROR: {results_root} not found", file=sys.stderr)
        sys.exit(1)

    files = collect_all(results_root)
    third_party_results_root = (
        repo_root / "third_party" / "parser-benchmark" / "benchmark_results"
    )
    if third_party_results_root.exists():
        files.extend(collect_all(third_party_results_root))
    if not files:
        print("ERROR: No benchmark result files found", file=sys.stderr)
        sys.exit(1)

    # Discover available galley grammars. Show broadly recognized languages first,
    # then project-specific and regression grammars.
    discovered_grammars = {
        bf.language for bf in files if bf.source == "galley" and bf.language
    }
    ordered_grammars = [
        grammar for grammar in GRAMMAR_SECTION_ORDER if grammar in discovered_grammars
    ]
    ordered_grammars.extend(
        grammar
        for grammar in sorted(discovered_grammars)
        if grammar not in ordered_grammars
    )

    comparison_parts: List[str] = []

    comparison_parts.append("""\
# Benchmarks

> Generated by `scripts/generate_benchmarks_doc.py`. Re-run to refresh after new benchmark runs.

This document compares **Galley** (the generated LL/LR parser in this repository) against
widely-used third-party parsers and parser-generators on JSON inputs.

Unless noted otherwise, results were recorded on an **Apple M1 Pro**.

---
""")

    comparison_parts.append(section_json_comparison(files))
    comparison_parts.append("---\n")

    comparison_parts.append(section_methodology_third_party())

    comparison_path = repo_root / "BENCHMARKS.md"
    comparison_path.write_text("\n".join(comparison_parts), encoding="utf-8")
    print(f"Written: {comparison_path}")

    internal_parts: List[str] = []

    internal_parts.append("""\
# Internal Benchmarks

> Generated by `scripts/generate_benchmarks_doc.py`. Re-run to refresh after new benchmark runs.

This document tracks **Galley**'s own parser throughput across the bundled grammars
and configurations. Use it to follow progress and catch performance regressions;
for comparison against third-party parsers see [BENCHMARKS.md](BENCHMARKS.md).

Unless noted otherwise, results were recorded on an **Apple M1 Pro**.

---
""")

    # Grammar breadth overview
    internal_parts.append(section_bundled_grammar_coverage())
    internal_parts.append("---\n")

    # Per-grammar Galley breakdown
    for grammar in ordered_grammars:
        internal_parts.append(section_galley_language(files, grammar))
        internal_parts.append("---\n")

    # Methodology
    internal_parts.append(section_methodology_galley())

    internal_path = repo_root / "BENCHMARKS_INTERNAL.md"
    internal_path.write_text("\n".join(internal_parts), encoding="utf-8")
    print(f"Written: {internal_path}")

    # Summary stats
    tp = third_party_results(files)
    galley_ll = submodule_galley_entries(tp).get("Galley LL  (no-ast)")
    if galley_ll:
        best_tp = max(tp.values(), key=lambda r: r.throughput) if tp else None
        print(f"\nGalley LL best JSON:  {galley_ll.throughput:,.1f} MB/s")
        if best_tp:
            print(
                f"Best third-party:     {best_tp.throughput:,.1f} MB/s  ({best_tp.display_name})"
            )


if __name__ == "__main__":
    main()
