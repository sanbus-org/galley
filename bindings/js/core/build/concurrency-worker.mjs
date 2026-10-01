/**
 * One thread of the shared concurrency scenario (see `concurrency.mjs`):
 * opens a parser and one session with its own hooks, parses the grammar's
 * input behind a shared-memory barrier, then parses repeatedly as a stress
 * phase, and posts a report of what its hooks saw.
 */

import { parentPort, workerData } from "node:worker_threads";

const {
  directory,
  grammar,
  hooks,
  items,
  stressRounds,
  universalEntry,
  backend,
  barrier: barrierMemory,
  parties,
  barrierTimeoutMs,
} = workerData;

// galley_error_session_in_use: changing hooks during a parse is refused.
const SESSION_IN_USE = -13;

const shared = new Int32Array(barrierMemory);

/** True once `parties` threads arrived; false on timeout. */
function barrierWait() {
  const arrived = Atomics.add(shared, 0, 1) + 1;
  if (arrived === parties) {
    Atomics.store(shared, 1, 1);
    Atomics.notify(shared, 1);
    return true;
  }
  const deadline = Date.now() + barrierTimeoutMs;
  while (Atomics.load(shared, 1) === 0) {
    const remaining = deadline - Date.now();
    if (remaining <= 0) return false;
    Atomics.wait(shared, 1, 0, remaining);
  }
  return true;
}

const input =
  grammar === "keyvalue"
    ? Array.from({ length: items }, (_, index) => `k${index}:${index % 97}`).join(",")
    : Array.from({ length: items }, () => "word").join("+");
const specific = grammar === "keyvalue" ? "hook_print" : "hook_tally";
const reduction = grammar === "keyvalue" ? "reduction_Pair" : "reduction_Word";

const { openLanguageDirectory } = await import(universalEntry);
const parser = await openLanguageDirectory(directory, { backend });
// The fixture's bundled hooks are defaults every session would copy.
parser.clearProcedures();
const session = parser.openSession();

let calls = {};
let foreignText = 0;
let barrierPending = true;
let arrivedTogether = null;
let refusalCode = null;

function onHook(name, takesArguments) {
  const record = () => {
    calls[name] = (calls[name] ?? 0) + 1;
    if (barrierPending) {
      barrierPending = false;
      arrivedTogether = barrierWait();
      // Still inside the parse: changing hooks must be refused.
      try {
        session.clearProcedures();
      } catch (error) {
        refusalCode = error.code;
      }
    }
  };
  if (!takesArguments) return () => record();
  return (args) => {
    const node = args.currentNode();
    if (node === null || node.text().length === 0) foreignText++;
    record();
  };
}

for (const name of hooks) session.installProcedure(name, onHook(name, name === reduction));

function expectedCalls() {
  return {
    [specific]: hooks.includes(specific) ? items : 0,
    [reduction]: hooks.includes(reduction) ? items : 0,
  };
}

function matchesExpected() {
  const expected = expectedCalls();
  return (
    (calls[specific] ?? 0) === expected[specific] &&
    (calls[reduction] ?? 0) === expected[reduction] &&
    foreignText === 0
  );
}

const report = { grammar, hooks, first: false, arrivedTogether: false, refusalCode: null, stable: true };

const parsed = session.parse(input);
report.first = parsed > 0 && matchesExpected();
report.arrivedTogether = arrivedTogether === true;
report.refusalCode = refusalCode;
report.refusalIsSessionInUse = refusalCode === SESSION_IN_USE;
report.listedHooks = Object.keys(session.listProcedures()).length === hooks.length;
report.calls = { ...calls };

// Stress: parse again and again with no barrier; every round reproduces
// the expected counts.
for (let round = 0; round < stressRounds; round++) {
  calls = {};
  foreignText = 0;
  if (session.parse(input) <= 0 || !matchesExpected()) report.stable = false;
}

session.close();
parentPort.postMessage(report);
