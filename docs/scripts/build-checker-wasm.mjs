#!/usr/bin/env node
/**
 * Builds the Try-it page parsers (`docs/public/try-it/*.wasm`) from
 * `docs/try-it/lang/<name>` through the stock wasm builder.
 *
 * Each language directory holds one grammar and its hooks setup (no AST,
 * procedures on) and compiles twice: `<name>.wasm` from the directory
 * itself, and `<name>-ast.wasm` (AST on, procedures off) from a scratch
 * copy whose `config.zig` carries exactly three flipped constants. The
 * tracked config is never rewritten; the AST build inherits everything
 * else, so the two builds cannot drift apart.
 *
 * GALLEY_CHECKOUT is honored when set and validated like every other
 * builder; when unset, the enclosing checkout is used and said loudly.
 * Needs zig and an installed+built bindings/js/wasm (both fail loudly
 * inside the builder when missing).
 */

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
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

// The AST twin's whole config delta: everything else is inherited from
// the language's own config, so a single grammar can never pair with a
// stale AST setup.
function flipAstConfig(configPath) {
  let text = fs.readFileSync(configPath, "utf8");
  const flip = (from, to) => {
    if (!text.includes(from)) fatal(`${configPath} lacks \`${from}\` (not a hooks setup?)`);
    text = text.replace(from, to);
  };
  flip("pub const ast = false;", "pub const ast = true;");
  flip("pub const procedures = true;", "pub const procedures = false;");
  if (text.includes("pub const allow_no_ast_tree_procedures = true;")) {
    text = text.replace(
      "pub const allow_no_ast_tree_procedures = true;",
      "pub const allow_no_ast_tree_procedures = false;",
    );
  }
  fs.writeFileSync(configPath, text);
}

function buildOne(sourceDir, outName) {
  console.log(`+ node ${buildScript} ${sourceDir}`);
  const built = spawnSync("node", [buildScript, sourceDir], {
    stdio: "inherit",
    env: { ...process.env, GALLEY_CHECKOUT: checkout },
  });
  if (built.error) fatal(`cannot run node: ${built.error.message}`);
  if (built.status !== 0) fatal(`wasm builder failed for ${sourceDir} (exit ${built.status})`);

  const produced = fs.readdirSync(sourceDir).filter((name) => name.endsWith(".wasm"));
  if (produced.length !== 1) {
    fatal(`expected exactly one .wasm in ${sourceDir}, found ${produced.length}`);
  }
  const target = path.join(publicDir, outName);
  fs.copyFileSync(path.join(sourceDir, produced[0]), target);
  console.log(`docs:wasm: wrote ${target}`);
}

fs.mkdirSync(publicDir, { recursive: true });
for (const language of languages) {
  const languageDir = path.join(languagesDir, language);
  if (!fs.existsSync(path.join(languageDir, "ll.grm"))) {
    fatal(`${languageDir} does not contain ll.grm`);
  }
  if (!fs.existsSync(path.join(languageDir, "config.zig"))) {
    fatal(`${languageDir} does not contain config.zig`);
  }
  buildOne(languageDir, `${language}.wasm`);

  const staging = fs.mkdtempSync(path.join(os.tmpdir(), `try-it-${language}-ast-`));
  try {
    fs.cpSync(languageDir, staging, { recursive: true });
    flipAstConfig(path.join(staging, "config.zig"));
    buildOne(staging, `${language}-ast.wasm`);
  } finally {
    fs.rmSync(staging, { recursive: true, force: true });
  }
}
