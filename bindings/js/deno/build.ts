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
 * The tool generates the parser (--emit-metadata), builds the shared library
 * through the generic consumer build, and copies libgalley-js-deno.* into
 * the language directory so `import { Session } from "galley-js-deno"`
 * can locate it via cwd or GALLEY_LIBRARY_PATH.
 *
 * Environment overrides: ZIG_EXECUTABLE (default zig), GALLEY_LIBRARY_PATH,
 *   GALLEY_CHECKOUT (existing Galley working tree, wins over fetching),
 *   GALLEY_REPOSITORY, GALLEY_TAG (default main). Without GALLEY_CHECKOUT
 *   the script clones GALLEY_REPOSITORY at GALLEY_TAG, matching the Rust,
 *   Go, and Python consumers.
 */

import * as path from "node:path";
import { createHash } from "node:crypto";
import { emitJsProcedureShim } from "../core/build/shim.mjs";

const LIBRARY_NAME = "galley-js-deno";
const DEFAULT_GALLEY_REPOSITORY = "https://github.com/sanbus-org/galley.git";
const DEFAULT_GALLEY_TAG = "main";

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

function cacheDir(): string {
  const home = Deno.env.get("HOME") ?? "/tmp";
  let dir: string;
  if (Deno.build.os === "darwin") dir = path.join(home, "Library", "Caches");
  else if (Deno.build.os === "windows") dir = Deno.env.get("LOCALAPPDATA") ?? Deno.tmpdir();
  else dir = Deno.env.get("XDG_CACHE_HOME") ?? path.join(home, ".cache");
  dir = path.join(dir, "galley-bindings", "js-deno");
  Deno.mkdirSync(dir, { recursive: true });
  return dir;
}

function resolveGalley(cacheDirPath: string): string {
  // GALLEY_CHECKOUT wins; otherwise clone GALLEY_REPOSITORY at GALLEY_TAG
  // into <cache>/galley-src.
  const checkoutEnv = Deno.env.get("GALLEY_CHECKOUT");
  if (checkoutEnv) {
    if (!exists(path.join(checkoutEnv, "build.zig"))) {
      fatal(`GALLEY_CHECKOUT=${checkoutEnv} is not a Galley repository checkout (no build.zig)`);
    }
    return path.resolve(checkoutEnv);
  }
  const tag = Deno.env.get("GALLEY_TAG") ?? DEFAULT_GALLEY_TAG;
  const repository = Deno.env.get("GALLEY_REPOSITORY") ?? DEFAULT_GALLEY_REPOSITORY;
  const sourceDir = path.join(cacheDirPath, "galley-src");
  const stamp = path.join(cacheDirPath, "galley-tag");
  let previous = "";
  try {
    if (exists(stamp)) previous = Deno.readTextFileSync(stamp).trim();
  } catch {
    // ignore
  }
  if (exists(sourceDir) && previous === tag) return sourceDir;
  try {
    Deno.removeSync(sourceDir, { recursive: true });
  } catch {
    // ignore
  }
  awaitRun("git", ["clone", "--depth", "1", "--branch", tag, "--single-branch", "--recurse-submodules=false", repository, sourceDir]);
  try {
    Deno.writeTextFileSync(stamp, tag);
  } catch (e) {
    fatal(`failed to write tag stamp: ${(e as Error).message}`);
  }
  return sourceDir;
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

function detectParser(languageDir: string): [string, string] {
  const hasLL = exists(path.join(languageDir, "_ll-parser.zig"));
  const hasLR = exists(path.join(languageDir, "_lr-parser.zig"));
  if (hasLL && !hasLR) return ["_ll-parser.zig", "ll"];
  if (hasLR && !hasLL) return ["_lr-parser.zig", "lr"];
  if (hasLL && hasLR) {
    fatal(
      `both _ll-parser.zig and _lr-parser.zig exist in ${languageDir}; one library embeds one parser — split the language dirs`,
    );
  }
  fatal(`generation produced no parser in ${languageDir}`);
  throw new Error("unreachable");
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

  const galleySource = resolveGalley(cacheDir());
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

  const [parserSource, parserType] = detectParser(languageDir);

  const prefix = path.join(
    cacheDir(),
    "capi",
    createHash("sha256").update(languageDir).digest("hex").slice(0, 16),
  );
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
    emitJsProcedureShim(path.join(languageDir, "procedures.zig"), shimPath);
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
      emitJsProcedureShim(path.join(languageDir, "procedures.zig"), shimPath);
      proceduresZigSource = shimPath;
    }
  }

  const consumerArgs = [
    "build",
    "--build-file",
    path.join(galleySource, "bindings/c/consumer/build.zig"),
    `-Dparser-source=${path.join(languageDir, parserSource)}`,
    `-Dparser-type=${parserType}`,
    `-Dlib-name=${LIBRARY_NAME}`,
    "-Doptimize=ReleaseFast",
    "--prefix",
    prefix,
    "install",
  ];
  if (proceduresZigSource !== null) {
    consumerArgs.splice(consumerArgs.length - 1, 0, `-Dprocedures-zig-source=${proceduresZigSource}`);
  }
  if (proceduresCSource !== null) {
    consumerArgs.splice(consumerArgs.length - 1, 0, `-Dprocedures-c-source=${proceduresCSource}`);
  }
  const errMsgCandidate = path.join(languageDir, `${parserType}_error_messages.zig`);
  if (exists(errMsgCandidate)) {
    consumerArgs.splice(consumerArgs.length - 1, 0, `-Derror-messages-zig-source=${errMsgCandidate}`);
  }
  await run(zigExecutable(), consumerArgs, { cwd: galleySource });

  const builtLib = path.join(prefix, "lib", libFileName());
  if (!exists(builtLib)) fatal(`expected library not found at ${builtLib}`);

  // Copy into language dir for cwd-based discovery.
  const dest = path.join(languageDir, libFileName());
  Deno.copyFileSync(builtLib, dest);
  console.log(`galley-bindings: built ${dest}; import from ${languageDir} (or set GALLEY_LIBRARY_PATH)`);
  console.log(`  cache: ${builtLib}`);
}

main();
