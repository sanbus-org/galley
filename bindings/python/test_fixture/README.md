# Python binding test fixture

Keyvalue `procedures.py` copied from `examples/python/kv`; `ll.grm` and `config.zig` are symlinks to the one shared grammar in `bindings/test-fixture` when the binding suite
was decoupled from the user-facing examples. No rewrites: the hooks
use relative imports (`from . import ...`), so they execute only as a
submodule of this package on direct import.

The parser (`_ll-parser.zig`, `procedures.zig`,
`procedures_python.zig`, `metadata.json`, `libgalley-python.*`,
`galley_impl.*.so`, `__init__.py`, `__init__.pyi`) is built into this directory with:

    GALLEY_CHECKOUT=<checkout> python -m galley bindings/python/test_fixture

and the suite runs against it with:

    PYTHONPATH=bindings/python python bindings/python/tests/test_bindings.py

Edit these sources and the Python suite picks the change up on its
next run.
