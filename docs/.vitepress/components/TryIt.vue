<template>
  <div class="try-it">
    <div class="tabs">
      <button v-for="checker in checkers" :key="checker.id" class="tab" :class="{ active: checker.id === active }"
        @click="active = checker.id">
        {{ checker.title }}
      </button>
    </div>
    <section v-for="checker in checkers" v-show="checker.id === active" :key="checker.id" class="checker">
      <label class="dropzone" :class="{ over: checker.dragOver, disabled: !checker.ready }"
        @dragover.prevent="(e) => { checker.dragOver = true; e.dataTransfer.dropEffect = 'copy'; }"
        @dragleave="checker.dragOver = false" @drop.prevent="(e) => dropFile(checker, e)">
        <input type="file" hidden :disabled="!checker.ready" @change="(e) => pickFile(checker, e)" />
        <span>Drop a {{ checker.ext }} file here, or click to browse</span>
      </label>
      <div v-if="checker.file" class="filebar">
        <span>Using file {{ checker.file.name }} ({{ checker.file.size }} bytes)</span>
        <button class="tab" @click="() => clearFile(checker)">
          Clear {{ checker.file.name }} and type instead
        </button>
      </div>
      <textarea v-else v-model="checker.text" spellcheck="false" rows="8" :disabled="!checker.ready"
        @input="() => inputEdited(checker)"></textarea>
      <div v-if="checker.id === 'json'" class="modes">
        <button v-for="mode in JSON_MODES" :key="mode.id" class="tab"
          :class="{ active: checker.mode === mode.id }" :disabled="actionDisabled(checker)"
          @click="() => setMode(checker, mode.id)">
          <span v-if="actionPending(checker, mode.id)" class="spinner" aria-hidden="true"></span>
          {{ mode.label }}
        </button>
      </div>
      <div class="bench">
        <button v-for="action in RUN_ACTIONS" :key="action.id" class="tab"
          :class="{ active: selectedRunButton(checker) === action.id }"
          :disabled="actionDisabled(checker, runOffered(checker, action))"
          @click="() => askRun(checker, action)">
          <span v-if="actionPending(checker, action.id)" class="spinner" aria-hidden="true"></span>
          {{ action.describe(checker) }}
        </button>
      </div>
      <!-- One result box, green when valid, red on a diagnostic: the
           rerun action sits in its top-right corner and stays mounted
           while its own work runs, so its spinner is never lost. -->
      <div class="status" :class="checker.result ? 'ok' : checker.statusClass"><button v-if="rerunShown(checker)" class="tab rerun" :disabled="actionDisabled(checker)"
          @click="() => rerun(checker)">
          <span v-if="actionPending(checker, RERUN_ID)" class="spinner" aria-hidden="true"></span>
          Rerun
        </button><template v-if="checker.result">
        <div>valid {{ checker.result.label }}<template v-if="checker.benchmark && checker.benchmark.runs > 1"> · {{ plural(checker.benchmark.runs, "run", "runs") }}</template></div>
        <!-- One row: the batch that actually ran — its own measured
             time over its own total bytes — cleared together with the
             result so the cells cannot outlive their input. -->
        <table class="numbers">
          <thead>
            <tr>
              <th>bytes</th>
              <th>time</th>
              <th>throughput</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td v-for="(value, name) in rowCells(checker)" :key="name">{{ value }}</td>
            </tr>
          </tbody>
        </table>
        <div v-if="checker.result.stats">{{ countsLine(checker.result.stats) }}</div>
      </template><template v-else>{{ checker.status }}<progress v-if="checker.progress !== null" class="progress" :value="checker.progress" max="1"></progress></template></div>
    </section>
    <p class="engines">
      Throughput depends on the browser's WebAssembly engine; measured on
      your machine, your input, right now.
    </p>
  </div>
</template>

<script setup>
import { reactive, ref, onMounted, watch } from "vue";
import { galley } from "@sanbus/galley";
import * as jsonHooks from "../../try-it/lang/json/procedures.js";
import { countSnapshot } from "../../try-it/lang/json-ast/snapshot-stats.js";
import { galleySample, jsonSample, lispSample, luaSample } from "../../try-it/samples.js";

function formatRate(bytes, elapsedMs) {
  // A parse that measures 0 ms has no rate to show.
  if (!(elapsedMs > 0)) return null;
  const perSecond = (bytes / elapsedMs) * 1000;
  if (perSecond >= 1e6) return `${(perSecond / 1e6).toFixed(1)} MB/s`;
  if (perSecond >= 1e3) return `${(perSecond / 1e3).toFixed(1)} kB/s`;
  return `${Math.round(perSecond)} B/s`;
}

function formatBytes(bytes) {
  if (bytes >= 1e6) return `${+(bytes / 1e6).toFixed(1)} MB`;
  if (bytes >= 1e3) return `${+(bytes / 1e3).toFixed(1)} kB`;
  return `${bytes} B`;
}

const active = ref("lisp");

// The JSON tab's four measurements: each button picks what the single
// table row times — a bare parse, that same build with its counting
// hooks firing, the AST build's snapshot materialized on top, or the
// snapshot walked to totals as well.
const JSON_MODES = [
  { id: "raw", label: "Raw parse" },
  { id: "hooks", label: "Hooks" },
  { id: "ast", label: "AST" },
  { id: "ast-visit", label: "AST + visit" },
];

// One rule for every action button, both rows: an action runs only
// when idle and ready; a row may additionally withhold an unoffered
// action. The spinner follows the pending action, not the state.
function actionDisabled(checker, offered = true) {
  return Boolean(checker.busy) || !checker.ready || !offered;
}

// One spinner rule for every action button: the spinner belongs to
// the button that asked for the currently running work, from the click
// to the end of that work — whichever row the button is in.
function actionPending(checker, id) {
  return Boolean(checker.busy) && checker.pending === id;
}

// The repeat row is data like the measure row: identity, the ask that
// defines the count, and the description of what that ask runs. Only
// size offers carry a target — their offer is withheld when the count
// would collapse to the one run the first button already offers.
const RUN_ACTIONS = [
  { id: "single", ask: () => 1, describe: (checker) => batchLabel(1, inputBytes(checker).byteLength) },
  sizeAction("small", 1e6),
  sizeAction("medium", 1e7),
  sizeAction("large", 1e8),
  { id: "custom", ask: promptRuns, describe: () => "Custom…" },
];

function sizeAction(id, targetBytes) {
  const ask = (checker) => suggestedRuns(inputBytes(checker).byteLength, targetBytes);
  return {
    id,
    target: targetBytes,
    ask,
    // The offer's nominal total: this many runs of the input reach it.
    describe: (checker) => batchLabel(ask(checker), targetBytes),
  };
}

// Every repeat button states its ask as count times total — "× 866 =
// 1 MB" — so the row reads as batches, not names.
function batchLabel(runs, totalBytes) {
  return `× ${runs} = ${formatBytes(totalBytes)}`;
}

// The measurement the page opens with: the large offer, so the lit
// button and the first batch agree from the first paint.
const DEFAULT_RUN_ACTION = RUN_ACTIONS.find((action) => action.id === "large");

function runOffered(checker, action) {
  if (!action.target) return true;
  return suggestedRuns(inputBytes(checker).byteLength, action.target) > 1;
}

const checkers = reactive([
  {
    id: "lisp",
    title: "Lisp",
    ext: ".lisp",
    text: lispSample,
    status: "loading parser…",
    statusClass: "",
    dragOver: false,
    ready: false,
    file: null,
    busy: null,
    pending: null,
    progress: null,
    runs: 1,
    benchmark: null,
  },
  {
    id: "json",
    title: "JSON",
    ext: ".json",
    text: jsonSample,
    status: "loading parser…",
    statusClass: "",
    dragOver: false,
    ready: false,
    file: null,
    busy: null,
    pending: null,
    progress: null,
    runs: 1,
    benchmark: null,
    mode: "hooks",
    result: null,
  },
  {
    id: "lua",
    title: "Lua",
    ext: ".lua",
    text: luaSample,
    status: "loading parser…",
    statusClass: "",
    dragOver: false,
    ready: false,
    file: null,
    busy: null,
    pending: null,
    progress: null,
    runs: 1,
    benchmark: null,
  },
  {
    id: "galley",
    title: "Galley",
    ext: ".grm",
    text: galleySample,
    status: "loading parser…",
    statusClass: "",
    dragOver: false,
    ready: false,
    file: null,
    busy: null,
    pending: null,
    progress: null,
    runs: 1,
    benchmark: null,
  },
]);

// Parser sessions and uploaded file bytes live outside reactivity: Vue
// proxies break the adapter's private methods (Safari: "Cannot access
// private method") and add overhead to large inputs.
const sessions = {};
const fileInputs = {};

const decoder = new TextDecoder();

// Display names for the synthetic control-byte terminals (end of input
// and the indentation pair), which never occur as user-typable input.
// Mirrors `displayTokenName` in `bindings/js/core/src/diagnostic.ts`
// (and `tokenDisplayName` in `src/runtime/string.zig`): the browser entry
// does not export it, and docs stay on the public surface only.
function displayToken(token) {
  if (token.length !== 1) return decoder.decode(token);
  switch (token[0]) {
    case 0x00:
      return "End of input";
    case 0x01:
      return "Indent";
    case 0x02:
      return "Dedent";
    default:
      return decoder.decode(token);
  }
}

function showError(checker, diagnostic) {
  checker.result = null;
  checker.statusClass = "bad";
  const lines = [`${diagnostic.line}:${diagnostic.column}: ${diagnostic.message}`];
  if (diagnostic.expectedTokens && diagnostic.expectedTokens.length > 0) {
    const shown = diagnostic.expectedTokens
      .slice(0, 8)
      .map((token) => `'${displayToken(token)}'`)
      .join(", ");
    const more = diagnostic.expectedTokens.length > 8 ? ` (+${diagnostic.expectedTokens.length - 8} more)` : "";
    lines.push(`expected one of: ${shown}${more}`);
  }
  checker.status = lines.join("\n");
}

function countsLine(stats) {
  if (!stats) return "";
  return (
    `${plural(stats.object, "object", "objects")}, ` +
    `${plural(stats.array, "array", "arrays")}, ` +
    `${plural(stats.string, "string", "strings")}, ` +
    `${plural(stats.number, "number", "numbers")}, ` +
    `${plural(stats.boolean, "boolean", "booleans")}, ` +
    `${plural(stats.null, "null", "nulls")}, ` +
    `${plural(stats.key, "key", "keys")}`
  );
}

function sessionFor(checker) {
  // Raw and Hooks share the no-AST build — no procedures installed
  // versus the counting hooks — so the gap between those two buttons
  // is the hooks alone; the AST buttons use the build that constructs
  // a tree during the parse.
  if (checker.id !== "json") return sessions[checker.id];
  if (checker.mode === "raw") return sessions["json-raw"];
  if (checker.mode === "hooks") return sessions["json-hooks"];
  return sessions["json-snapshot"];
}

function showOk(checker, label, bytes, runMs, stats) {
  checker.statusClass = "ok";
  checker.result = { label, bytes, runMs, stats };
}

// One clear for every path that invalidates the current measurement:
// result, benchmark, class, and status go together, so the table can
// never describe input that no longer exists.
function resetMeasurement(checker, status) {
  checker.result = null;
  checker.benchmark = null;
  checker.statusClass = "";
  checker.status = status;
}

function plural(count, one, many) {
  return `${count} ${count === 1 ? one : many}`;
}

function fmtMs(value) {
  return `${value < 10 && value > 0 ? value.toFixed(1) : Math.round(value)} ms`;
}

function fmtDuration(ms) {
  if (ms < 1) {
    const micros = ms * 1000;
    return `${micros < 10 ? micros.toFixed(1) : Math.round(micros)} µs`;
  }
  return fmtMs(ms);
}

// The single table row is the batch the page actually ran: the batch's
// own measured total when one ran (and it was long enough to time),
// the single-run rate otherwise. Both are cleared together with the
// result, so the cells cannot outlive their input.
function rowCells(checker) {
  const runs = checker.benchmark?.runs ?? 1;
  const bytes = checker.result.bytes * runs;
  const ms = checker.benchmark ? checker.benchmark.totalMs : checker.result.runMs;
  return { bytes, time: fmtDuration(ms), rate: formatRate(bytes, ms) ?? "—" };
}

// Typed input past this length parses through the busy path: status
// first, one painted frame, then the synchronous parse. Smaller edits
// parse in place — there is nothing to wait for.
const INPUT_BUSY_CHARS = 256 * 1024;
const INPUT_DEBOUNCE_MS = 150;

// Pending debounce timers and queued parse runs stay outside reactivity.
const inputTimers = new Map();
const runChains = new Map();

function nextPaint() {
  // Microtasks never reach a frame boundary, so the busy state waits for
  // a real frame: rAF runs before paint, its timer runs after it.
  return new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 0)));
}

// Heavy runs are serialized per checker: the busy state (spinner,
// disabled buttons, checking… status) reacts immediately, each queued
// run repainted it right before the work takes the thread. Any
// non-benchmark work supersedes an outstanding benchmark.
function enqueue(checker, kind, work = () => runCheck(checker)) {
  if (kind !== "benchmark") invalidateBenchmark(checker);
  checker.busy = kind;
  const run = async () => {
    checker.busy = kind;
    await nextPaint();
    try {
      await work();
    } finally {
      checker.busy = null;
      // Whatever asked for this work stops spinning with it; the
      // spinner and the progress bar clear with the run that owned them.
      checker.pending = null;
      checker.progress = null;
    }
  };
  const previous = runChains.get(checker.id) ?? Promise.resolve();
  runChains.set(
    checker.id,
    previous.then(run).catch((error) => console.error(error)),
  );
}

function clearInputTimer(checker) {
  const timer = inputTimers.get(checker.id);
  if (timer !== undefined) clearTimeout(timer);
  inputTimers.delete(checker.id);
}

function inputEdited(checker) {
  clearInputTimer(checker);
  // Any edit supersedes outstanding benchmark work first: a benchmark
  // finishing later would pair its run count with the wrong input.
  invalidateBenchmark(checker);
  if (checker.text.length < INPUT_BUSY_CHARS) {
    runCheck(checker);
    return;
  }
  // The text just changed, so the table (and its run totals) describes
  // text that no longer exists: clear it now, not when the debounce
  // fires. The debounce then re-checks the size (it may have shrunk
  // back) and shows "checking…" for a frame before the parse blocks
  // the thread.
  resetMeasurement(checker, "");
  inputTimers.set(
    checker.id,
    setTimeout(() => {
      inputTimers.delete(checker.id);
      if (checker.text.length < INPUT_BUSY_CHARS) {
        runCheck(checker);
        return;
      }
      resetMeasurement(checker, "checking…");
      enqueue(checker, "input");
    }, INPUT_DEBOUNCE_MS),
  );
}

function setMode(checker, mode) {
  if (checker.busy || checker.mode === mode) return;
  checker.mode = mode;
  // The executor clears the result measured under the previous mode
  // and re-runs the count in effect under the new one, so the size
  // selected in the row below survives the switch.
  startRuns(checker, checker.runs, mode);
}

// A benchmark runs its workload in chunks of at most this long,
// repainting between them, so progress stays visible instead of
// freezing the tab.
const BENCHMARK_CHUNK_MS = 50;

function invalidateBenchmark(checker) {
  // Single cancel signal: bumping the id supersedes queued and running
  // benchmark work, which captures the id when it is requested.
  checker.benchmarkRequest = (checker.benchmarkRequest ?? 0) + 1;
}

const textBytesCache = new Map();
const EMPTY_INPUT = new Uint8Array(0);

// The one encode of the typed input: text plus its trailing newline
// (line-oriented grammars need it; the rest treat it as whitespace),
// re-encoded only when the text changed. The parser, the batch, and
// the size labels all read this same array, so a button's count can
// never disagree with the bytes a run parses. Uploaded files pass
// through byte-exact.
function inputBytes(checker) {
  if (checker.file) return fileInputs[checker.id] ?? EMPTY_INPUT;
  const cached = textBytesCache.get(checker.id);
  if (cached && cached.text === checker.text) return cached.bytes;
  const bytes = new TextEncoder().encode(`${checker.text}\n`);
  textBytesCache.set(checker.id, { text: checker.text, bytes });
  return bytes;
}

// A suggestion is the run count that brings an input of this size to
// the target total size: the batch reaches the target, an input that
// already meets it collapses to the one run, and an empty input can't
// fill any target — only its single run is offerable.
function suggestedRuns(inputSize, targetBytes) {
  if (inputSize < 1) return 1;
  return Math.ceil(targetBytes / inputSize);
}

// Which run button matches the current run count. Priority follows the
// spec: 1 wins over any suggestion that also clamps to 1 for big inputs.
function selectedRunButton(checker) {
  if (checker.runs === 1) return "single";
  const inputSize = inputBytes(checker).byteLength;
  if (checker.runs === suggestedRuns(inputSize, 1e6)) return "small";
  if (checker.runs === suggestedRuns(inputSize, 1e7)) return "medium";
  if (checker.runs === suggestedRuns(inputSize, 1e8)) return "large";
  return "custom";
}

// The custom count asks directly: enter a number, run that many
// parses. Cancel or invalid input runs nothing.
function promptRuns(checker) {
  const answer = prompt("Run the parser how many times?", String(checker.runs));
  if (answer === null) return null;
  const runs = Math.floor(Number(answer));
  return Number.isFinite(runs) && runs >= 1 ? runs : null;
}

// The result box's own action: run the count in effect again. It is
// the deliberate exception to askRun's no-op — its whole purpose is
// to run what is already in effect.
const RERUN_ID = "rerun";

// Shown only where it could act: a tab whose parser failed to start
// has no measurement to rerun and no way to produce one.
function rerunShown(checker) {
  return (
    checker.ready &&
    (Boolean(checker.result) ||
      checker.statusClass === "bad" ||
      actionPending(checker, RERUN_ID))
  );
}

function rerun(checker) {
  if (checker.busy) return;
  startRuns(checker, checker.runs, RERUN_ID);
}

// One entry for the repeat row, mirroring the mode row: an ask equal
// to what is already in effect does nothing.
function askRun(checker, action) {
  if (checker.busy) return;
  const runs = action.ask(checker);
  if (runs === null || runs === checker.runs) return;
  startRuns(checker, runs, action.id);
}

// The executor both run actions enter. The count and the spinner
// commit only where the work is enqueued, so the pending action
// always has exactly the run that clears it; every path that
// supersedes that run lands in runCheck, which rewrites the count to
// the parses that actually happened.
function startRuns(checker, runs, id) {
  if (!checker.ready) return;
  if (!checker.file && checker.text.trim() === "") {
    runCheck(checker);
    return;
  }
  checker.runs = runs;
  checker.pending = id;
  resetMeasurement(checker, "benchmarking…");
  invalidateBenchmark(checker);
  const request = checker.benchmarkRequest;
  enqueue(checker, "benchmark", () => runBenchmark(checker, runs, request));
}

async function runBenchmark(checker, runs, request) {
  // A superseded benchmark exits without touching state: the work
  // that superseded it already owns the table and the run count.
  if (checker.benchmarkRequest !== request) return;
  const { input } = currentInput(checker);
  const session = sessionFor(checker);
  let done = 0;
  let totalMs = 0;
  try {
    while (done < runs) {
      if (checker.benchmarkRequest !== request) return;
      // Chunk the workload into at most this long, repainting between
      // chunks, so the bar keeps moving. Each chunk is timed for the
      // batch total; the paint gaps between chunks are not part of
      // the work.
      const chunkStart = performance.now();
      while (performance.now() - chunkStart < BENCHMARK_CHUNK_MS && done < runs) {
        runWorkload(checker, session, input);
        done += 1;
      }
      totalMs += performance.now() - chunkStart;
      if (done >= runs) break;
      if (checker.benchmarkRequest !== request) return;
      checker.progress = done / runs;
      await nextPaint();
    }
    if (checker.benchmarkRequest !== request) return;
    // The row renders this batch: its own measured total is the time,
    // falling back to the per-run rate scaled by the count when the
    // batch is shorter than the timer resolves. runCheck writes every
    // result as one run, so the count that ran is restored in the same
    // tick — no paint pairs the row with a count of one.
    runCheck(checker);
    if (!checker.result) return;
    checker.runs = runs;
    checker.benchmark = {
      runs,
      totalMs: totalMs >= MIN_MEASURABLE_MS ? totalMs : checker.result.runMs * runs,
    };
  } catch {
    // A failing input shows its diagnostic through the standard check.
    runCheck(checker);
  }
}

// The browser's timer reads sub-100 µs work as 0 ms, so a lone call
// is timed only when it alone fills the window (big inputs, where any
// cold-start overhead is negligible); shorter work discards a possibly
// cold first call and averages a window of warm calls instead.
const MIN_MEASURABLE_MS = 2;
const MAX_TIMED_CALLS = 1e6;

function timeWindowed(op) {
  const firstStart = performance.now();
  let value = op();
  const firstMs = performance.now() - firstStart;
  if (firstMs >= MIN_MEASURABLE_MS) return { value, ms: firstMs };
  const start = performance.now();
  let calls = 0;
  do {
    value = op();
    calls += 1;
  } while (performance.now() - start < MIN_MEASURABLE_MS && calls < MAX_TIMED_CALLS);
  return { value, ms: (performance.now() - start) / calls };
}

// One definition of what one run of the workload costs — the call the
// table times and the batch loops: a bare parse for raw and hooks
// (the hooks fire inside session.parse), plus snapshot materialization
// for AST, plus the host walk for AST + visit. Hooks reset first so
// their stats describe this run; the input is shared bytes, never
// re-encoded here.
function runWorkload(checker, session, input) {
  const hooksMode = checker.id === "json" && checker.mode === "hooks";
  if (hooksMode) jsonHooks.resetStats();
  const bytes = session.parse(input);
  let stats = null;
  if (checker.mode === "ast") session.snapshot();
  else if (checker.mode === "ast-visit") stats = countSnapshot(session, input);
  else if (hooksMode) stats = { ...jsonHooks.stats };
  return { bytes, stats };
}

function timeParse(checker, input) {
  const session = sessionFor(checker);
  // One window over that same workload: a lone run and a batch time
  // identical work, so what the row shows and what a batch ran agree.
  const { value, ms } = timeWindowed(() => runWorkload(checker, session, input));
  return { bytes: value.bytes, runMs: ms, stats: value.stats };
}

function currentInput(checker) {
  if (checker.file) {
    return { input: fileInputs[checker.id], label: `${checker.title}: ${checker.file.name}` };
  }
  return { input: inputBytes(checker), label: checker.title };
}

function runCheck(checker) {
  // Any check invalidates a finished benchmark line (stale numbers) and
  // supersedes queued or running benchmark work.
  invalidateBenchmark(checker);
  checker.benchmark = null;
  // A plain check is one run of the mode's workload, so the run count
  // always describes what the table shows — every path that presents a
  // result writes it here.
  checker.runs = 1;
  if (!checker.ready) return;
  if (!checker.file && checker.text.trim() === "") {
    checker.result = null;
    checker.statusClass = "";
    checker.status = `type some ${checker.title}`;
    return;
  }
  try {
    const { input, label } = currentInput(checker);
    const { bytes, runMs, stats } = timeParse(checker, input);
    showOk(checker, label, bytes, runMs, stats);
  } catch (error) {
    const diagnostic = error?.diagnostic ?? sessionFor(checker)?.diagnostic?.() ?? null;
    if (!diagnostic) {
      checker.result = null;
      checker.statusClass = "bad";
      checker.status = error?.message ?? String(error);
      return;
    }
    if (checker.file) {
      checker.result = null;
      checker.statusClass = "bad";
      checker.status = `${checker.file.name}: ${diagnostic.line}:${diagnostic.column}: ${diagnostic.message}`;
    } else {
      showError(checker, diagnostic);
    }
  }
}

async function checkFile(checker, file) {
  await ensureChecker(checker);
  if (!checker.ready) return;
  clearInputTimer(checker);
  resetMeasurement(checker, `checking ${file.name}…`);
  let bytes;
  try {
    bytes = new Uint8Array(await file.arrayBuffer());
  } catch (error) {
    checker.statusClass = "bad";
    checker.status = `${file.name}: could not read file`;
    return;
  }
  fileInputs[checker.id] = bytes;
  checker.file = { name: file.name, size: bytes.length };
  enqueue(checker, "file");
}

function clearFile(checker) {
  clearInputTimer(checker);
  delete fileInputs[checker.id];
  checker.file = null;
  runCheck(checker);
}

function pickFile(checker, event) {
  const file = event.target.files?.[0];
  event.target.value = "";
  if (file) checkFile(checker, file);
}

function dropFile(checker, event) {
  checker.dragOver = false;
  const file = event.dataTransfer.files?.[0];
  if (file) checkFile(checker, file);
}

// Each wasm module loads only when its tab is first selected, not when
// the page opens. In-flight loads are tracked outside reactivity.
const loading = new Set();

async function ensureChecker(checker) {
  if (checker.ready || loading.has(checker.id)) return;
  loading.add(checker.id);
  // The sessions this attempt opens. Published only once all of them
  // exist, closed on failure: dropping a session without close()
  // orphans its wasm handle, so a retry must start from nothing.
  const openedSessions = [];
  try {
    const url = `${import.meta.env.BASE_URL}try-it/${checker.id}.wasm`;
    const parser = await galley.loadUrl(url);
    if (checker.id === "json") {
      // Raw and Hooks share this no-AST build. A session copies the
      // parser's procedures as it opens, so the raw session opens
      // first, then the counters are installed for the hooks session.
      // The AST buttons load the build that constructs a tree.
      const raw = parser.openSession();
      openedSessions.push(raw);
      parser.installProcedures(jsonHooks);
      const hooks = parser.openSession();
      openedSessions.push(hooks);
      const snapshotUrl = `${import.meta.env.BASE_URL}try-it/json-ast.wasm`;
      const snapshot = (await galley.loadUrl(snapshotUrl)).openSession();
      openedSessions.push(snapshot);
      sessions["json-raw"] = raw;
      sessions["json-hooks"] = hooks;
      sessions["json-snapshot"] = snapshot;
    } else {
      const session = parser.openSession();
      openedSessions.push(session);
      sessions[checker.id] = session;
    }
    checker.ready = true;
    // A tab's first measurement is the default offer: the button the
    // page lights must be the batch it actually ran.
    startRuns(checker, DEFAULT_RUN_ACTION.ask(checker), DEFAULT_RUN_ACTION.id);
  } catch (error) {
    // Before ready the sessions are this attempt's scratch — close
    // them so the retry starts clean. After ready they belong to the
    // page and stay.
    if (!checker.ready) {
      for (const session of openedSessions) session.close();
    }
    checker.statusClass = "bad";
    checker.status = `failed to start: ${error.message ?? error}`;
  } finally {
    loading.delete(checker.id);
  }
}

// The disabled row shows the default from the first paint, so the lit
// button already describes the batch that runs once ready. Settled at
// the end of setup, where the ask's byte-count machinery exists.
for (const checker of checkers) {
  checker.runs = DEFAULT_RUN_ACTION.ask(checker);
}

onMounted(async () => {
  watch(active, (id) => {
    const selected = checkers.find((checker) => checker.id === id);
    if (selected) ensureChecker(selected);
  });
  await ensureChecker(checkers.find((checker) => checker.id === active.value));
});
</script>

<style scoped>
.try-it .tabs {
  display: flex;
  gap: 0.5rem;
  margin-bottom: 0.75rem;
}

.try-it .tab {
  padding: 0.4rem 1.1rem;
  border: 1px solid var(--vp-c-border);
  border-radius: 8px;
  background: transparent;
  color: var(--vp-c-text-2);
  font-size: 14px;
  cursor: pointer;
}

.try-it .tab.active {
  border-color: var(--vp-c-brand-1);
  color: var(--vp-c-brand-1);
}

.try-it .tab:disabled {
  opacity: 0.6;
  cursor: default;
}

.try-it .spinner {
  display: inline-block;
  width: 0.8em;
  height: 0.8em;
  margin-right: 0.35em;
  border: 2px solid currentColor;
  border-right-color: transparent;
  border-radius: 50%;
  vertical-align: -0.05em;
  animation: try-it-spin 0.7s linear infinite;
}

@keyframes try-it-spin {
  to {
    transform: rotate(360deg);
  }
}

.try-it .checker {
  margin-bottom: 2.5rem;
}

.try-it .modes {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin: 0.75rem 0;
  font-size: 14px;
  color: var(--vp-c-text-2);
}

.try-it .modes .tab {
  padding: 0.25rem 0.9rem;
  border: 1px solid var(--vp-c-border);
  border-radius: 8px;
  background: transparent;
  color: var(--vp-c-text-2);
  font-size: 14px;
  cursor: pointer;
}

.try-it .modes .tab.active {
  border-color: var(--vp-c-brand-1);
  color: var(--vp-c-brand-1);
}

.try-it .bench {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin: 0.75rem 0;
  font-size: 14px;
  color: var(--vp-c-text-2);
}

.try-it .bench .tab {
  padding: 0.25rem 0.9rem;
  border: 1px solid var(--vp-c-border);
  border-radius: 8px;
  background: transparent;
  color: var(--vp-c-text-2);
  font-size: 14px;
  cursor: pointer;
}

.try-it .bench .tab:disabled {
  opacity: 0.5;
  cursor: default;
}

.try-it .bench .tab.active {
  border-color: var(--vp-c-brand-1);
  color: var(--vp-c-brand-1);
}

.try-it table.numbers {
  border-collapse: collapse;
  margin: 0.5rem 0;
  font-size: 14px;
}

.try-it table.numbers th,
.try-it table.numbers td {
  border: 1px solid var(--vp-c-border);
  padding: 0.2rem 0.7rem;
  text-align: right;
}

.try-it table.numbers td:first-child,
.try-it table.numbers th:first-child {
  text-align: left;
}

.try-it .dropzone {
  display: block;
  border: 1px dashed var(--vp-c-border);
  border-radius: 8px;
  padding: 1rem;
  text-align: center;
  color: var(--vp-c-text-2);
  cursor: pointer;
  margin-bottom: 0.75rem;
}

.try-it .dropzone.over {
  border-color: var(--vp-c-brand-1);
  color: var(--vp-c-brand-1);
}

.try-it .dropzone.disabled {
  opacity: 0.5;
  cursor: default;
}

.try-it .filebar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
  border: 1px solid var(--vp-c-border);
  border-radius: 8px;
  padding: 0.6rem 0.75rem;
  margin-bottom: 0.75rem;
  font-size: 14px;
  color: var(--vp-c-text-1);
}

.try-it .filebar .tab {
  padding: 0.25rem 0.9rem;
  border: 1px solid var(--vp-c-border);
  border-radius: 8px;
  background: transparent;
  color: var(--vp-c-text-2);
  font-size: 14px;
  cursor: pointer;
  white-space: nowrap;
}

.try-it textarea {
  display: block;
  width: 100%;
  font-family: monospace;
  font-size: 14px;
  background-color: var(--vp-c-bg-alt);
  color: var(--vp-c-text-1);
  border: 1px solid var(--vp-c-border);
  border-radius: 8px;
  padding: 0.5rem;
}

.try-it .status {
  position: relative;
  white-space: pre-wrap;
  margin-top: 0.75rem;
  padding: 0.75rem;
  /* Reserve the top-right corner for the rerun button in every state,
     so the layout never jumps when it appears or disappears. */
  padding-right: 6.5rem;
  border: 1px solid var(--vp-c-border);
  border-radius: 8px;
  min-height: 3rem;
}

.try-it .status .rerun {
  position: absolute;
  top: 0.5rem;
  right: 0.5rem;
}

.try-it .progress {
  display: block;
  width: 100%;
  height: 6px;
  margin-top: 0.5rem;
  appearance: none;
  border: none;
  border-radius: 4px;
  background: var(--vp-c-default-soft);
}

.try-it .progress::-webkit-progress-bar {
  background: var(--vp-c-default-soft);
  border-radius: 4px;
}

.try-it .progress::-webkit-progress-value {
  background: var(--vp-c-brand-1);
  border-radius: 4px;
}

.try-it .progress::-moz-progress-bar {
  background: var(--vp-c-brand-1);
  border-radius: 4px;
}

.try-it .status.ok {
  border-color: var(--vp-c-green-1);
  color: var(--vp-c-green-1);
}

.try-it .status.bad {
  border-color: var(--vp-c-red-1);
  color: var(--vp-c-red-1);
}

.try-it .engines {
  margin-top: 1rem;
  font-size: 13px;
  color: var(--vp-c-text-2);
}
</style>
