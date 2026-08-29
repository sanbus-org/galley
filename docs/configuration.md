# Configuration & Options

## Table of Contents
- [Overview](#overview)
- [The config.zig Contract](#the-configzig-contract)
- [Generator CLI Options](#generator-cli-options)
- [Syntax Error Message Overrides](#syntax-error-message-overrides)
- [Runtime API Options](#runtime-api-options)
- [Quick Reference](#quick-reference)

---

## Overview

Galley's pipeline consists of two distinct stages: generating parser source via
`galley`, then assembling and consuming the parser through its Zig API.

Generated parsers are **configuration-independent artifacts**: they read every
generation-time option from your language's `config.zig` at compile time
(`comptime`). Changing configuration therefore requires **recompiling** the
consuming project — never regenerating the parser.

---

## The config.zig Contract

Each language directory contains a user-owned `config.zig`. Its contract:

- **Constants only.** Never define functions in this file.
- **Generation-time options only.** Every value is compiled into the parser
  when the consuming project is built.
- **Parse-time configuration does not belong here.** Per-session settings
  (maximum error count, dynamic message overrides, reporters) are set through
  parse/session options in your code.

| Constant | Type | Meaning |
| :--- | :--- | :--- |
| `ast` | `bool` | Construct an abstract syntax tree and expose tree APIs. `false` skips AST construction entirely for maximum throughput; procedure hooks still run. |
| `procedures` | `bool` | Execute grammar-annotated procedure hooks (`@procedures(...)`). |
| `allow_no_ast_tree_procedures` | `bool` | In no-AST mode, treat standard tree-manipulation procedures as no-ops instead of failing to compile. |
| `error_recovery` | `bool` | Enable generated syntax-error recovery. Enabled unannotated grammars use automatic recovery; grammars containing recovery annotations use explicit-only recovery. |
| `ast_for_terminals` | `bool` | Allocate AST nodes for individual terminals. Disabling keeps AST allocations minimal. |
| `position_tracking` | `?bool` | Line/column tracking. `null` (the default) enables it except in `ReleaseFast`; `true`/`false` force it regardless of build mode. |
| `input_streaming` | `bool` | Stream files incrementally. Only no-AST/no-procedure parsers use a bounded input window; AST or procedure-enabled parsers retain the complete source. |
| `indentation_syntax` | `bool` | Track indentation changes at line starts and emit virtual `block_start` (`\x01`) / `block_end` (`\x02`) tokens for indentation-sensitive grammars. |
| `error_messages` | anonymous struct | Template overrides for syntax-error messages — see [below](#syntax-error-message-overrides). |

The file is created with documented defaults when missing (for example by
running the generator once). Galley never rewrites an existing `config.zig`
on its own.

---

## Generator CLI Options

Build Galley first, then run the installed generator binary:

```sh
zig build
./zig-out/bin/galley [OPTIONS] <LANGUAGE_DIR>
```

Option flags **edit `config.zig` in place**: an explicit flag rewrites its
constant (`--with-ast` writes `ast = true`, `--no-ast` writes `ast = false`);
an absent flag leaves the value untouched. Edits are surgical — surrounding
comments and formatting are preserved. After editing, Galley regenerates the
parser files; consumers pick up new configuration when they next compile.

| Flag | Argument | Description |
| :--- | :--- | :--- |
| `<LANGUAGE_DIR>` | `<PATH>` | Directory containing `ll.grm` and/or `lr.grm`, plus the language's `config.zig`. | 
| `--parser-type` | `ll` \| `lr` | Limits generation to one parser type. Without it, Galley generates every parser type with a matching grammar file. This flag does not touch `config.zig`. |
| `--with-ast` / `--no-ast` | Flag | Writes `ast = true` / `false`. |
| `--with-procedures` / `--no-procedures` | Flag | Writes `procedures = true` / `false`. |
| `--with-error-recovery` / `--no-error-recovery` | Flag | Writes `error_recovery = true` / `false`. |
| `--with-position-tracking` / `--no-position-tracking` | Flag | Writes `position_tracking = true` / `false`. |
| `--with-input-streaming` / `--no-input-streaming` | Flag | Writes `input_streaming = true` / `false`. |
| `--ast-for-terminals` / `--no-ast-for-terminals` | Flag | Writes `ast_for_terminals = true` / `false`. |
| `--indentation-syntax` / `--no-indentation-syntax` | Flag | Writes `indentation_syntax = true` / `false`. |
| `--allow-no-ast-tree-procedures` | Flag | Writes `allow_no_ast_tree_procedures = true`. |
| `--fill-error-messages` | Flag | Creates or appends default syntax-error message hooks in `ll_error_messages.zig` and/or `lr_error_messages.zig`. Existing hooks are preserved; obsolete public `syntax_error_*` hooks are reported. |
| `--emit-metadata` | Flag | Write metadata.json and procedures.zig next to the generated parser(s); the bindings workflow consumes both. |
| `--bootstrap-zig-project` | Flag | Creates a minimal Zig project (`build.zig`, `build.zig.zon`, `src/main.zig`) that parses files with the generated parser. Refuses to overwrite existing files. |
| `--watch` | Flag | Keeps running and regenerates the parser whenever the grammar file changes. If regeneration fails (for example mid-edit), the previous parser output is kept. |

`ast = false` with `procedures = true` enables semantic procedures without
constructing an AST. The same `procedures.zig` module works in both modes. In
no-AST mode, hooks receive temporary `Node` values containing source spans,
symbol identity, payload, and direct-child links; tree mutation APIs are
unavailable.

Parser files named `_ll-parser.zig` and `_lr-parser.zig` are underscore-prefixed because Galley overwrites them on every generation. User-owned support files such as `config.zig` and `procedures.zig` are not underscore-prefixed because Galley preserves existing content; error-message hook files are never touched by plain generation — only `--fill-error-messages` creates or updates them.

---

## Syntax Error Message Overrides

There are three layers of message customization, tried in order:

1. **Session overrides** — per-parse, set programmatically through
   `ParseOptions.message_overrides`.
2. **Config templates** — the `error_messages` struct in `config.zig`.
3. **Hook functions** — declarations in `ll_error_messages.zig` /
   `lr_error_messages.zig` (created or extended by `--fill-error-messages`),
   followed by Galley's built-in renderer.

Both override tables share one key rule: entries are looked up by the
innermost variable name where the error occurs, falling back to the universal
`"*"` key. Config-table keys are plain field names; non-identifier keys need
`@"..."` quoting:

```zig
pub const error_messages = .{
    .Number = "digits only at line {line}",
    .@"*" = "parse failed: {unexpected}",
};
```

Template values may contain placeholders expanded against each diagnostic:
`{line}`, `{column}`, `{unexpected}`, `{expected}`, `{context}`. Unknown
placeholders are emitted verbatim.

---

## Runtime API Options

Pass runtime behavior to `Session.init` or one-shot parse helpers through
`ParseOptions`:

```zig
var session = try parser.Session.init(io, allocator, .{
    .input_path = "input.json",
    .verbosity = 0,
    .max_errors = 10,
    .recovery_window = 500,
    .stack_overflow_recovery = false,
});
defer session.deinit();
```

`max_errors` and `recovery_window` configure generated error recovery.
`stack_overflow_recovery` enables the optional native recovery boundary and is
disabled by default. `message_overrides` registers dynamic per-session syntax
message overrides (layer 1 above); `syntax_error_reporter` receives each
rendered message instead of the default stderr printer.

ReleaseFast builds compile out debugging instrumentation and position tracking
where configured to maximize throughput.

---

## Quick Reference

### Generate and Parse
```sh
zig build
./zig-out/bin/galley --parser-type ll languages/json
```

```zig
var parsed = try json_parser.parseBytes(io, allocator, input, .{});
defer parsed.deinit();
```

### High-Precision API Benchmark
```sh
./zig-out/bin/galley --parser-type ll --no-ast --no-error-recovery languages/json
bash scripts/fetch-large-samples.sh json
zig build -Doptimize=ReleaseFast run-ll-json -- \
  languages/json/samples/code-02.json --iterations 100 --warmup-iterations 10
```

The `code-02.json` fixture is too large for git and is fetched from a GitHub
release asset by `scripts/fetch-large-samples.sh`.

### Report More Than One Syntax Error
```zig
var session = try json_parser.Session.init(io, allocator, .{
    .max_errors = 10,
    .recovery_window = 500,
});
defer session.deinit();
```

Generate the parser with recovery support first:

```sh
./zig-out/bin/galley --parser-type ll --with-error-recovery languages/json-recovery
```
