# Using Galley from Another Zig Project

Galley can be used from another project in two related ways:

1. Use the `galley_generator` package module to generate Zig parser source from a grammar.
2. Use a generated parser module to parse input from Zig code.

These are separate stages. The generator API emits parser source only. The
`galley` CLI also creates missing customization files when generating into a
language directory. In either case, the consuming project's `build.zig`
assembles the generated source and customization modules with Galley's runtime.

## Add Galley as a Dependency

For local development, add Galley to your project's `build.zig.zon` with a relative path:

```zig
.dependencies = .{
    .galley = .{
        .path = "../galley",
    },
},
```

When consuming a published archive, use its `url` and `hash` instead. The dependency name does not have to be `galley`, but the examples below assume that it is.

Galley requires Zig 0.16 or newer.

## Generate Parser Source from Zig

The public package module for parser generation is `galley_generator`. Add it to the module that needs to generate parsers:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const galley = b.dependency("galley", .{
        .target = target,
        .optimize = optimize,
    });

    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{
                .name = "galley_generator",
                .module = galley.module("galley_generator"),
            },
        },
    });

    const app = b.addExecutable(.{
        .name = "my-generator",
        .root_module = app_mod,
    });
    b.installArtifact(app);
}
```

Application code can generate parser source in memory with `generateParserAlloc`:

```zig
const generator = @import("galley_generator");

const parser_source = try generator.generateParserAlloc(
    allocator,
    grammar_source,
    .ll,
    .{},
);
defer allocator.free(parser_source);
```

Pass `.lr` to generate an LR parser. The final argument controls code-generation behavior:

```zig
const options = generator.Options{
    .with_ast = true,
    .with_procedures = true,
    .with_error_recovery = false,
    .ast_for_terminals = false,
    .with_position_tracking = null,
    .with_input_streaming = false,
};
```

The defaults are shown above. A `null` position-tracking setting enables
tracking except in `ReleaseFast`; set it explicitly to `true` or `false` to
override that build-mode default. `with_input_streaming` selects incremental
file input at generation time. When disabled, file inputs are loaded completely
before parsing. No-AST streaming uses a bounded input window.

When the destination is already represented by a `std.Io.Writer`, use `emitParserFromSource` to avoid allocating the complete generated file:

```zig
try generator.emitParserFromSource(
    allocator,
    grammar_source,
    writer,
    .ll,
    options,
);
```

For tools that need to inspect or transform the grammar first, `parseGrammar`
returns Galley's grammar model and `emitParser` generates code from that model.
`parseGrammar` allocates the complete cloned model with the supplied allocator;
an arena is the simplest ownership strategy when the model can be discarded as
a unit. `Rule`, `RightHandSide`, and `SymbolRef` each expose an `annotations`
field containing `procedures` and `recovery_points`; every `RecoveryPoint`
contains exact terminal bytes and a `.before` or `.after` resume side.
Programmatically constructed grammars use the same validation and recovery
behavior as parsed grammar source.

## Generate into a Language Directory

Generating source is only the first half of the pipeline. A generated parser depends on:

- Galley's parser runtime;
- the generated `_ll-parser.zig` or `_lr-parser.zig` file;
- `config.zig` for language-specific runtime options; and
- `procedures.zig` for reduction hooks and AST payloads.

`ll_error_messages.zig` / `lr_error_messages.zig` are *optional*: they
exist only if you create them (or run `--fill-error-messages`), and a
grammar without them simply uses the built-in message renderer — or, in
the language bindings, message overrides and host renderers.

First build the generator from the Galley checkout:

```sh
cd path/to/galley
zig build
```

Create a directory containing `ll.grm`, `lr.grm`, or both, then generate the parser:

```sh
./zig-out/bin/galley --parser-type ll ../my-language
```

In addition to `_ll-parser.zig`, the first run creates the support files a
compilable grammar needs:

```text
my-language/
├── _ll-parser.zig
├── config.zig
├── ll.grm
└── procedures.zig
```

Support files are never overwritten by normal generation. Regenerating updates
the selected parser file while preserving configuration and procedures.
Generated parser files are underscore-prefixed
(`_ll-parser.zig`, `_lr-parser.zig`) to signal that Galley owns them.

To customize syntax-error messages in Zig, create the hooks file (and
populate all default hooks for the current grammar) with:

```sh
./zig-out/bin/galley --parser-type ll --fill-error-messages ../my-language
```

This creates — or appends missing `pub fn syntax_error_*` hooks to —
`ll_error_messages.zig` or `lr_error_messages.zig`. Existing public hooks
are preserved. Public hooks no longer produced by the current grammar are
reported as obsolete; non-public helper functions are ignored. For fixed
strings instead of Zig code, prefer message overrides or host renderers
(see the [C](/bindings_c), [Rust](/bindings_rust), and [Go](/bindings_go)
binding docs).

To consume the generated parser from another language instead of Zig, see
the language bindings: [C and C++](/bindings_c),
[Rust](/bindings_rust), and [Go](/bindings_go) — the same
language-directory flow applies, and Galley ships a generic consumer build
file that compiles the generated parser into a shared library with a C
header.

LL hook names are semantic instead of numbered. A specific hook is named from the parser symbol and what that branch expected, for example `syntax_error_ll_Value__expected_String_or_Number`. If the specific LL hook is not present, the generated parser checks broader hooks at comptime in this order: `syntax_error_ll_Value`, `syntax_error_ll`, `syntax_error`, then Galley's default renderer.

LR sites retain their stable generated names such as `syntax_error_lr_state_12_action_19`. If that exact hook is absent, the parser checks `syntax_error_lr`, then `syntax_error`, then Galley's default renderer. The parser-level fallback is useful for a language-wide diagnostic style without maintaining one wrapper per LR state.

Each hook receives the current diagnostic and returns the text to print:

```zig
const root = @import("galley");

pub fn syntax_error_ll_Value__expected_String_or_Number(args: root.SyntaxErrorMessageArgs) ![]const u8 {
    return try root.renderParseDiagnostic(args.allocator, args.diagnostic, args.style);
}
```

Your `build.zig` must assemble the generated source and customization files
around Galley's runtime API. Importing `_ll-parser.zig` directly is not enough:
that file contains the generated parsing implementation, while public entry
points such as `parseBytes`, `parseFile`, and `Session` are provided by
`src/runtime/api.zig`.

For a language stored in `language/`, this complete LL example exposes the
assembled API to the application as `parser`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const galley = b.dependency("galley", .{
        .target = target,
        .optimize = optimize,
    });

    // Galley's runtime resolves every option through @hasDecl, so an empty
    // default module yields the built-in defaults. Override an option by
    // wiring your own b.addOptions() module instead.
    const runtime_options = b.createModule(.{
        .root_source_file = galley.path("src/runtime/default_runtime_options.zig"),
    });

    const procedures = b.createModule(.{
        .root_source_file = b.path("language/procedures.zig"),
        .target = target,
        .optimize = optimize,
    });
    const config = b.createModule(.{
        .root_source_file = b.path("language/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    const error_messages = b.createModule(.{
        .root_source_file = b.path("language/ll_error_messages.zig"),
        .target = target,
        .optimize = optimize,
    });
    const generated_parser = b.createModule(.{
        .root_source_file = b.path("language/_ll-parser.zig"),
        .target = target,
        .optimize = optimize,
    });

    const parser = b.createModule(.{
        .root_source_file = galley.path("src/runtime/api.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = switch (target.result.os.tag) {
            .linux, .macos => true,
            else => null,
        },
        .imports = &.{
            .{ .name = "procedures", .module = procedures },
            .{ .name = "config", .module = config },
            .{ .name = "error_messages", .module = error_messages },
            .{ .name = "parser", .module = generated_parser },
            .{ .name = "runtime_options", .module = runtime_options },
        },
    });

    // These imports let generated and customization code refer to the
    // assembled runtime as @import("galley").
    parser.addImport("galley", parser);
    procedures.addImport("galley", parser);
    config.addImport("galley", parser);
    error_messages.addImport("galley", parser);
    generated_parser.addImport("galley", parser);

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "parser", .module = parser },
            },
        }),
    });
    b.installArtifact(exe);
}
```

The corresponding `build.zig.zon` must declare the Galley package under the
same `galley` dependency name. For a local checkout:

```zig
.dependencies = .{
    .galley = .{
        .path = "../path/to/galley",
    },
},
```

For LR, replace `_ll-parser.zig` and `ll_error_messages.zig` with
`_lr-parser.zig` and `lr_error_messages.zig`. The repository's
[`tests/package-consumer/build.zig`](https://github.com/sanbus-org/galley/blob/main/tests/package-consumer/build.zig)
continuously validates the same assembly pattern.

The generated parser type is selected by this build wiring, so parsing does not
take a `.ll` or `.lr` argument:

```zig
var parsed = try parser.parseBytes(io, allocator, input, .{});
defer parsed.deinit();
```

## Parse Input from Zig

Choose an import name for the assembled runtime module in your application,
for example:

```zig
const parser = @import("parser");
```

For a single in-memory input, use `parseBytes`:

```zig
var parsed = try parser.parseBytes(
    io,
    allocator,
    "some input",
    .{ .input_path = "inline" },
);
defer parsed.deinit();

const result = parsed.result;
var reader = try parsed.session.read(result);
defer reader.deinit();
```

`parseBytes` makes a sentinel-terminated copy of the input. The returned `ParsedInput` owns that copy, the parser session, and any AST storage, so it must remain alive while its result or AST is being inspected.

For repeated parsing, reuse a `Session`:

```zig
var session = try parser.Session.init(io, allocator, .{});
defer session.deinit();

const first = try session.parseBytes("first input", "first");
{
    var reader = try session.read(first);
    defer reader.deinit();
    // Inspect first.ast_root through reader.astAllocator().
}
_ = try session.parseBytes("second input", "second");
```

Parsing takes an exclusive session lock and returns `error.SessionInUse` rather
than waiting if the session is already parsing or has active readers. Call
`session.read(result)` before inspecting session-owned AST data. Multiple
readers may coexist, but every reader must be released before parsing again.
Results carry a session generation, so `read` returns
`error.StaleParseResult` after a later parse has reused the session.
`tryDeinit()` similarly returns `error.SessionInUse`; `deinit()` reports
incorrect active-guard destruction with a clear panic.

Stack-overflow recovery is disabled by default so ordinary parses pay no
signal-recovery setup cost. Enable it for inputs that may contain excessive
recursive nesting:

```zig
var session = try parser.Session.init(io, allocator, .{
    .stack_overflow_recovery = true,
});
defer session.deinit();
```

Recovery is currently available on Linux and macOS.

LL and LR parsers report the first syntax error and stop by default. Enable recovery while generating the parser to report multiple diagnostics:

```sh
./zig-out/bin/galley --parser-type ll --with-error-recovery <LANGUAGE_DIR>
```

API generators enable the same behavior with `.with_error_recovery = true`. Every generated parser exposes `ErrorRecoveryMode`, `error_recovery_mode`, and the compatibility boolean `is_error_recovery_enabled`. The mode is `.disabled` without generated recovery, `.automatic` when recovery is enabled for an unannotated grammar, and `.explicit` when recovery is enabled for a grammar containing `@` annotations.

Explicit annotations can be attached to an LHS variable, a production immediately after `|`, or an RHS variable occurrence:

```text
Statement@!^"}"@!";"^@hook
|@!","^ Expression
| Block Statement@!^"}"
```

The caret selects the resume side: `@!^"}"` preserves `}` and resumes before it, while `@!";"^` consumes `;` and resumes after it. Multiple consecutive annotations are candidates on the same target. If a grammar contains any recovery annotation, recovery is explicit-only: a mismatch with no active annotated scope fails instead of falling back to automatic recovery. See the [grammar guidelines](grammar_guidelines.md#5-explicit-syntax-recovery-) for validation and scope-selection details.

Galley's own LL and LR grammars use newline and blank-line annotations as the production example. The `languages/json-recovery` LL and LR grammars demonstrate nested occurrence, production, and LHS recovery around object and array delimiters, together with finalized custom diagnostics in `languages/json-recovery/error_messages.zig`. The minimal `languages/json` grammars remain the performance reference. From the repository root, compare Galley's material recovery behavior against automatic recovery with:

```sh
zig build compare-galley-recovery
```

The command generates both parsers from the same LL grammar model, clears only the recovery annotations for the automatic baseline, and runs the same malformed grammar through both.

Recovery-enabled parsers use `max_errors` and `recovery_window` at runtime:

```zig
var session = try parser.Session.init(io, allocator, .{
    .max_errors = 10,
    .recovery_window = 500,
});
defer session.deinit();

if (session.parseBytes(input, "input")) |_| {
    // Parsed without syntax errors.
} else |err| switch (err) {
    parser.ParseError.SyntaxError => {
        var reader = try session.readLatest();
        defer reader.deinit();
        std.debug.print("reported {d} syntax errors\n", .{reader.syntaxErrorCount()});
    },
    parser.ParseError.StackOverflow => {
        std.debug.print("parser stack overflow recovered\n", .{});
    },
    else => return err,
}
```

Fail-fast parsers populate `SessionReadGuard.lastDiagnostic()` and report a
syntax-error count of one. A recovery-enabled parse that encounters errors
still returns `ParseError.SyntaxError`; acquire `session.readLatest()` before
allowing another reuse, then use `syntaxErrorCount()` and `lastDiagnostic()` on
that guard.

`SyntaxDiagnostic.recovery` is `null` until explicit synchronization succeeds. On success it identifies the winning terminal, whether parsing resumed `.before` or `.after` it, and the winning target: an LHS variable, a production `{ variable, rhs_index }`, or an occurrence `{ parent_variable, rhs_index, symbol_index, variable }`. The original unexpected token, expected tokens, source location, mismatch context, and LL/LR message-hook name are unchanged. Default plain and ANSI rendering append a `Recovery:` line, and custom message hooks receive the finalized diagnostic.

Recovery procedures may run on partial trees, so AST results from an erroneous parse are not a validity guarantee. Explicit recovery skips hooks belonging to the damaged occurrence, selected production, and variable.

Each call resets the session's transient parsing state while retaining reusable allocations. Other input APIs are available for specialized callers:

- `session.parseFile(file, input_path)` parses from a `std.Io.File`; the caller
  retains ownership of the file and must close it.
- `parseSentinelBytes` and `session.parseSentinelBytes` accept caller-owned `[:0]const u8` input and avoid the copy performed by `parseBytes`.

The sentinel-terminated input must remain valid for the complete parse. When
AST generation is enabled, the parse result exposes `ast_root`, and a matching
session read guard exposes the AST allocator through `astAllocator()`.

## Understand the Package Boundary

`galley_generator` is Galley's supported package-level generator API. A
generated parser is not just the emitted Zig file: it is a configured module
assembled from generated source, runtime code, configuration, procedures,
error-message hooks, and build-created runtime options. That is why application
code should import the assembled parser module rather than the generated source
or files under Galley's `src/runtime` directory directly.

Use the generator API or `galley` CLI to produce parser source. Applications
assemble that source with their customization modules and consume only the
generated parser API.
