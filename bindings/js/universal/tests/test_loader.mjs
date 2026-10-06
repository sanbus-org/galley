#!/usr/bin/env node
/**
 * Behavioral tests for the universal loader.
 *
 * Run:
 *   node bindings/js/universal/tests/test_loader.mjs
 *
 * Uses the shared fixture (bindings/js/test-fixture), built on demand
 * with the node and wasm builders into temp workdirs; sessions open
 * them through `galley` (bare loads) and `openLanguageDirectory`
 * (the generated-entry path).
 */

import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as http from "node:http";
import * as path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { artifactFileName, wasmArtifactFileName } from "@sanbus/galley-core/internal";
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

const { detectRuntime, galley, openLanguageDirectory, __resetParserCache } = await import("../dist/index.js");
const browserEntry = await import("../dist/browser.js");
const { __resetLoader: resetLoader, resolveSync } = await import("../dist/loader.js");

let passed = 0;
let failed = 0;
let skipped = 0;

class SkipTest extends Error {}

async function test(name, fn) {
  resetLoader();
  __resetParserCache();
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

await test("factories validate their source", () => {
  assert.throws(() => openLanguageDirectory(""), /languagePath/);
  assert.throws(() => openLanguageDirectory(), /languagePath/);
  assert.throws(() => galley.load(""), /filePath/);
  assert.throws(() => galley.load(), /filePath/);
  assert.throws(() => galley.loadBytes("not-bytes"), /bytes/);
  assert.throws(() => galley.loadBytes(new Uint8Array([0]), { backend: "wasm" }), /backend/);
  assert.throws(() => openLanguageDirectory(nativeDir, { backend: "native" }), /backend/);
  assert.rejects(galley.loadUrl(42), /URL/);
  assert.rejects(galley.loadUrl("data:application/wasm;base64,AA==", { backend: "wasm" }), /backend/);
});

await test("openLanguageDirectory resolves native for a language directory", async () => {
  const { result: parser, lines } = await silenceWarnAsync(() => openLanguageDirectory(nativeDir));
  assert.equal(parser.backend, "native");
  assert.equal(lines.length, 0);
  assert.ok(parser.version().length > 0);
  const session = await parser.openSession();
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
  const libName = artifactFileName("galley-js-node", process.platform);
  const customLib = path.join(fileDir, `custom-name${path.extname(libName)}`);
  fs.renameSync(path.join(fileDir, libName), customLib);
  try {
    const { result: parser, lines } = await silenceWarnAsync(() => galley.load(customLib));
    assert.equal(parser.backend, "native");
    assert.equal(lines.length, 0);
    // Bare file loads wire nothing: hooks arrive explicitly only.
    assert.deepEqual(parser.listProcedures(), {});
    const session = await parser.openSession();
    try {
      assert.equal(session.parse("alpha:12,beta:3"), 15);
    } finally {
      session.close();
    }
  } finally {
    fs.rmSync(fileDir, { recursive: true, force: true });
  }
});

await test("galley.load missing artifact fails loudly", () => {
  assert.throws(
    () => galley.load(path.join(nativeDir, "no-such-lib")),
    /no-such-lib/,
  );
});

await test("galley.load yields a foreign artifact to its engine", async () => {
  // The wasm artifact sitting beside the native addon: the native leg
  // must not dlopen it (it never even reached the wasm leg before),
  // and the wasm leg must serve it.
  const foreignDir = `${nativeDir}-foreign`;
  fs.rmSync(foreignDir, { recursive: true, force: true });
  fs.cpSync(nativeDir, foreignDir, { recursive: true });
  const wasmName = wasmArtifactFileName("galley-js-wasm");
  const foreign = path.join(foreignDir, wasmName);
  fs.copyFileSync(path.join(wasmDir, wasmName), foreign);
  try {
    const { result: parser, lines } = await silenceWarnAsync(() => galley.load(foreign));
    assert.equal(parser.backend, "wasm");
    // The `.wasm` file names its engine: intentional, not a fallback,
    // so the one-time notice stays silent.
    assert.equal(lines.length, 0);
    const session = await parser.openSession();
    try {
      assert.equal(session.parse("alpha:12,beta:3"), 15);
    } finally {
      session.close();
    }
  } finally {
    fs.rmSync(foreignDir, { recursive: true, force: true });
  }
});

await test("missing native falls back to wasm with notice", async () => {
  const { result: parser, lines } = await silenceWarnAsync(() => openLanguageDirectory(wasmDir));
  assert.equal(parser.backend, "wasm");
  assert.equal(lines.length, 1);
  assert.match(lines[0], /WebAssembly/);
  const session = await parser.openSession();
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("resolveSync flags only the engine-unspecified fallback", () => {
  const wasmArtifact = path.join(wasmDir, wasmArtifactFileName("galley-js-wasm"));
  // Directory: names no engine, wasm took over after native missed.
  const fromDirectory = resolveSync({ languagePath: wasmDir }, detectRuntime());
  assert.equal(fromDirectory.backend, "wasm");
  assert.equal(fromDirectory.fallback, true);
  // File and bytes name wasm themselves; native is always preferred.
  const fromFile = resolveSync({ filePath: wasmArtifact }, detectRuntime());
  assert.equal(fromFile.backend, "wasm");
  assert.equal(fromFile.fallback, false);
  const fromBytes = resolveSync({ bytes: new Uint8Array(fs.readFileSync(wasmArtifact)) }, detectRuntime());
  assert.equal(fromBytes.backend, "wasm");
  assert.equal(fromBytes.fallback, false);
  const native = resolveSync({ languagePath: nativeDir }, detectRuntime());
  assert.equal(native.backend, "native");
  assert.equal(native.fallback, false);
});

await test("missing everything explains how to build", () => {
  const missingArtifact = (expectedPath) => (error) => {
    assert.equal(error.code, "galley:missing-artifact");
    assert.ok(error.message.includes(expectedPath));
    assert.ok(error.message.includes(`npx galley build ${expectedPath}`));
    return true;
  };
  const noSuchDir = path.join(nativeDir, "no-such-dir");
  assert.throws(() => openLanguageDirectory(noSuchDir), missingArtifact(noSuchDir));
});

await test("bare load before directory open still wires bundled hooks", async () => {
  const artifact = path.join(nativeDir, artifactFileName("galley-js-node", process.platform));
  const bare = await galley.load(artifact);
  assert.deepEqual(bare.listProcedures(), {});
  const explicit = () => {};
  bare.installProcedure("reduction_Pair", explicit);

  const procedures = await import(
    pathToFileURL(path.join(nativeDir, "procedures.ts")).href
  );
  const { result: parser, lines } = await silenceWarnAsync(() =>
    openLanguageDirectory(nativeDir, {}, procedures),
  );
  assert.equal(lines.length, 0);
  assert.equal(parser, bare);
  // The entry's namespace fills the uninstalled names but keeps the explicit one.
  assert.equal(parser.procedureHook("reduction_Pair"), explicit);
  assert.equal(typeof parser.procedureHook("hook_print"), "function");
});

await test("native and wasm sessions parse interleaved", async () => {
  const { lines, restore } = captureWarn();
  try {
    const nativeParser = openLanguageDirectory(nativeDir);
    const wasmParser = openLanguageDirectory(wasmDir);
    const native = await nativeParser.openSession();
    const wasm = await wasmParser.openSession();
    try {
      assert.equal(native.parse("alpha:12,beta:3"), 15);
      assert.equal(wasm.parse("alpha:12,beta:3"), 15);
      assert.equal(native.parse("alpha:1"), 7);
      assert.equal(wasm.parse("alpha:1"), 7);
    } finally {
      native.close();
      wasm.close();
    }
  } finally {
    restore();
  }
  // One notice: the wasm open.
  assert.equal(lines.length, 1);
  assert.match(lines[0], /WebAssembly/);
});

await test("galley.loadUrl resolves a usable parser", async () => {
  const wasmBytes = new Uint8Array(fs.readFileSync(path.join(wasmDir, "libgalley-js-wasm.wasm")));
  await withServer(wasmBytes, async (url) => {
    const { lines, restore } = captureWarn();
    const parser = await galley.loadUrl(url);
    try {
      assert.equal(parser.backend, "wasm");
      const session = await parser.openSession();
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

await test("galley.loadBytes resolves a usable parser", async () => {
  const bytes = new Uint8Array(fs.readFileSync(path.join(wasmDir, "libgalley-js-wasm.wasm")));
  const { result: parser, lines } = await silenceWarnAsync(() => galley.loadBytes(bytes));
  assert.equal(parser.backend, "wasm");
  // Bytes name wasm themselves: never a fallback, so no notice.
  assert.equal(lines.length, 0);
  const session = await parser.openSession();
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("garbage bytes reject loudly", () => {
  assert.throws(() => galley.loadBytes(new Uint8Array([0, 1, 2, 3])), /WebAssembly/);
});

await test("browser entry parses from bytes", async () => {
  const bytes = new Uint8Array(fs.readFileSync(path.join(wasmDir, "libgalley-js-wasm.wasm")));
  const { result: parser, lines } = await silenceWarnAsync(
    () => browserEntry.galley.loadBytes(bytes),
  );
  // Wasm is the browser's only leg: no fallback notice exists to fire.
  assert.equal(lines.length, 0);
  const session = await parser.openSession();
  try {
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  } finally {
    session.close();
  }
});

await test("browser entry caches identical bytes to one parser", async () => {
  const bytes = new Uint8Array(fs.readFileSync(path.join(wasmDir, "libgalley-js-wasm.wasm")));
  const first = await browserEntry.galley.loadBytes(bytes);
  const second = await browserEntry.galley.loadBytes(bytes);
  // Identical bytes resolve to the identical parser.
  assert.equal(second, first);
  const s1 = await first.openSession();
  const s2 = await second.openSession();
  assert.equal(s1.parse("alpha:12,beta:3"), 15);
  assert.equal(s2.parse("alpha:12,beta:3"), 15);
  s1.close();
  s2.close();
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
    const { result: parser } = await silenceWarnAsync(() => browserEntry.galley.loadUrl(url));
    await using session = parser.openSession();
    assert.equal(session.parse("alpha:12,beta:3"), 15);
  });
});

await test("entries hide the base Session value", async () => {
  const ns = await import("../dist/index.js");
  assert.equal("Session" in ns, false);
  assert.equal(typeof ns.Parser, "function");
  // The browser entry exposes its own wasm-only subclass under the name,
  // never the core base.
  assert.equal(browserEntry.Session.name, "BrowserSession");
  assert.equal(typeof browserEntry.Parser, "function");
});

await test("entries keep loader internals off the public surface", async () => {
  for (const ns of [await import("../dist/index.js"), browserEntry]) {
    for (const name of ["resolveArtifact", "checkModuleBytes", "encodeUtf8"]) {
      assert.equal(name in ns, false);
    }
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

// The fixture's generated entry is written by the real builder gate on
// every run, so these pins read actual build output, never a copy.
await test("generated package entry follows the hook contracts", () => {
  const entry = fs.readFileSync(path.join(nativeDir, "index.mjs"), "utf-8");
  // Bundled wiring happens inside the directory open — core fills only
  // names never installed, so explicit installs win over bundled hooks
  // regardless of order — and the entry runs that open once at module
  // import, synchronously, over its statically imported procedures
  // namespace, then mirrors the parser's interface as its exports.
  assert.ok(entry.includes('import * as procedures from "./procedures'));
  assert.ok(entry.includes("const PARSER = openLanguageDirectory(LANGUAGE_DIR, {}, procedures);"));
  assert.ok(entry.includes("export const openSession = PARSER.openSession.bind(PARSER);"));
  assert.ok(entry.includes("export const backend = PARSER.backend;"));
  // No top-level await (CommonJS require() of the entry works), no
  // parser() accessor, no manual wiring call.
  assert.ok(!entry.includes("await"));
  assert.ok(!/\bparser\(/.test(entry));
  assert.ok(!entry.includes("installBundledProcedures(procedures)"));
  assert.ok(!entry.includes("initialize"));
  // Generated example content never names another language.
  assert.ok(!/\bpython\b/i.test(entry));
});

console.log(`\n${passed} passed, ${failed} failed, ${skipped} skipped`);
process.exit(failed === 0 ? 0 : 1);
