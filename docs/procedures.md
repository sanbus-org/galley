# Reduction Procedures

## Table of Contents

- [Overview](#overview)
- [How Procedures Work](#how-procedures-work)
- [AST Generation Requirement](#ast-generation-requirement)
- [Explicit Hook Annotations](#explicit-hook-annotations)
  - [1. LHS Variable Hooks](#1-lhs-variable-hooks)
  - [2. RHS Symbol Hooks](#2-rhs-symbol-hooks)
  - [3. Production Hooks](#3-production-hooks)
  - [4. Chaining Multiple Hooks](#4-chaining-multiple-hooks)
- [Implicit / Automatic Hooks](#implicit--automatic-hooks)
- [Writing Hook Functions in Zig](#writing-hook-functions-in-zig)
  - [Function Signature](#function-signature)
  - [Standard Helper Procedures](#standard-helper-procedures)
  - [Custom State & Payload](#custom-state--payload)

---

## Overview

Reduction procedures in Galley are user-defined semantic hooks written in Zig (`procedures.zig`). They execute during parsing when the parser matches and reduces grammar rules, allowing you to manipulate the Abstract Syntax Tree (AST), inspect parsed symbols, track state, or perform custom semantic validation.

---

## How Procedures Work

1. **Table Generation:** The grammar generator parses your grammar file (`ll.grm` or `lr.grm`) and outputs a serialized parser file (e.g. `_ll-parser.zig`).
2. **Binding:** For every hook reference (explicit or implicit), the generator checks if a public declaration with that name is exported by `languages/<name>/procedures.zig`.
3. **Execution:** During runtime, when the parser shifts or reduces the marked symbols, it calls the corresponding hook function, passing a mutable context.

---

## AST Generation Requirement

> [!IMPORTANT]
> Hooks are strictly tied to AST node generation. If AST construction is disabled (using the `--no-ast` generator flag), all reduction procedures are automatically disabled and compiled out to maximize raw syntax validation speed.
>
> Furthermore, for a specific symbol to trigger a hook, an AST node must be generated for it:
>
> - Capitalized variables (PascalCase) generate AST nodes by default, so they can always trigger hooks.
> - Helper variables starting with an underscore (e.g. `_OptionalBlank`) do *not* generate AST nodes, so hooks attached to them will not execute.
> - Terminals do *not* generate AST nodes unless the `--ast-for-terminals` generator flag is active.

---

## Explicit Hook Annotations

You can explicitly bind a procedure to a grammar symbol by appending `@procedure_name`:

### 1. LHS Variable Hooks

Attaches directly to the left-hand-side variable name. The procedure executes whenever this variable is reduced anywhere in the grammar:

```
Value@dropChildren
| Object OptionalBlank
| Array OptionalBlank
```

### 2. RHS Symbol Hooks

Attaches to a specific symbol on the right-hand side of a production (which can be a variable, or a terminal symbol if `--ast-for-terminals` is enabled). The procedure executes only when that symbol is matched in that particular position:

```
ArrayMembers
| Value ArrayMembersTail@replaceWithChildren "]"

ObjectMember
| String OptionalBlank ":"@myColonHook OptionalBlank Value

Number
| digit@myDigitHook _PositiveIntegerNumberTail
```

### 3. Production Hooks

Attaches to an entire right-hand-side production by placing the hook immediately after the initial pipe (`|`). The procedure executes when the complete production is reduced:

```
FloatTail@dropSelf
|@dropSelf "." PositiveIntegerNumber
|
```

### 4. Chaining Multiple Hooks

You can chain multiple hooks together on the same symbol or production by appending them sequentially (e.g., `@hook1@hook2`).

When multiple hooks are chained, they are executed in **left-to-right order** (the leftmost hook executes first). This acts like function composition, where the leftmost hook operates on the raw match first before passing the result to the next hook to the right:

```
Expr
| "+" Number@my_hook1@my_hook2
```

In the example above, `my_hook1` runs first, followed immediately by `my_hook2`.

---

## Implicit / Automatic Hooks

In addition to explicit annotations, the generator automatically binds and executes procedures based on convention names exported by your `procedures.zig`:

| Procedure Name | Execution Trigger |
| :--- | :--- |
| `reduction_<SymbolName>` | If exported, executes automatically as a hook for the grammar symbol `<SymbolName>` (e.g., `reduction_Expr` runs automatically whenever the `Expr` rule is reduced, as if `@reduction_Expr` was explicitly attached to it). |
| `reduction` | If exported, executes automatically as a fallback hook for *every* symbol reduced in the grammar (as if `@reduction` was attached to all symbols). |

---

## Writing Hook Functions in Zig

All custom procedures are defined inside your language's `procedures.zig`.

### Function Signature

Every hook function must match the following signature:

```zig
const ProcedureArguments = @import("root").data_structures.ProcedureArguments;

pub fn myHook(args: *ProcedureArguments) !void {
    // If the node was allocated, inspect or modify it
    if (args.node) |node_address| {
        var node = args.context.node_allocator.at(node_address);
        // Modify node.id, node.payload, node.children, etc.
    }
}
```

### Standard Helper Procedures

Many language implementations leverage standard tree-cleanup procedures:

- **`dropChildren`**: Discards all child nodes of the current node to save memory:

  ```zig
  pub fn dropChildren(args: *ProcedureArguments) !void {
      if (args.node) |node_address| {
          _ = try data_structures.ASTNode.cleanChildren(node_address, args.context.node_allocator);
      }
  }
  ```

- **`rightRecursiveReduction`** and **`leftRecursiveReduction`**: Flatten one level of a recursive node when its edge child has the same grammar variable:

  ```zig
  pub const reduction_ItemsTail_0 = standard_procedures.rightRecursiveReduction;
  ```

- **`dropSelf`**: Discards the current node itself by setting it to `null`:

  ```zig
  pub fn dropSelf(args: *ProcedureArguments) !void {
      args.node = null;
  }
  ```

- **`dropIfEmpty`**: Discards the current node when it has no children. This is useful for optional recursive tails:

  ```zig
  pub const dropIfEmpty = standard_procedures.dropIfEmpty;
  ```

- **`replaceWithChildren`**: Discards the current parent node's structure and replaces it with its first child in the AST hierarchy:

  ```zig
  pub fn replaceWithChildren(args: *ProcedureArguments) !void {
      if (args.node) |node_address| {
          var node = args.context.node_allocator.at(node_address);
          if (node.children.first) |first_child| {
              args.node = first_child;
          }
      }
  }
  ```

### Custom State & Payload

You can define a custom state structure inside `procedures.zig` to keep track of variables or parse state. Export a public `Payload` struct, which will be initialized per-parse:

```zig
pub const Payload = struct {
    nesting_depth: u32 = 0,
    variable_count: u32 = 0,
};
```

Within any hook function, access your payload instance via `args.context.payload`:

```zig
pub fn enter_block(args: *ProcedureArguments) !void {
    args.context.payload.nesting_depth += 1;
}
```
