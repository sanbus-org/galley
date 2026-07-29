# Included Languages

## Table of Contents

- [Overview](#overview)
- [Bundled Grammars](#bundled-grammars)
  - [JSON (`languages/json`)](#json-languagesjson)
  - [JSON Unicode (`languages/json-unicode`)](#json-unicode-languagesjson-unicode)
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

The minimal JSON benchmark implementation. It supports recursive object and array structures, floating-point numbers, and ASCII string content. Its grammar deliberately avoids Unicode scalar validation and JSON escape decoding so the generated parser has fewer calls and less intermediate structure.

- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.

This is the minimal performance reference. Unicode validation lives in `languages/json-unicode`, and recovery-oriented grammar structure lives in `languages/json-recovery`, so neither feature changes the baseline grammar's topology or throughput.

### JSON Unicode (`languages/json-unicode`)

The Unicode-complete JSON reference grammar. It accepts valid raw UTF-8 scalar values, rejects malformed and non-scalar UTF-8 encodings, and validates standard JSON escapes including `\uXXXX`. Its string decoder combines UTF-16 surrogate pairs, preserves embedded `U+0000` in length-aware output slices, and returns decoded UTF-8.

- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.
- **Unicode grammar:** Single-byte UTF-8 generative terminals are composed into two-, three-, and four-byte scalar rules.
- **Sample:** `samples/code-01.json` includes 20-scalar Unicode strings across every root object.

### JSON Recovery (`languages/json-recovery`)

The full JSON recovery and diagnostics demonstration. It accepts the same valid corpus through symlinks to `languages/json/samples`, while its grammar is free to use recovery-specific boundaries.

- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.
- **Recovery:** Uses explicit occurrence, production, and LHS annotations to preserve later array elements and object members while safely closing damaged containers. LL isolates one damaged value; LR uses its existing left-recursive list production where that preserves the same visible behavior without an additional reduction per list item.
- **Diagnostics:** `error_messages.zig` provides shared JSON-specific guidance, exposed through semantic LL hooks and the parser-wide LR fallback.

Generate either parser with recovery enabled, then run the intentionally malformed demonstration through the repository API harness. Its nonzero exit status is expected after all recoverable diagnostics are printed:

```sh
./zig-out/bin/galley --parser-type ll --with-error-recovery languages/json-recovery
zig build run-ll-json-recovery -- languages/json-recovery/recovery-demo.json
```

### JSON Structured AST (`languages/json-structured-ast`)

A full RFC 8259 JSON grammar with additional non-terminals for a richer AST shape. It parses the same language as `languages/json`, but preserves more intermediate structure and therefore has lower benchmark throughput.

- **Parser Engines:** Both `ll.grm` and `lr.grm` are provided.
- **Hooks:** Uses LHS `@replaceWithChildren` annotations and automatic reduction hooks to shape the AST and collect payload counts.

### JSON Augmented (`languages/json-augmented`)

An extended JSON variant designed to test extreme recursion depths and the
optional stack-overflow recovery mechanism. It introduces special grouping
syntax (`*(...)` and `(...)`) for deeply nested stress inputs.

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

## Generating and Benchmarking Included Languages

To compile and benchmark any included language, generate its parser and invoke `zig build` from the repository root:

```sh
# Generate and benchmark the LL parser for standard JSON
zig build
./zig-out/bin/galley --parser-type ll languages/json
zig build -Doptimize=ReleaseFast run-ll-json -- \
  languages/json/samples/code-01.json --iterations 100

# Generate and benchmark the Unicode JSON parser
./zig-out/bin/galley --parser-type ll languages/json-unicode
zig build -Doptimize=ReleaseFast run-ll-json-unicode -- \
  languages/json-unicode/samples/code-01.json --iterations 100

# Generate and benchmark the LR parser for the Grammar specification itself
./zig-out/bin/galley --parser-type lr languages/galley
zig build -Doptimize=ReleaseFast run-lr-galley -- \
  languages/galley/lr.grm --iterations 100
```

These `ll-*` and `lr-*` repository executables are benchmark harnesses around
the parser API. Applications should import an assembled parser module rather
than treating these harnesses as generated applications.
