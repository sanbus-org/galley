// Package galleybindings ships the Go bindings' build tooling. The wrapper
// source embedded here is the single source of truth that
// cmd/galley emits into each consumer project alongside its generated cgo
// preamble.
package galleybindings

import _ "embed"

// WrapperTemplate is the session/node wrapper body (without package or
// import clauses) emitted as part of the generated galley package.
//
//go:embed assets/wrapper.go.tmpl
var WrapperTemplate string
