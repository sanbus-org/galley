/**
 * WebAssembly adapter for the Galley JavaScript bindings: a `WasmPort`
 * implementing the core `FfiPort` over a WASI reactor module built from
 * `bindings/c/galley.h` (`zig build -Dwasm`, see `build.mjs`).
 *
 * Zero npm dependencies. The module is instantiated with a minimal
 * in-TS `wasi_snapshot_preview1` stub (real `random_get`/`clock_time_get`,
 * filesystem calls report unavailable — the parse path never touches the
 * filesystem) plus an `env.galley_host_dispatch` import that forwards
 * procedure hooks (session handle, hook index) to the owning session. All memory copying
 * and integer normalization live here; all session logic lives in
 * `@sanbus/galley-core`.
 *
 * Port acquisition is synchronous (`getWasmPort`): file-backed modules
 * read and instantiate under Node, byte-fed modules instantiate in every
 * runtime. Fetching a module over the network (`url`) stays asynchronous
 * and lives in the session factories, which are async on every entry.
 * Views into wasm memory are never cached: `malloc` may grow memory and
 * detach old views.
 */

import type {
  FfiPort,
  NodeFamily,
  Handle,
  HookTicket,
  DispatchHandler,
  SessionCOptions,
  SnapshotColumns,
} from "@sanbus/galley-core";
import { GalleyError, NO_VARIABLE, Status } from "@sanbus/galley-core";
import { GenerationBigInt, resolveArtifact, resolveArtifactFile, wasmArtifactFileName } from "@sanbus/galley-core/internal";
import { hashModuleBytes } from "@sanbus/galley-core/internal";

const LIBRARY_BASE = "galley-js-wasm";
const WASI_NOSYS = 52;
const WASI_BADF = 8;

/** Callable view of the wasm exports (wasm32: pointers/i32 are `number`, i64/u64 are `bigint`). */
/**
 * The node, tree and walk exports both doors expose, keyed by the C name
 * after `galley_`. The guest exports each twice: `galley_<name>` over a
 * session handle and `galley_hook_<name>` over a parse's door, with
 * identical signatures. A refusal is a negative status.
 */
interface DoorCalls {
  node_child_count(handle: number, generation: bigint, node: bigint): bigint;
  node_first_child(handle: number, generation: bigint, node: bigint): bigint;
  node_last_child(handle: number, generation: bigint, node: bigint): bigint;
  node_next_sibling(handle: number, generation: bigint, node: bigint): bigint;
  node_prior_sibling(handle: number, generation: bigint, node: bigint): bigint;
  node_parent(handle: number, generation: bigint, node: bigint): bigint;
  node_symbol_name(handle: number, generation: bigint, node: bigint, outData: number, outLen: number): bigint;
  node_text(handle: number, generation: bigint, node: bigint, outData: number, outLen: number): bigint;
  node_span(handle: number, generation: bigint, node: bigint, outStart: number, outLen: number): bigint;
  node_line_column(handle: number, generation: bigint, node: bigint, outLine: number, outCol: number): bigint;
  node_variable_index(handle: number, generation: bigint, node: bigint): bigint;
  walk_next(handle: number, cursor: number): bigint;
  tree_append_children(handle: number, generation: bigint, parent: bigint, firstGeneration: bigint, first: bigint): bigint;
  tree_insert_before(handle: number, generation: bigint, target: bigint, firstGeneration: bigint, first: bigint): bigint;
  tree_insert_after(handle: number, generation: bigint, target: bigint, firstGeneration: bigint, first: bigint): bigint;
  tree_remove_siblings(handle: number, generation: bigint, node: bigint, count: number, outHead: number): bigint;
  tree_remove_self(handle: number, generation: bigint, node: bigint, outHead: number): bigint;
  tree_clean_children(handle: number, generation: bigint, node: bigint, outHead: number): bigint;
  tree_insert_children_at(handle: number, generation: bigint, parent: bigint, index: number, firstGeneration: bigint, first: bigint): bigint;
  tree_remove_children_at(handle: number, generation: bigint, parent: bigint, index: number, count: number, outHead: number): bigint;
}

/** `DoorCalls` under one door's C names: `galley_<name>` or `galley_hook_<name>`. */
type DoorNames<Door extends "" | "hook_"> = {
  [Name in keyof DoorCalls as `galley_${Door}${Name & string}`]: DoorCalls[Name];
};

interface GalleyWasmExports extends DoorNames<"">, DoorNames<"hook_"> {
  memory: WebAssembly.Memory;
  _initialize?: unknown;
  galley_js_malloc(len: number): number;
  galley_js_free(ptr: number, len: number): void;
  galley_version(): number;
  galley_parser_type(): bigint;
  galley_error_recovery_mode(): bigint;
  galley_has_ast(): number;
  galley_has_procedures(): number;
  galley_allows_no_ast_tree_procedures(): number;
  galley_source_retention_enabled(): number;
  galley_has_position_tracking(): number;
  galley_has_input_streaming(): number;
  galley_uses_verbatim(): number;
  galley_stack_overflow_recovery_available(): number;
  galley_symbol_count(): bigint;
  galley_variable_count(): bigint;
  galley_status_string(status: bigint): number;
  galley_symbol_name(session: number, index: bigint, outData: number, outLen: number): bigint;
  galley_symbol_is_terminal(session: number, index: bigint): number;
  galley_variable_name(session: number, index: bigint, outData: number, outLen: number): bigint;
  galley_session_create(): number;
  galley_session_create_ex(options: number): number;
  galley_session_destroy(session: number): void;
  galley_session_set_message_override(
    session: number,
    name: number,
    nameLen: number,
    message: number,
    messageLen: number,
  ): bigint;
  galley_parse(session: number, data: number, len: number): bigint;
  galley_node_count(session: number, generation: bigint): bigint;
  galley_reserve_nodes(session: number, capacity: bigint): bigint;
  galley_node_capacity(session: number): bigint;
  galley_root_node(session: number, outRoot: number, outGeneration: number): bigint;
  galley_tree_snapshot(
    session: number,
    generation: bigint,
    outParent: number,
    outFirstChild: number,
    outNext: number,
    outChildCount: number,
    outVariable: number,
    outSpanStart: number,
    outSpanLen: number,
    outIsSemanticError: number,
    outIsRecovered: number,
    capacity: bigint,
  ): bigint;
  galley_last_position(session: number, outLine: number, outCol: number): bigint;
  galley_last_input(session: number, outData: number, outLen: number): bigint;
  galley_has_diagnostic(session: number): number;
  galley_diagnostic_kind(session: number): bigint;
  galley_diagnostic_message(session: number, out: number): bigint;
  galley_diagnostic_message_ansi(session: number, out: number): bigint;
  galley_diagnostic_position(session: number, outLine: number, outCol: number): bigint;
  galley_diagnostic_unexpected_token(session: number, outData: number, outLen: number): bigint;
  galley_diagnostic_expected_count(session: number): bigint;
  galley_diagnostic_expected_at(session: number, index: bigint, outData: number, outLen: number): bigint;
  galley_diagnostic_context_count(session: number): bigint;
  galley_diagnostic_context_at(session: number, index: bigint, outData: number, outLen: number): bigint;
  galley_diagnostic_indentation(session: number, outSpaces: number, outWidth: number): bigint;
  galley_syntax_error_count(session: number): bigint;
  galley_semantic_error_count(session: number): bigint;
  galley_diagnostic_semantic(
    session: number,
    outVariable: number,
    outVariableLen: number,
    outMessage: number,
    outMessageLen: number,
  ): bigint;
  galley_diagnostic_recovery_kind(session: number): bigint;
  galley_diagnostic_recovery_terminal(session: number, outData: number, outLen: number): bigint;
  galley_diagnostic_recovery_resume(session: number, out: number): bigint;
  galley_diagnostic_recovery_lhs_variable(session: number, outData: number, outLen: number): bigint;
  galley_diagnostic_recovery_production(
    session: number,
    outVar: number,
    outLen: number,
    outIndex: number,
  ): bigint;
  galley_diagnostic_recovery_occurrence(
    session: number,
    outParent: number,
    outParentLen: number,
    outRhs: number,
    outSym: number,
    outVar: number,
    outVarLen: number,
  ): bigint;
  galley_recorded_diagnostic_count(session: number): bigint;
  galley_recorded_diagnostic_kind(session: number, index: bigint): bigint;
  galley_recorded_diagnostic_position(
    session: number,
    index: bigint,
    outLine: number,
    outCol: number,
  ): bigint;
  galley_recorded_unexpected_token(
    session: number,
    index: bigint,
    outData: number,
    outLen: number,
  ): bigint;
  galley_recorded_diagnostic_message(session: number, index: bigint, out: number): bigint;
  galley_recorded_indentation(
    session: number,
    index: bigint,
    outSpaces: number,
    outWidth: number,
  ): bigint;
  galley_recorded_semantic(
    session: number,
    index: bigint,
    outVariable: number,
    outVariableLen: number,
    outMessage: number,
    outMessageLen: number,
  ): bigint;
  galley_recorded_expected_count(session: number, index: bigint): bigint;
  galley_recorded_expected_token(
    session: number,
    index: bigint,
    tokenIndex: bigint,
    outData: number,
    outLen: number,
  ): bigint;
  galley_recorded_context_count(session: number, index: bigint): bigint;
  galley_recorded_context_name(
    session: number,
    index: bigint,
    contextIndex: bigint,
    outData: number,
    outLen: number,
  ): bigint;
  galley_recorded_diagnostic_recovery_kind(session: number, index: bigint): bigint;
  galley_recorded_recovery_terminal(
    session: number,
    index: bigint,
    outData: number,
    outLen: number,
  ): bigint;
  galley_recorded_recovery_resume(session: number, index: bigint, out: number): bigint;
  galley_recorded_recovery_lhs_variable(
    session: number,
    index: bigint,
    outData: number,
    outLen: number,
  ): bigint;
  galley_recorded_recovery_production(
    session: number,
    index: bigint,
    outVar: number,
    outLen: number,
    outIdx: number,
  ): bigint;
  galley_recorded_recovery_occurrence(
    session: number,
    index: bigint,
    outParent: number,
    outParentLen: number,
    outRhs: number,
    outSym: number,
    outVar: number,
    outVarLen: number,
  ): bigint;
  galley_procedure_current_node(session: number, hook: bigint): bigint;
  galley_procedure_door(session: number, hook: bigint, outDoor: number): bigint;
  galley_procedure_set_current_node(session: number, hook: bigint, generation: bigint, node: bigint): bigint;
  galley_procedure_drop_self(session: number, hook: bigint): bigint;
  galley_procedure_drop_children(session: number, hook: bigint): bigint;
  galley_procedure_drop_if_empty(session: number, hook: bigint): bigint;
  galley_procedure_replace_with_children(session: number, hook: bigint): bigint;
  galley_procedure_context_line(session: number, hook: bigint): bigint;
  galley_procedure_context_column(session: number, hook: bigint): bigint;
  galley_procedure_report_semantic_error(session: number, hook: bigint, message: number, messageLen: number): bigint;
  galley_hook_generation(door: number, outGeneration: number): bigint;
  // host hooks (see galley_session_set_hooks in galley.h)
  galley_hooks_count(): number;
  galley_hooks_name_data(index: number): number;
  galley_hooks_name_length(index: number): number;
  galley_session_set_hooks(session: number, dispatch: number, hookHandle: number, enabled: number, enabledCount: number): bigint;
}

// --- instance cache (one module per grammar file) --------------------------

const ports = new Map<string, WasmPort>();

interface ProcessGlobal {
  versions?: { node?: string };
  stdout?: { write(text: string): void };
  stderr?: { write(text: string): void };
}

function nodeProcess(): ProcessGlobal | undefined {
  return (globalThis as { process?: ProcessGlobal }).process;
}

function isNode(): boolean {
  return typeof nodeProcess()?.versions?.node === "string";
}

/**
 * Host file access. The Node entry (`index.ts`) seeds the real
 * filesystem; the browser entry leaves it unset, where file-backed
 * loads throw loudly (browsers pass `bytes` or fetch a `url`).
 */
export interface FileIo {
  existsSync(localPath: string): boolean;
  readFile(localPath: string): Uint8Array;
  resolvePath(candidate: string): string;
}

let fileIo: FileIo | null = null;
let fileIoUsed = false;

/** Node entry wires the real filesystem; browsers never call this. Reseeding after file-backed loads is a loud error. Byte-fed loads never touch file IO and never lock it. */
export function seedFileIo(io: FileIo): void {
  if (fileIoUsed) {
    throw new Error("galley-wasm: file IO is already in use and cannot be reseeded");
  }
  fileIo = io;
}


// --- library discovery -----------
// One place, named up front: the language directory must hold the
// adapter's standard-named module file.

const BUILD_HINT =
  `Build it first: npx galley-js-wasm <language-dir>\n` +
  `That leaves ${wasmFileName()} in the directory.`;

export function wasmFileName(base = LIBRARY_BASE): string {
  return wasmArtifactFileName(base);
}

function exists(localPath: string): boolean {
  try {
    return fileIo?.existsSync(localPath) ?? false;
  } catch {
    return false;
  }
}

export function findLibrary(languagePath: string): string {
  return resolveArtifact(languagePath, wasmFileName(), joinPath, {
    resolvePath: (candidate) => fileIo?.resolvePath(candidate) ?? candidate,
    existsSync: exists,
    buildHint: BUILD_HINT,
  });
}

/** Explicit-file twin of {@link findLibrary}: names the module itself. */
export function findLibraryFile(filePath: string): string {
  return resolveArtifactFile(filePath, {
    resolvePath: (candidate) => fileIo?.resolvePath(candidate) ?? candidate,
    existsSync: exists,
    buildHint: BUILD_HINT,
  });
}

function joinPath(directory: string, file: string): string {
  return directory.endsWith("/") ? directory + file : `${directory}/${file}`;
}

// --- minimal WASI stub ------------------------------------------------------
// Real entropy and clocks; filesystem calls report unavailable. The parse
// path never touches the filesystem (`parseFile` is served by the host
// reading the file into a buffer first).

function makeWasiStub(getMemory: () => ArrayBuffer): Record<string, WebAssembly.ImportValue> {
  const view = () => new DataView(getMemory());
  const bytes = () => new Uint8Array(getMemory());
  const fail = () => WASI_NOSYS;
  return {
    random_get: (ptr: number, len: number) => {
      crypto.getRandomValues(bytes().subarray(ptr, ptr + len));
      return 0;
    },
    clock_res_get: (_id: number, resPtr: number) => {
      view().setBigUint64(resPtr, 1n, true);
      return 0;
    },
    clock_time_get: (_id: number, _precision: bigint, timePtr: number) => {
      view().setBigUint64(timePtr, BigInt(Date.now()) * 1000000n, true);
      return 0;
    },
    fd_write: (fd: number, iovs: number, iovsLen: number, nwrittenPtr: number) => {
      try {
        const dataView = view();
        let written = 0;
        const chunks: Uint8Array[] = [];
        for (let i = 0; i < iovsLen; i++) {
          const base = dataView.getUint32(iovs + i * 8, true);
          const len = dataView.getUint32(iovs + i * 8 + 4, true);
          chunks.push(bytes().slice(base, base + len));
          written += len;
        }
        if (fd === 1 || fd === 2) {
          const text = chunks.map((c) => new TextDecoder().decode(c)).join("");
          const hostProcess = nodeProcess();
          if (isNode() && hostProcess?.stdout && hostProcess?.stderr) {
            (fd === 1 ? hostProcess.stdout : hostProcess.stderr).write(text);
          } else if (fd === 2) {
            console.error(text);
          } else {
            console.log(text);
          }
        }
        dataView.setUint32(nwrittenPtr, written, true);
        return 0;
      } catch {
        return WASI_NOSYS;
      }
    },
    proc_exit: (code: number) => {
      throw new Error(`galley-wasm: guest called proc_exit(${code})`);
    },
    // No preopened directories: BADF ends the preopen scan (NOSYS aborts libc init).
    fd_prestat_get: () => WASI_BADF,
    fd_fdstat_get: fail,
    fd_filestat_get: fail,
    fd_filestat_set_size: fail,
    fd_filestat_set_times: fail,
    fd_pread: fail,
    fd_prestat_dir_name: fail,
    fd_pwrite: fail,
    fd_read: fail,
    fd_seek: fail,
    path_create_directory: fail,
    path_filestat_get: fail,
    path_filestat_set_times: fail,
    path_link: fail,
    path_open: fail,
    path_readlink: fail,
    path_remove_directory: fail,
    path_rename: fail,
    path_symlink: fail,
    path_unlink_file: fail,
    poll_oneoff: fail,
    fd_sync: fail,
    fd_readdir: fail,
    fd_close: fail,
  };
}

// --- loader -----------------------------------------------------------------

export interface WasmPortSource {
  /** Language directory holding the standard-named module file. */
  languagePath?: string;
  /** Explicit module file. Wires nothing; install hooks explicitly. */
  filePath?: string;
  /** Raw module bytes. Instantiates synchronously in every runtime. */
  bytes?: Uint8Array;
}

interface PendingInstance {
  port: WasmPort | null;
  memory: ArrayBuffer | null;
}

function makeImports(pending: PendingInstance): WebAssembly.Imports {
  return {
    wasi_snapshot_preview1: makeWasiStub(() => {
      if (pending.memory === null) throw new Error("galley-wasm: memory unavailable");
      return pending.memory;
    }),
    env: {
      // Every hook of the module: the session's handle, the hook's index,
      // and the ticket of this hook call (a 64-bit value, so a BigInt).
      galley_host_dispatch: (hookHandle: number, hookIndex: number, hook: bigint): number => {
        return pending.port?.hookDispatch?.(hookHandle, hookIndex, hook) ?? 1;
      },
    },
  };
}

function adoptInstance(
  instance: WebAssembly.Instance,
  wasmPath: string,
  pending: PendingInstance,
  cache: boolean,
): WasmPort {
  pending.memory = (instance.exports.memory as WebAssembly.Memory).buffer;
  if (typeof instance.exports._initialize === "function") {
    (instance.exports._initialize as () => void)();
  }
  const port = new WasmPort(instance.exports as unknown as GalleyWasmExports, wasmPath);
  pending.port = port;
  if (cache) ports.set(wasmPath, port);
  return port;
}

function instantiate(bytes: Uint8Array<ArrayBuffer>, wasmPath: string, cache: boolean): WasmPort {
  const pending: PendingInstance = { port: null, memory: null };
  const instance = new WebAssembly.Instance(compileModuleSync(bytes), makeImports(pending));
  return adoptInstance(instance, wasmPath, pending, cache);
}

// --- compiled-module cache (one Module per distinct bytes) -----------------
// Compilation dominates instantiation cost, so compiled modules are shared
// while instances stay per session (session state lives in the instance:
// sharing one would merge sessions). Unbounded like the port cache, by the
// same documented policy.

const compiledModules = new Map<string, WebAssembly.Module>();

function compileModuleSync(bytes: Uint8Array<ArrayBuffer>): WebAssembly.Module {
  const key = hashModuleBytes(bytes);
  const hit = compiledModules.get(key);
  if (hit !== undefined) return hit;
  const module = new WebAssembly.Module(bytes);
  compiledModules.set(key, module);
  return module;
}

/** Test-only: clear the compiled-module cache. */
export function __resetModuleCache(): void {
  compiledModules.clear();
}

/** Test-only: clear the file-IO consumption flag (mirrors `__resetLoader`). */
export function __resetWasmAcquisition(): void {
  fileIoUsed = false;
}

/**
 * Synchronously instantiates raw module bytes. Compiled modules are
 * shared through the cache above, but every call gets a fresh instance:
 * session state lives in the instance, so sharing one would merge
 * sessions. Byte ports arrive only through this gate (`getWasmPort`
 * and the universal loader's byte path delegate here).
 */
export function instantiateWasm(bytes: Uint8Array): WasmPort {
  return instantiate(Uint8Array.from(bytes), "<bytes>", false);
}

/**
 * Single gate for synchronous consumers: returns the port for a
 * language directory or an explicit module file (file-backed, cached
 * per resolved path) or for raw bytes (fresh per call). Network fetch
 * stays asynchronous and lives in the session.
 */
export function getWasmPort(source: WasmPortSource): WasmPort {
  if (source.bytes) {
    return instantiateWasm(source.bytes);
  }
  if (source.filePath === undefined && source.languagePath === undefined) {
    throw new TypeError("galley-wasm: pass languagePath, filePath, or bytes");
  }
  if (!fileIo) {
    throw new Error("galley-wasm: artifact files need file access; pass bytes or url instead");
  }
  if (source.filePath !== undefined && !source.filePath.toLowerCase().endsWith(".wasm")) {
    throw new Error(`galley-wasm: not a WebAssembly module: ${source.filePath}`);
  }
  // findLibrary{,File} throws MissingArtifactError naming the exact place.
  // Only a successful resolution counts as consuming file IO: failed
  // probes must not block a later legitimate seed.
  const wasmPath =
    source.filePath !== undefined ? findLibraryFile(source.filePath) : findLibrary(source.languagePath as string);
  fileIoUsed = true;
  const cached = ports.get(wasmPath);
  if (cached) {
    // Dispatch rides with the port, not the Session: every consumer of
    // the port gets working procedure hooks.
    return cached;
  }
  const bytes = Uint8Array.from(fileIo.readFile(wasmPath));
  return instantiate(bytes, wasmPath, true);
}

// --- helpers ----------------------------------------------------------------

function isNegative(status: bigint): boolean {
  return status < 0n;
}

function toNumber(value: bigint): number {
  return Number(value);
}

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

/** `GalleyWalkCursor` from galley.h: the host-owned walk cursor's size. */
const WALK_CURSOR_BYTES = 40;

/**
 * The wasm `FfiPort`: normalizes the reactor module's i32/i64 boundary
 * into the structured values the core expects. Memory is allocated with
 * the guest's `galley_js_malloc`/`galley_js_free`; every view is fresh
 * because allocation may grow (and detach) memory.
 */
export class WasmPort implements FfiPort {
  readonly wasm: GalleyWasmExports;
  readonly libraryPath: string;
  hookDispatch: DispatchHandler | null = null;

  constructor(wasm: GalleyWasmExports, libraryPath: string) {
    this.wasm = wasm;
    this.libraryPath = libraryPath;
    this.session = this.#family("");
    this.hook = this.#family("hook_");
  }

  #hookNameTable: string[] | null = null;
  /**
   * One 40-byte scratch cursor per port instance: wasm memory never
   * relocates, so a single guest allocation serves every walk step.
   */
  #walkCursorSlot: number | null = null;
  /**
   * The 16 guest bytes every session-door node crossing writes its
   * out-values into, allocated once per port instance. A JS realm is
   * single-threaded and no node crossing re-enters JS, and results are read
   * out before the call returns, so one slot serves every call and nothing
   * is allocated per call.
   */
  #nodeOutSlotPointer: number | null = null;

  #nodeOutSlot(): number {
    if (this.#nodeOutSlotPointer === null) this.#nodeOutSlotPointer = this.malloc(16);
    return this.#nodeOutSlotPointer;
  }

  hookNames(): string[] {
    if (this.#hookNameTable !== null) return this.#hookNameTable;
    const table: string[] = [];
    const total = this.wasm.galley_hooks_count();
    for (let index = 0; index < total; index++) {
      const address = this.wasm.galley_hooks_name_data(index);
      if (address === 0) break;
      table.push(textDecoder.decode(this.readBytes(address, this.wasm.galley_hooks_name_length(index))));
    }
    this.#hookNameTable = table;
    return table;
  }

  // -- memory -------------------------------------------------------------

  private memoryBytes(): Uint8Array<ArrayBuffer> {
    return new Uint8Array(this.wasm.memory.buffer);
  }

  private dataView(): DataView {
    return new DataView(this.wasm.memory.buffer);
  }

  private malloc(len: number): number {
    const ptr = this.wasm.galley_js_malloc(len);
    if (ptr === 0) throw new Error("galley-wasm: out of memory");
    return ptr;
  }

  private free(ptr: number, len: number): void {
    if (len === 0) return;
    this.wasm.galley_js_free(ptr, len);
  }

  /** Copy guest bytes out (owned copy, valid after the next call). */
  private readBytes(ptr: number, len: number): Uint8Array<ArrayBuffer> {
    if (ptr === 0 || len === 0) return new Uint8Array(0);
    return this.memoryBytes().slice(ptr, ptr + len);
  }

  /** Reads a guest u64 the core wrote into an out-parameter. */
  #readU64(ptr: number): bigint {
    return this.dataView().getBigUint64(ptr, true);
  }

  private readCString(ptr: number): string {
    if (ptr === 0) return "";
    const memory = this.memoryBytes();
    let end = ptr;
    while (memory[end] !== 0) end++;
    return textDecoder.decode(memory.subarray(ptr, end));
  }

  /** Copy host bytes in; zero-length inputs still get a non-null slot. */
  private writeBytes(data: Uint8Array): { ptr: number; len: number } {
    const len = data.length;
    const ptr = this.malloc(Math.max(len, 1));
    if (len > 0) this.memoryBytes().set(data, ptr);
    return { ptr, len };
  }

  // -- module-level queries -----------------------------------------------

  version(): string {
    return this.readCString(this.wasm.galley_version());
  }

  parserType(): number {
    return toNumber(this.wasm.galley_parser_type());
  }

  errorRecoveryMode(): number {
    return toNumber(this.wasm.galley_error_recovery_mode());
  }

  hasAst(): boolean {
    return this.wasm.galley_has_ast() !== 0;
  }

  hasProcedures(): boolean {
    return this.wasm.galley_has_procedures() !== 0;
  }

  allowsNoAstTreeProcedures(): boolean {
    return this.wasm.galley_allows_no_ast_tree_procedures() !== 0;
  }

  sourceRetentionEnabled(): boolean {
    return this.wasm.galley_source_retention_enabled() !== 0;
  }

  hasPositionTracking(): boolean {
    return this.wasm.galley_has_position_tracking() !== 0;
  }

  hasInputStreaming(): boolean {
    return this.wasm.galley_has_input_streaming() !== 0;
  }

  usesVerbatim(): boolean {
    return this.wasm.galley_uses_verbatim() !== 0;
  }

  stackOverflowRecoveryAvailable(): boolean {
    return this.wasm.galley_stack_overflow_recovery_available() !== 0;
  }

  symbolCount(): number {
    return toNumber(this.wasm.galley_symbol_count());
  }

  variableCount(): number {
    return toNumber(this.wasm.galley_variable_count());
  }

  statusString(status: number): string | null {
    const ptr = this.wasm.galley_status_string(BigInt(status));
    if (ptr === 0) return null;
    return this.readCString(ptr);
  }

  // -- sessions ------------------------------------------------------------

  createSession(options: SessionCOptions | null): Handle {
    if (options === null) {
      const handle = this.wasm.galley_session_create();
      if (handle === 0) return null;
      return handle;
    }
    // GalleyCOptions layout (wasm32, little-endian): 5x i32/u32, pad, f64, u64.
    const ptr = this.malloc(40);
    try {
      const view = this.dataView();
      view.setInt32(ptr, options.maxErrors, true);
      view.setInt32(ptr + 4, options.recoveryWindow, true);
      view.setInt32(ptr + 8, options.stackOverflowRecovery, true);
      view.setUint32(ptr + 12, options.syntaxErrorStackDepth, true);
      view.setInt32(ptr + 16, options.verbosity, true);
      view.setFloat64(ptr + 24, options.astPreallocationRatio, true);
      view.setBigUint64(ptr + 32, options.astPreallocationCap, true);
      const handle = this.wasm.galley_session_create_ex(ptr);
      if (handle === 0) return null;
      return handle;
    } finally {
      this.free(ptr, 40);
    }
  }

  destroySession(handle: Handle): void {
    this.wasm.galley_session_destroy(handle as number);
  }

  setMessageOverride(handle: Handle, name: Uint8Array, message: Uint8Array): number {
    const nameBytes = textEncoder.encode(textDecoder.decode(name));
    const messageBytes = textEncoder.encode(textDecoder.decode(message));
    const nameSlot = this.writeBytes(nameBytes);
    const messageSlot = this.writeBytes(messageBytes);
    try {
      return toNumber(
        this.wasm.galley_session_set_message_override(
          handle as number,
          nameSlot.ptr,
          nameSlot.len,
          messageSlot.ptr,
          messageSlot.len,
        ),
      );
    } finally {
      this.free(nameSlot.ptr, Math.max(nameSlot.len, 1));
      this.free(messageSlot.ptr, Math.max(messageSlot.len, 1));
    }
  }

  // -- parsing --------------------------------------------------------------

  parse(handle: Handle, data: Uint8Array): number {
    const slot = this.writeBytes(data);
    try {
      return toNumber(this.wasm.galley_parse(handle as number, slot.ptr, slot.len));
    } finally {
      this.free(slot.ptr, Math.max(slot.len, 1));
    }
  }

  parseFile(handle: Handle, filePath: string): number {
    // No guest filesystem: the host reads the file, then parses bytes.
    // Without file IO (browsers) every file read is unavailable.
    if (!fileIo) return -11;
    let data: Uint8Array;
    try {
      data = new Uint8Array(fileIo.readFile(filePath));
    } catch {
      return -11;
    }
    // A successful host read consumes the seed like port resolution does.
    fileIoUsed = true;
    return this.parse(handle, data);
  }

  lastPosition(handle: Handle): [number, number] | number {
    const out = this.malloc(8);
    try {
      const status = this.wasm.galley_last_position(handle as number, out, out + 4);
      if (isNegative(status)) return toNumber(status);
      const view = this.dataView();
      return [view.getUint32(out, true), view.getUint32(out + 4, true)];
    } finally {
      this.free(out, 8);
    }
  }

  lastInput(handle: Handle): Uint8Array | number {
    const out = this.malloc(8);
    try {
      const status = this.wasm.galley_last_input(handle as number, out, out + 4);
      if (isNegative(status)) return toNumber(status);
      const view = this.dataView();
      const ptr = view.getUint32(out, true);
      const len = view.getUint32(out + 4, true);
      return ptr === 0 || len === 0 ? new Uint8Array(0) : this.readBytes(ptr, len);
    } finally {
      this.free(out, 8);
    }
  }

  // -- arena and navigation ---------------------------------------------------

  /** The generation as the BigInt wasm's `i64` parameter requires. */
  readonly #generation = new GenerationBigInt();

  nodeCount(handle: Handle, generation: number): number {
    return Number(this.wasm.galley_node_count(handle as number, this.#generation.of(generation)));
  }

  reserveNodes(handle: Handle, capacity: bigint): number {
    return toNumber(this.wasm.galley_reserve_nodes(handle as number, capacity));
  }

  nodeCapacity(handle: Handle): number {
    return toNumber(this.wasm.galley_node_capacity(handle as number));
  }

  rootNode(handle: Handle): { status: number; root: bigint; generation: number } {
    const out = this.#nodeOutSlot();
    const status = this.wasm.galley_root_node(handle as number, out, out + 8);
    return {
      status: Number(status),
      root: this.#readU64(out),
      generation: Number(this.#readU64(out + 8)),
    };
  }

  treeSnapshot(handle: Handle, generation: number): SnapshotColumns | number {
    for (let attempt = 0; attempt < 2; attempt++) {
      const count = this.nodeCount(handle, generation);
      if (count < 0) return count;
      if (count === 0) {
        // A zero count (a build with no AST construction) still crosses
        // with null columns so the gate can answer.
        const status = toNumber(
          this.wasm.galley_tree_snapshot(handle as number, this.#generation.of(generation), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0n),
        );
        if (status < 0) return status;
        return {
          count,
          parent: new BigUint64Array(0),
          firstChild: new BigUint64Array(0),
          next: new BigUint64Array(0),
          childCount: new Uint32Array(0),
          variable: new BigInt64Array(0),
          spanStart: new BigUint64Array(0),
          spanLen: new BigUint64Array(0),
          isSemanticError: new Int32Array(0),
          isRecovered: new Int32Array(0),
        };
      }
      // Eight-byte columns first (parent, firstChild, next, spanStart,
      // spanLen, variable), then the u32 childCount tail and the i32
      // semantic-error and recovered flag tails: every column stays
      // naturally aligned for bulk typed-array copies.
      const stride = count * 8;
      const offParent = 0;
      const offFirst = stride;
      const offNext = stride * 2;
      const offSpanStart = stride * 3;
      const offSpanLen = stride * 4;
      const offVariable = stride * 5;
      const offChildCount = stride * 6;
      const offSemantic = offChildCount + count * 4;
      const offRecovered = offSemantic + count * 4;
      const total = offRecovered + count * 4;
      const base = this.malloc(total);
      try {
        const status = this.wasm.galley_tree_snapshot(
          handle as number, this.#generation.of(generation), base + offParent, base + offFirst, base + offNext,
          base + offChildCount, base + offVariable, base + offSpanStart,
          base + offSpanLen, base + offSemantic, base + offRecovered, BigInt(count),
        );
        if (isNegative(status)) return Number(status);
        if (status !== BigInt(count)) continue;
        const memory = this.memoryBytes();
        const column64 = (offset: number) =>
          new BigUint64Array(memory.buffer, memory.byteOffset + base + offset, count);
        const parent = new BigUint64Array(count);
        parent.set(column64(offParent));
        const firstChild = new BigUint64Array(count);
        firstChild.set(column64(offFirst));
        const next = new BigUint64Array(count);
        next.set(column64(offNext));
        const spanStart = new BigUint64Array(count);
        spanStart.set(column64(offSpanStart));
        const spanLen = new BigUint64Array(count);
        spanLen.set(column64(offSpanLen));
        const variable = new BigInt64Array(count);
        variable.set(new BigInt64Array(memory.buffer, memory.byteOffset + base + offVariable, count));
        const childCount = new Uint32Array(count);
        childCount.set(new Uint32Array(memory.buffer, memory.byteOffset + base + offChildCount, count));
        const isSemanticError = new Int32Array(count);
        isSemanticError.set(new Int32Array(memory.buffer, memory.byteOffset + base + offSemantic, count));
        const isRecovered = new Int32Array(count);
        isRecovered.set(new Int32Array(memory.buffer, memory.byteOffset + base + offRecovered, count));
        return { count, parent, firstChild, next, childCount, variable, spanStart, spanLen, isSemanticError, isRecovered };
      } finally {
        this.free(base, total);
      }
    }
    throw new GalleyError("node count changed during galley_tree_snapshot", Status.ErrorInternal);
  }

  // -- walking ---------------------------------------------------------------

  /** The wasm guest is little-endian regardless of the host platform. */
  readonly walkCursorLittleEndian = true;

  #walkCursor(): number {
    if (this.#walkCursorSlot === null) this.#walkCursorSlot = this.malloc(WALK_CURSOR_BYTES);
    return this.#walkCursorSlot;
  }

  #copyCursorToGuest(slot: number, cursor: ArrayBuffer): void {
    const memory = this.memoryBytes();
    memory.set(new Uint8Array(cursor, 0, WALK_CURSOR_BYTES), slot);
  }

  #copyCursorFromGuest(slot: number, cursor: ArrayBuffer): void {
    // The call may have grown memory: re-read the buffer, never a stale view.
    const memory = this.memoryBytes();
    new Uint8Array(cursor, 0, WALK_CURSOR_BYTES).set(memory.subarray(slot, slot + WALK_CURSOR_BYTES));
  }

  // -- node accessors ------------------------------------------------------------

  /** Read a guest `(data, len)` byte pair; null on negative status. */
  private tryCopyBytes(
    call: (outData: number, outLen: number) => bigint,
  ): Uint8Array | null {
    const out = this.malloc(8);
    try {
      const status = call(out, out + 4);
      if (isNegative(status)) return null;
      const view = this.dataView();
      const ptr = view.getUint32(out, true);
      const len = view.getUint32(out + 4, true);
      if (ptr === 0) return null;
      return this.readBytes(ptr, len);
    } finally {
      this.free(out, 8);
    }
  }

  private readSemanticPair(
    call: (
      outVariable: number,
      outVariableLen: number,
      outMessage: number,
      outMessageLen: number,
    ) => bigint,
  ): [string, string] | null {
    const out = this.malloc(16);
    try {
      const status = call(out, out + 4, out + 8, out + 12);
      if (isNegative(status)) return null;
      const view = this.dataView();
      const variablePtr = view.getUint32(out, true);
      const variableLen = view.getUint32(out + 4, true);
      const messagePtr = view.getUint32(out + 8, true);
      const messageLen = view.getUint32(out + 12, true);
      if (variablePtr === 0 || messagePtr === 0) return null;
      return [
        textDecoder.decode(this.readBytes(variablePtr, variableLen)),
        textDecoder.decode(this.readBytes(messagePtr, messageLen)),
      ];
    } finally {
      this.free(out, 16);
    }
  }

  symbolNameAt(handle: Handle, index: number): Uint8Array | null {
    const session = handle as number;
    return this.tryCopyBytes((data, len) => this.wasm.galley_symbol_name(session, BigInt(index), data, len));
  }

  symbolIsTerminal(handle: Handle, index: number): boolean {
    return this.wasm.galley_symbol_is_terminal(handle as number, BigInt(index)) !== 0;
  }

  variableNameAt(handle: Handle, index: number): Uint8Array | null {
    const session = handle as number;
    return this.tryCopyBytes((data, len) => this.wasm.galley_variable_name(session, BigInt(index), data, len));
  }

  // -- diagnostics ------------------------------------------------------------------

  hasDiagnostic(handle: Handle): boolean {
    return this.wasm.galley_has_diagnostic(handle as number) !== 0;
  }

  diagnosticKind(handle: Handle): number {
    return toNumber(this.wasm.galley_diagnostic_kind(handle as number));
  }

  diagnosticMessage(handle: Handle): string | null {
    const out = this.malloc(4);
    try {
      if (this.wasm.galley_diagnostic_message(handle as number, out) !== 0n) return null;
      return this.readCString(this.dataView().getUint32(out, true));
    } finally {
      this.free(out, 4);
    }
  }

  diagnosticMessageAnsi(handle: Handle): string | null {
    const out = this.malloc(4);
    try {
      if (this.wasm.galley_diagnostic_message_ansi(handle as number, out) !== 0n) return null;
      return this.readCString(this.dataView().getUint32(out, true));
    } finally {
      this.free(out, 4);
    }
  }

  diagnosticPosition(handle: Handle): [number, number] | null {
    const out = this.malloc(8);
    try {
      if (isNegative(this.wasm.galley_diagnostic_position(handle as number, out, out + 4)))
        return null;
      const view = this.dataView();
      return [view.getUint32(out, true), view.getUint32(out + 4, true)];
    } finally {
      this.free(out, 8);
    }
  }

  diagnosticUnexpectedToken(handle: Handle): Uint8Array | null {
    const session = handle as number;
    return this.tryCopyBytes((data, len) => this.wasm.galley_diagnostic_unexpected_token(session, data, len));
  }

  diagnosticExpectedCount(handle: Handle): number {
    return toNumber(this.wasm.galley_diagnostic_expected_count(handle as number));
  }

  diagnosticExpectedAt(handle: Handle, index: number): Uint8Array | null {
    const session = handle as number;
    return this.tryCopyBytes((data, len) =>
      this.wasm.galley_diagnostic_expected_at(session, BigInt(index), data, len),
    );
  }

  diagnosticContextCount(handle: Handle): number {
    return toNumber(this.wasm.galley_diagnostic_context_count(handle as number));
  }

  diagnosticContextAt(handle: Handle, index: number): Uint8Array | null {
    const session = handle as number;
    return this.tryCopyBytes((data, len) =>
      this.wasm.galley_diagnostic_context_at(session, BigInt(index), data, len),
    );
  }

  syntaxErrorCount(handle: Handle): number {
    return toNumber(this.wasm.galley_syntax_error_count(handle as number));
  }

  semanticErrorCount(handle: Handle): number {
    return toNumber(this.wasm.galley_semantic_error_count(handle as number));
  }

  diagnosticSemantic(handle: Handle): [string, string] | null {
    const session = handle as number;
    return this.readSemanticPair((variable, variableLen, message, messageLen) =>
      this.wasm.galley_diagnostic_semantic(session, variable, variableLen, message, messageLen),
    );
  }

  diagnosticIndentation(handle: Handle): [number, number] | null {
    const out = this.malloc(8);
    try {
      if (toNumber(this.wasm.galley_diagnostic_indentation(handle as number, out, out + 4)) !== 0)
        return null;
      const view = this.dataView();
      return [view.getUint32(out, true), view.getUint32(out + 4, true)];
    } finally {
      this.free(out, 8);
    }
  }

  diagnosticRecoveryKind(handle: Handle): number {
    return toNumber(this.wasm.galley_diagnostic_recovery_kind(handle as number));
  }

  diagnosticRecoveryTerminal(handle: Handle): Uint8Array | null {
    const session = handle as number;
    return this.tryCopyBytes((data, len) =>
      this.wasm.galley_diagnostic_recovery_terminal(session, data, len),
    );
  }

  diagnosticRecoveryResume(handle: Handle): number | null {
    const out = this.malloc(8);
    try {
      if (toNumber(this.wasm.galley_diagnostic_recovery_resume(handle as number, out)) !== 0)
        return null;
      return toNumber(this.dataView().getBigInt64(out, true));
    } finally {
      this.free(out, 8);
    }
  }

  diagnosticRecoveryLhsVariable(handle: Handle): string | null {
    const session = handle as number;
    const out = this.malloc(8);
    try {
      const status = this.wasm.galley_diagnostic_recovery_lhs_variable(session, out, out + 4);
      if (isNegative(status)) return null;
      const view = this.dataView();
      const ptr = view.getUint32(out, true);
      if (ptr === 0) return null;
      return textDecoder.decode(this.readBytes(ptr, view.getUint32(out + 4, true)));
    } finally {
      this.free(out, 8);
    }
  }

  diagnosticRecoveryProduction(handle: Handle): [string, number] | null {
    const out = this.malloc(12);
    try {
      if (
        toNumber(this.wasm.galley_diagnostic_recovery_production(handle as number, out, out + 4, out + 8)) !==
        0
      )
        return null;
      const view = this.dataView();
      return [
        textDecoder.decode(this.readBytes(view.getUint32(out, true), view.getUint32(out + 4, true))),
        view.getUint32(out + 8, true),
      ];
    } finally {
      this.free(out, 12);
    }
  }

  diagnosticRecoveryOccurrence(handle: Handle): [string, number, number, string] | null {
    const out = this.malloc(24);
    try {
      if (
        toNumber(
          this.wasm.galley_diagnostic_recovery_occurrence(
            handle as number,
            out,
            out + 4,
            out + 8,
            out + 12,
            out + 16,
            out + 20,
          ),
        ) !== 0
      )
        return null;
      const view = this.dataView();
      return [
        textDecoder.decode(this.readBytes(view.getUint32(out, true), view.getUint32(out + 4, true))),
        view.getUint32(out + 8, true),
        view.getUint32(out + 12, true),
        textDecoder.decode(this.readBytes(view.getUint32(out + 16, true), view.getUint32(out + 20, true))),
      ];
    } finally {
      this.free(out, 24);
    }
  }

  recordedDiagnosticCount(handle: Handle): number {
    return toNumber(this.wasm.galley_recorded_diagnostic_count(handle as number));
  }

  recordedDiagnosticKind(handle: Handle, diagIndex: number): number {
    return toNumber(this.wasm.galley_recorded_diagnostic_kind(handle as number, BigInt(diagIndex)));
  }

  recordedDiagnosticPosition(handle: Handle, diagIndex: number): [number, number] | null {
    const out = this.malloc(8);
    try {
      if (
        isNegative(this.wasm.galley_recorded_diagnostic_position(handle as number, BigInt(diagIndex), out, out + 4))
      )
        return null;
      const view = this.dataView();
      return [view.getUint32(out, true), view.getUint32(out + 4, true)];
    } finally {
      this.free(out, 8);
    }
  }

  recordedUnexpectedToken(handle: Handle, diagIndex: number): Uint8Array | null {
    const session = handle as number;
    return this.tryCopyBytes((data, len) =>
      this.wasm.galley_recorded_unexpected_token(session, BigInt(diagIndex), data, len),
    );
  }

  recordedDiagnosticMessage(handle: Handle, diagIndex: number): string | null {
    const out = this.malloc(4);
    try {
      if (toNumber(this.wasm.galley_recorded_diagnostic_message(handle as number, BigInt(diagIndex), out)) !== 0)
        return null;
      return this.readCString(this.dataView().getUint32(out, true));
    } finally {
      this.free(out, 4);
    }
  }

  recordedIndentation(handle: Handle, diagIndex: number): [number, number] | null {
    const out = this.malloc(8);
    try {
      if (
        toNumber(this.wasm.galley_recorded_indentation(handle as number, BigInt(diagIndex), out, out + 4)) !== 0
      )
        return null;
      const view = this.dataView();
      return [view.getUint32(out, true), view.getUint32(out + 4, true)];
    } finally {
      this.free(out, 8);
    }
  }

  recordedSemantic(handle: Handle, diagIndex: number): [string, string] | null {
    const session = handle as number;
    return this.readSemanticPair((variable, variableLen, message, messageLen) =>
      this.wasm.galley_recorded_semantic(session, BigInt(diagIndex), variable, variableLen, message, messageLen),
    );
  }

  recordedExpectedCount(handle: Handle, diagIndex: number): number {
    return toNumber(this.wasm.galley_recorded_expected_count(handle as number, BigInt(diagIndex)));
  }

  recordedExpectedToken(handle: Handle, diagIndex: number, tokenIndex: number): Uint8Array | null {
    const session = handle as number;
    return this.tryCopyBytes((data, len) =>
      this.wasm.galley_recorded_expected_token(session, BigInt(diagIndex), BigInt(tokenIndex), data, len),
    );
  }

  recordedContextCount(handle: Handle, diagIndex: number): number {
    return toNumber(this.wasm.galley_recorded_context_count(handle as number, BigInt(diagIndex)));
  }

  recordedContextName(handle: Handle, diagIndex: number, contextIndex: number): Uint8Array | null {
    const session = handle as number;
    return this.tryCopyBytes((data, len) =>
      this.wasm.galley_recorded_context_name(session, BigInt(diagIndex), BigInt(contextIndex), data, len),
    );
  }

  recordedRecoveryKind(handle: Handle, diagIndex: number): number {
    return toNumber(this.wasm.galley_recorded_diagnostic_recovery_kind(handle as number, BigInt(diagIndex)));
  }

  recordedRecoveryTerminal(handle: Handle, diagIndex: number): Uint8Array | null {
    const session = handle as number;
    return this.tryCopyBytes((data, len) =>
      this.wasm.galley_recorded_recovery_terminal(session, BigInt(diagIndex), data, len),
    );
  }

  recordedRecoveryResume(handle: Handle, diagIndex: number): number | null {
    const out = this.malloc(8);
    try {
      if (toNumber(this.wasm.galley_recorded_recovery_resume(handle as number, BigInt(diagIndex), out)) !== 0)
        return null;
      return toNumber(this.dataView().getBigInt64(out, true));
    } finally {
      this.free(out, 8);
    }
  }

  recordedRecoveryLhsVariable(handle: Handle, diagIndex: number): string | null {
    const session = handle as number;
    const out = this.malloc(8);
    try {
      const status = this.wasm.galley_recorded_recovery_lhs_variable(session, BigInt(diagIndex), out, out + 4);
      if (isNegative(status)) return null;
      const view = this.dataView();
      const ptr = view.getUint32(out, true);
      if (ptr === 0) return null;
      return textDecoder.decode(this.readBytes(ptr, view.getUint32(out + 4, true)));
    } finally {
      this.free(out, 8);
    }
  }

  recordedRecoveryProduction(handle: Handle, diagIndex: number): [string, number] | null {
    const out = this.malloc(12);
    try {
      if (
        toNumber(
          this.wasm.galley_recorded_recovery_production(handle as number, BigInt(diagIndex), out, out + 4, out + 8),
        ) !== 0
      )
        return null;
      const view = this.dataView();
      return [
        textDecoder.decode(this.readBytes(view.getUint32(out, true), view.getUint32(out + 4, true))),
        view.getUint32(out + 8, true),
      ];
    } finally {
      this.free(out, 12);
    }
  }

  recordedRecoveryOccurrence(
    handle: Handle,
    diagIndex: number,
  ): [string, number, number, string] | null {
    const out = this.malloc(24);
    try {
      if (
        toNumber(
          this.wasm.galley_recorded_recovery_occurrence(
            handle as number,
            BigInt(diagIndex),
            out,
            out + 4,
            out + 8,
            out + 12,
            out + 16,
            out + 20,
          ),
        ) !== 0
      )
        return null;
      const view = this.dataView();
      return [
        textDecoder.decode(this.readBytes(view.getUint32(out, true), view.getUint32(out + 4, true))),
        view.getUint32(out + 8, true),
        view.getUint32(out + 12, true),
        textDecoder.decode(this.readBytes(view.getUint32(out + 16, true), view.getUint32(out + 20, true))),
      ];
    } finally {
      this.free(out, 24);
    }
  }

  // -- node and tree calls, both doors ---------------------------------------------

  readonly session: NodeFamily;
  readonly hook: NodeFamily;

  /**
   * One door's node and tree calls, bound from the guest's twin exports:
   * `galley_<name>` for the session door, `galley_hook_<name>` for the hook
   * door. Each capability is written here once and used for both. A refusal
   * is a negative status, which the core's door turns into the host's
   * failure.
   */
  #family(door: "" | "hook_"): NodeFamily {
    const calls = this.wasm as unknown as Record<string, unknown>;
    const bound = <Name extends keyof DoorCalls>(name: Name): DoorCalls[Name] =>
      calls[`galley_${door}${name}`] as DoorCalls[Name];
    const generations = this.#generation;
    const childCount = bound("node_child_count");
    const firstChild = bound("node_first_child");
    const lastChild = bound("node_last_child");
    const nextSibling = bound("node_next_sibling");
    const priorSibling = bound("node_prior_sibling");
    const parent = bound("node_parent");
    const symbolName = bound("node_symbol_name");
    const text = bound("node_text");
    const span = bound("node_span");
    const lineColumn = bound("node_line_column");
    const variableIndex = bound("node_variable_index");
    const walkNext = bound("walk_next");
    const appendChildren = bound("tree_append_children");
    const insertBefore = bound("tree_insert_before");
    const insertAfter = bound("tree_insert_after");
    const removeSiblings = bound("tree_remove_siblings");
    const removeSelf = bound("tree_remove_self");
    const cleanChildren = bound("tree_clean_children");
    const insertChildrenAt = bound("tree_insert_children_at");
    const removeChildrenAt = bound("tree_remove_children_at");
    const head = (call: (out: number) => bigint): { status: number; head: bigint } => {
      const out = this.#nodeOutSlot();
      const status = toNumber(call(out));
      return { status, head: this.dataView().getBigUint64(out, true) };
    };
    return {
      childCount: (handle, generation, node) =>
        Number(childCount(handle as number, generations.of(generation), node)),
      firstChild: (handle, generation, node) =>
        firstChild(handle as number, generations.of(generation), node),
      lastChild: (handle, generation, node) =>
        lastChild(handle as number, generations.of(generation), node),
      nextSibling: (handle, generation, node) =>
        nextSibling(handle as number, generations.of(generation), node),
      priorSibling: (handle, generation, node) =>
        priorSibling(handle as number, generations.of(generation), node),
      parent: (handle, generation, node) =>
        parent(handle as number, generations.of(generation), node),
      nodeSymbolName: (handle, generation, node) => {
        const out = this.#nodeOutSlot();
        const status = symbolName(handle as number, generations.of(generation), node, out, out + 4);
        if (isNegative(status)) return Number(status);
        const view = this.dataView();
        return this.readBytes(view.getUint32(out, true), view.getUint32(out + 4, true));
      },
      nodeText: (handle, generation, node) => {
        const out = this.#nodeOutSlot();
        const status = text(handle as number, generations.of(generation), node, out, out + 4);
        if (isNegative(status)) return Number(status);
        const view = this.dataView();
        return this.readBytes(view.getUint32(out, true), view.getUint32(out + 4, true));
      },
      nodeSpan: (handle, generation, node) => {
        const out = this.#nodeOutSlot();
        const status = span(handle as number, generations.of(generation), node, out, out + 8);
        if (isNegative(status)) return Number(status);
        const view = this.dataView();
        return [view.getBigUint64(out, true), view.getBigUint64(out + 8, true)];
      },
      nodeLineColumn: (handle, generation, node) => {
        const out = this.#nodeOutSlot();
        const status = lineColumn(handle as number, generations.of(generation), node, out, out + 4);
        if (isNegative(status)) return Number(status);
        const view = this.dataView();
        return [view.getUint32(out, true), view.getUint32(out + 4, true)];
      },
      nodeVariableIndex: (handle, generation, node) => {
        const index = variableIndex(handle as number, generations.of(generation), node);
        return index === NO_VARIABLE ? null : Number(index);
      },
      walkNext: (handle, cursor) => {
        const slot = this.#walkCursor();
        this.#copyCursorToGuest(slot, cursor);
        const status = walkNext(handle as number, slot);
        this.#copyCursorFromGuest(slot, cursor);
        return Number(status);
      },
      treeAppendChildren: (handle, generation, parentNode, firstGeneration, first) =>
        toNumber(appendChildren(handle as number, generations.of(generation), parentNode, BigInt(firstGeneration), first)),
      treeInsertBefore: (handle, generation, target, firstGeneration, first) =>
        toNumber(insertBefore(handle as number, generations.of(generation), target, BigInt(firstGeneration), first)),
      treeInsertAfter: (handle, generation, target, firstGeneration, first) =>
        toNumber(insertAfter(handle as number, generations.of(generation), target, BigInt(firstGeneration), first)),
      treeRemoveSiblings: (handle, generation, node, count) =>
        head((out) => removeSiblings(handle as number, generations.of(generation), node, count, out)),
      treeRemoveSelf: (handle, generation, node) =>
        head((out) => removeSelf(handle as number, generations.of(generation), node, out)),
      treeCleanChildren: (handle, generation, node) =>
        head((out) => cleanChildren(handle as number, generations.of(generation), node, out)),
      treeInsertChildrenAt: (handle, generation, parentNode, index, firstGeneration, first) =>
        toNumber(insertChildrenAt(handle as number, generations.of(generation), parentNode, index, BigInt(firstGeneration), first)),
      treeRemoveChildrenAt: (handle, generation, parentNode, index, count) =>
        head((out) => removeChildrenAt(handle as number, generations.of(generation), parentNode, index, count, out)),
    };
  }

  // -- procedure hooks (parse-time state) ---------------------------------------------------

  procCurrentNode(session: Handle, hook: HookTicket): bigint | number {
    const node = this.wasm.galley_procedure_current_node(session as number, hook);
    return isNegative(node) ? toNumber(node) : node;
  }

  procDoor(session: Handle, hook: HookTicket): { status: number; door: Handle } {
    const out = this.malloc(8);
    try {
      const status = toNumber(this.wasm.galley_procedure_door(session as number, hook, out));
      return { status, door: status < 0 ? null : this.dataView().getUint32(out, true) };
    } finally {
      this.free(out, 8);
    }
  }

  procSetCurrentNode(session: Handle, hook: HookTicket, generation: number, node: bigint): number {
    return Number(this.wasm.galley_procedure_set_current_node(session as number, hook, this.#generation.of(generation), node));
  }

  procDropSelf(session: Handle, hook: HookTicket): number {
    return toNumber(this.wasm.galley_procedure_drop_self(session as number, hook));
  }

  procDropChildren(session: Handle, hook: HookTicket): number {
    return toNumber(this.wasm.galley_procedure_drop_children(session as number, hook));
  }

  procDropIfEmpty(session: Handle, hook: HookTicket): number {
    return toNumber(this.wasm.galley_procedure_drop_if_empty(session as number, hook));
  }

  procReplaceWithChildren(session: Handle, hook: HookTicket): number {
    return toNumber(this.wasm.galley_procedure_replace_with_children(session as number, hook));
  }

  procContextLine(session: Handle, hook: HookTicket): number {
    return toNumber(this.wasm.galley_procedure_context_line(session as number, hook));
  }

  procContextColumn(session: Handle, hook: HookTicket): number {
    return toNumber(this.wasm.galley_procedure_context_column(session as number, hook));
  }

  procReportSemanticError(session: Handle, hook: HookTicket, message: Uint8Array): number {
    const bytes = textEncoder.encode(textDecoder.decode(message));
    const slot = this.writeBytes(bytes);
    try {
      return toNumber(
        this.wasm.galley_procedure_report_semantic_error(session as number, hook, slot.ptr, slot.len),
      );
    } finally {
      this.free(slot.ptr, Math.max(slot.len, 1));
    }
  }

  hookGeneration(door: Handle): number {
    const out = this.malloc(8);
    try {
      const status = this.wasm.galley_hook_generation(door as number, out);
      return isNegative(status) ? Number(status) : Number(this.dataView().getBigUint64(out, true));
    } finally {
      this.free(out, 8);
    }
  }

  setSessionHooks(session: Handle, hookHandle: number, enabled: Uint8Array): number {
    // A wasm function pointer is a table index the host cannot mint, so the
    // dispatch argument is null and hooks arrive through the
    // `env.galley_host_dispatch` import.
    const slot = this.writeBytes(enabled);
    try {
      return toNumber(this.wasm.galley_session_set_hooks(session as number, 0, hookHandle, slot.ptr, enabled.length));
    } finally {
      this.free(slot.ptr, Math.max(slot.len, 1));
    }
  }
}
