#!/usr/bin/env node
/**
 * Single build entry for the Galley JavaScript bindings.
 *
 * Usage:
 *   galley build <language-dir> [--native-only|--wasm-only] [generator flags...]
 *
 * Builds both artifacts next to the grammar by default: the canonical
 * shared native library (serves the Node, Bun, and Deno adapters) plus
 * the Node NAPI addon, and the wasm module (serves browsers and the
 * universal fallback leg). The per-adapter builders (`@sanbus/galley-node`, `@sanbus/galley-bun`,
 * `@sanbus/galley-wasm`, the Deno `build.ts`) remain as thin wrappers over the
 * same shared gate for single-leg builds, and stay flag-free: this is the
 * one full CLI.
 *
 * Generator flags forward verbatim to the generator ahead of
 * `--emit-metadata`: the wrappers forward every flag they don't own and
 * the binary owns its surface (unknown flags die there with `unknown
 * argument`), so new generator flags work with no wrapper changes. Only
 * `--parser-type`'s value-shape is known here (`--parser-type lr` and
 * `--parser-type=lr` both forward). `--watch` is refused loudly until it
 * has its own entry: forwarding it would park the build inside the
 * generator's watch loop and never compile.
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

const USAGE = "usage: galley build <language-dir> [--native-only|--wasm-only] [generator flags...]";

async function main() {
  const argumentList = process.argv.slice(2);
  if (argumentList.length < 2 || argumentList[0] !== "build") fatal(USAGE);
  const flagList = argumentList.slice(2);
  const generatorFlags = [];
  for (let index = 0; index < flagList.length; index++) {
    const flag = flagList[index];
    if (flag === "--native-only" || flag === "--wasm-only") continue;
    if (flag === "-h" || flag === "--help") {
      console.log(USAGE);
      process.exit(0);
    }
    if (flag === "--watch") fatal("--watch needs its own entry (not yet implemented); this build runs the generator once");
    if (flag === "--parser-type") {
      const value = flagList[index + 1];
      if (value === undefined) fatal(`--parser-type needs ll or lr; ${USAGE}`);
      generatorFlags.push(flag, value);
      index++;
    } else if (flag.startsWith("-")) {
      generatorFlags.push(flag);
    } else {
      fatal(`unexpected positional argument ${flag}; ${USAGE}`);
    }
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
      generatorFlags,
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
      generatorFlags,
    });
  }
}

main().catch((error) => fatal(error?.message ?? String(error)));
