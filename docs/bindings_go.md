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
$ go run github.com/sanbus-org/galley/bindings/go/cmd/galley gen <language-dir> [generator flags...]
$ go build .
$ ./my-parser-consumer
```

Add `--optimize Debug` to build the parser library in Debug with the
runtime's misuse checks (a failed check aborts the process); the default is ReleaseFast. `--optimize` takes any
Zig build mode (`Debug`, `ReleaseSafe`, `ReleaseFast`, `ReleaseSmall`).

Generator flags forward verbatim to the generator ahead of
`--emit-metadata`: every flag `gen` does not own goes to the generator,
which owns its surface (documented in [Configuration](/configuration)).

`gen` needs no checkout: released modules download the version-pinned
generator CLI and compile kit from GitHub releases into the user cache on
first use (progress and destination shown, checksums verified, exact
version only — a tampered or missing artifact is a loud error, never a
silent fallback). Contributors running from a checkout fall back to
`GALLEY_CHECKOUT` (a Galley working tree); `ZIG_EXECUTABLE` selects zig.
For convenience, `GALLEY_CHECKOUT=$(examples/scripts/fetch-galley.sh)`
fetches one into the system cache, but that cache is examples-only, not
part of the bindings.
It generates the parser, builds the shared library directly next to the
grammar, detects optional hook files next
to your grammar (`procedures.go`, `ll_error_messages.zig`), and emits
`<language-dir>/galley/galley.go` — a generated cgo bridge bound
to this library. Regenerate after changing the grammar; commit nothing it
generates.

## Procedures

Set `pub const procedures = true;` in your grammar's `config.zig` and implement the
hooks in Go in a `procedures.go` file next to your grammar — ordinary Go
compiled into your own binary by your ordinary `go build`. No C anywhere
on the consumer side. Put it in the same package as `main` so the
`//export`ed symbols are linked without a blank import:

```go
package main

import (
	"fmt"
	"os"
	"unsafe"

	galley "example.com/my-parser-consumer/galley"
)

//export reduction_Pair
func reduction_Pair(ptr unsafe.Pointer) {
	args := galley.Args(ptr)
	door := args.Door()
	node, ok := args.CurrentNode()
	if !ok {
		return
	}
	text, _ := door.Text(node)
	line, column, _ := door.LineColumn(node)
	children, _ := door.ChildCount(node)
	fmt.Fprintf(os.Stderr, "Pair %s (%d children) at %d:%d\n",
		text, children, line, column)
}

//export reduction_KeyTail
func reduction_KeyTail(ptr unsafe.Pointer) {
	_ = galley.Args(ptr).DropIfEmpty()
}

//export hook_print
func hook_print(ptr unsafe.Pointer) {
	args := galley.Args(ptr)
	door := args.Door()
	node, ok := args.CurrentNode()
	if !ok {
		return
	}
	text, _ := door.Text(node)
	line, column, _ := door.LineColumn(node)
	fmt.Fprintf(os.Stderr, "@print %q at %d:%d\n", text, line, column)
}
```

Do not import `procedures.go` from the generated `galley` package:
procedures already import `galley`, and that cycle would not compile. A
separate hooks package still works if `main` imports it so the
`//export`ed symbols stay in the binary.

Mechanically, gen reads the generator's hook list (`procedures` in
metadata.json) and produces a
Zig shim module containing one nullable function-pointer slot per hook;
your binary's init registers each `//export`ed address into its slot. The
parser calls through those slots directly, so hook code executes in *your*
process under *your* Go runtime — the shared library stays runtime-free,
which is what keeps loading it from Go programs safe (embedding a second
Go runtime via c-archive segfaults on linux/amd64). Each hook fires after
the corresponding variable is reduced; unregistered slots are no-ops.
Reduction hooks keep their `reduction_<VariableName>` names (plus the
general `reduction`); author-defined grammar hooks are declared as
`hook_<name>`. Semantic payloads are unavailable through bindings. Tree
queries use the parse's door, `galley.Args(ptr).Door()`, which implements
`galley.NodeDoor` like a session does; the door is the same for every hook of
one parse and valid until that parse ends. The arguments themselves are valid
only while their hook runs; drop/replace use `args.DropSelf()` and friends.

## Error Messages

To replace messages with fixed strings — no Zig file at all — pass
`MessageOverrides` in the session options. Keys are structured
identities: the innermost in-progress variable name (for example
`"Number"`), or `"*"` for every syntax and indentation error. Variable
keys win over `"*"`, and overrides take priority over hooks.
Placeholders expand against the failing diagnostic:

```go
options.MessageOverrides = map[string]string{
    "Number": "expected a number after ':' (digits only) at line {line}",
}
```

Override messages may contain `{line}`, `{column}`, `{unexpected}`,
`{expected}`, and `{context}` placeholders, expanded against the failing
diagnostic.

## Semantic Errors

A hook reports a semantic error when the input parses but its meaning is
invalid. `ReportSemanticError` records the diagnostic, marks the node, and
returns the running total so hooks can limit themselves. Parsing continues;
a syntax-clean parse with any semantic error fails with `ErrSemantic`:

```go
if value > 999 {
    _, _ = args.ReportSemanticError("value out of range")
}
```

Read them through `Session.Diagnostic` / `Session.Diagnostics`; the
snapshot carries `Kind == DiagnosticKindSemantic` and a `Semantic`
`{Variable, Message}` pair.

## Tree Walking

`Session.Walk` returns a pre-order `Walker` over the last successful parse,
yielding one `WalkStep{Node, Depth, IsSemanticError}` per step with the root
at depth 0 — the shared runtime walker, so order and depths match every
other binding. The walker owns no native resource: there is nothing to
close, and a walker left behind by a later parse answers `ErrStaleTree`
at its next step instead of reading stale storage. `SkipChildren` prunes
the last yielded node's children host-side; `Walk(root, true)` prunes
semantic-error subtrees. Steps follow the live links, so edits between
steps are visible, and a step whose position is no longer inside the
walk's root (removed, or moved elsewhere) reports `ErrInvalidNode`:

```go
walker := session.Walk(root, false)
for {
    step, ok, err := walker.Next()
    if err != nil { ... }
    if !ok { break }
    _ = step
}
```

`door.Walk(root, skip)` — `door` from a hook's `galley.Args(ptr).Door()` —
is the hook-door twin: it walks the running parse's in-flight tree through
`galley_hook_walk_next`, bound to that parse's own generation, and
reproduces the post-parse walk once the parse publishes.

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
the same session or `Close`. A failed parse counts as a later parse:
nothing is published, so `Snapshot()`, `NodeCount()`, and every node read
return `ErrStaleTree` until a successful parse, while `LastInput()` keeps
the last successful input. `RootNode()` is the one "is there a tree here"
probe: it answers `(root, true, nil)` for a published tree, `(_, false, nil)`
when nothing is published, and an error when the core refuses
(`ErrSessionInUse` while a parse runs). There is no validity
probe — a real read is the answer, and it fails. A `Node` carries the
core's parse generation and its address, and every read and edit hands that
generation to the core, which refuses one it no longer holds with
`ErrStaleTree`. `RootNode()` reports the generation with the root, a
`Snapshot` stamps its own (`Snapshot.Node(index)` makes a handle of that
parse), and links and walk steps carry their source's. Nothing is cached, so
no host-side reading can disagree with the core.

## Development builds

The Go module proxy serves every pushed commit, so any
commit is installable directly:

```sh
go get github.com/sanbus-org/galley/bindings/go@<commit-sha>
```

Tagged releases only mark stable points.

## Related Pages

- [C and C++](/bindings_c) — the underlying C ABI
- [Rust](/bindings_rust) — bindings over the same shared library
- [Configuration](/configuration) — the config.zig contract
- [Grammar Guidelines](/grammar_guidelines)
