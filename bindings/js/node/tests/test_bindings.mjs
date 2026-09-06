#!/usr/bin/env node
/**
 * Behavioral tests for the Galley TypeScript bindings.
 * Mirrors `bindings/python/tests/test_bindings.py`.
 *
 * Run:
 *   node bindings/js/node/tests/test_bindings.mjs
 * or with explicit library:
 *   GALLEY_LIBRARY_PATH=/tmp/libgalley-js-node.dylib node ...
 */

import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const exampleLib = (() => {
  if (process.platform === "darwin") return "libgalley-js-node.dylib";
  if (process.platform === "win32") return "galley-js-node.dll";
  return "libgalley-js-node.so";
})();
const defaultLibPath = path.resolve(__dirname, "../../../../examples/js/node", exampleLib);
const libPath = process.env.GALLEY_LIBRARY_PATH ?? (fs.existsSync(defaultLibPath) ? defaultLibPath : undefined);

// Must set before import if using env-based discovery
if (libPath && !process.env.GALLEY_LIBRARY_PATH) process.env.GALLEY_LIBRARY_PATH = libPath;

const {
  Session,
  Node,
  version,
  parserType,
  hasAst,
  hasProcedures,
  allowsNoAstTreeProcedures,
  sourceRetentionEnabled,
  hasPositionTracking,
  hasInputStreaming,
  usesVerbatim,
  stackOverflowRecoveryAvailable,
  errorRecoveryMode,
  symbolCount,
  variableCount,
  statusString,
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
  installProcedure,
  installProcedures,
  clearProcedures,
  listProcedures,
} = await import("../dist/index.js");

// Helper to create session with library path
function newSession(opts = {}) {
  if (libPath) return new Session({ libraryPath: libPath, ...opts });
  return new Session(opts);
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

// ---- ModuleSurfaceTests ----

await test("version returns non-empty string", () => {
  const v = version();
  assert.equal(typeof v, "string");
  assert.notEqual(v, "");
});

await test("parser metadata flags are consistent", () => {
  assertIn(parserType(), [PARSER_TYPE_LL, PARSER_TYPE_LR]);
  assert.equal(hasAst(), true);
  assert.equal(typeof hasProcedures(), "boolean");
  assert.equal(typeof allowsNoAstTreeProcedures(), "boolean");
  assert.equal(typeof sourceRetentionEnabled(), "boolean");
  assert.equal(typeof hasPositionTracking(), "boolean");
  assert.equal(typeof hasInputStreaming(), "boolean");
  assert.equal(typeof usesVerbatim(), "boolean");
  assert.equal(typeof stackOverflowRecoveryAvailable(), "boolean");
  assertIn(errorRecoveryMode(), [RECOVERY_MODE_DISABLED, RECOVERY_MODE_AUTOMATIC, RECOVERY_MODE_EXPLICIT]);
});

await test("status_string renders known codes", () => {
  const rendered = statusString(-2);
  assert.equal(typeof rendered, "string");
  assert.ok(rendered.toLowerCase().includes("syntax"));
  assert.equal(statusString(999999), null);
});

// ---- SessionTests ----

await test("parse accepts string and buffers", () => {
  const s = newSession();
  try {
    const sample = "alpha:12,beta:3";
    assert.equal(s.parse(sample), sample.length);
    assert.equal(s.parse(Buffer.from(sample, "utf-8")), sample.length);
    assert.equal(s.parse(new Uint8Array(Buffer.from(sample))), sample.length);
  } finally {
    s.close();
  }
});

await test("parseSentinel matches parse for nul-free input", () => {
  const s = newSession();
  try {
    const sample = "alpha:12,beta:3";
    const a = s.parseSentinel(sample);
    const b = s.parse(sample);
    assert.equal(a, b);
  } finally {
    s.close();
  }
});

await test("syntax error raises error with code and diagnostic", () => {
  const s = newSession();
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

await test("diagnostic resets after successful parse", () => {
  const s = newSession();
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

await test("file parsing reports end position", () => {
  const s = newSession();
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

await test("root and navigation links", () => {
  const s = newSession();
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

await test("symbol names text spans and positions", () => {
  const s = newSession();
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

await test("Node object mirrors Session navigation", () => {
  const s = newSession();
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

await test("terminal-only nodes have empty symbol names", () => {
  const s = newSession();
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

await test("walk matches hand-rolled recursion", () => {
  const s = newSession();
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

await test("walk skipChildren prunes the subtree", () => {
  const s = newSession();
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

await test("invalid node accessors return null", () => {
  const s = newSession();
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

await test("clean and append round-trip", () => {
  const s = newSession();
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

await test("Node clean/append round-trip", () => {
  const s = newSession();
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

await test("insertBefore reorders siblings", () => {
  const s = newSession();
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

await test("removeSelf detaches single node", () => {
  const s = newSession();
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

await test("insert and remove children at", () => {
  const s = newSession();
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

await test("promote and unlink wrapper", () => {
  const s = newSession();
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

await test("unlink wrapper detaches without touching children", () => {
  const s = newSession();
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

await test("symbol and variable tables", () => {
  const s = newSession();
  try {
    assert.ok(symbolCount() > 0);
    assert.ok(variableCount() > 0);
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

await test("reserve and report capacity", () => {
  const s = newSession();
  try {
    const cap = s.nodeCapacity();
    s.reserveNodes(cap + 1024);
    assert.ok(s.nodeCapacity() >= cap + 1024);
  } finally {
    s.close();
  }
});

// ---- LifetimeTests ----

await test("close is idempotent and closed sessions throw", () => {
  const s = newSession();
  s.parse("alpha:12");
  s.close();
  s.close();
  assert.throws(() => s.parse("alpha:12"), /closed/);
  assert.throws(() => s.rootNode(), /closed/);
});

await test("Node after close throws", () => {
  const s = newSession();
  s.parse("alpha:12,beta:3");
  const root = s.rootNode();
  s.close();
  assert.throws(() => root.children(), /closed/);
  assert.throws(() => root.text(), /closed/);
});

await test("using-like dispose", () => {
  let s = newSession();
  const addr = (() => {
    s.parse("alpha:12");
    return s.rootNode()?.address;
  })();
  s.close();
  assert.throws(() => s.parse("alpha:12"));
  // Symbol.dispose path if available (Node 24+ supports using)
  // We test manual dispose
  const s2 = newSession();
  s2[Symbol.dispose]();
  assert.equal(s2.isClosed, true);
});

await test("options round-trip", () => {
  const s = newSession({
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

await test("message override", () => {
  const s = newSession({ messageOverrides: { Number: "custom at line {line}" } });
  try {
    try {
      s.parse("alpha:");
    } catch (err) {
      assert.ok(err.diagnostic.message.includes("custom at line 1"));
    }
    // also via method
    const s2 = newSession();
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

await test("procedure hook can read node text", () => {
  clearProcedures();
  const seen = [];
  installProcedure("reduction_Pair", (args) => {
    const node = args.currentNode();
    assert.ok(node);
    const text = node.text();
    assert.ok(text);
    assert.ok(text.length > 0);
    seen.push(text);
  });
  const s = newSession();
  try {
    s.parse("alpha:12,beta:3");
    assert.equal(seen.length, 2);
  } finally {
    s.close();
    clearProcedures();
  }
});

await test("hook-reported semantic errors aggregate and fail", () => {
  clearProcedures();
  const counts = [];
  installProcedure("reduction_Number", (args) => {
    const node = args.currentNode();
    assert.ok(node);
    const value = Number.parseInt(Buffer.from(node.text()).toString("utf-8"), 10);
    if (value > 99) counts.push(args.reportSemanticError("value out of range"));
  });
  const s = newSession();
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
    clearProcedures();
  }
});

await test("installProcedure dispatches host hooks", () => {
  clearProcedures();
  let called = 0;
  installProcedure("reduction", () => { called++; });
  installProcedure("reduction_Pair", () => { called++; });
  assert.deepEqual(listProcedures().sort(), ["reduction", "reduction_Pair"].sort());
  const s = newSession();
  try {
    s.parse("alpha:12,beta:3");
    assert.ok(called > 0, "hooks should have fired");
    const before = called;
    clearProcedures();
    assert.equal(listProcedures().length, 0);
    s.parse("alpha:12");
    assert.equal(called, before, "hooks should not fire after clear");
  } finally {
    s.close();
    clearProcedures();
  }
});

await test("installProcedures bulk registers", () => {
  clearProcedures();
  const mod = {
    reduction_Document: () => {},
    hook_print: () => {},
    notAHook: () => {},
    reduction_Key: "not a function",
  };
  const n = installProcedures(mod);
  assert.equal(n, 2);
  assert.deepEqual(listProcedures().sort(), ["hook_print", "reduction_Document"].sort());
  clearProcedures();
});

await test("hook throwing does not abort parse", () => {
  clearProcedures();
  installProcedure("reduction_Pair", () => { throw new Error("boom"); });
  const s = newSession();
  try {
    // should not throw despite hook throwing; parse still succeeds
    const parsed = s.parse("alpha:12,beta:3");
    assert.ok(parsed > 0);
  } finally {
    s.close();
    clearProcedures();
  }
});

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
