# Python binding test fixture

Keyvalue `procedures.py` copied from `examples/python`; `ll.grm` and `config.zig` are symlinks to the one shared grammar in `bindings/test-fixture` when the binding suite
was decoupled from the user-facing examples. No rewrites: the hooks
only ever `import galley`, which resolves to whichever built extension
is on `PYTHONPATH`.

The parser (`_ll-parser.zig`, `procedures.zig`,
`procedures_python.zig`, `metadata.json`, `libgalley-python.*`,
`galley.*.so`, `galley.pyi`) is built into this directory with:

    GALLEY_CHECKOUT=<checkout> python -m galley_bindings bindings/python/test-fixture

and the suite runs against it with:

    PYTHONPATH=bindings/python/test-fixture python bindings/python/tests/test_bindings.py

Edit these sources and the Python suite picks the change up on its
next run.
