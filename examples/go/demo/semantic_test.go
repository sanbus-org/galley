package main

import (
	"errors"
	"testing"

	galley "github.com/sanbus-org/galley/examples/go/demo/galley"
)

// The file hooks in procedures.go report values above 999 as semantic
// errors; demo inputs stay below that bound so demo output is unchanged.
func TestSemanticErrorsAggregateAndFail(t *testing.T) {
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	defer session.Close()

	if _, err := session.Parse([]byte("alpha:1,beta:2000,gamma:3000")); !errors.Is(err, galley.ErrSemantic) {
		t.Fatalf("expected ErrSemantic, got %v", err)
	}
	diagnostic, ok := session.Diagnostic()
	if !ok {
		t.Fatal("expected a diagnostic")
	}
	if diagnostic.Kind != galley.DiagnosticKindSemantic {
		t.Fatalf("expected semantic kind, got %d", diagnostic.Kind)
	}
	if diagnostic.Semantic == nil {
		t.Fatal("expected semantic fields")
	}
	if diagnostic.Semantic.Variable != "Number" || diagnostic.Semantic.Message != "value out of range" {
		t.Fatalf("unexpected semantic fields: %+v", diagnostic.Semantic)
	}
	recorded := session.Diagnostics()
	if len(recorded) != 2 {
		t.Fatalf("expected 2 recorded diagnostics, got %d", len(recorded))
	}
}

func TestCleanParseAfterSemanticFailure(t *testing.T) {
	session, err := galley.New()
	if err != nil {
		t.Fatalf("session: %v", err)
	}
	defer session.Close()

	if _, err := session.Parse([]byte("alpha:2000")); !errors.Is(err, galley.ErrSemantic) {
		t.Fatalf("expected ErrSemantic, got %v", err)
	}
	if _, err := session.Parse([]byte("alpha:12")); err != nil {
		t.Fatalf("clean parse: %v", err)
	}
	if _, ok := session.Diagnostic(); ok {
		t.Fatal("expected no diagnostic after clean parse")
	}
}
