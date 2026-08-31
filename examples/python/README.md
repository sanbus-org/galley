# Galley Python example

Requires `python3`, `zig`, and `git`.

```sh
pip install -e .
python -m galley_bindings .
python demo.py
python -m galley_bindings benchmark
python benchmark.py
```

The build fetches Galley on its own; set `GALLEY_CHECKOUT=/path/to/galley` to develop against a local Galley checkout instead. Pass a grammar-source file as an argument to parse that file instead of running the built-in demo. `benchmark.py` parses `languages/json/samples/code-01.json` 50,000 times through a no-AST, no-procedures, no-error-recovery JSON parser and prints bytes/s.
