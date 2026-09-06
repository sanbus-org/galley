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
import { ensureTestLibrary } from "../../../js/core/build/fixture.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..", "..", "..", "..");
// Self-built shared fixture (bindings/js/test-fixture); never examples/.
const nativeLib = ensureTestLibrary({
  buildCommand: ["node", path.join(repoRoot, "bindings", "js", "node", "build.mjs")],
  libFileName:
    process.platform === "darwin" ? "libgalley-js-node.dylib" : "libgalley-js-node.so",
  scope: "node",
});
const wasmModule = ensureTestLibrary({
  buildCommand: ["node", path.join(repoRoot, "bindings", "js", "wasm", "build.mjs")],
  libFileName: "libgalley-js-wasm.wasm",
  scope: "wasm",
});

const { init, backend, detectRuntime, Session, version } = await import("../dist/index.js");
const { __resetLoader: resetLoader } = await import("../dist/loader.js");
const { findLibrary: findNativeLibrary } = await import("galley-js-node");
const { findLibrary: findWasmLibrary } = await import("galley-js-wasm");

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

console.log(`\n${passed} passed, ${failed} failed, ${skipped} skipped`);
process.exit(failed === 0 ? 0 : 1);
