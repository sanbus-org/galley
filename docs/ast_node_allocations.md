# AST Node Allocation Mechanics & Limitations (LL vs. LR)

## Table of Contents

- [1. Structural Node Allocations (`is_ast_enabled`)](#1-structural-node-allocations-is_ast_enabled)
- [2. Terminal AST Allocations (`ast-for-terminals`)](#2-terminal-ast-allocations-ast-for-terminals)
  - [LL Parser: Dynamic Propagation](#ll-parser-dynamic-propagation)
  - [LR Parser: Static Analysis Constraint](#lr-parser-static-analysis-constraint)

---

When building optimized parser generators, managing memory allocation in the Abstract Syntax Tree (AST) is critical. This document details the architectural differences, optimizations, and compiler-level limitations of AST node allocations in LL (top-down) and LR (bottom-up) parsers in this project.

---

## 1. Structural Node Allocations (`is_ast_enabled`)

For helper or temporary variables in the grammar (like `_StringContent` or `_OptionalBlank` starting with an underscore), AST node generation should be skipped completely to keep memory usage low.

- **LL Parser (Top-Down):**
  LL parses rules top-down. The parser knows which rule it is expanding before it matches the children. If the variable has `is_ast_enabled = False`, LL simply skips allocating the AST node.
  
- **LR Parser (Bottom-Up):**
  LR parses rules bottom-up, meaning parent nodes are only created during reduction. If the reduced variable has `is_ast_enabled = False`, LR skips the node allocation. However, because it still needs to track positions for parent rules, it pushes the start position (`context.pos()`) directly onto the semantic stack as a raw integer instead of allocating an AST node.

---

## 2. Terminal AST Allocations (`ast-for-terminals`)

When `--ast-for-terminals` is enabled, the parser is instructed to create AST leaf nodes for terminal tokens. However, terminal tokens inside non-AST helper variables (like characters inside a string) should still be ignored.

### LL Parser: Dynamic Propagation

Because LL has a standard function call stack, it propagates a `non_ast` boolean parameter dynamically:

1. When parsing enters a non-AST helper rule, `non_ast` is set to `true`.
2. This `non_ast` flag is passed down to all children functions.
3. If `non_ast` is `true`, terminal allocations are dynamically skipped.

### LR Parser: Static Analysis Constraint

Because LR is bottom-up, it is built on a flat state machine rather than a call stack. At the moment the parser shifts a terminal token onto the stack, it has no top-down call stack context to know whether that token belongs to an AST-enabled parent or a non-AST helper variable.

To solve this limitation, LR uses a **compile-time static analysis** mechanism:

1. During generator time, the generator builds a set of `linked_terminals` — terminals that appear on the RHS of at least one AST-enabled rule.
2. During runtime shifting, LR only allocates a terminal AST node if the terminal is in `linked_terminals`. Otherwise, it pushes the raw position `context.pos()`.
3. **Limitation:** If a terminal (like `digit`) is linked in one rule (`IntegerNumber`) but not in another (`_PositiveIntegerNumberTail`), LR is forced to allocate nodes for it every time it shifts, because it cannot distinguish them bottom-up. LL, conversely, can suppress them inside `_PositiveIntegerNumberTail` using its top-down `non_ast` flag.
