package main

import (
	"os"
	"path/filepath"
	"testing"

	galley "github.com/sanbus-org/galley/examples/go/galley"
)

func TestGalleyJSONMessageOverrides(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "galley.json")
	valid := `{
	    "ast": true,
	    "error_messages": {
	        "syntax_error_ll_Number__expected_generative_terminal_digit":
	            "expected a number after ':' (digits only)",
	        "syntax_error": "parse failed near line {line}"
	    }
	}`
	if err := os.WriteFile(path, []byte(valid), 0o644); err != nil {
		t.Fatal(err)
	}
	overrides := galley.GalleyJSONMessageOverrides(path)
	if len(overrides) != 2 {
		t.Fatalf("expected 2 overrides, got %d", len(overrides))
	}
	if overrides["syntax_error"] != "parse failed near line {line}" {
		t.Fatalf("unexpected syntax_error override: %q", overrides["syntax_error"])
	}

	if err := os.WriteFile(path, []byte(`{"error_messages": {"k": 12}}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := galley.GalleyJSONMessageOverrides(path); got != nil {
		t.Fatalf("expected nil for malformed entry, got %v", got)
	}
	if got := galley.GalleyJSONMessageOverrides(filepath.Join(dir, "missing.json")); got != nil {
		t.Fatalf("expected nil for missing file, got %v", got)
	}
}
