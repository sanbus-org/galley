#!/usr/bin/env node
/**
 * Parses a small key/value document through the Galley TypeScript bindings,
 * mirroring examples/c, examples/python, etc. byte-for-byte in output.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import {
  init,
  installProcedures,
  Session,
  KIND_SYNTAX,
  KIND_INDENTATION,
  artifactFileName,
  wasmArtifactFileName,
} from "@sanbus/galley";
import * as procedures from "./procedures.ts";

// The one parser file this demo runs: exact path, no searching.
const LIBRARY_PATH = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  artifactFileName("galley-js-node", process.platform),
);

// GALLEY_WASM=1 (or a path) runs the same demo through the WebAssembly
// backend instead of native. Explicit choice, so the fallback notice
// stays off and the output matches the native run byte for byte.
function wasmPath(): string | null {
  const selected = process.env.GALLEY_WASM;
  if (!selected) return null;
  if (selected !== "1") return selected;
  return path.join(path.dirname(fileURLToPath(import.meta.url)), wasmArtifactFileName("galley-js-wasm"));
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
  try {
    const wasm = wasmPath();
    await init(wasm ? { wasmPath: wasm, quiet: true } : { libraryPath: LIBRARY_PATH });
  } catch {
    console.error("failed to create a parser session");
    return 1;
  }
  if (installProcedures(procedures as unknown as Record<string, unknown>) === 0) {
    console.error("failed to register procedure hooks");
    return 1;
  }
  let session: Session;
  try {
    session = new Session({ maxErrors: 10 });
  } catch {
    console.error("failed to create a parser session");
    return 1;
  }
  console.log(`galley version: ${session.version()}`);

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
      parsed = session.parseSentinel(VALID_SAMPLE);
    } catch (err: unknown) {
      const galleyErr = err as { code: number };
      console.error(`unexpected failure: ${err} (${galleyErr.code})`);
      return 1;
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
        diag.kind === KIND_SYNTAX
          ? "syntax"
          : diag.kind === KIND_INDENTATION
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
    if (session.hasAst()) {
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
