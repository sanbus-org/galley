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
 * missing compiler or headers is a loud error, never a fallback.
 */

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { buildParserArtifact } from "@sanbus/galley-core/build/builder.mjs";

const LIBRARY_NAME = "galley-js-node";
const ADDON_NAME = "galley-js-node.node";

function fatal(message) {
  console.error(`galley-bindings: ${message}`);
  process.exit(1);
}

// Directory holding node_api.h for the running Node (shipped with every
// Node distribution next to the executable). No search elsewhere.
function nodeIncludeDirectory() {
  const candidate = path.resolve(path.dirname(process.execPath), "..", "include", "node");
  try {
    fs.accessSync(path.join(candidate, "node_api.h"));
    return candidate;
  } catch {
    fatal(`node_api.h not found under ${candidate}; reinstall Node with headers`);
  }
}

function compileAddon(languageDirectory) {
  if (process.platform === "win32") {
    fatal("the Node addon is not supported on Windows; use WSL or another adapter");
  }
  // C inputs come from the checkout, never from this package's install
  // location: installs are copies that may predate them (and packed
  // installs omit sources entirely). The gate already requires
  // GALLEY_CHECKOUT, so it is set by the time this runs.
  const checkout = process.env.GALLEY_CHECKOUT;
  if (!checkout) fatal("GALLEY_CHECKOUT is not set; point it at a Galley checkout");
  const zig = process.env.ZIG_EXECUTABLE ?? "zig";
  const addonSource = path.join(checkout, "bindings", "js", "node", "addon.c");
  const headerDirectory = path.join(checkout, "bindings", "c");
  const directory = path.resolve(languageDirectory);
  const addonOutput = path.join(directory, ADDON_NAME);
  // The gate may skip a fresh parser library; the addon still needs to
  // exist and postdate both its source and the library it links.
  try {
    const addonTime = fs.statSync(addonOutput).mtimeMs;
    const sourceTime = fs.statSync(addonSource).mtimeMs;
    let libraryTime = 0;
    for (const entry of fs.readdirSync(directory)) {
      if (entry === ADDON_NAME) continue;
      if (entry.startsWith("libgalley-js-node.")) {
        libraryTime = Math.max(libraryTime, fs.statSync(path.join(directory, entry)).mtimeMs);
      }
    }
    if (addonTime >= sourceTime && addonTime >= libraryTime && libraryTime > 0) return;
  } catch {
    // Missing addon, source, or library: compile (or fail loud below).
  }
  const linkArguments = [
    "-shared",
    "-O2",
    `-I${nodeIncludeDirectory()}`,
    `-I${headerDirectory}`,
    addonSource,
    "-o",
    addonOutput,
    `-L${directory}`,
    "-lgalley-js-node",
  ];
  if (process.platform === "darwin") {
    // Node-API symbols resolve when Node loads the addon.
    linkArguments.push("-undefined", "dynamic_lookup");
    linkArguments.push("-Wl,-rpath,@loader_path");
  } else {
    // Position-independent code plus libdl: the addon probes optional
    // shim symbols with dlopen/dlsym (mirroring the Python extension).
    linkArguments.push("-fPIC", "-ldl", "-Wl,-rpath,$ORIGIN");
  }
  // The addon links the grammar's parser library so a missing or stale
  // library fails here, next to the grammar, not at require() time.
  const result = spawnSync(zig, ["cc", ...linkArguments], { stdio: "pipe", encoding: "utf-8" });
  if (result.status !== 0) {
    fatal(`zig cc failed for ${ADDON_NAME}:\n${result.stderr || result.stdout || "unknown error"}`);
  }
  console.error(`galley-bindings: built ${addonOutput}; import from ${directory}`);
}

async function main() {
  if (process.argv.length !== 3) fatal("usage: npx galley-js-node <language-dir>");
  const bindingsDirectory = path.dirname(fileURLToPath(import.meta.url));
  await buildParserArtifact({
    languageDirectory: process.argv[2],
    libraryName: LIBRARY_NAME,
    bindingsDirectory,
  });
  compileAddon(process.argv[2]);
}

main().catch((error) => fatal(error?.message ?? String(error)));
