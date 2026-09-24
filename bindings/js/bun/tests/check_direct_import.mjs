/**
 * Consumer-realistic check for a generated language package: import the
 * fixture entry by path in a fresh process (as a consumer would), wire
 * bundled hooks, and report the result as JSON on stdout.
 *
 * Runs in its own process so module resolution starts warm: the parent
 * suite installs the fixture's `file:` dependencies mid-process, which
 * the parent's own resolver snapshot cannot see, but a fresh process
 * resolves through the new lockfile. Isolation also keeps the child on
 * its own adapter realm (the native dispatch table is process-global).
 *
 * Usage: bun check_direct_import.mjs <languageDir>
 */

import assert from "node:assert/strict";
import * as path from "node:path";
import { pathToFileURL } from "node:url";

const languageDir = process.argv[2];
if (!languageDir) {
  throw new Error("check_direct_import: languageDir argument is required");
}

const kv = await import(pathToFileURL(path.join(languageDir, "index.mjs")).href);
await kv.initialize();

// Hook namespaces are imported from their hook file; the entry binds
// none, and named exports are the sole spelling.
assert.equal("procedures" in kv, false);
assert.equal("default" in kv, false);

// Namespace pin: every type and constant the grammar module exposes,
// with hook and query functions living on the parser like the
// module, not the session.
const surface = [
  "Session",
  "Node",
  "Walker",
  "ProcedureArguments",
  "Parser",
  "GalleyError",
  "Kind",
  "ParserType",
  "RecoveryMode",
  "RecoveryTarget",
  "Resume",
];
assert.deepEqual(Object.keys(kv).sort(), ["initialize", "openSession", "parser", ...surface].sort());

// Construction stays async-only: the bare class needs a bound port.
assert.throws(() => new kv.Session(), /bound port/);

const parser = await kv.parser();
const session = await kv.openSession();
try {
  assert.ok("reduction_Pair" in parser.listProcedures());
  const parsed = session.parse("alpha:12,beta:3");
  assert.equal(parsed, 15);
  console.log(`GALLEY_RESULT=${JSON.stringify({ parse: parsed, procedures: Object.keys(parser.listProcedures()).sort() })}`);
} finally {
  session.close();
}
