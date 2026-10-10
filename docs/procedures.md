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
  - [Terminal Hooks](#terminal-hooks)
  - [Hook Names Outside Zig](#hook-names-outside-zig)
- [Hook Execution Order](#hook-execution-order)
- [Semantic Errors](#semantic-errors)
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
persistent syntax tree. The native example is
[`examples/zig/procedures.zig`](https://github.com/sanbus-org/galley/tree/main/examples/zig/procedures.zig);
the other `examples/` directories implement the same hooks through the C ABI.

---

## How Procedures Work

1. **Source Generation:** The grammar generator parses your grammar file
   (`ll.grm` or `lr.grm`) and emits Zig parser source such as
   `_ll-parser.zig`.
2. **Binding:** For every hook reference (explicit or implicit), the generator checks if a public declaration with that name is exported by `languages/<name>/procedures.zig`. An annotation `@print` binds the declaration `hook_print`; automatic hooks bind their `reduction` names.
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
var parsed = try parser.parseBytes(io, allocator, input, null, .{});
defer parsed.deinit();
if (parsed.result.semantic_root) |root| {
    std.debug.print("value = {d}\n", .{root.value});
}
```

---

## Explicit Hook Annotations

You can explicitly bind a procedure to a grammar symbol by appending `@name`. The annotation binds the declaration `hook_<name>`: `@dropChildren` runs `hook_dropChildren` from your `procedures.zig`, which must declare it. Bare names are never hooks.

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
| `reduction_<Variable>` | Executes whenever the variable `<Variable>` produces a visible node by reduction. |
| `reduction_"<spelling>"`, `reduction_<stem>` | Execute whenever a terminal matches. See [Terminal Hooks](#terminal-hooks). |
| `reduction` | Executes as the general hook for every eligible variable reduction and visible terminal match. |

Missing automatic hooks are silent nulls by default. Set `require_reduction_procedures = true` in `config.zig` (or pass `--require-reduction-procedures`) to warn at generation and fail compilation for any visible production without `reduction_<SymbolName>_<RhsIndex>`, naming variable, index, and shape.

Variables whose names begin with `_` produce no visible node, so neither they nor their productions bind automatic hooks; that includes the generator's own `_AugmentedStart` and `_GenerativeTerminal`. Synthetic `<Variable>_Tail` helpers from automatic left-factoring expand inline into their parent and bind none either.

### Terminal Hooks

A terminal matches with a hook only under `--ast-for-terminals`. Each terminal can be hooked under two names, and the generator looks them up in this order:

1. The readable name: `reduction_` followed by the terminal's decoded byte spelling in a fixed pair of double quotes, `reduction_"<spelling>"`. The spelling derives from the bytes the terminal matches, not from its text in the grammar source: newline, tab, carriage return and backslash are escaped as `\n`, `\t`, `\r` and `\\`; every other control byte and every byte from `0x7f` up is escaped as lowercase `\xNN`. Bytes from `0x20` to `0x7e` appear literally, so a `"` inside the fixed quote pair is not escaped — the terminal `"\u{22}"` reads `reduction_"""`. Most readable names are not valid Zig identifiers; declare them with `@"..."`.
2. The identifier-safe name: `reduction_` followed by the terminal's generated identifier stem, the same stem LL parser function names use. The stem is `terminal_` (`generative_terminal_` for generative terminals) plus the readable spelling with every byte other than a letter, digit or `_` replaced by `_x<decimal byte value>`. The escaping is applied to the already backslash-escaped readable spelling, so a tab, spelled `\t`, becomes `_x92t`, not `_x9`.

If both names are declared, the readable one runs and the other is ignored without a warning. Each terminal costs exactly these two lookups.

| Terminal | Readable hook name | Identifier-safe hook name |
| :--- | :--- | :--- |
| `"{"` | `@"reduction_\"{\""` | `reduction_terminal__x123` |
| `"A"` | `@"reduction_\"A\""` | `reduction_terminal_A` |
| `"null"` | `@"reduction_\"null\""` | `reduction_terminal_null` |
| `","` | `@"reduction_\",\""` | `reduction_terminal__x44` |
| `"\t"` | `@"reduction_\"\\t\""` | `reduction_terminal__x92t` |
| `"\u{7}"` | `@"reduction_\"\\x07\""` | `reduction_terminal__x92x07` |
| `digit` (generative) | `reduction_digit` | `reduction_generative_terminal_digit` |

Rules that follow:

- Variables bind `reduction_<Variable>` only. A terminal `"A"` and a variable `A` may coexist; `reduction_A` hooks the variable and `@"reduction_\"A\""` hooks the terminal.
- Generative terminals are written unquoted, and so is their readable hook name: `reduction_digit`, `reduction_letter`. The name is the terminal's identifier re-serialized, exception chain included: with an exception it reads `@"reduction_digit^\"1\""`. A generative terminal and a literal terminal spelled alike (`digit` and `"digit"`) therefore bind separately.
- The unquoted spelling of a literal terminal (`reduction_{`, `reduction_null`) is not a hook name and never binds.
- Generation fails with `error.SymbolNameCollision`, naming both, when two symbols or productions would bind one hook name: for example `","` and `"_x44"` (both `reduction_terminal__x44`), or the first production of `A` and a variable `A_0` (both `reduction_A_0`). Rename one of them.
- End of input has no hook: it never produces a node, so it has neither a readable nor an identifier-safe hook name, and a terminal `"\u{0}"` owns `@"reduction_\"\\x00\""`.

### Hook Names Outside Zig

Python, Java and JavaScript install hooks by name at runtime, and a built library lists the names it accepts (`galley_hooks_count`, `galley_hooks_name_data`). The list is the generated parser's own hook table: every hook the parser binds, each under one name that is a valid identifier in every language:

- `reduction`, `reduction_<Variable>` and `reduction_<Variable>_<RhsIndex>`, as in Zig.
- `reduction_<stem>` for a terminal: the identifier-safe name from [Terminal Hooks](#terminal-hooks) (`reduction_terminal__x123` for `"{"`, `reduction_generative_terminal_digit` for `digit`). The readable spellings, `reduction_"<spelling>"` and a generative terminal's `reduction_<id>`, are Zig-only.
- `hook_<name>` for every annotation `@name`.

Installing a name outside the list raises the host's argument error, suggesting `hook_<name>` or `reduction_<name>` when the artifact defines it. With `procedures = false` the list is empty and every install raises.

C, C++, Rust and Go hooks are compiled into the library instead. `--emit-metadata` writes `procedures.zig` declaring only `reduction`, `reduction_<Variable>` and `hook_<name>`, and the consumer must define every one of them, so terminal and per-production hooks are not reachable from those languages yet. The planned fix declares hooks in `procedures.h`, translated with `addTranslateC`, so a consumer defines only the hooks it implements and every name in the list becomes reachable. `metadata.json` lists the same declared subset under `procedures`.

---

## Hook Execution Order

For each eligible variable reduction, hooks execute from the most specific context to the most general:

1. Hooks attached to that variable's occurrence in its parent's right-hand side, in left-to-right chain order.
2. Hooks attached after the initial pipe of the selected production, in left-to-right chain order.
3. The automatic production hook `reduction_<SymbolName>_<RhsIndex>`, if exported.
4. Hooks attached to the variable's left-hand-side declaration, in left-to-right chain order.
5. The automatic variable hook `reduction_<Variable>`, if exported.
6. The general `reduction` hook, if exported.

Each phase receives the node resulting from the preceding phase. An RHS occurrence hook belongs to the child variable's reduction and runs only when that child is reached through the annotated parent position. A child completes this sequence before its parent variable is reduced. The start variable has no parent RHS occurrence, and `reduction` runs once and last for each eligible reduction.

A variable flattened with `@<` builds no node where it is flattened, so none of these phases run for it there; its children join the node around it, which runs its own hooks as usual. See [Flattening](grammar_guidelines.md#9-flattening).

For a terminal match enabled by `--ast-for-terminals`, only the applicable phases run:

1. Hooks attached to that terminal occurrence, in left-to-right chain order.
2. The automatic terminal hook, if exported (see [Terminal Hooks](#terminal-hooks)).
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

## Semantic Errors

A hook reports a semantic error when the input parses but its meaning is invalid (undeclared variable, duplicate key, out-of-range value). Call the single gate:

```zig
pub fn reduction_Item_1(args: *ProcedureArguments) !void {
    _ = try args.reportSemanticError("unexpected item");
}
```

The gate records an arena-backed diagnostic, marks the current node (`is_semantic_error = true`), and returns the total count so hooks can limit themselves:

```zig
const count = try args.reportSemanticError("duplicate key");
if (count > 200) return;
```

Parsing continues after each report, so one parse aggregates many errors. A syntax-clean parse with any semantic error returns `ParseError.SemanticError`; syntax errors keep precedence. Read diagnostics through `recordedDiagnostics()` / `lastDiagnostic()` and counts through `semanticErrorCount()`. In AST mode, parents stay unmarked — call `Node.hasSemanticErrorSubtree(address, allocator)` to check a subtree before emitting follow-on diagnostics. In no-AST mode, check child `is_semantic_error` flags directly during the hook call. A diagnostic survives even when a later hook phase drops its node. A parse that returns `ParseError.SemanticError` has run to its end, so its tree is published with the marked nodes: read it with `session.readCurrent()`, or walk it with `skip_semantic_error_subtrees` to see only the valid parts (the host bindings expose the same flag and skip option). Template overrides in `config.zig` and per-session `message_overrides` apply to syntax errors only.

### Failing a hook

A hook that returns an error aborts the parse: the error propagates out of `parse*` and the parse publishes nothing. Use it for failures the parse cannot continue after; a hook that wants the parse to go on reports a semantic error instead. A hook of a host binding (Python, Java, JavaScript) that raises is the same: the host shim returns `error.HookFailed`, the parse stops where the hook ran, and `lastDiagnostic()` is a `.hook` diagnostic carrying the position, the variable being parsed and the hook's name. The binding raises its own failure from `parse` with the hook's exception as the cause.

---

## Writing Hook Functions in Zig

All custom procedures are defined inside your language's `procedures.zig`.

### Function Signature

Every hook function must match the following signature. This one runs for the annotation `@myHook`:

```zig
const data_structures = @import("galley").data_structures;
const ProcedureArguments = data_structures.ProcedureArguments;

pub fn hook_myHook(args: *ProcedureArguments) !void {
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

Tree edits go through the public `Node` functions (`insertBefore`,
`removeSelf`, `cleanChildren`, ...). They assert misuse in Debug builds only;
release builds do not check, and misuse corrupts the tree. The `immediate*`
tier is internal to generated parsers (see
[Immediate Tree Edits](/architecture#immediate-tree-edits)).

Two rules follow from how generated parsers use the tree:

- A hook that replaces the node (`args.node_address = ...`) must hand back a
  node or chain that is detached, such as the result of `cleanChildren` or
  `replaceWithChildren`. Handing back a node that is still attached to a
  parent, for example the node's own first child, lists it under two parents.
- A hook must not detach an ancestor of the node being reduced. A repetition
  climbs from each wrapper to the one enclosing it, so a detached ancestor
  skips the outer procedures of that repetition.

### Standard Helper Procedures

Many language implementations leverage standard tree-cleanup procedures:

The helpers below manipulate AST nodes and require AST construction. In no-AST
mode they fail to compile unless the parser is generated with
`--allow-no-ast-tree-procedures`, in which case each becomes a no-op.

Each is a public function of `standard_procedures`; an annotation reaches it through a re-export under its `hook_` name, for example `pub const hook_dropIfEmpty = standard_procedures.dropIfEmpty;`. The sketches below show what each one does.

- **`dropChildren`**: Discards all child nodes of the current node to save memory:

  ```zig
  pub fn hook_dropChildren(args: *ProcedureArguments) !void {
      if (args.node_address) |node_address| {
          _ = data_structures.Node.cleanChildren(node_address, args.context.node_allocator);
      }
  }
  ```

- **`rightRecursiveReduction`** and **`leftRecursiveReduction`**: Flatten one level of a recursive node when its edge child has the same grammar variable:

  ```zig
  pub const reduction_ItemsTail_0 = standard_procedures.rightRecursiveReduction;
  ```

- **`dropSelf`**: Discards the current node itself by setting it to `null`:

  ```zig
  pub fn hook_dropSelf(args: *ProcedureArguments) !void {
      args.node_address = null;
  }
  ```

- **`dropIfEmpty`**: Discards the current node when it has no children. This is useful for optional recursive tails:

  ```zig
  pub const hook_dropIfEmpty = standard_procedures.dropIfEmpty;
  ```

- **`replaceWithChildren`**: Detaches the current node and puts all of its children in its place among its siblings. With no children the result is `null` and the node stays; a node without a parent yields its children as a detached chain:

  ```zig
  pub fn hook_replaceWithChildren(args: *ProcedureArguments) !void {
      if (args.node_address) |node_address| {
          args.node_address = data_structures.Node.immediatePromoteChildrenOverWrapper(node_address, args.context.node_allocator);
      }
  }
  ```

  `immediatePromoteChildrenOverWrapper` is internal: it does the splice in one pass and leaves the node fully detached. A host that wants the same result through the public tier calls `cleanChildren`, `insertBefore`, and `removeSelf`, which gives the same tree in several passes.

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
pub fn hook_countVariable(args: *ProcedureArguments) void {
    if (args.currentNode()) |node| {
        node.payload.variable_count += 1;
    }
}
```

`Payload` is node-local storage, not per-parse context state. Data shared by an entire parse must be managed separately rather than through `args.context.payload`, which does not exist.
