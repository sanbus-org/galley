# Configuration & Flags

## Table of Contents
- [Overview](#overview)
- [Generator CLI Options](#generator-cli-options)
- [Language Configuration](#language-configuration)
- [Runtime Executable Flags](#runtime-executable-flags)
- [Quick Reference](#quick-reference)

---

## Overview

Galley's pipeline consists of two distinct stages: generating parser files for a language directory via `galley`, and running the compiled Zig binary. Both stages expose command-line flags to tune AST generation and benchmarking behavior.

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
| `--with-ast` / `--no-ast` | Flag | Enables or disables AST construction. Disabling AST construction maximizes raw syntax validation speed. | `--with-ast` |
| `--with-procedures` / `--no-procedures` | Flag | Enables or disables executing reduction hooks defined in `procedures.zig`. | `--with-procedures` |
| `--ast-for-terminals` / `--no-ast-for-terminals` | Flag | Controls whether individual terminal characters allocate AST nodes. Disabling terminal nodes keeps AST allocations minimal. | `--no-ast-for-terminals` |
| `--input-size` | `<BITS>` | Number of bit-width integer bits required to represent input file length pointers (e.g. `16` or `32`). | `16` |
| `--fill-error-messages` | Flag | Creates or appends default syntax-error message hooks in `ll_error_messages.zig` and/or `lr_error_messages.zig`. Existing hooks are preserved; obsolete public `syntax_error_*` hooks are reported. | Off |

Parser files named `_ll-parser.zig` and `_lr-parser.zig` are underscore-prefixed because Galley overwrites them on every generation. User-owned support files such as `config.zig`, `procedures.zig`, and `ll_error_messages.zig` / `lr_error_messages.zig` are not underscore-prefixed because Galley preserves existing content.

---

## Language Configuration

Each language's `config.zig` declares compile-time parser configuration:

```zig
pub const indentation_syntax = true; // or false
```

When `indentation_syntax` is set to `true`, the parser tracks indentation changes at the beginning of lines and emits virtual `block_start` (`\x01`) and `block_end` (`\x02`) tokens for indentation-sensitive grammars.

---

## Runtime Executable Flags

Build a parser target first, then invoke the installed binary directly:

```sh
zig build -Doptimize=ReleaseFast ll-json
./zig-out/bin/ll-json [OPTIONS] <FILE>
```

| Flag | Short | Argument | Description | Default |
| :--- | :--- | :--- | :--- | :--- |
| `--verbosity` | `-v` | `<0-2>` | Verbosity level. `0` prints benchmark speed; `1` prints parsed AST structure and metrics; `2` outputs detailed execution traces. | `0` |
| `--iterations` | `-r` | `<INT>` | Number of times to repeat parsing the file. Highly useful for getting stable throughput averages during benchmarking. | `1` |
| `--warmup-iterations` | `-w` | `<INT>` | Number of warmup parse passes before recording benchmark timers to ensure CPU cache saturation. | `0` |
| `--max-errors` | None | `<INT>` | Maximum syntax errors to print before stopping. Use `1` for fail-fast parsing. Must be greater than zero. | `10` |
| `--recovery-window` | None | `<BYTES>` | Maximum input distance examined by each recovery attempt. Must be greater than zero. | `500` |
| `--disable-stack-overflow-recovery` | None | Flag | Disables dynamic stack overflow recovery, falling back to static stack boundaries. | Enabled |
| `<FILE>` | None | `<PATH>` | **Required.** Path to the source code file to parse. | None |

> [!IMPORTANT]
> When compiling the parser with `-Doptimize=ReleaseFast` (the default optimization mode for benchmarking), all debugging instrumentation, execution logging, verbosity traces, and even source location tracking (line/column numbers) are completely disabled and compiled out to maximize parsing throughput. For debugging, syntax error reporting, or verbose parsing traces, compile the parser without `-Doptimize=ReleaseFast` (which defaults to Debug mode).

---

## Quick Reference

### Standard Production Generation & Run
```sh
zig build
./zig-out/bin/galley --parser-type ll languages/json
zig build -Doptimize=ReleaseFast ll-json
./zig-out/bin/ll-json languages/json/samples/code-01.json
```

### High-Precision Benchmarking Loop (100 Iterations with 10 Warmups)
```sh
zig build -Doptimize=ReleaseFast ll-json
./zig-out/bin/ll-json -r 100 -w 10 languages/json/samples/code-02.json
```

### AST Debugging & Inspection
```sh
zig build ll-json
./zig-out/bin/ll-json -v 1 languages/json/samples/code-01.json
```

### Report More Than One Syntax Error
```sh
zig build ll-json
./zig-out/bin/ll-json --max-errors 10 --recovery-window 500 malformed.json
```
