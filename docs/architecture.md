# Architecture

## Table of Contents

- [Overview](#overview)
- [Unified No-Lexer Design](#unified-no-lexer-design)
- [Native Call-Stack Execution](#native-call-stack-execution)
- [Syntax-Error Recovery](#syntax-error-recovery)
- [Optional Stack-Overflow Recovery](#optional-stack-overflow-recovery)
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

## Syntax-Error Recovery

Generated LL and LR parsers are fail-fast by default: a mismatch records and prints one diagnostic, then returns `ParseError.SyntaxError`. Passing `with_error_recovery = true` to the generator enables recovery. Generated parsers expose `error_recovery_mode` as `.disabled`, `.automatic`, or `.explicit`, while retaining `is_error_recovery_enabled` for compatibility.

An enabled grammar without recovery annotations uses automatic recovery. If any LHS variable, production, or RHS variable occurrence carries a `!` synchronization annotation, the parser instead uses explicit-only recovery with no automatic fallback. An annotation records an exact terminal and whether synchronization resumes before it (preserving it) or after it (consuming it). Disabled generation keeps annotations inert and emits one warning.

An automatic-mode LL syntax mismatch transfers control to a generated cold handler. The handler prints the first diagnostic at an input position, searches ahead for the failing symbol's recovery candidates, and returns a neutral parser value. The parent then continues through its ordinary generated code, naturally exposing later grammar states as recovery points.

An automatic-mode LR mismatch uses the same bounded lookahead and position-based diagnostic suppression, with recovery candidates derived from the complete terminals accepted by the current LR state. Finding a candidate skips the invalid input and retries the state. If the state cannot resynchronize, an internal result unwinds one native LR frame and, when AST construction is enabled, its semantic value; the caller recognizes it and retries in its existing frame. This continues until the nearest viable state resumes or the initial state is exhausted. Unrecoverable end-of-input stops at the original diagnostic instead of inventing a terminal.

Explicit recovery separates mismatch detection from synchronization. Once a production is committed, the parser tries the active RHS occurrence, selected production, LHS variable, and then enclosing committed reductions. LR recovery annotations are stored separately from canonical LR items, so adding or removing them cannot change closures, states, actions, gotos, or state numbering. Explicit LR state calls carry a small linked frame containing the canonical state and incoming symbol; after a mismatch, the recovery planner combines those active frames with canonical closure metadata to resolve committed scopes without a second LR stack. For each annotated occurrence, bounded graph reachability checks whether any productive closure path can avoid it; the occurrence is active only when no surviving path can, so shared-prefix states do not activate speculative scopes. Enclosing `(frame, item)` lineages are likewise deduplicated into a finite graph, and occurrence, production, and LHS scopes become candidates only when they dominate every productive exit. Neither analysis enumerates or copies closure paths. For consecutive terminals on one target, selection is deterministic: earliest input offset, longest terminal, then annotation source order. A successful recovery attaches the winning target, terminal, and resume side to the existing diagnostic, neutral-completes the damaged variable, discards its partial semantic state, and skips its occurrence, production, and variable hooks. Message-hook invocation is deferred until the structured recovery context is finalized.

Automatic recovery does not use Zig errors for internal control flow: LL void parsers return normally, AST parsers return the invalid-node sentinel, and LR state functions return an internal recovery result when a frame must unwind. Explicit LL recovery instead propagates a private `ExplicitSyntaxRecovery` signal until a committed annotated boundary synchronizes or the public entry point converts it to `ParseError.SyntaxError`; explicit LR recovery carries the equivalent result through its state frames. A session-local target-and-position guard prevents a preserved terminal from repeatedly selecting the same explicit scope. Resynchronizing completes the current recovery and permits a later mismatch to be reported separately. Automatic LL recovery can neutral-complete a missing symbol at end-of-input, while explicit recovery requires a matching synchronization terminal.

Normal automatic-mode LL child calls retain the same `try parse_child(...)` shape. Eligible automatic recovery calls use `always_tail` on the LLVM and native AArch64 backends and fall back to ordinary calls on other backends. LR state calls inspect the returned recovery result, and each state uses its existing native frame rather than a second parser stack. Neither parser scans for synchronization terminals during normal shifts or reductions; recovery lookahead allocation happens only after a mismatch. For indentation-sensitive languages, the search distance counts parser input units, including generated indent and dedent symbols. Procedures may run on partial or later-discarded trees, so an AST from erroneous input is diagnostic data rather than a guaranteed-valid syntax tree.

Recovery-enabled parsers stop after 10 syntax errors by default. Runtime callers
configure the limit and search window through `ParseOptions.max_errors` and
`ParseOptions.recovery_window`.

---

## Optional Stack-Overflow Recovery

Generated parsers use the native call stack, so excessive recursive nesting can
exhaust the stack available to the calling thread. On Linux and macOS, Galley
can run a parse inside a protected signal-recovery scope that converts a fault
at the thread's stack boundary into `ParseError.StackOverflow`.

Recovery is disabled by default because establishing that scope adds fixed
setup and teardown work to every protected parse call. Runtime callers opt in
with `ParseOptions.stack_overflow_recovery = true`.

The recovery scope installs an alternate signal stack and temporary
`SIGSEGV`/`SIGBUS` handlers, records the current thread's stack bounds, and
restores the previous process and thread state when parsing finishes. A memory
fault outside the active thread's stack boundary is forwarded to the previously
installed handler instead of being reported as parser stack overflow.

---

## Dense Integer Node Pooling

When AST construction is enabled, Galley avoids allocating individual nodes via the system heap (`malloc`). Instead, nodes are allocated from contiguous, preallocated memory pools (`ASTAllocator`).

Furthermore, AST nodes reference their parents, children, and siblings using
integer indices rather than memory pointers. Those indices remain valid when
the contiguous pool grows and relocates. Session reuse retains the allocated
pool, although reset currently clears the previously used node range before
rewinding it.

---

## Role of the Self-Hosted Generator

The grammar analysis engine is self-hosted in Zig. Galley ships an LL seed
parser for its own grammar format in `languages/galley/_ll-parser.zig`. The
seed parser constructs the grammar model; the generator API then:

1. Validates the parsed grammar model.
2. Computes FIRST, FOLLOW, and nullable sets.
3. Constructs deterministic LL(k) lookup tables or LR/LALR shift-reduce automata.
4. Emits optimized Zig parser source (`_ll-parser.zig` or `_lr-parser.zig`).

Because this step happens entirely ahead-of-time (AOT), the runtime Zig binary carries zero generator overhead. The original Python bootstrap generator was removed after commit `0190e40`.

---

## Self-Hosting

Galley ships with a formal specification of its own grammar syntax
(`languages/galley`). The tracked LL seed parser parses `.grm` files into the
grammar model used by the generator API, which can emit both LL and LR parser
source. The Galley LR parser stays generated/ignored and is used as a
verification path rather than as a second bootstrap artifact.
