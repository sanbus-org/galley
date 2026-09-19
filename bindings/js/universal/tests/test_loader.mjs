#!/usr/bin/env node
/**
 * Behavioral tests for the universal loader.
 *
 * Run:
 *   node bindings/js/universal/tests/test_loader.mjs
 *
 * Uses the shared fixture (bindings/js/test-fixture), built on demand
 * with the node and wasm builders into temp workdirs; sessions open
 * them through async factories.
 */

import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as http from "node:http";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { artifactFileName, wasmArtifactFileName } from "@sanbus/galley-core";
import { ensureTestLibrary } from "../../../js/core/build/fixture.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..", "..", "..", "..");
// Self-built shared fixture (bindings/js/test-fixture); never examples/.
const nativeDir = ensureTestLibrary({
  buildCommand: ["node", path.join(repoRoot, "bindings", "js", "node", "build.mjs")],
  libFileName: artifactFileName("galley-js-node", process.platform),
  scope: "node",
});
const wasmDir = ensureTestLibrary({
  buildCommand: ["node", path.join(repoRoot, "bindings", "js", "wasm", "build.mjs")],
  libFileName: wasmArtifactFileName("galley-js-wasm"),
  scope: "wasm",
});

const { detectRuntime, Session } = await import("../dist/index.js");
const browserEntry = await import("../dist/browser.js");
const { __resetLoader: resetLoader } = await import("../dist/loader.js");

let passed = 0;
let failed = 0;
let skipped = 0;

class SkipTest extends Error {}

async function test(name, fn) {
  resetLoader();
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

await test("detectRuntime reports node", () => {
  assert.equal(detectRuntime(), "node");
});

await test("factories validate their source", async () => {
  await assert.rejects(Session.fromDirectory(""), /languagePath/);
  await assert.rejects(Session.fromDirectory(), /languagePath/);
  await assert.rejects(Session.fromFile(""), /filePath/);
  await assert.rejects(Session.fromFile(), /filePath/);
  await assert.rejects(Session.fromBytes("not-bytes"), /bytes/);
  await assert.rejects(Session.fromUrl(42), /URL/);
});

await test("fromDirectory resolves native for a language directory", async () => {
  const { result: session, lines } = await silenceWarnAsync(() => Session.fromDirectory(nativeDir));
  try {
    assert.equal(session.backend, "native");
    assert.equal(lines.length, 0);
    assert.ok(session.version().length > 0);
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("fromFile opens an explicit artifact file", async () => {
  const fileDir = `${nativeDir}-file`;
  fs.rmSync(fileDir, { recursive: true, force: true });
  fs.cpSync(nativeDir, fileDir, { recursive: true });
  const libName = artifactFileName("galley-js-node", process.platform);
  const customLib = path.join(fileDir, `custom-name${path.extname(libName)}`);
  fs.renameSync(path.join(fileDir, libName), customLib);
  try {
    const { result: session, lines } = await silenceWarnAsync(() => Session.fromFile(customLib));
    try {
      assert.equal(session.backend, "native");
      assert.equal(lines.length, 0);
      // Bare file loads never scan: hooks arrive explicitly only.
      assert.deepEqual(session.listProcedures(), []);
      assert.equal(session.parse("alpha:12,beta:3"), 15);
    } finally {
      session.close();
    }
  } finally {
    fs.rmSync(fileDir, { recursive: true, force: true });
  }
});

await test("fromFile missing artifact fails loudly", async () => {
  await assert.rejects(
    Session.fromFile(path.join(nativeDir, "no-such-lib")),
    /no-such-lib/,
  );
});

await test("missing native falls back to wasm with notice", async () => {
  const { result: session, lines } = await silenceWarnAsync(() => Session.fromDirectory(wasmDir));
  try {
    assert.equal(session.backend, "wasm");
    assert.equal(lines.length, 1);
    assert.match(lines[0], /WebAssembly/);
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("backend pin selects the wasm leg", async () => {
  const { result: session, lines } = await silenceWarnAsync(
    () => Session.fromDirectory(wasmDir, { backend: "wasm" }),
  );
  try {
    assert.equal(lines.length, 1);
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("missing everything explains how to build", async () => {
  await assert.rejects(
    Session.fromDirectory(path.join(nativeDir, "no-such-dir")),
    /Build one first/,
  );
  await assert.rejects(
    Session.fromDirectory(nativeDir, { backend: "wasm" }),
    /no parser artifact found/,
  );
});

await test("quiet suppresses the fallback notice", async () => {
  const { result: session, lines } = await silenceWarnAsync(
    () => Session.fromDirectory(wasmDir, { quiet: true }),
  );
  try {
    assert.equal(lines.length, 0);
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("native and wasm sessions parse interleaved", async () => {
  const { lines, restore } = captureWarn();
  const native = await Session.fromDirectory(nativeDir, { quiet: true });
  const wasm = await Session.fromDirectory(wasmDir, { quiet: true });
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

await test("fromUrl resolves a usable session", async () => {
  const wasmBytes = new Uint8Array(fs.readFileSync(path.join(wasmDir, "libgalley-js-wasm.wasm")));
  await withServer(wasmBytes, async (url) => {
    const { lines, restore } = captureWarn();
    const session = await Session.fromUrl(url, { quiet: true });
    try {
      assert.equal(session.backend, "wasm");
      assert.equal(session.parse("alpha:12,beta:3"), 15);
    } finally {
      restore();
      session.close();
    }
  });
});

await test("unreachable url rejects loudly", async () => {
  await assert.rejects(
    Session.fromUrl("http://127.0.0.1:1/grammar.wasm", { quiet: true }),
    /fetch|ECONNREFUSED|Failed|Unable to connect/,
  );
});

await test("fromBytes resolves a usable session", async () => {
  const bytes = new Uint8Array(fs.readFileSync(path.join(wasmDir, "libgalley-js-wasm.wasm")));
  const { result: session, lines } = await silenceWarnAsync(() => Session.fromBytes(bytes, { quiet: true }));
  try {
    assert.equal(session.backend, "wasm");
    assert.equal(lines.length, 0);
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("garbage bytes reject loudly", async () => {
  await assert.rejects(Session.fromBytes(new Uint8Array([0, 1, 2, 3])), /WebAssembly/);
});

await test("browser entry parses from bytes", async () => {
  const bytes = new Uint8Array(fs.readFileSync(path.join(wasmDir, "libgalley-js-wasm.wasm")));
  const { result: session, lines } = await silenceWarnAsync(
    () => browserEntry.Session.fromBytes(bytes, { quiet: true }),
  );
  try {
    assert.equal(lines.length, 0);
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("browser entry warns once without quiet", async () => {
  const bytes = new Uint8Array(fs.readFileSync(path.join(wasmDir, "libgalley-js-wasm.wasm")));
  const { lines, restore } = captureWarn();
  try {
    const first = await browserEntry.Session.fromBytes(bytes);
    const second = await browserEntry.Session.fromBytes(bytes);
    assert.equal(lines.length, 1);
    assert.match(lines[0], /WebAssembly/);
    first.close();
    second.close();
  } finally {
    restore();
  }
});

await test("browser entry omits fromDirectory", () => {
  // Browsers have no filesystem: absence at compile time, not a runtime throw.
  assert.equal(typeof browserEntry.Session.fromBytes, "function");
  assert.equal(typeof browserEntry.Session.fromUrl, "function");
  assert.equal(browserEntry.Session.fromDirectory, undefined);
});

await test("browser entry parses from url", async () => {
  const wasmBytes = new Uint8Array(fs.readFileSync(path.join(wasmDir, "libgalley-js-wasm.wasm")));
  await withServer(wasmBytes, async (url) => {
    await using session = await browserEntry.Session.fromUrl(url, { quiet: true });
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
