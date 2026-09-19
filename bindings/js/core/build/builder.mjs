#!/usr/bin/env node
/**
 * Shared parser-artifact builder for the Galley JavaScript bindings.
 *
 * Single gate behind every JavaScript build entry: `galley build` in the
 * universal package, plus `@sanbus/galley-node`, `@sanbus/galley-bun`,
 * `@sanbus/galley-wasm`, and the Deno `build.ts`. Callers pass targeting
 * information (library name, wasm or native, platform, install layout);
 * the gate owns everything else — checkout resolution, CLI bootstrap,
 * parser generation, procedure-shim selection, and the consumer `zig
 * build` invocation. No caller builds consumer arguments or picks shim
 * emitters directly.
 *
 * The language directory must contain `ll.grm` (or `lr.grm` under
 * `--parser-type lr`) and may contain
 * `config.zig`, procedures, and `ll_error_messages.zig`, mirroring the
 * other bindings:
 *
 * * `procedures.ts` / `procedures.js` — JavaScript hooks
 *   (`export function reduction_<Variable>(args)` /
 *   `export function hook_<name>(args)`), dispatched through a generated
 *   shim shared by the Node, Bun, and Deno adapters (native emitter) or
 *   through the wasm import (wasm emitter). This is the native-language
 *   path mirroring Rust's `procedures.rs`.
 * * `procedures.c` / `procedures.cpp` — rejected: not a JavaScript
 *   hook source (implement hooks in `procedures.ts`).
 * * `ll_error_messages.zig` / `lr_error_messages.zig` — custom syntax-error
 *   message hooks.
 *
 * A `procedures.c` / `procedures.cpp` file next to the grammar is not a
 * JavaScript hook source and fails loudly: implement hooks in
 * `procedures.ts` (or `procedures.js`). The gate always generates the
 * shim as a no-op fallback so the artifact links (hooks stay no-ops
 * until JavaScript registers them), mirroring the always-shim model of
 * the other bindings.
 *
 * The tool generates the parser (`--emit-metadata`) and builds the artifact
 * through the generic consumer build directly next to the grammar, so the
 * universal entry and the generated package entry can open it from the
 * language directory.
 *
 * Environment: `ZIG_EXECUTABLE` names an explicit zig; else `zig` on
 * `PATH`; else `uvx` provisioning the pinned ziglang (0.16.0). Neither
 * installed is a loud error naming both install pages. Compiling the
 * generated parser needs no checkout: the published core package carries
 * `compile-kit/` (the consumer build plus every source it reads), while
 * contributors running from a checkout without an assembled kit fall back
 * to `GALLEY_CHECKOUT` (must hold `build.zig`). Generating the parser
 * needs no checkout either: the CLI resolves from `GALLEY_CLI`, else the
 * platform package matching this machine (`optionalDependencies` of
 * `@sanbus/galley`), else a checkout bootstrap. To fetch a checkout for
 * convenience, use `examples/scripts/fetch-galley.sh` — that cache is an
 * examples-only convenience, not part of the bindings.
 */

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import { createRequire } from "node:module";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { emitJsProcedureShim, emitJsProcedureShimWasm } from "./shim.mjs";

/**
 * Canonical shared native build: one library serves the Node, Bun, and
 * Deno adapters (the dispatch symbols are identical across them). The
 * Bun/Deno adapters resolve this name as their shared fallback
 * (`SHARED_NATIVE_LIBRARY_BASE` in `core/src/artifact.ts`, which must
 * match this literal — separate module systems, so the universal loader
 * suite pins them equal through an end-to-end `galley build` case).
 */
export const NATIVE_LIBRARY_BASE = "galley-js-node";
/** Canonical wasm build for the wasm adapter and the universal fallback leg. */
export const WASM_LIBRARY_BASE = "galley-js-wasm";

/**
 * The `--parser-type` selection inside forwarded generator flags, if any.
 * Last wins on both spellings (`--parser-type lr`, `--parser-type=lr`),
 * mirroring the binary. Anything else (including a bad value) is the
 * generator's to reject — this only answers "must ll.grm exist?".
 * `--parser-type` is the one piece of generator surface the gate knows:
 * its value-shape is needed to find the grammar file. Every other flag
 * forwards untouched and the binary owns it.
 */
function parserTypeFromFlags(generatorFlags) {
  let parserType = null;
  for (let index = 0; index < generatorFlags.length; index++) {
    const flag = generatorFlags[index];
    if (flag === "--parser-type") {
      parserType = generatorFlags[index + 1] ?? null;
      index++;
    } else if (flag.startsWith("--parser-type=")) {
      parserType = flag.slice("--parser-type=".length);
    }
  }
  return parserType;
}

const WASM_TARGET = "wasm32-wasi";
const NATIVE_SHIM_FILE = "procedures_js.zig";
const WASM_SHIM_FILE = "procedures_wasm.zig";

// Generated package entry (node prototype): marker banner heading
// every generated index.mjs, marker field in package.json. The clobber
// guard refuses to overwrite either without it.
const PACKAGE_INIT_FILE = "index.mjs";
const PACKAGE_TYPES_FILE = "index.d.mts";
const PACKAGE_MANIFEST_FILE = "package.json";
const PACKAGE_BANNER = "// Generated by galley-js bindings; DO NOT EDIT.";
const PACKAGE_MANIFEST_FIELD = "galley-generated";
const CORE_DIRECTORY = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

function fatal(message) {
  console.error(`galley-bindings: ${message}`);
  process.exit(1);
}

function run(command, argumentList, options = {}) {
  console.log(`+ ${command} ${argumentList.map((argument) => JSON.stringify(argument)).join(" ")}`);
  const result = spawnSync(command, argumentList, { stdio: "inherit", ...options });
  if (result.error) fatal(`executable not found: ${command} (${result.error.message})`);
  if (result.status !== 0) fatal(`command failed: ${command} ${argumentList.join(" ")} (exit ${result.status})`);
}

function capture(command, argumentList) {
  const result = spawnSync(command, argumentList, { encoding: "utf-8" });
  if (result.error) fatal(`failed to probe ${command}: ${result.error.message}`);
  if (result.status !== 0) fatal(`command failed: ${command} ${argumentList.join(" ")}`);
  return result.stdout ?? "";
}

const COMPILE_KIT_DIRECTORY = path.join(CORE_DIRECTORY, "compile-kit");

let cachedZigCommand = null;

function probe(command, argumentList) {
  const result = spawnSync(command, argumentList, { stdio: "pipe", encoding: "utf-8" });
  return !result.error && result.status === 0;
}

/**
 * The zig command prefix. Explicit `ZIG_EXECUTABLE` wins; else `zig` on
 * `PATH`; else `uvx` provisioning the pinned ziglang. Anything else names
 * both installs loudly: zig 0.16.0 on PATH, or uvx so this tool provisions
 * zig itself.
 */
function zigCommand() {
  if (cachedZigCommand) return cachedZigCommand;
  const explicit = process.env.ZIG_EXECUTABLE;
  if (explicit) return (cachedZigCommand = [explicit]);
  if (probe("zig", ["version"])) return (cachedZigCommand = ["zig"]);
  if (probe("uvx", ["--version"])) {
    console.error("galley-bindings: no zig on PATH; provisioning zig 0.16.0 via uvx");
    return (cachedZigCommand = ["uvx", "--from", "ziglang==0.16.0", "python-zig"]);
  }
  fatal(
    "need zig to compile the generated parser: install zig 0.16.0 and put it on PATH " +
      "(https://ziglang.org/learn/getting-started/) " +
      "or install uvx (https://docs.astral.sh/uv/getting-started/installation/) " +
      "and this tool provisions zig 0.16.0 itself via `uvx --from ziglang==0.16.0 python-zig`.",
  );
}

function runZig(argumentList, options = {}) {
  const [command, ...prefix] = zigCommand();
  run(command, [...prefix, ...argumentList], options);
}

/**
 * Where the consumer build and its sources live. The published core
 * package carries `compile-kit/` (no checkout needed); contributors
 * running from a checkout without an assembled kit fall back to
 * `GALLEY_CHECKOUT` holding `build.zig`. Anything else is a loud error.
 * Both legs run the same consumer build with the same flags; only the
 * source root differs.
 */
function resolveCompileInputs() {
  const kitBuildFile = path.join(COMPILE_KIT_DIRECTORY, "build.zig");
  if (fs.existsSync(kitBuildFile)) {
    return {
      buildFile: kitBuildFile,
      galleySources: path.join(COMPILE_KIT_DIRECTORY, "sources"),
    };
  }
  const checkout = process.env.GALLEY_CHECKOUT;
  if (checkout && fs.existsSync(path.join(checkout, "build.zig"))) {
    const root = path.resolve(checkout);
    return {
      buildFile: path.join(root, "bindings/c/consumer/build.zig"),
      galleySources: root,
    };
  }
  fatal(
    "need compile inputs: the installed @sanbus/galley-core has no compile-kit/ " +
      "(reinstall it) or, when running from a Galley checkout, set GALLEY_CHECKOUT " +
      "at the checkout (must contain build.zig) or assemble the kit with " +
      "scripts/js/assemble_compile_kit.sh.",
  );
}

/** Prebuilt generator CLI per platform: npm package holding the binary. */
const GENERATOR_CLI_PLATFORMS = {
  "darwin:arm64": { package: "@sanbus/galley-cli-darwin-arm64", file: "bin/galley" },
  "darwin:x64": { package: "@sanbus/galley-cli-darwin-x64", file: "bin/galley" },
  "linux:x64": { package: "@sanbus/galley-cli-linux-x64", file: "bin/galley" },
  "linux:arm64": { package: "@sanbus/galley-cli-linux-arm64", file: "bin/galley" },
  "win32:x64": { package: "@sanbus/galley-cli-win32-x64", file: "bin/galley.exe" },
  "win32:arm64": { package: "@sanbus/galley-cli-win32-arm64", file: "bin/galley.exe" },
};

/**
 * The generator CLI to run, without building anything. Explicit
 * `GALLEY_CLI` wins; then the installed platform package (present exactly
 * when npm installed this machine's `optionalDependencies`); then a
 * checkout bootstrap, which needs `GALLEY_CHECKOUT` and zig. Anything
 * else is a loud error naming every leg. Pass `bindingsDirectory: null`
 * to skip the installed-package leg (the Deno wrapper runs from source
 * with no install step).
 */
export function resolveGeneratorCli({ bindingsDirectory = null } = {}) {
  const explicit = process.env.GALLEY_CLI;
  if (explicit) {
    if (!fs.existsSync(explicit)) fatal(`GALLEY_CLI=${explicit} does not exist`);
    return path.resolve(explicit);
  }
  const key = `${process.platform}:${process.arch}`;
  const target = GENERATOR_CLI_PLATFORMS[key];
  if (target && bindingsDirectory !== null) {
    try {
      const base = path.join(path.resolve(bindingsDirectory), "package.json");
      const resolved = createRequire(base).resolve(`${target.package}/${target.file}`);
      if (fs.existsSync(resolved)) return resolved;
    } catch {
      // Not installed: fall through to the checkout bootstrap below.
    }
  }
  const checkout = process.env.GALLEY_CHECKOUT;
  if (checkout && fs.existsSync(path.join(checkout, "build.zig"))) {
    const binary = `galley${process.platform === "win32" ? ".exe" : ""}`;
    const cli = path.join(path.resolve(checkout), "zig-out", "bin", binary);
    if (!fs.existsSync(cli)) {
      runZig(["build", "-Doptimize=ReleaseFast", "install"], { cwd: path.resolve(checkout) });
    }
    return cli;
  }
  const installed = target
    ? `npm install ${target.package} (or the owning @sanbus/galley with optional dependencies)`
    : `no prebuilt CLI exists for ${key} (shipped: ${Object.keys(GENERATOR_CLI_PLATFORMS).join(", ")})`;
  fatal(
    `no generator CLI found (tried GALLEY_CLI, then the installed platform package, then a checkout bootstrap).\n` +
      `To generate with no toolchain: ${installed}.\n` +
      `To bootstrap from source: set GALLEY_CHECKOUT at a Galley checkout with zig installed.`,
  );
}

/**
 * Confirm the owning adapter is installed and built. Whatever the install
 * layout (symlinked `file:` package or `--install-links` copy), the
 * runtime dependency must resolve from the owning directory the same way
 * the built output loads it. Say so loudly instead of running a package
 * manager behind your back. Pass `bindingsDirectory: null` to skip (the
 * Deno wrapper runs from source with no install step).
 */
export function ensureBindingsInstalled({ bindingsDirectory, dependencyName = null, installCommand = "npm install" }) {
  const builtIndex = path.join(bindingsDirectory, "dist", "index.js");
  if (!fs.existsSync(builtIndex)) {
    fatal(`bindings not built: run npm run build in ${bindingsDirectory} first`);
  }
  if (dependencyName !== null) {
    try {
      createRequire(path.join(bindingsDirectory, "package.json")).resolve(dependencyName);
    } catch {
      fatal(`bindings not installed: run ${installCommand} in ${bindingsDirectory} first`);
    }
  }
}

let cachedArtifactNames = null;
async function loadArtifactNames() {
  if (cachedArtifactNames) return cachedArtifactNames;
  try {
    cachedArtifactNames = await import("../dist/artifact.js");
    return cachedArtifactNames;
  } catch (error) {
    fatal(`cannot load @sanbus/galley-core dist (${error.message}); run npm run build in ${CORE_DIRECTORY} first`);
  }
}

function findJsProceduresFile(languageDirectory) {
  const candidates = [
    path.join(languageDirectory, "procedures.ts"),
    path.join(languageDirectory, "procedures.js"),
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) return candidate;
  }
  return null;
}

/**
 * Directory holding node_api.h for the running Node (shipped with every
 * Node distribution next to the executable).
 */
function nodeIncludeDirectory() {
  const candidate = path.resolve(path.dirname(process.execPath), "..", "include", "node");
  try {
    fs.accessSync(path.join(candidate, "node_api.h"));
    return candidate;
  } catch {
    fatal(`node_api.h not found under ${candidate}; reinstall Node with headers`);
  }
}

/**
 * Compile the Node NAPI addon (`addon.c`) against the language directory's
 * native library. Only the Node adapter needs this; Bun (`bun:ffi`) and
 * Deno (`Deno.dlopen`) load the shared library directly. The C inputs come
 * from the compile inputs (kit or checkout leg), so generation may have
 * used the prebuilt CLI.
 */
export function compileNodeAddon({ languageDirectory, libraryName }) {
  if (process.platform === "win32") {
    fatal("the Node addon is not supported on Windows; use WSL or another adapter");
  }
  const { galleySources } = resolveCompileInputs();
  const addonSource = path.join(galleySources, "bindings", "js", "node", "addon.c");
  const headerDirectory = path.join(galleySources, "bindings", "c");
  const directory = path.resolve(languageDirectory);
  const addonOutput = path.join(directory, `${libraryName}.node`);
  // The gate may skip a fresh parser library; the addon still needs to
  // exist and postdate both its source and the parser library it serves
  // (the addon resolves every grammar symbol through its own dlopen
  // probe at load, never through a link, so two copies of one build —
  // or two grammars, which share an install name — never alias).
  try {
    const addonTime = fs.statSync(addonOutput).mtimeMs;
    const sourceTime = fs.statSync(addonSource).mtimeMs;
    let libraryTime = 0;
    for (const entry of fs.readdirSync(directory)) {
      if (entry === `${libraryName}.node`) continue;
      if (entry.startsWith(`lib${libraryName}.`)) {
        libraryTime = Math.max(libraryTime, fs.statSync(path.join(directory, entry)).mtimeMs);
      }
    }
    if (addonTime >= sourceTime && addonTime >= libraryTime && libraryTime > 0) return;
  } catch {
    // Missing addon, source, or library: compile (or fail loud below).
  }
  const linkArguments = [
    "-shared",
    "-O2",
    `-I${nodeIncludeDirectory()}`,
    `-I${headerDirectory}`,
    addonSource,
    "-o",
    addonOutput,
  ];
  if (process.platform === "darwin") {
    // Node-API symbols resolve when Node loads the addon.
    linkArguments.push("-undefined", "dynamic_lookup");
  } else {
    // Position-independent code plus libdl for library probing.
    linkArguments.push("-fPIC", "-ldl");
  }
  const [zig, ...zigPrefix] = zigCommand();
  const result = spawnSync(zig, [...zigPrefix, "cc", ...linkArguments], { stdio: "pipe", encoding: "utf-8" });
  if (result.status !== 0) {
    fatal(`zig cc failed for ${libraryName}.node:\n${result.stderr || result.stdout || "unknown error"}`);
  }
  // The link proves nothing about the grammar library (nothing is
  // linked); loading it here proves every required symbol resolves,
  // next to the grammar.
  smokeLoadAddon(addonOutput, directory, libraryName);
  console.error(`galley-bindings: built ${addonOutput} (native addon for ${directory})`);
}

/**
 * Load a freshly built addon against its parser library: a missing or
 * stale library fails the build here, naming the symbol, instead of at
 * first parse.
 */
function smokeLoadAddon(addonOutput, languageDirectory, libraryName) {
  let library = null;
  for (const entry of fs.readdirSync(languageDirectory)) {
    if (entry.startsWith(`lib${libraryName}.`)) {
      library = path.join(languageDirectory, entry);
      break;
    }
  }
  if (library === null) fatal(`expected parser library next to ${addonOutput}`);
  let addon;
  try {
    addon = createRequire(import.meta.url)(addonOutput);
  } catch (error) {
    fatal(`built addon failed to load ${addonOutput}: ${error.message}`);
  }
  try {
    addon.load(library);
  } catch (error) {
    fatal(`built addon failed against ${library}: ${error.message}`);
  }
}

/**
 * Build one parser artifact next to the grammar. `wasm` selects the WASI
 * reactor module (wasm shim, `-Dwasm` target); otherwise a native shared
 * library (native shim). `platform` names the host for the native filename
 * (`process.platform` under Node/Bun, `Deno.build.os` under Deno — both
 * spellings map through the shared mapping). Returns the built path.
 *
 * `artifactFileName` / `wasmArtifactFileName` are the shared mapping from
 * `@sanbus/galley-core`. Node-family wrappers omit them and the gate loads the
 * built dist (their preflight guarantees it exists); the Deno wrapper
 * passes them from core sources, which Deno consumes directly without
 * ever building dist.
 *
 * @param {object} options
 * @param {string} options.languageDirectory
 * @param {string} options.libraryName
 * @param {boolean} [options.wasm]
 * @param {string} [options.platform]
 * @param {string|null} [options.bindingsDirectory]
 * @param {string|null} [options.dependencyName]
 * @param {string} [options.installCommand]
 * @param {boolean} [options.posixOnly]
 * @param {boolean} [options.addon] compile the Node NAPI addon after the
 *   native library (Node only; Bun and Deno load the library directly)
 * @param {Function|null} [options.artifactFileName]
 * @param {Function|null} [options.wasmArtifactFileName]
 * @param {string[]} [options.generatorFlags] extra generator CLI flags
 *   forwarded verbatim ahead of `--emit-metadata`. The wrappers forward
 *   every flag they don't own; the binary owns its surface (unknown flags
 *   die there with `unknown argument`). Only `--parser-type`'s
 *   value-shape is known here, to find the grammar file.
 * @returns {Promise<string>}
 */
export async function buildParserArtifact({
  languageDirectory,
  libraryName,
  wasm = false,
  platform = process.platform,
  bindingsDirectory = null,
  dependencyName = null,
  installCommand = "npm install",
  posixOnly = true,
  addon = false,
  artifactFileName = null,
  wasmArtifactFileName = null,
  generatorFlags = [],
}) {
  if (!languageDirectory) fatal("no language directory given");
  if (!libraryName) fatal("no library name given");
  if (posixOnly && (platform === "win32" || platform === "windows")) {
    fatal("the JavaScript bindings target POSIX platforms");
  }
  if (bindingsDirectory !== null) {
    ensureBindingsInstalled({ bindingsDirectory, dependencyName, installCommand });
  }

  const names =
    artifactFileName && wasmArtifactFileName
      ? { artifactFileName, wasmArtifactFileName }
      : await loadArtifactNames();
  const outputFileName = wasm ? names.wasmArtifactFileName(libraryName) : names.artifactFileName(libraryName, platform);

  const languageDir = path.resolve(languageDirectory);
  // Single-parser generation needs only its own grammar: `--parser-type lr`
  // runs against lr.grm alone. Anything else (including a bad value) is
  // the generator's to reject.
  if (parserTypeFromFlags(generatorFlags) !== "lr" && !fs.existsSync(path.join(languageDir, "ll.grm")))
    fatal(`${languageDir} does not contain ll.grm`);
  if (fs.existsSync(path.join(languageDir, "procedures.c")) || fs.existsSync(path.join(languageDir, "procedures.cpp")))
    fatal("procedures.c/procedures.cpp is not a JavaScript hook source: implement hooks in procedures.ts");

  const cli = resolveGeneratorCli({ bindingsDirectory });

  const help = capture(cli, ["--help"]);
  if (!help.includes("--emit-metadata")) {
    fatal(`the generator CLI at ${cli} is too old for the bindings workflow (no --emit-metadata support); update it`);
  }

  run(cli, [...generatorFlags, "--emit-metadata", languageDir]);

  // One library embeds one parser; the consumer build locates the file
  // generation produced from `-Dlanguage-dir` and infers the family from
  // the filename.
  const jsProceduresFile = findJsProceduresFile(languageDir);
  // The wasm shim lives next to the native one under its own name so both
  // builds can share one language directory.
  const shimPath = path.join(languageDir, wasm ? WASM_SHIM_FILE : NATIVE_SHIM_FILE);
  const emitShim = wasm ? emitJsProcedureShimWasm : emitJsProcedureShim;
  if (jsProceduresFile !== null) {
    console.error(`galley-bindings: using JS procedures from ${jsProceduresFile}`);
  }
  emitShim(path.join(languageDir, "metadata.json"), shimPath);
  const proceduresZigSource = shimPath;

  // Compiling needs the kit (or a checkout leg); generation above
  // deliberately needs neither.
  const { buildFile } = resolveCompileInputs();
  const consumerArguments = [
    "build",
    "--build-file",
    buildFile,
    `-Dlanguage-dir=${languageDir}`,
    `-Dlib-name=${libraryName}`,
    ...(wasm ? [`-Dtarget=${WASM_TARGET}`, "-Dwasm"] : []),
    `-Doutput=${outputFileName}`,
    "-Doptimize=ReleaseFast",
    `-Dprocedures-zig-source=${proceduresZigSource}`,
    "--prefix",
    languageDir,
    "install",
  ];
  // `config.zig` and `{ll,lr}_error_messages.zig` are inferred by the
  // consumer build from the parser location.
  runZig(consumerArguments, { cwd: languageDir });

  const destination = path.join(languageDir, outputFileName);
  if (!fs.existsSync(destination)) fatal(`expected library not found at ${destination}`);
  if (addon) {
    if (wasm) fatal("the Node addon serves the native leg only; do not combine addon with wasm");
    compileNodeAddon({ languageDirectory: languageDir, libraryName });
  }
  // Every leg writes the import entry: it only pre-binds the universal
  // directory open, so it is backend-agnostic. Packaging never fails the
  // artifact build — a skipped entry warns loudly and the artifact
  // still loads through galley.load.
  const packageName = emitPackageEntry(languageDir);
  if (packageName !== null) {
    console.log(
      `galley-bindings: built ${destination}; import ${packageName} from ${path.dirname(languageDir)} or galley.load(${destination})`,
    );
  } else {
    console.log(`galley-bindings: built ${destination}; galley.load(${destination})`);
  }
  return destination;
}

/**
 * Package name for a language directory, or null with a loud warning.
 * npm rules, conservative subset: lowercase alphanumerics plus `._~-`,
 * capped length. A skipped entry never fails the artifact build
 * (`galley.load` works with any name).
 */
function packageNameFor(languageDir) {
  const name = path.basename(languageDir);
  if (!/^[a-z0-9][a-z0-9._~-]*$/.test(name) || name.length > 214) {
    console.error(
      `galley-bindings: skipping package entry: ${languageDir} is not an importable package name (${name}); rename the folder to import it`,
    );
    return null;
  }
  return name;
}

/**
 * Writes the generated package entry for direct import: `package.json`
 * plus an `index.mjs` that opens sessions on its own directory, with
 * the bundled `procedures` scan the generated entry performs. The entry
 * only pre-binds the directory. Returns the package name, or null when
 * the entry is skipped (warned, never fatal: packaging must not fail
 * artifact compilation).
 */
function emitPackageEntry(languageDir) {
  const name = packageNameFor(languageDir);
  if (name === null) return null;
  // Check all clobber guards before writing any file: a foreign
  // index.mjs must not leave a half-written entry behind.
  const manifestPath = path.join(languageDir, PACKAGE_MANIFEST_FILE);
  let previous = null;
  if (fs.existsSync(manifestPath)) {
    try {
      previous = JSON.parse(fs.readFileSync(manifestPath, "utf-8"));
    } catch {
      previous = null;
    }
    if (!previous || previous[PACKAGE_MANIFEST_FIELD] !== true) {
      console.error(
        `galley-bindings: skipping package entry: ${manifestPath} exists and was not generated by galley-js; move it aside to make the language directory importable`,
      );
      return null;
    }
  }
  const initPath = path.join(languageDir, PACKAGE_INIT_FILE);
  if (fs.existsSync(initPath) && !fs.readFileSync(initPath, "utf-8").includes(PACKAGE_BANNER)) {
    console.error(
      `galley-bindings: skipping package entry: ${initPath} exists and was not generated by galley-js; move it aside to make the language directory importable`,
    );
    return null;
  }
  const typesPath = path.join(languageDir, PACKAGE_TYPES_FILE);
  if (fs.existsSync(typesPath) && !fs.readFileSync(typesPath, "utf-8").includes(PACKAGE_BANNER)) {
    console.error(
      `galley-bindings: skipping package entry: ${typesPath} exists and was not generated by galley-js; move it aside to make the language directory importable`,
    );
    return null;
  }
  // Baked into the entry: the bundled hook file found at build time, or
  // null for hook-less grammars. `initialize()` loads it on runtimes
  // without a synchronous scan (Deno).
  const proceduresFile = findJsProceduresFile(languageDir);
  const proceduresSpecifier = proceduresFile === null ? "null" : `"./${path.basename(proceduresFile)}"`;
  fs.writeFileSync(
    manifestPath,
    JSON.stringify(
      {
        ...previous,
        name,
        type: "module",
        // "main" serves CJS require("./<dir>") (directory resolution
        // ignores "exports"); ESM still needs the file: import
        // "./<dir>/index.mjs". Bare "l1" works either way once the
        // directory is installed under node_modules.
        main: "./index.mjs",
        exports: { ".": "./index.mjs" },
        // Unpinned on purpose: the builder cannot know the consumer's
        // pin; presence (not version) is what the entry needs.
        peerDependencies: { "@sanbus/galley": "*", "@sanbus/galley-core": "*" },
        [PACKAGE_MANIFEST_FIELD]: true,
      },
      null,
      2,
    ) + "\n",
    "utf-8",
  );
  fs.writeFileSync(
    initPath,
    `${PACKAGE_BANNER}
// Language package: parser surface plus bundled hook wiring. Mirrors
// the built Python package (\`import kv\`): sessions open on this
// package's parser, bundled hooks wire automatically.
//
//   import * as kv from "./kv/index.mjs";
//   await kv.initialize();
//   const session = await kv.openSession({ maxErrors: 10 });
import { fileURLToPath } from "node:url";
import {
  Session,
  Node,
  Walker,
  ProcedureArguments,
  Language,
  GalleyError,
  Kind,
  ParserType,
  RecoveryMode,
  RecoveryTarget,
  Resume,
} from "@sanbus/galley-core";
import { openLanguageDirectory } from "@sanbus/galley";

export {
  Session,
  Node,
  Walker,
  ProcedureArguments,
  Language,
  GalleyError,
  Kind,
  ParserType,
  RecoveryMode,
  RecoveryTarget,
  Resume,
};

const LANGUAGE_DIR = fileURLToPath(new URL(".", import.meta.url));

// Baked at build time: the bundled hook file found next to the grammar,
// or null for hook-less grammars.
const PROCEDURES_SPECIFIER = ${proceduresSpecifier};

/**
 * Bundled hook namespace once loaded by \`initialize()\`, else null.
 * Module-private: hook namespaces are imported from their hook file.
 */
let bundledProcedures = null;

/**
 * Prepare this package for use. Required on Deno, where no synchronous
 * scan exists: loads the bundled hooks into the shared language handle
 * for later sessions. A no-op on every other runtime, so one program
 * runs everywhere.
 */
export async function initialize() {
  if (
    PROCEDURES_SPECIFIER !== null &&
    bundledProcedures === null &&
    globalThis.Deno !== undefined
  ) {
    bundledProcedures = await import(PROCEDURES_SPECIFIER);
    (await openLanguageDirectory(LANGUAGE_DIR, { expectProcedures: true })).installProcedures(bundledProcedures);
  }
}

/**
 * The shared language handle for this package's parser. Sessions open
 * from it, and explicit hook installs target it directly.
 *
 * @returns {Promise<import("@sanbus/galley").Language>}
 */
export function language(options = {}) {
  return openLanguageDirectory(LANGUAGE_DIR, options);
}

/**
 * Opens a session on this package's parser. Bundled \`procedures\`
 * wire automatically at handle creation, ahead of any explicit
 * installs on the language handle. Backend pins apply to the acquire
 * half only; explicit hooks need \`language()\` first, since one call
 * cannot install and open atomically.
 *
 * @returns {Promise<import("@sanbus/galley").Session>}
 */
export function openSession(options = {}) {
  const { backend, ...sessionOptions } = options;
  return openLanguageDirectory(LANGUAGE_DIR, { backend }).then((lang) =>
    lang.openSession(sessionOptions),
  );
}
`,
    "utf-8",
  );
  fs.writeFileSync(
    typesPath,
    `${PACKAGE_BANNER}
// Type declarations for the generated language package entry.
import type {
  Session,
  Node,
  Walker,
  ProcedureArguments,
  Language,
  Diagnostic,
  GalleyError,
  Kind,
  ParserType,
  RecoveryMode,
  RecoveryTarget,
  Resume,
  SessionOptions,
  UniversalDirectoryOptions,
} from "@sanbus/galley";

export {
  Session,
  Node,
  Walker,
  ProcedureArguments,
  Language,
  Diagnostic,
  GalleyError,
  Kind,
  ParserType,
  RecoveryMode,
  RecoveryTarget,
  Resume,
};

/** See \`initialize\` in \`./index.mjs\`. */
export declare function initialize(): Promise<void>;
/** See \`openSession\` in \`./index.mjs\`. */
export declare function openSession(options?: SessionOptions & UniversalDirectoryOptions): Promise<Session>;
/** See \`language\` in \`./index.mjs\`. */
export declare function language(options?: UniversalDirectoryOptions): Promise<Language>;
`,
    "utf-8",
  );
  return name;
}
