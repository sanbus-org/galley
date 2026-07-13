<picture>
  <source media="(prefers-color-scheme: dark)" srcset="resources/banner-dark.webp">
  <source media="(prefers-color-scheme: light)" srcset="resources/banner-light.webp">
  <img alt="Galley — Directly encoded speed. Zero boilerplate." src="resources/banner-light.webp">
</picture>

# Galley

> **Alpha** — interfaces and grammar format may change between releases.

A parser generator and high-performance parser runtime written in [Zig](https://ziglang.org). Galley reads a grammar definition (`.grm` file), generates a native Zig parser, and produces recursive-descent and recursive-ascent parsers that run at **hundreds of megabytes per second** with zero heap allocation during parsing.

---

## Documentation

Full user guides and architectural documentation are available online at:
👉 **[sanbus-org.github.io/galley](https://sanbus-org.github.io/galley/)**

* **[Getting Started](https://sanbus-org.github.io/galley/getting_started)** — Installation, requirements, and running your first parser.
* **[Included Languages](https://sanbus-org.github.io/galley/languages)** — Reference implementations including JSON, Augmented JSON, Lisp, Lua, and the self-hosting Galley grammar parser.
* **[Configuration & Flags](https://sanbus-org.github.io/galley/configuration)** — Complete list of generator CLI and runtime compiler flags.
* **[Writing a Language](https://sanbus-org.github.io/galley/writing_a_language)** — Creating new grammars, directory layout, and compiling custom targets.
* **[Using Galley from Another Project](docs/using-galley.md)** — Consuming the generator API and generated parser modules from Zig projects.
* **[Reduction Procedures](https://sanbus-org.github.io/galley/procedures)** — Writing Zig hooks to manipulate ASTs, handle state, and clean up nodes.
* **[Testing](docs/testing.md)** — Running standalone suites, focused generated-parser cases, and typed test filters.
* **[Architecture](https://sanbus-org.github.io/galley/architecture)** — Under the hood of Galley's stack-overflow recovery, lexer-less design, and self-hosting roadmap.
* **[AST Allocations](https://sanbus-org.github.io/galley/ast_node_allocations)** — AST node pool optimizations and top-down vs. bottom-up allocation limits.
* **[Benchmarks](https://sanbus-org.github.io/galley/benchmarks)** — Precision benchmarking guidelines and throughput metrics.

For a local, up-to-date comparison against third-party parsers see [BENCHMARKS.md](BENCHMARKS.md).

---

## Quick Start

### Prerequisites

* [Zig 0.16+](https://ziglang.org/download/) — Native compiler toolchain

### Compile & Run a Bundled Parser

```sh
# 1. Generate the Zig parser for JSON.
zig build
./zig-out/bin/galley --parser-type ll languages/json

# 2. Build exactly that parser, then run it.
zig build -Doptimize=ReleaseFast ll-json
./zig-out/bin/ll-json languages/json/samples/code-01.json
```

---

## Benchmarked Grammar Coverage

For current Apple M1 Pro throughput numbers across all bundled grammars and the JSON
third-party comparison, see [BENCHMARKS.md](BENCHMARKS.md).

---

## License

MIT © 2026 Sassan Haradji
