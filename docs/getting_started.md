# Getting Started

## Table of Contents

- [What You Need](#what-you-need)
- [Your First Parser](#your-first-parser)
  - [Parse existing JSON](#parse-existing-json)
  - [Try the LR parser too](#try-the-lr-parser-too)
- [Next Steps](#next-steps)

---

## What You Need

- [Zig 0.16+](https://ziglang.org/download/) — this is the only runtime requirement
- A terminal or shell

---

## Your First Parser

The fastest path is to start with an example grammar that already ships with the repo. Run all commands from the repository root directory.

### Parse existing JSON

```sh
# 1. Generate the LL parser
zig build
./zig-out/bin/galley --parser-type ll languages/json

# 2. Build exactly that parser, then run it with release optimization
zig build -Doptimize=ReleaseFast ll-json
./zig-out/bin/ll-json languages/json/samples/code-01.json
```

That's it — `languages/json/samples/code-01.json` parses at hundreds of megabytes per second.

### Try the LR parser too

```sh
# 1. Generate the LR parser
zig build
./zig-out/bin/galley --parser-type lr languages/json

# 2. Build and run it
zig build -Doptimize=ReleaseFast lr-json
./zig-out/bin/lr-json languages/json/samples/code-01.json
```

---

## Next Steps

Now that you have verified the bundled JSON parsers work, you can explore the other [included languages](languages.md), check out the [CLI configuration and flags](configuration.md), or start [writing your own custom language](writing_a_language.md).
