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
- [Immediate Tree Edits](#immediate-tree-edits)
- [Ambiguity Diagnostics](#ambiguity-diagnostics)
- [Concurrency](/concurrency)
- [Role of the Self-Hosted Generator](#role-of-the-self-hosted-generator)
- [Self-Hosting](#self-hosting)

---

## Overview

Galley generates LL and LR parsers as native Zig source, encoding grammar rules directly into code paths rather than interpreting transition tables at runtime. It pairs that with a design centered on that goal: a single no-lexer pass that matches characters and reduces rules at the same time, the native call stack as the parse stack in both recursive-descent and recursive-ascent parsers, AST node allocation decided at generation time per symbol, and a self-hosted generator that runs ahead-of-time to emit both LL and LR parser source from a parsed grammar. None of these ideas are unique to Galley on their own, but the combination is its take on parser generation.

---

## Unified No-Lexer Design

Traditional parsers split execution into two passes: a lexer (tokenizer) that scans source text and allocates token objects on the heap, followed by a parser that consumes those tokens.

Galley eliminates the separate lexer pass entirely. Character matching and structural grammar reduction happen simultaneously in a single, unified pass over the source byte buffer, avoiding the token-allocation and intermediate-buffering overhead of a separate lexer.

Token selection follows longest-match: when two terminals in one decision share a byte prefix (for example `"="` and `"=="`, or `">"` and `">="` inside `operator`), the shorter terminal is the fallback and the continuation is a nested group, so the longest available match wins deterministically in both LL and LR parsers. Identical byte strings with different targets have no longest match and are rejected at generation time as `AmbiguousGrammar`: give one side an exception (for example `character^"\n"` next to a `new_line` alternative) or merge the targets.

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

When AST construction is enabled, Galley avoids allocating individual nodes via the system heap (`malloc`). Instead, nodes are allocated from the `ASTAllocator`'s node storage, which never relocates: on platforms with lazy-commit anonymous mappings (macOS, Linux, the BSDs) an address-space region sized to the requested capacity (page-rounded) is reserved up front and backed by the OS on first touch, with demand past the reservation covered by appended fixed-size segments; other platforms use segments throughout. Because neither region ever moves, integer node addresses stay valid for the allocator's lifetime. The only hard wall is address exhaustion (the pointer width minus the invalid sentinel), reported as `ASTCapacityExceeded`.

Furthermore, AST nodes reference their parents, children, and siblings using integer indices rather than memory pointers. Because the storage never relocates, element addresses are stable for the allocator's lifetime: pointers resolved from an address (for example `args.currentNode()` inside a procedure hook) remain valid across subsequent node allocations. Session reuse retains the allocated storage, although reset currently clears the previously used node range before rewinding it.

AST allocation is also decided at generation time, per symbol: helper variables (written with a leading `_`) never allocate nodes, and the parser is emitted with exactly the node creation it needs, so no runtime branching decides whether to build a node. See [AST Node Allocations](/ast_node_allocations) for the full mechanics and the LR generator's static-analysis constraints.

---

## Self-Repeating Decisions

Rules that repeat a variable on their own right-hand side (list and suffix shapes) are recognized statically during planning. Instead of re-parsing the repeated variable from scratch each time, the generator emits a dedicated decision that steps through the repetition and stops on the first token that no longer matches, folding the loop into the parse flow.

---

## Immediate Tree Edits

`Node` has two tiers of structure functions. The public tier (`insertBefore`, `insertAfter`, `insertChildren`, `appendChildren`, `remove`, `removeSelf`, `removeChildren`, `removeChild`, `cleanChildren`) reaches hosts through the `galley_tree_*` and `galley_hook_tree_*` calls and leaves the tree consistent after every correct call: a node that is not linked into a tree has an invalid parent, prior, and next. Misuse (inserting a chain whose head still has a parent or prior, a chain that contains the target or one of its ancestors, or an index past the end) is caught by assertions in Debug builds only. Release builds do not check, and misuse corrupts the tree.

The `immediate*` tier exists only for the hot paths of generated parsers. Today it is `immediateAppendChildren`, the one implementation of linking a parentless chain under a parent: sibling links, parent links through `attachParent`, and counts. It skips every check. `appendChildren` is the same function behind the Debug assertions, and `insertBefore`, `insertAfter`, and `insertChildren` give the chain its parent through the same `attachChain` step. It is safe for the parser because the chain it appends is parentless with no prior: nodes the parser just created, or a detached chain a hook handed back (for example the children `replaceWithChildren` promoted). A hook must not hand back a node that is still attached to a parent; that would list the node under two parents, and only a Debug build asserts it.

`attachParent` writes a parent link without bumping the allocator's `structure_version`: attaching a parentless node cannot move a walk position, because a cursor's position below its root always has a parent and the root bounds the climb. Every write that changes or clears an existing parent goes through `setParent`, or `setChainParent` for a whole sibling chain, which bump it (once per call, so once per operation for a chain), so walk cursors re-verify their position. Parent links are written only by `setParent`, `setChainParent`, `attachParent`, and node initialization.

Every function in this tier must keep one invariant: whenever user code can observe the tree, it is consistent. Hooks run mid-parse and can walk and edit the tree through the hook door, so no immediate function may leave a half-linked node behind between generated statements that a hook can run in. A hook must also not detach an ancestor of the node being reduced: the repetition loop climbs from wrapper to enclosing wrapper, and a detached ancestor skips the outer procedures of the repetition.

`immediatePromoteChildrenOverWrapper` is the other member: internal, used only by the `replaceWithChildren` procedure, it splices a wrapper's children into its place in one pass and leaves the wrapper fully detached; it is not in the C ABI or any binding.

Removal has no immediate variant. The generated loop removes a dropped wrapper with the public `removeSelf`, which cannot fail and clears the node's parent, prior, and next, so a dropped node never reports a live parent or sibling. The loop reads the enclosing wrapper before the procedures run, because procedures may detach the wrapper.

The tier is not public because its safety depends on the caller knowing what happens next, which an external caller cannot guarantee. The standard `replaceWithChildren` procedure calls `immediatePromoteChildrenOverWrapper`; hosts that need the same result compose the public tier with `cleanChildren`, `insertBefore`, and `removeSelf`, which gives the same tree in several passes.

---

## Ambiguity Diagnostics

When the LL planner finds two productions of a variable that share a terminal, it reports the conflict together with the derivation chain that explains each side: the reason rules that placed the terminal into FIRST or FOLLOW, the nullable derivations that let it pass through, and where the terminal is finally produced. When the conflicting productions share a hoistable prefix, the planner factors it automatically; when annotations block factoring, the diagnostic names the refusal instead of suggesting a rewrite. See [Grammar Guidelines §7](/grammar_guidelines#7-operator-precedence--ambiguity-free-expression-extraction) for the reported output.

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
