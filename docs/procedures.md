# Reduction Procedures

## Table of Contents

- [Overview](#overview)
- [How Procedures Work](#how-procedures-work)
- [AST and No-AST Modes](#ast-and-no-ast-modes)
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

Reduction procedures in Galley are user-defined semantic hooks written in Zig
(`procedures.zig`). They execute during parsing when the parser matches and
reduces grammar rules. Hooks can inspect spans and children, propagate typed
payloads, perform validation, and—with AST construction enabled—manipulate the
persistent syntax tree.

---

## How Procedures Work

1. **Source Generation:** The grammar generator parses your grammar file
   (`ll.grm` or `lr.grm`) and emits Zig parser source such as
   `_ll-parser.zig`.
2. **Binding:** For every hook reference (explicit or implicit), the generator checks if a public declaration with that name is exported by `languages/<name>/procedures.zig`.
3. **Execution:** During runtime, when the parser shifts or reduces the marked symbols, it calls the corresponding hook function, passing a mutable context.

---

## AST and No-AST Modes

> [!IMPORTANT]
> With `--no-ast`, semantic procedures still run without allocating an AST.
>
> Hook eligibility is identical in AST and no-AST procedure modes:
>
> - Capitalized variables are visible and trigger hooks.
> - Helper variables starting with an underscore (for example,
>   `_OptionalBlank`) and their suppressed subtrees produce no visible node or
>   hook.
> - Terminals are visible and trigger hooks only with `--ast-for-terminals`.

Both modes use the same `Node` type and the same `procedures.zig`. AST mode
stores persistent nodes in `ASTAllocator`. No-AST mode uses temporary nodes
whose child links are valid only during the current hook call. Payload values
may be copied into later reductions, and the start symbol's final payload is
returned as `ParseResult.semantic_root`.

Procedure-enabled parsers retain complete source input so hooks can read a
node's matched text from `args.context.getTextSlice(node.text_start,
node.text_length)`. The bounded sliding input window is used only when both AST
construction and procedures are disabled.

### No-AST Reduction Channel

In no-AST mode a node's children remain readable during its hook call, and
payloads accumulate into the start symbol's final payload. `currentNode()`
returns a pointer to the temporary node; iterate its children with
`node.childIterator(context)`, reading each child's `payload`:

```zig
pub fn reduction_List(args: *ProcedureArguments) !void {
    const node = args.currentNode() orelse return;
    var iterator = node.childIterator(args.context);
    var sum: usize = 0;
    while (iterator.next()) |child| sum += child.payload.value;
    node.payload.value = sum;
}
```

Payload values begin at the struct defaults and are copied into later
reductions as each hook runs. After parsing, the start symbol's payload is
available as `ParseResult.semantic_root`:

```zig
var parsed = try parser.parseBytes(io, allocator, input, .{});
defer parsed.deinit();
if (parsed.result.semantic_root) |root| {
    std.debug.print("value = {d}\n", .{root.value});
}
```

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
| `reduction_<SymbolName>` | Executes whenever `<SymbolName>` produces a visible node, either by reducing a variable or matching an enabled terminal. |
| `reduction` | Executes as the general hook for every eligible variable reduction and visible terminal match. |

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

For a terminal match enabled by `--ast-for-terminals`, only the applicable phases run:

1. Hooks attached to that terminal occurrence, in left-to-right chain order.
2. The automatic terminal hook `reduction_<SymbolName>`, if exported.
3. The general `reduction` hook, if exported.

Variable hooks receive the selected variable rule in `args.rule`. Terminals do
not have a reduction rule, so terminal hooks receive `args.rule = null`.
`args.currentNode()` returns a direct pointer to the current `Node`; ordinary
hooks mutate its span or payload in place. Node storage never relocates, so the
pointer stays valid even when the hook (or a tree helper it calls) allocates
further nodes. In AST mode, tree helpers may replace or remove the stable
allocator address through `args.node_address`; `currentNode()` resolves from
that address, so it reflects any drop or replacement performed by an earlier
hook phase.

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
    if (args.currentNode()) |node| {
        const text = args.context.getTextSlice(node.text_start, node.text_length);
        _ = node.variable;
        _ = text;
    }
}
```

`args.node_address` and `args.context.node_allocator` exist only when AST
construction is enabled. Code that allocates or restructures tree nodes must
use those fields and intentionally fails to compile in no-AST mode.

### Standard Helper Procedures

Many language implementations leverage standard tree-cleanup procedures:

The helpers below manipulate AST nodes and require AST construction. In no-AST
mode they fail to compile unless the parser is generated with
`--allow-no-ast-tree-procedures`, in which case each becomes a no-op.

- **`dropChildren`**: Discards all child nodes of the current node to save memory:

  ```zig
  pub fn dropChildren(args: *ProcedureArguments) !void {
      if (args.node_address) |node_address| {
          _ = try data_structures.Node.cleanChildren(node_address, args.context.node_allocator);
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
      args.node_address = null;
  }
  ```

- **`dropIfEmpty`**: Discards the current node when it has no children. This is useful for optional recursive tails:

  ```zig
  pub const dropIfEmpty = standard_procedures.dropIfEmpty;
  ```

- **`replaceWithChildren`**: Discards the current parent node's structure and replaces it with its first child in the AST hierarchy:

  ```zig
  pub fn replaceWithChildren(args: *ProcedureArguments) !void {
      if (args.node_address) |node_address| {
          args.node_address = data_structures.Node.promoteChildrenOverWrapper(
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

Within a hook, access the payload through the direct current node pointer in
either mode:

```zig
pub fn countVariable(args: *ProcedureArguments) void {
    if (args.currentNode()) |node| {
        node.payload.variable_count += 1;
    }
}
```

`Payload` is node-local storage, not per-parse context state. Data shared by an entire parse must be managed separately rather than through `args.context.payload`, which does not exist.
