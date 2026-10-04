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

// WrapperPreamble is the C the generated cgo preamble carries after the
// includes: one dispatch function per node capability, so the choice between
// the session family and its hook twin is written once.
//
//go:embed assets/dispatch.h
var WrapperPreamble string
