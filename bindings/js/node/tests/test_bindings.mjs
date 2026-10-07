#!/usr/bin/env node
/**
 * Behavioral tests for the Galley TypeScript bindings.
 *
 * Run:
 *   node bindings/js/node/tests/test_bindings.mjs
 *
 * Uses the shared fixture (bindings/js/test-fixture), built on demand
 * into a temp workdir; sessions open it through the universal entry
 * pinned to the native leg (plus the generated package entry once).
 *
 * The universal dist must be built first:
 *   npm --prefix bindings/js/universal install
 */

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { artifactFileName } from "@sanbus/galley-core/internal";
import { collect } from "../../../js/core/build/collect.mjs";
import { ensureTestLibrary } from "../../../js/core/build/fixture.mjs";
import { runConcurrencyScenario } from "../../../js/core/build/concurrency.mjs";
import { runGenerationScenarios } from "../../../js/core/build/generations.mjs";
import { runRefusalScenarios } from "../../../js/core/build/refusals.mjs";
import { runPublishedFailureScenarios } from "../../../js/core/build/published-failures.mjs";
import { runHookFailureScenarios } from "../../../js/core/build/hook-failures.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const exampleLib = artifactFileName("galley-js-node", process.platform);
// Self-built shared fixture (bindings/js/test-fixture).
const languageDir = ensureTestLibrary({
  buildCommand: ["node", path.join(__dirname, "..", "build.mjs")],
  libFileName: exampleLib,
  scope: "node",
});

const {
  Node,
  SessionClosedError,
  StaleTreeError,
  GalleyError,
  ParserType,
  RecoveryMode,
  Kind,
  Status,
  INVALID_NODE,
} = await import("../dist/index.js");

const { galley, openLanguageDirectory, __resetParserCache, Parser } = await import("../../universal/dist/index.js");

// The fixture's hook module, passed the way the generated entry passes it.
const bundledProcedures = await import(
  pathToFileURL(path.join(languageDir, "procedures.ts")).href
);

async function newParser() {
  return openLanguageDirectory(languageDir, {}, bundledProcedures);
}

async function newSession(opts = {}) {
  const parser = await newParser();
  return parser.openSession(opts);
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

await test("openLanguageDirectory requires languagePath", () => {
  assert.throws(() => openLanguageDirectory(""), /languagePath/);
  assert.throws(() => openLanguageDirectory(), /languagePath/);
});

await test("openLanguageDirectory resolves a usable parser", async () => {
  const parser = await openLanguageDirectory(languageDir);
  assert.ok(parser.version().length > 0);
  const s = await parser.openSession();
  try {
    assert.equal(s.parse("alpha:12,beta:3"), 15);
  } finally {
    s.close();
  }
});

await test("openSession rejects keys outside the parser tunables", async () => {
  const parser = await newParser();
  assert.throws(() => parser.openSession({ backend: "wasm" }), TypeError);
  assert.throws(() => parser.openSession({ procedures: {} }), TypeError);
  assert.throws(() => parser.openSession({ maxError: 1 }), TypeError);
  const s = parser.openSession({ maxErrors: 1 });
  try {
    assert.equal(s.parse("alpha:12,beta:3"), 15);
  } finally {
    s.close();
  }
});

await test("missing artifact names the directory", () => {
  assert.throws(
    () => openLanguageDirectory(path.join(languageDir, "no-such-dir")),
    /no-such-dir/,
  );
});

await test("galley.load requires filePath", () => {
  assert.throws(() => galley.load(""), /filePath/);
  assert.throws(() => galley.load(), /filePath/);
  assert.throws(() => galley.load("no-such-lib\0"), /interior NUL/);
});

await test("galley.load missing artifact names the file", () => {
  assert.throws(
    () => galley.load(path.join(languageDir, "no-such-lib")),
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
    // Bare file loads wire nothing: hooks arrive explicitly only.
    const parser = await galley.load(customLib);
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
  // The entry mirrors the parser's interface: derive the pin from the
  // Parser prototype chain (universal additions over core), excluding
  // the constructor and core's internal `port` accessor.
  const parserInterface = (() => {
    const names = new Set();
    for (let proto = Parser.prototype; proto !== Object.prototype; proto = Object.getPrototypeOf(proto)) {
      for (const name of Object.getOwnPropertyNames(proto)) {
        if (name === "constructor" || name === "port") continue;
        names.add(name);
      }
    }
    return [...names];
  })();
  assert.equal(parserInterface.length, 22);
  assert.deepEqual(
    Object.keys(kv).sort(),
    [...parserInterface, ...surface].sort(),
  );
  // Construction stays direct: the bare class needs a bound port.
  assert.throws(() => new kv.Session(), /bound port/);
  const s = kv.openSession();
  try {
    assert.ok("reduction_Pair" in kv.listProcedures());
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
  assert.equal(typeof ns.StaleTreeError, "function");
});

await test("entry keeps loader internals off the public surface", async () => {
  const ns = await import("../dist/index.js");
  for (const name of ["resolveArtifact", "checkModuleBytes", "encodeUtf8"]) {
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
      assert.ok(Object.isFrozen(d));
      assert.ok(Object.isFrozen(d.expectedTokens));
      assert.ok(Object.isFrozen(d.context));
      assert.throws(() => d.expectedTokens.push(new Uint8Array(0)), TypeError);
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
    // No validity probe: a real read is the answer, and it reads.
    assert.ok(s.childCount(root) > 0);
    assert.equal(s.parent(root), null);
    // A raw address is refused at entry: it carries no session or generation.
    assert.throws(() => s.childCount(INVALID_NODE), TypeError);
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
      const node = snap.node(i);
      assert.ok(node !== null);
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
    const walker = root.walk();
    assert.ok(walker !== null);
    for (const step of walker) walked.push(step.node.address);
    assert.deepEqual(preorder, walked);
  } finally {
    s.close();
  }
});

await test("snapshot node round-trips columns and accessors", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const snap = s.snapshot();
    const root = s.rootNode();
    assert.ok(root !== null);
    // Same parse, same address: the interned node is the very object.
    const node = snap.node(root.address);
    assert.ok(node === root);
    const first = s.firstChild(node);
    assert.ok(first !== null);
    assert.equal(snap.firstChild[Number(node.address)], first.address);
    assert.ok(snap.node(first.address) === first);
    // An absent node link answers null, never a node.
    assert.equal(snap.node(INVALID_NODE), null);
    // Every address and the sentinel are non-negative, and a generation is a
    // plain Number: only statuses are negative, and no BigInt copy rides along.
    assert.equal(INVALID_NODE, 2n ** 63n - 1n);
    assert.equal(typeof s.rootNode().generation, "number");
  } finally {
    s.close();
  }
});

await test("snapshot node out of range throws", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const snap = s.snapshot();
    assert.ok(snap.count > 0);
    assert.throws(() => snap.node(snap.count), RangeError);
    assert.throws(() => snap.node(-1), RangeError);
  } finally {
    s.close();
  }
});

await test("snapshot node refuses values that are not an address", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const snap = s.snapshot();
    const rejected = [
      "0",
      3.5,
      NaN,
      1e300,
      Number.MAX_SAFE_INTEGER + 2,
      true,
      false,
      null,
      undefined,
      {},
      [0],
    ];
    for (const value of rejected) {
      assert.throws(() => snap.node(value), TypeError, `accepted ${String(value)}`);
    }
    // The sanctioned forms still answer.
    assert.ok(snap.node(0) !== null);
    assert.ok(snap.node(0n) !== null);
  } finally {
    s.close();
  }
});

await test("snapshot node is stale after a re-parse", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    assert.ok(root !== null);
    const snap = s.snapshot();
    const stale = snap.node(root.address);
    assert.ok(stale !== null);
    s.parse("alpha:12");
    const fresh = s.rootNode();
    assert.ok(fresh !== null);
    // The columns never follow a later parse, and the re-parse's
    // generation owns the intern table now: the stale snapshot answers
    // with a fresh, uninterned handle on every call, and each handle
    // reads as stale.
    assert.ok(snap.node(root.address) !== stale);
    assert.ok(snap.node(root.address) !== fresh);
    assert.ok(snap.node(root.address) !== snap.node(root.address));
    assert.throws(() => stale.text(), StaleTreeError);
    assert.throws(() => snap.node(root.address).text(), StaleTreeError);
    assert.equal(Buffer.from(fresh.text()).toString(), "alpha:12");
  } finally {
    s.close();
  }
});

await test("one interned node per address of a parse", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    assert.ok(root !== null);
    assert.ok(s.rootNode() === root);
    const child = s.firstChild(root);
    assert.ok(child !== null);
    assert.ok(s.firstChild(root) === child);
    assert.ok(root.children()[0] === child);
    const snap = s.snapshot();
    assert.ok(snap.node(child.address) === child);
    const walker = root.walk();
    assert.ok(walker !== null);
    const step = walker.next();
    assert.equal(step.done, false);
    assert.ok(step.value.node === root);
  } finally {
    s.close();
  }
});

await test("Node construction is closed and the session exposes no creation helpers", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    assert.ok(root !== null);
    assert.ok(root instanceof Node);
    // The constructor demands a module-private token: no argument
    // combination reachable from outside builds a node.
    assert.throws(() => Reflect.construct(Node, []), TypeError);
    assert.throws(() => Reflect.construct(Node, [s, root.address, 0n]), TypeError);
    assert.throws(
      () => Reflect.construct(Node, [Symbol("galley.Node"), s, root.address, 0n]),
      TypeError,
    );
    assert.throws(
      () => Reflect.construct(Node, [s, s, root.address, 0n]),
      TypeError,
    );
    // The creation helpers are not reachable from the session instance.
    assert.ok(!("nodeForGeneration" in s));
    assert.ok(!("publishedGeneration" in s));
    assert.ok(!("nodeValid" in s));
  } finally {
    s.close();
  }
});

await test("lastInput buffers snapshot spans and refuses before any parse", async () => {
  const fresh = await newSession();
  try {
    assert.throws(() => fresh.lastInput(), StaleTreeError);
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
      const text = s.text(snap.node(i));
      assert.ok(text !== null);
      const start = Number(snap.spanStart[i]);
      const end = start + Number(snap.spanLen[i]);
      assert.deepEqual(Buffer.from(input.subarray(start, end)), Buffer.from(text));
    }
  } finally {
    s.close();
  }
});

await test("a parse that publishes nothing retains no input", async () => {
  // One error is the limit, so the failing parse raises instead of recovering.
  const s = await newSession({ maxErrors: 1 });
  try {
    s.parse("alpha:12,beta:3");
    const retained = Buffer.from(s.lastInput());
    assert.equal(retained.toString(), "alpha:12,beta:3");
    const root = s.rootNode();
    assert.ok(root !== null);

    // The input follows the published tree like every read: the failed
    // parse wiped the last successful tree when it started and published
    // none of its own, so the input, node reads and snapshots all refuse
    // until the next successful parse.
    assert.throws(() => s.parse("gamma:"), (err) => err.code === Status.ErrorSyntax);
    assert.throws(() => s.lastInput(), StaleTreeError);
    assert.throws(() => s.snapshot(), StaleTreeError);
    assert.throws(() => s.text(root), StaleTreeError);
    assert.throws(() => root.text(), StaleTreeError);

    // The door reopens on the next successful parse over the same input.
    s.parse("alpha:12,beta:3");
    const snap = s.snapshot();
    assert.ok(snap.count > 0);
    for (let i = 0; i < snap.count; i++) {
      const text = s.text(snap.node(i));
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
    assert.ok(root.at(0) === kids[0]);
    assert.throws(() => root.at(100), RangeError);
    // identity: one interned object per (session, generation, address)
    const root2 = s.rootNode();
    assert.ok(root === root2);
    // The address never converts back into something a call accepts.
    assert.throws(() => s.childCount(root.address), TypeError);
    assert.throws(() => BigInt(root), SyntaxError);
    assert.ok(Number.isNaN(+root));
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
    const walker = root.walk();
    assert.ok(walker !== null);
    const walked = [];
    for (const step of walker) {
      assert.equal(step.isSemanticError, false);
      walked.push([step.node.address, step.depth]);
    }
    assert.deepEqual(walked, expected);
  } finally {
    s.close();
  }
});

await test("walk skipChildren prunes the subtree", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    const walker = root.walk();
    assert.ok(walker !== null);
    const first = walker.next();
    assert.equal(first.done, false);
    assert.ok(first.value.node === root);
    assert.equal(first.value.depth, 0);
    walker.skipChildren();
    assert.equal(walker.next().done, true);
  } finally {
    s.close();
  }
});

await test("walker step after close throws", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    const walker = root.walk();
    assert.ok(walker !== null);
    assert.equal(walker.next().done, false);
    s.close();
    assert.throws(() => walker.next(), SessionClosedError);
    assert.throws(() => walker.skipChildren(), SessionClosedError);
  } finally {
    s.close();
  }
});

await test("walker step after re-parse throws", async () => {
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    const walker = root.walk();
    assert.ok(walker !== null);
    assert.equal(walker.next().done, false);
    assert.equal(s.parse("alpha:12,beta:3"), 15);
    assert.throws(() => walker.next(), StaleTreeError);
    // skipChildren is a pure host-side state write: staleness is the
    // next step's answer, not this one's.
    walker.skipChildren();
    assert.throws(() => walker.next(), StaleTreeError);
    const fresh = s.rootNode();
    assert.ok(fresh !== null);
    const rewound = fresh.walk();
    assert.ok(rewound !== null);
    assert.equal(rewound.next().done, false);
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
    assert.throws(() => s.childCount(root), StaleTreeError);
    assert.throws(() => root.text(), StaleTreeError);
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
    const walker = root.walk();
    assert.ok(walker !== null);
    // Parsing never throws merely because a walker is open; the
    // abandoned walker fails at its next step instead.
    assert.equal(s.parse("alpha:12,beta:3"), 15);
    assert.throws(() => walker.next(), StaleTreeError);
  } finally {
    s.close();
  }
});

await test("accessors refuse raw addresses", async () => {
  // A raw address carries no generation, so an accessor that takes a
  // node refuses it instead of reading whichever node happens to hold
  // that index in whichever parse is current.
  const s = await newSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    assert.ok(root !== null);
    const calls = [
      (address) => s.symbolName(address),
      (address) => s.text(address),
      (address) => s.span(address),
      (address) => s.lineColumn(address),
      (address) => s.variableIndex(address),
      (address) => s.childCount(address),
    ];
    for (const address of [INVALID_NODE, root.address]) {
      for (const call of calls) {
        assert.throws(
          () => call(address),
          (err) => err instanceof TypeError && /expected a Node/.test(err.message),
        );
      }
    }
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

await test("every edit entry refuses a node from another session", async () => {
  // A node crosses as a bare address and the native side only
  // bounds-checks it, so a node from another session would alias whatever
  // node holds that index here. Every entry that takes a node refuses one
  // from another session, not only Node methods.
  const parser = await newParser();
  const s = await parser.openSession();
  const other = await parser.openSession();
  try {
    s.parse("alpha:12,beta:3");
    other.parse("alpha:12");
    const root = s.rootNode();
    const otherRoot = other.rootNode();
    assert.throws(() => root.appendChildren(otherRoot), TypeError);
    assert.throws(() => otherRoot.appendChildren(root), TypeError);
    assert.throws(() => s.appendChildren(root, otherRoot), TypeError);
    assert.throws(() => s.insertBefore(root, otherRoot), TypeError);
    assert.throws(() => s.insertAfter(root, otherRoot), TypeError);
    assert.throws(() => s.insertChildrenAt(root, 0, otherRoot), TypeError);
    assert.throws(() => s.text(otherRoot), TypeError);
    assert.throws(() => other.appendChildren(otherRoot, root), TypeError);
  } finally {
    s.close();
    other.close();
  }
});

await test("a hook refuses nodes of an earlier parse", async () => {
  // A node of the previous parse against a node of the running parse,
  // both directions; the refusal must fire inside the hook.
  const parser = await newParser();
  const s = await parser.openSession();
  try {
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    const refusals = [];
    s.installProcedure("reduction_Pair", (args) => {
      const hookNode = args.currentNode();
      if (!hookNode) return;
      for (const append of [
        () => root.appendChildren(hookNode),
        () => hookNode.appendChildren(root),
      ]) {
        try {
          append();
        } catch (error) {
          refusals.push(error);
        }
      }
    });
    try {
      s.parse("alpha:12,beta:3");
    } finally {
      s.clearProcedures();
    }
    assert.equal(refusals.length, 4);
    assert.ok(refusals.every((error) => error instanceof StaleTreeError));
  } finally {
    s.close();
  }
});

await test("a hook's setCurrentNode refuses a raw address", async () => {
  const parser = await newParser();
  const s = await parser.openSession();
  const refusals = [];
  s.installProcedure("reduction_Pair", (args) => {
    const node = args.currentNode();
    if (node === null) return;
    try {
      args.setCurrentNode(node.address);
      refusals.push(null);
    } catch (error) {
      refusals.push(error);
    }
  });
  try {
    s.parse("alpha:12,beta:3");
  } finally {
    s.clearProcedures();
    s.close();
  }
  assert.ok(refusals.length > 0);
  assert.ok(refusals.every((error) => error instanceof TypeError));
});

await test("a chain detached in one hook attaches in a later hook", async () => {
  // A chain detached in one hook can be attached in a later hook of the
  // same parse: both nodes carry the running parse's generation.
  const parser = await newParser();
  const stash = [];
  const outcomes = [];
  parser.installProcedure("reduction_Pair", (args) => {
    const node = args.currentNode();
    if (stash.length === 0) {
      stash.push(node.cleanChildren());
      return;
    }
    try {
      node.appendChildren(stash[0]);
      outcomes.push("ok");
    } catch (error) {
      outcomes.push(error);
    }
  });
  const s = await parser.openSession();
  try {
    s.parse("alpha:12,beta:3");
  } finally {
    parser.clearProcedures();
    s.close();
  }
  assert.deepEqual(outcomes, ["ok"]);
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

await test("hook nodes outlive their hook and their parse", async () => {
  // The tree belongs to the parse, not to the hook that handed out a
  // node: a node stashed by one hook stays usable from a later hook of
  // the same parse, after the parse succeeds, and refuses only once the
  // session parses again.
  const parser = await newParser();
  const stashed = [];
  const seen = [];
  parser.installProcedure("reduction_Pair", (args) => {
    if (stashed.length === 0) stashed.push(args.currentNode());
  });
  parser.installProcedure("reduction_Document", () => {
    // Only the first parse's hook reads the stash; the stash is stale by the
    // second parse, and a hook that throws would abort that parse.
    if (seen.length === 0) seen.push(new TextDecoder().decode(stashed[0].text()));
  });
  const s = await parser.openSession();
  try {
    s.parse("alpha:12,beta:3");
    assert.deepEqual(seen, ["alpha:12"]);
    assert.equal(new TextDecoder().decode(stashed[0].text()), "alpha:12");
    s.parse("gamma:7");
    assert.throws(() => stashed[0].text(), StaleTreeError);
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
    // A session starts with a copy of the parser's defaults.
    assert.deepEqual(Object.keys(s.listProcedures()).sort(), ["reduction", "reduction_Pair"]);
    s.parse("alpha:12,beta:3");
    assert.ok(called > 0, "hooks should have fired");
    const before = called;
    s.clearProcedures();
    assert.equal(Object.keys(s.listProcedures()).length, 0);
    assert.equal(Object.keys(parser.listProcedures()).length, 2, "the defaults are untouched");
    s.parse("alpha:12");
    assert.equal(called, before, "hooks should not fire after clear");
  } finally {
    s.close();
    parser.clearProcedures();
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

await test("installProcedures warns on hooks hidden in a default export", async () => {
  const parser = await newParser();
  parser.clearProcedures();
  const original = console.warn;
  const lines = [];
  console.warn = (message) => lines.push(String(message));
  try {
    const n = parser.installProcedures({
      default: { hook_print: () => {} },
      helper: () => {},
    });
    assert.equal(n, 0);
  } finally {
    console.warn = original;
  }
  assert.equal(lines.length, 1);
  assert.match(lines[0], /ignoring default export/);
  assert.match(lines[0], /named exports/);
});

await test("installProcedures warns on a default function export", async () => {
  const parser = await newParser();
  parser.clearProcedures();
  const original = console.warn;
  const lines = [];
  console.warn = (message) => lines.push(String(message));
  try {
    const n = parser.installProcedures({ default: () => {} });
    assert.equal(n, 0);
  } finally {
    console.warn = original;
  }
  assert.equal(lines.length, 1);
  assert.match(lines[0], /ignoring default export/);
});

await test("installProcedures stays quiet when a top-level hook covers the default", async () => {
  const parser = await newParser();
  parser.clearProcedures();
  const hook = () => {};
  const original = console.warn;
  const lines = [];
  console.warn = (message) => lines.push(String(message));
  try {
    const n = parser.installProcedures({ default: { hook_print: hook }, hook_print: hook });
    assert.equal(n, 1);
  } finally {
    console.warn = original;
  }
  assert.equal(lines.length, 0);
});

await test("installProcedures warns when a wrong-typed top-level export does not cover the default", async () => {
  const parser = await newParser();
  parser.clearProcedures();
  const original = console.warn;
  const lines = [];
  console.warn = (message) => lines.push(String(message));
  try {
    const n = parser.installProcedures({ default: { hook_print: () => {} }, hook_print: null });
    assert.equal(n, 0);
  } finally {
    console.warn = original;
  }
  assert.equal(lines.length, 1);
  assert.match(lines[0], /ignoring default export/);
});

await test("bundled wiring reports a non-empty module that exports no hooks", async () => {
  const parser = await newParser();
  parser.clearProcedures();
  const original = console.warn;
  const lines = [];
  console.warn = (message) => lines.push(String(message));
  try {
    const broken = { helper: () => {} };
    parser.installBundledProcedures(broken);
    parser.installBundledProcedures(broken); // same module: one report, wasm's double scan included
    parser.installBundledProcedures({ helper: () => {} }); // a distinct broken module still reports
    parser.installBundledProcedures({}); // the build's empty stub shape: silent
    parser.installBundledProcedures(null); // bare load: silent
  } finally {
    console.warn = original;
  }
  assert.equal(lines.length, 2);
  for (const line of lines) assert.match(line, /no hooks wired/);
});

await test("bundled wiring reports a default-shaped module once", async () => {
  const parser = await newParser();
  parser.clearProcedures();
  const original = console.warn;
  const lines = [];
  console.warn = (message) => lines.push(String(message));
  try {
    parser.installBundledProcedures({ default: { hook_print: () => {} } });
  } finally {
    console.warn = original;
  }
  assert.equal(lines.length, 1);
  assert.match(lines[0], /ignoring default export/);
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

await test("sessions own their hooks", async () => {
  const parser = await newParser();
  parser.clearProcedures();
  const a = await parser.openSession();
  const b = await parser.openSession();
  const fired = [];
  a.installProcedure("reduction_Pair", () => { fired.push("a"); });
  b.installProcedure("reduction_Number", () => { fired.push("b"); });
  try {
    a.parse("alpha:12,beta:3");
    assert.deepEqual(fired, ["a", "a"]);
    fired.length = 0;
    b.parse("alpha:12,beta:3");
    assert.deepEqual(fired, ["b", "b"]);
    assert.deepEqual(Object.keys(a.listProcedures()), ["reduction_Pair"]);
    assert.equal(b.procedureHook("reduction_Pair"), undefined);
    // Replacing one session's hook leaves the other untouched.
    fired.length = 0;
    a.installProcedure("reduction_Pair", () => { fired.push("replaced"); });
    a.parse("alpha:12");
    b.parse("alpha:12");
    assert.deepEqual(fired, ["replaced", "b"]);
  } finally {
    a.close();
    b.close();
  }
});

await test("parser installs reach only later sessions", async () => {
  const parser = await newParser();
  parser.clearProcedures();
  let called = 0;
  const earlier = await parser.openSession();
  parser.installProcedure("reduction_Pair", () => { called++; });
  const later = await parser.openSession();
  try {
    earlier.parse("alpha:12,beta:3");
    assert.equal(called, 0);
    later.parse("alpha:12,beta:3");
    assert.equal(called, 2);
    parser.clearProcedures();
    later.parse("alpha:12,beta:3");
    assert.equal(called, 4);
  } finally {
    earlier.close();
    later.close();
  }
});

await test("changing hooks during a parse is refused", async () => {
  const parser = await newParser();
  parser.clearProcedures();
  const s = await parser.openSession();
  const refusals = [];
  s.installProcedure("reduction_Pair", () => {
    for (const change of [() => s.clearProcedures(), () => s.installProcedure("reduction_Number", () => {})]) {
      try {
        change();
      } catch (error) {
        refusals.push(error);
      }
    }
  });
  try {
    s.parse("alpha:12");
    assert.equal(refusals.length, 2);
    assert.ok(refusals.every((error) => error.code === Status.ErrorSessionInUse));
    // The refused changes left the hooks as they were.
    assert.deepEqual(Object.keys(s.listProcedures()), ["reduction_Pair"]);
  } finally {
    s.close();
  }
});

await test("nested parse of another session uses its own hooks", async () => {
  const parser = await newParser();
  parser.clearProcedures();
  const outerSeen = [];
  const innerSeen = [];
  let nested = false;
  const s = await parser.openSession();
  s.installProcedure("reduction_Pair", (args) => {
    outerSeen.push(Buffer.from(args.currentNode().text()).toString());
    if (!nested) {
      nested = true;
      const inner = parser.openSession();
      try {
        inner.installProcedure("reduction_Number", (innerArgs) => {
          innerSeen.push(Buffer.from(innerArgs.currentNode().text()).toString());
        });
        inner.parse("alpha:9");
      } finally {
        inner.close();
      }
    }
  });
  try {
    s.parse("alpha:12,beta:3");
    // Neither parse saw or disturbed the other's hooks.
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
    const parser = await openLanguageDirectory(languageDir);
    const alias = await openLanguageDirectory(linkDir);
    assert.equal(alias, parser);
    let outerCalls = 0;
    let nested = false;
    let b = null;
    parser.installProcedure("reduction_Pair", () => {
      outerCalls++;
      if (!nested) {
        nested = true;
        b.parse("alpha:9");
      }
    });
    const a = await parser.openSession();
    b = await parser.openSession();
    try {
      assert.ok(a.parse("alpha:12,beta:3,gamma:4") > 0);
      // Both sessions copied the parser's default hook, so the nested
      // parse fires its own copy too.
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
    const parser = await openLanguageDirectory(languageDir);
    const alias = await galley.load(linkFile);
    assert.equal(alias, parser);
    let outerCalls = 0;
    let nested = false;
    let b = null;
    parser.installProcedure("reduction_Pair", () => {
      outerCalls++;
      if (!nested) {
        nested = true;
        b.parse("alpha:9");
      }
    });
    const a = await parser.openSession();
    b = await parser.openSession();
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
    const parserA = await openLanguageDirectory(languageDir);
    parserA.installProcedure("reduction_Pair", () => { fired.push("a-pair"); });
    const parserB = await openLanguageDirectory(secondDir);
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

// `galley build` runs with a fake generator and a fake zig that records its arguments and
// fails, so nothing builds: -Doptimize must reach the consumer build only when a mode was chosen.
function recordConsumerBuildArguments(extraArguments) {
  const workDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "galley-optimize-test-"));
  try {
    const checkout = path.join(workDirectory, "checkout");
    fs.mkdirSync(checkout);
    fs.writeFileSync(path.join(checkout, "build.zig"), "");
    const generator = path.join(workDirectory, "generator");
    fs.writeFileSync(generator, '#!/bin/sh\n[ "$1" = --help ] && echo --emit-host-procedures\nexit 0\n', { mode: 0o755 });
    const recorded = path.join(workDirectory, "recorded.txt");
    const fakeZig = path.join(workDirectory, "zig");
    fs.writeFileSync(fakeZig, `#!/bin/sh\nprintf '%s\\n' "$@" > '${recorded}'\nexit 1\n`, { mode: 0o755 });
    const languageDirectory = path.join(workDirectory, "language");
    fs.mkdirSync(languageDirectory);
    fs.writeFileSync(path.join(languageDirectory, "ll.grm"), "");
    const result = spawnSync(
      process.execPath,
      [path.join(__dirname, "..", "..", "universal", "build.mjs"), "build", languageDirectory, "--native-only", ...extraArguments],
      {
        encoding: "utf-8",
        env: { ...process.env, GALLEY_CHECKOUT: checkout, GALLEY_CLI: generator, ZIG_EXECUTABLE: fakeZig },
      },
    );
    assert.equal(result.status, 1, result.stderr);
    return fs.readFileSync(recorded, "utf-8").split("\n");
  } finally {
    fs.rmSync(workDirectory, { recursive: true, force: true });
  }
}

await test("the consumer build gets -Doptimize only when a mode is chosen", () => {
  const defaultArguments = recordConsumerBuildArguments([]);
  assert.ok(defaultArguments.includes("--build-file"));
  assert.deepEqual(defaultArguments.filter((argument) => argument.startsWith("-Doptimize")), []);
  assert.deepEqual(recordConsumerBuildArguments(["--optimize", ""]).filter((argument) => argument.startsWith("-Doptimize")), []);
  assert.ok(recordConsumerBuildArguments(["--optimize", "Debug"]).includes("-Doptimize=Debug"));
});

await runGenerationScenarios({ test, assert, newParser, SessionClosedError, StaleTreeError, GalleyError, Status, collect });
await runPublishedFailureScenarios({ test, assert, newParser, StaleTreeError, GalleyError, Status });
await runHookFailureScenarios({ test, assert, newParser, StaleTreeError, GalleyError, Status, Kind });
await runRefusalScenarios({ test, assert, newParser, StaleTreeError, GalleyError, Status });

await test("two parsers, two sessions each, four threads at once", async () => {
  const secondDirectory = ensureTestLibrary({
    buildCommand: ["node", path.join(__dirname, "..", "build.mjs")],
    libFileName: exampleLib,
    scope: "node",
    second: true,
  });
  await runConcurrencyScenario({
    universalEntry: pathToFileURL(path.join(__dirname, "..", "..", "universal", "dist/index.js")).href,
    firstDirectory: languageDir,
    secondDirectory,
  });
});

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
