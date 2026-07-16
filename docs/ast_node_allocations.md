# AST Node Allocation Mechanics & Limitations (LL vs. LR)

## Table of Contents

- [1. Structural Node Allocations (`is_ast_enabled`)](#1-structural-node-allocations-is_ast_enabled)
- [2. Terminal AST Allocations (`ast-for-terminals`)](#2-terminal-ast-allocations-ast-for-terminals)
  - [LL Parser: Generated AST-Suppressed Variants](#ll-parser-generated-ast-suppressed-variants)
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

When `--ast-for-terminals` is enabled, the parser is instructed to create AST leaf nodes for terminal tokens. However, terminal tokens inside AST-suppressed helper variables (like characters inside a string) should still be ignored.

### LL Parser: Generated AST-Suppressed Variants

Because LL is generated top-down, the generator propagates a `skip_ast_construction` decision while emitting parser functions:

1. When a child belongs to an AST-suppressed helper rule, the generator selects an AST-suppressed parser variant.
2. The generator propagates that decision while emitting the helper's descendants.
3. Those generated variants omit structural and terminal AST allocations; no runtime boolean is needed.

### LR Parser: Static Analysis Constraint

Because LR is bottom-up, it is built on a flat state machine rather than a call stack. At the moment the parser shifts a terminal token onto the stack, it has no top-down call stack context to know whether that token belongs to an AST-enabled parent or an AST-suppressed helper variable.

To solve this limitation, LR uses a **compile-time static analysis** mechanism:

1. During generator time, the generator builds a set of `linked_terminals` — terminals that appear on the RHS of at least one AST-enabled rule.
2. During runtime shifting, LR only allocates a terminal AST node if the terminal is in `linked_terminals`. Otherwise, it pushes the raw position `context.pos()`.
3. **Limitation:** If a terminal (like `digit`) is linked in one rule (`IntegerNumber`) but not in another (`_PositiveIntegerNumberTail`), LR is forced to allocate nodes for it every time it shifts, because it cannot distinguish them bottom-up. LL, conversely, can select an AST-suppressed parser variant for `_PositiveIntegerNumberTail` during generation.
