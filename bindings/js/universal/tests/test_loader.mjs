#!/usr/bin/env node
/**
 * Behavioral tests for the universal loader.
 *
 * Run:
 *   node bindings/js/universal/tests/test_loader.mjs
 *
 * Uses the shared fixture (bindings/js/test-fixture), built on demand
 * with the node and wasm builders into a temp workdir.
 */

import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { artifactFileName, wasmArtifactFileName } from "@sanbus/galley-core";
import { ensureTestLibrary } from "../../../js/core/build/fixture.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..", "..", "..", "..");
// Self-built shared fixture (bindings/js/test-fixture); never examples/.
const nativeLib = ensureTestLibrary({
  buildCommand: ["node", path.join(repoRoot, "bindings", "js", "node", "build.mjs")],
  libFileName: artifactFileName("galley-js-node", process.platform),
  scope: "node",
});
const wasmModule = ensureTestLibrary({
  buildCommand: ["node", path.join(repoRoot, "bindings", "js", "wasm", "build.mjs")],
  libFileName: wasmArtifactFileName("galley-js-wasm"),
  scope: "wasm",
});

const { init, backend, detectRuntime, Session, version } = await import("../dist/index.js");
const browserEntry = await import("../dist/browser.js");
const { __resetLoader: resetLoader } = await import("../dist/loader.js");
const { findLibrary: findNativeLibrary } = await import("@sanbus/galley-node");
const { findLibrary: findWasmLibrary } = await import("@sanbus/galley-wasm");

let passed = 0;
let failed = 0;
let skipped = 0;

class SkipTest extends Error {}

async function test(name, fn) {
  resetLoader();
  try {
    await fn();
    console.log(`✓ ${name}`);
    passed++;
  } catch (e) {
    if (e instanceof SkipTest) {
      console.log(`- ${e.message}`);
      skipped++;
      return;
    }
    console.error(`✗ ${name}`);
    console.error(e);
    failed++;
  }
}

function skip(name, reason) {
  throw new SkipTest(`${name} (skip: ${reason})`);
}

/** A native artifact is discoverable (warm checkout): fallback tests that
 * need it missing skip instead of failing. */
function nativeDiscoverable() {
  try {
    return fs.existsSync(findNativeLibrary());
  } catch {
    return false;
  }
}

function wasmDiscoverable() {
  try {
    return fs.existsSync(findWasmLibrary());
  } catch {
    return false;
  }
}

async function silenceWarnAsync(fn) {
  const original = console.warn;
  const lines = [];
  console.warn = (message) => lines.push(String(message));
  try {
    const result = await fn();
    return { result, lines };
  } finally {
    console.warn = original;
  }
}

await test("detectRuntime reports node", () => {
  assert.equal(detectRuntime(), "node");
});

await test("init resolves the native backend for an explicit library", async () => {
  const { result, lines } = await silenceWarnAsync(() => init({ libraryPath: nativeLib }));
  await result;
  assert.equal(backend(), "native");
  assert.equal(lines.length, 0);
  assert.ok(version().length > 0);
  const session = new Session();
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("explicit .wasm path pins the wasm backend with notice", async () => {
  const { result, lines } = await silenceWarnAsync(() => init({ libraryPath: wasmModule }));
  await result;
  assert.equal(backend(), "wasm");
  assert.equal(lines.length, 1);
  assert.match(lines[0], /WebAssembly/);
  const session = new Session();
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("missing native falls back to explicit wasm", async () => {
  if (nativeDiscoverable()) {
    skip("missing native falls back to explicit wasm", "native artifact discoverable in this checkout");
    return;
  }
  const { result, lines } = await silenceWarnAsync(() =>
    init({ libraryPath: "/nonexistent/x.so", wasmPath: wasmModule }),
  );
  await result;
  assert.equal(backend(), "wasm");
  assert.equal(lines.length, 1);
  const session = new Session();
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("missing everything explains how to build", async () => {
  if (nativeDiscoverable() || wasmDiscoverable()) {
    skip("missing everything explains how to build", "artifacts discoverable in this checkout");
    return;
  }
  await assert.rejects(init({ libraryPath: "/nonexistent/x.so" }), /Build one first/);
  assert.equal(backend(), null);
});

await test("quiet suppresses the fallback notice", async () => {
  const { result, lines } = await silenceWarnAsync(() => init({ libraryPath: wasmModule, quiet: true }));
  await result;
  assert.equal(backend(), "wasm");
  assert.equal(lines.length, 0);
});

await test("Session resolves synchronously without init", () => {
  const session = new Session({ libraryPath: nativeLib });
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("default discovery honors GALLEY_LIBRARY_PATH", async () => {
  const previous = process.env.GALLEY_LIBRARY_PATH;
  process.env.GALLEY_LIBRARY_PATH = nativeLib;
  try {
    await init();
    assert.equal(backend(), "native");
  } finally {
    if (previous === undefined) delete process.env.GALLEY_LIBRARY_PATH;
    else process.env.GALLEY_LIBRARY_PATH = previous;
  }
});

/** Transitive local `.js` closure of a dist entry (bare specifiers excluded,
 * except the pinned `@sanbus/galley-wasm/browser` subpath edge). */
function transitiveLocalJs(root) {
  const wasmBrowser = path.join(repoRoot, "bindings", "js", "wasm", "dist", "browser.js");
  const seen = new Set();
  const visit = (file) => {
    if (seen.has(file)) return;
    seen.add(file);
    const text = fs.readFileSync(file, "utf-8");
    for (const match of text.matchAll(/(?:from\s+|import\(\s*)["']([^"']+)["']/g)) {
      const specifier = match[1];
      if (specifier === "@sanbus/galley-wasm/browser") visit(wasmBrowser);
      else if (specifier.startsWith(".")) visit(path.resolve(path.dirname(file), specifier));
    }
  };
  visit(root);
  return seen;
}

await test("browser entry parses from bytes with notice", async () => {
  browserEntry.__resetLoader();
  const bytes = new Uint8Array(fs.readFileSync(wasmModule));
  const { result, lines } = await silenceWarnAsync(() => browserEntry.init({ wasmBytes: bytes }));
  await result;
  assert.equal(browserEntry.backend(), "wasm");
  assert.equal(lines.length, 1);
  assert.match(lines[0], /WebAssembly/);
  const session = new browserEntry.Session();
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("loader resolves adapters only through seeded legs", () => {
  const text = fs.readFileSync(path.join(__dirname, "..", "dist", "loader.js"), "utf-8");
  for (const match of text.matchAll(/(?:from\s+|import\(\s*)["']([^"']+)["']/g)) {
    assert.ok(
      !match[1].startsWith("node:") &&
        !match[1].startsWith("@sanbus/galley-node") &&
        !match[1].startsWith("@sanbus/galley-bun") &&
        !match[1].startsWith("@sanbus/galley-deno") &&
        !match[1].startsWith("@sanbus/galley-wasm"),
      `loader.js statically resolves ${match[1]} (must arrive via seedEngineLegs)`,
    );
  }
  assert.ok(text.includes("seedEngineLegs"), "loader.js must expose seedEngineLegs");
  assert.ok(
    !/import\s*\(/.test(text),
    "loader.js must contain no dynamic import (adapters arrive only via seedEngineLegs)",
  );
});

await test("browser entries have no node: specifiers", () => {
  const roots = [
    path.join(__dirname, "..", "dist", "browser.js"),
    path.join(repoRoot, "bindings", "js", "wasm", "dist", "browser.js"),
    path.join(repoRoot, "bindings", "js", "core", "dist", "index.js"),
  ];
  // The cross-package edge must stay an explicit subpath: a bare
  // "@sanbus/galley-wasm" would only resolve to the browser file when the
  // bundler also applies that package's browser condition.
  const universalBrowser = fs.readFileSync(roots[0], "utf-8");
  assert.ok(
    universalBrowser.includes('"@sanbus/galley-wasm/browser"'),
    "universal browser entry must import the explicit wasm browser subpath",
  );
  for (const root of roots) {
    for (const file of transitiveLocalJs(root)) {
      const text = fs.readFileSync(file, "utf-8");
      for (const match of text.matchAll(/(?:from\s+|import\(\s*)["']([^"']+)["']/g)) {
        assert.ok(
          !match[1].startsWith("node:"),
          `${file} references ${match[1]} (unresolvable in browser graphs)`,
        );
      }
    }
  }
});

console.log(`\n${passed} passed, ${failed} failed, ${skipped} skipped`);
process.exit(failed === 0 ? 0 : 1);
