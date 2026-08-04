# Grammar Writing Guidelines

## Table of Contents

- [1. File Structure & Rule Syntax (`.grm` files)](#1-file-structure--rule-syntax-grm-files)
- [2. Variable Naming & AST Generation](#2-variable-naming--ast-generation)
- [3. Terminal Symbols](#3-terminal-symbols)
- [4. Procedure Hooks (`@procedure_name`)](#4-procedure-hooks-procedure_name)
- [5. Explicit Syntax Recovery (`!`)](#5-explicit-syntax-recovery-)
- [6. Indentation-Sensitive Grammars](#6-indentation-sensitive-grammars)
- [7. Operator Precedence & Ambiguity-Free Expression Extraction](#7-operator-precedence--ambiguity-free-expression-extraction)

---

This guide details the syntax, conventions, and compile-time annotations supported by this repository's parser generators (LL and LR).

---

## 1. File Structure & Rule Syntax (`.grm` files)

- **Rule Structure:**
  Each grammar rule is defined by the LHS (Left-Hand Side) variable symbol on a single line, followed by its alternative productions.
- **Unique Rule Headers:**
  Each variable must have exactly one LHS header. Put all of its alternatives on consecutive `|` lines beneath that header; declaring the same LHS again is an error.
- **Alternation:**
  Each alternative production must start with a pipe character `|` on a new line, followed by space-separated symbols:

  ```
  Value
  | "{" OptionalBlank ObjectMembers OptionalBlank
  | "null" OptionalBlank
  ```

- **Epsilon (Empty Productions):**
  An empty production is represented by a single pipe `|` with no trailing symbols:

  ```
  OptionalBlank
  | space _OptionalBlankTail
  |
  ```

- **Formatting:** Rules must be separated by at least one blank line. The first variable defined in the file is automatically treated as the parser's entry point.

---

## 2. Variable Naming & AST Generation

The parser generator statically configures the Abstract Syntax Tree (AST) node creation based on the naming style of the variable symbols:

- **PascalCase Validation:** All variable names must be written in PascalCase. The generator validates this at compile-time.
- **AST-Enabled Variables:** Variables starting with a Capital letter (e.g. `Value`, `ObjectMembers`) allocate an AST node when matched.
- **AST-Suppressed Helper Variables:** Variables starting with an underscore (e.g. `_StringContent`, `_OptionalBlank`) are helper rules. The generator completely skips allocating AST nodes for them, optimizing runtime parsing performance and memory footprint.

---

## 3. Terminal Symbols

Terminals in rules represent either exact character literals or pre-defined generative character classes:

- **Normal Terminals:** Exact character/string matches can be written in one of two quoting styles:
  - **Double-quoted:** Wrapped in double quotes (e.g., `"{"`, `"null"`, `"+"`).
  - **Single-quoted:** Wrapped in single quotes at the start and terminating with the `\x03` (0x03) byte (e.g., `'"\x03` representing the `"` character).
  - Valid UTF-8 can be written directly in either form (e.g., `"سلام"` or `"😀"`).
  - `\u{...}` inserts one Unicode scalar value using one to six hexadecimal digits (e.g., `"\u{1f600}"`). Surrogate code points and values above `U+10FFFF` are rejected.
  - Existing byte escapes such as `"\x03"` remain available when an exact byte is more convenient than a literal character.
- **Generative Character Terminals:** Unquoted keyword names map to specific sets of ASCII characters:
  - `digit`: Matches `'0'-'9'`
  - `hex_digit`: Matches `'0'-'9'`, `'a'-'f'`, and `'A'-'F'`
  - `letter`: Matches `'a'-'z'` and `'A'-'Z'`
  - `lowercase_letter`: Matches `'a'-'z'`
  - `uppercase_letter`: Matches `'A'-'Z'`
  - `whitespace`: Matches whitespace characters (`\t`, `\n`, `\r`, `\x0b`, `\x0c`, ` `)
  - `punctuation`: Matches standard punctuation characters
  - `character`: Matches letters, digits, punctuation, and whitespace
  - `operator`: Matches operator symbols (`+`, `*`, `/`, `&`, `|`, `>`, `>=`, `<`, `<=`, `=`)
  - `new_line`: Matches `\n`
  - `space`: Matches space `' '`
  - `block_start`: Matches control character `\x01` (representing the start of a block when indentation syntax is enabled for the parser, see [Language Configuration](configuration.md#language-configuration) for details)
  - `block_end`: Matches control character `\x02` (representing the end of a block when indentation syntax is enabled for the parser, see [Language Configuration](configuration.md#language-configuration) for details)
- **UTF-8 Byte-Class Terminals:** These single-byte generative terminals can be composed into grammar rules that accept every valid UTF-8 scalar while rejecting overlong encodings, surrogate encodings, and values above `U+10FFFF`:
  - `utf8_lead_two`: Two-byte sequence leads (`0xC2`-`0xDF`)
  - `utf8_lead_three_general`: General three-byte leads (`0xE1`-`0xEC`, `0xEE`-`0xEF`)
  - `utf8_lead_four_general`: General four-byte leads (`0xF1`-`0xF3`)
  - `utf8_continuation`: Any continuation byte (`0x80`-`0xBF`)
  - `utf8_continuation_80_8f`, `utf8_continuation_80_9f`, `utf8_continuation_90_bf`, and `utf8_continuation_a0_bf`: Restricted continuation ranges used at UTF-8 boundary cases

  See `languages/json-unicode/ll.grm` and `languages/json-unicode/lr.grm` for complete LL and LR scalar rules built from these terminals.
- **Generative Suffix Exceptions:** Any generative terminal can have exceptions appended as a suffix chain introduced by the `^` character followed by a normal terminal (e.g., `character^"\n"`, `character^'"\x03`, or multiple chained exceptions like `digit^"1"^"3"`). The exception terminal's characters are excluded from the allowed terminal characters of the generative class.

---

## 4. Procedure Hooks (`@procedure_name`)

Galley provides three explicit hook placements, registered by appending a procedure name with `@`, and a fourth family of automatic reduction hooks:

1. **LHS Variable Hook:** Attaches to the left-hand-side variable definition, executing whenever this variable is reduced anywhere:

   ```
   Value@dropChildren
   | Object OptionalBlank
   | Array OptionalBlank
   ```

2. **RHS Symbol Hook:** Attaches to a right-hand-side symbol (either a variable, or a terminal symbol if `--ast-for-terminals` is active), executing only when matched in that position:

   ```
   Parent
   | Value Child@validateChild "]"

   Number
   | digit@recordDigit _PositiveIntegerNumberTail
   ```

3. **Production Hook:** Attaches to the left-hand-side variable for a specific right-hand-side production. It is placed immediately after the pipe (`|`) and executes on the resulting left-hand-side node only when that particular production is reduced:

   ```
   FloatTail
   |@normalizeFraction "." PositiveIntegerNumber
   |
   ```

4. **Automatic Reduction Hooks:** Exporting conventionally named public procedures from `procedures.zig` binds them without grammar annotations:

   - `reduction_<SymbolName>_<RhsIndex>` runs only for the zero-based production index of that symbol. Indices follow the consecutive `|` lines beneath the variable's unique LHS header.
   - `reduction_<SymbolName>` runs whenever that symbol produces an AST node.
   - `reduction` runs for every eligible variable reduction and AST-enabled terminal match.

Multiple procedures can be chained on any explicit hook target (for example, `Number@hook1@hook2`). Chaining runs the procedures from left to right; it is not a separate hook kind.

For each variable reduction, hooks run in this order: RHS occurrence hooks, production hooks, `reduction_<SymbolName>_<RhsIndex>`, LHS hooks, `reduction_<SymbolName>`, then the general `reduction` hook. Each explicit chain runs left to right, and each phase receives the node produced by the preceding phase.

For an AST-enabled terminal, the occurrence chain runs first, followed by `reduction_<SymbolName>` and then `reduction`. Terminal hooks receive `args.rule = null`. LR generation reports `error.AmbiguousProcedureHooks` if the parser cannot distinguish occurrences with different chains at the match or reduction point.

---

For detailed information on automatic hooks, nested reduction ordering, compiler AST requirements, and how to write hook functions in Zig, see the [Reduction Procedures User Guide](procedures.md).

## 5. Explicit Syntax Recovery (`!`)

Recovery annotations declare synchronization terminals on an LHS variable, a production, or an RHS variable occurrence:

```text
Statement!^"}"!";"^@hook
|!","^ Expression
| Block Statement!^"}"
```

- `!^"}"` resumes immediately before `}` and preserves the terminal for the surrounding parser state.
- `!";"^` resumes immediately after `;` and consumes the terminal.
- Consecutive annotations provide multiple candidates for one target. They must appear before any `@` hooks on that target.
- Recovery terminals accept the same two quoted exact-terminal forms as normal grammar terminals. Empty terminals, NUL-containing terminals, and generative terminals are invalid.
- An RHS recovery annotation may only attach to a variable occurrence, not a terminal occurrence.

When error recovery generation is enabled and the grammar has no annotations, Galley uses automatic recovery. The presence of any recovery annotation selects explicit-only recovery for the generated parser; an error outside committed annotated scopes fails immediately without automatic fallback. When recovery generation is disabled, annotations remain in the grammar model but are inert, and generation emits one warning.

After a mismatch, Galley tries committed scopes from the most specific to the most general: the active RHS occurrence, its selected production, its LHS variable, then enclosing reductions. Within one target it chooses the earliest candidate in the input, then the longest terminal, then source order. A successful recovery preserves the original mismatch diagnostic, adds structured recovery context, neutral-completes the damaged variable, and skips hooks belonging to the damaged occurrence, production, and variable.

Galley's own [LL grammar](https://github.com/sanbus-org/galley/blob/main/languages/galley/ll.grm) and [LR grammar](https://github.com/sanbus-org/galley/blob/main/languages/galley/lr.grm) are maintained examples. They recover a damaged `Symbol` before its newline, discard a damaged `RightHandSideLine` after its newline, and fall back from a damaged `Rule` to the blank line before the next rule. Run `zig build compare-galley-recovery` to see the annotated LL grammar and an annotation-free clone parse the same malformed grammar in explicit and automatic modes.

---

## 6. Indentation-Sensitive Grammars

Set `pub const indentation_syntax = true;` in `config.zig` to make the generated
lexer translate line indentation into explicit block tokens. Grammar rules then
match them through three generative terminals:

| Terminal | Byte | Meaning |
| :--- | :--- | :--- |
| `block_start` | `\x01` | One level of indentation was opened. |
| `block_end` | `\x02` | One level of indentation was closed. |
| `new_line` | `\n` | A line boundary at the same indentation level. |

Galley's `languages/ll1/ll.grm` is a maintained example: blocks are written as
`block_start Fields block_end`, and a sequence of same-level rows joins them with
`new_line`.

### Tokenization Rules

- Indentation is measured **only on lines that follow a newline**. The very
  first line of a file has no preceding newline, so its leading spaces are
  ordinary `' '` tokens, not indentation.
- Only literal ASCII spaces count. Leading tabs are not indentation; a line
  that begins with a tab is treated as being at level 0, and the tab itself is
  tokenized normally.
- `indent_width` snaps to the leading-space count of the first line that follows
  a newline. Every later line's leading spaces must be an integer multiple of
  that width; otherwise parsing fails with a structured `IndentationError`
  ("N spaces are not divisible by the detected indentation width of M").
- Each line's indentation level is `leading_spaces / indent_width`. Compared
  with the previous line's level:
  - same level → one `new_line` token;
  - `k` levels deeper → `k` `block_start` tokens;
  - `k` levels shallower → `k` `block_end` tokens.

  The leading spaces themselves are consumed and never appear as tokens.
- A blank line (zero leading spaces) closes every open block with one
  `block_end` each, snapping the level to 0; the next indented line re-opens the
  blocks with `block_start` tokens. So blocks that must survive blank lines
  cannot be written directly — the grammar must accept the close/reopen pair.
- End of input emits no implicit closing tokens. A grammar that expects a block
  to be closed must match the trailing `block_end`s itself.

---

## 7. Operator Precedence & Ambiguity-Free Expression Extraction

The most common source of grammar ambiguity is a **shared operator nonterminal**
used by more than one precedence level:

```
Expression
| Expression Operator Expression
| "(" Expression ")"
| Number

Operator
| "+"
| "*"
```

Because both `+` and `*` collapse into one `Operator` symbol, the parser cannot
tell them apart at a single decision point: the LL planner reports
`ambiguous grammar: variable <X>, terminal "<t>" matches two productions`, and
the LR planner reports conflicting shift/reduce actions. There is no grammar
annotation that rescues this shape — the fix is structural.

### Rule 1: Give each precedence level its own operator

Split the shared `Operator` into one nonterminal per precedence level and
nest the levels so the tighter-binding operators are lower:

```
Expression
| Expression "+" Term
| Term

Term
| Term "*" Factor
| Factor

Factor
| "(" Expression ")"
| Number
```

Now `+` and `*` are distinct terminals at distinct levels, and the nesting
(`Expression` → `Term` → `Factor`) encodes precedence directly.

### Rule 2: LL(1) additionally requires the grammar to be left-factored

The LR generator accepts the left-recursive form above. The LL generator does
not: productions sharing a prefix — including `Expression | Expression "+" Term
| Term`, which both start with `Expression` — conflict in their FIRST sets. For
LL, hoist the recursion into a tail nonterminal and factor shared prefixes:

```
Expression
| Term ExpressionTail

ExpressionTail
| "+" Term ExpressionTail
|

Term
| Factor TermTail

TermTail
| "*" Factor TermTail
|

Factor
| "(" Expression ")"
| Number
```

When two productions of a variable do share a nonempty prefix, generation warns
with a suggested left-factored rewrite (a fresh `<Variable>_Tail` production),
as in:

```
warning: ambiguous grammar: variable Root, terminal ":" matches two productions:
  Root -> ":" Fields ActionTail
  Root -> ":" ActionTail
warning:   suggestion: left-factor the shared prefix
  Root -> ":" Root_Tail
  Root_Tail -> Fields ActionTail
  Root_Tail -> ActionTail
```

### Rule 3: Keep mixed-associativity operators at separate levels

Operators that associate differently (e.g. left-associative `-`, right-associative `^`)
must live at different precedence levels, each with its own recursion direction
(right recursion for right-associativity in LL, left recursion for
left-associativity in LR).

Galley's `languages/ll1/ll.grm` demonstrates the per-level pattern with
`Expression` / `ExpressionTail`, `OperandAndNumber`, and `Operand`/`OperandTail`
for suffix calls, list gets, and casts.
