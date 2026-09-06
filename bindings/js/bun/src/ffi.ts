/**
 * Bun adapter for the Galley JavaScript bindings: `bun:ffi` bindings over
 * `bindings/c/galley.h`, implementing the core `FfiPort`.
 *
 * Zero npm dependencies: `bun:ffi` is built into the runtime. The core
 * (`galley-js-core`) owns all session logic; memory copying and integer
 * normalization live here. Library discovery mirrors the Node adapter.
 */

import { Buffer } from "node:buffer";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { dlopen, FFIType, ptr, toArrayBuffer, CString } from "bun:ffi";
import type { FfiPort, Handle, SessionCOptions, WalkedStep } from "galley-js-core";

/** Native handles are addresses; 0 is null. */
type NativeHandle = number;

/** Callable view of the native symbols (see `BASE_SYMBOLS` below). */
interface GalleySymbols {
  galley_version(): string;
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
  galley_status_string(status: bigint): string;
  galley_symbol_name(session: NativeHandle, index: bigint, outData: number, outLen: number): bigint;
  galley_symbol_is_terminal(session: NativeHandle, index: bigint): number;
  galley_variable_name(session: NativeHandle, index: bigint, outData: number, outLen: number): bigint;
  galley_session_create(): NativeHandle;
  galley_session_create_ex(options: number): NativeHandle;
  galley_session_destroy(session: NativeHandle): void;
  galley_session_set_message_override(session: NativeHandle, name: number, nameLen: bigint, message: number, messageLen: bigint): bigint;
  galley_parse(session: NativeHandle, data: number, len: bigint): bigint;
  galley_parse_file(session: NativeHandle, path: number): bigint;
  galley_last_position(session: NativeHandle, outLine: number, outCol: number): bigint;
  galley_node_count(session: NativeHandle): bigint;
  galley_reserve_nodes(session: NativeHandle, capacity: bigint): bigint;
  galley_node_capacity(session: NativeHandle): bigint;
  galley_root_node(session: NativeHandle): bigint;
  galley_node_is_valid(session: NativeHandle, node: bigint): number;
  galley_node_child_count(session: NativeHandle, node: bigint): number;
  galley_node_first_child(session: NativeHandle, node: bigint): bigint;
  galley_node_last_child(session: NativeHandle, node: bigint): bigint;
  galley_node_next_sibling(session: NativeHandle, node: bigint): bigint;
  galley_node_prior_sibling(session: NativeHandle, node: bigint): bigint;
  galley_node_parent(session: NativeHandle, node: bigint): bigint;
  galley_walker_create(session: NativeHandle, node: bigint, skipSemanticErrors: number): NativeHandle;
  galley_walker_next(walker: NativeHandle, outNode: number, outDepth: number, outFlag: number): number;
  galley_walker_skip_children(walker: NativeHandle): void;
  galley_walker_destroy(walker: NativeHandle): void;
  galley_node_span(session: NativeHandle, node: bigint, outStart: number, outLen: number): bigint;
  galley_node_symbol_name(session: NativeHandle, node: bigint, outData: number, outLen: number): bigint;
  galley_node_variable_index(session: NativeHandle, node: bigint): bigint;
  galley_node_text(session: NativeHandle, node: bigint, outData: number, outLen: number): bigint;
  galley_node_line_column(session: NativeHandle, node: bigint, outLine: number, outCol: number): bigint;
  galley_has_diagnostic(session: NativeHandle): number;
  galley_diagnostic_kind(session: NativeHandle): bigint;
  galley_diagnostic_message(session: NativeHandle, out: number): bigint;
  galley_diagnostic_message_ansi(session: NativeHandle, out: number): bigint;
  galley_diagnostic_position(session: NativeHandle, outLine: number, outCol: number): bigint;
  galley_diagnostic_unexpected_token(session: NativeHandle, outData: number, outLen: number): bigint;
  galley_diagnostic_expected_count(session: NativeHandle): bigint;
  galley_diagnostic_expected_at(session: NativeHandle, index: bigint, outData: number, outLen: number): bigint;
  galley_diagnostic_context_count(session: NativeHandle): bigint;
  galley_diagnostic_context_at(session: NativeHandle, index: bigint, outData: number, outLen: number): bigint;
  galley_diagnostic_indentation(session: NativeHandle, outSpaces: number, outWidth: number): bigint;
  galley_syntax_error_count(session: NativeHandle): bigint;
  galley_semantic_error_count(session: NativeHandle): bigint;
  galley_diagnostic_semantic(session: NativeHandle, outVariable: number, outVariableLen: number, outMessage: number, outMessageLen: number): bigint;
  galley_diagnostic_recovery_kind(session: NativeHandle): bigint;
  galley_diagnostic_recovery_terminal(session: NativeHandle, outData: number, outLen: number): bigint;
  galley_diagnostic_recovery_resume(session: NativeHandle, out: number): bigint;
  galley_diagnostic_recovery_lhs_variable(session: NativeHandle, outData: number, outLen: number): bigint;
  galley_diagnostic_recovery_production(session: NativeHandle, outVar: number, outLen: number, outIdx: number): bigint;
  galley_diagnostic_recovery_occurrence(session: NativeHandle, outParent: number, outParentLen: number, outRhs: number, outSym: number, outVar: number, outVarLen: number): bigint;
  galley_recorded_diagnostic_count(session: NativeHandle): bigint;
  galley_recorded_diagnostic_kind(session: NativeHandle, diagIndex: bigint): bigint;
  galley_recorded_diagnostic_position(session: NativeHandle, diagIndex: bigint, outLine: number, outCol: number): bigint;
  galley_recorded_unexpected_token(session: NativeHandle, diagIndex: bigint, outData: number, outLen: number): bigint;
  galley_recorded_diagnostic_message(session: NativeHandle, diagIndex: bigint, out: number): bigint;
  galley_recorded_indentation(session: NativeHandle, diagIndex: bigint, outSpaces: number, outWidth: number): bigint;
  galley_recorded_semantic(session: NativeHandle, diagIndex: bigint, outVariable: number, outVariableLen: number, outMessage: number, outMessageLen: number): bigint;
  galley_recorded_expected_count(session: NativeHandle, diagIndex: bigint): bigint;
  galley_recorded_expected_token(session: NativeHandle, diagIndex: bigint, tokenIndex: bigint, outData: number, outLen: number): bigint;
  galley_recorded_context_count(session: NativeHandle, diagIndex: bigint): bigint;
  galley_recorded_context_name(session: NativeHandle, diagIndex: bigint, ctxIndex: bigint, outData: number, outLen: number): bigint;
  // NB: the implementation exports galley_recorded_diagnostic_recovery_kind
  // (the header's shorter name is stale); bun has no symbol remapping, so
  // the table and this interface use the true name.
  galley_recorded_diagnostic_recovery_kind(session: NativeHandle, diagIndex: bigint): bigint;
  galley_recorded_recovery_terminal(session: NativeHandle, diagIndex: bigint, outData: number, outLen: number): bigint;
  galley_recorded_recovery_resume(session: NativeHandle, diagIndex: bigint, out: number): bigint;
  galley_recorded_recovery_lhs_variable(session: NativeHandle, diagIndex: bigint, outData: number, outLen: number): bigint;
  galley_recorded_recovery_production(session: NativeHandle, diagIndex: bigint, outVar: number, outLen: number, outIdx: number): bigint;
  galley_recorded_recovery_occurrence(session: NativeHandle, diagIndex: bigint, outParent: number, outParentLen: number, outRhs: number, outSym: number, outVar: number, outVarLen: number): bigint;
  galley_tree_append_children(session: NativeHandle, parent: bigint, first: bigint): bigint;
  galley_tree_insert_before(session: NativeHandle, target: bigint, first: bigint): bigint;
  galley_tree_insert_after(session: NativeHandle, target: bigint, first: bigint): bigint;
  galley_tree_remove_siblings(session: NativeHandle, node: bigint, count: bigint, outHead: number): bigint;
  galley_tree_remove_self(session: NativeHandle, node: bigint, outHead: number): bigint;
  galley_tree_promote_children_over_wrapper(session: NativeHandle, wrapper: bigint, outHead: number): bigint;
  galley_tree_clean_children(session: NativeHandle, node: bigint, outHead: number): bigint;
  galley_tree_unlink_wrapper(session: NativeHandle, wrapper: bigint): bigint;
  galley_tree_insert_children_at(session: NativeHandle, parent: bigint, index: bigint, first: bigint): bigint;
  galley_tree_remove_children_at(session: NativeHandle, parent: bigint, index: bigint, count: bigint, outHead: number): bigint;
  galley_procedure_session(args: NativeHandle): NativeHandle;
  galley_procedure_current_node(args: NativeHandle): bigint;
  galley_procedure_set_current_node(args: NativeHandle, node: bigint): void;
  galley_procedure_drop_self(args: NativeHandle): bigint;
  galley_procedure_drop_children(args: NativeHandle): bigint;
  galley_procedure_drop_if_empty(args: NativeHandle): bigint;
  galley_procedure_replace_with_children(args: NativeHandle): bigint;
  galley_procedure_context_line(args: NativeHandle): number;
  galley_procedure_context_column(args: NativeHandle): number;
  galley_procedure_report_semantic_error(args: NativeHandle, message: number, messageLen: bigint): bigint;
  galley_install_js_dispatch(callback: NativeHandle): void;
}

// --- library discovery -------------------------------------------------

function defaultCacheDir(): string {
  const home = os.homedir();
  if (process.platform === "darwin") {
    return path.join(home, "Library", "Caches", "galley-bindings", "js-bun", "capi");
  }
  if (process.platform === "win32") {
    const base = process.env.LOCALAPPDATA ?? os.tmpdir();
    return path.join(base, "galley-bindings", "js-bun", "capi");
  }
  const base = process.env.XDG_CACHE_HOME ?? path.join(home, ".cache");
  return path.join(base, "galley-bindings", "js-bun", "capi");
}

function libFileName(base = "galley-js-bun"): string {
  if (process.platform === "darwin") return `lib${base}.dylib`;
  if (process.platform === "win32") return `${base}.dll`;
  return `lib${base}.so`;
}

function exists(candidate: string): boolean {
  try {
    fs.accessSync(candidate);
    return true;
  } catch {
    return false;
  }
}

export function findLibrary(explicit?: string): string {
  if (explicit && exists(explicit)) return path.resolve(explicit);
  if (process.env.GALLEY_LIBRARY_PATH && exists(process.env.GALLEY_LIBRARY_PATH)) {
    return path.resolve(process.env.GALLEY_LIBRARY_PATH);
  }
  // 1) cwd / language-dir copies (build.mjs copies lib next to grammar)
  const cwdCandidates = [
    path.join(process.cwd(), libFileName()),
    path.join(process.cwd(), "libgalley-js-bun.dylib"),
    path.join(process.cwd(), "libgalley-js-bun.so"),
  ];
  for (const c of cwdCandidates) if (exists(c)) return c;

  // 2) cache dir (same as build.mjs prefix)
  const cacheLib = path.join(defaultCacheDir(), "lib", libFileName());
  if (exists(cacheLib)) return cacheLib;

  // 3) sibling examples/js/bun for development (from dist/, three levels up)
  try {
    const here = path.dirname(fileURLToPath(import.meta.url));
    const devCandidates = [
      path.join(here, "../../../../examples/js/bun", libFileName()),
      path.join(here, "../../../../../examples/js/bun", libFileName()),
    ];
    for (const c of devCandidates) if (exists(c)) return c;
  } catch {
    // ignore URL parsing errors in bundled contexts
  }

  // fallback: let dlopen error with cache path
  return cacheLib;
}

// --- loader ------------------------------------------------------------

const BASE_SYMBOLS = {
  galley_version: { args: [], returns: FFIType.cstring },
  galley_parser_type: { args: [], returns: FFIType.i64 },
  galley_error_recovery_mode: { args: [], returns: FFIType.i64 },
  galley_has_ast: { args: [], returns: FFIType.i32 },
  galley_has_procedures: { args: [], returns: FFIType.i32 },
  galley_allows_no_ast_tree_procedures: { args: [], returns: FFIType.i32 },
  galley_source_retention_enabled: { args: [], returns: FFIType.i32 },
  galley_has_position_tracking: { args: [], returns: FFIType.i32 },
  galley_has_input_streaming: { args: [], returns: FFIType.i32 },
  galley_uses_verbatim: { args: [], returns: FFIType.i32 },
  galley_stack_overflow_recovery_available: { args: [], returns: FFIType.i32 },
  galley_symbol_count: { args: [], returns: FFIType.u64 },
  galley_variable_count: { args: [], returns: FFIType.u64 },
  galley_status_string: { args: [FFIType.i64], returns: FFIType.cstring },
  galley_symbol_name: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_symbol_is_terminal: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i32 },
  galley_variable_name: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_session_create: { args: [], returns: FFIType.ptr },
  galley_session_create_ex: { args: [FFIType.ptr], returns: FFIType.ptr },
  galley_session_destroy: { args: [FFIType.ptr], returns: FFIType.void },
  galley_session_set_message_override: { args: [FFIType.ptr, FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_parse: { args: [FFIType.ptr, FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_parse_file: { args: [FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_last_position: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_node_count: { args: [FFIType.ptr], returns: FFIType.u64 },
  galley_reserve_nodes: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_node_capacity: { args: [FFIType.ptr], returns: FFIType.u64 },
  galley_root_node: { args: [FFIType.ptr], returns: FFIType.u64 },
  galley_node_is_valid: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i32 },
  galley_node_child_count: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.u32 },
  galley_node_first_child: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.u64 },
  galley_node_last_child: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.u64 },
  galley_node_next_sibling: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.u64 },
  galley_node_prior_sibling: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.u64 },
  galley_node_parent: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.u64 },
  galley_walker_create: { args: [FFIType.ptr, FFIType.u64, FFIType.i32], returns: FFIType.ptr },
  galley_walker_next: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i32 },
  galley_walker_skip_children: { args: [FFIType.ptr], returns: FFIType.void },
  galley_walker_destroy: { args: [FFIType.ptr], returns: FFIType.void },
  galley_node_span: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_node_symbol_name: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_node_variable_index: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_node_text: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_node_line_column: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_has_diagnostic: { args: [FFIType.ptr], returns: FFIType.i32 },
  galley_diagnostic_kind: { args: [FFIType.ptr], returns: FFIType.i64 },
  galley_diagnostic_message: { args: [FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_diagnostic_message_ansi: { args: [FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_diagnostic_position: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_diagnostic_unexpected_token: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_diagnostic_expected_count: { args: [FFIType.ptr], returns: FFIType.i64 },
  galley_diagnostic_expected_at: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_diagnostic_context_count: { args: [FFIType.ptr], returns: FFIType.i64 },
  galley_diagnostic_context_at: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_diagnostic_indentation: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_syntax_error_count: { args: [FFIType.ptr], returns: FFIType.i64 },
  galley_semantic_error_count: { args: [FFIType.ptr], returns: FFIType.i64 },
  galley_diagnostic_semantic: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_diagnostic_recovery_kind: { args: [FFIType.ptr], returns: FFIType.i64 },
  galley_diagnostic_recovery_terminal: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_diagnostic_recovery_resume: { args: [FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_diagnostic_recovery_lhs_variable: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_diagnostic_recovery_production: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_diagnostic_recovery_occurrence: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_diagnostic_count: { args: [FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_diagnostic_kind: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_recorded_diagnostic_position: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_unexpected_token: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_diagnostic_message: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_indentation: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_semantic: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_expected_count: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_recorded_expected_token: { args: [FFIType.ptr, FFIType.u64, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_context_count: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_recorded_context_name: { args: [FFIType.ptr, FFIType.u64, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_diagnostic_recovery_kind: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_recorded_recovery_terminal: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_recovery_resume: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_recovery_lhs_variable: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_recovery_production: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_recovery_occurrence: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_tree_append_children: { args: [FFIType.ptr, FFIType.u64, FFIType.u64], returns: FFIType.i64 },
  galley_tree_insert_before: { args: [FFIType.ptr, FFIType.u64, FFIType.u64], returns: FFIType.i64 },
  galley_tree_insert_after: { args: [FFIType.ptr, FFIType.u64, FFIType.u64], returns: FFIType.i64 },
  galley_tree_remove_siblings: { args: [FFIType.ptr, FFIType.u64, FFIType.u64, FFIType.ptr], returns: FFIType.i64 },
  galley_tree_remove_self: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr], returns: FFIType.i64 },
  galley_tree_promote_children_over_wrapper: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr], returns: FFIType.i64 },
  galley_tree_clean_children: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr], returns: FFIType.i64 },
  galley_tree_unlink_wrapper: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_tree_insert_children_at: { args: [FFIType.ptr, FFIType.u64, FFIType.u64, FFIType.u64], returns: FFIType.i64 },
  galley_tree_remove_children_at: { args: [FFIType.ptr, FFIType.u64, FFIType.u64, FFIType.u64, FFIType.ptr], returns: FFIType.i64 },
  galley_procedure_session: { args: [FFIType.ptr], returns: FFIType.ptr },
  galley_procedure_current_node: { args: [FFIType.ptr], returns: FFIType.u64 },
  galley_procedure_set_current_node: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.void },
  galley_procedure_drop_self: { args: [FFIType.ptr], returns: FFIType.i64 },
  galley_procedure_drop_children: { args: [FFIType.ptr], returns: FFIType.i64 },
  galley_procedure_drop_if_empty: { args: [FFIType.ptr], returns: FFIType.i64 },
  galley_procedure_replace_with_children: { args: [FFIType.ptr], returns: FFIType.i64 },
  galley_procedure_context_line: { args: [FFIType.ptr], returns: FFIType.u32 },
  galley_procedure_context_column: { args: [FFIType.ptr], returns: FFIType.u32 },
  galley_procedure_report_semantic_error: { args: [FFIType.ptr, FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
} as const;

const DISPATCH_SYMBOL = {
  galley_install_js_dispatch: { args: [FFIType.function], returns: FFIType.void },
} as const;

function openNative(libPath: string, withDispatch: boolean): { symbols: GalleySymbols } {
  const table = withDispatch ? { ...BASE_SYMBOLS, ...DISPATCH_SYMBOL } : BASE_SYMBOLS;
  return dlopen(libPath, table) as unknown as { symbols: GalleySymbols };
}

// --- read helpers ----------------------------------------------------------

/** Copy (addr,len) into a Uint8Array owning its bytes. */
export function readBytes(addr: bigint, len: bigint): Uint8Array {
  if (addr === 0n || len === 0n) return new Uint8Array(0);
  const view = toArrayBuffer(Number(addr), 0, Number(len)) as ArrayBuffer;
  return new Uint8Array(view.slice(0));
}

export function readCString(addr: bigint): string {
  return String(new CString(Number(addr)));
}

function ptrOut64(): BigUint64Array {
  return new BigUint64Array(1);
}

function u32Out(): Uint32Array {
  return new Uint32Array(1);
}

function i64Out(): BigInt64Array {
  return new BigInt64Array(1);
}

// --- FfiPort implementation ----------------------------------------------

export class BunPort implements FfiPort {
  readonly native: GalleySymbols;
  readonly libraryPath: string;
  readonly supportsDispatch: boolean;

  constructor(native: GalleySymbols, libraryPath: string, supportsDispatch: boolean) {
    this.native = native;
    this.libraryPath = libraryPath;
    this.supportsDispatch = supportsDispatch;
  }

  // -- module-level queries --------------------------------------------

  version(): string {
    return String(this.native.galley_version());
  }

  parserType(): number {
    return Number(this.native.galley_parser_type());
  }

  errorRecoveryMode(): number {
    return Number(this.native.galley_error_recovery_mode());
  }

  hasAst(): boolean {
    return this.native.galley_has_ast() !== 0;
  }

  hasProcedures(): boolean {
    return this.native.galley_has_procedures() !== 0;
  }

  allowsNoAstTreeProcedures(): boolean {
    return this.native.galley_allows_no_ast_tree_procedures() !== 0;
  }

  sourceRetentionEnabled(): boolean {
    return this.native.galley_source_retention_enabled() !== 0;
  }

  hasPositionTracking(): boolean {
    return this.native.galley_has_position_tracking() !== 0;
  }

  hasInputStreaming(): boolean {
    return this.native.galley_has_input_streaming() !== 0;
  }

  usesVerbatim(): boolean {
    return this.native.galley_uses_verbatim() !== 0;
  }

  stackOverflowRecoveryAvailable(): boolean {
    return this.native.galley_stack_overflow_recovery_available() !== 0;
  }

  symbolCount(): number {
    return Number(this.native.galley_symbol_count());
  }

  variableCount(): number {
    return Number(this.native.galley_variable_count());
  }

  statusString(status: number): string | null {
    // Native returns NULL for unknown codes; bun:ffi coerces that to "".
    const rendered = String(this.native.galley_status_string(BigInt(status)));
    return rendered === "" ? null : rendered;
  }

  // -- sessions ---------------------------------------------------------

  createSession(options: SessionCOptions | null): Handle {
    let handle: NativeHandle;
    if (options === null) {
      handle = this.native.galley_session_create();
    } else {
      // GalleyCOptions layout: int32 x5, double, uint64 (40 bytes, LE).
      const buf = new ArrayBuffer(40);
      const view = new DataView(buf);
      view.setInt32(0, options.maxErrors, true);
      view.setInt32(4, options.recoveryWindow, true);
      view.setInt32(8, options.stackOverflowRecovery, true);
      view.setUint32(12, options.syntaxErrorStackDepth, true);
      view.setInt32(16, options.verbosity, true);
      view.setFloat64(24, options.astPreallocationRatio, true);
      view.setBigUint64(32, options.astPreallocationCap, true);
      handle = this.native.galley_session_create_ex(ptr(new Uint8Array(buf)));
    }
    if (handle === 0 || handle === null || handle === undefined) return null;
    return handle;
  }

  destroySession(handle: Handle): void {
    this.native.galley_session_destroy(handle as NativeHandle);
  }

  setMessageOverride(handle: Handle, name: Uint8Array, message: Uint8Array): number {
    return Number(
      this.native.galley_session_set_message_override(
        handle as NativeHandle, ptr(name), BigInt(name.length), ptr(message), BigInt(message.length),
      ),
    );
  }

  // -- parsing ----------------------------------------------------------

  parse(handle: Handle, data: Uint8Array): number {
    return Number(this.native.galley_parse(handle as NativeHandle, ptr(data), BigInt(data.length)));
  }

  parseFile(handle: Handle, filePath: string): number {
    const bytes = Buffer.from(filePath, "utf-8");
    const nul = Buffer.alloc(bytes.length + 1);
    bytes.copy(nul);
    return Number(this.native.galley_parse_file(handle as NativeHandle, ptr(nul)));
  }

  lastPosition(handle: Handle): [number, number] | null {
    const outLine = u32Out();
    const outCol = u32Out();
    if (this.native.galley_last_position(handle as NativeHandle, ptr(outLine), ptr(outCol)) < 0n) return null;
    return [outLine[0], outCol[0]];
  }

  // -- arena and navigation ----------------------------------------------

  nodeCount(handle: Handle): number {
    return Number(this.native.galley_node_count(handle as NativeHandle));
  }

  reserveNodes(handle: Handle, capacity: bigint): number {
    return Number(this.native.galley_reserve_nodes(handle as NativeHandle, capacity));
  }

  nodeCapacity(handle: Handle): number {
    return Number(this.native.galley_node_capacity(handle as NativeHandle));
  }

  rootNode(handle: Handle): bigint {
    return this.native.galley_root_node(handle as NativeHandle);
  }

  nodeValid(handle: Handle, node: bigint): boolean {
    return this.native.galley_node_is_valid(handle as NativeHandle, node) !== 0;
  }

  childCount(handle: Handle, node: bigint): number {
    return this.native.galley_node_child_count(handle as NativeHandle, node);
  }

  firstChild(handle: Handle, node: bigint): bigint {
    return this.native.galley_node_first_child(handle as NativeHandle, node);
  }

  lastChild(handle: Handle, node: bigint): bigint {
    return this.native.galley_node_last_child(handle as NativeHandle, node);
  }

  nextSibling(handle: Handle, node: bigint): bigint {
    return this.native.galley_node_next_sibling(handle as NativeHandle, node);
  }

  priorSibling(handle: Handle, node: bigint): bigint {
    return this.native.galley_node_prior_sibling(handle as NativeHandle, node);
  }

  parent(handle: Handle, node: bigint): bigint {
    return this.native.galley_node_parent(handle as NativeHandle, node);
  }

  // -- walker ------------------------------------------------------------

  walkerCreate(handle: Handle, node: bigint, skipSemanticErrors: boolean): Handle | null {
    const walker = this.native.galley_walker_create(handle as NativeHandle, node, skipSemanticErrors ? 1 : 0);
    if (walker === 0 || walker === null || walker === undefined) return null;
    return walker;
  }

  walkerNext(walker: Handle): WalkedStep | null {
    const outNode = ptrOut64();
    const outDepth = u32Out();
    const outFlag = u32Out();
    if (this.native.galley_walker_next(walker as NativeHandle, ptr(outNode), ptr(outDepth), ptr(outFlag)) === 0) return null;
    return { node: outNode[0], depth: outDepth[0], isSemanticError: outFlag[0] !== 0 };
  }

  walkerSkipChildren(walker: Handle): void {
    this.native.galley_walker_skip_children(walker as NativeHandle);
  }

  walkerDestroy(walker: Handle): void {
    this.native.galley_walker_destroy(walker as NativeHandle);
  }

  // -- node accessors -----------------------------------------------------

  #tryCopyBytes(fn: (outData: BigUint64Array, outLen: BigUint64Array) => bigint): Uint8Array | null {
    const outData = ptrOut64();
    const outLen = ptrOut64();
    if (fn(outData, outLen) < 0n) return null;
    if (outData[0] === 0n) return null;
    return readBytes(outData[0], outLen[0]);
  }

  #readSemanticPair(
    fn: (outVariable: BigUint64Array, outVariableLen: BigUint64Array, outMessage: BigUint64Array, outMessageLen: BigUint64Array) => bigint,
  ): [string, string] | null {
    const outVariable = ptrOut64();
    const outVariableLen = ptrOut64();
    const outMessage = ptrOut64();
    const outMessageLen = ptrOut64();
    if (fn(outVariable, outVariableLen, outMessage, outMessageLen) < 0n) return null;
    if (outVariable[0] === 0n || outMessage[0] === 0n) return null;
    const decoder = new TextDecoder();
    return [
      decoder.decode(readBytes(outVariable[0], outVariableLen[0])),
      decoder.decode(readBytes(outMessage[0], outMessageLen[0])),
    ];
  }

  nodeSymbolName(handle: Handle, node: bigint): Uint8Array | null {
    const h = handle as NativeHandle;
    const outData = ptrOut64();
    const outLen = ptrOut64();
    if (this.native.galley_node_symbol_name(h, node, ptr(outData), ptr(outLen)) < 0n) return null;
    return readBytes(outData[0], outLen[0]);
  }

  nodeText(handle: Handle, node: bigint): Uint8Array | null {
    const h = handle as NativeHandle;
    const outData = ptrOut64();
    const outLen = ptrOut64();
    if (this.native.galley_node_text(h, node, ptr(outData), ptr(outLen)) < 0n) return null;
    return readBytes(outData[0], outLen[0]);
  }

  nodeSpan(handle: Handle, node: bigint): [bigint, bigint] | null {
    const outStart = ptrOut64();
    const outLen = ptrOut64();
    if (this.native.galley_node_span(handle as NativeHandle, node, ptr(outStart), ptr(outLen)) < 0n) return null;
    return [outStart[0], outLen[0]];
  }

  nodeLineColumn(handle: Handle, node: bigint): [number, number] | null {
    const outLine = u32Out();
    const outCol = u32Out();
    if (this.native.galley_node_line_column(handle as NativeHandle, node, ptr(outLine), ptr(outCol)) < 0n) return null;
    return [outLine[0], outCol[0]];
  }

  nodeVariableIndex(handle: Handle, node: bigint): number {
    return Number(this.native.galley_node_variable_index(handle as NativeHandle, node));
  }

  symbolNameAt(handle: Handle, index: number): Uint8Array | null {
    const h = handle as NativeHandle;
    const outData = ptrOut64();
    const outLen = ptrOut64();
    if (this.native.galley_symbol_name(h, BigInt(index), ptr(outData), ptr(outLen)) < 0n) return null;
    return readBytes(outData[0], outLen[0]);
  }

  symbolIsTerminal(handle: Handle, index: number): boolean {
    return this.native.galley_symbol_is_terminal(handle as NativeHandle, BigInt(index)) !== 0;
  }

  variableNameAt(handle: Handle, index: number): Uint8Array | null {
    const h = handle as NativeHandle;
    const outData = ptrOut64();
    const outLen = ptrOut64();
    if (this.native.galley_variable_name(h, BigInt(index), ptr(outData), ptr(outLen)) < 0n) return null;
    return readBytes(outData[0], outLen[0]);
  }

  // -- diagnostics ---------------------------------------------------------

  hasDiagnostic(handle: Handle): boolean {
    return this.native.galley_has_diagnostic(handle as NativeHandle) !== 0;
  }

  diagnosticKind(handle: Handle): number {
    return Number(this.native.galley_diagnostic_kind(handle as NativeHandle));
  }

  diagnosticMessage(handle: Handle): string | null {
    const out = ptrOut64();
    if (this.native.galley_diagnostic_message(handle as NativeHandle, ptr(out)) !== 0n) return null;
    return readCString(out[0]);
  }

  diagnosticMessageAnsi(handle: Handle): string | null {
    const out = ptrOut64();
    if (this.native.galley_diagnostic_message_ansi(handle as NativeHandle, ptr(out)) !== 0n) return null;
    return readCString(out[0]);
  }

  diagnosticPosition(handle: Handle): [number, number] | null {
    const outLine = u32Out();
    const outCol = u32Out();
    if (this.native.galley_diagnostic_position(handle as NativeHandle, ptr(outLine), ptr(outCol)) < 0n) return null;
    return [outLine[0], outCol[0]];
  }

  diagnosticUnexpectedToken(handle: Handle): Uint8Array | null {
    const h = handle as NativeHandle;
    return this.#tryCopyBytes((od, ol) => this.native.galley_diagnostic_unexpected_token(h, ptr(od), ptr(ol)));
  }

  diagnosticExpectedCount(handle: Handle): number {
    return Number(this.native.galley_diagnostic_expected_count(handle as NativeHandle));
  }

  diagnosticExpectedAt(handle: Handle, index: number): Uint8Array | null {
    const h = handle as NativeHandle;
    return this.#tryCopyBytes((od, ol) => this.native.galley_diagnostic_expected_at(h, BigInt(index), ptr(od), ptr(ol)));
  }

  diagnosticContextCount(handle: Handle): number {
    return Number(this.native.galley_diagnostic_context_count(handle as NativeHandle));
  }

  diagnosticContextAt(handle: Handle, index: number): Uint8Array | null {
    const h = handle as NativeHandle;
    return this.#tryCopyBytes((od, ol) => this.native.galley_diagnostic_context_at(h, BigInt(index), ptr(od), ptr(ol)));
  }

  syntaxErrorCount(handle: Handle): number {
    return Number(this.native.galley_syntax_error_count(handle as NativeHandle));
  }

  semanticErrorCount(handle: Handle): number {
    return Number(this.native.galley_semantic_error_count(handle as NativeHandle));
  }

  diagnosticSemantic(handle: Handle): [string, string] | null {
    const h = handle as NativeHandle;
    return this.#readSemanticPair((ov, ovl, om, oml) =>
      this.native.galley_diagnostic_semantic(h, ptr(ov), ptr(ovl), ptr(om), ptr(oml)));
  }

  diagnosticIndentation(handle: Handle): [number, number] | null {
    const outSpaces = u32Out();
    const outWidth = u32Out();
    if (this.native.galley_diagnostic_indentation(handle as NativeHandle, ptr(outSpaces), ptr(outWidth)) !== 0n) return null;
    return [outSpaces[0], outWidth[0]];
  }

  diagnosticRecoveryKind(handle: Handle): number {
    return Number(this.native.galley_diagnostic_recovery_kind(handle as NativeHandle));
  }

  diagnosticRecoveryTerminal(handle: Handle): Uint8Array | null {
    const h = handle as NativeHandle;
    return this.#tryCopyBytes((od, ol) => this.native.galley_diagnostic_recovery_terminal(h, ptr(od), ptr(ol)));
  }

  diagnosticRecoveryResume(handle: Handle): number | null {
    const out = i64Out();
    if (this.native.galley_diagnostic_recovery_resume(handle as NativeHandle, ptr(out)) !== 0n) return null;
    return Number(out[0]);
  }

  diagnosticRecoveryLhsVariable(handle: Handle): string | null {
    const h = handle as NativeHandle;
    const outData = ptrOut64();
    const outLen = ptrOut64();
    if (this.native.galley_diagnostic_recovery_lhs_variable(h, ptr(outData), ptr(outLen)) < 0n || outData[0] === 0n) return null;
    return new TextDecoder().decode(readBytes(outData[0], outLen[0]));
  }

  diagnosticRecoveryProduction(handle: Handle): [string, number] | null {
    const h = handle as NativeHandle;
    const outVar = ptrOut64();
    const outLen = ptrOut64();
    const outIdx = u32Out();
    if (this.native.galley_diagnostic_recovery_production(h, ptr(outVar), ptr(outLen), ptr(outIdx)) !== 0n) return null;
    return [new TextDecoder().decode(readBytes(outVar[0], outLen[0])), outIdx[0]];
  }

  diagnosticRecoveryOccurrence(handle: Handle): [string, number, number, string] | null {
    const h = handle as NativeHandle;
    const outParent = ptrOut64();
    const outParentLen = ptrOut64();
    const outRhs = u32Out();
    const outSym = u32Out();
    const outVar = ptrOut64();
    const outVarLen = ptrOut64();
    if (this.native.galley_diagnostic_recovery_occurrence(h, ptr(outParent), ptr(outParentLen), ptr(outRhs), ptr(outSym), ptr(outVar), ptr(outVarLen)) !== 0n) return null;
    const decoder = new TextDecoder();
    return [
      decoder.decode(readBytes(outParent[0], outParentLen[0])),
      outRhs[0],
      outSym[0],
      decoder.decode(readBytes(outVar[0], outVarLen[0])),
    ];
  }

  recordedDiagnosticCount(handle: Handle): number {
    return Number(this.native.galley_recorded_diagnostic_count(handle as NativeHandle));
  }

  recordedDiagnosticKind(handle: Handle, diagIndex: number): number {
    return Number(this.native.galley_recorded_diagnostic_kind(handle as NativeHandle, BigInt(diagIndex)));
  }

  recordedDiagnosticPosition(handle: Handle, diagIndex: number): [number, number] | null {
    const outLine = u32Out();
    const outCol = u32Out();
    if (this.native.galley_recorded_diagnostic_position(handle as NativeHandle, BigInt(diagIndex), ptr(outLine), ptr(outCol)) < 0n) return null;
    return [outLine[0], outCol[0]];
  }

  recordedUnexpectedToken(handle: Handle, diagIndex: number): Uint8Array | null {
    const h = handle as NativeHandle;
    const d = BigInt(diagIndex);
    return this.#tryCopyBytes((od, ol) => this.native.galley_recorded_unexpected_token(h, d, ptr(od), ptr(ol)));
  }

  recordedDiagnosticMessage(handle: Handle, diagIndex: number): string | null {
    const out = ptrOut64();
    if (this.native.galley_recorded_diagnostic_message(handle as NativeHandle, BigInt(diagIndex), ptr(out)) !== 0n) return null;
    return readCString(out[0]);
  }

  recordedIndentation(handle: Handle, diagIndex: number): [number, number] | null {
    const outSpaces = u32Out();
    const outWidth = u32Out();
    if (this.native.galley_recorded_indentation(handle as NativeHandle, BigInt(diagIndex), ptr(outSpaces), ptr(outWidth)) !== 0n) return null;
    return [outSpaces[0], outWidth[0]];
  }

  recordedSemantic(handle: Handle, diagIndex: number): [string, string] | null {
    const h = handle as NativeHandle;
    const d = BigInt(diagIndex);
    return this.#readSemanticPair((ov, ovl, om, oml) =>
      this.native.galley_recorded_semantic(h, d, ptr(ov), ptr(ovl), ptr(om), ptr(oml)));
  }

  recordedExpectedCount(handle: Handle, diagIndex: number): number {
    return Number(this.native.galley_recorded_expected_count(handle as NativeHandle, BigInt(diagIndex)));
  }

  recordedExpectedToken(handle: Handle, diagIndex: number, tokenIndex: number): Uint8Array | null {
    const h = handle as NativeHandle;
    const d = BigInt(diagIndex);
    const t = BigInt(tokenIndex);
    return this.#tryCopyBytes((od, ol) => this.native.galley_recorded_expected_token(h, d, t, ptr(od), ptr(ol)));
  }

  recordedContextCount(handle: Handle, diagIndex: number): number {
    return Number(this.native.galley_recorded_context_count(handle as NativeHandle, BigInt(diagIndex)));
  }

  recordedContextName(handle: Handle, diagIndex: number, contextIndex: number): Uint8Array | null {
    const h = handle as NativeHandle;
    const d = BigInt(diagIndex);
    const c = BigInt(contextIndex);
    return this.#tryCopyBytes((od, ol) => this.native.galley_recorded_context_name(h, d, c, ptr(od), ptr(ol)));
  }

  recordedRecoveryKind(handle: Handle, diagIndex: number): number {
    return Number(this.native.galley_recorded_diagnostic_recovery_kind(handle as NativeHandle, BigInt(diagIndex)));
  }

  recordedRecoveryTerminal(handle: Handle, diagIndex: number): Uint8Array | null {
    const h = handle as NativeHandle;
    const d = BigInt(diagIndex);
    return this.#tryCopyBytes((od, ol) => this.native.galley_recorded_recovery_terminal(h, d, ptr(od), ptr(ol)));
  }

  recordedRecoveryResume(handle: Handle, diagIndex: number): number | null {
    const out = i64Out();
    if (this.native.galley_recorded_recovery_resume(handle as NativeHandle, BigInt(diagIndex), ptr(out)) !== 0n) return null;
    return Number(out[0]);
  }

  recordedRecoveryLhsVariable(handle: Handle, diagIndex: number): string | null {
    const h = handle as NativeHandle;
    const d = BigInt(diagIndex);
    const outData = ptrOut64();
    const outLen = ptrOut64();
    if (this.native.galley_recorded_recovery_lhs_variable(h, d, ptr(outData), ptr(outLen)) < 0n || outData[0] === 0n) return null;
    return new TextDecoder().decode(readBytes(outData[0], outLen[0]));
  }

  recordedRecoveryProduction(handle: Handle, diagIndex: number): [string, number] | null {
    const h = handle as NativeHandle;
    const d = BigInt(diagIndex);
    const outVar = ptrOut64();
    const outLen = ptrOut64();
    const outIdx = u32Out();
    if (this.native.galley_recorded_recovery_production(h, d, ptr(outVar), ptr(outLen), ptr(outIdx)) !== 0n) return null;
    return [new TextDecoder().decode(readBytes(outVar[0], outLen[0])), outIdx[0]];
  }

  recordedRecoveryOccurrence(handle: Handle, diagIndex: number): [string, number, number, string] | null {
    const h = handle as NativeHandle;
    const d = BigInt(diagIndex);
    const outParent = ptrOut64();
    const outParentLen = ptrOut64();
    const outRhs = u32Out();
    const outSym = u32Out();
    const outVar = ptrOut64();
    const outVarLen = ptrOut64();
    if (this.native.galley_recorded_recovery_occurrence(h, d, ptr(outParent), ptr(outParentLen), ptr(outRhs), ptr(outSym), ptr(outVar), ptr(outVarLen)) !== 0n) return null;
    const decoder = new TextDecoder();
    return [
      decoder.decode(readBytes(outParent[0], outParentLen[0])),
      outRhs[0],
      outSym[0],
      decoder.decode(readBytes(outVar[0], outVarLen[0])),
    ];
  }

  // -- tree editing ----------------------------------------------------------

  treeAppendChildren(handle: Handle, parent: bigint, first: bigint): number {
    return Number(this.native.galley_tree_append_children(handle as NativeHandle, parent, first));
  }

  treeInsertBefore(handle: Handle, target: bigint, first: bigint): number {
    return Number(this.native.galley_tree_insert_before(handle as NativeHandle, target, first));
  }

  treeInsertAfter(handle: Handle, target: bigint, first: bigint): number {
    return Number(this.native.galley_tree_insert_after(handle as NativeHandle, target, first));
  }

  treeRemoveSiblings(handle: Handle, node: bigint, count: number): { status: number; head: bigint } {
    const outHead = ptrOut64();
    const st = this.native.galley_tree_remove_siblings(handle as NativeHandle, node, BigInt(count), ptr(outHead));
    return { status: Number(st), head: outHead[0] };
  }

  treeRemoveSelf(handle: Handle, node: bigint): { status: number; head: bigint } {
    const outHead = ptrOut64();
    const st = this.native.galley_tree_remove_self(handle as NativeHandle, node, ptr(outHead));
    return { status: Number(st), head: outHead[0] };
  }

  treePromoteChildrenOverWrapper(handle: Handle, wrapper: bigint): { status: number; head: bigint } {
    const outHead = ptrOut64();
    const st = this.native.galley_tree_promote_children_over_wrapper(handle as NativeHandle, wrapper, ptr(outHead));
    return { status: Number(st), head: outHead[0] };
  }

  treeCleanChildren(handle: Handle, node: bigint): { status: number; head: bigint } {
    const outHead = ptrOut64();
    const st = this.native.galley_tree_clean_children(handle as NativeHandle, node, ptr(outHead));
    return { status: Number(st), head: outHead[0] };
  }

  treeUnlinkWrapper(handle: Handle, wrapper: bigint): number {
    return Number(this.native.galley_tree_unlink_wrapper(handle as NativeHandle, wrapper));
  }

  treeInsertChildrenAt(handle: Handle, parent: bigint, index: number, first: bigint): number {
    return Number(this.native.galley_tree_insert_children_at(handle as NativeHandle, parent, BigInt(index), first));
  }

  treeRemoveChildrenAt(handle: Handle, parent: bigint, index: number, count: number): { status: number; head: bigint } {
    const outHead = ptrOut64();
    const st = this.native.galley_tree_remove_children_at(handle as NativeHandle, parent, BigInt(index), BigInt(count), ptr(outHead));
    return { status: Number(st), head: outHead[0] };
  }

  // -- procedure hooks ----------------------------------------------------------

  procCurrentNode(args: Handle): bigint {
    return this.native.galley_procedure_current_node(args as NativeHandle);
  }

  procSetCurrentNode(args: Handle, node: bigint): void {
    this.native.galley_procedure_set_current_node(args as NativeHandle, node);
  }

  procDropSelf(args: Handle): number {
    return Number(this.native.galley_procedure_drop_self(args as NativeHandle));
  }

  procDropChildren(args: Handle): number {
    return Number(this.native.galley_procedure_drop_children(args as NativeHandle));
  }

  procDropIfEmpty(args: Handle): number {
    return Number(this.native.galley_procedure_drop_if_empty(args as NativeHandle));
  }

  procReplaceWithChildren(args: Handle): number {
    return Number(this.native.galley_procedure_replace_with_children(args as NativeHandle));
  }

  procContextLine(args: Handle): number {
    return this.native.galley_procedure_context_line(args as NativeHandle);
  }

  procContextColumn(args: Handle): number {
    return this.native.galley_procedure_context_column(args as NativeHandle);
  }

  procReportSemanticError(args: Handle, message: Uint8Array): number {
    return Number(
      this.native.galley_procedure_report_semantic_error(args as NativeHandle, ptr(message), BigInt(message.length)),
    );
  }
}

const portCache = new Map<string, BunPort>();

/** Port for the library at `explicitPath` (or default discovery), cached per path. */
export function getBunPort(explicitPath?: string): BunPort {
  const libPath = findLibrary(explicitPath);
  const cached = portCache.get(libPath);
  if (cached) return cached;
  // Libraries built for C procedures lack the JS dispatch symbol.
  let native: GalleySymbols;
  let supportsDispatch = true;
  try {
    native = openNative(libPath, true).symbols;
  } catch {
    native = openNative(libPath, false).symbols;
    supportsDispatch = false;
  }
  const port = new BunPort(native, libPath, supportsDispatch);
  portCache.set(libPath, port);
  return port;
}
