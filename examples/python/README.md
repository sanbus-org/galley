# Galley Python example

Requires `python3`, `zig`, and `git`.

```sh
python3 ../../bindings/python/build.py .
PYTHONPATH=. python3 main.py
```

`build.py` generates the parser (`--emit-metadata`), builds the shared library, and compiles the `galley` extension module (`galley.*.so`) next to your grammar — no `pip` step needed. `procedures.py` (`hooks/procedures.py` also accepted) is the native-language hook file, mirroring `Rust`'s `procedures.rs` and `Go`'s `hooks/procedures.go`; legacy `procedures.c` still works. Pass a file as an argument to parse that file instead of running the built-in demo.
