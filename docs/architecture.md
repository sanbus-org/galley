# Architecture

## Table of Contents

- [Overview](#overview)
- [Unified No-Lexer Design](#unified-no-lexer-design)
- [Native Call-Stack Execution](#native-call-stack-execution)
- [Syntax-Error Recovery](#syntax-error-recovery)
- [Verbatim Raw Capture (`@>>` / `@>^"..."` / `@>"..."^`)](#verbatim-raw-capture)
- [Optional Stack-Overflow Recovery](#optional-stack-overflow-recovery)
- [Dense Integer Node Pooling](#dense-integer-node-pooling)
- [Self-Repeating Decisions](#self-repeating-decisions)
- [Ambiguity Diagnostics](#ambiguity-diagnostics)
- [Role of the Self-Hosted Generator](#role-of-the-self-hosted-generator)
- [Self-Hosting](#self-hosting)

---

## Overview

Galley generates LL and LR parsers as native Zig source, encoding grammar rules directly into code paths rather than interpreting transition tables at runtime. It pairs that with a design centered on that goal: a single no-lexer pass that matches characters and reduces rules at the same time, the native call stack as the parse stack in both recursive-descent and recursive-ascent parsers, AST node allocation decided at generation time per symbol, and a self-hosted generator that runs ahead-of-time to emit both LL and LR parser source from a parsed grammar. None of these ideas are unique to Galley on their own, but the combination is its take on parser generation.

---

## Unified No-Lexer Design

Traditional parsers split execution into two passes: a lexer (tokenizer) that scans source text and allocates token objects on the heap, followed by a parser that consumes those tokens.

Galley eliminates the separate lexer pass entirely. Character matching and structural grammar reduction happen simultaneously in a single, unified pass over the source byte buffer, avoiding the token-allocation and intermediate-buffering overhead of a separate lexer.

---

## Native Call-Stack Execution

In both generated LL recursive-descent and LR recursive-ascent parsers, Galley leverages the native CPU execution call stack as the grammar parsing stack.

Instead of dynamically allocating stack frame objects or pushing/popping state IDs in an array loop, grammar transitions compile directly into native machine function calls (`call` and `ret` instructions). This lets modern CPUs make use of their hardware return address stacks (RAS) and branch prediction units, avoiding the per-token dispatch and stack-array bookkeeping of table-driven parsers.

---

## Syntax-Error Recovery

Generated LL and LR parsers are fail-fast by default, returning `ParseError.SyntaxError` on the first mismatch. Enabling recovery produces either automatic or explicit (`@`-annotated) recovery modes, both built on the parser's native execution shape rather than a second parser stack. Recovery-enabled parsers stop after 10 syntax errors by default.

LL parsers also report the innermost-first sequence of variables being parsed at a syntax error, rendered as `Symbol <~ RightHandSide <~ ...`. The instrumentation is optional and folds away at compile time when disabled.

See [Syntax-Error Recovery and Messages](/syntax_error_recovery) for the full mechanics of both topics.

---

## Verbatim Raw Capture (`@>>` / `@>^"..."` / `@>"..."^`)

An RHS occurrence annotated with the verbatim marker `@>>` or a literal terminator (`@>^"..."` / `@>"..."^`) captures every raw byte until a terminator reappears, without lexing, indentation translation, or escape decoding. The `^` position chooses whether the terminator stays in the input or is appended to the captured span.

The LL and LR generators both support it, with LR emitting verbatim reductions as default actions on all lookaheads because a captured body may begin with any byte.

See [Grammar Guidelines §8](/grammar_guidelines#8-verbatim-raw-capture) for the full syntax and semantics.

---

## Optional Stack-Overflow Recovery

Generated parsers use the native call stack, so excessive recursive nesting can exhaust the stack available to the calling thread. On Linux and macOS, Galley can run a parse inside a protected signal-recovery scope that converts a fault at the thread's stack boundary into `ParseError.StackOverflow`.

Recovery is disabled by default because establishing that scope adds fixed setup and teardown work to every protected parse call. Runtime callers opt in with `ParseOptions.stack_overflow_recovery = true`.

The recovery scope installs an alternate signal stack and temporary `SIGSEGV`/`SIGBUS` handlers, records the current thread's stack bounds, and restores the previous process and thread state when parsing finishes. A memory fault outside the active thread's stack boundary is forwarded to the previously installed handler instead of being reported as parser stack overflow.

---

## Dense Integer Node Pooling

When AST construction is enabled, Galley avoids allocating individual nodes via the system heap (`malloc`). Instead, nodes are allocated from the `ASTAllocator`'s node storage, which never relocates: on platforms with lazy-commit anonymous mappings (macOS, Linux, the BSDs) one contiguous address-space region is reserved up front and backed by the OS on first touch; other platforms use fixed-size segments that are allocated once and never moved.

Furthermore, AST nodes reference their parents, children, and siblings using integer indices rather than memory pointers. Because the storage never relocates, element addresses are stable for the allocator's lifetime: pointers resolved from an address (for example `args.currentNode()` inside a procedure hook) remain valid across subsequent node allocations. Session reuse retains the allocated storage, although reset currently clears the previously used node range before rewinding it.

AST allocation is also decided at generation time, per symbol: helper variables (written with a leading `_`) never allocate nodes, and the parser is emitted with exactly the node creation it needs, so no runtime branching decides whether to build a node. See [AST Node Allocations](/ast_node_allocations) for the full mechanics and the LR generator's static-analysis constraints.

---

## Self-Repeating Decisions

Rules that repeat a variable on their own right-hand side (list and suffix shapes) are recognized statically during planning. Instead of re-parsing the repeated variable from scratch each time, the generator emits a dedicated decision that steps through the repetition and stops on the first token that no longer matches, folding the loop into the parse flow.

---

## Ambiguity Diagnostics

When the LL planner finds two productions of a variable that share a terminal, it reports the conflict together with the derivation chain that explains each side: the reason rules that placed the terminal into FIRST or FOLLOW, the nullable derivations that let it pass through, and where the terminal is finally produced. A left-factored rewrite is suggested when the conflicting productions share a prefix. See [Grammar Guidelines §7](/grammar_guidelines#7-operator-precedence--ambiguity-free-expression-extraction) for the reported output.

---

## Role of the Self-Hosted Generator

The grammar analysis engine is self-hosted in Zig. Galley ships an LL seed parser for its own grammar format in `languages/galley/_ll-parser.zig`. The seed parser constructs the grammar model; the generator API then:

1. Validates the parsed grammar model.
2. Computes FIRST, FOLLOW, and nullable sets.
3. Constructs deterministic LL(k) lookup tables or LR/LALR shift-reduce automata.
4. Emits optimized Zig parser source (`_ll-parser.zig` or `_lr-parser.zig`).

Because this step happens entirely ahead-of-time (AOT), the runtime Zig binary carries zero generator overhead. The original Python bootstrap generator was removed after commit `0190e40`.

---

## Self-Hosting

Galley ships with a formal specification of its own grammar syntax (`languages/galley`). The tracked LL seed parser parses `.grm` files into the grammar model used by the generator API, which can emit both LL and LR parser source. The Galley LR parser stays generated/ignored and is used as a verification path rather than as a second bootstrap artifact.
