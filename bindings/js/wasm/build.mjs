#!/usr/bin/env node
/**
 * Builds a Galley parser and its WebAssembly module for a JavaScript consumer.
 *
 * Usage:
 *   npx galley-js-wasm <language-dir> [<generator-flag>...]
 *
 * Thin wrapper over the shared gate (`@sanbus/galley-core/build/builder.mjs`),
 * which documents the accepted grammar files and owns the build. For both
 * legs at once, use the single entry instead: `galley build <language-dir>`
 * from `@sanbus/galley`.
 *
 * Flags it does not own (config edits, `--parser-type`) forward to the
 * generator CLI.
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
  const [languageDirectory, ...generatorFlags] = process.argv.slice(2);
  if (!languageDirectory)
    fatal("usage: npx galley-js-wasm <language-dir> [<generator-flag>...]");
  await buildParserArtifact({
    languageDirectory,
    generatorFlags,
    libraryName: LIBRARY_NAME,
    wasm: true,
    posixOnly: false,
    bindingsDirectory: path.dirname(fileURLToPath(import.meta.url)),
    dependencyName: "@sanbus/galley-core",
  });
}

main().catch((error) => fatal(error?.message ?? String(error)));
