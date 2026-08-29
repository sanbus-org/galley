// Command galley generates and builds a Galley parser as a shared library
// for the Go bindings, then emits the cgo bridge package into the language
// directory.
//
// Usage:
//
//	go run github.com/sanbus-org/galley/bindings/go/cmd/galley gen <language-dir>
//
// The language dir must contain ll.grm (generation options live in config.zig)
// and may contain hooks/procedures.go (procedure hook implementations in
// Go, called through generated registration slots) and
// ll_error_messages.zig (custom syntax-error message hooks), mirroring the
// C, C++, Rust, and Python consumers.
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
	"regexp"
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

	// Procedure hooks are written in Go: hooks/procedures.go declares the
	// exported entry points compiled into the consumer binary itself. This
	// tool never ships Go code inside the shared library — embedding a Go
	// runtime there crashes any Go program that loads it. Instead the
	// library receives a generated Zig shim module (one nullable slot per
	// grammar hook plus an installer), and the bridge package registers
	// the host's exported hook addresses into those slots at package init;
	// the parser then calls through the slots with no runtime crossing
	// beyond the unavoidable C-to-Go transition inside each exported
	// function.
	prefix := filepath.Join(cacheDir, "capi")
	languageAbsolute, err := filepath.Abs(languageDir)
	if err != nil {
		languageAbsolute = languageDir
	}
	proceduresGo := filepath.Join(languageDir, "hooks", "procedures.go")

	var userHooks []string
	shimPath := filepath.Join(languageDir, "procedures_go.zig")
	bindingPath := filepath.Join(languageDir, "galley", "hooks_binding.go")
	if err := emitProcedureShim(filepath.Join(languageDir, "procedures.zig"), shimPath); err != nil {
		fatal("%v", err)
	}
	if _, err := os.Stat(proceduresGo); err == nil {
		userHooks, err = parseExportedFunctions(proceduresGo)
		if err != nil {
			fatal("%v", err)
		}
	}
	if err := emitHookBinding(bindingPath, userHooks); err != nil {
		fatal("%v", err)
	}
	procedureZigSource := mustAbsolute(shimPath)
	hooksPresent := userHooks != nil

	consumerBuild := exec.Command(zigExecutable(), "build",
		"--build-file", filepath.Join(galleySource, "bindings", "c", "consumer", "build.zig"),
		"-Dparser-source="+filepath.Join(languageAbsolute, parserSource),
		"-Dparser-type="+parserType,
		"-Dlib-name="+libName,
		"-Doptimize=ReleaseFast",
		"--prefix", prefix,
		"install")
	consumerBuild.Dir = galleySource
	if procedureZigSource != "" {
		consumerBuild.Args = append(consumerBuild.Args,
			"-Dprocedures-zig-source="+procedureZigSource)
	}
	// config.zig and {ll,lr}_error_messages.zig next to the parser are
	// inferred by the consumer build when omitted, so no explicit flags
	// are needed for standard layouts.
	run(consumerBuild)

	emitBridge(languageAbsolute, prefix, hooksPresent)
	fmt.Println("galley-bindings: generated galley package; import it and build as usual")
}

// modulePath reads the `module` line from the consumer's go.mod, which the
// bridge needs to blank-import the hooks package so its //exported symbols
// are linked into the binary.
func modulePath(languageDir string) string {
	source, err := os.ReadFile(filepath.Join(languageDir, "go.mod"))
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(source), "\n") {
		if fields := strings.Fields(line); len(fields) == 2 && fields[0] == "module" {
			return fields[1]
		}
	}
	return ""
}

// parseExportedFunctions returns the //exported Go function names declared
// in the consumer's hooks/procedures.go, in declaration order.
func parseExportedFunctions(path string) ([]string, error) {
	source, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	pattern := regexp.MustCompile(`(?m)^//export\s+(\w+)`)
	var names []string
	seen := map[string]bool{}
	for _, match := range pattern.FindAllStringSubmatch(string(source), -1) {
		name := match[1]
		if !seen[name] {
			seen[name] = true
			names = append(names, name)
		}
	}
	return names, nil
}

// emitProcedureShim transforms the generated procedures module (whose decls
// are `pub extern fn` symbols that would otherwise have to be linked into
// the shared library) into an equivalent module whose hooks dispatch
// through nullable function-pointer slots filled at runtime by the host
// binary. Slots that were never registered stay silent no-ops.
func emitProcedureShim(templatePath, outputPath string) error {
	template, err := os.ReadFile(templatePath)
	if err != nil {
		return err
	}
	pattern := regexp.MustCompile(`pub extern fn (\w+)\((.*)\) (\w+);`)
	type hook struct{ name, parameters, result string }
	var hooks []hook
	var passthrough []string
	for _, line := range strings.Split(string(template), "\n") {
		if match := pattern.FindStringSubmatch(line); match != nil {
			hooks = append(hooks, hook{name: match[1], parameters: match[2], result: match[3]})
			continue
		}
		if strings.HasPrefix(line, "pub extern") || strings.HasPrefix(line, "// Auto-generated") ||
			strings.HasPrefix(line, "// Implement these functions") {
			continue
		}
		passthrough = append(passthrough, line)
	}

	var builder strings.Builder
	builder.WriteString("// Generated by galley-bindings gen; DO NOT EDIT.\n")
	builder.WriteString("// Procedure hooks dispatch through slots registered by the host\n")
	builder.WriteString("// binary's galley/hooks_binding.go; unregistered slots are no-ops.\n")
	builder.WriteString("const std = @import(\"std\");\n")
	for _, line := range passthrough {
		if strings.TrimSpace(line) == "" && len(builder.String()) > 0 {
			// keep blank separators as-is
		}
		builder.WriteString(line)
		builder.WriteString("\n")
	}
	builder.WriteString("\n")
	for _, h := range hooks {
		fmt.Fprintf(&builder,
			"var target_%[1]s: ?*const fn (?*anyopaque) callconv(.c) void = null;\n"+
				"pub fn %[1]s(args: %[2]s) %[3]s {\n"+
				"    if (target_%[1]s) |installed| installed(@ptrCast(args));\n"+
				"}\n\n",
			h.name, h.parameters, h.result)
	}
	builder.WriteString("const procedure_slots = [_]struct { name: []const u8, slot: *?*const fn (?*anyopaque) callconv(.c) void }{\n")
	for _, h := range hooks {
		fmt.Fprintf(&builder, "    .{ .name = \"%[1]s\", .slot = &target_%[1]s },\n", h.name)
	}
	builder.WriteString("};\n\n")
	builder.WriteString(
		"/// Registers the host implementation of one grammar hook. Returns 1\n" +
			"/// when the name matches a slot, 0 otherwise.\n" +
			"export fn galley_install_procedure_target(\n" +
			"    name_ptr: [*]const u8,\n" +
			"    name_len: usize,\n" +
			"    target: *const fn (?*anyopaque) callconv(.c) void,\n" +
			") c_int {\n" +
			"    const name = name_ptr[0..name_len];\n" +
			"    inline for (&procedure_slots) |*slot| {\n" +
			"        if (std.mem.eql(u8, slot.name, name)) {\n" +
			"            slot.slot.* = target;\n" +
			"            return 1;\n" +
			"        }\n" +
			"    }\n" +
			"    return 0;\n" +
			"}\n")
	return os.WriteFile(outputPath, []byte(builder.String()), 0o644)
}

// emitHookBinding writes <language-dir>/galley/hooks_binding.go: package-init
// code that hands each //exported hook address from hooks/procedures.go to
// the shared library's installer.
func emitHookBinding(outputPath string, userHooks []string) error {
	if err := os.MkdirAll(filepath.Dir(outputPath), 0o755); err != nil {
		return err
	}
	var builder strings.Builder
	builder.WriteString("// Code generated by galley-bindings gen; DO NOT EDIT.\n")
	builder.WriteString("// Registers the exported hook addresses from hooks/procedures.go into\n")
	builder.WriteString("// the parser library's procedure slots at package init.\n")
	builder.WriteString("package galley\n\n/*\n#include <stdlib.h>\n")
	for _, name := range userHooks {
		fmt.Fprintf(&builder, "void %[1]s(void*);\nstatic void* galley_addr_%[1]s(void) { return (void*)%[1]s; }\n", name)
	}
	builder.WriteString("extern int galley_install_procedure_target(const char*, size_t, void*);\n*/\n")
	builder.WriteString("import \"C\"\nimport \"fmt\"\nimport \"os\"\nimport \"unsafe\"\n\n")
	builder.WriteString("func init() {\n\ttargets := [...]struct {\n\t\tname string\n\t\taddress unsafe.Pointer\n\t}{\n")
	for _, name := range userHooks {
		fmt.Fprintf(&builder, "\t\t{%[1]q, C.galley_addr_%[1]s()},\n", name)
	}
	builder.WriteString("\t}\n")
	builder.WriteString("\tfor _, target := range targets {\n" +
		"\t\tcName := C.CString(target.name)\n" +
		"\t\tinstalled := C.galley_install_procedure_target(cName, C.size_t(len(target.name)), target.address)\n" +
		"\t\tC.free(unsafe.Pointer(cName))\n" +
		"\t\tif installed == 0 {\n" +
		"\t\t\tfmt.Fprintln(os.Stderr, \"galley-bindings: grammar declares no hook named\", target.name)\n" +
		"\t\t}\n" +
		"\t}\n}\n")
	formatted, err := format.Source([]byte(builder.String()))
	if err != nil {
		diagnosticPath := outputPath + ".unformatted"
		os.WriteFile(diagnosticPath, []byte(builder.String()), 0o644)
		return fmt.Errorf("generated %s does not compile as Go source: %w (raw source saved to %s)", filepath.Base(outputPath), err, diagnosticPath)
	}
	return os.WriteFile(outputPath, formatted, 0o644)
}

// emitBridge writes <language-dir>/galley/galley.go: the generated cgo
// preamble bound to this library plus the wrapper from the embedded
// template. The package name is fixed so the import path stays stable.
// When the consumer declares Go procedure hooks, a blank import of the
// hooks package keeps its //exported symbols in the binary for the
// generated hooks_binding.go registration to reference.
func emitBridge(languageDir, prefix string, hooksPresent bool) {
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
	if hooksPresent {
		if module := modulePath(languageDir); module != "" {
			fmt.Fprintf(&builder, "import _ %q\n\n", module+"/hooks")
		} else {
			fatal("hooks/procedures.go requires a go.mod with a module line so the bridge can import the hooks package")
		}
	}
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
