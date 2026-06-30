# Grammar Writing Guidelines

## Table of Contents

- [1. File Structure & Rule Syntax (`.grm` files)](#1-file-structure--rule-syntax-grm-files)
- [2. Variable Naming & AST Generation](#2-variable-naming--ast-generation)
- [3. Terminal Symbols](#3-terminal-symbols)
- [4. Procedure Hooks (`@procedure_name`)](#4-procedure-hooks-procedure_name)

---

This guide details the syntax, conventions, and compile-time annotations supported by this repository's parser generators (LL and LR).

---

## 1. File Structure & Rule Syntax (`.grm` files)

- **Rule Structure:**
  Each grammar rule is defined by the LHS (Left-Hand Side) variable symbol on a single line, followed by its alternative productions.
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
- **Non-AST Helper Variables:** Variables starting with an underscore (e.g. `_StringContent`, `_OptionalBlank`) are helper rules. The generator completely skips allocating AST nodes for them, optimizing runtime parsing performance and memory footprint.

---

## 3. Terminal Symbols

Terminals in rules represent either exact character literals or pre-defined generative character classes:

- **Normal Terminals:** Exact character/string matches can be written in one of two quoting styles:
  - **Double-quoted:** Wrapped in double quotes (e.g., `"{"`, `"null"`, `"+"`).
  - **Single-quoted:** Wrapped in single quotes at the start and terminating with the `\x03` (0x03) byte (e.g., `'"\x03` representing the `"` character).
- **Generative Character Terminals:** Unquoted keyword names map to specific sets of ASCII characters:
  - `digit`: Matches `'0'-'9'`
  - `letter`: Matches `'a'-'z'` and `'A'-'Z'`
  - `lowercase_letter`: Matches `'a'-'z'`
  - `uppercase_letter`: Matches `'A'-'Z'`
  - `whitespace`: Matches whitespace characters (`\t`, `\n`, `\r`, `\x0b`, `\x0c`, ` `)
  - `punctuation`: Matches standard punctuation characters
  - `character`: Matches letters, digits, punctuation, and whitespace
  - `operator`: Matches operator symbols (`+`, `*`, `/`, `&`, `|`, `>`, `>=`, `<`, `<=`, `=`)
  - `new_line`: Matches `\n`
  - `space`: Matches space `' '`
  - `block_start`: Matches control character `\x01` (representing the start of a block when indentation syntax is enabled for the parser, see [Reduction Procedures](procedures.md#indentation-syntax) for details)
  - `block_end`: Matches control character `\x02` (representing the end of a block when indentation syntax is enabled for the parser, see [Reduction Procedures](procedures.md#indentation-syntax) for details)
- **Generative Suffix Exceptions:** Any generative terminal can have exceptions appended as a suffix chain introduced by the `^` character followed by a normal terminal (e.g., `character^"\n"`, `character^'"\x03`, or multiple chained exceptions like `digit^"1"^"3"`). The exception terminal's characters are excluded from the allowed terminal characters of the generative class.

---

## 4. Procedure Hooks (`@procedure_name`)

You can register custom semantic logic to run automatically during parsing by appending a procedure name with `@`. There are four kinds of explicit grammar hooks:

1. **LHS Variable Hook:** Attaches to the left-hand-side variable definition, executing whenever this variable is reduced anywhere:

   ```
   Value@drop_children
   | Object OptionalBlank
   | Array OptionalBlank
   ```

2. **RHS Symbol Hook:** Attaches to a right-hand-side symbol (either a variable, or a terminal symbol if `--ast-for-terminals` is active), executing only when matched in that position:

   ```
   ArrayMembers
   | Value ArrayMembersTail@replace_with_children "]"

   Number
   | digit@my_digit_hook _PositiveIntegerNumberTail
   ```

3. **Production Hook:** Attaches to a complete right-hand-side production, placed immediately after the pipe (`|`), executing when the production is reduced:

   ```
   FloatTail@drop_self
   |@drop_self "." PositiveIntegerNumber
   |
   ```

---

For detailed information on implicit hooks (`reduction`, `reduction_<SymbolName>`), compiler AST requirements, and how to write hook functions in Zig, see the [Reduction Procedures User Guide](procedures.md).
