#!/usr/bin/env node
/**
 * Builds the Try-it page parsers (`docs/public/try-it/*.wasm`) from
 * `docs/try-it/lang/<name>` through the stock wasm builder, one module
 * per language.
 *
 * GALLEY_CHECKOUT is honored when set and validated like every other
 * builder; when unset, the enclosing checkout is used and said loudly.
 * Needs zig and an installed+built bindings/js/wasm (both fail loudly
 * inside the builder when missing).
 */

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const docsDir = path.resolve(__dirname, "..");
const repoRoot = path.resolve(docsDir, "..");
const languagesDir = path.join(docsDir, "try-it", "lang");
const publicDir = path.join(docsDir, "public", "try-it");

function fatal(message) {
  console.error(`docs:wasm: ${message}`);
  process.exit(1);
}

let checkout = process.env.GALLEY_CHECKOUT;
if (checkout) {
  checkout = path.resolve(checkout);
  if (!fs.existsSync(path.join(checkout, "build.zig"))) {
    fatal(`GALLEY_CHECKOUT=${checkout} is not a Galley checkout (no build.zig)`);
  }
} else {
  checkout = repoRoot;
  console.log(`docs:wasm: GALLEY_CHECKOUT unset; using enclosing checkout ${checkout}`);
}

const buildScript = path.join(checkout, "bindings", "js", "wasm", "build.mjs");
const languages = fs
  .readdirSync(languagesDir, { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name)
  .sort();
if (languages.length === 0) fatal(`no languages in ${languagesDir}`);

fs.mkdirSync(publicDir, { recursive: true });
for (const language of languages) {
  const languageDir = path.join(languagesDir, language);
  if (!fs.existsSync(path.join(languageDir, "ll.grm"))) {
    fatal(`${languageDir} does not contain ll.grm`);
  }
  console.log(`+ node ${buildScript} ${languageDir}`);
  const built = spawnSync("node", [buildScript, languageDir], {
    stdio: "inherit",
    env: { ...process.env, GALLEY_CHECKOUT: checkout },
  });
  if (built.error) fatal(`cannot run node: ${built.error.message}`);
  if (built.status !== 0) fatal(`wasm builder failed for ${language} (exit ${built.status})`);

  const produced = fs.readdirSync(languageDir).filter((name) => name.endsWith(".wasm"));
  if (produced.length !== 1) {
    fatal(`expected exactly one .wasm in ${languageDir}, found ${produced.length}`);
  }
  const target = path.join(publicDir, `${language}.wasm`);
  fs.copyFileSync(path.join(languageDir, produced[0]), target);
  console.log(`docs:wasm: wrote ${target}`);
}
