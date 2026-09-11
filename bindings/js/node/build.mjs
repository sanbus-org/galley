#!/usr/bin/env node
/**
 * Builds a Galley parser and its shared library for a JavaScript consumer
 * on Node, then compiles the Node NAPI addon (`addon.c`) against it.
 *
 * Usage:
 *   npx galley-js-node <language-dir>
 *
 * Thin wrapper over the shared gate (`@sanbus/galley-core/build/builder.mjs`),
 * which documents the accepted grammar files and owns the build. For both
 * legs at once, use the single entry instead: `galley build <language-dir>`
 * from `@sanbus/galley`.
 *
 * Environment: `ZIG_EXECUTABLE` (default `zig`), same as the gate. The
 * addon compiles with `zig cc` against the running Node's headers; a
 * missing compiler or headers is a loud error.
 */

import * as path from "node:path";
import { fileURLToPath } from "node:url";
import {
  NATIVE_LIBRARY_BASE,
  buildParserArtifact,
} from "@sanbus/galley-core/build/builder.mjs";

function fatal(message) {
  console.error(`galley-bindings: ${message}`);
  process.exit(1);
}

async function main() {
  if (process.argv.length !== 3) fatal("usage: npx galley-js-node <language-dir>");
  const bindingsDirectory = path.dirname(fileURLToPath(import.meta.url));
  await buildParserArtifact({
    languageDirectory: process.argv[2],
    libraryName: NATIVE_LIBRARY_BASE,
    bindingsDirectory,
    addon: true,
  });
}

main().catch((error) => fatal(error?.message ?? String(error)));
