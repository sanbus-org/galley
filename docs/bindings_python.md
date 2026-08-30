# Python

Galley-generated parsers can be consumed from Python through a CPython
extension module: Galley compiles a generated parser into a shared library
(`lib<name>.dylib` / `.so`) together with the C header
[`bindings/c/galley.h`](https://github.com/sanbus-org/galley/blob/main/bindings/c/galley.h),
and the extension module in
[`bindings/python/_galley.c`](https://github.com/sanbus-org/galley/tree/main/bindings/python)
wraps that API directly — sessions, node handles, structured diagnostics,
and tree editing, with no ctypes or cffi marshalling layer in between.

A complete, runnable consumer lives in
[`examples/python`](https://github.com/sanbus-org/galley/tree/main/examples/python);
it is built and executed by CI on every push, byte-for-byte identical in
output to the C, C++, Rust, and Go examples.

## Getting Started

Run Galley's build command against your language directory (a directory
containing `ll.grm` and `config.zig`):

```sh
python3 <galley>/bindings/python/build.py <language-dir>
```

The command generates the parser (`--emit-metadata`), builds the shared
library through Galley's generic consumer build file, detects optional hook
files next to your grammar (`procedures.py` for native Python hooks,
`procedures.c` for legacy C hooks, `procedures.zig`,
`ll_error_messages.zig`), and compiles the extension module to
`<language-dir>/galley<ext-suffix>`. Import `galley` from that directory:

```python
import galley

session = galley.Session(max_errors=10)
parsed = session.parse_sentinel("alpha:12,beta:3")
root = session.root_node()
```

`ZIG_EXECUTABLE` selects zig; `CC` overrides the compiler used for the
extension module (defaults to the one that built your interpreter). The
module targets the interpreter that ran the build command; rebuild per
Python version. Regenerate after changing the grammar; commit nothing the
command generates. One module embeds one parser — split grammars across
language directories exactly like the other bindings.

## Performance Notes

The module is designed so the FFI boundary adds as little as possible:

- Every method is `METH_O` or `METH_FASTCALL`; calls allocate no argument
  tuples.
- Node handles are `galley.Node` objects that wrap a stable address in the
  library's non-relocating node storage and keep a strong reference to
  their owning `Session`; plain `int` addresses are still accepted wherever
  a node is expected for backward compatibility, and `Node` supports
  `int(node)` / `operator.index(node)` to retrieve the address. Iteration
  and indexing are zero-copy (`for child in node:`, `node[0]`, `len(node)`).
- Text accessors (`text`, `symbol_name`, diagnostic tokens) return `bytes`
  with no UTF-8 decoding step; decode on demand.
- `parse()` reads `str` input zero-copy through the interpreter's cached
  UTF-8 buffer. `parse_sentinel()` additionally avoids the session's input
  copy — keep the input object alive until the next parse on the session.
- All calls hold the GIL; sessions are not thread-safe. Use one session
  per thread or guard it externally.

Node text, diagnostics, and expected-token data remain valid only until
the next parse on the same session; every accessor copies before
returning, so Python-side values never dangle. `Node` methods check that
their session is still open and raise `ValueError` after `session.close()`
or exiting a `with` block.

## Procedures

Set `pub const procedures = true;` in your grammar's `config.zig` and
implement the hooks in Python in a `procedures.py` file next to your
grammar — an ordinary Python module imported by the extension at load time.
No C anywhere on the consumer side, mirroring Rust's `procedures.rs` and
Go's `hooks/procedures.go`:

```python
# procedures.py
import sys

def reduction_Pair(args):
    print("[hook] Pair", file=sys.stderr)

def hook_print(args):
    print("[hook] print (Key)", file=sys.stderr)

# args is the opaque ProcedureArguments pointer as an int (pass to future
# helpers or ignore). Hooks that take no args are also accepted:
# def reduction_Pair(): ...
```

Mechanically, `build.py` reads the grammar's generated hook list and
produces a Zig shim module containing one dispatch slot; the extension
registers the Python callables into that slot at import time (it tries
`import procedures` on `sys.path` — the language dir is typically on
`PYTHONPATH` — and falls back to explicit registration). The parser calls
through the slot directly, so hook code executes in the host's Python
interpreter. Unregistered slots are no-ops.

Explicit registration is also available and composes with auto-import:

```python
import galley, procedures

galley.install_procedure("reduction_Pair", lambda args: print("Pair"))
galley.install_procedures(procedures)  # all reduction_*/hook_* in module
galley.list_procedures()   # {name: callable}
galley.clear_procedures()
```

When neither Python nor C implementations exist, the shim is still generated
as a no-op fallback so the library links; hooks are simply no-ops until
registered via `galley.install_procedure` without requiring a rebuild,
mirroring Go's always-shim model. `galley.has_procedures()` reports whether
the library was built with procedure hooks compiled in.

Legacy `procedures.c` / `procedures.cpp` hooks continue to work exactly
like the C/C++ consumers: the build compiles the C file into the shared
library when no `procedures.py` is present. If both Python and C files
exist, Python takes precedence and a warning is emitted. Reduction hooks
keep their `reduction_<VariableName>` names (plus the general `reduction`);
author-defined grammar hooks are declared as `hook_<name>`. Semantic
payloads are unavailable through bindings.

## Error Messages

Run `galley --fill-error-messages <language-dir>` and edit the generated
`ll_error_messages.zig` next to your grammar. The build command detects it
and compiles it into the shared library;
`session.diagnostic().message` then returns your hooks' text instead of
the built-in generic renderer. LR grammars use `lr_error_messages.zig`.

## Sessions

```python
with galley.Session(max_errors=10, recovery_window=500) as session:
    try:
        parsed = session.parse("alpha:12,beta:3")
    except galley.Error as error:
        diagnostic = error.diagnostic
        print(f"{diagnostic.line}:{diagnostic.column}: {diagnostic.message}")
```

Options mirror the runtime defaults: `max_errors=10`,
`recovery_window=500`, `stack_overflow_recovery=False`,
`syntax_error_stack_depth=0`, `verbosity=0`,
`ast_preallocation_ratio=-1.0`, `ast_preallocation_cap=0`.
Failures raise `galley.Error`, whose `code` and `diagnostic` attributes carry the raw
status code and the snapshot for that failure (`error.diagnostic` is `None` when no diagnostic, otherwise a `galley.Diagnostic`; `session.diagnostic()` remains for the last diagnostic).

`Session` is a context manager (`with galley.Session() as s:` closes on exit)
and `close()` is idempotent. Every session method that takes a node also
accepts a `galley.Node` or a plain `int` address; session methods that
return nodes now return `galley.Node`. Nodes are bound to their session:
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

`session.diagnostic()` returns a frozen snapshot (`galley.Diagnostic`)
with `kind`, `line`, `column`, `message`, `message_ansi`,
`unexpected_token`, `expected_tokens`, `context`, `syntax_error_count`,
indentation details, and the full structured recovery information — or
`None` when the last parse succeeded.

## Tests

The bindings ship a behavioral suite that runs against any built module:

```sh
PYTHONPATH=examples/python python3 bindings/python/tests/test_bindings.py
```

## Related Pages

- [C and C++](/bindings_c) — the underlying C ABI
- [Rust](/bindings_rust) and [Go](/bindings_go) — bindings over the same
  shared library
- [Configuration](/configuration) — galley.json schema
- [Grammar Guidelines](/grammar_guidelines)
