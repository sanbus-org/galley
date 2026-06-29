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

* **Rule Structure:**
  Each grammar rule is defined by the LHS (Left-Hand Side) variable symbol on a single line, followed by its alternative productions.
* **Alternation:**
  Each alternative production must start with a pipe character `|` on a new line, followed by space-separated symbols:

  ```
  Value
   | "{" OptionalBlank ObjectMembers OptionalBlank
   | "null" OptionalBlank
  ```

* **Epsilon (Empty Productions):**
  An empty production is represented by a single pipe `|` with no trailing symbols:

  ```
  OptionalBlank
   | space _OptionalBlankTail
   |
  ```

* **Formatting:** Rules must be separated by at least one blank line. The first variable defined in the file is automatically treated as the parser's entry point.

---

## 2. Variable Naming & AST Generation

The parser generator statically configures the Abstract Syntax Tree (AST) node creation based on the naming style of the variable symbols:

* **PascalCase Validation:** All variable names must be written in PascalCase. The generator validates this at compile-time.
* **AST-Enabled Variables:** Variables starting with a Capital letter (e.g. `Value`, `ObjectMembers`) allocate an AST node when matched.
* **Non-AST Helper Variables:** Variables starting with an underscore (e.g. `_StringContent`, `_OptionalBlank`) are helper rules. The generator completely skips allocating AST nodes for them, optimizing runtime parsing performance and memory footprint.
* **The Root Wrapper:** The generator wraps the entry rule under `_AugmentedStart`. Since it begins with an underscore, it allocates no structural root nodes.

---

## 3. Terminal Symbols

Terminals in rules represent either exact character literals or pre-defined generative character classes:

* **String Literals:** Exact string matches must be wrapped in double quotes (e.g. `"{"`, `"null"`, `"+"`).
* **Generative Character Terminals:** Unquoted keyword names map to specific sets of ASCII characters:
  * `digit`: Matches `'0'-'9'`
  * `letter`: Matches `'a'-'z'` and `'A'-'Z'`
  * `lowercase_letter`: Matches `'a'-'z'`
  * `uppercase_letter`: Matches `'A'-'Z'`
  * `whitespace`: Matches whitespace characters (`\t`, `\n`, `\r`, `\x0b`, `\x0c`, ` `)
  * `punctuation`: Matches standard punctuation characters
  * `character`: Matches letters, digits, punctuation, and whitespace
  * `operator`: Matches operator symbols (`+`, `*`, `/`, `&`, `|`, `>`, `>=`, `<`, `<=`, `=`)
  * `new_line`: Matches `\n`
  * `space`: Matches space `' '`
  * `block_start`: Matches control character `\x01`
  * `block_end`: Matches control character `\x02`

---

## 4. Procedure Hooks (`@procedure_name`)

You can register custom semantic logic to run automatically upon reduction or symbol matching by appending a procedure name with `@`:

```
ArrayMembers
 | Value ArrayMembersTail@replace_with_children "]"
```

* **Integration:** During code generation, the parser generator binds `@replace_with_children` to a declaration of the same name in the `procedures.zig` file within the language directory.
* **Execution:** When the parser performs a reduction on that production, it executes the corresponding function, passing standard `ProcedureArguments`.

---

**← Previous:** [Writing a Language](writing_a_language.md) | **Next:** [Core Architecture](architecture.md) **→**
