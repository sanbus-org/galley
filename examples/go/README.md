# Galley Go example

Requires `go` and `zig` (only the fetch script uses `git`; the build itself needs `GALLEY_CHECKOUT`).

```sh
GALLEY_CHECKOUT=/path/to/galley go generate ./...
go build -o galley-go-example ./demo
./galley-go-example
go build -o galley-go-benchmark ./benchmark
./galley-go-benchmark
```

Build, run, and benchmark conventions: see [examples/README.md](../README.md).
