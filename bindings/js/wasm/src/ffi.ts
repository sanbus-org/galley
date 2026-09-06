/**
 * WebAssembly adapter for the Galley JavaScript bindings: a `WasmPort`
 * implementing the core `FfiPort` over a WASI reactor module built from
 * `bindings/c/galley.h` (`zig build -Dwasm`, see `build.mjs`).
 *
 * Zero npm dependencies. The module is instantiated with a minimal
 * in-TS `wasi_snapshot_preview1` stub (real `random_get`/`clock_time_get`,
 * filesystem calls report unavailable — the parse path never touches the
 * filesystem) plus an `env.galley_js_dispatch` import that forwards
 * procedure hooks to the core registry. All memory copying and integer
 * normalization live here; all session logic lives in `galley-js-core`.
 *
 * Initialization is async (`await init()`), except under Node where the
 * file can be read and instantiated synchronously — `Session` and the
 * module-level queries auto-initialize there, so Node demos stay
 * synchronous. Elsewhere (browsers) the gate throws `NeedInitError` until
 * `await init()` completes. Views into wasm memory are never cached:
 * `malloc` may grow memory and detach old views.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import process from "node:process";
import type {
  FfiPort,
  Handle,
  SessionCOptions,
  WalkedStep,
} from "galley-js-core";
import { dispatchProcedure, MissingArtifactError } from "galley-js-core";

const LIBRARY_BASE = "galley-js-wasm";
const WASI_NOSYS = 52;
const WASI_BADF = 8;

export class NeedInitError extends Error {
  constructor(libraryPath?: string) {
    super(
      `galley-js-wasm: WebAssembly module${libraryPath ? ` for ${libraryPath}` : ""} is not initialized. ` +
        `Call "await init()" (or "await init({ url })" / "init({ bytes })" in browsers) first.`,
    );
    this.name = "NeedInitError";
  }
}

/** Callable view of the wasm exports (wasm32: pointers/i32 are `number`, i64/u64 are `bigint`). */
interface GalleyWasmExports {
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
  galley_node_count(session: number): bigint;
  galley_reserve_nodes(session: number, capacity: bigint): bigint;
  galley_node_capacity(session: number): bigint;
  galley_root_node(session: number): bigint;
  galley_node_is_valid(session: number, node: bigint): number;
  galley_node_child_count(session: number, node: bigint): number;
  galley_node_first_child(session: number, node: bigint): bigint;
  galley_node_last_child(session: number, node: bigint): bigint;
  galley_node_next_sibling(session: number, node: bigint): bigint;
  galley_node_prior_sibling(session: number, node: bigint): bigint;
  galley_node_parent(session: number, node: bigint): bigint;
  galley_walker_create(session: number, node: bigint, skipSemanticErrors: number): number;
  galley_walker_next(walker: number, outNode: number, outDepth: number, outFlag: number): number;
  galley_walker_skip_children(walker: number): void;
  galley_walker_destroy(walker: number): void;
  galley_node_symbol_name(session: number, node: bigint, outData: number, outLen: number): bigint;
  galley_node_text(session: number, node: bigint, outData: number, outLen: number): bigint;
  galley_node_span(session: number, node: bigint, outStart: number, outLen: number): bigint;
  galley_node_line_column(session: number, node: bigint, outLine: number, outCol: number): bigint;
  galley_node_variable_index(session: number, node: bigint): bigint;
  galley_last_position(session: number, outLine: number, outCol: number): bigint;
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
  galley_tree_append_children(session: number, parent: bigint, first: bigint): bigint;
  galley_tree_insert_before(session: number, target: bigint, first: bigint): bigint;
  galley_tree_insert_after(session: number, target: bigint, first: bigint): bigint;
  galley_tree_remove_siblings(session: number, node: bigint, count: number, outHead: number): bigint;
  galley_tree_remove_self(session: number, node: bigint, outHead: number): bigint;
  galley_tree_promote_children_over_wrapper(session: number, wrapper: bigint, outHead: number): bigint;
  galley_tree_clean_children(session: number, node: bigint, outHead: number): bigint;
  galley_tree_unlink_wrapper(session: number, wrapper: bigint): bigint;
  galley_tree_insert_children_at(session: number, parent: bigint, index: number, first: bigint): bigint;
  galley_tree_remove_children_at(
    session: number,
    parent: bigint,
    index: number,
    count: number,
    outHead: number,
  ): bigint;
  galley_procedure_current_node(args: number): bigint;
  galley_procedure_set_current_node(args: number, node: bigint): void;
  galley_procedure_drop_self(args: number): bigint;
  galley_procedure_drop_children(args: number): bigint;
  galley_procedure_drop_if_empty(args: number): bigint;
  galley_procedure_replace_with_children(args: number): bigint;
  galley_procedure_context_line(args: number): number;
  galley_procedure_context_column(args: number): number;
  galley_procedure_report_semantic_error(args: number, message: number, messageLen: number): bigint;
}

// --- instance cache (one module per grammar file) --------------------------

const ports = new Map<string, WasmPort>();
let seededDefault: string | null = null;

function isNode(): boolean {
  return (
    typeof process !== "undefined" &&
    typeof (process as unknown as { versions?: { node?: string } }).versions?.node === "string"
  );
}

// --- library discovery (mirrors the Node adapter, `.wasm` names) -----------
// One place, named up front: an explicit path or GALLEY_LIBRARY_PATH.
// Anything else is a loud error, never a search.

const BUILD_HINT =
  `Build it first: npx galley-js-wasm <language-dir>\n` +
  `or set GALLEY_LIBRARY_PATH=/path/to/${wasmFileName()}`;

export function wasmFileName(base = LIBRARY_BASE): string {
  return `lib${base}.wasm`;
}

function exists(localPath: string): boolean {
  try {
    fs.accessSync(localPath);
    return true;
  } catch {
    return false;
  }
}

export function findLibrary(explicit?: string): string {
  const chosen = explicit || process.env.GALLEY_LIBRARY_PATH;
  if (!chosen) {
    throw new MissingArtifactError(
      "no parser artifact given; pass libraryPath or set GALLEY_LIBRARY_PATH",
      BUILD_HINT,
    );
  }
  const resolved = path.resolve(chosen);
  if (!exists(resolved)) {
    throw new MissingArtifactError(`at ${resolved}`, BUILD_HINT);
  }
  return resolved;
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
          if (isNode()) {
            (fd === 1 ? process.stdout : process.stderr).write(text);
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
      throw new Error(`galley-js-wasm: guest called proc_exit(${code})`);
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

export interface InitOptions {
  /** Grammar module path. Defaults to discovery (`findLibrary()` under Node). */
  libraryPath?: string;
  /** Raw module bytes (browsers, tests). Wins over `libraryPath`/`url`. */
  bytes?: Uint8Array;
  /** Module URL for `fetch` (browsers). Wins over `libraryPath`. */
  url?: string | URL;
}

interface PendingInstance {
  port: WasmPort | null;
  memory: ArrayBuffer | null;
}

function makeImports(pending: PendingInstance): WebAssembly.Imports {
  return {
    wasi_snapshot_preview1: makeWasiStub(() => {
      if (pending.memory === null) throw new Error("galley-js-wasm: memory unavailable");
      return pending.memory;
    }),
    env: {
      galley_js_dispatch: (namePtr: number, nameLen: number, argsPtr: number) => {
        const port = pending.port;
        if (port === null) return;
        port.dispatchFromGuest(namePtr, nameLen, argsPtr);
      },
    },
  };
}

function adoptInstance(
  instance: WebAssembly.Instance,
  wasmPath: string,
  pending: PendingInstance,
): WasmPort {
  pending.memory = (instance.exports.memory as WebAssembly.Memory).buffer;
  if (typeof instance.exports._initialize === "function") {
    (instance.exports._initialize as () => void)();
  }
  const port = new WasmPort(instance.exports as unknown as GalleyWasmExports, wasmPath);
  pending.port = port;
  ports.set(wasmPath, port);
  return port;
}

function instantiate(bytes: Uint8Array<ArrayBuffer>, wasmPath: string): WasmPort {
  const pending: PendingInstance = { port: null, memory: null };
  const instance = new WebAssembly.Instance(new WebAssembly.Module(bytes), makeImports(pending));
  return adoptInstance(instance, wasmPath, pending);
}

function loadBytesSync(options: InitOptions): { bytes: Uint8Array<ArrayBuffer>; wasmPath: string } {
  if (options.bytes) {
    return {
      bytes: Uint8Array.from(options.bytes),
      wasmPath: options.libraryPath ?? seededDefault ?? "<bytes>",
    };
  }
  if (options.url !== undefined) {
    throw new NeedInitError(options.libraryPath);
  }
  if (!isNode()) throw new NeedInitError(options.libraryPath);
  // findLibrary throws MissingArtifactError naming the exact place.
  const wasmPath = options.libraryPath ?? seededDefault ?? findLibrary();
  return { bytes: Uint8Array.from(new Uint8Array(fs.readFileSync(wasmPath))), wasmPath };
}

/** Async entry point; the only way to initialize in browsers. */
export async function init(options: InitOptions = {}): Promise<void> {
  if (options.bytes) {
    const wasmPath = options.libraryPath ?? seededDefault ?? "<bytes>";
    instantiate(Uint8Array.from(options.bytes), wasmPath);
    if (options.libraryPath === undefined) seededDefault = wasmPath;
    return;
  }
  if (options.url !== undefined) {
    const response = await fetch(options.url);
    if (!response.ok) throw new Error(`galley-js-wasm: failed to fetch ${options.url}: ${response.status}`);
    const wasmPath = options.libraryPath ?? seededDefault ?? String(options.url);
    instantiate(new Uint8Array(await response.arrayBuffer()), wasmPath);
    if (options.libraryPath === undefined) seededDefault = wasmPath;
    return;
  }
  if (!isNode()) throw new NeedInitError(options.libraryPath);
  const { bytes, wasmPath } = loadBytesSync(options);
  // Asynchronous compile for streaming-friendly startup; semantics match initSync.
  const pending: PendingInstance = { port: null, memory: null };
  const instance = await WebAssembly.instantiate(
    await WebAssembly.compile(bytes),
    makeImports(pending),
  );
  adoptInstance(instance, wasmPath, pending);
}

/** Synchronous entry point; Node only (file read + `WebAssembly.Module`). */
export function initSync(options: InitOptions = {}): void {
  const { bytes, wasmPath } = loadBytesSync(options);
  instantiate(bytes, wasmPath);
  if (options.libraryPath === undefined) seededDefault = wasmPath;
}

/** Seed the default cache key (used by `init({ bytes })` without a path). */
export function seedDefault(wasmPath: string): void {
  seededDefault = wasmPath;
}

function resolveKey(explicit?: string): string {
  if (explicit) return explicit;
  if (seededDefault !== null) return seededDefault;
  if (!isNode()) throw new NeedInitError();
  return findLibrary();
}

/**
 * Single gate for every consumer: returns the initialized port for a
 * grammar, auto-initializing synchronously under Node. Throws
 * `NeedInitError` anywhere synchronous initialization is impossible.
 */
export function getWasmPort(libraryPath?: string): WasmPort {
  const key = libraryPath ?? resolveKey();
  const cached = ports.get(key);
  if (cached) return cached;
  if (!isNode()) throw new NeedInitError(libraryPath);
  const resolved = libraryPath ?? findLibrary();
  const direct = ports.get(resolved);
  if (direct) return direct;
  initSync(libraryPath ? { libraryPath: resolved } : {});
  const port = ports.get(resolved) ?? ports.get(key);
  if (!port) throw new NeedInitError(libraryPath);
  return port;
}

// --- helpers ----------------------------------------------------------------

function isNegative(status: bigint): boolean {
  return status < 0n;
}

function toNumber(value: bigint): number {
  return Number(value);
}

/** Reinterpret a guest i64 as an unsigned u64 address (INVALID_NODE survives). */
function asAddress(value: bigint): bigint {
  return BigInt.asUintN(64, value);
}

/** Encode a u64 address (possibly INVALID_NODE) as a guest i64. */
function asI64(value: bigint): bigint {
  return BigInt.asIntN(64, value);
}

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

/**
 * The wasm `FfiPort`: normalizes the reactor module's i32/i64 boundary
 * into the structured values the core expects. Memory is allocated with
 * the guest's `galley_js_malloc`/`galley_js_free`; every view is fresh
 * because allocation may grow (and detach) memory.
 */
export class WasmPort implements FfiPort {
  readonly wasm: GalleyWasmExports;
  readonly libraryPath: string;

  constructor(wasm: GalleyWasmExports, libraryPath: string) {
    this.wasm = wasm;
    this.libraryPath = libraryPath;
  }

  /** Guest hook entry: decode the name and forward to the core registry. */
  dispatchFromGuest(namePtr: number, nameLen: number, argsPtr: number): void {
    let name: string;
    try {
      name = textDecoder.decode(this.readBytes(namePtr, nameLen));
    } catch (error) {
      console.error("galley procedure dispatch: failed to decode name", error);
      return;
    }
    dispatchProcedure(name, argsPtr, this);
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
    if (ptr === 0) throw new Error("galley-js-wasm: out of memory");
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
    // Mirrors the native `galley_error_io` (-11) contract on read failure.
    let data: Uint8Array;
    try {
      data = new Uint8Array(fs.readFileSync(filePath));
    } catch {
      return -11;
    }
    return this.parse(handle, data);
  }

  lastPosition(handle: Handle): [number, number] | null {
    const out = this.malloc(8);
    try {
      const status = this.wasm.galley_last_position(handle as number, out, out + 4);
      if (isNegative(status)) return null;
      const view = this.dataView();
      return [view.getUint32(out, true), view.getUint32(out + 4, true)];
    } finally {
      this.free(out, 8);
    }
  }

  // -- arena and navigation ---------------------------------------------------

  nodeCount(handle: Handle): number {
    return toNumber(this.wasm.galley_node_count(handle as number));
  }

  reserveNodes(handle: Handle, capacity: bigint): number {
    return toNumber(this.wasm.galley_reserve_nodes(handle as number, asI64(capacity)));
  }

  nodeCapacity(handle: Handle): number {
    return toNumber(this.wasm.galley_node_capacity(handle as number));
  }

  rootNode(handle: Handle): bigint {
    return asAddress(this.wasm.galley_root_node(handle as number));
  }

  nodeValid(handle: Handle, node: bigint): boolean {
    return this.wasm.galley_node_is_valid(handle as number, asI64(node)) !== 0;
  }

  childCount(handle: Handle, node: bigint): number {
    return this.wasm.galley_node_child_count(handle as number, asI64(node));
  }

  firstChild(handle: Handle, node: bigint): bigint {
    return asAddress(this.wasm.galley_node_first_child(handle as number, asI64(node)));
  }

  lastChild(handle: Handle, node: bigint): bigint {
    return asAddress(this.wasm.galley_node_last_child(handle as number, asI64(node)));
  }

  nextSibling(handle: Handle, node: bigint): bigint {
    return asAddress(this.wasm.galley_node_next_sibling(handle as number, asI64(node)));
  }

  priorSibling(handle: Handle, node: bigint): bigint {
    return asAddress(this.wasm.galley_node_prior_sibling(handle as number, asI64(node)));
  }

  parent(handle: Handle, node: bigint): bigint {
    return asAddress(this.wasm.galley_node_parent(handle as number, asI64(node)));
  }

  // -- walker -------------------------------------------------------------------

  walkerCreate(handle: Handle, node: bigint, skipSemanticErrors: boolean): Handle | null {
    const walker = this.wasm.galley_walker_create(handle as number, asI64(node), skipSemanticErrors ? 1 : 0);
    if (walker === 0) return null;
    return walker;
  }

  walkerNext(walker: Handle): WalkedStep | null {
    const out = this.malloc(16);
    try {
      const yielded = this.wasm.galley_walker_next(walker as number, out, out + 8, out + 12);
      if (yielded === 0) return null;
      const view = this.dataView();
      return {
        node: view.getBigUint64(out, true),
        depth: view.getUint32(out + 8, true),
        isSemanticError: view.getInt32(out + 12, true) !== 0,
      };
    } finally {
      this.free(out, 16);
    }
  }

  walkerSkipChildren(walker: Handle): void {
    this.wasm.galley_walker_skip_children(walker as number);
  }

  walkerDestroy(walker: Handle): void {
    this.wasm.galley_walker_destroy(walker as number);
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

  nodeSymbolName(handle: Handle, node: bigint): Uint8Array | null {
    const session = handle as number;
    return this.tryCopyBytes((data, len) => this.wasm.galley_node_symbol_name(session, asI64(node), data, len));
  }

  nodeText(handle: Handle, node: bigint): Uint8Array | null {
    const session = handle as number;
    return this.tryCopyBytes((data, len) => this.wasm.galley_node_text(session, asI64(node), data, len));
  }

  nodeSpan(handle: Handle, node: bigint): [bigint, bigint] | null {
    const out = this.malloc(16);
    try {
      const status = this.wasm.galley_node_span(handle as number, asI64(node), out, out + 8);
      if (isNegative(status)) return null;
      const view = this.dataView();
      return [view.getBigUint64(out, true), view.getBigUint64(out + 8, true)];
    } finally {
      this.free(out, 16);
    }
  }

  nodeLineColumn(handle: Handle, node: bigint): [number, number] | null {
    const out = this.malloc(8);
    try {
      const status = this.wasm.galley_node_line_column(handle as number, asI64(node), out, out + 4);
      if (isNegative(status)) return null;
      const view = this.dataView();
      return [view.getUint32(out, true), view.getUint32(out + 4, true)];
    } finally {
      this.free(out, 8);
    }
  }

  nodeVariableIndex(handle: Handle, node: bigint): number {
    return toNumber(this.wasm.galley_node_variable_index(handle as number, asI64(node)));
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

  // -- tree editing --------------------------------------------------------------------

  treeAppendChildren(handle: Handle, parent: bigint, first: bigint): number {
    return toNumber(this.wasm.galley_tree_append_children(handle as number, asI64(parent), asI64(first)));
  }

  treeInsertBefore(handle: Handle, target: bigint, first: bigint): number {
    return toNumber(this.wasm.galley_tree_insert_before(handle as number, asI64(target), asI64(first)));
  }

  treeInsertAfter(handle: Handle, target: bigint, first: bigint): number {
    return toNumber(this.wasm.galley_tree_insert_after(handle as number, asI64(target), asI64(first)));
  }

  treeRemoveSiblings(handle: Handle, node: bigint, count: number): { status: number; head: bigint } {
    const out = this.malloc(8);
    try {
      const status = toNumber(
        this.wasm.galley_tree_remove_siblings(handle as number, asI64(node), count, out),
      );
      return { status, head: this.dataView().getBigUint64(out, true) };
    } finally {
      this.free(out, 8);
    }
  }

  treeRemoveSelf(handle: Handle, node: bigint): { status: number; head: bigint } {
    const out = this.malloc(8);
    try {
      const status = toNumber(this.wasm.galley_tree_remove_self(handle as number, asI64(node), out));
      return { status, head: this.dataView().getBigUint64(out, true) };
    } finally {
      this.free(out, 8);
    }
  }

  treePromoteChildrenOverWrapper(handle: Handle, wrapper: bigint): { status: number; head: bigint } {
    const out = this.malloc(8);
    try {
      const status = toNumber(
        this.wasm.galley_tree_promote_children_over_wrapper(handle as number, asI64(wrapper), out),
      );
      return { status, head: this.dataView().getBigUint64(out, true) };
    } finally {
      this.free(out, 8);
    }
  }

  treeCleanChildren(handle: Handle, node: bigint): { status: number; head: bigint } {
    const out = this.malloc(8);
    try {
      const status = toNumber(this.wasm.galley_tree_clean_children(handle as number, asI64(node), out));
      return { status, head: this.dataView().getBigUint64(out, true) };
    } finally {
      this.free(out, 8);
    }
  }

  treeUnlinkWrapper(handle: Handle, wrapper: bigint): number {
    return toNumber(this.wasm.galley_tree_unlink_wrapper(handle as number, asI64(wrapper)));
  }

  treeInsertChildrenAt(handle: Handle, parent: bigint, index: number, first: bigint): number {
    return toNumber(
      this.wasm.galley_tree_insert_children_at(handle as number, asI64(parent), index, asI64(first)),
    );
  }

  treeRemoveChildrenAt(
    handle: Handle,
    parent: bigint,
    index: number,
    count: number,
  ): { status: number; head: bigint } {
    const out = this.malloc(8);
    try {
      const status = toNumber(
        this.wasm.galley_tree_remove_children_at(handle as number, asI64(parent), index, count, out),
      );
      return { status, head: this.dataView().getBigUint64(out, true) };
    } finally {
      this.free(out, 8);
    }
  }

  // -- procedure hooks (parse-time state) ---------------------------------------------------

  procCurrentNode(args: Handle): bigint {
    return asAddress(this.wasm.galley_procedure_current_node(args as number));
  }

  procSetCurrentNode(args: Handle, node: bigint): void {
    this.wasm.galley_procedure_set_current_node(args as number, asI64(node));
  }

  procDropSelf(args: Handle): number {
    return toNumber(this.wasm.galley_procedure_drop_self(args as number));
  }

  procDropChildren(args: Handle): number {
    return toNumber(this.wasm.galley_procedure_drop_children(args as number));
  }

  procDropIfEmpty(args: Handle): number {
    return toNumber(this.wasm.galley_procedure_drop_if_empty(args as number));
  }

  procReplaceWithChildren(args: Handle): number {
    return toNumber(this.wasm.galley_procedure_replace_with_children(args as number));
  }

  procContextLine(args: Handle): number {
    return this.wasm.galley_procedure_context_line(args as number);
  }

  procContextColumn(args: Handle): number {
    return this.wasm.galley_procedure_context_column(args as number);
  }

  procReportSemanticError(args: Handle, message: Uint8Array): number {
    const bytes = textEncoder.encode(textDecoder.decode(message));
    const slot = this.writeBytes(bytes);
    try {
      return toNumber(
        this.wasm.galley_procedure_report_semantic_error(args as number, slot.ptr, slot.len),
      );
    } finally {
      this.free(slot.ptr, Math.max(slot.len, 1));
    }
  }
}
