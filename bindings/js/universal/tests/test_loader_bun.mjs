#!/usr/bin/env node
/**
 * Behavioral tests for the universal loader under Bun.
 *
 * Mirrors `tests/test_loader.mjs` (Node) through the Bun native adapter:
 * native-first resolution, wasm pinning, and `galley` /
 * `openLanguageDirectory` construction.
 *
 * Run:
 *   GALLEY_CHECKOUT=/path/to/galley bun bindings/js/universal/tests/test_loader_bun.mjs
 *
 * Uses the shared fixture (bindings/js/test-fixture), built on demand
 * with the bun and wasm builders into temp workdirs; sessions open
 * them through `galley` (bare loads) and `openLanguageDirectory`
 * (the generated-entry path).
 */

import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as http from "node:http";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { artifactFileName, wasmArtifactFileName, SHARED_NATIVE_LIBRARY_BASE } from "@sanbus/galley-core/internal";
import { ensureTestLibrary } from "../../../js/core/build/fixture.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..", "..", "..", "..");
// Self-built shared fixture (bindings/js/test-fixture); never examples/.
const nativeDir = ensureTestLibrary({
  buildCommand: ["bun", path.join(repoRoot, "bindings", "js", "bun", "build.mjs")],
  libFileName: artifactFileName("galley-js-bun", process.platform),
  scope: "bun",
});
const wasmDir = ensureTestLibrary({
  buildCommand: ["node", path.join(repoRoot, "bindings", "js", "wasm", "build.mjs")],
  libFileName: wasmArtifactFileName("galley-js-wasm"),
  scope: "wasm",
});
// The real-world `galley build` output: only the shared native library
// (plus wasm), no adapter-named file. Sessions on every native runtime
// must resolve native here silently — this is the CI parity path.
const sharedDir = ensureTestLibrary({
  buildCommand: ["node", path.join(repoRoot, "bindings", "js", "universal", "build.mjs"), "build"],
  libFileName: artifactFileName(SHARED_NATIVE_LIBRARY_BASE, process.platform),
  scope: "universal",
});

const { detectRuntime, galley, openLanguageDirectory, __resetLanguageCache } = await import("../dist/index.js");
const browserEntry = await import("../dist/browser.js");
const { __resetLoader: resetLoader } = await import("../dist/loader.js");

let passed = 0;
let failed = 0;
let skipped = 0;

class SkipTest extends Error {}

async function test(name, fn) {
  resetLoader();
  __resetLanguageCache();
  browserEntry.__resetLoader();
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

function captureWarn() {
  const original = console.warn;
  const lines = [];
  console.warn = (message) => lines.push(String(message));
  return { lines, restore: () => { console.warn = original; } };
}

async function silenceWarnAsync(fn) {
  const { lines, restore } = captureWarn();
  try {
    const result = await fn();
    return { result, lines };
  } finally {
    restore();
  }
}

/** Runs `fn` with the process-wide wasm-notice opt-out set. */
async function withQuietEnv(fn) {
  const previous = process.env.GALLEY_QUIET;
  process.env.GALLEY_QUIET = "1";
  try {
    return await fn();
  } finally {
    if (previous === undefined) delete process.env.GALLEY_QUIET;
    else process.env.GALLEY_QUIET = previous;
  }
}

/** Serve bytes over HTTP on an ephemeral port; releases on done. */
async function withServer(bytes, fn) {
  const server = http.createServer((request, response) => {
    response.writeHead(200, { "content-type": "application/wasm" });
    response.end(bytes);
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    const { port } = server.address();
    await fn(`http://127.0.0.1:${port}/grammar.wasm`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

await test("detectRuntime reports bun", () => {
  assert.equal(detectRuntime(), "bun");
});

await test("factories validate their source", async () => {
  await assert.rejects(openLanguageDirectory(""), /languagePath/);
  await assert.rejects(openLanguageDirectory(), /languagePath/);
  await assert.rejects(galley.load(""), /filePath/);
  await assert.rejects(galley.load(), /filePath/);
  await assert.rejects(galley.loadBytes("not-bytes"), /bytes/);
  await assert.rejects(galley.loadUrl(42), /URL/);
  await assert.rejects(galley.loadBytes(new Uint8Array([0]), { backend: "wasm" }), /backend/);
  await assert.rejects(galley.loadUrl("data:application/wasm;base64,AA==", { backend: "wasm" }), /backend/);
});

await test("openLanguageDirectory resolves native for a language directory", async () => {
  const { result: lang, lines } = await silenceWarnAsync(() => openLanguageDirectory(nativeDir));
  assert.equal(lang.backend, "native");
  assert.equal(lines.length, 0);
  assert.ok(lang.version().length > 0);
  const session = await lang.openSession();
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("openLanguageDirectory resolves the shared galley-build library natively", async () => {
  const { result: sharedLang, lines: sharedLines } = await silenceWarnAsync(() => openLanguageDirectory(sharedDir));
  assert.equal(sharedLang.backend, "native");
  assert.equal(sharedLines.length, 0);
  const sharedSession = await sharedLang.openSession();
  try {
    assert.equal(sharedSession.parse("alpha:12,beta:3"), 15);
  } finally {
    sharedSession.close();
  }
});

await test("galley.load opens an explicit artifact file", async () => {
  const fileDir = `${nativeDir}-file`;
  fs.rmSync(fileDir, { recursive: true, force: true });
  fs.cpSync(nativeDir, fileDir, { recursive: true });
  const libName = artifactFileName("galley-js-bun", process.platform);
  const customLib = path.join(fileDir, `custom-name${path.extname(libName)}`);
  fs.renameSync(path.join(fileDir, libName), customLib);
  try {
    const { result: lang, lines } = await silenceWarnAsync(() => galley.load(customLib));
    assert.equal(lang.backend, "native");
    assert.equal(lines.length, 0);
    // Bare file loads never scan: hooks arrive explicitly only.
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

await test("galley.load missing artifact fails loudly", async () => {
  await assert.rejects(
    galley.load(path.join(nativeDir, "no-such-lib")),
    /no-such-lib/,
  );
});

await test("missing native falls back to wasm with notice", async () => {
  const { result: lang, lines } = await silenceWarnAsync(() => openLanguageDirectory(wasmDir));
  assert.equal(lang.backend, "wasm");
  assert.equal(lines.length, 1);
  assert.match(lines[0], /WebAssembly/);
  const session = await lang.openSession();
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("backend pin selects the wasm leg", async () => {
  const { result: lang, lines } = await silenceWarnAsync(
    () => openLanguageDirectory(wasmDir, { backend: "wasm" }),
  );
  assert.equal(lines.length, 1);
  const session = await lang.openSession();
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("missing everything explains how to build", async () => {
  await assert.rejects(
    openLanguageDirectory(path.join(nativeDir, "no-such-dir")),
    /Build one first/,
  );
  await assert.rejects(
    openLanguageDirectory(nativeDir, { backend: "wasm" }),
    /no parser artifact found/,
  );
});

await test("GALLEY_QUIET suppresses the fallback notice", async () => {
  const { result: lang, lines } = await silenceWarnAsync(
    () => withQuietEnv(() => openLanguageDirectory(wasmDir)),
  );
  assert.equal(lines.length, 0);
  const session = await lang.openSession();
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("native and wasm sessions parse interleaved", async () => {
  const { lines, restore } = captureWarn();
  const { native, wasm } = await withQuietEnv(async () => {
    const nativeLang = await openLanguageDirectory(nativeDir);
    const wasmLang = await openLanguageDirectory(wasmDir);
    return { native: await nativeLang.openSession(), wasm: await wasmLang.openSession() };
  });
  try {
    assert.equal(native.parse("alpha:12,beta:3"), 15);
    assert.equal(wasm.parse("alpha:12,beta:3"), 15);
    assert.equal(native.parse("alpha:1"), 7);
    assert.equal(wasm.parse("alpha:1"), 7);
  } finally {
    restore();
    native.close();
    wasm.close();
  }
  assert.equal(lines.length, 0);
});

await test("galley.loadUrl resolves a usable language", async () => {
  const wasmBytes = new Uint8Array(fs.readFileSync(path.join(wasmDir, "libgalley-js-wasm.wasm")));
  await withServer(wasmBytes, async (url) => {
    const { lines, restore } = captureWarn();
    const lang = await withQuietEnv(() => galley.loadUrl(url));
    try {
      assert.equal(lang.backend, "wasm");
      const session = await lang.openSession();
      try {
        assert.equal(session.parse("alpha:12,beta:3"), 15);
      } finally {
        session.close();
      }
    } finally {
      restore();
    }
  });
});

await test("unreachable url rejects loudly", async () => {
  await assert.rejects(
    galley.loadUrl("http://127.0.0.1:1/grammar.wasm"),
    /fetch|ECONNREFUSED|Failed|Unable to connect/,
  );
});

await test("galley.loadBytes resolves a usable language", async () => {
  const bytes = new Uint8Array(fs.readFileSync(path.join(wasmDir, "libgalley-js-wasm.wasm")));
  const { result: lang, lines } = await silenceWarnAsync(() => withQuietEnv(() => galley.loadBytes(bytes)));
  assert.equal(lang.backend, "wasm");
  assert.equal(lines.length, 0);
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

await test("browser entry parses from bytes", async () => {
  const bytes = new Uint8Array(fs.readFileSync(path.join(wasmDir, "libgalley-js-wasm.wasm")));
  const { result: lang, lines } = await silenceWarnAsync(
    () => withQuietEnv(() => browserEntry.galley.loadBytes(bytes)),
  );
  assert.equal(lines.length, 0);
  const session = await lang.openSession();
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("browser entry warns once without quiet", async () => {
  const bytes = new Uint8Array(fs.readFileSync(path.join(wasmDir, "libgalley-js-wasm.wasm")));
  const { lines, restore } = captureWarn();
  try {
    const first = await browserEntry.galley.loadBytes(bytes);
    const second = await browserEntry.galley.loadBytes(bytes);
    assert.equal(lines.length, 1);
    assert.match(lines[0], /WebAssembly/);
    // Identical bytes resolve to the identical handle.
    assert.equal(second, first);
    const s1 = await first.openSession();
    const s2 = await second.openSession();
    assert.equal(s1.parse("alpha:12,beta:3"), 15);
    assert.equal(s2.parse("alpha:12,beta:3"), 15);
    s1.close();
    s2.close();
  } finally {
    restore();
  }
});

await test("browser entry exposes galley without filesystem loads", () => {
  // Browsers have no filesystem: absence at compile time, not a runtime throw.
  assert.equal(typeof browserEntry.galley.loadBytes, "function");
  assert.equal(typeof browserEntry.galley.loadUrl, "function");
  assert.equal(browserEntry.galley.load, undefined);
});

await test("browser entry parses from url", async () => {
  const wasmBytes = new Uint8Array(fs.readFileSync(path.join(wasmDir, "libgalley-js-wasm.wasm")));
  await withServer(wasmBytes, async (url) => {
    const lang = await withQuietEnv(() => browserEntry.galley.loadUrl(url));
    await using session = await lang.openSession();
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  });
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
