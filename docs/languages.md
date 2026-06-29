# Included Languages

## Table of Contents
- [Overview](#overview)
- [Bundled Grammars](#bundled-grammars)
  - [JSON (`languages/json`)](#json-languagesjson)
  - [Augmented JSON (`languages/augmented-json`)](#augmented-json-languagesaugmented-json)
  - [Flat JSON (`languages/flat_json`)](#flat-json-languagesflat_json)
  - [Grammar Parser (`languages/grammar`)](#grammar-parser-languagesgrammar)
- [Choosing Between LL and LR](#choosing-between-ll-and-lr)
- [Building and Running Included Languages](#building-and-running-included-languages)

---

## Overview

Galley ships with several ready-to-use grammar definitions located in the `languages/` directory. These bundled languages serve both as comprehensive benchmarks for parsing speed and as architectural reference implementations for defining your own grammars.

---

## Bundled Grammars

### JSON (`languages/json`)
The standard RFC 8259 JSON implementation. It supports full recursive object and array structures, floating-point numbers, unicode escape sequences, and string content literals.
- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.
- **Hooks:** Implements `@drop_children`, `@drop_self`, and `@replace_with_children` in `procedures.zig` to keep memory allocations minimal during AST generation.
- **Test Inputs:** Contains `sample-code.json` and `large-sample-code.json`.

### Augmented JSON (`languages/augmented-json`)
An extended JSON variant designed to test extreme recursion depths and stress-test the parser's stack overflow recovery mechanisms. It introduces special grouping syntax (`*(...)` and `(...)`) that allows deeply nested structures without exceeding memory limits.
- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.
- **Hooks:** Demonstrates advanced reduction hooking and stack management.

### Flat JSON (`languages/flat_json`)
A streamlined JSON grammar variant simplified for flat key-value structures. It serves as a great lightweight starting point if you want to understand standard tokenization and string matching rules without recursive complexity.
- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.

### Grammar Parser (`languages/grammar`)
The self-hosting definition of Galley's own `.grm` syntax! This language defines the exact structure of rule definitions, alternatives (`|`), variable symbols, quoted literals, and `@` annotations used across the compiler.
- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.

---

## Choosing Between LL and LR

When working with or creating languages in Galley, you can choose between two parsing paradigms:

1. **LL(k) Top-Down Parsing (`ll.grm`)**:
   - Generates recursive-descent parsing tables.
   - Ideal for clear, human-readable grammars where rules naturally decompose from top to bottom.
   - Requires eliminating left-recursion (e.g. rewrite `Expr | Expr "+" Number` to right-recursive or iterative form).

2. **LR / LALR Bottom-Up Parsing (`lr.grm`)**:
   - Generates deterministic shift-reduce state machines.
   - Easily handles left-recursive rules and complex expressions without restructuring.
   - Often produces highly optimized state transitions for dense programming languages.

---

## Building and Running Included Languages

To compile and benchmark any included language, generate its parse table using `uv` and invoke `zig build` from the repository root:

```sh
# Generate and test the LL parser for standard JSON
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/json --parser-type LL
zig build -Doptimize=ReleaseFast ll-json -- languages/json/sample-code.json

# Generate and test the LR parser for the Grammar specification itself
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/grammar --parser-type LR
zig build -Doptimize=ReleaseFast lr-grammar -- languages/grammar/sample-code.grm
```

---

**← Previous:** [Getting Started](getting_started.md) | **Next:** [Configuration & Flags](configuration.md) **→**
