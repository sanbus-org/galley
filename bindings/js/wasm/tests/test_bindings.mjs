#!/usr/bin/env node
/**
 * Behavioral tests for the Galley WebAssembly bindings.
 *
 * Run:
 *   node bindings/js/wasm/tests/test_bindings.mjs
 *
 * Uses the shared fixture (bindings/js/test-fixture), built on demand
 * into a temp workdir; sessions open it through the universal entry
 * pinned to the wasm leg (plus the generated package entry once).
 *
 * The universal dist must be built first:
 *   npm --prefix bindings/js/universal install
 */

import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { artifactFileName, wasmArtifactFileName } from "@sanbus/galley-core/internal";
import { ensureTestLibrary } from "../../../js/core/build/fixture.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const exampleLib = wasmArtifactFileName("galley-js-wasm");
// Self-built shared fixture (bindings/js/test-fixture).
const languageDir = ensureTestLibrary({
  buildCommand: ["node", path.join(__dirname, "..", "build.mjs")],
  libFileName: exampleLib,
  scope: "wasm",
});

const {
  Node,
  __resetModuleCache,
  ParserType,
  RecoveryMode,
  Kind,
  Status,
  INVALID_NODE,
  SessionClosedError,
} = await import("../dist/index.js");

const { galley, openLanguageDirectory, __resetParserCache } = await import("../../universal/dist/index.js");

async function newParser(opts = {}) {
  return openLanguageDirectory(languageDir, { backend: "wasm", ...opts });
}

async function newSession(opts = {}) {
  const parser = await newParser();
  return parser.openSession(opts);
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

let passed = 0;
let failed = 0;

async function test(name, fn) {
  __resetParserCache();
  try {
    await fn();
    console.log(`✓ ${name}`);
    passed++;
  } catch (e) {
    console.error(`✗ ${name}`);
    console.error(e);
    failed++;
  }
}

function assertIn(value, arr, msg) {
  assert.ok(arr.includes(value), msg ?? `${value} not in ${arr}`);
}

// ---- ParserSurfaceTests (grammar queries live on the parser) ----

await test("openLanguageDirectory requires languagePath", async () => {
  await assert.rejects(openLanguageDirectory(""), /languagePath/);
  await assert.rejects(openLanguageDirectory(), /languagePath/);
});

await test("openLanguageDirectory resolves a usable parser", async () => {
  const parser = await openLanguageDirectory(languageDir, { backend: "wasm" });
  assert.ok(parser.version().length > 0);
  const s = await parser.openSession();
  try {
    assert.equal(s.parse("alpha:12,beta:3"), 15);
  } finally {
    s.close();
  }
});

await test("missing artifact names the directory", async () => {
  await assert.rejects(
    openLanguageDirectory(path.join(languageDir, "no-such-dir"), { backend: "wasm" }),
    /no-such-dir/,
  );
});

await test("galley.load requires filePath", async () => {
  await assert.rejects(galley.load(""), /filePath/);
  await assert.rejects(galley.load(), /filePath/);
  await assert.rejects(galley.load("no-such-lib\0"), /interior NUL/);
});

await test("galley.load missing artifact names the file", async () => {
  await assert.rejects(
    galley.load(path.join(languageDir, "no-such-lib"), { backend: "wasm" }),
    /no-such-lib/,
  );
});

await test("galley.load opens an explicit artifact file", async () => {
  const fileDir = `${languageDir}-file`;
  fs.rmSync(fileDir, { recursive: true, force: true });
  fs.cpSync(languageDir, fileDir, { recursive: true });
  const customLib = path.join(fileDir, `custom-name${path.extname(exampleLib)}`);
  fs.renameSync(path.join(fileDir, exampleLib), customLib);
  try {
    // Bare file loads never scan: hooks arrive explicitly only.
    const parser = await galley.load(customLib, { backend: "wasm" });
    assert.deepEqual(parser.listProcedures(), {});
    const s = await parser.openSession();
    try {
      assert.equal(s.parse("alpha:12,beta:3"), 15);
    } finally {
      s.close();
    }
    // Explicit procedures still fire on bare-loaded parsers.
    let called = 0;
    parser.installProcedures({ reduction_Pair: () => { called++; } });
    const s2 = await parser.openSession();
    try {
      s2.parse("alpha:12,beta:3");
      assert.equal(called, 2);
    } finally {
      s2.close();
    }
  } finally {
    fs.rmSync(fileDir, { recursive: true, force: true });
  }
});

await test("direct package import wires bundled hooks", async () => {
  // The generated entry imports @sanbus/galley by specifier: link the
  // workspace universal package into the temp fixture directory so the
  // import resolves exactly as in a consumer project.
  const universalLink = path.join(languageDir, "node_modules", "@sanbus", "galley");
  const coreLink = path.join(languageDir, "node_modules", "@sanbus", "galley-core");
  fs.mkdirSync(path.dirname(universalLink), { recursive: true });
  for (const link of [universalLink, coreLink]) {
    try {
      fs.unlinkSync(link);
    } catch {
      // Absent on first run; stale on repeats.
    }
  }
  fs.symlinkSync(path.join(__dirname, "..", "..", "universal"), universalLink);
  fs.symlinkSync(path.join(__dirname, "..", "..", "core"), coreLink);
  const kv = await import(pathToFileURL(path.join(languageDir, "index.mjs")).href);
  await kv.initialize();
  // Hook namespaces are imported from their hook file; the entry binds
  // none, and named exports are the sole spelling.
  assert.equal("procedures" in kv, false);
  assert.equal("default" in kv, false);
  // Namespace pin: every type and constant the grammar module exposes,
  // with hook and query functions living on the parser like the
  // module, not the session.
  const surface = [
    "Session",
    "Node",
    "Walker",
    "ProcedureArguments",
    "Parser",
    "GalleyError",
    "Kind",
    "ParserType",
    "RecoveryMode",
    "RecoveryTarget",
    "Resume",
  ];
  assert.deepEqual(
    Object.keys(kv).sort(),
    ["initialize", "openSession", "parser", ...surface].sort(),
  );
  // Construction stays async-only: the bare class needs a bound port.
  assert.throws(() => new kv.Session(), /bound port/);
  const parser = await kv.parser();
  const s = await kv.openSession();
  try {
    assert.ok("reduction_Pair" in parser.listProcedures());
    assert.equal(s.parse("alpha:12,beta:3"), 15);
  } finally {
    s.close();
  }
});

await test("version returns non-empty string", async () => {
  const parser = await newParser();
  const v = parser.version();
  assert.equal(typeof v, "string");
  assert.notEqual(v, "");
});

await test("parser metadata flags are consistent", async () => {
  const parser = await newParser();
  assertIn(parser.parserType(), [ParserType.Ll, ParserType.Lr]);
  assert.equal(parser.hasAst(), true);
  assert.equal(typeof parser.hasProcedures(), "boolean");
  assert.equal(typeof parser.allowsNoAstTreeProcedures(), "boolean");
  assert.equal(typeof parser.sourceRetentionEnabled(), "boolean");
  assert.equal(typeof parser.hasPositionTracking(), "boolean");
  assert.equal(typeof parser.hasInputStreaming(), "boolean");
  assert.equal(typeof parser.usesVerbatim(), "boolean");
  assert.equal(typeof parser.stackOverflowRecoveryAvailable(), "boolean");
  assertIn(parser.errorRecoveryMode(), [RecoveryMode.Disabled, RecoveryMode.Automatic, RecoveryMode.Explicit]);
});

await test("status_string renders known codes", async () => {
  const parser = await newParser();
  const rendered = parser.statusString(-2);
  assert.equal(typeof rendered, "string");
  assert.ok(rendered.toLowerCase().includes("syntax"));
  assert.equal(parser.statusString(999999), null);
});


await test("entry hides the base Session value", async () => {
  const ns = await import("../dist/index.js");
  assert.equal("Session" in ns, false);
  assert.equal(typeof ns.Parser, "function");
  assert.equal(typeof ns.SessionClosedError, "function");
});

await test("entry keeps loader internals off the public surface", async () => {
  const ns = await import("../dist/index.js");
  for (const name of ["resolveArtifact", "checkModuleBytes", "encodeUtf8", "noteSkippedScan"]) {
    assert.equal(name in ns, false);
  }
});

// ---- SessionTests ----

await test("parse accepts string and buffers", async () => {
  const s = await newSession();
  try {
    const sample = "alpha:12,beta:3";
    assert.equal(s.parse(sample), sample.length);
    assert.equal(s.parse(Buffer.from(sample, "utf-8")), sample.length);
    assert.equal(s.parse(new Uint8Array(Buffer.from(sample))), sample.length);
    const encoded = new TextEncoder().encode(sample);
    assert.equal(s.parse(new DataView(encoded.buffer)), sample.length);
    assert.equal(s.parse(encoded.buffer.slice(0)), sample.length);
    assert.throws(() => s.parse(123), TypeError);
    assert.throws(() => s.parseFile(123), TypeError);
    // File paths accept strings and file URLs; bytes are input, not paths.
    const p = "/tmp/galley-js-test-parse.kv";
    fs.writeFileSync(p, sample);
    assert.equal(s.parseFile(p), sample.length);
    assert.equal(s.parseFile(pathToFileURL(p)), sample.length);
    assert.throws(() => s.parseFile(Buffer.from(p)), TypeError);
    assert.throws(() => s.parseFile(p + "\0"), TypeError);
  } finally {
    s.close();
  }
});

await test("message inputs accept bytes", async () => {
  const encode = new TextEncoder().encode.bind(new TextEncoder());
  const parser = await newParser();
  parser.installProcedure("reduction_Number", (args) => {
    args.reportSemanticError(encode("bad number"));
  });
  const s = await parser.openSession();
  try {
    s.setMessageOverride("Number", encode("custom at line {line}"));
    try {
      s.parse("alpha:");
    } catch (err) {
      assert.ok(err.diagnostic.message.includes("custom at line 1"));
    }
    assert.throws(() => s.parse("alpha:999"), (err) => {
      assert.ok(String(err.message).includes("bad number"));
      return true;
    });
  } finally {
    s.close();
  }
});

await test("syntax error throws error with code and diagnostic", async () => {
  const s = await newSession();
  try {
    try {
      s.parse("alpha:");
      assert.fail("expected error");
    } catch (err) {
      assert.equal(err.code, Status.ErrorSyntax);
      assert.ok(err.diagnostic);
      const d = err.diagnostic;
      assert.equal(d.kind, Kind.Syntax);
      assert.equal(d.line, 1);
      assert.equal(d.column, 7);
      assert.ok(d.message.includes("parse failed"));
      assert.equal(typeof d.messageAnsi, "string");
      assert.ok(d.expectedTokens.length > 0);
      assert.ok(d.expectedTokens.every((t) => t instanceof Uint8Array));
      assert.equal(d.context[d.context.length - 1], "Number");
      assert.equal(typeof d.syntaxErrorCount, "number");
    }
    assert.equal(s.hasDiagnostic(), true);
    assert.ok(s.diagnostic() !== null);
    // diagnostic from error should also be available via session
    const diag = s.diagnostic();
    assert.ok(diag);
  } finally {
    s.close();
  }
});

await test("diagnostic resets after successful parse", async () => {
  const s = await newSession();
  try {
    try {
      s.parse("alpha:");
    } catch {}
    assert.ok(s.diagnostic() !== null);
    s.parse("alpha:1");
    assert.equal(s.hasDiagnostic(), false);
    assert.equal(s.diagnostic(), null);
  } finally {
    s.close();
  }
});

await test("file parsing reports end position", async () => {
  const s = await newSession();
  try {
    const p = "/tmp/galley-js-node-test.kv";
    fs.writeFileSync(p, "alpha:12,beta:3");
    const parsed = s.parseFile(p);
    assert.equal(parsed, 15);
    const pos = s.lastPosition();
    assert.deepEqual(pos, [1, 17]);
  } finally {
    s.close();
  }
});

// ---- WalkTests ----

await test("root and navigation links", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    assert.ok(root !== null);
    assert.equal(s.nodeValid(root), true);
    assert.equal(s.parent(root), null);
    assert.equal(s.nodeValid(INVALID_NODE), false);
    const first = s.firstChild(root);
    const last = s.lastChild(root);
    assert.ok(first !== null);
    assert.equal(s.nextSibling(last), null);
    assert.equal(s.priorSibling(first), null);
    assert.ok(s.parent(first)?.address === root.address);
    const visited = [];
    let child = first;
    while (child !== null) {
      visited.push(child);
      child = s.nextSibling(child);
    }
    assert.equal(visited.length, s.childCount(root));
  } finally {
    s.close();
  }
});

await test("symbol names text spans and positions", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    assert.deepEqual(s.symbolName(root), "Document");
    const text = s.text(root);
    assert.ok(text instanceof Uint8Array);
    assert.equal(Buffer.from(text).toString(), "alpha:12,beta:3");
    const span = s.span(root);
    assert.ok(span !== null);
    assert.equal(span[0], 0n);
    assert.equal(span[1], BigInt(text.length));
    const lc = s.lineColumn(root);
    assert.deepEqual(lc, [1, 1]);
    assert.equal(typeof s.variableIndex(root), "number");
    assert.ok(s.nodeCount() > 0);
  } finally {
    s.close();
  }
});

await test("snapshot matches per-node accessors in one crossing", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const snap = s.snapshot();
    assert.equal(snap.count, s.nodeCount());
    assert.ok(snap.count > 0);
    for (const column of [snap.parent, snap.firstChild, snap.next, snap.spanStart, snap.spanLen]) {
      assert.equal(column.length, snap.count);
    }
    assert.equal(snap.childCount.length, snap.count);
    assert.equal(snap.variable.length, snap.count);
    assert.equal(snap.isSemanticError.length, snap.count);
    for (let i = 0; i < snap.count; i++) {
      const node = BigInt(i);
      const parent = s.parent(node);
      assert.equal(snap.parent[i], parent === null ? INVALID_NODE : parent.address);
      const first = s.firstChild(node);
      assert.equal(snap.firstChild[i], first === null ? INVALID_NODE : first.address);
      const next = s.nextSibling(node);
      assert.equal(snap.next[i], next === null ? INVALID_NODE : next.address);
      assert.equal(snap.childCount[i], s.childCount(node));
      const variable = s.variableIndex(node);
      assert.equal(snap.variable[i], variable === null ? -1n : BigInt(variable));
      const span = s.span(node);
      assert.ok(span !== null);
      assert.equal(snap.spanStart[i], span[0]);
      assert.equal(snap.spanLen[i], span[1]);
    }
    // The snapshot alone drives the same preorder walk as the walker.
    const root = s.rootNode();
    assert.ok(root !== null);
    const preorder = [];
    const stack = [root.address];
    while (stack.length > 0) {
      const node = stack.pop();
      preorder.push(node);
      let child = snap.firstChild[Number(node)];
      const chain = [];
      while (child !== INVALID_NODE) {
        chain.push(child);
        child = snap.next[Number(child)];
      }
      assert.equal(chain.length, snap.childCount[Number(node)]);
      for (let k = chain.length - 1; k >= 0; k--) stack.push(chain[k]);
    }
    const walked = [];
    const walker = s.walk(root);
    assert.ok(walker !== null);
    try {
      for (const step of walker) walked.push(step.node.address);
    } finally {
      walker.close();
    }
    assert.deepEqual(preorder, walked);
  } finally {
    s.close();
  }
});

await test("lastInput buffers snapshot spans and starts empty", async () => {
  const fresh = await newSession();
  try {
    assert.equal(fresh.lastInput().length, 0);
  } finally {
    fresh.close();
  }
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const input = s.lastInput();
    assert.ok(input instanceof Uint8Array);
    assert.deepEqual(Buffer.from(input), Buffer.from("alpha:12,beta:3"));
    const snap = s.snapshot();
    assert.ok(snap.count > 0);
    for (let i = 0; i < snap.count; i++) {
      const text = s.text(BigInt(i));
      assert.ok(text !== null);
      const start = Number(snap.spanStart[i]);
      const end = start + Number(snap.spanLen[i]);
      assert.deepEqual(Buffer.from(input.subarray(start, end)), Buffer.from(text));
    }
  } finally {
    s.close();
  }
});

await test("failed parse keeps the input of the last successful parse", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const retained = Buffer.from(s.lastInput());
    assert.equal(retained.toString(), "alpha:12,beta:3");

    // A failed parse must not clobber the retained input: snapshots
    // from the last successful parse keep indexing it.
    assert.throws(() => s.parse("gamma:"), (err) => err.code === Status.ErrorSyntax);
    assert.deepEqual(Buffer.from(s.lastInput()), retained);

    const snap = s.snapshot();
    assert.ok(snap.count > 0);
    for (let i = 0; i < snap.count; i++) {
      const text = s.text(BigInt(i));
      assert.ok(text !== null);
      const start = Number(snap.spanStart[i]);
      const end = start + Number(snap.spanLen[i]);
      assert.deepEqual(Buffer.from(retained.subarray(start, end)), Buffer.from(text));
    }
  } finally {
    s.close();
  }
});

await test("Node object mirrors Session navigation", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    assert.ok(root !== null);
    // Node methods
    assert.equal(root.symbolName(), "Document");
    assert.ok(root.text() instanceof Uint8Array);
    assert.deepEqual(root.span(), [0n, 15n]);
    assert.deepEqual(root.lineColumn(), [1, 1]);
    assert.equal(root.length, s.childCount(root));
    assert.ok(root.firstChild() !== null);
    assert.ok(root.lastChild() !== null);
    assert.equal(root.parent(), null);
    const kids = root.children();
    assert.equal(kids.length, 1);
    // iterator
    let count = 0;
    for (const child of root) count++;
    assert.equal(count, 1);
    // at()
    assert.ok(root.at(0).equals(kids[0]));
    assert.throws(() => root.at(100), RangeError);
    // equals
    const root2 = s.rootNode();
    assert.ok(root.equals(root2));
    assert.ok(!root.equals(123n));
  } finally {
    s.close();
  }
});

await test("terminal-only nodes have empty symbol names", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    function containsTerminal(n) {
      if (s.symbolName(n) === "") return n;
      let child = s.firstChild(n);
      while (child !== null) {
        const found = containsTerminal(child);
        if (found) return found;
        child = s.nextSibling(child);
      }
      return null;
    }
    const root = s.rootNode();
    assert.ok(containsTerminal(root) !== null);
  } finally {
    s.close();
  }
});

await test("walk matches hand-rolled recursion", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    assert.ok(root !== null);
    function recurse(n, depth, out) {
      out.push([n.address, depth]);
      let child = s.firstChild(n);
      while (child !== null) {
        recurse(child, depth + 1, out);
        child = s.nextSibling(child);
      }
    }
    const expected = [];
    recurse(root, 0, expected);
    assert.ok(expected.length > 1);
    const walker = s.walk(root);
    assert.ok(walker !== null);
    try {
      const walked = [];
      for (const step of walker) {
        assert.equal(step.isSemanticError, false);
        walked.push([step.node.address, step.depth]);
      }
      assert.deepEqual(walked, expected);
    } finally {
      walker.close();
    }
  } finally {
    s.close();
  }
});

await test("walk skipChildren prunes the subtree", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    const walker = s.walk(root);
    assert.ok(walker !== null);
    try {
      const first = walker.next();
      assert.equal(first.done, false);
      assert.ok(first.value.node.equals(root));
      assert.equal(first.value.depth, 0);
      walker.skipChildren();
      assert.equal(walker.next().done, true);
    } finally {
      walker.close();
    }
    assert.equal(s.walk(INVALID_NODE), null);
  } finally {
    s.close();
  }
});

await test("walker step after close throws", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    const walker = s.walk(root);
    assert.ok(walker !== null);
    assert.equal(walker.next().done, false);
    s.close();
    assert.throws(() => walker.next(), SessionClosedError);
    assert.throws(() => walker.skipChildren(), SessionClosedError);
    walker.close();
    walker.close();
  } finally {
    s.close();
  }
});

await test("walker step after re-parse throws", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    const walker = s.walk(root);
    assert.ok(walker !== null);
    assert.equal(walker.next().done, false);
    assert.equal(s.parse("alpha:12,beta:3"), 15);
    assert.throws(() => walker.next(), SessionClosedError);
    assert.throws(() => walker.skipChildren(), SessionClosedError);
    walker.close();
    const fresh = s.rootNode();
    assert.ok(fresh !== null);
    const rewound = s.walk(fresh);
    assert.ok(rewound !== null);
    try {
      assert.equal(rewound.next().done, false);
    } finally {
      rewound.close();
    }
  } finally {
    s.close();
  }
});

await test("node read after re-parse throws", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    assert.ok(root !== null);
    assert.ok(s.childCount(root) > 0);
    s.parse("alpha:12,beta:3");
    assert.throws(() => s.childCount(root), SessionClosedError);
    assert.throws(() => root.text(), SessionClosedError);
    const fresh = s.rootNode();
    assert.ok(fresh !== null);
    assert.ok(s.childCount(fresh) > 0);
  } finally {
    s.close();
  }
});

await test("parse with abandoned walker succeeds", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    const walker = s.walk(root);
    assert.ok(walker !== null);
    // Parsing never throws merely because a walker is open; the
    // abandoned walker fails at its next step instead.
    assert.equal(s.parse("alpha:12,beta:3"), 15);
    assert.throws(() => walker.next(), SessionClosedError);
    walker.close();
  } finally {
    s.close();
  }
});

await test("walker close is idempotent and using disposes", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    const walker = s.walk(root);
    assert.ok(walker !== null);
    walker.close();
    walker.close();
    assert.throws(() => walker.next(), SessionClosedError);
    {
      using scoped = s.walk(root);
      assert.ok(scoped !== null);
      assert.equal(scoped.next().done, false);
    }
  } finally {
    s.close();
  }
});

await test("invalid node accessors return null", async () => {
  const s = await newSession();
  try {
    const invalid = INVALID_NODE;
    assert.equal(s.symbolName(invalid), null);
    assert.equal(s.text(invalid), null);
    assert.equal(s.span(invalid), null);
    assert.equal(s.lineColumn(invalid), null);
    assert.equal(s.variableIndex(invalid), null);
    assert.equal(s.childCount(invalid), 0);
  } finally {
    s.close();
  }
});

// ---- EditTests ----

await test("clean and append round-trip", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    const before = s.childCount(root);
    const head = s.cleanChildren(root);
    assert.ok(head !== null);
    assert.equal(s.childCount(root), 0);
    s.appendChildren(root, head);
    assert.equal(s.childCount(root), before);
  } finally {
    s.close();
  }
});

await test("Node clean/append round-trip", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    const before = root.length;
    const head = root.cleanChildren();
    assert.ok(head !== null);
    assert.equal(root.length, 0);
    root.appendChildren(head);
    assert.equal(root.length, before);
  } finally {
    s.close();
  }
});

await test("insertBefore reorders siblings", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    const wrapper = s.firstChild(root);
    const pair = s.firstChild(wrapper);
    const tail = s.nextSibling(pair);
    const detached = s.removeSiblings(tail, 1);
    assert.ok(detached !== null);
    s.insertBefore(pair, detached);
    assert.ok(s.firstChild(wrapper)?.address === tail.address);
    assert.equal(s.nextSibling(pair), null);
    assert.ok(s.nextSibling(tail)?.address === pair.address);
  } finally {
    s.close();
  }
});

await test("removeSelf detaches single node", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    const first = s.firstChild(root);
    const head = s.removeSelf(first);
    assert.ok(head?.address === first.address);
    assert.equal(s.parent(first), null);
  } finally {
    s.close();
  }
});

await test("insert and remove children at", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    const original = s.childCount(root);
    const head = s.cleanChildren(root);
    s.insertChildrenAt(root, 0, head);
    assert.equal(s.childCount(root), original);
    const removed = s.removeChildrenAt(root, 0, original);
    assert.ok(removed !== null);
    assert.equal(s.childCount(root), 0);
  } finally {
    s.close();
  }
});

await test("promote and unlink wrapper", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    const wrapper = s.firstChild(root);
    const grandchildrenHead = s.cleanChildren(wrapper);
    s.appendChildren(wrapper, grandchildrenHead);
    const promoted = s.promoteChildrenOverWrapper(wrapper);
    assert.ok(promoted !== null);
    const active = [];
    let child = s.firstChild(root);
    while (child !== null) {
      active.push(child);
      child = s.nextSibling(child);
    }
    assert.ok(!active.some((n) => n.address === wrapper.address));
    assert.ok(active.some((n) => n.address === promoted.address));
  } finally {
    s.close();
  }
});

await test("unlink wrapper detaches without touching children", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    const wrapper = s.firstChild(root);
    const before = s.childCount(wrapper);
    s.unlinkWrapper(wrapper);
    assert.equal(s.childCount(wrapper), before);
    assert.ok(s.firstChild(root)?.address !== wrapper.address);
  } finally {
    s.close();
  }
});

// ---- SymbolTableTests ----

await test("symbol and variable tables", async () => {
  const parser = await newParser();
  assert.ok(parser.symbolCount() > 0);
  assert.ok(parser.variableCount() > 0);
  const s = await parser.openSession();
  try {
    const firstName = s.symbolNameAt(0);
    assert.ok(firstName instanceof Uint8Array);
    assert.equal(typeof s.symbolIsTerminal(0), "boolean");
    const varName = s.variableNameAt(0);
    assert.ok(varName instanceof Uint8Array);
    assert.equal(s.symbolNameAt(1_000_000_000), null);
    assert.equal(s.variableNameAt(1_000_000_000), null);
  } finally {
    s.close();
  }
});

// ---- ReservationTests ----

await test("reserve and report capacity", async () => {
  const s = await newSession();
  try {
    const cap = s.nodeCapacity();
    s.reserveNodes(cap + 1024);
    assert.ok(s.nodeCapacity() >= cap + 1024);
  } finally {
    s.close();
  }
});

// ---- LifetimeTests ----

await test("close is idempotent and closed sessions throw", async () => {
  const s = await newSession();
  s.parse("alpha:12");
  s.close();
  s.close();
  assert.throws(() => s.parse("alpha:12"), SessionClosedError);
  assert.throws(() => s.rootNode(), SessionClosedError);
});

await test("Node after close throws", async () => {
  const s = await newSession();
  s.parse("alpha:12,beta:3");
  const root = s.rootNode();
  s.close();
  assert.throws(() => root.children(), SessionClosedError);
  assert.throws(() => root.text(), SessionClosedError);
});

await test("using-like dispose", async () => {
  let s = await newSession();
  const addr = (() => {
    s.parse("alpha:12");
    return s.rootNode()?.address;
  })();
  s.close();
  assert.throws(() => s.parse("alpha:12"), SessionClosedError);
  // Symbol.dispose path if available (Node 24+ supports using)
  // We test manual dispose
  const s2 = await newSession();
  s2[Symbol.dispose]();
  assert.equal(s2.isClosed, true);
  await using s3 = await newSession();
  assert.equal(s3.isClosed, false);
});

await test("options round-trip", async () => {
  const s = await newSession({
    maxErrors: 3,
    recoveryWindow: 100,
    stackOverflowRecovery: false,
    syntaxErrorStackDepth: 8,
    verbosity: 0,
    astPreallocationRatio: 2.0,
    astPreallocationCap: 4096,
  });
  try {
    assert.ok(s.parse("alpha:12") > 0);
  } finally {
    s.close();
  }
});

await test("message override", async () => {
  const s = await newSession();
  try {
    s.setMessageOverride("Number", "custom at line {line}");
    try {
      s.parse("alpha:");
    } catch (err) {
      assert.ok(err.diagnostic.message.includes("custom at line 1"));
    }
    // also via a second session on the same parser
    const parser = await newParser();
    const s2 = await parser.openSession();
    try {
      s2.setMessageOverride("Number", "override2 {line}:{column}");
      try {
        s2.parse("alpha:");
      } catch (err2) {
        assert.ok(err2.diagnostic.message.includes("override2"));
      }
    } finally {
      s2.close();
    }
  } finally {
    s.close();
  }
});

await test("procedure hook can read node text", async () => {
  const seen = [];
  const parser = await newParser();
  parser.installProcedure("reduction_Pair", (args) => {
    const node = args.currentNode();
    assert.ok(node);
    const text = node.text();
    assert.ok(text);
    assert.ok(text.length > 0);
    seen.push(text);
  });
  const s = await parser.openSession();
  try {
    s.parse("alpha:12,beta:3");
    assert.equal(seen.length, 2);
  } finally {
    s.close();
  }
});

await test("hook-reported semantic errors aggregate and fail", async () => {
  const counts = [];
  const parser = await newParser();
  parser.installProcedure("reduction_Number", (args) => {
    const node = args.currentNode();
    assert.ok(node);
    const value = Number.parseInt(Buffer.from(node.text()).toString("utf-8"), 10);
    if (value > 99) counts.push(args.reportSemanticError("value out of range"));
  });
  const s = await parser.openSession();
  try {
    assert.throws(() => s.parse("alpha:12,beta:300,gamma:400"), (err) => {
      assert.equal(err.code, Status.ErrorSemantic);
      assert.ok(String(err.message).includes("value out of range"));
      return true;
    });
    assert.deepEqual(counts, [1, 2]);
    const d = s.diagnostic();
    assert.ok(d);
    assert.equal(d.kind, Kind.Semantic);
    assert.equal(d.semanticErrorCount, 2);
    assert.deepEqual(d.semantic, ["Number", "value out of range"]);
    assert.ok(d.message.includes("SemanticError"));
    const recorded = s.diagnostics();
    assert.equal(recorded.length, 2);
    assert.ok(recorded.every((item) => item.kind === Kind.Semantic));
    s.parse("alpha:12");
    assert.equal(s.diagnostic(), null);
  } finally {
    s.close();
  }
});

await test("installProcedure dispatches host hooks", async () => {
  const parser = await newParser();
  parser.clearProcedures();
  let called = 0;
  parser.installProcedure("reduction", () => { called++; });
  parser.installProcedure("reduction_Pair", () => { called++; });
  assert.deepEqual(Object.keys(parser.listProcedures()).sort(), ["reduction", "reduction_Pair"]);
  const s = await parser.openSession();
  try {
    s.parse("alpha:12,beta:3");
    assert.ok(called > 0, "hooks should have fired");
    const before = called;
    parser.clearProcedures();
    assert.equal(Object.keys(parser.listProcedures()).length, 0);
    s.parse("alpha:12");
    assert.equal(called, before, "hooks should not fire after clear");
  } finally {
    s.close();
  }
});

await test("procedureHook returns the installed callable", async () => {
  const parser = await newParser();
  parser.clearProcedures();
  assert.equal(parser.procedureHook("reduction_Pair"), undefined);
  const hook = () => {};
  parser.installProcedure("reduction_Pair", hook);
  assert.equal(parser.procedureHook("reduction_Pair"), hook);
  assert.equal(parser.listProcedures()["reduction_Pair"], hook);
});

await test("installProcedures bulk registers", async () => {
  const parser = await newParser();
  parser.clearProcedures();
  const mod = {
    reduction_Document: () => {},
    hook_print: () => {},
    notAHook: () => {},
    reduction_Key: "not a function",
  };
  const n = parser.installProcedures(mod);
  assert.equal(n, 2);
  assert.deepEqual(Object.keys(parser.listProcedures()).sort(), ["hook_print", "reduction_Document"]);
  parser.clearProcedures();
});

await test("parser installs serve later sessions", async () => {
  let called = 0;
  const parser = await newParser();
  parser.installProcedures({ reduction_Pair: () => { called++; } });
  const a = await parser.openSession();
  try {
    a.parse("alpha:12,beta:3");
    assert.equal(called, 2);
    assert.equal(typeof parser.listProcedures()["reduction_Pair"], "function");
  } finally {
    a.close();
  }
  const b = await parser.openSession();
  try {
    b.parse("alpha:12");
    assert.equal(called, 3);
  } finally {
    b.close();
  }
  // Reinstalling replaces the hook for every session of the parser.
  let replaced = 0;
  parser.installProcedure("reduction_Pair", () => { replaced++; });
  const c = await parser.openSession();
  try {
    c.parse("alpha:12");
    assert.equal(replaced, 1);
    assert.equal(called, 3);
  } finally {
    c.close();
  }
});

await test("hook throwing does not abort parse", async () => {
  const parser = await newParser();
  parser.installProcedure("reduction_Pair", () => { throw new Error("boom"); });
  const s = await parser.openSession();
  try {
    // should not throw despite hook throwing; parse still succeeds
    const parsed = s.parse("alpha:12,beta:3");
    assert.ok(parsed > 0);
  } finally {
    s.close();
  }
});

await test("one table serves every session of the parser", async () => {
  const parser = await newParser();
  const a = await parser.openSession();
  const b = await parser.openSession();
  const fired = [];
  parser.installProcedure("reduction_Pair", () => { fired.push("shared"); });
  try {
    a.parse("alpha:12,beta:3");
    assert.ok(fired.length === 2 && fired.every((x) => x === "shared"));
    fired.length = 0;
    b.parse("alpha:12,beta:3");
    assert.ok(fired.length === 2 && fired.every((x) => x === "shared"));
    // Reinstalling replaces the hook for both sessions at once.
    fired.length = 0;
    parser.installProcedure("reduction_Pair", () => { fired.push("replaced"); });
    a.parse("alpha:12");
    b.parse("alpha:12");
    a.parse("alpha:12");
    assert.deepEqual(fired, ["replaced", "replaced", "replaced"]);
  } finally {
    a.close();
    b.close();
  }
});

// ---- Wasm-only sources (loadBytes/loadUrl serve bytes and fetched modules) ----

await test("galley.loadBytes resolves a usable parser", async () => {
  const bytes = new Uint8Array(fs.readFileSync(path.join(languageDir, "libgalley-js-wasm.wasm")));
  const parser = await withQuietEnv(() => galley.loadBytes(bytes));
  assert.ok(parser.version().length > 0);
  const s = await parser.openSession();
  try {
    assert.equal(s.parse("alpha:12,beta:3"), 15);
  } finally {
    s.close();
  }
});

await test("byte-fed modules compile off-thread once per distinct bytes", async () => {
  const bytes = new Uint8Array(fs.readFileSync(path.join(languageDir, "libgalley-js-wasm.wasm")));
  __resetModuleCache();
  __resetParserCache();
  const RealModule = WebAssembly.Module;
  const realCompile = WebAssembly.compile;
  let syncCompiles = 0;
  let asyncCompiles = 0;
  WebAssembly.Module = function (...args) {
    syncCompiles++;
    return new RealModule(...args);
  };
  WebAssembly.compile = async (...args) => {
    asyncCompiles++;
    return realCompile(...args);
  };
  try {
    const parser1 = await withQuietEnv(() => galley.loadBytes(bytes));
    const s1 = await parser1.openSession();
    try {
      assert.equal(s1.parse("alpha:12,beta:3"), 15);
    } finally {
      s1.close();
    }
    const parser2 = await withQuietEnv(() => galley.loadBytes(bytes));
    // Identical bytes resolve to the identical parser: no second compile.
    assert.equal(parser2, parser1);
    const s2 = await parser2.openSession();
    try {
      assert.equal(s2.parse("alpha:12,beta:3"), 15);
    } finally {
      s2.close();
    }
  } finally {
    WebAssembly.Module = RealModule;
    WebAssembly.compile = realCompile;
  }
  // The async factory must never block on synchronous compilation, and
  // identical bytes must reuse the compiled module.
  assert.equal(syncCompiles, 0);
  assert.equal(asyncCompiles, 1);
});

await test("garbage bytes reject loudly", async () => {
  await assert.rejects(galley.loadBytes(new Uint8Array([0, 1, 2, 3])), /WebAssembly/);
  await assert.rejects(galley.loadBytes("not-bytes"), /bytes/);
});

await test("galley.loadUrl resolves a usable parser", async () => {
  const bytes = new Uint8Array(fs.readFileSync(path.join(languageDir, "libgalley-js-wasm.wasm")));
  const url = `data:application/wasm;base64,${Buffer.from(bytes).toString("base64")}`;
  const parser = await withQuietEnv(() => galley.loadUrl(url));
  const s = await parser.openSession();
  try {
    assert.equal(s.parse("alpha:12,beta:3"), 15);
  } finally {
    s.close();
  }
});

await test("unreachable url rejects loudly", async () => {
  await assert.rejects(
    galley.loadUrl("http://127.0.0.1:1/grammar.wasm"),
    /fetch|ECONNREFUSED|Failed|Unable to connect/,
  );
  await assert.rejects(galley.loadUrl(42), /URL/);
});

await test("nested parse restores the outer session's hooks", async () => {
  const parser = await newParser();
  const outerSeen = [];
  const innerSeen = [];
  let nested = false;
  function outerPair(args) {
    const node = args.currentNode();
    outerSeen.push(Buffer.from(node.text()).toString());
    if (!nested) {
      nested = true;
      const inner = parser.openSession();
      try {
        parser.clearProcedures();
        parser.installProcedure("reduction_Number", (innerArgs) => {
          innerSeen.push(Buffer.from(innerArgs.currentNode().text()).toString());
        });
        try {
          inner.parse("alpha:9");
        } finally {
          parser.clearProcedures();
          parser.installProcedure("reduction_Pair", outerPair);
        }
      } finally {
        inner.close();
      }
    }
  }
  const s = await parser.openSession();
  try {
    parser.installProcedure("reduction_Pair", outerPair);
    s.parse("alpha:12,beta:3");
    assert.deepEqual(outerSeen, ["alpha:12", "beta:3"]);
    assert.deepEqual(innerSeen, ["9"]);
  } finally {
    s.close();
  }
});

await test("nested parse across symlinked paths keeps hooks", async () => {
  const linkDir = `${languageDir}-link`;
  fs.rmSync(linkDir, { force: true });
  fs.symlinkSync(languageDir, linkDir, "junction");
  try {
    // Same file through two spellings: one shared port and one shared
    // parser, so the inner parse must restore the outer
    // session's gates on unwind.
    const parser = await openLanguageDirectory(languageDir, { backend: "wasm" });
    const alias = await openLanguageDirectory(linkDir, { backend: "wasm" });
    assert.equal(alias, parser);
    const a = await parser.openSession();
    const b = await parser.openSession();
    let outerCalls = 0;
    let nested = false;
    parser.installProcedure("reduction_Pair", () => {
      outerCalls++;
      if (!nested) {
        nested = true;
        b.parse("alpha:9");
      }
    });
    try {
      assert.ok(a.parse("alpha:12,beta:3,gamma:4") > 0);
      // The inner parse shares the table, so its pair fires the hook too.
      assert.equal(outerCalls, 4);
    } finally {
      a.close();
      b.close();
    }
  } finally {
    fs.rmSync(linkDir, { force: true });
  }
});

await test("nested parse across symlinked file keeps hooks", async () => {
  if (process.platform === "win32") {
    // File symlinks need privileges on Windows; directory junctions
    // (covered above) are the portable case.
    console.log("  (skip: file symlinks need privileges on Windows)");
    return;
  }
  const linkFile = `${languageDir}-link${path.extname(exampleLib)}`;
  fs.rmSync(linkFile, { force: true });
  fs.symlinkSync(path.join(languageDir, exampleLib), linkFile);
  try {
    // Same library through directory and symlinked-file spellings:
    // one shared port and one shared parser. Covers
    // findLibraryFile's half.
    const parser = await openLanguageDirectory(languageDir, { backend: "wasm" });
    const alias = await galley.load(linkFile, { backend: "wasm" });
    assert.equal(alias, parser);
    const a = await parser.openSession();
    const b = await parser.openSession();
    let outerCalls = 0;
    let nested = false;
    parser.installProcedure("reduction_Pair", () => {
      outerCalls++;
      if (!nested) {
        nested = true;
        b.parse("alpha:9");
      }
    });
    try {
      assert.ok(a.parse("alpha:12,beta:3,gamma:4") > 0);
      assert.equal(outerCalls, 4);
    } finally {
      a.close();
      b.close();
    }
  } finally {
    fs.rmSync(linkFile, { force: true });
  }
});

await test("two language directories parse independently", async () => {
  const secondDir = `${languageDir}-second`;
  fs.rmSync(secondDir, { recursive: true, force: true });
  fs.cpSync(languageDir, secondDir, { recursive: true });
  try {
    const fired = [];
    const parserA = await openLanguageDirectory(languageDir, { backend: "wasm" });
    parserA.installProcedure("reduction_Pair", () => { fired.push("a-pair"); });
    const parserB = await openLanguageDirectory(secondDir, { backend: "wasm" });
    // Divergent hook tables: each parser gates only its own hooks, so
    // interleaved parses never fire the other parser's hooks.
    parserB.installProcedure("reduction_Number", () => { fired.push("b-number"); });
    const a = await parserA.openSession();
    const b = await parserB.openSession();
    try {
      assert.equal(a.parse("alpha:12,beta:3"), 15);
      assert.ok(fired.length === 2 && fired.every((x) => x === "a-pair"));
      fired.length = 0;
      assert.equal(b.parse("alpha:12,beta:3"), 15);
      assert.ok(fired.length === 2 && fired.every((x) => x === "b-number"));
      fired.length = 0;
      a.parse("alpha:12");
      b.parse("alpha:12");
      assert.deepEqual(fired, ["a-pair", "b-number"]);
    } finally {
      a.close();
      b.close();
    }
  } finally {
    fs.rmSync(secondDir, { recursive: true, force: true });
  }
});

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
