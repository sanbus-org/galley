#!/usr/bin/env node
/**
 * Builds a Galley parser and its shared library for a JavaScript consumer
 * on Node.
 *
 * Usage:
 *   npx galley-js-node <language-dir>
 *
 * The language dir must contain ll.grm and may contain config.zig,
 * procedures, ll_error_messages.zig etc, mirroring the other bindings:
 *
 * * `procedures.ts` / `procedures.js` — JS hooks
 *   (`export function reduction_<Var>(args)` / `export function hook_<name>(args)`),
 *   dispatched through a generated JS shim shared by the Node, Bun, and
 *   Deno adapters. This is the native-language path mirroring Rust's
 *   `procedures.rs`.
 * * `procedures.c` / `procedures.cpp` — legacy C/C++ hooks compiled into the
 *   shared library, exactly like the C/C++ consumers.
 * * `ll_error_messages.zig` / `lr_error_messages.zig` — custom syntax-error
 *   message hooks.
 *
 * The tool generates the parser (--emit-metadata) and builds the shared
 * library through the generic consumer build directly next to the grammar,
 * so `import { Session } from "galley-js-node"`
 * can locate it via cwd or GALLEY_LIBRARY_PATH.
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

const LIBRARY_NAME = "galley-js-node";

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

function findGeneratedParser(languageDir) {
  const hasLL = fs.existsSync(path.join(languageDir, "_ll-parser.zig"));
  const hasLR = fs.existsSync(path.join(languageDir, "_lr-parser.zig"));
  if (hasLL && !hasLR) return "_ll-parser.zig";
  if (hasLR && !hasLL) return "_lr-parser.zig";
  if (hasLL && hasLR)
    fatal(
      `both _ll-parser.zig and _lr-parser.zig exist in ${languageDir}; one library embeds one parser — split the language dirs`,
    );
  fatal(`generation produced no parser in ${languageDir}`);
}

function libFileName(base = LIBRARY_NAME) {
  if (process.platform === "darwin") return `lib${base}.dylib`;
  if (process.platform === "win32") return `${base}.dll`;
  return `lib${base}.so`;
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
  // runs below. The generator lives in galley-js-core so the Node, Bun, and
  // Deno build scripts share one implementation.
  try {
    return await import("galley-js-core/build/shim.mjs");
  } catch (e) {
    fatal(
      `cannot load galley-js-core/build/shim.mjs (${e.message}); run npm install in bindings/js/node first`,
    );
  }
}

function ensureBindingsInstalled() {
  // `file:` consumers (examples/js/node) symlink this package; npm does
  // not install our dependencies into this directory. `createRequire(import.meta.url)`
  // in dist/ffi.js therefore cannot see koffi unless we install ourselves.
  const bindingsDir = path.dirname(fileURLToPath(import.meta.url));
  const koffi = path.join(bindingsDir, "node_modules", "koffi");
  const distIndex = path.join(bindingsDir, "dist", "index.js");
  if (fs.existsSync(koffi) && fs.existsSync(distIndex)) return;
  console.error("galley-bindings: installing JavaScript bindings dependencies...");
  run("npm", ["install"], { cwd: bindingsDir });
  if (!fs.existsSync(koffi)) fatal("npm install did not produce node_modules/koffi");
  if (!fs.existsSync(distIndex)) fatal("npm install did not produce dist/index.js");
}

async function main() {
  if (process.argv.length !== 3) fatal("usage: npx galley-js-node <language-dir>");
  if (os.platform() === "win32") fatal("the JavaScript bindings target POSIX platforms");

  ensureBindingsInstalled();
  const { emitJsProcedureShim } = await loadShimGenerator();

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

  const parserSource = findGeneratedParser(languageDir);

  // JS-native procedures take precedence over C procedures: if a
  // procedures.ts/js exists, generate a JS dispatch shim and use it
  // instead of the C extern stub. When neither JS nor C implementations
  // exist, still generate the JS shim as a no-op fallback so the
  // library links (hooks are simply no-ops until JS registers them via
  // installProcedure), mirroring Python's always-shim model.
  const jsProceduresFile = findJsProceduresFile(languageDir);
  let proceduresZigSource = null;
  let proceduresCSource = null;
  const hasCProcedures =
    fs.existsSync(path.join(languageDir, "procedures.c")) ||
    fs.existsSync(path.join(languageDir, "procedures.cpp"));
  if (jsProceduresFile !== null) {
    if (hasCProcedures) {
      console.error(
        `galley-bindings: both JS (${jsProceduresFile}) and C procedures found — using JS`,
      );
    }
    console.error(`galley-bindings: using JS procedures from ${jsProceduresFile}`);
    const shimPath = path.join(languageDir, "procedures_js.zig");
    const templatePath = path.join(languageDir, "procedures.zig");
    emitJsProcedureShim(templatePath, shimPath);
    proceduresZigSource = shimPath;
  } else if (hasCProcedures) {
    if (fs.existsSync(path.join(languageDir, "procedures.zig")))
      proceduresZigSource = path.join(languageDir, "procedures.zig");
    if (fs.existsSync(path.join(languageDir, "procedures.c")))
      proceduresCSource = path.join(languageDir, "procedures.c");
    else if (fs.existsSync(path.join(languageDir, "procedures.cpp")))
      proceduresCSource = path.join(languageDir, "procedures.cpp");
  } else {
    if (fs.existsSync(path.join(languageDir, "procedures.zig"))) {
      const shimPath = path.join(languageDir, "procedures_js.zig");
      const templatePath = path.join(languageDir, "procedures.zig");
      emitJsProcedureShim(templatePath, shimPath);
      proceduresZigSource = shimPath;
    }
  }

  const consumerArgs = [
    "build",
    "--build-file",
    path.join(galleySource, "bindings/c/consumer/build.zig"),
    `-Dparser-source=${path.join(languageDir, parserSource)}`,
    `-Dlib-name=${LIBRARY_NAME}`,
    `-Doutput=${libFileName()}`,
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

  const dest = path.join(languageDir, libFileName());
  if (!fs.existsSync(dest)) fatal(`expected library not found at ${dest}`);
  console.log(`galley-bindings: built ${dest}; import from ${languageDir} (or set GALLEY_LIBRARY_PATH)`);
}

main().catch((e) => fatal(e?.message ?? String(e)));
