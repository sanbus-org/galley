#!/usr/bin/env node
/**
 * Behavioral tests for the Galley TypeScript bindings.
 * Mirrors `bindings/python/tests/test_bindings.py`.
 *
 * Run:
 *   node bindings/js/wasm/tests/test_bindings.mjs
 *
 * Uses the shared fixture (bindings/js/test-fixture), built on demand
 * into a temp workdir; sessions open it through fromDirectory.
 */

import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { wasmArtifactFileName } from "@sanbus/galley-core";
import { ensureTestLibrary } from "../../../js/core/build/fixture.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const exampleLib = wasmArtifactFileName("galley-js-wasm");
// Self-built shared fixture (bindings/js/test-fixture); never examples/.
const languageDir = ensureTestLibrary({
  buildCommand: ["node", path.join(__dirname, "..", "build.mjs")],
  libFileName: exampleLib,
  scope: "wasm",
});

const {
  Session,
  __resetModuleCache,
  Node,
  PARSER_TYPE_LL,
  PARSER_TYPE_LR,
  RECOVERY_MODE_DISABLED,
  RECOVERY_MODE_AUTOMATIC,
  RECOVERY_MODE_EXPLICIT,
  KIND_SYNTAX,
  KIND_NONE,
  KIND_SEMANTIC,
  STATUS_ERROR_SEMANTIC,
  INVALID_NODE,
} = await import("../dist/index.js");

async function newSession(opts = {}) {
  return Session.fromDirectory(languageDir, opts);
}

let passed = 0;
let failed = 0;

async function test(name, fn) {
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

// ---- SessionSurfaceTests (grammar queries live on the session) ----

await test("fromDirectory requires languagePath", async () => {
  assert.throws(() => Session.fromDirectory(""), /languagePath/);
  assert.throws(() => Session.fromDirectory(), /languagePath/);
});

await test("fromDirectory resolves a usable session", async () => {
  await using s = await Session.fromDirectory(languageDir);
  assert.ok(s.version().length > 0);
});

await test("missing artifact names the directory", async () => {
  assert.throws(
    () => Session.fromDirectory(path.join(languageDir, "no-such-dir")),
    /no-such-dir/,
  );
});

await test("fromFile requires filePath", async () => {
  assert.throws(() => Session.fromFile(""), /filePath/);
  assert.throws(() => Session.fromFile(), /filePath/);
});

await test("fromFile missing artifact names the file", async () => {
  assert.throws(
    () => Session.fromFile(path.join(languageDir, "no-such-lib")),
    /no-such-lib/,
  );
});

await test("fromFile opens an explicit artifact file", async () => {
  const fileDir = `${languageDir}-file`;
  fs.rmSync(fileDir, { recursive: true, force: true });
  fs.cpSync(languageDir, fileDir, { recursive: true });
  const customLib = path.join(fileDir, `custom-name${path.extname(exampleLib)}`);
  fs.renameSync(path.join(fileDir, exampleLib), customLib);
  try {
    const s = Session.fromFile(customLib);
    try {
      // Sibling scan: the file's own directory provides hooks.
      assert.ok(s.listProcedures().includes("reduction_Pair"));
      assert.equal(s.parse("alpha:12,beta:3"), 15);
    } finally {
      s.close();
    }
    // Explicit procedures win over the sibling scan.
    let called = 0;
    const s2 = Session.fromFile(customLib, { procedures: { reduction_Pair: () => { called++; } } });
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

await test("version returns non-empty string", async () => {
  const s = await newSession();
  try {
    const v = s.version();
    assert.equal(typeof v, "string");
    assert.notEqual(v, "");
  } finally {
    s.close();
  }
});

await test("parser metadata flags are consistent", async () => {
  const s = await newSession();
  try {
    assertIn(s.parserType(), [PARSER_TYPE_LL, PARSER_TYPE_LR]);
    assert.equal(s.hasAst(), true);
    assert.equal(typeof s.hasProcedures(), "boolean");
    assert.equal(typeof s.allowsNoAstTreeProcedures(), "boolean");
    assert.equal(typeof s.sourceRetentionEnabled(), "boolean");
    assert.equal(typeof s.hasPositionTracking(), "boolean");
    assert.equal(typeof s.hasInputStreaming(), "boolean");
    assert.equal(typeof s.usesVerbatim(), "boolean");
    assert.equal(typeof s.stackOverflowRecoveryAvailable(), "boolean");
    assertIn(s.errorRecoveryMode(), [RECOVERY_MODE_DISABLED, RECOVERY_MODE_AUTOMATIC, RECOVERY_MODE_EXPLICIT]);
  } finally {
    s.close();
  }
});

await test("status_string renders known codes", async () => {
  const s = await newSession();
  try {
    const rendered = s.statusString(-2);
    assert.equal(typeof rendered, "string");
    assert.ok(rendered.toLowerCase().includes("syntax"));
    assert.equal(s.statusString(999999), null);
  } finally {
    s.close();
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
  } finally {
    s.close();
  }
});

await test("parseSentinel matches parse for nul-free input", async () => {
  const s = await newSession();
  try {
    const sample = "alpha:12,beta:3";
    const a = s.parseSentinel(sample);
    const b = s.parse(sample);
    assert.equal(a, b);
  } finally {
    s.close();
  }
});

await test("syntax error raises error with code and diagnostic", async () => {
  const s = await newSession();
  try {
    try {
      s.parse("alpha:");
      assert.fail("expected error");
    } catch (err) {
      assert.equal(err.code, -2);
      assert.ok(err.diagnostic);
      const d = err.diagnostic;
      assert.equal(d.kind, KIND_SYNTAX);
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
    const p = "/tmp/galley-js-wasm-test.kv";
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
  const s = await newSession();
  try {
    assert.ok(s.symbolCount() > 0);
    assert.ok(s.variableCount() > 0);
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
  assert.throws(() => s.parse("alpha:12"), /closed/);
  assert.throws(() => s.rootNode(), /closed/);
});

await test("Node after close throws", async () => {
  const s = await newSession();
  s.parse("alpha:12,beta:3");
  const root = s.rootNode();
  s.close();
  assert.throws(() => root.children(), /closed/);
  assert.throws(() => root.text(), /closed/);
});

await test("using-like dispose", async () => {
  let s = await newSession();
  const addr = (() => {
    s.parse("alpha:12");
    return s.rootNode()?.address;
  })();
  s.close();
  assert.throws(() => s.parse("alpha:12"));
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
  const s = await newSession({ messageOverrides: { Number: "custom at line {line}" } });
  try {
    try {
      s.parse("alpha:");
    } catch (err) {
      assert.ok(err.diagnostic.message.includes("custom at line 1"));
    }
    // also via method
    const s2 = await newSession();
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
  const s = await newSession();
  s.installProcedure("reduction_Pair", (args) => {
    const node = args.currentNode();
    assert.ok(node);
    const text = node.text();
    assert.ok(text);
    assert.ok(text.length > 0);
    seen.push(text);
  });
  try {
    s.parse("alpha:12,beta:3");
    assert.equal(seen.length, 2);
  } finally {
    s.close();
  }
});

await test("hook-reported semantic errors aggregate and fail", async () => {
  const counts = [];
  const s = await newSession();
  s.installProcedure("reduction_Number", (args) => {
    const node = args.currentNode();
    assert.ok(node);
    const value = Number.parseInt(Buffer.from(node.text()).toString("utf-8"), 10);
    if (value > 99) counts.push(args.reportSemanticError("value out of range"));
  });
  try {
    assert.throws(() => s.parse("alpha:12,beta:300,gamma:400"), (err) => {
      assert.equal(err.code, STATUS_ERROR_SEMANTIC);
      assert.ok(String(err.message).includes("value out of range"));
      return true;
    });
    assert.deepEqual(counts, [1, 2]);
    const d = s.diagnostic();
    assert.ok(d);
    assert.equal(d.kind, KIND_SEMANTIC);
    assert.equal(d.semanticErrorCount, 2);
    assert.deepEqual(d.semantic, ["Number", "value out of range"]);
    assert.ok(d.message.includes("SemanticError"));
    const recorded = s.diagnostics();
    assert.equal(recorded.length, 2);
    assert.ok(recorded.every((item) => item.kind === KIND_SEMANTIC));
    s.parse("alpha:12");
    assert.equal(s.diagnostic(), null);
  } finally {
    s.close();
  }
});

await test("installProcedure dispatches host hooks", async () => {
  const s = await newSession();
  s.clearProcedures();
  let called = 0;
  s.installProcedure("reduction", () => { called++; });
  s.installProcedure("reduction_Pair", () => { called++; });
  assert.deepEqual(s.listProcedures().sort(), ["reduction", "reduction_Pair"].sort());
  try {
    s.parse("alpha:12,beta:3");
    assert.ok(called > 0, "hooks should have fired");
    const before = called;
    s.clearProcedures();
    assert.equal(s.listProcedures().length, 0);
    s.parse("alpha:12");
    assert.equal(called, before, "hooks should not fire after clear");
  } finally {
    s.close();
  }
});

await test("installProcedures bulk registers", async () => {
  const s = await newSession();
  try {
    s.clearProcedures();
    const mod = {
      reduction_Document: () => {},
      hook_print: () => {},
      notAHook: () => {},
      reduction_Key: "not a function",
    };
    const n = s.installProcedures(mod);
    assert.equal(n, 2);
    assert.deepEqual(s.listProcedures().sort(), ["hook_print", "reduction_Document"].sort());
    s.clearProcedures();
  } finally {
    s.close();
  }
});

await test("procedures option installs at construction", async () => {
  let called = 0;
  const s = await newSession({ procedures: { reduction_Pair: () => { called++; } } });
  try {
    s.parse("alpha:12,beta:3");
    assert.equal(called, 2);
    assert.ok(s.listProcedures().includes("reduction_Pair"));
  } finally {
    s.close();
  }
});

await test("hook throwing does not abort parse", async () => {
  const s = await newSession();
  s.installProcedure("reduction_Pair", () => { throw new Error("boom"); });
  try {
    // should not throw despite hook throwing; parse still succeeds
    const parsed = s.parse("alpha:12,beta:3");
    assert.ok(parsed > 0);
  } finally {
    s.close();
  }
});

await test("same-named hooks resolve per session", async () => {
  const a = await newSession();
  const b = await newSession();
  const fired = [];
  a.installProcedure("reduction_Pair", () => { fired.push("a"); });
  b.installProcedure("reduction_Pair", () => { fired.push("b"); });
  try {
    a.parse("alpha:12,beta:3");
    assert.ok(fired.length === 2 && fired.every((x) => x === "a"));
    fired.length = 0;
    b.parse("alpha:12,beta:3");
    assert.ok(fired.length === 2 && fired.every((x) => x === "b"));
    // interleaved parses re-sync each session's hooks in turn
    fired.length = 0;
    a.parse("alpha:12");
    b.parse("alpha:12");
    a.parse("alpha:12");
    assert.deepEqual(fired, ["a", "b", "a"]);
  } finally {
    a.close();
    b.close();
  }
});

// ---- Wasm-only sources (fromBytes/fromUrl live only on wasm-capable entries) ----

await test("fromBytes resolves a usable session", async () => {
  const bytes = new Uint8Array(fs.readFileSync(path.join(languageDir, "libgalley-js-wasm.wasm")));
  await using s = await Session.fromBytes(bytes);
  assert.equal(s.parse("alpha:12,beta:3"), 15);
  assert.ok(s.version().length > 0);
});

await test("byte-fed modules compile off-thread once per distinct bytes", async () => {
  const bytes = new Uint8Array(fs.readFileSync(path.join(languageDir, "libgalley-js-wasm.wasm")));
  __resetModuleCache();
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
    await using s1 = await Session.fromBytes(bytes);
    assert.equal(s1.parse("alpha:12,beta:3"), 15);
    await using s2 = await Session.fromBytes(bytes);
    assert.equal(s2.parse("alpha:12,beta:3"), 15);
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
  await assert.rejects(Session.fromBytes(new Uint8Array([0, 1, 2, 3])), /WebAssembly/);
  await assert.rejects(Session.fromBytes("not-bytes"), /bytes/);
});

await test("fromUrl resolves a usable session", async () => {
  const bytes = new Uint8Array(fs.readFileSync(path.join(languageDir, "libgalley-js-wasm.wasm")));
  const url = `data:application/wasm;base64,${Buffer.from(bytes).toString("base64")}`;
  await using s = await Session.fromUrl(url);
  assert.equal(s.parse("alpha:12,beta:3"), 15);
});

await test("unreachable url rejects loudly", async () => {
  await assert.rejects(
    Session.fromUrl("http://127.0.0.1:1/grammar.wasm"),
    /fetch|ECONNREFUSED|Failed|Unable to connect/,
  );
  await assert.rejects(Session.fromUrl(42), /URL/);
});

await test("nested parse restores the outer session's hooks", async () => {
  const a = await newSession();
  const b = await newSession();
  a.clearProcedures();
  b.clearProcedures();
  let outerCalls = 0;
  let nested = false;
  a.installProcedure("reduction_Pair", () => {
    outerCalls++;
    if (!nested) {
      nested = true;
      // The inner session holds no hooks, so its parse clears every
      // native gate. The outer parse must re-enable its own gates on
      // unwind: all three pairs fire, not just the first.
      b.parse("zeta:9");
    }
  });
  try {
    assert.ok(a.parse("alpha:12,beta:3,gamma:4") > 0);
    assert.equal(outerCalls, 3);
  } finally {
    a.close();
    b.close();
  }
});

await test("nested parse across symlinked paths keeps hooks", async () => {
  const linkDir = `${languageDir}-link`;
  fs.rmSync(linkDir, { force: true });
  fs.symlinkSync(languageDir, linkDir, "junction");
  try {
    // Same file through two spellings: one shared port, so the inner
    // parse must restore the outer session's gates on unwind.
    const a = await Session.fromDirectory(languageDir);
    const b = await Session.fromDirectory(linkDir);
    a.clearProcedures();
    b.clearProcedures();
    let outerCalls = 0;
    let nested = false;
    a.installProcedure("reduction_Pair", () => {
      outerCalls++;
      if (!nested) {
        nested = true;
        b.parse("zeta:9");
      }
    });
    try {
      assert.ok(a.parse("alpha:12,beta:3,gamma:4") > 0);
      assert.equal(outerCalls, 3);
    } finally {
      a.close();
      b.close();
    }
  } finally {
    fs.rmSync(linkDir, { force: true });
  }
});

await test("two language directories parse independently", async () => {
  const secondDir = `${languageDir}-second`;
  fs.rmSync(secondDir, { recursive: true, force: true });
  fs.cpSync(languageDir, secondDir, { recursive: true });
  try {
    const fired = [];
    const a = await Session.fromDirectory(languageDir);
    a.installProcedure("reduction_Pair", () => { fired.push("a-pair"); });
    const b = await Session.fromDirectory(secondDir);
    // Divergent hook sets: each session enables only its own gates, so
    // interleaved parses never fire the other session's hooks.
    b.installProcedure("reduction_Number", () => { fired.push("b-number"); });
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
