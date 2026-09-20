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
 * - `GALLEY_CHECKOUT` must name the Galley checkout to build against
 *   (CI sets it). Unset is a loud error, never a guess.
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

/** The checkout GALLEY_CHECKOUT names, or a loud error. No guessing. */
function requireGalleyCheckout() {
  const checkout = process.env.GALLEY_CHECKOUT;
  if (!checkout) {
    throw new Error(
      "galley test fixture: set GALLEY_CHECKOUT to a Galley checkout (must contain build.zig)",
    );
  }
  return checkout;
}

/**
 * Build the shared fixture with `buildCommand` (argv prefix, workdir
 * appended) and return the workdir — the language directory sessions
 * open through `languagePath`. Throws loudly when the build fails.
 */
export function ensureTestLibrary({ buildCommand, libFileName, scope }) {
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
  requireGalleyCheckout();
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
  return workDir;
}

/**
 * Make the fixture workdir a real installed Bun consumer so generated
 * entries resolve their `@sanbus` imports through a manager layout.
 * Bun-only: runs `bun install` and the layout it writes is only honored
 * by Bun's resolver. `packages` maps a scope to the workspace directory
 * to pin; each entry becomes a `file:` dependency of the fixture manifest
 * (every other field, including the generated peer declaration, is
 * preserved), then `bun install --linker hoisted` runs in the workdir and
 * writes its lockfile. Stale install output is purged first so repeats
 * never merge with a previous manager layout. The lockfile is the trust
 * anchor: without it Bun bypasses a hand-linked `node_modules` for the
 * global cache. Hoisted with the default backend keeps `file:` resolution
 * on the workspace source, so the entry shares the suite's single adapter
 * realm.
 */
export function installBunFixturePackages({ languageDir, packages }) {
  if (!languageDir) {
    throw new Error("galley test fixture: languageDir is required");
  }
  if (!packages || typeof packages !== "object" || Object.keys(packages).length === 0) {
    throw new Error("galley test fixture: packages must be a non-empty scope-to-directory map");
  }
  fs.rmSync(path.join(languageDir, "node_modules"), { recursive: true, force: true });
  for (const lockfile of ["bun.lock", "package-lock.json"]) {
    fs.rmSync(path.join(languageDir, lockfile), { force: true });
  }
  const manifestPath = path.join(languageDir, "package.json");
  if (!fs.existsSync(manifestPath)) {
    throw new Error(`galley test fixture: no package.json in ${languageDir}; build the fixture first`);
  }
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf-8"));
  manifest.dependencies = {
    ...(manifest.dependencies ?? {}),
    ...Object.fromEntries(
      Object.entries(packages).map(([scope, sourceDirectory]) => [
        `@sanbus/${scope}`,
        `file:${sourceDirectory}`,
      ]),
    ),
  };
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + "\n");
  const installed = spawnSync("bun", ["install", "--linker", "hoisted"], {
    cwd: languageDir,
    encoding: "utf-8",
  });
  if (installed.error) {
    throw new Error(`galley test fixture: cannot run bun install: ${installed.error.message}`);
  }
  if (installed.status !== 0) {
    throw new Error(
      `galley test fixture: install failed for ${languageDir} (exit ${installed.status})\n${installed.stdout ?? ""}${installed.stderr ?? ""}`,
    );
  }
}
