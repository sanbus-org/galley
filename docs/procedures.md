# Reduction Procedures

## Table of Contents

- [Overview](#overview)
- [How Procedures Work](#how-procedures-work)
- [AST Generation Requirement](#ast-generation-requirement)
- [Explicit Hook Annotations](#explicit-hook-annotations)
  - [1. LHS Variable Hooks](#1-lhs-variable-hooks)
  - [2. RHS Symbol Hooks](#2-rhs-symbol-hooks)
  - [3. Production Hooks](#3-production-hooks)
  - [Chaining Multiple Hooks](#chaining-multiple-hooks)
- [Implicit / Automatic Hooks](#implicit--automatic-hooks)
- [Hook Execution Order](#hook-execution-order)
- [Writing Hook Functions in Zig](#writing-hook-functions-in-zig)
  - [Function Signature](#function-signature)
  - [Standard Helper Procedures](#standard-helper-procedures)
  - [Custom AST Node Payload](#custom-ast-node-payload)

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
Parent
| Value Child@validateChild "]"

ObjectMember
| String OptionalBlank ":"@myColonHook OptionalBlank Value

Number
| digit@myDigitHook _PositiveIntegerNumberTail
```

### 3. Production Hooks

Attaches to the left-hand-side variable for a specific right-hand-side production by placing the hook immediately after the initial pipe (`|`). The procedure executes on the resulting left-hand-side node only when that particular production is reduced:

```
FloatTail
|@normalizeFraction "." PositiveIntegerNumber
|
```

### Chaining Multiple Hooks

Chaining is not a separate hook kind. It applies multiple procedures to the same symbol or production by appending them sequentially (e.g., `@hook1@hook2`).

When multiple hooks are chained, they are executed in **left-to-right order** (the leftmost hook executes first). This acts like function composition, where the leftmost hook operates on the raw match first before passing the result to the next hook to the right:

```
Expr
| "+" Number@firstHook@secondHook
```

In the example above, `firstHook` runs first, followed immediately by `secondHook`.

---

## Implicit / Automatic Hooks

Alongside the three explicit hook placements, Galley provides a fourth family of automatic reduction hooks. They require no grammar annotations: the generator binds them by name when they are exported by your `procedures.zig`:

| Procedure Name | Execution Trigger |
| :--- | :--- |
| `reduction_<SymbolName>_<RhsIndex>` | Executes when the zero-based right-hand-side production `<RhsIndex>` of `<SymbolName>` is reduced (e.g. `reduction_Expr_0` runs only for the first `Expr` production). Indices follow the consecutive `|` lines beneath the variable's unique LHS header. |
| `reduction_<SymbolName>` | Executes whenever `<SymbolName>` produces an AST node, either by reducing a variable or matching an AST-enabled terminal. |
| `reduction` | Executes as the general hook for every eligible variable reduction and AST-enabled terminal match. |

---

## Hook Execution Order

For each eligible variable reduction, hooks execute from the most specific context to the most general:

1. Hooks attached to that variable's occurrence in its parent's right-hand side, in left-to-right chain order.
2. Hooks attached after the initial pipe of the selected production, in left-to-right chain order.
3. The automatic production hook `reduction_<SymbolName>_<RhsIndex>`, if exported.
4. Hooks attached to the variable's left-hand-side declaration, in left-to-right chain order.
5. The automatic symbol hook `reduction_<SymbolName>`, if exported.
6. The general `reduction` hook, if exported.

Each phase receives the node resulting from the preceding phase. An RHS occurrence hook belongs to the child variable's reduction and runs only when that child is reached through the annotated parent position. A child completes this sequence before its parent variable is reduced. The start variable has no parent RHS occurrence, and `reduction` runs once and last for each eligible reduction.

For an AST-enabled terminal match, only the applicable phases run:

1. Hooks attached to that terminal occurrence, in left-to-right chain order.
2. The automatic terminal hook `reduction_<SymbolName>`, if exported.
3. The general `reduction` hook, if exported.

Variable hooks receive the selected variable rule in `args.rule`. Terminals do not have a reduction rule, so terminal hooks receive `args.rule = null`. All phases share the same mutable `args.node`; dropping or replacing it is visible to every later hook.

An LR parser must know the parent occurrence when a variable reduces or terminal matches. If the active LR state and lookahead correspond to multiple occurrences with different hook chains, generation fails with `error.AmbiguousProcedureHooks` rather than running a hook for the wrong position. Identical chains may share the action.

---

## Writing Hook Functions in Zig

All custom procedures are defined inside your language's `procedures.zig`.

### Function Signature

Every hook function must match the following signature:

```zig
const data_structures = @import("galley").data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;

pub fn myHook(args: *ProcedureArguments) !void {
    // If the node was allocated, inspect or modify it
    if (args.node) |node_address| {
        const node = args.context.node_allocator.at(node_address);
        // Inspect the node or update its custom payload.
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
          args.node = data_structures.ASTNode.promoteChildrenOverWrapper(
              node_address,
              args.context.node_allocator,
          );
      }
  }
  ```

### Custom AST Node Payload

You can export a public `Payload` struct from `procedures.zig` to add language-specific data to every AST node. Each newly allocated node initializes its own payload using the struct's default field values:

```zig
pub const Payload = struct {
    nesting_depth: u32 = 0,
    variable_count: u32 = 0,
};
```

Within a hook, access the payload through the current AST node:

```zig
pub fn countVariable(args: *ProcedureArguments) void {
    if (args.node) |node_address| {
        const node = args.context.node_allocator.at(node_address);
        node.payload.variable_count += 1;
    }
}
```

`Payload` is node-local storage, not per-parse context state. Data shared by an entire parse must be managed separately rather than through `args.context.payload`, which does not exist.
