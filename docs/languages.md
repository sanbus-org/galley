# Included Languages

## Table of Contents

- [Overview](#overview)
- [Bundled Grammars](#bundled-grammars)
  - [JSON (`languages/json`)](#json-languagesjson)
  - [JSON Recovery (`languages/json-recovery`)](#json-recovery-languagesjson-recovery)
  - [JSON Structured AST (`languages/json-structured-ast`)](#json-structured-ast-languagesjson-structured-ast)
  - [JSON Augmented (`languages/json-augmented`)](#json-augmented-languagesjson-augmented)
  - [Lisp (`languages/lisp`)](#lisp-languageslisp)
  - [Lua (`languages/lua`)](#lua-languageslua)
  - [Grammar Parser (`languages/galley`)](#grammar-parser-languagesgalley)
- [Choosing Between LL and LR](#choosing-between-ll-and-lr)
- [Building and Running Included Languages](#building-and-running-included-languages)

---

## Overview

Galley ships with several ready-to-use grammar definitions located in the `languages/` directory. These bundled languages serve both as comprehensive benchmarks for parsing speed and as architectural reference implementations for defining your own grammars.

---

## Bundled Grammars

### JSON (`languages/json`)

The standard RFC 8259 JSON implementation used for JSON benchmarking. It supports full recursive object and array structures, floating-point numbers, unicode escape sequences, and string content literals. Its grammar is written with fewer non-terminals so the generated parser has fewer calls and less intermediate AST structure.

- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.

This is the minimal performance reference. Recovery-oriented grammar structure lives in `languages/json-recovery` so it cannot affect JSON benchmark topology or throughput.

### JSON Recovery (`languages/json-recovery`)

The full JSON recovery and diagnostics demonstration. It accepts the same valid corpus through symlinks to `languages/json/samples`, while its grammar is free to use recovery-specific boundaries.

- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.
- **Recovery:** Uses explicit occurrence, production, and LHS annotations to preserve later array elements and object members while safely closing damaged containers. LL isolates one damaged value; LR uses its existing left-recursive list production where that preserves the same visible behavior without an additional reduction per list item.
- **Diagnostics:** `error_messages.zig` provides shared JSON-specific guidance, exposed through semantic LL hooks and the parser-wide LR fallback.

Generate either parser with recovery enabled, then run the intentionally malformed demonstration. Its nonzero exit status is expected after all recoverable diagnostics are printed:

```sh
./zig-out/bin/galley --parser-type ll --with-error-recovery languages/json-recovery
zig build ll-json-recovery
./zig-out/bin/ll-json-recovery languages/json-recovery/recovery-demo.json
```

### JSON Structured AST (`languages/json-structured-ast`)

A full RFC 8259 JSON grammar with additional non-terminals for a richer AST shape. It parses the same language as `languages/json`, but preserves more intermediate structure and therefore has lower benchmark throughput.

- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.
- **Hooks:** Uses LHS `@replaceWithChildren` annotations and automatic reduction hooks to shape the AST and collect payload counts.

### JSON Augmented (`languages/json-augmented`)

An extended JSON variant designed to test extreme recursion depths and stress-test the parser's stack overflow recovery mechanisms. It introduces special grouping syntax (`*(...)` and `(...)`) that allows deeply nested structures without exceeding memory limits.

- **Parser Engines:** `ll.grm` is provided.
- **Hooks:** Uses LHS cleanup hooks plus automatic symbol and general reduction hooks to shape the AST and collect payload counts.

### Lisp (`languages/lisp`)

A Lisp grammar covering lists, symbols, numbers, strings, reader macros, comments, vectors, arrays, and multiple top-level forms.

- **Parser Engines:** `ll.grm` is provided.

### Lua (`languages/lua`)

A Lua grammar that demonstrates keyword-led statements, function declarations, returns, function-call expressions, integer literals, strings, comments, and keyed table constructors.

- **Parser Engines:** `ll.grm` is provided.

### Grammar Parser (`languages/galley`)

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

To compile and benchmark any included language, generate its parser and invoke `zig build` from the repository root:

```sh
# Generate and test the LL parser for standard JSON
zig build
./zig-out/bin/galley --parser-type ll languages/json
zig build -Doptimize=ReleaseFast ll-json
./zig-out/bin/ll-json languages/json/samples/code-01.json

# Generate and test the LR parser for the Grammar specification itself
./zig-out/bin/galley --parser-type lr languages/galley
zig build -Doptimize=ReleaseFast lr-galley
./zig-out/bin/lr-galley languages/galley/lr.grm
```
