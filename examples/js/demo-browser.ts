/**
 * Browser demo for the universal example: the same grammar and the same
 * procedures as `demo.ts` through `@sanbus/galley/browser` (wasm only, no
 * `node:` specifier in this file's import graph). Output rows shared with
 * the runtime demo use the same formats.
 */

import {
  init,
  installProcedures,
  Session,
  KIND_SYNTAX,
  KIND_INDENTATION,
  type Node,
} from "@sanbus/galley/browser";
import * as procedures from "./procedures.ts";

const VALID_SAMPLE = "alpha:12,beta:3";
const BROKEN_SAMPLE = "alpha:";
const MULTI_ERROR_SAMPLE = "alpha:13x,beta:,gamma:q";

const utf8 = new TextDecoder();

/**
 * Where the wasm module lives. Browsers load it beside the page; under
 * Node (vite-bundle proof) it comes from the matrix-style static server.
 * Only the bytes location branches — never parse behavior.
 */
function wasmUrl(): string {
  const location = (globalThis as { location?: { href: string } }).location;
  if (location) return new URL("./libgalley-js-wasm.wasm", location.href).href;
  return "http://127.0.0.1:8123/grammar.wasm";
}

function fail(message: string): never {
  throw new Error(`browser demo: ${message}`);
}

function printTree(node: Node, depth: number): void {
  const name = node.symbolName();
  const text = node.text();
  if (name === null || text === null) fail("invalid node");
  const pos = node.lineColumn();
  const line = pos ? pos[0] : 0;
  console.log(`${"  ".repeat(depth)}${name} [line ${line}, ${text!.length} bytes]`);
  for (const child of node) {
    printTree(child, depth + 1);
  }
}

async function main(): Promise<void> {
  // Quiet: the fallback notice is stderr noise, and the wasm leg is the
  // only leg here — the runtime demo runs it quiet for the same reason.
  await init({ url: wasmUrl(), quiet: true });
  if (installProcedures(procedures as unknown as Record<string, unknown>) === 0) {
    fail("failed to register procedure hooks");
  }
  const session = new Session({ maxErrors: 10 });
  try {
    console.log(`galley version: ${session.version()}`);

    try {
      session.setMessageOverride(
        "Number",
        "expected a number after ':' (digits only) at line {line}",
      );
    } catch {
      fail("failed to register the message override");
    }

    // Successful parse: walk the tree.
    let parsed: number;
    try {
      parsed = session.parseSentinel(VALID_SAMPLE);
    } catch (err: unknown) {
      fail(`unexpected failure: ${err}`);
    }
    console.log(`parsed ${parsed} bytes, ${session.nodeCount()} AST nodes`);
    if (!session.hasAst()) {
      console.log("AST construction disabled; skipping tree walk");
    } else {
      const root = session.rootNode();
      if (root !== null) printTree(root, 1);
    }

    // Failed parse: inspect the diagnostic.
    try {
      session.parseSentinel(BROKEN_SAMPLE);
      fail("expected the broken sample to fail");
    } catch {
      // expected
    }
    const diagnostic = session.diagnostic();
    if (!diagnostic) fail("expected a diagnostic for the broken sample");
    console.log(`diagnostic at ${diagnostic.line}:${diagnostic.column}: ${diagnostic.message}`);

    let expected = "expected one of: ";
    diagnostic.expectedTokens.forEach((tok, idx) => {
      if (idx !== 0) expected += ", ";
      expected += `'${utf8.decode(tok)}'`;
    });
    console.log(expected);

    let context = "while parsing (innermost first):";
    for (const name of diagnostic.context) context += ` ${name}`;
    console.log(context);

    // Multi-error parse: every recorded diagnostic stays addressable.
    try {
      session.parse(MULTI_ERROR_SAMPLE);
      fail("expected the multi-error sample to fail");
    } catch {
      // expected
    }
    const recorded = session.diagnostics();
    console.log(`recorded diagnostics: ${recorded.length}`);
    recorded.forEach((diag, idx) => {
      const kindName =
        diag.kind === KIND_SYNTAX
          ? "syntax"
          : diag.kind === KIND_INDENTATION
            ? "indentation"
            : "none";
      const unexpected = diag.unexpectedToken ? utf8.decode(diag.unexpectedToken) : "";
      console.log(`  [${idx}] ${kindName} at ${diag.line}:${diag.column} near '${unexpected}'`);
    });

    // Tree editing: detach the root's children, then reattach them.
    if (session.hasAst()) {
      const root = session.rootNode();
      if (!root) fail("expected the root to have children");
      const childrenBefore = root.length;
      const head = root.cleanChildren();
      if (!head) fail("expected the root to have children");
      root.appendChildren(head);
      console.log(`tree edit: ${childrenBefore} children before, ${root.length} after reattach`);
    }
  } finally {
    session.close();
  }
}

await main();
