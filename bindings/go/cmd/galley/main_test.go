package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestFindGeneratedParser(t *testing.T) {
	cases := []struct {
		name       string
		hasLL      bool
		hasLR      bool
		wantSource string
		wantErr    bool
	}{
		{name: "ll only", hasLL: true, wantSource: "_ll-parser.zig"},
		{name: "lr only", hasLR: true, wantSource: "_lr-parser.zig"},
		{name: "neither", wantErr: true},
		{name: "both is ambiguous", hasLL: true, hasLR: true, wantErr: true},
	}
	for _, testCase := range cases {
		t.Run(testCase.name, func(t *testing.T) {
			dir := t.TempDir()
			write := func(name string) {
				if err := os.WriteFile(filepath.Join(dir, name), []byte("// generated\n"), 0o644); err != nil {
					t.Fatal(err)
				}
			}
			if testCase.hasLL {
				write("_ll-parser.zig")
			}
			if testCase.hasLR {
				write("_lr-parser.zig")
			}
			source, err := findGeneratedParser(dir)
			if testCase.wantErr {
				if err == nil {
					t.Fatalf("expected an error, got source=%q", source)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if source != testCase.wantSource {
				t.Fatalf("got %q, want %q", source, testCase.wantSource)
			}
		})
	}
}
