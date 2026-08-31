# Galley Go example

Requires `go`, `zig`, and `git`.

```sh
go generate ./...
go build -o galley-go-example ./demo
./galley-go-example
go build -o galley-go-benchmark ./benchmark
./galley-go-benchmark
```

The build fetches Galley on its own; set `GALLEY_CHECKOUT=/path/to/galley` to develop against a local Galley checkout instead. Pass a grammar-source file as an argument to parse that file instead of running the built-in demo. `galley-go-benchmark` parses `languages/json/samples/code-01.json` 50,000 times through a no-AST, no-procedures, no-error-recovery JSON parser and prints bytes/s.
