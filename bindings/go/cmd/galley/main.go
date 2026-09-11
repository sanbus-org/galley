// Command galley generates and builds a Galley parser as a shared library
// for the Go bindings, then emits the cgo bridge package into the language
// directory.
//
// Usage:
//
//	galley gen <language-dir> [generator flags...]
//
// Generator flags forward verbatim to the generator ahead of
// --emit-metadata: this tool forwards every flag it does not own and the
// binary owns its surface (unknown flags die there with `unknown
// argument`), so new generator flags work with no wrapper changes. Only
// --parser-type's value-shape is known here (--parser-type lr and
// --parser-type=lr both forward). --watch is refused loudly: forwarding
// it would park the build inside the generator's watch loop and never
// compile.
//
// No checkout is needed: released modules download the version-pinned
// generator CLI and compile kit from GitHub releases into the user cache
// on first use (progress and destination shown, checksums verified, exact
// version only). Contributors running from a checkout fall back to
// GALLEY_CHECKOUT pointing at one.
//
// The language dir must contain ll.grm (generation options live in config.zig)
// and may contain procedures.go (procedure hook implementations in Go,
// called through generated registration slots) and ll_error_messages.zig
// (custom syntax-error message hooks), mirroring the C, C++, Rust, Python,
// and TypeScript consumers.
//
// Environment overrides: GALLEY_CLI (explicit generator binary),
// GALLEY_CHECKOUT (contributor fallback: existing Galley working tree),
// ZIG_EXECUTABLE (default zig), GALLEY_ARTIFACT_MIRROR (release download
// root override, announced when used), GALLEY_ARTIFACT_VERSION (artifact
// version pin override, announced when used). To fetch a checkout for
// convenience, use examples/scripts/fetch-galley.sh — that cache is an
// examples-only convenience, not part of the bindings.
package main

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"go/format"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"runtime/debug"
	"strings"

	galleybindings "github.com/sanbus-org/galley/bindings/go"
)

var wrapperTemplate = galleybindings.WrapperTemplate

const (
	libName = "galley-go"
)

// parserTypeFromFlags returns the --parser-type selection inside forwarded
// generator flags, if any. Last wins on both spellings (--parser-type lr,
// --parser-type=lr), mirroring the binary. Anything else (including a bad
// value) is the generator's to reject — this only answers "must ll.grm
// exist?". --parser-type is the one piece of generator surface this tool
// knows: its value-shape is needed to find the grammar file. Every other
// flag forwards untouched and the binary owns it.
func parserTypeFromFlags(flags []string) string {
	parserType := ""
	for i := 0; i < len(flags); i++ {
		flag := flags[i]
		if flag == "--parser-type" {
			i++
			if i < len(flags) {
				parserType = flags[i]
			}
		} else if value, ok := strings.CutPrefix(flag, "--parser-type="); ok {
			parserType = value
		}
	}
	return parserType
}

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

// resolveCheckout returns GALLEY_CHECKOUT when it names an existing
// Galley working tree, else "". Fetching a checkout into the system cache
// is an examples-only convenience (examples/scripts/fetch-galley.sh), not
// part of the bindings.
func resolveCheckout() string {
	checkout := env("GALLEY_CHECKOUT")
	if checkout == "" {
		return ""
	}
	if _, err := os.Stat(filepath.Join(checkout, "build.zig")); err != nil {
		fatal("GALLEY_CHECKOUT=%s is not a Galley repository checkout (no build.zig)", checkout)
	}
	return checkout
}

// resolveGeneratorCli names the generator binary without building
// anything. Explicit GALLEY_CLI wins; then an explicit GALLEY_CHECKOUT
// bootstrap; then a version-pinned download into the user cache (release
// builds only — first use shows progress and the destination). Anything
// else fails loudly naming every leg.
func resolveGeneratorCli() string {
	if explicit := env("GALLEY_CLI"); explicit != "" {
		if _, err := os.Stat(explicit); err != nil {
			fatal("GALLEY_CLI=%s does not exist", explicit)
		}
		return explicit
	}
	if checkout := resolveCheckout(); checkout != "" {
		cli := filepath.Join(checkout, "zig-out", "bin", "galley")
		if _, err := os.Stat(cli); err != nil {
			build := exec.Command(zigExecutable(), "build", "-Doptimize=ReleaseFast", "install")
			build.Dir = checkout
			run(build)
		}
		return cli
	}
	tag := moduleReleaseTag()
	if tag == "" {
		fatal("no generator CLI found (tried GALLEY_CLI, then a GALLEY_CHECKOUT bootstrap). " +
			"To generate with no toolchain, use a released galley module (its exact version downloads the CLI on first use). " +
			"To bootstrap from source, set GALLEY_CHECKOUT at a Galley checkout with zig installed " +
			"(examples/scripts/fetch-galley.sh can fetch one).")
	}
	asset, err := generatorAssetName(runtime.GOOS, runtime.GOARCH)
	if err != nil {
		fatal("%v (tried GALLEY_CLI, then a GALLEY_CHECKOUT bootstrap, then a version-pinned download of %s)", err, tag)
	}
	return ensureArtifact(tag, asset)
}

// resolveCompileInputs locates the consumer build file and the source
// root its `@import("galley")` resolves against. An explicit
// GALLEY_CHECKOUT wins; then the version-pinned kit in the user cache
// (release builds only). Both legs run the same consumer build with the
// same flags; only the inputs differ. Anything else fails loudly.
func resolveCompileInputs() (buildFile, sourceRoot string) {
	if checkout := resolveCheckout(); checkout != "" {
		return filepath.Join(checkout, "bindings", "c", "consumer", "build.zig"), checkout
	}
	tag := moduleReleaseTag()
	if tag == "" {
		fatal("need compile inputs (tried GALLEY_CHECKOUT). " +
			"To compile with no checkout, use a released galley module (its exact version downloads the kit on first use). " +
			"To build from source, set GALLEY_CHECKOUT at a Galley checkout " +
			"(examples/scripts/fetch-galley.sh can fetch one).")
	}
	kitDir := ensureKit(tag)
	return filepath.Join(kitDir, "build.zig"), filepath.Join(kitDir, "sources")
}

// artifactBaseURL is the release download root. GALLEY_ARTIFACT_MIRROR
// overrides it (test and air-gap escape hatch); the override is explicit
// and announced once when first used.
var cachedArtifactBaseURL = ""

func artifactBaseURL() string {
	if cachedArtifactBaseURL != "" {
		return cachedArtifactBaseURL
	}
	if mirror := env("GALLEY_ARTIFACT_MIRROR"); mirror != "" {
		fmt.Fprintf(os.Stderr, "galley-bindings: using artifact mirror %s\n", mirror)
		cachedArtifactBaseURL = strings.TrimSuffix(mirror, "/")
	} else {
		cachedArtifactBaseURL = "https://github.com/sanbus-org/galley/releases/download"
	}
	return cachedArtifactBaseURL
}

// releaseTagForVersion maps a module version to its product release tag,
// or "" when the version is not a clean release (checkout builds report
// "(devel)", contributor snapshots report pseudo-versions). Only clean
// releases download artifacts: the exact version is the skew stamp, and
// anything else resolves through GALLEY_CHECKOUT or fails loudly.
func releaseTagForVersion(version string) string {
	matched, _ := regexp.MatchString(`^v[0-9]+\.[0-9]+\.[0-9]+$`, version)
	if !matched {
		return ""
	}
	return version
}

// moduleReleaseTag is the running module's release tag, or "" in
// contributor mode. GALLEY_ARTIFACT_VERSION pins it explicitly (test and
// air-gap escape hatch); the pin is announced once, and skew from it is
// the user's responsibility.
var cachedModuleReleaseTag = ""
var moduleReleaseTagResolved = false

func moduleReleaseTag() string {
	if !moduleReleaseTagResolved {
		moduleReleaseTagResolved = true
		if pinned := env("GALLEY_ARTIFACT_VERSION"); pinned != "" {
			fmt.Fprintf(os.Stderr, "galley-bindings: GALLEY_ARTIFACT_VERSION pins artifacts at %s (module reports %s)\n", pinned, moduleVersion())
			cachedModuleReleaseTag = pinned
		} else {
			cachedModuleReleaseTag = releaseTagForVersion(moduleVersion())
		}
	}
	return cachedModuleReleaseTag
}

func moduleVersion() string {
	if info, ok := debug.ReadBuildInfo(); ok && info.Main.Version != "" {
		return info.Main.Version
	}
	return "(devel)"
}

// generatorAssetName is the release asset holding the generator CLI for a
// platform. riscv64 is deliberately skipped (no portable static target);
// 32-bit and BSD platforms fail loudly through the error.
func generatorAssetName(goos, goarch string) (string, error) {
	switch goos + "/" + goarch {
	case "darwin/arm64":
		return "galley-darwin-arm64", nil
	case "darwin/amd64":
		return "galley-darwin-x64", nil
	case "linux/amd64":
		return "galley-linux-x64", nil
	case "linux/arm64":
		return "galley-linux-arm64", nil
	case "windows/amd64":
		return "galley-win32-x64.exe", nil
	case "windows/arm64":
		return "galley-win32-arm64.exe", nil
	}
	return "", fmt.Errorf("no prebuilt generator exists for %s:%s", goos, goarch)
}

const kitAssetName = "compile-kit.tar.gz"
const sumsAssetName = "sha256sums.txt"

// artifactCacheDir is where version-pinned downloads live. The version is
// part of the path, so two releases never share bytes.
func artifactCacheDir(tag string) string {
	cache, err := os.UserCacheDir()
	if err != nil || cache == "" {
		fatal("cannot locate the user cache directory: %v (set GALLEY_CLI and GALLEY_CHECKOUT to bypass downloads)", err)
	}
	return filepath.Join(cache, "galley", tag)
}

func artifactURL(tag, asset string) string {
	return artifactBaseURL() + "/" + tag + "/" + asset
}

func parseSums(text string) map[string]string {
	sums := map[string]string{}
	for _, line := range strings.Split(text, "\n") {
		fields := strings.Fields(line)
		if len(fields) != 2 {
			continue
		}
		// sha256sum marks binary-mode reads with a leading "*".
		sums[strings.TrimPrefix(fields[1], "*")] = fields[0]
	}
	return sums
}

func fetchURL(url string) *http.Response {
	response, err := http.Get(url)
	if err != nil {
		fatal("failed to download %s: %v", url, err)
	}
	if response.StatusCode != http.StatusOK {
		response.Body.Close()
		fatal("failed to download %s: HTTP %s (is %s released with artifacts?)", url, response.Status, artifactBaseURL())
	}
	return response
}

// downloadFile streams url to a unique temp file beside dest, showing a
// progress line on stderr, and renames it into place. Callers verify
// checksums after; concurrent first runs both download and the last
// rename wins, which is safe because verified bytes are identical.
func downloadFile(url, dest string) {
	fmt.Fprintf(os.Stderr, "galley-bindings: downloading %s\n  saving to %s\n", url, dest)
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		fatal("cannot create %s: %v", filepath.Dir(dest), err)
	}
	body := fetchURL(url)
	defer body.Body.Close()
	tmp, err := os.CreateTemp(filepath.Dir(dest), ".download-*")
	if err != nil {
		fatal("cannot stage download beside %s: %v", dest, err)
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	total := body.ContentLength
	var done int64
	chunk := make([]byte, 1<<20)
	for {
		n, err := body.Body.Read(chunk)
		if n > 0 {
			done += int64(n)
			if _, werr := tmp.Write(chunk[:n]); werr != nil {
				tmp.Close()
				fatal("failed to write %s: %v", tmpName, werr)
			}
			if total > 0 {
				fmt.Fprintf(os.Stderr, "\r  %d/%d bytes (%d%%)", done, total, done*100/total)
			} else {
				fmt.Fprintf(os.Stderr, "\r  %d bytes", done)
			}
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			tmp.Close()
			fatal("failed to download %s: %v", url, err)
		}
	}
	tmp.Close()
	fmt.Fprintf(os.Stderr, "\nsaved %s (%d bytes)\n", dest, done)
	if err := os.Rename(tmpName, dest); err != nil {
		fatal("cannot move %s into place: %v", tmpName, err)
	}
	if !strings.HasSuffix(dest, ".exe") {
		os.Chmod(dest, 0o755)
	}
}

func verifyChecksum(path, sumsText string) {
	want, ok := parseSums(sumsText)[filepath.Base(path)]
	if !ok {
		fatal("no checksum for %s in %s; refusing to use it", filepath.Base(path), sumsAssetName)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		fatal("cannot read %s: %v", path, err)
	}
	sum := sha256.Sum256(data)
	if hex.EncodeToString(sum[:]) != want {
		os.Remove(path)
		fatal("checksum mismatch for %s (deleted); refusing to use it", path)
	}
}

// ensureArtifact returns the version-pinned file for asset, downloading it
// on first use. Every use (cached or fresh) is checksum-verified against
// the release's sums, so the cache is tamper-evident; warm hits read the
// cached sums and need no network.
func ensureArtifact(tag, asset string) string {
	dir := artifactCacheDir(tag)
	dest := filepath.Join(dir, asset)
	sumsDest := filepath.Join(dir, sumsAssetName)
	if _, err := os.Stat(dest); err == nil {
		sums, err := os.ReadFile(sumsDest)
		if err != nil {
			fatal("cached %s has no checksums; delete %s and retry", dest, dir)
		}
		verifyChecksum(dest, string(sums))
		return dest
	}
	sumsResponse := fetchURL(artifactURL(tag, sumsAssetName))
	sumsText, err := io.ReadAll(sumsResponse.Body)
	sumsResponse.Body.Close()
	if err != nil {
		fatal("failed to read %s: %v", sumsAssetName, err)
	}
	downloadFile(artifactURL(tag, asset), dest)
	if err := os.WriteFile(sumsDest, sumsText, 0o644); err != nil {
		fatal("cannot cache %s: %v", sumsAssetName, err)
	}
	verifyChecksum(dest, string(sumsText))
	return dest
}

// ensureKit unpacks the version-pinned compile kit on first use and
// returns its directory (holding build.zig over sources/, exactly like
// the other bindings' kit leg).
func ensureKit(tag string) string {
	dir := artifactCacheDir(tag)
	kitDir := filepath.Join(dir, "compile-kit")
	if _, err := os.Stat(filepath.Join(kitDir, "build.zig")); err == nil {
		return kitDir
	}
	archive := ensureArtifact(tag, kitAssetName)
	fmt.Fprintf(os.Stderr, "galley-bindings: unpacking %s\n  to %s\n", archive, kitDir)
	file, err := os.Open(archive)
	if err != nil {
		fatal("cannot open %s: %v", archive, err)
	}
	defer file.Close()
	uncompressed, err := gzip.NewReader(file)
	if err != nil {
		fatal("cannot decompress %s: %v", archive, err)
	}
	defer uncompressed.Close()
	staging, err := os.MkdirTemp(dir, ".kit-*")
	if err != nil {
		fatal("cannot stage kit unpacking in %s: %v", dir, err)
	}
	defer os.RemoveAll(staging)
	reader := tar.NewReader(uncompressed)
	for {
		header, err := reader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			fatal("cannot unpack %s: %v", archive, err)
		}
		target := filepath.Join(staging, filepath.FromSlash(header.Name))
		if !strings.HasPrefix(target, staging+string(os.PathSeparator)) {
			fatal("refusing to unpack %s outside the kit directory", header.Name)
		}
		switch header.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0o755); err != nil {
				fatal("cannot unpack %s: %v", archive, err)
			}
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				fatal("cannot unpack %s: %v", archive, err)
			}
			out, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
			if err != nil {
				fatal("cannot unpack %s: %v", archive, err)
			}
			if _, err := io.Copy(out, reader); err != nil {
				out.Close()
				fatal("cannot unpack %s: %v", archive, err)
			}
			out.Close()
		}
	}
	if err := os.Rename(filepath.Join(staging, "compile-kit"), kitDir); err != nil {
		fatal("cannot move unpacked kit into place: %v", err)
	}
	return kitDir
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
	const usage = "usage: galley gen <language-dir> [generator flags...]"
	if len(os.Args) < 3 || os.Args[1] != "gen" {
		fatal("%s", usage)
	}
	languageDir := os.Args[2]
	var generatorFlags []string
	for i := 3; i < len(os.Args); i++ {
		flag := os.Args[i]
		if flag == "-h" || flag == "--help" {
			fmt.Println(usage)
			os.Exit(0)
		}
		if flag == "--watch" {
			fatal("--watch needs its own entry (not yet implemented); this build runs the generator once")
		}
		if flag == "--parser-type" {
			i++
			if i >= len(os.Args) {
				fatal("--parser-type needs ll or lr; %s", usage)
			}
			generatorFlags = append(generatorFlags, flag, os.Args[i])
		} else if strings.HasPrefix(flag, "-") {
			generatorFlags = append(generatorFlags, flag)
		} else {
			fatal("unexpected positional argument %s; %s", flag, usage)
		}
	}
	// Single-parser generation needs only its own grammar: --parser-type
	// lr runs against lr.grm alone. Anything else (including a bad value)
	// is the generator's to reject.
	if parserTypeFromFlags(generatorFlags) != "lr" {
		if _, err := os.Stat(filepath.Join(languageDir, "ll.grm")); err != nil {
			fatal("%s does not contain ll.grm", languageDir)
		}
	}

	// The gate owns all build semantics: generation resolves through
	// the generator CLI, compiling through the compile inputs. Both
	// consumer-build legs run the same build with the same flags; only
	// the inputs differ.
	cli := resolveGeneratorCli()
	buildFile, sourceRoot := resolveCompileInputs()

	// Parser generation relies on flags introduced alongside the bindings
	// workflow; refuse with guidance when the resolved generator predates
	// them instead of failing deep inside generation.
	help, err := exec.Command(cli, "--help").Output()
	if err != nil {
		fatal("failed to probe %s: %v", cli, err)
	}
	if !strings.Contains(string(help), "--emit-metadata") {
		fatal("the generator at %s is too old for the bindings workflow (no --emit-metadata support); "+
			"update the galley module", cli)
	}

	generateArgs := append(append([]string{}, generatorFlags...), "--emit-metadata", languageDir)
	generate := exec.Command(cli, generateArgs...)
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
		"--build-file", buildFile,
		"-Dlanguage-dir="+languageAbsolute,
		"-Dlib-name="+libName,
		"-Doutput="+libraryFileName(),
		"-Doptimize=ReleaseFast",
		"--prefix", languageAbsolute,
		"install")
	consumerBuild.Dir = languageAbsolute
	if procedureZigSource != "" {
		consumerBuild.Args = append(consumerBuild.Args,
			"-Dprocedures-zig-source="+procedureZigSource)
	}
	// config.zig and {ll,lr}_error_messages.zig next to the parser are
	// inferred by the consumer build when omitted, so no explicit flags
	// are needed for standard layouts.
	run(consumerBuild)

	emitBridge(languageAbsolute, sourceRoot)
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
