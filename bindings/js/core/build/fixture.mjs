/**
 * Shared test-fixture builder for the Galley JavaScript bindings.
 *
 * One implementation behind every JS binding suite (node, bun, deno, wasm,
 * universal): each test resolves its parser artifact through
 * `ensureTestLibrary` instead of borrowing a user-facing example build.
 * The fixture grammar (`bindings/js/test-fixture`, verbatim keyvalue
 * sources) is copied to a stable per-scope workdir under the system temp
 * directory and built there with the adapter's own builder, so test runs
 * never read or write `examples/`.
 *
 * - `GALLEY_LIBRARY_PATH`, when set, wins outright (explicit user artifact,
 *   no build). Otherwise the fixture is built and its path returned.
 * - `GALLEY_CHECKOUT`, when unset, defaults to the enclosing Galley
 *   checkout (walk-up from the fixture dir) so `node tests/...` works with
 *   no environment. CI already sets it; then nothing changes.
 * - The workdir path is stable per `scope`, so the builders' content-hash
 *   caches and zig's incremental cache stay warm across runs.
 * - Builder output is captured and shown only on failure.
 */

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const FIXTURE_DIR = path.resolve(HERE, "..", "..", "test-fixture");
const FIXTURE_FILES = ["ll.grm", "config.zig", "procedures.zig", "procedures.ts"];

/** Point at the enclosing checkout when the caller set no explicit one. */
function defaultGalleyCheckout() {
  if (process.env.GALLEY_CHECKOUT) return;
  let directory = FIXTURE_DIR;
  for (let depth = 0; depth < 4; depth++) {
    if (fs.existsSync(path.join(directory, "build.zig"))) {
      process.env.GALLEY_CHECKOUT = directory;
      return;
    }
    directory = path.dirname(directory);
  }
}

/**
 * Return the parser artifact at `GALLEY_LIBRARY_PATH`, or build the shared
 * fixture with `buildCommand` (argv prefix, workdir appended) and return
 * `<workdir>/<libFileName>`. Throws loudly when the build fails.
 */
export function ensureTestLibrary({ buildCommand, libFileName, scope }) {
  if (process.env.GALLEY_LIBRARY_PATH) return process.env.GALLEY_LIBRARY_PATH;
  if (!Array.isArray(buildCommand) || buildCommand.length === 0) {
    throw new Error("galley test fixture: buildCommand must be a non-empty argv array");
  }
  if (!libFileName || !scope) {
    throw new Error("galley test fixture: libFileName and scope are required");
  }
  const workDir = path.join(os.tmpdir(), "galley-js-test", scope);
  fs.mkdirSync(workDir, { recursive: true });
  for (const file of FIXTURE_FILES) {
    fs.copyFileSync(path.join(FIXTURE_DIR, file), path.join(workDir, file));
  }
  defaultGalleyCheckout();
  const [command, ...prefix] = buildCommand;
  const built = spawnSync(command, [...prefix, workDir], { encoding: "utf-8" });
  if (built.error) {
    throw new Error(`galley test fixture: cannot run ${command}: ${built.error.message}`);
  }
  // Deno's node:child_process may return a degenerate result instead of
  // throwing (e.g. spawning without --allow-run): fail loudly here rather
  // than printing "exit undefined" below.
  if (typeof built.status !== "number") {
    throw new Error(
      `galley test fixture: no exit status from ${command}; ` +
        "under Deno the test command needs --allow-run",
    );
  }
  if (built.status !== 0) {
    throw new Error(
      `galley test fixture: build failed for ${workDir} (exit ${built.status})\n${built.stdout ?? ""}${built.stderr ?? ""}`,
    );
  }
  const libPath = path.join(workDir, libFileName);
  if (!fs.existsSync(libPath)) {
    throw new Error(`galley test fixture: expected library not found at ${libPath}`);
  }
  return libPath;
}
