#!/usr/bin/env node
/**
 * Verification for the docs Try-it page's measurement semantics.
 *
 * Run: node docs/scripts/verify-try-it.mjs
 * Exits 0 when every check passes, 1 otherwise.
 *
 * Checks, against the page's own sources and the committed wasm:
 *
 *  1. The JSON tab's session layout: a session opened before the
 *     counters are installed carries no procedures; one opened after
 *     carries all seven — Raw and Hooks differ by the hooks alone.
 *  2. Raw parses fire no counters; hooks parses count; both parse the
 *     same bytes.
 *  3. String and byte inputs are one path: same parse return, same
 *     hook counts, same diagnostic — typed text and dropped files
 *     measure identically.
 *  4. The run-count suggestion behind the "× n = m" labels: ceil to
 *     the target, collapse to one run at or over it, empty input
 *     offers only the single run.
 */
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { basename, join } from "node:path";
import { pathToFileURL } from "node:url";

const docs = new URL("../", import.meta.url);
const { galley } = await import(
  new URL("../../bindings/js/universal/dist/index.js", import.meta.url).href
);

// The page's two .js sources sit under a package without
// "type": "module", so node refuses to import them as ESM directly:
// stage .mjs copies in a temp dir and import those. The copies can go
// as soon as they are imported — the modules are fully evaluated then.
const staging = await mkdtemp(join(tmpdir(), "try-it-verify-"));
const stage = async (url) => {
  const target = join(staging, basename(url.pathname).replace(/\.js$/, ".mjs"));
  await writeFile(target, await readFile(url));
  return import(pathToFileURL(target).href);
};
let jsonHooks;
let jsonSample;
try {
  jsonHooks = await stage(new URL("try-it/lang/json/procedures.js", docs));
  ({ jsonSample } = await stage(new URL("try-it/samples.js", docs)));
} finally {
  await rm(staging, { recursive: true, force: true });
}

const wasm = await readFile(new URL("public/try-it/json.wasm", docs));
const input = `${jsonSample}\n`;

let failed = false;
const check = (ok, name, detail = "") => {
  console.log(`${ok ? "OK  " : "FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failed = true;
};

// The page's session layout: raw opens before the counters install.
const parser = galley.loadBytes(wasm);
const raw = parser.openSession();
parser.installProcedures(jsonHooks);
const hooked = parser.openSession();

const rawNames = Object.keys(raw.listProcedures());
const hookNames = Object.keys(hooked.listProcedures());
check(rawNames.length === 0, "raw session carries no procedures", `n=${rawNames.length}`);
check(hookNames.length === 7, "hooks session carries the counters", `n=${hookNames.length}`);

jsonHooks.resetStats();
const rawBytes = raw.parse(input);
const rawCount = Object.values(jsonHooks.stats).reduce((sum, n) => sum + n, 0);
check(rawCount === 0, "raw parse fires no counters", `count=${rawCount}`);

jsonHooks.resetStats();
const hookBytes = hooked.parse(input);
const hookCount = Object.values(jsonHooks.stats).reduce((sum, n) => sum + n, 0);
check(hookCount > 0, "hooks parse counts", `count=${hookCount}`);
check(rawBytes === hookBytes && rawBytes > 0, "both sessions parse the same bytes", `${rawBytes}/${hookBytes}`);

// String and byte inputs are one path.
const encoded = new TextEncoder().encode(input);
jsonHooks.resetStats();
const stringRun = hooked.parse(input);
const stringStats = { ...jsonHooks.stats };
jsonHooks.resetStats();
const bytesRun = hooked.parse(encoded);
const bytesStats = { ...jsonHooks.stats };
check(
  stringRun === bytesRun && JSON.stringify(stringStats) === JSON.stringify(bytesStats),
  "string and byte inputs measure identically",
  `${stringRun}/${bytesRun}`,
);

const diagnosticOf = (run) => {
  try {
    run();
    return null;
  } catch (error) {
    const diagnostic = error?.diagnostic;
    return diagnostic
      ? `${diagnostic.line}:${diagnostic.column}:${diagnostic.message}`
      : String(error?.message ?? error);
  }
};
const bad = '{ "a": }';
const stringDiag = diagnosticOf(() => hooked.parse(bad));
const bytesDiag = diagnosticOf(() => hooked.parse(new TextEncoder().encode(bad)));
check(
  stringDiag !== null && stringDiag === bytesDiag,
  "diagnostics identical for string and byte input",
  stringDiag ?? "no diagnostic thrown",
);

// The suggestion formula mirrored from TryIt.vue's suggestedRuns —
// the SFC cannot be imported from node, so this is its copy.
const suggestedRuns = (inputSize, targetBytes) => {
  if (inputSize < 1) return 1;
  return Math.ceil(targetBytes / inputSize);
};
check(suggestedRuns(700e3, 1e6) === 2, "700 kB suggests 2 runs (batch reaches 1 MB)");
check(suggestedRuns(420e3, 1e6) === 3, "420 kB suggests 3 runs (batch reaches 1 MB)");
check(suggestedRuns(1e6, 1e6) === 1, "input at target collapses to 1 run");
check(suggestedRuns(3e6, 1e6) === 1, "input over target collapses to 1 run");
check(suggestedRuns(0, 1e8) === 1, "empty input offers only the single run");

process.exit(failed ? 1 : 0);
