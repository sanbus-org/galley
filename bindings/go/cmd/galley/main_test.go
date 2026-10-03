package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

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

// TestMain lets the wiring test below re-run this test binary as the real
// `galley` command.
func TestMain(m *testing.M) {
	if os.Getenv("GALLEY_TEST_RUN_MAIN") != "" {
		main()
		return
	}
	os.Exit(m.Run())
}

// recordConsumerBuildArguments runs `galley gen` with a fake generator and a
// fake zig that records its arguments and fails, so nothing builds.
func recordConsumerBuildArguments(t *testing.T, extraArguments ...string) []string {
	t.Helper()
	root := t.TempDir()
	checkout := filepath.Join(root, "checkout")
	languageDir := filepath.Join(root, "language")
	for _, directory := range []string{checkout, languageDir} {
		if err := os.MkdirAll(directory, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	recorded := filepath.Join(root, "recorded.txt")
	files := map[string]string{
		filepath.Join(checkout, "build.zig"):        "",
		filepath.Join(languageDir, "ll.grm"):        "",
		filepath.Join(languageDir, "metadata.json"): `{"procedures": ["reduction"]}`,
		filepath.Join(root, "generator"):            "#!/bin/sh\n[ \"$1\" = --help ] && echo --emit-metadata\nexit 0\n",
		filepath.Join(root, "zig"):                  "#!/bin/sh\nprintf '%s\\n' \"$@\" > '" + recorded + "'\nexit 1\n",
	}
	for path, content := range files {
		mode := os.FileMode(0o644)
		if strings.HasPrefix(content, "#!") {
			mode = 0o755
		}
		if err := os.WriteFile(path, []byte(content), mode); err != nil {
			t.Fatal(err)
		}
	}
	command := exec.Command(os.Args[0], append([]string{"gen", languageDir}, extraArguments...)...)
	command.Env = append(os.Environ(),
		"GALLEY_TEST_RUN_MAIN=1",
		"GALLEY_CHECKOUT="+checkout,
		"GALLEY_CLI="+filepath.Join(root, "generator"),
		"ZIG_EXECUTABLE="+filepath.Join(root, "zig"))
	output, err := command.CombinedOutput()
	if err == nil {
		t.Fatalf("fake zig should fail the command; output:\n%s", output)
	}
	raw, readErr := os.ReadFile(recorded)
	if readErr != nil {
		t.Fatalf("zig was not run: %v; output:\n%s", readErr, output)
	}
	return strings.Split(string(raw), "\n")
}

// -Doptimize reaches the consumer build only when a mode was chosen; the
// consumer build owns the default.
func TestConsumerBuildArgumentsOptimize(t *testing.T) {
	hasOptimize := func(arguments []string) bool {
		for _, argument := range arguments {
			if strings.HasPrefix(argument, "-Doptimize") {
				return true
			}
		}
		return false
	}
	if hasOptimize(recordConsumerBuildArguments(t)) {
		t.Error("no mode chosen, but -Doptimize was passed")
	}
	if hasOptimize(recordConsumerBuildArguments(t, "--optimize", "")) {
		t.Error("empty mode chosen, but -Doptimize was passed")
	}
	chosen := recordConsumerBuildArguments(t, "--optimize", "Debug")
	found := false
	for _, argument := range chosen {
		found = found || argument == "-Doptimize=Debug"
	}
	if !found {
		t.Errorf("-Doptimize=Debug missing from %v", chosen)
	}
}
