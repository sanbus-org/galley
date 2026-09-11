#!/usr/bin/env node
/**
 * Single build entry for the Galley JavaScript bindings.
 *
 * Usage:
 *   galley build <language-dir> [--native-only|--wasm-only]
 *
 * Builds both artifacts next to the grammar by default: the canonical
 * shared native library (serves the Node, Bun, and Deno adapters) plus
 * the Node NAPI addon, and the wasm module (serves browsers and the
 * universal fallback leg). The per-adapter builders (`@sanbus/galley-node`, `@sanbus/galley-bun`,
 * `@sanbus/galley-wasm`, the Deno `build.ts`) remain as thin wrappers over the
 * same shared gate for single-leg builds.
 *
 * Environment: `ZIG_EXECUTABLE` names an explicit zig (else `zig` on
 * `PATH`, else `uvx` provisioning zig 0.16.0); `GALLEY_CLI` names an
 * explicit generator binary. Generating the parser needs no checkout
 * (prebuilt CLI from the installed platform package, else `GALLEY_CLI`,
 * else a `GALLEY_CHECKOUT` bootstrap); compiling it needs no checkout
 * either (the kit inside `@sanbus/galley-core`, else a `GALLEY_CHECKOUT`
 * leg). To fetch a checkout for convenience, use
 * `examples/scripts/fetch-galley.sh` (examples-only, not core).
 */

import * as path from "node:path";
import { fileURLToPath } from "node:url";
import {
  NATIVE_LIBRARY_BASE,
  WASM_LIBRARY_BASE,
  buildParserArtifact,
} from "@sanbus/galley-core/build/builder.mjs";

function fatal(message) {
  console.error(`galley-bindings: ${message}`);
  process.exit(1);
}

const USAGE = "usage: galley build <language-dir> [--native-only|--wasm-only]";

async function main() {
  const argumentList = process.argv.slice(2);
  if (argumentList.length < 2 || argumentList[0] !== "build") fatal(USAGE);
  const flagList = argumentList.slice(2);
  for (const flag of flagList) {
    if (flag !== "--native-only" && flag !== "--wasm-only") fatal(`unknown flag ${flag}; ${USAGE}`);
  }
  const nativeOnly = flagList.includes("--native-only");
  const wasmOnly = flagList.includes("--wasm-only");
  if (nativeOnly && wasmOnly) fatal(`pass at most one of --native-only, --wasm-only; ${USAGE}`);

  const languageDirectory = argumentList[1];
  const bindingsDirectory = path.dirname(fileURLToPath(import.meta.url));
  if (!wasmOnly) {
    await buildParserArtifact({
      languageDirectory,
      libraryName: NATIVE_LIBRARY_BASE,
      bindingsDirectory,
      dependencyName: "@sanbus/galley-core",
      addon: true,
    });
  }
  if (!nativeOnly) {
    await buildParserArtifact({
      languageDirectory,
      libraryName: WASM_LIBRARY_BASE,
      wasm: true,
      posixOnly: false,
      bindingsDirectory,
      dependencyName: "@sanbus/galley-core",
    });
  }
}

main().catch((error) => fatal(error?.message ?? String(error)));
