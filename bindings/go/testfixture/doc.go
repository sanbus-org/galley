// Package testfixture is the Go binding's own test grammar: the shared
// keyvalue sources (ll.grm, config.zig, procedures.go) copied from
// examples/go/demo when the suite was decoupled from the user-facing
// examples. The binding tests in this directory build and exercise the
// parser generated here; edits to the examples never affect them.
//
//go:generate go run github.com/sanbus-org/galley/bindings/go/cmd/galley gen .
package testfixture
