#!/usr/bin/env -S deno run --allow-read --allow-write --allow-run --allow-env
/**
 * Builds a Galley parser and its shared library for a JavaScript consumer
 * on Deno.
 *
 * Usage (from a language directory, e.g. examples/js/deno):
 *   deno task build
 * which runs:
 *   deno run --allow-read --allow-write --allow-run --allow-env \
 *     ../../../bindings/js/deno/build.ts .
 *
 * The language dir must contain ll.grm and may contain config.zig,
 * procedures, ll_error_messages.zig etc, mirroring the other bindings:
 *
 * * `procedures.ts` — JS hooks
 *   (`export function reduction_<Var>(args)` / `export function hook_<name>(args)`),
 *   dispatched through the generated JS shim shared by the Node, Bun, and
 *   Deno adapters (see `galley-js-core/build/shim.mjs`).
 * * `procedures.c` / `procedures.cpp` — legacy C/C++ hooks compiled into the
 *   shared library, exactly like the C/C++ consumers.
 * * `ll_error_messages.zig` / `lr_error_messages.zig` — custom syntax-error
 *   message hooks.
 *
 * The tool generates the parser (--emit-metadata) and builds the shared
 * library through the generic consumer build directly next to the grammar,
 * so `import { Session } from "galley-js-deno"` can locate it via cwd or
 * GALLEY_LIBRARY_PATH.
 *
 * Environment overrides: ZIG_EXECUTABLE (default zig), GALLEY_LIBRARY_PATH,
 *   GALLEY_CHECKOUT (required: existing Galley working tree). To fetch a
 *   checkout for convenience, use examples/scripts/fetch-galley.sh — that
 *   cache is an examples-only convenience, not part of the bindings.
 */

import * as path from "node:path";
import { emitJsProcedureShim } from "../core/build/shim.mjs";

const LIBRARY_NAME = "galley-js-deno";

function fatal(msg: string): never {
  console.error(`galley-bindings: ${msg}`);
  Deno.exit(1);
}

async function run(cmd: string, args: string[], opts: { cwd?: string } = {}): Promise<void> {
  console.log(`+ ${cmd} ${args.map((a) => JSON.stringify(a)).join(" ")}`);
  const out = await new Deno.Command(cmd, {
    args,
    cwd: opts.cwd,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  }).output();
  if (!out.success) fatal(`command failed: ${cmd} ${args.join(" ")} (exit ${out.code})`);
}

function runCapture(cmd: string, args: string[]): string {
  const out = new Deno.Command(cmd, { args, stdout: "piped", stderr: "null" }).outputSync();
  if (!out.success) fatal(`command failed: ${cmd} ${args.join(" ")}`);
  return new TextDecoder().decode(out.stdout);
}

function zigExecutable(): string {
  return Deno.env.get("ZIG_EXECUTABLE") ?? "zig";
}

function exists(filePath: string): boolean {
  try {
    Deno.statSync(filePath);
    return true;
  } catch {
    return false;
  }
}

function resolveGalley(): string {
  // GALLEY_CHECKOUT is required. Fetching a checkout into the system cache
  // is an examples-only convenience (examples/scripts/fetch-galley.sh).
  const checkoutEnv = Deno.env.get("GALLEY_CHECKOUT");
  if (!checkoutEnv) {
    fatal("GALLEY_CHECKOUT is not set; point it at a Galley checkout (examples/scripts/fetch-galley.sh can fetch one)");
  }
  if (!exists(path.join(checkoutEnv, "build.zig"))) {
    fatal(`GALLEY_CHECKOUT=${checkoutEnv} is not a Galley repository checkout (no build.zig)`);
  }
  return path.resolve(checkoutEnv);
}

function awaitRun(cmd: string, args: string[]): void {
  console.log(`+ ${cmd} ${args.map((a) => JSON.stringify(a)).join(" ")}`);
  const out = new Deno.Command(cmd, {
    args,
    stdin: "inherit",
    stdout: "inherit",
    stderr: "inherit",
  }).outputSync();
  if (!out.success) fatal(`command failed: ${cmd} ${args.join(" ")} (exit ${out.code})`);
}

function libFileName(base = LIBRARY_NAME): string {
  if (Deno.build.os === "darwin") return `lib${base}.dylib`;
  if (Deno.build.os === "windows") return `${base}.dll`;
  return `lib${base}.so`;
}

function findJsProceduresFile(languageDir: string): string | null {
  for (const candidate of [path.join(languageDir, "procedures.ts"), path.join(languageDir, "procedures.js")]) {
    try {
      if (exists(candidate) && Deno.statSync(candidate).isFile) return candidate;
    } catch {
      // ignore
    }
  }
  return null;
}

async function main(): Promise<void> {
  if (Deno.args.length !== 1) fatal("usage: deno task build  (runs build.ts <language-dir>)");
  if (Deno.build.os === "windows") fatal("the JavaScript bindings target POSIX platforms");

  const languageDir = path.resolve(Deno.args[0]);
  if (!exists(path.join(languageDir, "ll.grm"))) fatal(`${languageDir} does not contain ll.grm`);

  const galleySource = resolveGalley();
  const cli = path.join(galleySource, "zig-out", "bin", "galley");
  if (!exists(cli)) {
    await run(zigExecutable(), ["build", "-Doptimize=ReleaseFast", "install"], { cwd: galleySource });
  }

  const help = runCapture(cli, ["--help"]);
  if (!help.includes("--emit-metadata")) {
    fatal(
      `the Galley at ${galleySource} is too old for the bindings workflow (no --emit-metadata support); update the checkout`,
    );
  }

  await run(cli, ["--emit-metadata", languageDir]);

  // One library embeds one parser; the consumer build locates the file
  // generation produced from -Dlanguage-dir and infers the family from
  // the filename.
  // JS-native procedures take precedence over C procedures: if a
  // procedures.ts/js exists, generate a JS dispatch shim and use it
  // instead of the C extern stub. When neither JS nor C implementations
  // exist, still generate the JS shim as a no-op fallback so the
  // library links (hooks are simply no-ops until JS registers them via
  // installProcedures), mirroring Python's always-shim model.
  const jsProceduresFile = findJsProceduresFile(languageDir);
  let proceduresZigSource: string | null = null;
  let proceduresCSource: string | null = null;
  const hasCProcedures =
    exists(path.join(languageDir, "procedures.c")) ||
    exists(path.join(languageDir, "procedures.cpp"));
  if (jsProceduresFile !== null) {
    if (hasCProcedures) {
      console.error(`galley-bindings: both JS (${jsProceduresFile}) and C procedures found — using JS`);
    }
    console.error(`galley-bindings: using JS procedures from ${jsProceduresFile}`);
    const shimPath = path.join(languageDir, "procedures_js.zig");
    emitJsProcedureShim(path.join(languageDir, "metadata.json"), shimPath);
    proceduresZigSource = shimPath;
  } else if (hasCProcedures) {
    if (exists(path.join(languageDir, "procedures.zig"))) proceduresZigSource = path.join(languageDir, "procedures.zig");
    if (exists(path.join(languageDir, "procedures.c"))) proceduresCSource = path.join(languageDir, "procedures.c");
    else if (exists(path.join(languageDir, "procedures.cpp"))) {
      proceduresCSource = path.join(languageDir, "procedures.cpp");
    }
  } else {
    if (exists(path.join(languageDir, "procedures.zig"))) {
      const shimPath = path.join(languageDir, "procedures_js.zig");
      emitJsProcedureShim(path.join(languageDir, "metadata.json"), shimPath);
      proceduresZigSource = shimPath;
    }
  }

  const consumerArgs = [
    "build",
    "--build-file",
    path.join(galleySource, "bindings/c/consumer/build.zig"),
    `-Dlanguage-dir=${languageDir}`,
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
  await run(zigExecutable(), consumerArgs, { cwd: galleySource });

  const dest = path.join(languageDir, libFileName());
  if (!exists(dest)) fatal(`expected library not found at ${dest}`);
  console.log(`galley-bindings: built ${dest}; import from ${languageDir} (or set GALLEY_LIBRARY_PATH)`);
}

main();
