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
 * The language directory must contain `ll.grm` and may contain
 * `config.zig`, procedures, and `ll_error_messages.zig`, mirroring the
 * other bindings:
 *
 * * `procedures.ts` / `procedures.js` — JavaScript hooks
 *   (`export function reduction_<Variable>(args)` /
 *   `export function hook_<name>(args)`), dispatched through a generated
 *   shim shared by the Node, Bun, and Deno adapters (native emitter) or
 *   through the wasm import (wasm emitter). This is the native-language
 *   path mirroring Rust's `procedures.rs`.
 * * `procedures.c` / `procedures.cpp` — legacy C/C++ hooks compiled into
 *   the artifact, exactly like the C/C++ consumers.
 * * `ll_error_messages.zig` / `lr_error_messages.zig` — custom syntax-error
 *   message hooks.
 *
 * JavaScript procedures take precedence over C procedures. When neither
 * exists, the gate still generates the shim as a no-op fallback so the
 * artifact links (hooks stay no-ops until JavaScript registers them),
 * mirroring the always-shim model of the other bindings.
 *
 * The tool generates the parser (`--emit-metadata`) and builds the artifact
 * through the generic consumer build directly next to the grammar, so the
 * adapters can name it through an explicit path or `GALLEY_LIBRARY_PATH`.
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
 * Deno adapters (the dispatch symbols are identical across them).
 */
export const NATIVE_LIBRARY_BASE = "galley-js-node";
/** Canonical wasm build for the wasm adapter and the universal fallback leg. */
export const WASM_LIBRARY_BASE = "galley-js-wasm";

const WASM_TARGET = "wasm32-wasi";
const NATIVE_SHIM_FILE = "procedures_js.zig";
const WASM_SHIM_FILE = "procedures_wasm.zig";
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
  // exist and postdate both its source and the library it links.
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
    `-L${directory}`,
    `-l${libraryName}`,
  ];
  if (process.platform === "darwin") {
    // Node-API symbols resolve when Node loads the addon.
    linkArguments.push("-undefined", "dynamic_lookup");
    linkArguments.push("-Wl,-rpath,@loader_path");
  } else {
    // Position-independent code plus libdl for shim probing.
    linkArguments.push("-fPIC", "-ldl", "-Wl,-rpath,$ORIGIN");
  }
  // The addon links the grammar's parser library so a missing or stale
  // library fails here, next to the grammar.
  const [zig, ...zigPrefix] = zigCommand();
  const result = spawnSync(zig, [...zigPrefix, "cc", ...linkArguments], { stdio: "pipe", encoding: "utf-8" });
  if (result.status !== 0) {
    fatal(`zig cc failed for ${libraryName}.node:\n${result.stderr || result.stdout || "unknown error"}`);
  }
  console.error(`galley-bindings: built ${addonOutput}; import from ${directory}`);
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
  if (!fs.existsSync(path.join(languageDir, "ll.grm"))) fatal(`${languageDir} does not contain ll.grm`);

  const cli = resolveGeneratorCli({ bindingsDirectory });

  const help = capture(cli, ["--help"]);
  if (!help.includes("--emit-metadata")) {
    fatal(`the generator CLI at ${cli} is too old for the bindings workflow (no --emit-metadata support); update it`);
  }

  run(cli, ["--emit-metadata", languageDir]);

  // One library embeds one parser; the consumer build locates the file
  // generation produced from `-Dlanguage-dir` and infers the family from
  // the filename.
  const jsProceduresFile = findJsProceduresFile(languageDir);
  let proceduresZigSource = null;
  let proceduresCSource = null;
  const hasCProcedures =
    fs.existsSync(path.join(languageDir, "procedures.c")) ||
    fs.existsSync(path.join(languageDir, "procedures.cpp"));
  // The wasm shim lives next to the native one under its own name so both
  // builds can share one language directory.
  const shimPath = path.join(languageDir, wasm ? WASM_SHIM_FILE : NATIVE_SHIM_FILE);
  const emitShim = wasm ? emitJsProcedureShimWasm : emitJsProcedureShim;
  if (jsProceduresFile !== null) {
    if (hasCProcedures) {
      console.error(`galley-bindings: both JS (${jsProceduresFile}) and C procedures found — using JS`);
    }
    console.error(`galley-bindings: using JS procedures from ${jsProceduresFile}`);
    emitShim(path.join(languageDir, "metadata.json"), shimPath);
    proceduresZigSource = shimPath;
  } else if (hasCProcedures) {
    if (fs.existsSync(path.join(languageDir, "procedures.zig"))) {
      proceduresZigSource = path.join(languageDir, "procedures.zig");
    }
    if (fs.existsSync(path.join(languageDir, "procedures.c"))) {
      proceduresCSource = path.join(languageDir, "procedures.c");
    } else if (fs.existsSync(path.join(languageDir, "procedures.cpp"))) {
      proceduresCSource = path.join(languageDir, "procedures.cpp");
    }
  } else if (fs.existsSync(path.join(languageDir, "procedures.zig"))) {
    emitShim(path.join(languageDir, "metadata.json"), shimPath);
    proceduresZigSource = shimPath;
  }

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
    "--prefix",
    languageDir,
    "install",
  ];
  if (proceduresZigSource !== null) {
    consumerArguments.splice(consumerArguments.length - 1, 0, `-Dprocedures-zig-source=${proceduresZigSource}`);
  }
  if (proceduresCSource !== null) {
    consumerArguments.splice(consumerArguments.length - 1, 0, `-Dprocedures-c-source=${proceduresCSource}`);
  }
  // `config.zig` and `{ll,lr}_error_messages.zig` are inferred by the
  // consumer build from the parser location.
  runZig(consumerArguments, { cwd: languageDir });

  const destination = path.join(languageDir, outputFileName);
  if (!fs.existsSync(destination)) fatal(`expected library not found at ${destination}`);
  console.log(`galley-bindings: built ${destination}; import from ${languageDir} (or set GALLEY_LIBRARY_PATH)`);
  if (addon) {
    if (wasm) fatal("the Node addon serves the native leg only; do not combine addon with wasm");
    compileNodeAddon({ languageDirectory: languageDir, libraryName });
  }
  return destination;
}
