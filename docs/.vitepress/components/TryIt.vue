<template>
  <div class="try-it">
    <div class="tabs">
      <button
        v-for="checker in checkers"
        :key="checker.id"
        class="tab"
        :class="{ active: checker.id === active }"
        @click="active = checker.id"
      >
        {{ checker.title }}
      </button>
    </div>
    <section v-for="checker in checkers" v-show="checker.id === active" :key="checker.id" class="checker">
      <label
        class="dropzone"
        :class="{ over: checker.dragOver, disabled: !checker.ready }"
        @dragover.prevent="(e) => { checker.dragOver = true; e.dataTransfer.dropEffect = 'copy'; }"
        @dragleave="checker.dragOver = false"
        @drop.prevent="(e) => dropFile(checker, e)"
      >
        <input
          type="file"
          hidden
          :disabled="!checker.ready"
          @change="(e) => pickFile(checker, e)"
        />
        <span>Drop a {{ checker.ext }} file here, or click to browse</span>
      </label>
      <div v-if="checker.file" class="filebar">
        <span>Using file {{ checker.file.name }} ({{ checker.file.size }} bytes)</span>
        <button class="tab" @click="() => clearFile(checker)">
          Clear {{ checker.file.name }} and type instead
        </button>
      </div>
      <textarea
        v-else
        v-model="checker.text"
        spellcheck="false"
        rows="8"
        :disabled="!checker.ready"
        @input="() => runCheck(checker)"
      ></textarea>
      <div v-if="checker.id === 'json'" class="modes">
        <span>Count with</span>
        <button
          class="tab"
          :class="{ active: checker.mode === 'hooks' }"
          @click="() => setMode(checker, 'hooks')"
        >
          Hooks
        </button>
        <button
          class="tab"
          :class="{ active: checker.mode === 'snapshot' }"
          @click="() => setMode(checker, 'snapshot')"
        >
          AST snapshot
        </button>
      </div>
      <div v-if="checker.result" class="status ok">
        <div>valid {{ checker.result.label }} ({{ checker.result.bytes }} bytes)</div>
        <table class="numbers">
          <tr>
            <th></th>
            <th>time</th>
            <th>throughput</th>
          </tr>
          <tr>
            <td>parse</td>
            <td>{{ fmtMs(checker.result.parseMs) }}</td>
            <td>{{ formatRate(checker.result.bytes, checker.result.parseMs) ?? "—" }}</td>
          </tr>
          <tr v-if="checker.id === 'json' && checker.mode === 'snapshot'">
            <td>parse + visit</td>
            <td>{{ fmtMs(checker.result.parseMs + checker.result.countMs) }}</td>
            <td>{{ formatRate(checker.result.bytes, checker.result.parseMs + checker.result.countMs) ?? "—" }}</td>
          </tr>
        </table>
        <div>{{ countsLine(checker.result.stats) }}</div>
      </div>
      <div v-else class="status" :class="checker.statusClass">{{ checker.status }}</div>
    </section>
    <p class="engines">
      Throughput is fastest in Chrome; Firefox is close behind; Safari is
      an order of magnitude slower.
    </p>
  </div>
</template>

<script setup>
import { reactive, ref, onMounted } from "vue";
import * as jsonHooks from "../../try-it/lang/json/procedures.js";
import { countSnapshot } from "../../try-it/lang/json-ast/snapshot-stats.js";

function formatRate(bytes, elapsedMs) {
  if (!(elapsedMs > 0)) return null;
  const perSecond = (bytes / elapsedMs) * 1000;
  if (perSecond >= 1e6) return `${(perSecond / 1e6).toFixed(1)} MB/s`;
  if (perSecond >= 1e3) return `${(perSecond / 1e3).toFixed(1)} kB/s`;
  return `${Math.round(perSecond)} B/s`;
}

const active = ref("lisp");

const checkers = reactive([
  {
    id: "lisp",
    title: "Lisp",
    ext: ".lisp",
    text: "(define (square x) (* x x))",
    status: "loading parser…",
    statusClass: "",
    dragOver: false,
    ready: false,
    file: null,
  },
  {
    id: "json",
    title: "JSON",
    ext: ".json",
    text: '{"hello": ["world", 42], "ok": true}',
    status: "loading parser…",
    statusClass: "",
    dragOver: false,
    ready: false,
    file: null,
    mode: "hooks",
    result: null,
  },
  {
    id: "lua",
    title: "Lua",
    ext: ".lua",
    text: 'local name = "world"\nprint("hi " .. name)',
    status: "loading parser…",
    statusClass: "",
    dragOver: false,
    ready: false,
    file: null,
  },
]);

// Parser sessions and uploaded file bytes live outside reactivity: Vue
// proxies break the adapter's private methods (Safari: "Cannot access
// private method") and add overhead to large inputs.
const sessions = {};
const fileInputs = {};

let galley = null;
const decoder = new TextDecoder();

function showError(checker, diagnostic) {
  checker.result = null;
  checker.statusClass = "bad";
  const lines = [`${diagnostic.line}:${diagnostic.column}: ${diagnostic.message}`];
  if (diagnostic.expectedTokens && diagnostic.expectedTokens.length > 0) {
    const shown = diagnostic.expectedTokens
      .slice(0, 8)
      .map((token) => `'${galley.displayTokenName(token) ?? decoder.decode(token)}'`)
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
  if (checker.id === "json" && checker.mode === "snapshot") return sessions["json-snapshot"];
  return sessions[checker.id];
}

function showOk(checker, label, bytes, parseMs, countMs, stats) {
  checker.statusClass = "ok";
  checker.result = { label, bytes, parseMs, countMs, stats: checker.id === "json" ? stats : null };
}

function plural(count, one, many) {
  return `${count} ${count === 1 ? one : many}`;
}

function fmtMs(value) {
  return `${value < 10 && value > 0 ? value.toFixed(1) : Math.round(value)} ms`;
}

function setMode(checker, mode) {
  if (checker.mode === mode) return;
  checker.mode = mode;
  runCheck(checker);
}

function toInputBytes(input) {
  return typeof input === "string" ? new TextEncoder().encode(input) : input;
}

function timeParse(checker, input) {
  const session = sessionFor(checker);
  let stats = null;
  let countMs = 0;
  if (checker.id === "json" && checker.mode === "hooks") jsonHooks.resetStats();
  const parseStart = performance.now();
  const bytes = session.parse(input);
  const parseMs = performance.now() - parseStart;
  if (checker.id === "json") {
    if (checker.mode === "hooks") {
      stats = { ...jsonHooks.stats };
    } else {
      const countStart = performance.now();
      stats = countSnapshot(session, toInputBytes(input));
      countMs = performance.now() - countStart;
    }
  }
  return { bytes, parseMs, countMs, stats };
}

function currentInput(checker) {
  if (checker.file) {
    return { input: fileInputs[checker.id], label: `${checker.title}: ${checker.file.name}` };
  }
  return { input: checker.text, label: checker.title };
}

function runCheck(checker) {
  if (!checker.ready) return;
  if (!checker.file && checker.text.trim() === "") {
    checker.result = null;
    checker.statusClass = "";
    checker.status = `type some ${checker.title}`;
    return;
  }
  try {
    const { input, label } = currentInput(checker);
    const { bytes, parseMs, countMs, stats } = timeParse(checker, input);
    showOk(checker, label, bytes, parseMs, countMs, stats);
  } catch (error) {
    const diagnostic = error.diagnostic ?? sessionFor(checker).diagnostic();
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
  checker.result = null;
  checker.statusClass = "";
  checker.status = `checking ${file.name}…`;
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
  runCheck(checker);
}

function clearFile(checker) {
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
  if (file && checker.ready) checkFile(checker, file);
}

onMounted(async () => {
  try {
    galley = await import("galley-js-wasm");
    galley.installProcedures(jsonHooks);
    for (const checker of checkers) {
      const url = `${import.meta.env.BASE_URL}try-it/${checker.id}.wasm`;
      await galley.init({ url, libraryPath: checker.id });
      sessions[checker.id] = new galley.Session({ libraryPath: checker.id });
      if (checker.id === "json") {
        const snapshotUrl = `${import.meta.env.BASE_URL}try-it/json-ast.wasm`;
        await galley.init({ url: snapshotUrl, libraryPath: "json-snapshot" });
        sessions["json-snapshot"] = new galley.Session({ libraryPath: "json-snapshot" });
      }
      checker.ready = true;
      runCheck(checker);
    }
  } catch (error) {
    for (const checker of checkers) {
      if (!checker.ready) {
        checker.statusClass = "bad";
        checker.status = `failed to start: ${error.message ?? error}`;
      }
    }
  }
});
</script>

<style scoped>
.try-it .tabs {
  display: flex;
  gap: 0.5rem;
  margin-bottom: 1.25rem;
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
.try-it .checker {
  margin-bottom: 2.5rem;
}
.try-it .modes {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 0.75rem;
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
  white-space: pre-wrap;
  margin-top: 0.75rem;
  padding: 0.75rem;
  border: 1px solid var(--vp-c-border);
  border-radius: 8px;
  min-height: 3rem;
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
