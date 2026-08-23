package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDetectParser(t *testing.T) {
	cases := []struct {
		name       string
		hasLL      bool
		hasLR      bool
		wantSource string
		wantType   string
		wantErr    bool
	}{
		{name: "ll only", hasLL: true, wantSource: "_ll-parser.zig", wantType: "ll"},
		{name: "lr only", hasLR: true, wantSource: "_lr-parser.zig", wantType: "lr"},
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
			source, parserType, err := detectParser(dir)
			if testCase.wantErr {
				if err == nil {
					t.Fatalf("expected an error, got source=%q type=%q", source, parserType)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if source != testCase.wantSource || parserType != testCase.wantType {
				t.Fatalf("got %q/%q, want %q/%q", source, parserType, testCase.wantSource, testCase.wantType)
			}
		})
	}
}
