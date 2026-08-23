// Command galley generates and builds a Galley parser as a shared library
// for the Go bindings, then emits the cgo bridge package into the language
// directory.
//
// Usage:
//
//	go run github.com/sanbus-org/galley/bindings/go/cmd/galley gen <language-dir>
//
// The language dir must contain ll.grm and galley.json (generation options)
// and may contain procedures.c (procedure hook implementations) and
// ll_error_messages.zig (custom syntax-error message hooks), mirroring the
// C, C++, and Rust consumers.
//
// Environment overrides: GALLEY_CHECKOUT (existing Galley working tree,
// wins over fetching), GALLEY_REPOSITORY, GALLEY_TAG (default main),
// ZIG_EXECUTABLE (default zig).
package main

import (
	"fmt"
	"go/format"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	galleybindings "github.com/sanbus-org/galley/bindings/go"
)

var wrapperTemplate = galleybindings.WrapperTemplate

const (
	defaultRepository = "https://github.com/sanbus-org/galley.git"
	defaultTag        = "main"
	libName           = "galley-go"
)

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "galley-bindings: "+format+"\n", args...)
	os.Exit(1)
}

func run(command *exec.Cmd) {
	command.Stdout = os.Stdout
	command.Stderr = os.Stderr
	if err := command.Run(); err != nil {
		fatal("command failed: %v", command)
	}
}

func env(name string) string {
	value := os.Getenv(name)
	if value == "" {
		return ""
	}
	return value
}

func zigExecutable() string {
	if value := env("ZIG_EXECUTABLE"); value != "" {
		return value
	}
	return "zig"
}

func mustAbsolute(path string) string {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	return absolute
}

// detectParser reports which parser family generation produced (one
// library embeds one parser; both families present is ambiguous).
func detectParser(languageDir string) (parserSource string, parserType string, err error) {
	var hasLL, hasLR bool
	if _, err := os.Stat(filepath.Join(languageDir, "_ll-parser.zig")); err == nil {
		hasLL = true
	}
	if _, err := os.Stat(filepath.Join(languageDir, "_lr-parser.zig")); err == nil {
		hasLR = true
	}
	switch {
	case hasLL && !hasLR:
		return "_ll-parser.zig", "ll", nil
	case hasLR && !hasLL:
		return "_lr-parser.zig", "lr", nil
	case hasLL && hasLR:
		return "", "", fmt.Errorf(
			"both _ll-parser.zig and _lr-parser.zig exist in %s; one library embeds one parser — split the language dirs",
			languageDir)
	default:
		return "", "", fmt.Errorf("generation produced no parser in %s", languageDir)
	}
}

// resolveGalley returns the Galley checkout to build against: the
// GALLEY_CHECKOUT when set, otherwise a shallow clone of GALLEY_REPOSITORY
// at GALLEY_TAG inside cacheDir. Mirrors bindings/rust/src/build_helper.rs.
func resolveGalley(cacheDir string) string {
	if checkout := env("GALLEY_CHECKOUT"); checkout != "" {
		if _, err := os.Stat(filepath.Join(checkout, "build.zig")); err != nil {
			fatal("GALLEY_CHECKOUT=%s is not a Galley repository checkout (no build.zig)", checkout)
		}
		return checkout
	}
	tag := defaultTag
	if value := env("GALLEY_TAG"); value != "" {
		tag = value
	}
	repository := defaultRepository
	if value := env("GALLEY_REPOSITORY"); value != "" {
		repository = value
	}
	sourceDir := filepath.Join(cacheDir, "galley-src")
	stamp := filepath.Join(cacheDir, "galley-tag")
	if previous, err := os.ReadFile(stamp); err == nil && strings.TrimSpace(string(previous)) == tag {
		if _, err := os.Stat(sourceDir); err == nil {
			return sourceDir
		}
	}
	_ = os.RemoveAll(sourceDir)
	run(exec.Command("git", "clone", "--depth", "1", "--branch", tag,
		"--single-branch", "--recurse-submodules=false", repository, sourceDir))
	if err := os.WriteFile(stamp, []byte(tag), 0o644); err != nil {
		fatal("failed to write tag stamp: %v", err)
	}
	return sourceDir
}

func main() {
	if len(os.Args) != 3 || os.Args[1] != "gen" {
		fatal("usage: galley gen <language-dir>")
	}
	languageDir := os.Args[2]
	if _, err := os.Stat(filepath.Join(languageDir, "ll.grm")); err != nil {
		fatal("%s does not contain ll.grm", languageDir)
	}

	cacheRoot, err := os.UserCacheDir()
	if err != nil {
		cacheRoot = os.TempDir()
	}
	cacheDir := filepath.Join(cacheRoot, "galley-bindings", "go")
	if err := os.MkdirAll(cacheDir, 0o755); err != nil {
		fatal("failed to create cache dir: %v", err)
	}

	galleySource := resolveGalley(cacheDir)
	cli := filepath.Join(galleySource, "zig-out", "bin", "galley")
	if _, err := os.Stat(cli); err != nil {
		build := exec.Command(zigExecutable(), "build", "-Doptimize=ReleaseFast", "install")
		build.Dir = galleySource
		run(build)
	}

	// Parser generation relies on flags introduced alongside the bindings
	// workflow; refuse with guidance when the resolved Galley predates them
	// instead of failing deep inside generation.
	help, err := exec.Command(cli, "--help").Output()
	if err != nil {
		fatal("failed to probe %s: %v", cli, err)
	}
	if !strings.Contains(string(help), "--emit-metadata") {
		fatal("the Galley at %s is too old for the bindings workflow (no --emit-metadata support); "+
			"point GALLEY_CHECKOUT at a current Galley checkout, or remove the stale copy and "+
			"update GALLEY_TAG so a fresh Galley is fetched", galleySource)
	}

	generate := exec.Command(cli, "--emit-metadata", languageDir)
	run(generate)

	// One library embeds one parser; detect which family generation
	// produced (both present is ambiguous and unsupported).
	parserSource, parserType, err := detectParser(languageDir)
	if err != nil {
		fatal("%v", err)
	}

	prefix := filepath.Join(cacheDir, "capi")
	languageAbsolute, err := filepath.Abs(languageDir)
	if err != nil {
		languageAbsolute = languageDir
	}
	consumerBuild := exec.Command(zigExecutable(), "build",
		"--build-file", filepath.Join(galleySource, "bindings", "c", "consumer", "build.zig"),
		"-Dparser-source="+filepath.Join(languageAbsolute, parserSource),
		"-Dparser-type="+parserType,
		"-Dlib-name="+libName,
		"-Doptimize=ReleaseFast",
		"--prefix", prefix,
		"install")
	consumerBuild.Dir = galleySource
	for _, optionalFile := range []struct {
		flag  string
		paths []string
	}{
		// procedures.c lives under hooks/ in the Go example because the Go
		// toolchain refuses .c files inside a package without cgo; the root
		// path stays supported for consumers whose main package imports C.
		{"-Dprocedures-zig-source=", []string{"procedures.zig"}},
		{"-Dprocedures-c-source=", []string{"hooks/procedures.c", "procedures.c"}},
		{"-Derror-messages-zig-source=", []string{
			fmt.Sprintf("%s_error_messages.zig", parserType),
		}},
	} {
		for _, relativePath := range optionalFile.paths {
			candidate := filepath.Join(languageDir, relativePath)
			if _, err := os.Stat(candidate); err != nil {
				continue
			}
			consumerBuild.Args = append(consumerBuild.Args,
				optionalFile.flag+mustAbsolute(candidate))
			break
		}
	}
	run(consumerBuild)

	emitBridge(languageAbsolute, prefix)
	fmt.Println("galley-bindings: generated galley package; import it and build as usual")
}

// emitBridge writes <language-dir>/galley/galley.go: the generated cgo
// preamble bound to this library plus the wrapper from the embedded
// template. The package name is fixed so the import path stays stable.
func emitBridge(languageDir, prefix string) {
	outDir := filepath.Join(languageDir, "galley")
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		fatal("failed to create %s: %v", outDir, err)
	}
	includeDir := filepath.Join(prefix, "include")
	libDir := filepath.Join(prefix, "lib")

	var builder strings.Builder
	builder.WriteString("// Code generated by galley-bindings gen; DO NOT EDIT.\n")
	builder.WriteString("package galley\n\n/*\n#cgo CFLAGS: -I")
	builder.WriteString(includeDir)
	builder.WriteString("\n#cgo LDFLAGS: -L")
	builder.WriteString(libDir)
	builder.WriteString(" -l" + libName + " -Wl,-rpath," + libDir)
	builder.WriteString("\n#include <stdlib.h>\n#include <galley.h>\n*/\nimport \"C\"\n\n")
	builder.WriteString(strings.TrimRight(wrapperTemplate, "\n"))
	builder.WriteString("\n")

	target := filepath.Join(outDir, "galley.go")
	formatted, err := format.Source([]byte(builder.String()))
	if err != nil {
		fatal("generated bridge does not compile as Go source: %v", err)
	}
	if err := os.WriteFile(target, formatted, 0o644); err != nil {
		fatal("failed to write %s: %v", target, err)
	}
}
