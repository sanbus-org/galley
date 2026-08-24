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
| `--with-ast` / `--no-ast` | Flag | Enables or disables AST construction. | `--with-ast` |
| `--with-procedures` / `--no-procedures` | Flag | Enables or disables executing reduction hooks defined in `procedures.zig`. | `--with-procedures` |
| `--with-error-recovery` / `--no-error-recovery` | Flag | Enables or disables generated syntax recovery. Enabled unannotated grammars use automatic recovery; grammars containing `@` annotations use explicit-only recovery. | `--no-error-recovery` |
| `--with-position-tracking` / `--no-position-tracking` | Flag | Enables or disables generated line and column tracking. Without either flag, tracking is enabled except in `ReleaseFast`. | Build-mode dependent |
| `--with-input-streaming` / `--no-input-streaming` | Flag | Streams files incrementally or loads them completely before parsing. Only no-AST/no-procedure parsers use a bounded input window; AST or procedure-enabled parsers retain the complete source. | `--no-input-streaming` |
| `--ast-for-terminals` / `--no-ast-for-terminals` | Flag | Controls whether individual terminal characters allocate AST nodes. Disabling terminal nodes keeps AST allocations minimal. | `--no-ast-for-terminals` |
| `--fill-error-messages` | Flag | Creates or appends default syntax-error message hooks in `ll_error_messages.zig` and/or `lr_error_messages.zig`. Existing hooks are preserved; obsolete public `syntax_error_*` hooks are reported. | Off |
| `--allow-no-ast-tree-procedures` | Flag | In no-AST mode, treats standard tree-manipulation procedures as no-ops instead of failing to compile. Has no effect when AST construction is enabled. | Off |
| `--bootstrap-zig-project` | Flag | Creates a minimal Zig project (`build.zig`, `build.zig.zon`, `src/main.zig`) in the language directory that parses files with the generated parser. Refuses to overwrite existing files. | Off |
## galley.json

An optional `galley.json` file in the language directory supplies defaults
for the generation options above. Explicit command-line flags always
override values from the file; unspecified fields keep their built-in
defaults.

| Key | Type | Matches |
| --- | --- | --- |
| `parser_type` | `"ll"` or `"lr"` | `--parser-type` |
| `ast` | boolean | `--with-ast` / `--no-ast` |
| `procedures` | boolean | `--with-procedures` / `--no-procedures` |
| `error_recovery` | boolean | `--with-error-recovery` / `--no-error-recovery` |
| `ast_for_terminals` | boolean | `--ast-for-terminals` / `--no-ast-for-terminals` |
| `position_tracking` | boolean | `--with-position-tracking` / `--no-position-tracking` |
| `input_streaming` | boolean | `--with-input-streaming` / `--no-input-streaming` |
| `allow_no_ast_tree_procedures` | boolean | `--allow-no-ast-tree-procedures` |
| `error_messages` | object of string → string | Ignored during generation; the Rust and Go bindings read it at session creation and register its entries as syntax-error message overrides (see their docs). C, C++, and Zig consumers use the same override concept through the session API instead. |

Unknown keys are rejected so misspelled options never silently disable a
feature. Action flags (`--fill-error-messages`, `--bootstrap-zig-project`,
`--watch`) cannot appear in the file.

| `--watch` | Flag | Keeps running and regenerates the parser whenever the grammar file changes. Each run is separated by a timestamped banner and reports parse duration in milliseconds; if regeneration fails (for example, mid-edit), the previous parser output is kept. | Off |

`--no-ast --with-procedures` enables semantic procedures without constructing
an AST. The same `procedures.zig` module works in both modes. In no-AST mode,
hooks receive temporary `Node` values containing source spans, symbol identity,
payload, and direct-child links; tree mutation APIs are unavailable.

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
