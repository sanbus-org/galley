# Using Galley from Another Zig Project

Galley can be used from another project in two related ways:

1. Use the `galley_generator` package module to generate Zig parser source from a grammar.
2. Use a generated parser module to parse input from Zig code.

These are separate stages. The generator produces a Zig source file; that source must then be assembled with Galley's runtime, your language configuration, and your reduction procedures. Galley's CLI can create that complete parser project for you.

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
    .ast_for_terminals = false,
    .input_size = 16,
};
```

The defaults are shown above. `input_size` is the bit width used for input offsets and must be large enough for the largest input the generated parser will accept.

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

For tools that need to inspect or transform the grammar first, `parseGrammar` returns Galley's grammar model and `emitParser` generates code from that model.

## Create a Standalone Parser Project

Generating source is only the first half of the pipeline. A generated parser depends on:

- Galley's parser runtime;
- the generated `_ll-parser.zig` or `_lr-parser.zig` file;
- `config.zig` for language-specific runtime options; and
- `procedures.zig` for reduction hooks and AST payloads.

The easiest way to assemble these pieces is to run the Galley CLI on a language directory outside the Galley repository.

First build the generator from the Galley checkout:

```sh
cd path/to/galley
zig build
```

Create a directory containing `ll.grm`, `lr.grm`, or both, then generate the parser:

```sh
./zig-out/bin/galley --parser-type ll ../my-language
```

In addition to `_ll-parser.zig`, the first run creates any missing support files:

```text
my-language/
├── _ll-parser.zig
├── build.zig
├── config.zig
├── ll.grm
├── main.zig
├── procedures.zig
├── samples/
│   └── code-01
└── tests/
    └── parser_test.zig
```

Support files are never overwritten. Regenerating updates the selected parser file while preserving your configuration, procedures, application code, samples, and tests.

Replace the placeholder in `samples/code-01` with valid input for the grammar, then build and test the parser project:

```sh
cd ../my-language
zig build test
zig build run-ll
```

`run-ll` parses every file under `samples/` whose name begins with `code-`. Use `run-lr` for an LR parser. Benchmark-style repetition is available after `--`:

```sh
zig build -Doptimize=ReleaseFast run-ll -- \
    --iterations 100 \
    --warmup-iterations 10
```

The generated `build.zig` records the absolute path of the Galley checkout used to create it. If that checkout moves, regenerate the support project or update `galley_root` in `build.zig`.

## Parse Input from Zig

The standalone build injects the assembled parser into `main.zig` and `tests/parser_test.zig` under the import name `generated_parser`:

```zig
const parser = @import("generated_parser");
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
```

`parseBytes` makes a sentinel-terminated copy of the input. The returned `ParsedInput` owns that copy, the parser session, and any AST storage, so it must remain alive while its result or AST is being inspected.

For repeated parsing, reuse a `Session`:

```zig
var session = try parser.Session.init(io, allocator, .{});
defer session.deinit();

const first = try session.parseBytes("first input", "first");
const second = try session.parseBytes("second input", "second");
```

Each call resets the session's transient parsing state while retaining reusable allocations. Other input APIs are available for specialized callers:

- `session.parseFile(file, input_path)` parses from a `std.Io.File`.
- `parseSentinelBytes` and `session.parseSentinelBytes` accept caller-owned `[:0]const u8` input and avoid the copy performed by `parseBytes`.

The sentinel-terminated input must remain valid for the complete parse. When AST generation is enabled, the parse result exposes `ast_root`, and the session exposes its AST allocator through `astAllocator()`.

## Understand the Package Boundary

`galley_generator` is Galley's supported package-level generator API. A generated parser is not just the emitted Zig file: it is a configured module assembled from generated source, runtime code, configuration, and procedures. That is why application code should import the assembled parser module rather than files under Galley's `src/runtime` directory.

Use the generator API when your project needs to produce parser source itself. Use the CLI-generated standalone project when you want to define a language and immediately build, test, and call its parser.
