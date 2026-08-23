# Go

Galley-generated parsers can be consumed from Go through cgo: Galley
compiles a generated parser into a shared library (`lib<name>.dylib` /
`.so`) together with the C header
[`bindings/c/galley.h`](https://github.com/sanbus-org/galley/blob/main/bindings/c/galley.h),
and the Go bindings package wraps that API in a safe, typed surface
(sessions, node handles, structured diagnostics, tree editing).

The bindings live in
[`bindings/go`](https://github.com/sanbus-org/galley/tree/main/bindings/go).
A complete, runnable consumer lives in
[`examples/go`](https://github.com/sanbus-org/galley/tree/main/examples/go);
it is built and executed by CI on every push.

## Getting Started

Add the bindings module to your `go.mod` and point a `replace` directive at
a Galley checkout (or a fetched copy):

```go
module example.com/my-parser-consumer

go 1.22

require github.com/sanbus-org/galley/bindings/go v0.0.0

replace github.com/sanbus-org/galley/bindings/go => /path/to/galley/bindings/go
```

Then generate, build, and run:

```console
$ go run github.com/sanbus-org/galley/bindings/go/cmd/galley gen <language-dir>
$ go build .
$ ./my-parser-consumer
```

`gen` resolves Galley exactly like the Rust build helper:
`GALLEY_CHECKOUT` (existing working tree) wins over `GALLEY_REPOSITORY` +
`GALLEY_TAG` (default `main`); `ZIG_EXECUTABLE` selects zig. It generates
the parser, builds the shared library, detects optional hook files next to
your grammar (`procedures.zig`, `procedures.c`, `ll_error_messages.zig`),
and emits `<language-dir>/galley/galley.go` — a generated cgo bridge bound
to this library. Regenerate after changing the grammar; commit nothing it
generates.

## Procedures

Set `"procedures": true` in your grammar's galley.json and implement the
hooks in a `hooks/procedures.c` file next to your grammar (the hooks
subdirectory keeps C sources out of the Go package, which refuses them):
the gen command compiles it into the shared library, mirroring the C,
C++, and Rust consumers:

```c
/* hooks/procedures.c */
#include <stdio.h>

void reduction_Pair(void *args) {
    fprintf(stderr, "[hook] Pair\n");
}
```

Reduction hooks keep their `reduction_<VariableName>` names (plus the
general `reduction`); author-defined grammar hooks are declared as
`hook_<name>`. Each hook fires after the corresponding variable is reduced.
Semantic payloads are unavailable through bindings.

## Error Messages

Run `galley --fill-error-messages <language-dir>` and edit the generated
`ll_error_messages.zig` next to your grammar. The gen command detects it
and compiles it into the shared library;
`session.Diagnostic().Message` then returns your hooks' text instead of
the built-in generic renderer.

## Sessions

```go
session, err := galley.WithOptions(galley.SessionOptions{
    MaxErrors:      10,
    RecoveryWindow: 500,
})
if err != nil { ... }
defer session.Close()

parsed, err := session.ParseSentinel("alpha:12,beta:3")
```

Sessions own their IO backend and allocator and are not safe for
concurrent use — keep one per goroutine or guard it externally. Node
handles, text slices, and diagnostics remain valid until the next parse on
the same session or `Close`.

## Related Pages

- [C and C++](/bindings_c) — the underlying C ABI
- [Rust](/bindings_rust) — bindings over the same shared library
- [Configuration](/configuration) — galley.json schema
- [Grammar Guidelines](/grammar_guidelines)
