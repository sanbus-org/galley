/**
 * Behavioral tests for the universal loader under Deno.
 *
 * Mirrors `tests/test_loader.mjs` (Node) through the Deno native adapter:
 * native-first resolution, wasm pinning, and explicit `procedures`
 * (there is no synchronous module scan on this runtime). Sessions come
 * from `galley` (bare loads) and `openLanguageDirectory`
 * (the generated-entry path) on every runtime.
 *
 * Run:
 *   GALLEY_CHECKOUT=/path/to/galley deno task test
 *
 * Uses the shared fixture (bindings/js/test-fixture), built on demand
 * with the deno and wasm builders into temp workdirs; sessions open
 * them through `galley` (bare loads) and `openLanguageDirectory`
 * (the generated-entry path).
 */

import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { artifactFileName, SHARED_NATIVE_LIBRARY_BASE } from "@sanbus/galley-core/internal";
import { wasmArtifactFileName } from "@sanbus/galley-core/internal";
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

import { detectRuntime, galley, openLanguageDirectory, __resetLanguageCache } from "../src/index.ts";
import { __resetLoader as resetLoader } from "../src/loader.ts";

let passed = 0;
let failed = 0;
let skipped = 0;

class SkipTest extends Error {}

async function test(name: string, fn: () => void | Promise<void>) {
  resetLoader();
  __resetLanguageCache();
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

/** Runs `fn` with the process-wide wasm-notice opt-out set. */
async function withQuietEnv<T>(fn: () => T): Promise<T> {
  Deno.env.set("GALLEY_QUIET", "1");
  try {
    return await fn();
  } finally {
    Deno.env.delete("GALLEY_QUIET");
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
  await assert.rejects(openLanguageDirectory(""), /languagePath/);
  await assert.rejects(galley.load(""), /filePath/);
  await assert.rejects(galley.loadBytes("not-bytes" as unknown as Uint8Array), /bytes/);
  await assert.rejects(galley.loadUrl(42 as unknown as string), /URL/);
  await assert.rejects(galley.loadBytes(new Uint8Array([0]), { backend: "wasm" }), /backend/);
  await assert.rejects(galley.loadUrl("data:application/wasm;base64,AA==", { backend: "wasm" }), /backend/);
});

await test("galley.loadBytes resolves a usable language", async () => {
  const bytes = new Uint8Array(Deno.readFileSync(`${wasmDir}/libgalley-js-wasm.wasm`));
  const lang = await withQuietEnv(() => galley.loadBytes(bytes));
  assert.equal(lang.backend, "wasm");
  const session = await lang.openSession();
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("galley.loadUrl resolves a usable language", async () => {
  const bytes = new Uint8Array(Deno.readFileSync(`${wasmDir}/libgalley-js-wasm.wasm`));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  const lang = await withQuietEnv(() => galley.loadUrl(`data:application/wasm;base64,${btoa(binary)}`));
  assert.equal(lang.backend, "wasm");
  const session = await lang.openSession();
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("garbage bytes reject loudly", async () => {
  await assert.rejects(galley.loadBytes(new Uint8Array([0, 1, 2, 3])), /WebAssembly/);
});

await test("openLanguageDirectory resolves native for a language directory", async () => {
  const { result: lang, lines } = await silenceWarnAsync(() => openLanguageDirectory(nativeDir));
  assert.equal(lang.backend, "native");
  assert.equal(lines.length, 1);
  assert.match(lines[0], /procedures/);
  assert.ok(lang.version().length > 0);
  const session = await lang.openSession();
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("openLanguageDirectory resolves the shared galley-build library natively", async () => {
  const { result: lang, lines } = await silenceWarnAsync(() => openLanguageDirectory(sharedDir));
  assert.equal(lang.backend, "native");
  assert.equal(lines.length, 1);
  assert.match(lines[0], /procedures/);
  const session = await lang.openSession();
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("galley.load opens an explicit artifact file", async () => {
  const fileDir = `${nativeDir}-file`;
  fs.rmSync(fileDir, { recursive: true, force: true });
  fs.cpSync(nativeDir, fileDir, { recursive: true });
  const libName = artifactFileName("galley-js-deno", Deno.build.os);
  const customLib = path.join(fileDir, `custom-name${path.extname(libName)}`);
  fs.renameSync(path.join(fileDir, libName), customLib);
  try {
    const { result: lang, lines } = await silenceWarnAsync(() => galley.load(customLib));
    assert.equal(lang.backend, "native");
    // Bare file loads never scan and never warn: hooks arrive
    // explicitly only.
    assert.equal(lines.length, 0);
    assert.deepEqual(lang.listProcedures(), {});
    const session = await lang.openSession();
    try {
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
  const lang = await openLanguageDirectory(wasmDir);
  try {
    assert.equal(lang.backend, "wasm");
    assert.equal(lines.length, 1);
    assert.match(lines[0], /WebAssembly/);
    const session = await lang.openSession();
    try {
      assert.equal(session.parse("alpha:12,beta:3"), 15);
    } finally {
      session.close();
    }
  } finally {
    console.warn = original;
  }
});

await test("backend pin selects the wasm leg", async () => {
  const original = console.warn;
  const lines: string[] = [];
  console.warn = (message: unknown) => lines.push(String(message));
  const lang = await openLanguageDirectory(wasmDir, { backend: "wasm" });
  try {
    assert.equal(lang.backend, "wasm");
    assert.equal(lines.length, 1);
    const session = await lang.openSession();
    try {
      assert.equal(session.parse("alpha:12,beta:3"), 15);
    } finally {
      session.close();
    }
  } finally {
    console.warn = original;
  }
});

await test("missing everything explains how to build", async () => {
  await assert.rejects(
    openLanguageDirectory(path.join(nativeDir, "no-such-dir")),
    /Build one first/,
  );
});

await test("GALLEY_QUIET suppresses the fallback notice", async () => {
  const original = console.warn;
  const lines: string[] = [];
  console.warn = (message: unknown) => lines.push(String(message));
  const lang = await withQuietEnv(() => openLanguageDirectory(wasmDir));
  try {
    assert.equal(lines.length, 0);
    const session = await lang.openSession();
    try {
      assert.equal(session.parse("alpha:12,beta:3"), 15);
    } finally {
      session.close();
    }
  } finally {
    console.warn = original;
  }
});

await test("explicit procedures dispatch on deno", async () => {
  const hooks = await import(pathToFileURL(path.join(nativeDir, "procedures.ts")).href);
  const { result: lang } = await silenceWarnAsync(() => openLanguageDirectory(nativeDir));
  lang.installProcedures(hooks as Record<string, unknown>);
  try {
    assert.ok("reduction_Pair" in lang.listProcedures());
    const session = await lang.openSession();
    try {
      assert.equal(session.parse("alpha:12,beta:3"), 15);
    } finally {
      session.close();
    }
  } finally {
    lang.clearProcedures();
  }
});

await test("native and wasm sessions parse interleaved", async () => {
  const { nativeLang, wasmLang } = await withQuietEnv(async () => {
    const nativeLang = await openLanguageDirectory(nativeDir);
    const wasmLang = await openLanguageDirectory(wasmDir);
    return { nativeLang, wasmLang };
  });
  assert.equal(nativeLang.backend, "native");
  assert.equal(wasmLang.backend, "wasm");
  const native = await nativeLang.openSession();
  const wasm = await wasmLang.openSession();
  try {
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
