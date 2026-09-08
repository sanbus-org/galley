#!/usr/bin/env node
/**
 * Builds a Galley parser and its shared library for a JavaScript consumer
 * on Bun.
 *
 * Usage:
 *   npx galley-js-bun <language-dir>
 *
 * Thin wrapper over the shared gate (`@sanbus/galley-core/build/builder.mjs`),
 * which documents the accepted grammar files and owns the build. For both
 * legs at once, use the single entry instead: `galley build <language-dir>`
 * from `@sanbus/galley`.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { buildParserArtifact } from "@sanbus/galley-core/build/builder.mjs";

const LIBRARY_NAME = "galley-js-bun";

function fatal(message) {
  console.error(`galley-bindings: ${message}`);
  process.exit(1);
}

async function main() {
  if (process.argv.length !== 3) fatal("usage: npx galley-js-bun <language-dir>");
  const bindingsDirectory = path.dirname(fileURLToPath(import.meta.url));
  const languageDirectory = path.resolve(process.argv[2]);
  await buildParserArtifact({
    languageDirectory,
    libraryName: LIBRARY_NAME,
    bindingsDirectory,
    dependencyName: "@sanbus/galley-core",
    installCommand: "bun install",
  });

  // Bun snapshots `file:` dependencies into node_modules at install time,
  // so a consumer's copy can predate the build outputs (dist/ and the
  // nested @sanbus/galley-core, materialized above, after install) and fail
  // resolution with "Cannot find package". Refresh every snapshot copy
  // reachable from this build: the language dir's own and the invoking
  // directory's (the benchmark flow builds benchmark/ while resolving
  // through the parent example dir). The npm-based adapters symlink
  // `file:` dirs and never need this. This stays in the wrapper: it is a
  // Bun install-layout quirk, not build semantics.
  const refreshed = new Set();
  for (const rootDirectory of [languageDirectory, process.cwd()]) {
    const resolved = path.resolve(rootDirectory);
    if (refreshed.has(resolved)) continue;
    refreshed.add(resolved);
    refreshSnapshot(resolved, bindingsDirectory);
  }
}

function refreshSnapshot(rootDirectory, bindingsDirectory) {
  const snapshotDirectory = path.join(rootDirectory, "node_modules", "@sanbus/galley-bun");
  const snapshotPackage = path.join(snapshotDirectory, "package.json");
  if (!fs.existsSync(snapshotPackage)) return;
  // Only touch our own snapshot copy, never an unrelated registry install.
  const bindingsPackage = JSON.parse(fs.readFileSync(path.join(bindingsDirectory, "package.json"), "utf-8"));
  const snapshotManifest = JSON.parse(fs.readFileSync(snapshotPackage, "utf-8"));
  if (
    snapshotManifest.name !== bindingsPackage.name ||
    snapshotManifest.version !== bindingsPackage.version
  )
    return;
  const snapshotDist = path.join(snapshotDirectory, "dist");
  fs.rmSync(snapshotDist, { recursive: true, force: true });
  fs.cpSync(path.join(bindingsDirectory, "dist"), snapshotDist, { recursive: true });
  console.log(`galley-bindings: refreshed ${snapshotDist}`);
  const snapshotCore = path.join(snapshotDirectory, "node_modules", "@sanbus/galley-core");
  fs.rmSync(snapshotCore, { recursive: true, force: true });
  fs.mkdirSync(path.join(snapshotDirectory, "node_modules"), { recursive: true });
  // Dereference: the source entry is usually a symlink into the checkout,
  // which would dangle from inside the snapshot.
  fs.cpSync(path.join(bindingsDirectory, "node_modules", "@sanbus/galley-core"), snapshotCore, {
    recursive: true,
    dereference: true,
  });
  console.log(`galley-bindings: refreshed ${snapshotCore}`);
}

main().catch((error) => fatal(error?.message ?? String(error)));
