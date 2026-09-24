#!/usr/bin/env node
/**
 * Browser-leg proof for the universal loader.
 *
 * Runs the real loader (`bindings/js/universal/dist`) inside a `node:vm`
 * realm with no `process`, `Bun`, or `Deno` globals, so `detectRuntime()`
 * reports `"browser"`. Realm modules resolve through an explicit table:
 * `@sanbus/galley-core` and `@sanbus/galley-wasm` load from the checkout, Node
 * builtins resolve to throwing stubs the bytes path never calls, and
 * anything else (notably every native backend) throws loudly instead of
 * loading. The realm is pre-linked bottom-up so shared modules are fully
 * linked before their importers resolve; dynamic `import()` inside the
 * realm serves only the cached wasm backend and rejects everything else,
 * proving browsers never touch FFI.
 *
 * What it proves: `galley.loadBytes(bytes)` resolves a parser whose
 * sessions parse the shared probe to the same value as the
 * Node/Bun/Deno proofs (15), with the one-time notice, and bad sources
 * reject loudly instead of guessing.
 *
 * Run:
 *   GALLEY_CHECKOUT=/path/to/galley node --experimental-vm-modules bindings/js/universal/tests/test_loader_browser.mjs
 *
 * Uses the shared wasm fixture (bindings/js/test-fixture), built on demand
 * with the wasm builder into a temp workdir.
 */

import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import vm from "node:vm";
import { TextDecoder, TextEncoder } from "node:util";
import { wasmArtifactFileName } from "@sanbus/galley-core/internal";
import { ensureTestLibrary } from "../../../js/core/build/fixture.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..", "..", "..", "..");
const universalDir = path.resolve(__dirname, "..");
// Self-built shared fixture (bindings/js/test-fixture); never examples/.
const wasmDir = ensureTestLibrary({
  buildCommand: ["node", path.join(repoRoot, "bindings", "js", "wasm", "build.mjs")],
  libFileName: wasmArtifactFileName("galley-js-wasm"),
  scope: "wasm",
});
const wasmBytes = new Uint8Array(
  fs.readFileSync(path.join(wasmDir, wasmArtifactFileName("galley-js-wasm"))),
);

const UNIVERSAL_INDEX = pathToFileURL(path.join(universalDir, "dist", "index.js")).href;
const WASM_INDEX = pathToFileURL(
  path.join(universalDir, "node_modules", "@sanbus/galley-wasm", "dist", "index.js"),
).href;

const BARE_MODULES = new Map([
  ["@sanbus/galley-core", pathToFileURL(path.join(universalDir, "node_modules", "@sanbus/galley-core", "dist", "index.js")).href],
  ["@sanbus/galley-core/internal", pathToFileURL(path.join(universalDir, "node_modules", "@sanbus/galley-core", "dist", "internal.js")).href],
  ["@sanbus/galley-wasm", WASM_INDEX],
]);

const STUB_SOURCES = new Map([
  ["node:module", `export function createRequire() { throw new Error("browser proof: createRequire is unreachable"); }`],
  ["node:process", `export default undefined;`],
  ["node:fs", `export function accessSync() { throw new Error("browser proof: fs is unreachable"); }\nexport function readFileSync() { throw new Error("browser proof: fs is unreachable"); }`],
  ["node:path", `export function resolve() { throw new Error("browser proof: path is unreachable"); }\nexport function join() { throw new Error("browser proof: path is unreachable"); }\nexport function dirname() { throw new Error("browser proof: path is unreachable"); }`],
]);

const ENTRY_SOURCE = `
import { detectRuntime, galley, openLanguageDirectory } from ${JSON.stringify(UNIVERSAL_INDEX)};

export async function prove(bytesInput) {
  const runtime = detectRuntime();
  const parser = await galley.loadBytes(bytesInput);
  const session = await parser.openSession();
  let parsed;
  let version;
  let backend;
  let sessionBackend;
  try {
    parsed = session.parse("alpha:12,beta:3");
    version = parser.version();
    backend = parser.backend;
    sessionBackend = session.backend;
  } finally {
    session.close();
  }
  return { runtime, backend, sessionBackend, parsed, version };
}

export async function proveBadSource() {
  try {
    await galley.loadBytes("not-bytes");
  } catch (error) {
    return { name: error?.name ?? "unknown", message: String(error?.message ?? error) };
  }
  return { name: "no-throw", message: "fromBytes(string) unexpectedly succeeded" };
}

export async function proveDirectoryFails() {
  try {
    await openLanguageDirectory("/parsers/language");
  } catch (error) {
    return { name: error?.name ?? "unknown", message: String(error?.message ?? error) };
  }
  return { name: "no-throw", message: "fromDirectory unexpectedly succeeded in a browser" };
}
`;

/** Map an import specifier to a realm URL, or throw for anything outside
 * the browser-reachable closure (native backends live here). */
function resolveUrl(specifier, referrer) {
  if (specifier.startsWith("file:")) return specifier;
  if (specifier.startsWith(".")) return new URL(specifier, referrer).href;
  if (BARE_MODULES.has(specifier)) return BARE_MODULES.get(specifier);
  if (STUB_SOURCES.has(specifier)) return `stub:${specifier}`;
  throw new Error(`browser proof: unexpected import ${specifier}`);
}

function readSource(url, specifier) {
  if (url.startsWith("stub:")) return STUB_SOURCES.get(specifier);
  return fs.readFileSync(fileURLToPath(url), "utf-8");
}

/** Static dependencies of a module source. Comments are stripped first so
 * prose cannot phantom-link. Variable `import(name)` calls (the loader's
 * backend loading) are runtime concerns, handled by the dynamic gate. */
function staticDependencies(source) {
  const code = source.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|\s)\/\/[^\n]*/g, "");
  const found = new Set();
  for (const pattern of [/(?:import|export)[^'";]*?from\s*['"]([^'"]+)['"]/g, /import\s*['"]([^'"]+)['"]/g]) {
    for (const match of code.matchAll(pattern)) found.add(match[1]);
  }
  return found;
}

async function loadRealm(warnings) {
  const sandbox = {
    console: {
      warn: (message) => warnings.push(String(message)),
      error: (...args) => console.error(...args),
      log: (...args) => console.log(...args),
    },
    TextEncoder,
    TextDecoder,
    crypto: globalThis.crypto,
  };
  const context = vm.createContext(sandbox);
  const linked = new Map();
  const inProgress = new Set();
  const staticEdges = new Map();

  function dynamicGate(specifier) {
    if (specifier === "@sanbus/galley-wasm") return ensureEvaluated(WASM_INDEX);
    throw new Error(`browser proof: unexpected dynamic import ${specifier}`);
  }

  // Evaluate one module after its static closure. Node serves a
  // gate-returned module as-is, so the gate evaluates the wasm backend on
  // first dynamic import, mirroring browser timing exactly.
  async function ensureEvaluated(url) {
    const module = linked.get(url);
    if (!module) throw new Error(`browser proof: ${url} was never pre-linked`);
    if (module.status !== "linked") return module;
    for (const dependency of staticEdges.get(url) ?? []) {
      await ensureEvaluated(dependency);
    }
    await module.evaluate();
    return module;
  }

  function staticLink(specifier, referrer) {
    const url = resolveUrl(specifier, referrer.identifier);
    const module = linked.get(url);
    if (!module) throw new Error(`browser proof: ${url} was never pre-linked`);
    return module;
  }

  // Pre-link one file and its static closure bottom-up, so every module is
  // fully linked before its importers resolve it. Evaluation stays lazy:
  // the entry evaluates its static graph, the gate evaluates the wasm
  // backend on first dynamic import.
  async function preload(url, specifier) {
    if (linked.has(url)) return;
    if (inProgress.has(url)) throw new Error(`browser proof: import cycle through ${url}`);
    inProgress.add(url);
    const source = readSource(url, specifier);
    const edges = [...staticDependencies(source)].map((dependency) => ({
      specifier: dependency,
      url: resolveUrl(dependency, url),
    }));
    staticEdges.set(
      url,
      edges.map((edge) => edge.url),
    );
    for (const edge of edges) {
      await preload(edge.url, edge.specifier);
    }
    const module = new vm.SourceTextModule(source, {
      identifier: url,
      context,
      importModuleDynamically: async (dynamicSpecifier) => dynamicGate(dynamicSpecifier),
    });
    await module.link(staticLink);
    linked.set(url, module);
    inProgress.delete(url);
  }

  await preload(WASM_INDEX, "@sanbus/galley-wasm");
  await preload(UNIVERSAL_INDEX, UNIVERSAL_INDEX);
  const entry = new vm.SourceTextModule(ENTRY_SOURCE, {
    identifier: "browser-proof:entry",
    context,
    importModuleDynamically: async (dynamicSpecifier) => dynamicGate(dynamicSpecifier),
  });
  await entry.link(staticLink);
  await entry.evaluate();
  return entry.namespace;
}

let passed = 0;
let failed = 0;

async function test(name, fn) {
  const warnings = [];
  try {
    await fn(warnings);
    console.log(`✓ ${name}`);
    passed++;
  } catch (error) {
    console.error(`✗ ${name}`);
    console.error(error);
    failed++;
  }
}

await test("detectRuntime reports browser and bytes sessions parse", async (warnings) => {
  const namespace = await loadRealm(warnings);
  const result = await namespace.prove(wasmBytes);
  assert.equal(result.runtime, "browser");
  assert.equal(result.backend, "wasm");
  assert.equal(result.sessionBackend, "wasm");
  assert.equal(result.parsed, 15);
  assert.ok(result.version.length > 0);
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /WebAssembly/);
});

await test("bad sources reject loudly", async () => {
  const namespace = await loadRealm([]);
  const badBytes = await namespace.proveBadSource();
  assert.equal(badBytes.name, "TypeError");
  assert.match(badBytes.message, /bytes/);
  const directory = await namespace.proveDirectoryFails();
  assert.equal(directory.name, "Error");
  assert.match(directory.message, /language directories/);
});

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
