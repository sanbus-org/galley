# Architecture

## Table of Contents

- [Overview](#overview)
- [Unified No-Lexer Design](#unified-no-lexer-design)
- [Native Call-Stack Execution](#native-call-stack-execution)
- [LL Syntax-Error Recovery](#ll-syntax-error-recovery)
- [Dynamic Stack-Overflow Recovery](#dynamic-stack-overflow-recovery)
- [Dense Integer Node Pooling](#dense-integer-node-pooling)
- [Role of the Self-Hosted Generator](#role-of-the-self-hosted-generator)
- [Self-Hosting](#self-hosting)

---

## Overview

Galley achieves parsing speeds tens to hundreds of times faster than traditional table-driven parser generators by fundamentally rethinking how parsers interact with memory and the CPU. Rather than interpreting state transitions at runtime, Galley directly encodes grammar semantics into compile-time Zig execution paths.

---

## Unified No-Lexer Design

Traditional parsers split execution into two passes: a lexer (tokenizer) that scans source text and allocates token objects on the heap, followed by a parser that consumes those tokens.

Galley eliminates the separate lexer pass entirely. Character matching and structural grammar reduction happen simultaneously in a single, unified pass over the source byte buffer. By avoiding token allocation and intermediate buffering, memory bus traffic is reduced by over 50%.

---

## Native Call-Stack Execution

In both generated LL recursive-descent and LR recursive-ascent parsers, Galley leverages the native CPU execution call stack as the grammar parsing stack.

Instead of dynamically allocating stack frame objects or pushing/popping state IDs in an array loop, grammar transitions compile directly into native machine function calls (`call` and `ret` instructions). This allows modern CPUs to fully utilize their hardware return address stacks (RAS) and branch prediction units, resulting in near-zero overhead state transitions.

---

## LL Syntax-Error Recovery

An LL syntax mismatch transfers control to a generated cold handler. The handler prints the first diagnostic at an input position, searches ahead for the failing state's recovery candidates, and returns a neutral parser value. The parent then continues through its ordinary generated code, naturally exposing later grammar states as recovery points. No parallel parser stack, recovery interpreter, or generated continuation graph is maintained.

Syntax mismatches are not represented as Zig errors. Void parsers return normally and AST parsers return the invalid-node sentinel; Zig errors remain reserved for real failures such as allocation, I/O, and procedure errors. A session-local input-position marker suppresses repeated diagnostics while recovery is unresolved. Finding a candidate, consuming input, or inserting an expected symbol at end-of-input completes recovery and permits a later mismatch to be reported separately.

Normal child calls retain the same `try parse_child(...)` shape as parsers without recovery. No recovery state is read or written on valid input. Void-returning LL variables reach their cold handlers through guaranteed tail calls; AST and terminal handlers are kept out of line. Recovery scanning and lookahead allocation therefore happen only after a syntax mismatch. For indentation-sensitive languages, the search distance counts parser input units, including generated indent and dedent symbols. Procedures may run while reductions containing neutral children complete, so a partial AST from erroneous input is diagnostic data rather than a guaranteed-valid syntax tree.

The parser stops after 10 syntax errors by default. Runtime callers can set `ParseOptions.max_errors` and `ParseOptions.recovery_window`; generated parser executables expose the same settings as `--max-errors` and `--recovery-window`.

---

## Dynamic Stack-Overflow Recovery

Leveraging the native CPU call stack introduces a potential risk when parsing deeply recursive structures (such as thousands of nested JSON arrays): exceeding the operating system thread stack limit.

To prevent crashes, Galley includes a runtime stack-overflow recovery mechanism. As parsing approaches the stack limit, the runtime intercepts execution and dynamically transitions to heap-backed continuation frames. This guarantees safety on arbitrarily deep input files while maintaining maximum bare-metal speed during normal execution depths.

---

## Dense Integer Node Pooling

When AST construction is enabled, Galley avoids allocating individual nodes via the system heap (`malloc`). Instead, nodes are allocated from contiguous, preallocated memory pools (`ASTAllocator`).

Furthermore, AST nodes reference their parents, children, and siblings using compact integer indices (`u16` or bit-width defined by `--input-size`) rather than 64-bit pointers. This cuts AST memory consumption in half, ensures dense cache packing in CPU L1/L2 caches, and allows resetting the entire parser state between iterations in \(O(1)\) time simply by zeroing a counter.

---

## Role of the Self-Hosted Generator

The grammar analysis engine is self-hosted in Zig. Galley ships an LL seed parser for its own grammar format in `languages/galley/_ll-parser.zig`; that parser is responsible for:

1. Parsing the `.grm` definition files.
2. Computing FIRST, FOLLOW, and nullable sets.
3. Constructing deterministic LL(k) lookup tables or LR/LALR shift-reduce automatas.
4. Emitting highly optimized, zero-boilerplate Zig code (`_ll-parser.zig` and `_lr-parser.zig`).

Because this step happens entirely ahead-of-time (AOT), the runtime Zig binary carries zero generator overhead. The original Python bootstrap generator was removed after commit `0190e40`.

---

## Self-Hosting

Galley ships with a formal specification of its own grammar syntax (`languages/galley`). The tracked LL seed parser can parse `.grm` files and generate both LL and LR parsers from them. The Galley LR parser stays generated/ignored and is used as a verification path rather than as a second bootstrap artifact.
