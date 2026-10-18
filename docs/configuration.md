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
| `procedures` | `bool` | Execute grammar-annotated procedure hooks (`@Name`). |
| `error_recovery` | `bool` | Enable generated syntax-error recovery. Enabled unannotated grammars use automatic recovery; grammars containing recovery annotations use explicit-only recovery. |
| `ast_for_terminals` | `bool` | Allocate AST nodes for individual terminals. Disabling keeps AST allocations minimal. Requires `ast` or `procedures`; otherwise compilation fails. |
| `position_tracking` | `?bool` | Line/column tracking while parsing, for debugging. `null` (the default) enables it in `Debug` and `ReleaseSafe`; `true`/`false` force it regardless of build mode. Diagnostics carry line and column either way. |
| `input_streaming` | `bool` | Stream files incrementally. Only parsers with no AST, no procedures, and no verbatim capture use a bounded input window; AST-, procedure-, or verbatim-enabled parsers keep the complete source available, an indentation-syntax parser streaming a file by reading it again from the file. |
| `indentation_syntax` | `bool` | Track indentation changes at line starts and emit virtual `block_start` (`\x01`) / `block_end` (`\x02`) tokens for indentation-sensitive grammars. Grammars that name the `block_start`/`block_end` terminals require it; otherwise compilation fails. |
| `newline_after_block_end` | `bool` | After each `block_end` sequence, emit `\x03`. Productions that expect `new_line` match it as a newline; every other expected terminal skips it. Requires `indentation_syntax`; otherwise compilation fails. |
| `inline_parsers` | `bool` | LL only. Force variable parsers inline into their callers, so a parse makes fewer calls. On each recursion cycle, the few rules chosen to break it keep their own functions, so one nesting level costs one frame. Builds take longer and parsers grow. Debug builds keep every parser a function, since unoptimized inlined parsers cost far more stack. `false` keeps every variable parser a function. |
| `fold_decisions` | `bool` | LL only. Where a rule starts with a variable that has one non-nullable rule, the decision that selected the rule also selects the variable's rule, and the variable's parser skips its own decision. `false` makes every variable parser decide for itself. |
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
| `--newline-after-block-end` / `--no-newline-after-block-end` | Flag | Writes `newline_after_block_end = true` / `false`. |
| `--fold-decisions` / `--no-fold-decisions` | Flag | Writes `fold_decisions = true` / `false`. |
| `--inline-parsers` / `--no-inline-parsers` | Flag | Writes `inline_parsers = true` / `false`. |
| `--require-reduction-procedures` | Flag | Warns at generation, and fails compilation of the generated parser, for each visible production without `reduction_<Var>_<N>`. Names variable, index, and shape. Does not touch `config.zig`. |
| `--fill-error-messages` | Flag | Creates or appends default syntax-error message hooks in `ll_error_messages.zig` and/or `lr_error_messages.zig`. Existing hooks are preserved; obsolete public `syntax_error_*` hooks are reported. |
| `--emit-metadata` | Flag | Write metadata.json and procedures.zig next to the generated parser(s); the bindings workflow consumes both. |
| `--bootstrap-zig-project` | Flag | Creates a minimal Zig project (`build.zig`, `build.zig.zon`, `src/main.zig`) that parses files with the generated parser via `addParserModule`. Refuses to overwrite existing files. Not a second API: see `examples/zig` for the native runtime showcase. If `GALLEY_CHECKOUT` is set, `build.zig.zon` uses a `.path` to that tree instead of fetching GitHub. |
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
    .verbosity = 0,
    .max_errors = 10,
    .recovery_window = 500,
    .stack_overflow_recovery = false,
});
defer session.deinit();
```

`max_errors` and `recovery_window` configure generated error recovery.
`max_errors` counts syntax errors only; semantic errors have no runtime limit.
`stack_overflow_recovery` enables the native recovery boundary, a debugging aid,
and is disabled by default. `message_overrides` registers dynamic per-session syntax
message overrides (layer 1 above).

Without tracking, a diagnostic computes its line and column from its byte offset
when it is recorded, so the parse pays nothing for it until an error occurs; one
pass over the input serves all of a parse's diagnostics. A parser reading through
a bounded input window, or an indentation-syntax parser streaming a file, reads
its input in chunks, so without tracking its diagnostics carry no line and
column (0, 0).

---

## Quick Reference

### Generate and Parse
```sh
zig build
./zig-out/bin/galley --parser-type ll languages/json
```

```zig
var parsed = try json_parser.parseBytes(io, allocator, input, null, .{});
defer parsed.deinit();
```

The fourth argument is the optional input path: passed per parse call, not
through `ParseOptions`, and read by hooks of that parse as
`args.context.input_path`.

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
