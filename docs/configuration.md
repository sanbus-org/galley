# Configuration & Options

## Table of Contents
- [Overview](#overview)
- [Generator CLI Options](#generator-cli-options)
- [Language Configuration](#language-configuration)
- [Runtime API Options](#runtime-api-options)
- [Quick Reference](#quick-reference)

---

## Overview

Galley's pipeline consists of two distinct stages: generating parser source via
`galley`, then assembling and consuming the parser through its Zig API.

---

## Generator CLI Options

Build Galley first, then run the installed generator binary:

```sh
zig build
./zig-out/bin/galley [OPTIONS] <LANGUAGE_DIR>
```

| Flag | Argument | Description | Default |
| :--- | :--- | :--- | :--- |
| `<LANGUAGE_DIR>` | `<PATH>` | Directory containing `ll.grm` and/or `lr.grm`. | None |
| `--parser-type` | `ll` \| `lr` | Limits generation to one parser type. Without it, Galley generates every parser type with a matching grammar file. | All available |
| `--with-ast` / `--no-ast` | Flag | Enables or disables AST construction. Disabling AST construction also disables procedures and maximizes raw syntax validation speed. | `--with-ast` |
| `--with-procedures` / `--no-procedures` | Flag | Enables or disables executing reduction hooks defined in `procedures.zig`. | `--with-procedures` |
| `--with-error-recovery` / `--no-error-recovery` | Flag | Enables or disables generated syntax recovery. Enabled unannotated grammars use automatic recovery; grammars containing `!` annotations use explicit-only recovery. | `--no-error-recovery` |
| `--with-position-tracking` / `--no-position-tracking` | Flag | Enables or disables generated line and column tracking. Without either flag, tracking is enabled except in `ReleaseFast`. | Build-mode dependent |
| `--with-input-refill` / `--no-input-refill` | Flag | Selects refill-aware or fixed-buffer input advancement at generation time. Refill allows no-AST parsers to stream inputs larger than their cursor range. | `--no-input-refill` |
| `--ast-for-terminals` / `--no-ast-for-terminals` | Flag | Controls whether individual terminal characters allocate AST nodes. Disabling terminal nodes keeps AST allocations minimal. | `--no-ast-for-terminals` |
| `--input-size` | `<BITS>` | Bit width used for generated input offsets and AST indices (for example `16` or `32`). | `16` |
| `--fill-error-messages` | Flag | Creates or appends default syntax-error message hooks in `ll_error_messages.zig` and/or `lr_error_messages.zig`. Existing hooks are preserved; obsolete public `syntax_error_*` hooks are reported. | Off |

`--no-ast` and `--with-procedures` are mutually incompatible because procedure hooks operate on AST nodes.

Parser files named `_ll-parser.zig` and `_lr-parser.zig` are underscore-prefixed because Galley overwrites them on every generation. User-owned support files such as `config.zig`, `procedures.zig`, and `ll_error_messages.zig` / `lr_error_messages.zig` are not underscore-prefixed because Galley preserves existing content.

---

## Language Configuration

Each language's `config.zig` declares compile-time parser configuration:

```zig
pub const indentation_syntax = true; // or false
pub const Options = struct {};
```

When `indentation_syntax` is set to `true`, the parser tracks indentation changes at the beginning of lines and emits virtual `block_start` (`\x01`) and `block_end` (`\x02`) tokens for indentation-sensitive grammars.

`Options` defines arbitrary per-session state made available to procedures
through `ParseOptions.language_options`. Both declarations are required, even
when a language does not need indentation or custom options.

---

## Runtime API Options

Pass runtime behavior to `Session.init` or one-shot parse helpers through
`ParseOptions`:

```zig
var session = try parser.Session.init(io, allocator, .{
    .language_options = .{},
    .input_path = "input.json",
    .verbosity = 0,
    .max_errors = 10,
    .recovery_window = 500,
    .stack_overflow_recovery = false,
});
defer session.deinit();
```

`language_options` has the language-defined `config.Options` type and is
available to arbitrary reduction procedures. `max_errors` and
`recovery_window` configure generated error recovery.
`stack_overflow_recovery` enables the optional native recovery boundary and is
disabled by default.

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
./zig-out/bin/galley --parser-type ll --no-ast --no-error-recovery --input-size 32 languages/json
zig build -Doptimize=ReleaseFast run-ll-json -- \
  languages/json/samples/code-02.json --iterations 100 --warmup-iterations 10
```

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
