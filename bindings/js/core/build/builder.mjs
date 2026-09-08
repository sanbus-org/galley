#!/usr/bin/env node
/**
 * Shared parser-artifact builder for the Galley JavaScript bindings.
 *
 * Single gate behind every JavaScript build entry: `galley build` in the
 * universal package, plus `galley-js-node`, `galley-js-bun`,
 * `galley-js-wasm`, and the Deno `build.ts`. Callers pass targeting
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
 * Environment: `ZIG_EXECUTABLE` (default `zig`) and `GALLEY_CHECKOUT`
 * (required): an existing Galley working tree holding `build.zig`. To
 * fetch a checkout for convenience, use
 * `examples/scripts/fetch-galley.sh` — that cache is an examples-only
 * convenience, not part of the bindings.
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

function zigExecutable() {
  return process.env.ZIG_EXECUTABLE ?? "zig";
}

/** The checkout `GALLEY_CHECKOUT` names, or a loud error. No guessing. */
export function resolveGalleyCheckout() {
  const checkout = process.env.GALLEY_CHECKOUT;
  if (!checkout) {
    fatal("GALLEY_CHECKOUT is not set; point it at a Galley checkout (examples/scripts/fetch-galley.sh can fetch one)");
  }
  if (!fs.existsSync(path.join(checkout, "build.zig"))) {
    fatal(`GALLEY_CHECKOUT=${checkout} is not a Galley repository checkout (no build.zig)`);
  }
  return path.resolve(checkout);
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
    fatal(`cannot load galley-js-core dist (${error.message}); run npm run build in ${CORE_DIRECTORY} first`);
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
 * Build one parser artifact next to the grammar. `wasm` selects the WASI
 * reactor module (wasm shim, `-Dwasm` target); otherwise a native shared
 * library (native shim). `platform` names the host for the native filename
 * (`process.platform` under Node/Bun, `Deno.build.os` under Deno — both
 * spellings map through the shared mapping). Returns the built path.
 *
 * `artifactFileName` / `wasmArtifactFileName` are the shared mapping from
 * `galley-js-core`. Node-family wrappers omit them and the gate loads the
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

  const galleySource = resolveGalleyCheckout();
  const cli = path.join(galleySource, "zig-out", "bin", "galley");
  if (!fs.existsSync(cli)) {
    run(zigExecutable(), ["build", "-Doptimize=ReleaseFast", "install"], { cwd: galleySource });
  }

  const help = capture(cli, ["--help"]);
  if (!help.includes("--emit-metadata")) {
    fatal(
      `the Galley at ${galleySource} is too old for the bindings workflow (no --emit-metadata support); update the checkout`,
    );
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

  const consumerArguments = [
    "build",
    "--build-file",
    path.join(galleySource, "bindings/c/consumer/build.zig"),
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
  run(zigExecutable(), consumerArguments, { cwd: galleySource });

  const destination = path.join(languageDir, outputFileName);
  if (!fs.existsSync(destination)) fatal(`expected library not found at ${destination}`);
  console.log(`galley-bindings: built ${destination}; import from ${languageDir} (or set GALLEY_LIBRARY_PATH)`);
  return destination;
}
