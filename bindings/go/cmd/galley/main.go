// Command galley generates and builds a Galley parser as a shared library
// for the Go bindings, then emits the cgo bridge package into the language
// directory.
//
// Usage:
//
//	go run github.com/sanbus-org/galley/bindings/go/cmd/galley gen <language-dir>
//
// The language dir must contain ll.grm (generation options live in config.zig)
// and may contain procedures.go (procedure hook implementations in Go,
// called through generated registration slots) and ll_error_messages.zig
// (custom syntax-error message hooks), mirroring the C, C++, Rust, Python,
// and TypeScript consumers.
//
// Environment overrides: GALLEY_CHECKOUT (required: existing Galley working
// tree), ZIG_EXECUTABLE (default zig). To fetch a checkout for convenience,
// use examples/scripts/fetch-galley.sh — that cache is an examples-only
// convenience, not part of the bindings.
package main

import (
	"encoding/json"
	"fmt"
	"go/format"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"

	galleybindings "github.com/sanbus-org/galley/bindings/go"
)

var wrapperTemplate = galleybindings.WrapperTemplate

const (
	libName = "galley-go"
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

// resolveGalley returns the Galley checkout from GALLEY_CHECKOUT, which is
// required. Fetching a checkout into the system cache is an examples-only
// convenience (examples/scripts/fetch-galley.sh), not part of the bindings.
func resolveGalley() string {
	if checkout := env("GALLEY_CHECKOUT"); checkout != "" {
		if _, err := os.Stat(filepath.Join(checkout, "build.zig")); err != nil {
			fatal("GALLEY_CHECKOUT=%s is not a Galley repository checkout (no build.zig)", checkout)
		}
		return checkout
	}
	fatal("GALLEY_CHECKOUT is not set; point it at a Galley checkout (examples/scripts/fetch-galley.sh can fetch one)")
	return ""
}

func libraryFileName() string {
	if runtime.GOOS == "darwin" {
		return "lib" + libName + ".dylib"
	}
	if runtime.GOOS == "windows" {
		return libName + ".dll"
	}
	return "lib" + libName + ".so"
}

func main() {
	if len(os.Args) != 3 || os.Args[1] != "gen" {
		fatal("usage: galley gen <language-dir>")
	}
	languageDir := os.Args[2]
	if _, err := os.Stat(filepath.Join(languageDir, "ll.grm")); err != nil {
		fatal("%s does not contain ll.grm", languageDir)
	}

	galleySource := resolveGalley()
	cli := filepath.Join(galleySource, "zig-out", "bin", "galley")
	if _, err := os.Stat(cli); err != nil {
		build := exec.Command(zigExecutable(), "build", "-Doptimize=ReleaseFast", "install")
		build.Dir = galleySource
		run(build)
	}

	// Parser generation relies on flags introduced alongside the bindings
	// workflow; refuse with guidance when the resolved Galley predates them.
	help, err := exec.Command(cli, "--help").Output()
	if err != nil {
		fatal("failed to probe %s: %v", cli, err)
	}
	if !strings.Contains(string(help), "--emit-metadata") {
		fatal("the Galley at %s is too old for the bindings workflow (no --emit-metadata support); "+
			"point GALLEY_CHECKOUT at a current Galley checkout", galleySource)
	}

	generate := exec.Command(cli, "--emit-metadata", languageDir)
	run(generate)

	// One library embeds one parser; the consumer build locates the file
	// generation produced from -Dlanguage-dir and infers the family from
	// the filename.
	// Procedure hooks are written in Go: procedures.go next to the grammar
	// declares the exported entry points compiled into the consumer binary
	// itself. This tool never ships Go code inside the shared library —
	// embedding a Go runtime there crashes any Go program that loads it.
	// Instead the library receives a generated Zig shim module (one
	// nullable slot per grammar hook plus an installer), and the bridge
	// package registers the host's exported hook addresses into those
	// slots at package init; the parser then calls through the slots with
	// no runtime crossing beyond the unavoidable C-to-Go transition
	// inside each exported function.
	languageAbsolute, err := filepath.Abs(languageDir)
	if err != nil {
		languageAbsolute = languageDir
	}
	proceduresGo := filepath.Join(languageDir, "procedures.go")

	var userHooks []string
	shimPath := filepath.Join(languageDir, "procedures_go.zig")
	bindingPath := filepath.Join(languageDir, "galley", "hooks_binding.go")
	procedureHooks, err := readProcedureHooks(languageDir)
	if err != nil {
		fatal("%v", err)
	}
	if err := emitProcedureShim(procedureHooks, shimPath); err != nil {
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

	consumerBuild := exec.Command(zigExecutable(), "build",
		"--build-file", filepath.Join(galleySource, "bindings", "c", "consumer", "build.zig"),
		"-Dlanguage-dir="+languageAbsolute,
		"-Dlib-name="+libName,
		"-Doutput="+libraryFileName(),
		"-Doptimize=ReleaseFast",
		"--prefix", languageAbsolute,
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

	emitBridge(languageAbsolute, galleySource)
	fmt.Println("galley-bindings: generated galley package; import it and build as usual")
}

// parseExportedFunctions returns the //exported Go function names declared
// in the consumer's procedures.go, in declaration order.
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

// readProcedureHooks returns the generator's hook list from metadata.json,
// written alongside procedures.zig. The generator owns the hook list; this
// tool renders it.
func readProcedureHooks(languageDir string) ([]string, error) {
	raw, err := os.ReadFile(filepath.Join(languageDir, "metadata.json"))
	if err != nil {
		return nil, err
	}
	var metadata struct {
		Procedures []string `json:"procedures"`
	}
	if err := json.Unmarshal(raw, &metadata); err != nil {
		return nil, fmt.Errorf("failed to parse metadata.json: %w", err)
	}
	if len(metadata.Procedures) == 0 {
		return nil, fmt.Errorf("metadata.json has no procedure hook list; update the Galley checkout")
	}
	return metadata.Procedures, nil
}

// emitProcedureShim renders a dispatch module from the generator's hook
// list (metadata.json): each hook gets a nullable function-pointer slot
// filled at runtime by the host binary through
// galley_install_procedure_target. Slots that were never registered stay
// silent no-ops. The generator owns the hook list; this tool renders it.
func emitProcedureShim(hooks []string, outputPath string) error {
	const parameters = "*root.data_structures.ProcedureArguments"
	const result = "void"

	var builder strings.Builder
	builder.WriteString("// Generated by galley-bindings gen; DO NOT EDIT.\n")
	builder.WriteString("// Procedure hooks dispatch through slots registered by the host\n")
	builder.WriteString("// binary's galley/hooks_binding.go; unregistered slots are no-ops.\n")
	builder.WriteString("const std = @import(\"std\");\n")
	builder.WriteString("const root = @import(\"galley\");\n")
	builder.WriteString("pub const Payload = struct {};\n")
	builder.WriteString("\n")
	for _, name := range hooks {
		fmt.Fprintf(&builder,
			"var target_%[1]s: ?*const fn (?*anyopaque) callconv(.c) void = null;\n"+
				"pub fn %[1]s(args: %[2]s) %[3]s {\n"+
				"    if (target_%[1]s) |installed| installed(@ptrCast(args));\n"+
				"}\n\n",
			name, parameters, result)
	}
	builder.WriteString("const procedure_slots = [_]struct { name: []const u8, slot: *?*const fn (?*anyopaque) callconv(.c) void }{\n")
	for _, name := range hooks {
		fmt.Fprintf(&builder, "    .{ .name = \"%[1]s\", .slot = &target_%[1]s },\n", name)
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
// code that hands each //exported hook address from procedures.go to
// the shared library's installer.
func emitHookBinding(outputPath string, userHooks []string) error {
	if err := os.MkdirAll(filepath.Dir(outputPath), 0o755); err != nil {
		return err
	}
	if len(userHooks) == 0 {
		// No host hooks to register. Keep the file so package galley is
		// complete, but do not cgo-link galley_install_procedure_target:
		// a procedures=false library does not export that symbol.
		return os.WriteFile(outputPath, []byte("// Code generated by galley-bindings gen; DO NOT EDIT.\npackage galley\n"), 0o644)
	}
	var builder strings.Builder
	builder.WriteString("// Code generated by galley-bindings gen; DO NOT EDIT.\n")
	builder.WriteString("// Registers the exported hook addresses from procedures.go into\n")
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
// Procedure hooks live in the consumer's procedures.go and import this
// package, so this file must not import them (that would cycle). When
// procedures.go is in the same package as main, its //exported symbols
// are linked automatically; a separate package must be imported from
// main so hooks_binding.go can register the addresses.
func emitBridge(languageDir, galleySource string) {
	outDir := filepath.Join(languageDir, "galley")
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		fatal("failed to create %s: %v", outDir, err)
	}
	includeDir := filepath.Join(galleySource, "bindings", "c")
	libDir := languageDir

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
