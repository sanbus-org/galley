# Go binding test fixture

Keyvalue `procedures.go` copied from `examples/go/demo`; `ll.grm` and `config.zig` are symlinks to the one shared grammar in `bindings/test-fixture` when the binding suite
was decoupled from the user-facing examples. Two mechanical rewrites
on the copies: `package main` became `package testfixture`, and the
generated-package import became
`github.com/sanbus-org/galley/bindings/go/testfixture/galley`.

`_ll-parser.zig`, `metadata.json`, `procedures_go.zig`,
`procedures.zig`, `galley/`, and the built library are generated into
this directory by `go generate ./testfixture/` from `bindings/go`,
never committed.

Edit these sources and the Go suite picks the change up on its next run.
