#!/usr/bin/env node
/**
 * Browser-leg proof for the JavaScript bindings.
 *
 * Runs the real browser entry (`bindings/js/universal/dist/browser.js`)
 * and the real loader (`dist/loader.js`) inside a `node:vm` realm with no
 * `process`, `Bun`, or `Deno` globals, so `detectRuntime()` reports
 * `"browser"`. Realm modules resolve through an explicit table:
 * `@sanbus/galley-core` and `@sanbus/galley-wasm/browser` load from the
 * checkout, everything else — notably every native backend and every
 * `node:` builtin — throws loudly instead of loading. Any dynamic
 * `import()` inside the realm throws: the browser graph is static, so
 * browsers never touch FFI through a late import either.
 *
 * What it proves: `galley.loadBytes(bytes)` returns a parser whose
 * sessions parse the shared probe to the same value as the
 * Node/Bun/Deno proofs (15), with no notice — wasm is the browser's
 * only leg; bad sources reject loudly instead of guessing; and the
 * loader's browser guards fail loudly — directory sources cannot
 * resolve and a loader with no seeded legs falls back to nothing but
 * the compile guidance.
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

const UNIVERSAL_BROWSER = pathToFileURL(path.join(universalDir, "dist", "browser.js")).href;
const LOADER_INDEX = pathToFileURL(path.join(universalDir, "dist", "loader.js")).href;
const WASM_BROWSER = pathToFileURL(
  path.join(universalDir, "node_modules", "@sanbus/galley-wasm", "dist", "browser.js"),
).href;

const BARE_MODULES = new Map([
  ["@sanbus/galley-core", pathToFileURL(path.join(universalDir, "node_modules", "@sanbus/galley-core", "dist", "index.js")).href],
  ["@sanbus/galley-core/internal", pathToFileURL(path.join(universalDir, "node_modules", "@sanbus/galley-core", "dist", "internal.js")).href],
  ["@sanbus/galley-wasm/browser", WASM_BROWSER],
]);

const ENTRY_SOURCE = `
import { galley } from ${JSON.stringify(UNIVERSAL_BROWSER)};
import { detectRuntime, resolveSync } from ${JSON.stringify(LOADER_INDEX)};

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
  return { name: "no-throw", message: "loadBytes(string) unexpectedly succeeded" };
}

export function proveGalleySurface() {
  return Object.keys(galley).sort();
}

export function proveDirectoryFails() {
  try {
    resolveSync({ languagePath: "/parsers/language" }, "browser");
  } catch (error) {
    return { name: error?.name ?? "unknown", message: String(error?.message ?? error) };
  }
  return { name: "no-throw", message: "directory resolve unexpectedly succeeded in a browser" };
}

export function proveUnseededBytesFail() {
  try {
    resolveSync({ bytes: new Uint8Array([0]) }, "browser");
  } catch (error) {
    return {
      name: error?.name ?? "unknown",
      code: error?.code ?? null,
      message: String(error?.message ?? error),
    };
  }
  return { name: "no-throw", message: "unseeded loader bytes unexpectedly succeeded" };
}
`;

/** Map an import specifier to a realm URL, or throw for anything outside
 * the browser-reachable closure (native backends and node builtins live
 * here). */
function resolveUrl(specifier, referrer) {
  if (specifier.startsWith("file:")) return specifier;
  if (specifier.startsWith(".")) return new URL(specifier, referrer).href;
  if (BARE_MODULES.has(specifier)) return BARE_MODULES.get(specifier);
  throw new Error(`browser proof: unexpected import ${specifier}`);
}

function readSource(url) {
  return fs.readFileSync(fileURLToPath(url), "utf-8");
}

/** Static dependencies of a module source. Comments are stripped first so
 * prose cannot phantom-link. Dynamic `import()` is a tripwire: no module
 * in the browser graph may use it. */
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

  function dynamicGate() {
    throw new Error("browser proof: unexpected dynamic import");
  }

  function staticLink(specifier, referrer) {
    const url = resolveUrl(specifier, referrer.identifier);
    const module = linked.get(url);
    if (!module) throw new Error(`browser proof: ${url} was never pre-linked`);
    return module;
  }

  // Pre-link one file and its static closure bottom-up, so every module is
  // fully linked before its importers resolve it. Evaluation stays lazy:
  // the entry evaluates its static graph.
  async function preload(url, specifier) {
    if (linked.has(url)) return;
    if (inProgress.has(url)) throw new Error(`browser proof: import cycle through ${url}`);
    inProgress.add(url);
    const source = readSource(url);
    const edges = [...staticDependencies(source)].map((dependency) => ({
      specifier: dependency,
      url: resolveUrl(dependency, url),
    }));
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

  await preload(LOADER_INDEX, LOADER_INDEX);
  await preload(UNIVERSAL_BROWSER, UNIVERSAL_BROWSER);
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
  // Wasm is the browser's only leg: the notice would be noise.
  assert.equal(warnings.length, 0);
});

await test("bad sources reject loudly", async () => {
  const namespace = await loadRealm([]);
  const badBytes = await namespace.proveBadSource();
  assert.equal(badBytes.name, "TypeError");
  assert.match(badBytes.message, /bytes/);
  const directory = namespace.proveDirectoryFails();
  assert.equal(directory.name, "Error");
  assert.match(directory.message, /language directories/);
  const unseeded = namespace.proveUnseededBytesFail();
  assert.equal(unseeded.code, "galley:missing-artifact");
});

await test("browser entry exposes only byte and url loaders", async () => {
  const namespace = await loadRealm([]);
  // Copy out of the realm: its Array has a different prototype.
  assert.deepEqual([...namespace.proveGalleySurface()], ["loadBytes", "loadUrl"]);
});

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
