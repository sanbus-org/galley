/**
 * Behavioral tests for the universal loader under Deno.
 *
 * Mirrors `tests/test_loader.mjs` (Node) through the Deno native adapter:
 * native-first resolution, wasm pinning, and the `await init()` + cached
 * `Session` pattern (synchronous construction is Node/Bun-only, so every
 * `Session` here follows an `init()` that warms the loader cache).
 *
 * Run:
 *   GALLEY_CHECKOUT=/path/to/galley deno task test
 *
 * Uses the shared fixture (bindings/js/test-fixture), built on demand
 * with the deno and wasm builders into a temp workdir.
 */

import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { artifactFileName } from "../../core/src/artifact.ts";
import { wasmArtifactFileName } from "../../core/src/artifact.ts";
import { ensureTestLibrary } from "../../../js/core/build/fixture.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..", "..", "..", "..");
// Self-built shared fixture (bindings/js/test-fixture); never examples/.
const nativeLib = ensureTestLibrary({
  buildCommand: [
    "deno",
    "run",
    "--allow-read",
    "--allow-write",
    "--allow-run",
    "--allow-env",
    path.join(__dirname, "..", "..", "deno", "build.ts"),
  ],
  libFileName: artifactFileName("galley-js-deno", Deno.build.os),
  scope: "deno",
});
const wasmModule = ensureTestLibrary({
  buildCommand: ["node", path.join(repoRoot, "bindings", "js", "wasm", "build.mjs")],
  libFileName: wasmArtifactFileName("galley-js-wasm"),
  scope: "wasm",
});

import { init, backend, detectRuntime, Session, version } from "../src/index.ts";
import { __resetLoader as resetLoader } from "../src/loader.ts";
import { findLibrary as findNativeLibrary } from "../../deno/src/index.ts";
import { findLibrary as findWasmLibrary } from "../../wasm/src/index.ts";

let passed = 0;
let failed = 0;
let skipped = 0;

class SkipTest extends Error {}

async function test(name: string, fn: () => void | Promise<void>) {
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

function skip(name: string, reason: string): never {
  throw new SkipTest(`${name} (skip: ${reason})`);
}

/** A native artifact is discoverable (warm checkout): fallback tests that
 * need it missing skip instead of failing. */
function nativeDiscoverable(): boolean {
  try {
    return fs.existsSync(findNativeLibrary());
  } catch {
    return false;
  }
}

function wasmDiscoverable(): boolean {
  try {
    return fs.existsSync(findWasmLibrary());
  } catch {
    return false;
  }
}

async function silenceWarnAsync<T>(fn: () => T): Promise<{ result: T; lines: string[] }> {
  const original = console.warn;
  const lines: string[] = [];
  console.warn = (message: unknown) => lines.push(String(message));
  try {
    const result = await fn();
    return { result, lines };
  } finally {
    console.warn = original;
  }
}

await test("detectRuntime reports deno", () => {
  assert.equal(detectRuntime(), "deno");
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
    init({ libraryPath: "/nonexistent/x.so", wasmPath: wasmModule })
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

await test("Session follows init through the loader cache", async () => {
  await init({ libraryPath: nativeLib });
  const session = new Session();
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
