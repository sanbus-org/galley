#!/usr/bin/env node
/**
 * Builds a Galley parser and its WebAssembly module for a JavaScript consumer.
 *
 * Usage:
 *   npx galley-js-wasm <language-dir>
 *
 * Thin wrapper over the shared gate (`@sanbus/galley-core/build/builder.mjs`),
 * which documents the accepted grammar files and owns the build. For both
 * legs at once, use the single entry instead: `galley build <language-dir>`
 * from `@sanbus/galley`.
 */

import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { buildParserArtifact } from "@sanbus/galley-core/build/builder.mjs";

const LIBRARY_NAME = "galley-js-wasm";

function fatal(message) {
  console.error(`galley-bindings: ${message}`);
  process.exit(1);
}

async function main() {
  if (process.argv.length !== 3) fatal("usage: npx galley-js-wasm <language-dir>");
  await buildParserArtifact({
    languageDirectory: process.argv[2],
    libraryName: LIBRARY_NAME,
    wasm: true,
    posixOnly: false,
    bindingsDirectory: path.dirname(fileURLToPath(import.meta.url)),
    dependencyName: "@sanbus/galley-core",
  });
}

main().catch((error) => fatal(error?.message ?? String(error)));
