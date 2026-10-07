# Python

Galley-generated parsers can be consumed from Python through a CPython
extension module: Galley compiles a generated parser into a static archive
together with the C header
[`bindings/c/galley.h`](https://github.com/sanbus-org/galley/blob/main/bindings/c/galley.h),
and the extension module in
[`bindings/python/_galley.c`](https://github.com/sanbus-org/galley/tree/main/bindings/python)
links it in whole — sessions, node handles, structured diagnostics,
and tree editing, with no ctypes or cffi marshalling layer in between.
One self-contained artifact per grammar, consumed either by direct
package import (bundled hooks automatic) or by bare file load through
the `galley` loader (manual hooks only).

A complete, runnable consumer lives in
[`examples/python`](https://github.com/sanbus-org/galley/tree/main/examples/python):
the `kv` keyvalue package behind `demo.py` and the `json` JSON
package behind `benchmark.py`.
It is built and executed by CI on every push.

## Getting Started

Add the bindings package to your `pyproject.toml` and point it at a Galley
checkout:

```toml
[project]
dependencies = [
    "galley @ file:../../bindings/python",
]
```

Then generate the parser for your language directory (a directory
containing `ll.grm` and `config.zig`):

```sh
pip install -e .
python -m galley <language-dir> [generator flags...]
```

Generator flags forward verbatim to the generator ahead of
`--emit-host-procedures`: every flag the tool does not own goes to the generator,
which owns its surface (documented in [Configuration](/configuration)).

Add `--optimize Debug` to build the parser library in Debug with the
runtime's misuse checks (a failed check aborts the process); the default is ReleaseFast. `--optimize` takes any
Zig build mode (`Debug`, `ReleaseSafe`, `ReleaseFast`, `ReleaseSmall`).

The command generates the parser (`--emit-host-procedures`), builds the grammar
as a static archive through Galley's generic consumer build file, detects
optional hook files next to your grammar (`procedures.py` for Python
hooks, `procedures.zig`, `ll_error_messages.zig`), and turns the language
directory into an importable package: a generated `__init__.py` plus the
linked inner extension.

Direct package import is the primary path. It needs the folder name to
be a valid identifier and its parent on `sys.path`, and it wires bundled
hooks automatically:

```python
import my_language

with my_language.Session(max_errors=10) as session:
    parsed = session.parse("alpha:12,beta:3")
    root = session.root_node()
```

Bare file loads take any path to the built inner extension and never
scan for hooks — wire them manually through the parser API:

```python
import galley

parser = galley.load("./my-language/galley_impl.cpython-314-darwin.so")
with parser.Session(max_errors=10) as session:
    parsed = session.parse("alpha:12,beta:3")
    root = session.root_node()
```

A missing file raises `galley.MissingArtifactError` naming the
expected file and the build command. Bundled `procedures.py` files are
package-only: they use relative imports and execute solely through the
generated init, never through a bare load.

`ZIG_EXECUTABLE` selects zig; `CC` overrides the compiler used for the
extension module (defaults to the one that built your interpreter). The
module targets the interpreter that ran the build command; rebuild per
Python version. No checkout is needed: the published package carries the
generator CLI for every platform and the compile inputs, so only the
package plus zig are required — for convenience,
`GALLEY_CHECKOUT=$(examples/scripts/fetch-galley.sh)` fetches a checkout
into the system cache for contributors, but that cache is examples-only,
not part of the bindings. The grammar archive (`libgalley-python.a`) links
into the extension next to the grammar, so the artifact is self-contained.
Regenerate
after changing the grammar; commit nothing the command generates. One
package embeds one parser — split grammars across language directories.
Two packages coexist in one process with
independent hooks: each package import is its own parser. Bare
loads share one `sys.modules` key with last-load-wins semantics while
the loader cache holds every object; pickling across processes is
unsupported. Rename non-identifier folders to import them directly:
standard rule, no hyphen support in the loader.

## Performance Notes

The module is designed so the FFI boundary adds as little as possible:

- Every method is `METH_O` or `METH_FASTCALL`; calls allocate no argument
  tuples.
- Node handles are `Node` objects that wrap a stable address in the
  library's non-relocating node storage and keep a strong reference to
  their owning `Session`; a session method takes a `Node` and refuses a
  raw address, so `Node.address` stays display-only. Iteration
  and indexing are zero-copy (`for child in node:`, `node[0]`, `len(node)`).
- Text accessors (`text`, `symbol_name`, diagnostic tokens) return `bytes`
  with no UTF-8 decoding step; decode on demand.
- `parse()` reads `str` input zero-copy through the interpreter's cached
  UTF-8 buffer. The session retains a copy, so node text stays valid
  after return regardless of the input object's lifetime.
- A parse releases the GIL (hooks take it back for the length of their call),
  so sessions on different threads parse in parallel; every other call holds
  it. Sessions are not thread-safe: use one session per thread or guard it
  externally.

Node text, diagnostics, and expected-token data remain valid only until
the next parse on the same session; every accessor copies before
returning, so Python-side values never dangle. `Node` methods raise
`ValueError` after `session.close()` or exiting a `with` block. A node
carries the core's parse generation and the core checks it on every call:
after a re-parse, node methods, walkers, and snapshot nodes of the earlier
parse raise `galley.StaleTreeError`, a `GalleyError` subclass with code
`ERROR_STALE_TREE`. Until a parse publishes, `session.node_count()`,
`session.snapshot()`, `session.last_input()` and `session.last_position()`
raise it too — before the first parse, and after a parse that published
nothing — and `session.root_node()` returns `None`, the one "is there a tree
here" probe; there is no validity probe.

A parse that fails after running to its end publishes its tree like a
success, and `parse()` still raises: one that recorded only semantic errors,
and one whose syntax errors the parser recovered from. `session.root_node()`
returns the tree, `last_input()` is that input, and the damaged regions are
nodes flagged `is_recovered` on walk steps and the snapshot, spanning the
input recovery skipped (the damaged variable's own node under LL, a
childless placeholder under LR); a walk with `skip_recovered=True` yields only
undamaged nodes. A parse the parser could not recover from, or that failed
to read, publishes nothing.

## Procedures

Set `pub const procedures = true;` in your grammar's `config.zig` and
implement the hooks in Python in a `procedures.py` file next to your
grammar — an ordinary Python module wired by the generated package init
on direct import only. Bare `galley.load()` never scans it.
No C anywhere on the consumer side:

```python
# procedures.py
import sys
from . import ProcedureArguments

def reduction_Pair(args: ProcedureArguments) -> None:
    node = args.current_node()
    if node is None:
        return
    line, column = node.line_column() or (0, 0)
    text = (node.text() or b"").decode()
    print(f"Pair {text} ({len(node)} children) at {line}:{column}",
          file=sys.stderr)

def reduction_KeyTail(args: ProcedureArguments) -> None:
    args.drop_if_empty()

def hook_print(args: ProcedureArguments) -> None:
    node = args.current_node()
    if node is None:
        return
    line, column = node.line_column() or (0, 0)
    text = (node.text() or b"").decode()
    print(f'@print "{text}" at {line}:{column}', file=sys.stderr)
```

`ProcedureArguments` is valid only while its hook runs: the core refuses every
call made with the arguments of a hook that has returned, and the object keeps
no expiry state of its own, so a kept reference raises `GalleyError` with code
`ERROR_STALE_HOOK`, from a later hook of the same parse and after the parse
alike. `node_capacity()`, `node_count()`, `snapshot()`, `last_input()` and
`last_position()` raise `GalleyError` with `ERROR_SESSION_IN_USE` inside a hook,
never 0 or an empty value, and a walker belongs to the parse of the tree it was
created over: stepping it after a re-parse raises `StaleTreeError`, even if it
had already finished. Text and input bytes are copies that outlive the next
parse. The nodes it yields belong to the parse: a hook may keep one for
later hooks of the same parse, and, when the parse publishes (a success, or
a failure that ran to its end), for use after it until the session parses
again. A node of a parse that published nothing raises. A node reads
through the parse's hook door only inside a hook of that parse on the thread
running it; from any other thread while the parse runs it raises `GalleyError`
with `ERROR_SESSION_IN_USE`, and a parse the core refuses invalidates nothing.
Inside a hook the core checks every node's generation on that door too: a node
of an earlier parse raises `StaleTreeError` on a read, a link, an edit or a
walk step, never `None`.

A hook that raises aborts the parse. `parse` raises `GalleyError` with code
`ERROR_HOOK_FAILED`, the hook's own exception as `__cause__`, and a `Kind.HOOK`
diagnostic of where the parse stopped; the parse publishes nothing, so
`root_node()` is `None` and the nodes of that parse raise `StaleTreeError`. The
session parses again afterwards. A hook that wants the parse to go on reports a
semantic error instead (see below).

Mechanically, `python -m galley` links the generator's host shim
(`host_procedures.zig`, written by `--emit-host-procedures`), which forwards
every hook to the parsing session's own dispatch. The generated init registers
the Python callables from `procedures.py` beside the package as the artifact's
defaults: every `Session` starts with a copy and owns it from then on, so a
default installed later reaches only sessions opened later (later installs win
per hook name). A session has the same install, list, look-up and clear
methods for its own hooks, and a change raises `GalleyError`
(`ERROR_SESSION_IN_USE`) while a parse is in flight.
`procedures.py` uses relative imports: it always executes as a submodule
of the language package, so hook code sees the right `Session` and the
same `GalleyError` class the parser raises. Hook code executes in the host's
Python interpreter; a parse releases the GIL, so sessions on different threads
parse in parallel and a hook takes the GIL back for the length of its call.
A hook the session did not install returns before any call.

Explicit registration is also available. On a bare-loaded parser it is
the only wiring; on a package it composes with the scan:

```python
import galley

parser = galley.load("./my-language/galley_impl.cpython-314-darwin.so")
parser.install_procedure("reduction_Pair", lambda args: print("Pair"))
parser.install_procedures(my_hooks)  # all reduction_*/hook_* in my_hooks
parser.list_procedures()   # {name: callable}
parser.procedure_hook("reduction_Pair")   # the callable, or None
parser.clear_procedures()

with parser.Session() as session:   # copies the defaults above
    session.install_procedure("reduction_Number", lambda args: print("Number"))
    session.parse("alpha:12")
```

When the grammar ships no hooks, the build writes an empty
`procedures.py`; the shim is still linked so the archive links
and hooks are simply no-ops until
registered via `parser.install_procedure` or `session.install_procedure`
without requiring a rebuild.
`parser.has_procedures()` reports whether
the library was built with procedure hooks compiled in.

Reduction hooks
keep their `reduction_<VariableName>` names (plus the general `reduction`);
author-defined grammar hooks are declared as `hook_<name>`. Semantic
payloads are unavailable through bindings.

## Tree Walking

`node.walk()` returns a pre-order `Walker` over that node's subtree,
yielding read-only `WalkStep` objects with `node`, `depth`,
`is_semantic_error` and `is_recovered` attributes; the node itself is at depth 0 — the
shared runtime walker. The walker owns no native
resource: no `close` and no context-manager block, and abandoning it is
free — its next step raises the dead-generation error instead of reading
stale storage. `walk()` itself does not raise for a stale node; the first
step does. `walker.skip_children()` prunes the last yielded
node's children host-side, without a native call;
`node.walk(skip_semantic_errors=True)` prunes
subtrees rooted at semantic-error nodes and `node.walk(skip_recovered=True)`
those rooted at recovered nodes. Steps follow the live links, so
edits between steps are visible, and a step whose position is no longer
inside the walk's root (removed, or moved elsewhere) raises
`GalleyError` with `ERROR_INVALID_NODE`:

```python
for step in session.root_node().walk():
    print("  " * step.depth, session.symbol_name(step.node))
```

## Error Messages

Run `galley --fill-error-messages <language-dir>` and edit the generated
`ll_error_messages.zig` next to your grammar. The build command detects it
and compiles it into the grammar archive;
`session.diagnostic().message` then returns your hooks' text instead of
the built-in generic renderer. LR grammars use `lr_error_messages.zig`.

## Sessions

```python
parser = galley.load("./my-language/galley_impl.cpython-314-darwin.so")

with parser.Session(max_errors=10, recovery_window=500) as session:
    try:
        parsed = session.parse("alpha:12,beta:3")
    except parser.GalleyError as error:
        diagnostic = error.diagnostic
        print(f"{diagnostic.line}:{diagnostic.column}: {diagnostic.message}")
```

Options mirror the runtime defaults: `max_errors=10`,
`recovery_window=500`, `stack_overflow_recovery=False`,
`syntax_error_stack_depth=0`, `verbosity=0`,
`ast_preallocation_ratio=-1.0`, `ast_preallocation_cap=0`.
Failures raise `parser.GalleyError`, whose `code` and `diagnostic` attributes carry the raw
status code and the snapshot for that failure (`error.diagnostic` is `None` when no diagnostic, otherwise a `parser.Diagnostic`; `session.diagnostic()` remains for the last diagnostic).

`Session` is a context manager (`with parser.Session() as s:` closes on exit)
and `close()` is idempotent. Every session method that takes a node takes
a `parser.Node` and refuses a raw address with `TypeError`; session
methods that return nodes return `parser.Node`. Nodes are bound to their
session:
`root = session.root_node()` then `root.text()`, `root.symbol_name()`,
`root.span()`, `root.line_column()`, `root.parent()`,
`root.first_child()` / `root.last_child()` / `root.next_sibling()` /
`root.prior_sibling()`, `root.children()` (tuple of `Node`), `len(root)`,
`root[i]` / `root[i].children()`, and `for child in root:` all read
directly from the node. Editing helpers are available both ways:
`root.clean_children()` / `session.clean_children(root)` and
`root.append_children(chain)` / `session.append_children(root, chain)`
(where `chain` is a detached head); the remaining tree edits
(`insert_before`, `remove_self`, `remove_siblings`, `insert_children_at`,
`remove_children_at`)
live on `Session` and take `Node`. Missing links return `None`.
`session.diagnostics()` returns every recorded diagnostic as a tuple of
snapshots. Nodes compare by identity (`==` checks same session, parse
generation, and address), hash consistently with that, and expose
`node.address` for display; `session.snapshot().node(index)` is the one
conversion from a stored address back to a node.

`session.diagnostic()` returns a frozen snapshot (`parser.Diagnostic`)
with `kind`, `line`, `column`, `message`, `message_ansi`,
`unexpected_token`, `expected_tokens`, `context`, `syntax_error_count`,
`semantic_error_count`, `semantic` (a `(variable bytes, message)` pair
for semantic errors, else `None`),
indentation details, and the full structured recovery information — or
`None` when the last parse succeeded.

A hook reports a semantic error through `args.report_semantic_error(message)`,
which returns the running total so hooks can limit themselves. Parsing
continues and a syntax-clean parse with any semantic error raises
`parser.GalleyError` with code `Status.ERROR_SEMANTIC` (`Kind.SEMANTIC` diagnostics):

```python
def reduction_Number(args: ProcedureArguments) -> None:
    node = args.current_node()
    assert node is not None
    text = node.text()
    assert text is not None
    if int(text) > 99:
        args.report_semantic_error("value out of range")
```

## Tests

The bindings ship a behavioral suite that runs against the binding's own
test fixture (built on demand, never examples/):

```sh
GALLEY_CHECKOUT=$PWD python -m galley bindings/python/test_fixture
PYTHONPATH=bindings/python python3 bindings/python/tests/test_bindings.py
```

## Development builds

Every green `main` push publishes dev versions to the static registry.
Dev versions look like
`0.1.3.dev42` (the PEP 440 form of `0.1.3-dev.42.gabc123456789`):

```sh
pip install --extra-index-url https://<R2_PACKAGES_HOSTNAME>/simple/ galley==0.1.3.dev42
```

Dev versions are ephemeral: they expire after about 48 hours, and only
the newest ~20 are kept.
Stable releases stay on PyPI; pin a stable release for anything durable.
Every CI run also uploads the built sdist and
wheel as workflow artifacts (Actions → the run → Artifacts →
`pkg-python`), carrying that commit's generator and compile kit.

## Related Pages

- [C and C++](/bindings_c) — the underlying C ABI
- [Rust](/bindings_rust) and [Go](/bindings_go) — bindings over per-grammar
  artifacts over the same C ABI
- [Configuration](/configuration) — galley.json schema
- [Grammar Guidelines](/grammar_guidelines)
