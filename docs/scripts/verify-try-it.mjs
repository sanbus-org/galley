#!/usr/bin/env node
/**
 * Verification for the docs Try-it page's measurement semantics.
 *
 * Run: node docs/scripts/verify-try-it.mjs
 * Exits 0 when every check passes, 1 otherwise.
 *
 * Checks, against the page's own sources and the built wasm, per
 * language (json, lisp, lua, galley, python):
 *
 *  1. The tab's session layout: a session opened before the counters
 *     are installed carries no procedures; one opened after carries
 *     exactly the tab's counters — Raw and Hooks differ by the hooks
 *     alone.
 *  2. Raw parses fire no counters; hooks parses count; both parse the
 *     same bytes.
 *  3. String and byte inputs are one path: same parse return, same
 *     hook counts, same diagnostic — typed text and dropped files
 *     measure identically.
 *  4. The AST twin parses the sample and the host walk sees nodes.
 *  5. The run-count suggestion behind the "× n = m" labels: ceil to
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
const { countNodes } = await import(new URL("../try-it/snapshot-nodes.js", import.meta.url));
const { countSnapshot } = await import(
  new URL("../try-it/lang/json/snapshot-stats.js", import.meta.url).href
);

// The page's .js sources sit under a package without
// "type": "module", so node refuses to import them as ESM directly:
// stage .mjs copies in a temp dir and import those. The copies can go
// as soon as they are imported — the modules are fully evaluated then.
const staging = await mkdtemp(join(tmpdir(), "try-it-verify-"));
const stage = async (url, name) => {
  const target = join(staging, name ?? basename(url.pathname).replace(/\.js$/, ".mjs"));
  await writeFile(target, await readFile(url));
  return import(pathToFileURL(target).href);
};

const samples = await stage(new URL("try-it/samples.js", docs));
const hooks = {};
for (const id of ["json", "lisp", "lua", "galley", "python"]) {
  hooks[id] = await stage(new URL(`try-it/lang/${id}/procedures.js`, docs), `procedures-${id}.mjs`);
}
await rm(staging, { recursive: true, force: true });

// Deliberately invalid inputs, one per language: each must fail with a
// diagnostic, exercising the same error path as a dropped bad file.
const languages = [
  {
    id: "json",
    sample: samples.jsonSample,
    hooks: hooks.json,
    hookCount: 7,
    bad: '{ "a": }',
    visit: (session, input) => countSnapshot(session, input),
  },
  {
    id: "lisp",
    sample: samples.lispSample,
    hooks: hooks.lisp,
    hookCount: 7,
    bad: "(define",
    visit: (session) => countNodes(session),
  },
  {
    id: "lua",
    sample: samples.luaSample,
    hooks: hooks.lua,
    hookCount: 4,
    bad: '"abc',
    visit: (session) => countNodes(session),
  },
  {
    id: "galley",
    sample: samples.galleySample,
    hooks: hooks.galley,
    hookCount: 6,
    bad: "Start\n| ?\n",
    visit: (session) => countNodes(session),
  },
  {
    id: "python",
    sample: samples.pythonSample,
    hooks: hooks.python,
    hookCount: 11,
    bad: "def f(:\n    pass\n",
    visit: (session) => countNodes(session),
  },
];

let failed = false;
const check = (ok, name, detail = "") => {
  console.log(`${ok ? "OK  " : "FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
  if (!ok) failed = true;
};

for (const language of languages) {
  const { id, sample, hooks: langHooks, hookCount, bad, visit } = language;
  const wasm = await readFile(new URL(`public/try-it/${id}.wasm`, docs));
  const input = `${sample}\n`;

  // The page's session layout: raw opens before the counters install.
  const parser = galley.loadBytes(wasm);
  const raw = parser.openSession();
  parser.installProcedures(langHooks);
  const hooked = parser.openSession();

  const rawNames = Object.keys(raw.listProcedures());
  const hookNames = Object.keys(hooked.listProcedures());
  check(rawNames.length === 0, `${id}: raw session carries no procedures`, `n=${rawNames.length}`);
  check(
    hookNames.length === hookCount,
    `${id}: hooks session carries the counters`,
    `n=${hookNames.length}`,
  );

  langHooks.resetStats();
  const rawBytes = raw.parse(input);
  const rawCount = Object.values(langHooks.stats).reduce((sum, n) => sum + n, 0);
  check(rawCount === 0, `${id}: raw parse fires no counters`, `count=${rawCount}`);

  langHooks.resetStats();
  const hookBytes = hooked.parse(input);
  const hookCounted = Object.values(langHooks.stats).reduce((sum, n) => sum + n, 0);
  check(hookCounted > 0, `${id}: hooks parse counts`, `count=${hookCounted}`);
  check(
    rawBytes === hookBytes && rawBytes > 0,
    `${id}: both sessions parse the same bytes`,
    `${rawBytes}/${hookBytes}`,
  );

  // String and byte inputs are one path.
  const encoded = new TextEncoder().encode(input);
  langHooks.resetStats();
  const stringRun = hooked.parse(input);
  const stringStats = { ...langHooks.stats };
  langHooks.resetStats();
  const bytesRun = hooked.parse(encoded);
  const bytesStats = { ...langHooks.stats };
  check(
    stringRun === bytesRun && JSON.stringify(stringStats) === JSON.stringify(bytesStats),
    `${id}: string and byte inputs measure identically`,
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
  const stringDiag = diagnosticOf(() => hooked.parse(bad));
  const bytesDiag = diagnosticOf(() => hooked.parse(new TextEncoder().encode(bad)));
  check(
    stringDiag !== null && stringDiag === bytesDiag,
    `${id}: diagnostics identical for string and byte input`,
    stringDiag ?? "no diagnostic thrown",
  );

  // The AST twin parses the sample and the host walk sees its nodes.
  const astWasm = await readFile(new URL(`public/try-it/${id}-ast.wasm`, docs));
  const astSession = galley.loadBytes(astWasm).openSession();
  const astBytes = astSession.parse(input);
  check(astBytes > 0, `${id}: AST build parses the sample`, `${astBytes}`);
  const visited = visit(astSession, encoded);
  const seen = Object.values(visited).reduce((sum, n) => sum + n, 0);
  check(seen > 0, `${id}: host walk sees nodes`, JSON.stringify(visited));
}

// The plural rule mirrored from TryIt.vue's countsLine + PLURALS —
// the SFC cannot be imported from node, so this is its copy. Every
// stats key below pins its rendered plural, so a newly added
// construct shows up here before it ships a "2 classs" line.
const PLURALS = {
  class: "classes",
  match: "matches",
  hash: "hashes",
  try: "tries",
  with: "with statements",
  escaped: "escapes",
};
const plural = (count, one, many) => `${count} ${count === 1 ? one : many}`;
const countsLine = (stats) =>
  Object.entries(stats)
    .map(([name, count]) => plural(count, name, PLURALS[name] ?? `${name}s`))
    .join(", ");

// Literal expectations per tab: adding a construct without updating
// both its hook module and this table fails loudly here.
const expectedLines = {
  json: "2 objects, 2 arrays, 2 strings, 2 numbers, 2 booleans, 2 nulls, 2 keys",
  lisp: "2 abbrevs, 2 lists, 2 hashes, 2 strings, 2 escapes, 2 numbers, 2 symbols",
  lua: "2 strings, 2 longstrings, 2 comments, 2 groups",
  galley: "2 alternatives, 2 variables, 2 terminals, 2 generatives, 2 annotations, 2 comments",
  python:
    "2 functions, 2 classes, 2 imports, 2 ifs, 2 loops, 2 with statements, 2 tries, 2 matches, 2 cases, 2 strings, 2 numbers",
};

for (const [id, mod] of Object.entries(hooks)) {
  const doubled = Object.fromEntries(Object.keys(mod.stats).map((key) => [key, 2]));
  check(countsLine(doubled) === expectedLines[id], `${id}: stats line`, countsLine(doubled));
}
check(countsLine({ node: 1 }) === "1 node", "node count renders singular");
check(countsLine({ node: 123 }) === "123 nodes", "node count renders plural");

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
