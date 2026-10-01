/**
 * Shared concurrency scenario for the Galley JavaScript binding suites:
 * two parsers, two sessions each, four threads parsing at the same time.
 *
 * One implementation behind the node, bun, deno, and wasm suites. Each
 * thread is a `node:worker_threads` worker (all four runtimes provide it)
 * running `concurrency-worker.mjs`: it opens its own parser through the
 * universal entry, opens one session with its own hook set, and parses. The
 * first hook of every parse waits at a four-way barrier on shared memory,
 * so the scenario passes only if all four parses are in flight at once.
 * Every worker checks its own hook counts against the grammar's, and a
 * stress phase repeats the parse without the barrier. A hook that fired for
 * the wrong session, did not fire, or read another session's nodes shows up
 * as a mismatch in that worker's report.
 */

import assert from "node:assert/strict";
import { Worker } from "node:worker_threads";
import { fileURLToPath } from "node:url";

const WORKER_FILE = fileURLToPath(new URL("./concurrency-worker.mjs", import.meta.url));
const BARRIER_TIMEOUT_MS = 20_000;
const RESULT_TIMEOUT_MS = 120_000;

/**
 * Runs the scenario, asserts on the four workers' reports, and returns
 * them. `universalEntry` is the URL of the universal entry module;
 * `backend` is `"native"` or `"wasm"`; `firstDirectory` and
 * `secondDirectory` are the built language directories of the keyvalue and
 * second grammars.
 */
export async function runConcurrencyScenario({
  universalEntry,
  backend,
  firstDirectory,
  secondDirectory,
  items = 150,
  stressRounds = 100,
}) {
  const barrier = new Int32Array(new SharedArrayBuffer(8));
  const configurations = [
    { grammar: "keyvalue", directory: firstDirectory, hooks: ["reduction_Pair", "hook_print"] },
    { grammar: "keyvalue", directory: firstDirectory, hooks: ["hook_print"] },
    { grammar: "words", directory: secondDirectory, hooks: ["reduction_Word", "hook_tally"] },
    { grammar: "words", directory: secondDirectory, hooks: ["reduction_Word"] },
  ];
  const pending = configurations.map((configuration) => {
    const worker = new Worker(WORKER_FILE, {
      workerData: {
        ...configuration,
        universalEntry,
        backend,
        items,
        stressRounds,
        barrier: barrier.buffer,
        parties: configurations.length,
        barrierTimeoutMs: BARRIER_TIMEOUT_MS,
      },
    });
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        worker.terminate();
        reject(new Error("a concurrency worker did not report in time"));
      }, RESULT_TIMEOUT_MS);
      worker.once("message", (report) => {
        clearTimeout(timer);
        resolve(report);
      });
      worker.once("error", (error) => {
        clearTimeout(timer);
        reject(error);
      });
    }).finally(() => worker.terminate());
  });
  const reports = await Promise.all(pending);
  reports.forEach((report, index) => {
    const label = `worker ${index} (${report.grammar}: ${report.hooks.join(", ")})`;
    assert.ok(report.arrivedTogether, `${label}: the four parses did not overlap`);
    assert.ok(report.first, `${label}: hook counts differ from the grammar's`);
    assert.ok(report.refusalIsSessionInUse, `${label}: changing hooks mid-parse was not refused (${report.refusalCode})`);
    assert.ok(report.listedHooks, `${label}: the refused change altered the session's hooks`);
    assert.ok(report.stable, `${label}: a stress round differed from the grammar's counts`);
  });
  return reports;
}
