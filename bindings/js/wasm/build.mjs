#!/usr/bin/env node
/**
 * Builds a Galley parser and its WebAssembly module for a JavaScript consumer.
 *
 * Usage:
 *   npx galley-js-wasm <language-dir>
 *
 * The language dir must contain ll.grm and may contain config.zig,
 * procedures, ll_error_messages.zig etc, mirroring the other bindings:
 *
 * * `procedures.ts` / `procedures.js` — JS hooks
 *   (`export function reduction_<Var>(args)` / `export function hook_<name>(args)`),
 *   dispatched through a generated wasm shim: every hook forwards through
 *   the `galley_js_dispatch` host import (see `galley-js-core/build/shim.mjs`).
 *   This is the wasm counterpart of the native JS dispatch shim.
 * * `procedures.c` / `procedures.cpp` — legacy C/C++ hooks compiled into the
 *   module, exactly like the C/C++ consumers.
 * * `ll_error_messages.zig` / `lr_error_messages.zig` — custom syntax-error
 *   message hooks.
 *
 * The tool generates the parser (--emit-metadata), builds the WASI reactor
 * module through the generic consumer build (`-Dwasm`) directly next to the grammar so
 * `import { Session } from "galley-js-wasm"` can locate it via cwd or
 * GALLEY_LIBRARY_PATH.
 *
 * Environment overrides: ZIG_EXECUTABLE (default zig), GALLEY_LIBRARY_PATH,
 *   GALLEY_CHECKOUT (required: existing Galley working tree). To fetch a
 *   checkout for convenience, use examples/scripts/fetch-galley.sh — that
 *   cache is an examples-only convenience, not part of the bindings.
 */

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const LIBRARY_NAME = "galley-js-wasm";
const WASM_TARGET = "wasm32-wasi";

function fatal(msg) {
  console.error(`galley-bindings: ${msg}`);
  process.exit(1);
}

function run(cmd, args, opts = {}) {
  console.log(`+ ${cmd} ${args.map((a) => JSON.stringify(a)).join(" ")}`);
  const res = spawnSync(cmd, args, { stdio: "inherit", ...opts });
  if (res.error) fatal(`executable not found: ${cmd} (${res.error.message})`);
  if (res.status !== 0) fatal(`command failed: ${cmd} ${args.join(" ")} (exit ${res.status})`);
}

function capture(cmd, args) {
  const res = spawnSync(cmd, args, { encoding: "utf-8" });
  if (res.error) fatal(`failed to probe ${cmd}: ${res.error.message}`);
  if (res.status !== 0) fatal(`command failed: ${cmd} ${args.join(" ")}`);
  return res.stdout ?? "";
}

function zigExecutable() {
  return process.env.ZIG_EXECUTABLE ?? "zig";
}

function resolveGalley() {
  // GALLEY_CHECKOUT is required. Fetching a checkout into the system cache
  // is an examples-only convenience (examples/scripts/fetch-galley.sh).
  const checkoutEnv = process.env.GALLEY_CHECKOUT;
  if (!checkoutEnv) {
    fatal("GALLEY_CHECKOUT is not set; point it at a Galley checkout (examples/scripts/fetch-galley.sh can fetch one)");
  }
  if (!fs.existsSync(path.join(checkoutEnv, "build.zig"))) {
    fatal(`GALLEY_CHECKOUT=${checkoutEnv} is not a Galley repository checkout (no build.zig)`);
  }
  return path.resolve(checkoutEnv);
}

function wasmFileName(base = LIBRARY_NAME) {
  return `lib${base}.wasm`;
}

function findJsProceduresFile(languageDir) {
  const candidates = [
    path.join(languageDir, "procedures.ts"),
    path.join(languageDir, "procedures.js"),
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) return candidate;
  }
  return null;
}

async function loadShimGenerator() {
  // Dynamic import: node_modules may not exist until ensureBindingsInstalled
  // runs below. The generator lives in galley-js-core so every JS build
  // script shares one implementation.
  try {
    return await import("galley-js-core/build/shim.mjs");
  } catch (e) {
    fatal(
      `cannot load galley-js-core/build/shim.mjs (${e.message}); run npm install in bindings/js/wasm first`,
    );
  }
}

function ensureBindingsInstalled() {
  // `file:` consumers (examples/js/wasm) link this package; the package
  // manager does not install our dependencies into this directory, so the
  // `galley-js-core` import in dist/ would not resolve unless we install
  // ourselves.
  const bindingsDir = path.dirname(fileURLToPath(import.meta.url));
  const core = path.join(bindingsDir, "node_modules", "galley-js-core");
  const distIndex = path.join(bindingsDir, "dist", "index.js");
  if (fs.existsSync(core) && fs.existsSync(distIndex)) return;
  console.error("galley-bindings: installing JavaScript bindings dependencies...");
  run("npm", ["install"], { cwd: bindingsDir });
  if (!fs.existsSync(core)) fatal("npm install did not produce node_modules/galley-js-core");
  if (!fs.existsSync(distIndex)) fatal("npm install did not produce dist/index.js");
}

async function main() {
  if (process.argv.length !== 3) fatal("usage: npx galley-js-wasm <language-dir>");

  ensureBindingsInstalled();
  const { emitJsProcedureShimWasm } = await loadShimGenerator();

  const languageDir = path.resolve(process.argv[2]);
  if (!fs.existsSync(path.join(languageDir, "ll.grm"))) fatal(`${languageDir} does not contain ll.grm`);

  const galleySource = resolveGalley();
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

  // One module embeds one parser; the consumer build locates the file
  // generation produced from -Dlanguage-dir and infers the family from
  // the filename.
  // JS-native procedures take precedence over C procedures: if a
  // procedures.ts/js exists, generate a wasm dispatch shim and use it
  // instead of the C extern stub. When neither JS nor C implementations
  // exist, still generate the wasm shim as a no-op fallback so the
  // module links (hooks are simply no-ops until JS registers them via
  // installProcedures), mirroring the native adapters.
  const jsProceduresFile = findJsProceduresFile(languageDir);
  let proceduresZigSource = null;
  let proceduresCSource = null;
  const hasCProcedures =
    fs.existsSync(path.join(languageDir, "procedures.c")) ||
    fs.existsSync(path.join(languageDir, "procedures.cpp"));
  // The wasm shim lives next to the native one under its own name so both
  // builds can share one language directory.
  const wasmShimPath = path.join(languageDir, "procedures_wasm.zig");
  if (jsProceduresFile !== null) {
    if (hasCProcedures) {
      console.error(
        `galley-bindings: both JS (${jsProceduresFile}) and C procedures found — using JS`,
      );
    }
    console.error(`galley-bindings: using JS procedures from ${jsProceduresFile}`);
    emitJsProcedureShimWasm(path.join(languageDir, "metadata.json"), wasmShimPath);
    proceduresZigSource = wasmShimPath;
  } else if (hasCProcedures) {
    if (fs.existsSync(path.join(languageDir, "procedures.zig")))
      proceduresZigSource = path.join(languageDir, "procedures.zig");
    if (fs.existsSync(path.join(languageDir, "procedures.c")))
      proceduresCSource = path.join(languageDir, "procedures.c");
    else if (fs.existsSync(path.join(languageDir, "procedures.cpp")))
      proceduresCSource = path.join(languageDir, "procedures.cpp");
  } else {
    if (fs.existsSync(path.join(languageDir, "procedures.zig"))) {
      emitJsProcedureShimWasm(path.join(languageDir, "metadata.json"), wasmShimPath);
      proceduresZigSource = wasmShimPath;
    }
  }

  const consumerArgs = [
    "build",
    "--build-file",
    path.join(galleySource, "bindings/c/consumer/build.zig"),
    `-Dlanguage-dir=${languageDir}`,
    `-Dlib-name=${LIBRARY_NAME}`,
    `-Dtarget=${WASM_TARGET}`,
    "-Dwasm",
    `-Doutput=${wasmFileName()}`,
    "-Doptimize=ReleaseFast",
    "--prefix",
    languageDir,
    "install",
  ];
  if (proceduresZigSource !== null) {
    consumerArgs.splice(consumerArgs.length - 1, 0, `-Dprocedures-zig-source=${proceduresZigSource}`);
  }
  if (proceduresCSource !== null) {
    consumerArgs.splice(consumerArgs.length - 1, 0, `-Dprocedures-c-source=${proceduresCSource}`);
  }
  // config.zig and {ll,lr}_error_messages.zig are inferred by the consumer
  // build from the parser location.
  run(zigExecutable(), consumerArgs, { cwd: galleySource });

  const dest = path.join(languageDir, wasmFileName());
  if (!fs.existsSync(dest)) fatal(`expected module not found at ${dest}`);
  console.log(`galley-bindings: built ${dest}; import from ${languageDir} (or set GALLEY_LIBRARY_PATH)`);
}

main().catch((e) => fatal(e?.message ?? String(e)));
