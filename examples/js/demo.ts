#!/usr/bin/env node
/**
 * Parses a small key/value document through the Galley TypeScript bindings;
 * output is byte-identical across bindings.
 */

import * as fs from "node:fs";
import process from "node:process";
import { galley, Kind } from "@sanbus/galley";
import type { Session } from "@sanbus/galley";
import * as kv from "./kv/index.mjs";
import * as procedures from "./kv/procedures.ts";

// GALLEY_WASM=1 (or a path to a `.wasm` module file) runs the same demo
// through the WebAssembly backend instead of native. Explicit choice, so
// the fallback notice is silenced process-wide and the output matches
// the native run byte for byte.
function wasmBytes(): Uint8Array | "dir" | null {
  const selected = process.env.GALLEY_WASM;
  if (!selected) return null;
  process.env.GALLEY_QUIET = "1";
  if (selected === "1") return "dir";
  return new Uint8Array(fs.readFileSync(selected));
}

const VALID_SAMPLE = "alpha:12,beta:3";
const BROKEN_SAMPLE = "alpha:";
const MULTI_ERROR_SAMPLE = "alpha:13x,beta:,gamma:q";
const SAMPLE_PATH = "/tmp/galley-js-universal-example.json";

// Shared with procedures.ts: TextDecoder is global on every runtime and
// decodes identically to Buffer (verified incl. multibyte).
const utf8 = new TextDecoder();

function printTree(node: import("@sanbus/galley").Node, depth: number): void {
  const name = node.symbolName();
  const text = node.text();
  if (name === null || text === null) {
    console.error("invalid node");
    process.exit(1);
  }
  const pos = node.lineColumn();
  const line = pos ? pos[0] : 0;
  console.log(`${"  ".repeat(depth)}${name} [line ${line}, ${text!.length} bytes]`);
  for (const child of node) {
    printTree(child, depth + 1);
  }
}

async function main(): Promise<number> {
  let session: Session;
  let language: import("@sanbus/galley").Language;
  try {
    await kv.initialize();
    const wasm = wasmBytes();
    const hooks = procedures as unknown as Record<string, unknown>;
    if (wasm === null) {
      language = await kv.language();
    } else if (wasm === "dir") {
      language = await kv.language({ backend: "wasm" });
    } else {
      language = await galley.loadBytes(wasm);
    }
    language.installProcedures(hooks);
    session = await language.openSession({ maxErrors: 10 });
  } catch {
    console.error("failed to create a parser session");
    return 1;
  }
  console.log(`galley version: ${language.version()}`);

  // emulate Python's `with` via try/finally close
  try {
    try {
      session.setMessageOverride(
        "Number",
        "expected a number after ':' (digits only) at line {line}",
      );
    } catch {
      console.error("failed to register the message override");
      return 1;
    }

    const args = process.argv.slice(2);
    if (args.length > 0) {
      try {
        const parsed = session.parseFile(args[0]);
        console.log(`parsed ${parsed} bytes`);
        return 0;
      } catch (err: unknown) {
        const galleyErr = err as import("@sanbus/galley").GalleyError;
        const diag = galleyErr.diagnostic ?? session.diagnostic();
        const line = diag?.line ?? 0;
        const col = diag?.column ?? 0;
        const msg = diag?.message ?? "";
        console.error(`${args[0]}:${line}:${col}: ${msg}`);
        return 1;
      }
    }

    // Successful parse: walk the tree.
    let parsed: number;
    try {
      parsed = session.parse(VALID_SAMPLE);
    } catch (err: unknown) {
      const galleyErr = err as { code: number };
      console.error(`unexpected failure: ${err} (${galleyErr.code})`);
      return 1;
    }
    console.log(`parsed ${parsed} bytes, ${session.nodeCount()} AST nodes`);
    if (!language.hasAst()) {
      console.log("AST construction disabled; skipping tree walk");
    } else {
      const root = session.rootNode();
      if (root !== null) printTree(root, 1);
    }

    // Failed parse: inspect the diagnostic.
    try {
      session.parse(BROKEN_SAMPLE);
      console.error("expected the broken sample to fail");
      return 1;
    } catch (err: unknown) {
      // expected
      void err;
    }
    const diagnostic = session.diagnostic();
    if (!diagnostic) {
      console.error("expected a diagnostic for the broken sample");
      return 1;
    }
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
      console.error("expected the multi-error sample to fail");
      return 1;
    } catch {
      // expected
    }
    const recorded = session.diagnostics();
    console.log(`recorded diagnostics: ${recorded.length}`);
    recorded.forEach((diag, idx) => {
      const kindName =
        diag.kind === Kind.Syntax
          ? "syntax"
          : diag.kind === Kind.Indentation
            ? "indentation"
            : "none";
      const unexpected = diag.unexpectedToken
        ? utf8.decode(diag.unexpectedToken)
        : "";
      console.log(`  [${idx}] ${kindName} at ${diag.line}:${diag.column} near '${unexpected}'`);
    });

    // File parsing.
    try {
      fs.writeFileSync(SAMPLE_PATH, VALID_SAMPLE, "utf-8");
    } catch {
      console.error(`failed to write ${SAMPLE_PATH}`);
      return 1;
    }
    try {
      parsed = session.parseFile(SAMPLE_PATH);
    } catch (err: unknown) {
      const galleyErr = err as { code: number };
      console.error(`file parse failed: ${err} (${galleyErr.code})`);
      return 1;
    }
    const pos = session.lastPosition();
    if (!pos) {
      console.error("expected a position after file parse");
      return 1;
    }
    const [endLine, endColumn] = pos;
    console.log(`file parse: ${parsed} bytes, ended at ${endLine}:${endColumn}`);

    // Tree editing: detach the root's children, then reattach them.
    if (language.hasAst()) {
      const root = session.rootNode();
      if (!root) {
        console.error("expected the root to have children");
        return 1;
      }
      const childrenBefore = root.length;
      const head = root.cleanChildren();
      if (!head) {
        console.error("expected the root to have children");
        return 1;
      }
      root.appendChildren(head);
      console.log(`tree edit: ${childrenBefore} children before, ${root.length} after reattach`);
    }

    return 0;
  } finally {
    session.close();
  }
}

main().then((code) => process.exit(code));
