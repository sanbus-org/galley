/**
 * Behavioral tests for the universal loader under Deno.
 *
 * Mirrors `tests/test_loader.mjs` (Node) through the Deno native adapter:
 * native-first resolution, wasm pinning, and explicit `procedures`
 * (there is no synchronous module scan on this runtime). Sessions come
 * from async factories on every runtime.
 *
 * Run:
 *   GALLEY_CHECKOUT=/path/to/galley deno task test
 *
 * Uses the shared fixture (bindings/js/test-fixture), built on demand
 * with the deno and wasm builders into temp workdirs; sessions open
 * them through async factories.
 */

import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { artifactFileName, SHARED_NATIVE_LIBRARY_BASE } from "../../core/src/artifact.ts";
import { wasmArtifactFileName } from "../../core/src/artifact.ts";
import { ensureTestLibrary } from "../../../js/core/build/fixture.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..", "..", "..", "..");
// Self-built shared fixture (bindings/js/test-fixture); never examples/.
const nativeDir = ensureTestLibrary({
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
const wasmDir = ensureTestLibrary({
  buildCommand: ["node", path.join(repoRoot, "bindings", "js", "wasm", "build.mjs")],
  libFileName: wasmArtifactFileName("galley-js-wasm"),
  scope: "wasm",
});
// The real-world `galley build` output: only the shared native library
// (plus wasm), no adapter-named file. Sessions on every native runtime
// must resolve native here — this is the CI parity path.
const sharedDir = ensureTestLibrary({
  buildCommand: ["node", path.join(repoRoot, "bindings", "js", "universal", "build.mjs"), "build"],
  libFileName: artifactFileName(SHARED_NATIVE_LIBRARY_BASE, Deno.build.os),
  scope: "universal",
});

import { detectRuntime, Session } from "../src/index.ts";
import { __resetLoader as resetLoader } from "../src/loader.ts";

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

await test("factories validate their source", async () => {
  await assert.rejects(Session.fromDirectory(""), /languagePath/);
  await assert.rejects(Session.fromFile(""), /filePath/);
  await assert.rejects(Session.fromBytes("not-bytes" as unknown as Uint8Array), /bytes/);
  await assert.rejects(Session.fromUrl(42 as unknown as string), /URL/);
});

await test("fromBytes resolves a usable session", async () => {
  const bytes = new Uint8Array(Deno.readFileSync(`${wasmDir}/libgalley-js-wasm.wasm`));
  const session = await Session.fromBytes(bytes, { quiet: true });
  try {
    assert.equal(session.backend, "wasm");
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("fromUrl resolves a usable session", async () => {
  const bytes = new Uint8Array(Deno.readFileSync(`${wasmDir}/libgalley-js-wasm.wasm`));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  const session = await Session.fromUrl(`data:application/wasm;base64,${btoa(binary)}`, { quiet: true });
  try {
    assert.equal(session.backend, "wasm");
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("garbage bytes reject loudly", async () => {
  await assert.rejects(Session.fromBytes(new Uint8Array([0, 1, 2, 3])), /WebAssembly/);
});

await test("fromDirectory resolves native for a language directory", async () => {
  const { result: session, lines } = await silenceWarnAsync(() => Session.fromDirectory(nativeDir));
  try {
    assert.equal(session.backend, "native");
    assert.equal(lines.length, 1);
    assert.match(lines[0], /procedures/);
    assert.ok(session.version().length > 0);
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("fromDirectory resolves the shared galley-build library natively", async () => {
  const { result: session, lines } = await silenceWarnAsync(() => Session.fromDirectory(sharedDir));
  try {
    assert.equal(session.backend, "native");
    assert.equal(lines.length, 1);
    assert.match(lines[0], /procedures/);
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("fromFile opens an explicit artifact file", async () => {
  const fileDir = `${nativeDir}-file`;
  fs.rmSync(fileDir, { recursive: true, force: true });
  fs.cpSync(nativeDir, fileDir, { recursive: true });
  const libName = artifactFileName("galley-js-deno", Deno.build.os);
  const customLib = path.join(fileDir, `custom-name${path.extname(libName)}`);
  fs.renameSync(path.join(fileDir, libName), customLib);
  try {
    const { result: session, lines } = await silenceWarnAsync(() => Session.fromFile(customLib));
    try {
      assert.equal(session.backend, "native");
      assert.equal(lines.length, 1);
      assert.match(lines[0], /procedures/);
      assert.equal(session.parse("alpha:12,beta:3"), 15);
    } finally {
      session.close();
    }
  } finally {
    fs.rmSync(fileDir, { recursive: true, force: true });
  }
});

await test("missing native falls back to wasm with notice", async () => {
  const original = console.warn;
  const lines: string[] = [];
  console.warn = (message: unknown) => lines.push(String(message));
  const session = await Session.fromDirectory(wasmDir);
  try {
    assert.equal(session.backend, "wasm");
    assert.equal(lines.length, 1);
    assert.match(lines[0], /WebAssembly/);
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    console.warn = original;
    session.close();
  }
});

await test("backend pin selects the wasm leg", async () => {
  const original = console.warn;
  const lines: string[] = [];
  console.warn = (message: unknown) => lines.push(String(message));
  const session = await Session.fromDirectory(wasmDir, { backend: "wasm" });
  try {
    assert.equal(session.backend, "wasm");
    assert.equal(lines.length, 1);
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    console.warn = original;
    session.close();
  }
});

await test("missing everything explains how to build", async () => {
  await assert.rejects(
    Session.fromDirectory(path.join(nativeDir, "no-such-dir")),
    /Build one first/,
  );
});

await test("quiet suppresses the fallback notice", async () => {
  const original = console.warn;
  const lines: string[] = [];
  console.warn = (message: unknown) => lines.push(String(message));
  const session = await Session.fromDirectory(wasmDir, { quiet: true });
  try {
    assert.equal(lines.length, 0);
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    console.warn = original;
    session.close();
  }
});

await test("explicit procedures dispatch on deno", async () => {
  const hooks = await import(pathToFileURL(path.join(nativeDir, "procedures.ts")).href);
  const session = await Session.fromDirectory(nativeDir, { procedures: hooks as Record<string, unknown> });
  try {
    assert.ok(session.listProcedures().includes("reduction_Pair"));
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("native and wasm sessions parse interleaved", async () => {
  const native = await Session.fromDirectory(nativeDir, { quiet: true });
  const wasm = await Session.fromDirectory(wasmDir, { quiet: true });
  try {
    assert.equal(native.backend, "native");
    assert.equal(wasm.backend, "wasm");
    assert.equal(native.parse("alpha:12,beta:3"), 15);
    assert.equal(wasm.parse("alpha:12,beta:3"), 15);
    assert.equal(native.parse("alpha:1"), 7);
    assert.equal(wasm.parse("alpha:1"), 7);
  } finally {
    native.close();
    wasm.close();
  }
});

console.log(`\n${passed} passed, ${failed} failed, ${skipped} skipped`);
process.exit(failed === 0 ? 0 : 1);
