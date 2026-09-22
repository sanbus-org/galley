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
It is built and executed by CI on every push, byte-for-byte identical in
output to the C, C++, Rust, and Go examples.

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
`--emit-metadata`: every flag the tool does not own goes to the generator,
which owns its surface (documented in [Configuration](/configuration)).

The command generates the parser (`--emit-metadata`), builds the grammar
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
scan for hooks — wire them manually through the module API:

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
package embeds one parser — split grammars across language directories
exactly like the other bindings. Two packages coexist in one process with
independent hooks: each package import is its own module object. Bare
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
  their owning `Session`; plain `int` addresses are still accepted wherever
  a node is expected for backward compatibility, and `Node` supports
  `int(node)` / `operator.index(node)` to retrieve the address. Iteration
  and indexing are zero-copy (`for child in node:`, `node[0]`, `len(node)`).
- Text accessors (`text`, `symbol_name`, diagnostic tokens) return `bytes`
  with no UTF-8 decoding step; decode on demand.
- `parse()` reads `str` input zero-copy through the interpreter's cached
  UTF-8 buffer. The session retains a copy, so node text stays valid
  after return regardless of the input object's lifetime.
- All calls hold the GIL; sessions are not thread-safe. Use one session
  per thread or guard it externally.

Node text, diagnostics, and expected-token data remain valid only until
the next parse on the same session; every accessor copies before
returning, so Python-side values never dangle. `Node` methods check that
their session is still open on the node's parse generation and raise
`ValueError` after `session.close()`, exiting a `with` block, or a
re-parse.

## Procedures

Set `pub const procedures = true;` in your grammar's `config.zig` and
implement the hooks in Python in a `procedures.py` file next to your
grammar — an ordinary Python module wired by the generated package init
on direct import only. Bare `galley.load()` never scans it.
No C anywhere on the consumer side, mirroring Rust's `procedures.rs` and
Go's `procedures.go`:

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

Mechanically, `python -m galley` reads the generator's hook list
(`procedures` in metadata.json) and produces a Zig shim module containing
one dispatch slot;
the generated init registers the Python callables into that slot from
`procedures.py` beside the package. Extra hooks go through the module's
`install_procedures` directly, where the shared-registry semantics are
visible (later installs win per hook name).
`procedures.py` uses relative imports: it always executes as a submodule
of the language package, so hook code sees the right `Session` and the
same `GalleyError` class the parser raises. The parser calls through the slot
directly, so hook code executes in the host's Python interpreter.
Unregistered slots are no-ops.

Explicit registration is also available. On a bare-loaded module it is
the only wiring; on a package it composes with the scan:

```python
import galley

parser = galley.load("./my-language/galley_impl.cpython-314-darwin.so")
parser.install_procedure("reduction_Pair", lambda args: print("Pair"))
parser.install_procedures(my_hooks)  # all reduction_*/hook_* in module
parser.list_procedures()   # {name: callable}
parser.procedure_hook("reduction_Pair")   # the callable, or None
parser.clear_procedures()
```

When no `procedures.py` exists, the shim is still generated
as a no-op fallback so the archive links; hooks are simply no-ops until
registered via `parser.install_procedure` without requiring a rebuild,
mirroring Go's always-shim model. `parser.has_procedures()` reports whether
the library was built with procedure hooks compiled in.

Reduction hooks
keep their `reduction_<VariableName>` names (plus the general `reduction`);
author-defined grammar hooks are declared as `hook_<name>`. Semantic
payloads are unavailable through bindings.

## Tree Walking

`session.walk(root)` returns a pre-order `Walker` over the last successful
parse, yielding `{"node", "depth", "is_semantic_error"}` dicts with the
root at depth 0 — the shared runtime walker, so order and depths match
every other binding. `walker.skip_children()` prunes the last yielded
node's children; `session.walk(root, skip_semantic_errors=True)` prunes
subtrees rooted at semantic-error nodes:

```python
for step in session.walk(session.root_node()):
    print("  " * step["depth"], session.symbol_name(step["node"]))
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
and `close()` is idempotent. Every session method that takes a node also
accepts a `parser.Node` or a plain `int` address; session methods that
return nodes now return `parser.Node`. Nodes are bound to their session:
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
`remove_children_at`, `promote_children_over_wrapper`, `unlink_wrapper`)
live on `Session` and accept `Node` or `int`. Missing links return `None`.
`session.diagnostics()` returns every recorded diagnostic as a tuple of
snapshots. Nodes compare by identity (`==` checks same session and address),
hash by address, and support `int(node)` to recover the raw address.

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
