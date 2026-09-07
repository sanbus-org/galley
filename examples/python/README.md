# Galley Python example

Requires `python3` and `zig` (only the fetch script uses `git`; the build itself needs `GALLEY_CHECKOUT`).

```sh
pip install -e .
GALLEY_CHECKOUT=/path/to/galley python -m galley_bindings .
python demo.py
GALLEY_CHECKOUT=/path/to/galley python -m galley_bindings benchmark
python benchmark.py
```

Build, run, and benchmark conventions: see [examples/README.md](../README.md).
