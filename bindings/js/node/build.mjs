#!/usr/bin/env node
/**
 * Builds a Galley parser and its shared library for a JavaScript consumer
 * on Node.
 *
 * Usage:
 *   npx galley-js-node <language-dir>
 *
 * Thin wrapper over the shared gate (`galley-js-core/build/builder.mjs`),
 * which documents the accepted grammar files and owns the build. For both
 * legs at once, use the single entry instead: `galley build <language-dir>`
 * from `@sanbus-org/galley`.
 */

import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { buildParserArtifact } from "galley-js-core/build/builder.mjs";

const LIBRARY_NAME = "galley-js-node";

function fatal(message) {
  console.error(`galley-bindings: ${message}`);
  process.exit(1);
}

async function main() {
  if (process.argv.length !== 3) fatal("usage: npx galley-js-node <language-dir>");
  await buildParserArtifact({
    languageDirectory: process.argv[2],
    libraryName: LIBRARY_NAME,
    bindingsDirectory: path.dirname(fileURLToPath(import.meta.url)),
    dependencyName: "koffi",
  });
}

main().catch((error) => fatal(error?.message ?? String(error)));
