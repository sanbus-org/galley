# Getting Started

## Table of Contents

- [What You Need](#what-you-need)
- [Your First Parser](#your-first-parser)
  - [Parse existing JSON](#parse-existing-json)
  - [Try the LR parser too](#try-the-lr-parser-too)
- [Writing Your Own Grammar](#writing-your-own-grammar)
  - [Minimal Example: Simple Arithmetic](#minimal-example-simple-arithmetic)
  - [Build](#build)
- [Next Steps](#next-steps)

---

## What You Need

- [Zig 0.16+](https://ziglang.org/download/) — this is the only runtime requirement
- [uv](https://docs.astral.sh/uv/) — to run the grammar generator
- A terminal or shell

---

## Your First Parser

The fastest path is to start with an example grammar that already ships with the repo. Run all commands from the repository root directory.

### Parse existing JSON

```sh
# 1. Generate the LL parse table
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/json --parser-type LL

# 2. Build and run it with release optimization for maximum throughput
zig build -Doptimize=ReleaseFast ll-json -- languages/json/sample-code.json
```

That's it — `languages/json/sample-code.json` parses at hundreds of megabytes per second.

### Try the LR parser too

```sh
# 1. Generate the LR parse table
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/json --parser-type LR

# 2. Build and run it
zig build -Doptimize=ReleaseFast lr-json -- languages/json/sample-code.json
```

---

## Writing Your Own Grammar

Create a new language directory under `languages/` and add a grammar file (`ll.grm` or `lr.grm`, depending on the parser type you want), alongside a required `procedures.zig` file. Each directory becomes an independently buildable parser.

### Minimal Example: Simple Arithmetic

Save `languages/mylang/ll.grm`:

```
Definition
 |"let" _WhiteSpace Expr _WhiteSpace

Expr
 |Number
 |"+" Number
 |"-" Number

Number
 |"4"
 |"2"

_WhiteSpace
 |space _WhiteSpace
 |new_line _WhiteSpace
 |
```

Note that exact keyword matches like `"let"` must be enclosed in quotes. Unquoted identifiers starting with a lowercase letter are treated as built-in generative terminals (like `space` or `new_line`). Variables prefixed with an underscore (like `_WhiteSpace`) incur zero overhead because they never allocate AST nodes.

Save `languages/mylang/procedures.zig`:

```zig
pub const indentation_syntax = false;
pub const Payload = struct {};
```

Every language must have a `procedures.zig` file exporting at least `indentation_syntax` and `Payload`.

Save `languages/mylang/sample-code.txt`:

```
let +4
```

### Build

```sh
# 1. Generate the LL parse table
uv run --project initial-parser-generator initial-parser-generator/main.py --language languages/mylang --parser-type LL

# 2. Build and run it
zig build ll-mylang -- languages/mylang/sample-code.txt
```

The executable `ll-mylang` will be built automatically because `build.zig` discovers all directories under `languages/` that contain `_ll-parser.zig`.

---

## Next Steps

Now that you have executed your first parser, explore the grammars bundled with Galley or configure advanced options.

---

**Next:** [Included Languages](languages.md) **→**
