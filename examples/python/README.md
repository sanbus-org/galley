# Galley Python example

Requires `python3`, `zig`, and `git`.

```sh
pip install -e .
python -m galley_bindings .
python main.py
```

The build fetches Galley on its own; set `GALLEY_CHECKOUT=/path/to/galley` to develop against a local Galley checkout instead. Pass a grammar-source file as an argument to parse that file instead of running the built-in demo.
