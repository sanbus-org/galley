package main

import "testing"

// The download leg pins the exact module version: only clean releases
// resolve to artifacts, everything else is contributor mode.
func TestReleaseTagForVersion(t *testing.T) {
	cases := map[string]string{
		"v0.1.3":                     "v0.1.3",
		"v10.20.30":                  "v10.20.30",
		"(devel)":                    "",
		"":                           "",
		"v0.1.3-0.20240101120000-ab": "",
		"0.1.3":                      "",
		"main":                       "",
	}
	for version, want := range cases {
		if got := releaseTagForVersion(version); got != want {
			t.Errorf("releaseTagForVersion(%q) = %q, want %q", version, got, want)
		}
	}
}

func TestGeneratorAssetName(t *testing.T) {
	cases := map[[2]string]string{
		{"darwin", "arm64"}:  "galley-darwin-arm64",
		{"darwin", "amd64"}:  "galley-darwin-x64",
		{"linux", "amd64"}:   "galley-linux-x64",
		{"linux", "arm64"}:   "galley-linux-arm64",
		{"windows", "amd64"}: "galley-win32-x64.exe",
		{"windows", "arm64"}: "galley-win32-arm64.exe",
	}
	for platform, want := range cases {
		got, err := generatorAssetName(platform[0], platform[1])
		if err != nil || got != want {
			t.Errorf("generatorAssetName(%q) = %q, %v; want %q", platform, got, err, want)
		}
	}
	if _, err := generatorAssetName("linux", "riscv64"); err == nil {
		t.Error("generatorAssetName(riscv64) unexpectedly succeeded")
	}
}

func TestParseSums(t *testing.T) {
	sums := parseSums("abc123  galley-linux-x64\ndef456 *compile-kit.tar.gz\n\nnot-a-sum-line\n")
	if sums["galley-linux-x64"] != "abc123" {
		t.Errorf("missing plain checksum: %v", sums)
	}
	if sums["compile-kit.tar.gz"] != "def456" {
		t.Errorf("missing binary-mode checksum: %v", sums)
	}
	if len(sums) != 2 {
		t.Errorf("malformed lines must be skipped, got %v", sums)
	}
}

func TestParserTypeFromFlagsLastWins(t *testing.T) {
	if got := parserTypeFromFlags([]string{"--parser-type", "ll", "--parser-type=lr"}); got != "lr" {
		t.Errorf("last flag must win, got %q", got)
	}
	if got := parserTypeFromFlags([]string{"--no-ast"}); got != "" {
		t.Errorf("no parser-type flag must yield \"\", got %q", got)
	}
}
