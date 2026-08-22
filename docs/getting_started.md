# Getting Started

## Table of Contents

- [What You Need](#what-you-need)
- [Your First Parser](#your-first-parser)
  - [Parse existing JSON](#parse-existing-json)
  - [Try the LR parser too](#try-the-lr-parser-too)
  - [Bootstrap a new language project](#bootstrap-a-new-language-project)
- [Next Steps](#next-steps)

---

## What You Need

- [Zig 0.16+](https://ziglang.org/download/) — the supported build toolchain
- A terminal or shell

---

## Your First Parser

The fastest path is to start with an example grammar that already ships with the repo. Run all commands from the repository root directory.

### Parse existing JSON

```sh
# 1. Generate the LL parser
zig build
./zig-out/bin/galley --parser-type ll languages/json

# 2. Run the repository API benchmark harness
zig build -Doptimize=ReleaseFast run-ll-json -- \
  languages/json/samples/code-01.json --iterations 100
```

That's it — `languages/json/samples/code-01.json` parses at hundreds of megabytes per second.

The separate `json-recovery` implementation demonstrates explicit recovery and custom messages while keeping the benchmark grammar minimal. Its demonstration input is intentionally malformed and exits with `SyntaxError` after reporting three recoverable value errors:

```sh
./zig-out/bin/galley --parser-type ll --with-error-recovery languages/json-recovery
zig build run-ll-json-recovery -- languages/json-recovery/recovery-demo.json
```

### Bootstrap a new language project

To turn a directory that only contains a grammar into a runnable Zig project, pass `--bootstrap-zig-project`. Galley writes `build.zig`, `build.zig.zon`, and `src/main.zig` next to the generated parser, and refuses to overwrite existing project files:

```sh
./zig-out/bin/galley --bootstrap-zig-project my-language
```

Bootstrapping is off by default; pass `--bootstrap-zig-project` to create the minimal project.

### Try the LR parser too

```sh
# 1. Generate the LR parser
zig build
./zig-out/bin/galley --parser-type lr languages/json

# 2. Run its API benchmark harness
zig build -Doptimize=ReleaseFast run-lr-json -- \
  languages/json/samples/code-01.json --iterations 100
```

---

## Next Steps

Now that you have verified the bundled JSON parsers work, you can learn how to
[use Galley from another Zig project](using-galley.md), explore the other
[included languages](languages.md), review the
[generator and runtime options](configuration.md), or start
[writing your own custom language](writing_a_language.md).
