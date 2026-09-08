#!/usr/bin/env -S deno run --allow-read --allow-write --allow-run --allow-env
/**
 * Builds a Galley parser and its shared library for a JavaScript consumer
 * on Deno.
 *
 * Usage (from a language directory, e.g. examples/js/deno):
 *   deno task build
 * which runs:
 *   deno run --allow-read --allow-write --allow-run --allow-env \
 *     ../../../bindings/js/deno/build.ts .
 *
 * Thin wrapper over the shared gate (`../core/build/builder.mjs`), which
 * documents the accepted grammar files and owns the build. For both legs
 * at once, use the single entry instead: `galley build <language-dir>`
 * from `@sanbus-org/galley`.
 */

import { buildParserArtifact } from "../core/build/builder.mjs";
import { artifactFileName, wasmArtifactFileName } from "../core/src/artifact.ts";

const LIBRARY_NAME = "galley-js-deno";

function fatal(msg: string): never {
  console.error(`galley-bindings: ${msg}`);
  Deno.exit(1);
}

async function main(): Promise<void> {
  if (Deno.args.length !== 1) fatal("usage: deno task build  (runs build.ts <language-dir>)");
  await buildParserArtifact({
    languageDirectory: Deno.args[0],
    libraryName: LIBRARY_NAME,
    platform: Deno.build.os,
    artifactFileName,
    wasmArtifactFileName,
  });
}

main();
