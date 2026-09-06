/**
 * Deno adapter for the Galley JavaScript bindings: `Deno.dlopen` bindings
 * over `bindings/c/galley.h`, implementing the core `FfiPort`.
 *
 * Zero dependencies: no npm packages, no build step for the adapter itself.
 * The core (`galley-js-core`, resolved to its compiled `dist` via the
 * package `deno.json` import map) owns all session logic; memory copying
 * and integer normalization live here. Requires `--allow-ffi` (dlopen),
 * `--allow-read` (library discovery, `parseFile`), and `--allow-env`
 * (library discovery).
 */

import type { FfiPort, Handle, SessionCOptions, WalkedStep } from "galley-js-core";

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

/** Callable view of the native symbols (see `BASE_SYMBOLS` below). */
type FfiOut = Uint8Array | Uint32Array | BigUint64Array | BigInt64Array;

interface GalleySymbols {
  galley_version(): Deno.PointerValue;
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
  galley_status_string(status: bigint): Deno.PointerValue;
  galley_symbol_name(session: Deno.PointerValue, index: bigint, outData: FfiOut, outLen: FfiOut): bigint;
  galley_symbol_is_terminal(session: Deno.PointerValue, index: bigint): number;
  galley_variable_name(session: Deno.PointerValue, index: bigint, outData: FfiOut, outLen: FfiOut): bigint;
  galley_session_create(): Deno.PointerValue;
  galley_session_create_ex(options: FfiOut): Deno.PointerValue;
  galley_session_destroy(session: Deno.PointerValue): void;
  galley_session_set_message_override(session: Deno.PointerValue, name: FfiOut, nameLen: number, message: FfiOut, messageLen: number): bigint;
  galley_parse(session: Deno.PointerValue, data: FfiOut, len: number): bigint;
  galley_parse_file(session: Deno.PointerValue, path: FfiOut): bigint;
  galley_last_position(session: Deno.PointerValue, outLine: FfiOut, outCol: FfiOut): bigint;
  galley_node_count(session: Deno.PointerValue): bigint;
  galley_reserve_nodes(session: Deno.PointerValue, capacity: bigint): bigint;
  galley_node_capacity(session: Deno.PointerValue): bigint;
  galley_root_node(session: Deno.PointerValue): bigint;
  galley_node_is_valid(session: Deno.PointerValue, node: bigint): number;
  galley_node_child_count(session: Deno.PointerValue, node: bigint): number;
  galley_node_first_child(session: Deno.PointerValue, node: bigint): bigint;
  galley_node_last_child(session: Deno.PointerValue, node: bigint): bigint;
  galley_node_next_sibling(session: Deno.PointerValue, node: bigint): bigint;
  galley_node_prior_sibling(session: Deno.PointerValue, node: bigint): bigint;
  galley_node_parent(session: Deno.PointerValue, node: bigint): bigint;
  galley_walker_create(session: Deno.PointerValue, node: bigint, skipSemanticErrors: number): Deno.PointerValue;
  galley_walker_next(walker: Deno.PointerValue, outNode: FfiOut, outDepth: FfiOut, outFlag: FfiOut): number;
  galley_walker_skip_children(walker: Deno.PointerValue): void;
  galley_walker_destroy(walker: Deno.PointerValue): void;
  galley_node_span(session: Deno.PointerValue, node: bigint, outStart: FfiOut, outLen: FfiOut): bigint;
  galley_node_symbol_name(session: Deno.PointerValue, node: bigint, outData: FfiOut, outLen: FfiOut): bigint;
  galley_node_variable_index(session: Deno.PointerValue, node: bigint): bigint;
  galley_node_text(session: Deno.PointerValue, node: bigint, outData: FfiOut, outLen: FfiOut): bigint;
  galley_node_line_column(session: Deno.PointerValue, node: bigint, outLine: FfiOut, outCol: FfiOut): bigint;
  galley_has_diagnostic(session: Deno.PointerValue): number;
  galley_diagnostic_kind(session: Deno.PointerValue): bigint;
  galley_diagnostic_message(session: Deno.PointerValue, out: FfiOut): bigint;
  galley_diagnostic_message_ansi(session: Deno.PointerValue, out: FfiOut): bigint;
  galley_diagnostic_position(session: Deno.PointerValue, outLine: FfiOut, outCol: FfiOut): bigint;
  galley_diagnostic_unexpected_token(session: Deno.PointerValue, outData: FfiOut, outLen: FfiOut): bigint;
  galley_diagnostic_expected_count(session: Deno.PointerValue): bigint;
  galley_diagnostic_expected_at(session: Deno.PointerValue, index: bigint, outData: FfiOut, outLen: FfiOut): bigint;
  galley_diagnostic_context_count(session: Deno.PointerValue): bigint;
  galley_diagnostic_context_at(session: Deno.PointerValue, index: bigint, outData: FfiOut, outLen: FfiOut): bigint;
  galley_diagnostic_indentation(session: Deno.PointerValue, outSpaces: FfiOut, outWidth: FfiOut): bigint;
  galley_syntax_error_count(session: Deno.PointerValue): bigint;
  galley_semantic_error_count(session: Deno.PointerValue): bigint;
  galley_diagnostic_semantic(session: Deno.PointerValue, outVariable: FfiOut, outVariableLen: FfiOut, outMessage: FfiOut, outMessageLen: FfiOut): bigint;
  galley_diagnostic_recovery_kind(session: Deno.PointerValue): bigint;
  galley_diagnostic_recovery_terminal(session: Deno.PointerValue, outData: FfiOut, outLen: FfiOut): bigint;
  galley_diagnostic_recovery_resume(session: Deno.PointerValue, out: FfiOut): bigint;
  galley_diagnostic_recovery_lhs_variable(session: Deno.PointerValue, outData: FfiOut, outLen: FfiOut): bigint;
  galley_diagnostic_recovery_production(session: Deno.PointerValue, outVar: FfiOut, outLen: FfiOut, outIdx: FfiOut): bigint;
  galley_diagnostic_recovery_occurrence(session: Deno.PointerValue, outParent: FfiOut, outParentLen: FfiOut, outRhs: FfiOut, outSym: FfiOut, outVar: FfiOut, outVarLen: FfiOut): bigint;
  galley_recorded_diagnostic_count(session: Deno.PointerValue): bigint;
  galley_recorded_diagnostic_kind(session: Deno.PointerValue, diagIndex: bigint): bigint;
  galley_recorded_diagnostic_position(session: Deno.PointerValue, diagIndex: bigint, outLine: FfiOut, outCol: FfiOut): bigint;
  galley_recorded_unexpected_token(session: Deno.PointerValue, diagIndex: bigint, outData: FfiOut, outLen: FfiOut): bigint;
  galley_recorded_diagnostic_message(session: Deno.PointerValue, diagIndex: bigint, out: FfiOut): bigint;
  galley_recorded_indentation(session: Deno.PointerValue, diagIndex: bigint, outSpaces: FfiOut, outWidth: FfiOut): bigint;
  galley_recorded_semantic(session: Deno.PointerValue, diagIndex: bigint, outVariable: FfiOut, outVariableLen: FfiOut, outMessage: FfiOut, outMessageLen: FfiOut): bigint;
  galley_recorded_expected_count(session: Deno.PointerValue, diagIndex: bigint): bigint;
  galley_recorded_expected_token(session: Deno.PointerValue, diagIndex: bigint, tokenIndex: bigint, outData: FfiOut, outLen: FfiOut): bigint;
  galley_recorded_context_count(session: Deno.PointerValue, diagIndex: bigint): bigint;
  galley_recorded_context_name(session: Deno.PointerValue, diagIndex: bigint, ctxIndex: bigint, outData: FfiOut, outLen: FfiOut): bigint;
  galley_recorded_recovery_kind(session: Deno.PointerValue, diagIndex: bigint): bigint;
  galley_recorded_recovery_terminal(session: Deno.PointerValue, diagIndex: bigint, outData: FfiOut, outLen: FfiOut): bigint;
  galley_recorded_recovery_resume(session: Deno.PointerValue, diagIndex: bigint, out: FfiOut): bigint;
  galley_recorded_recovery_lhs_variable(session: Deno.PointerValue, diagIndex: bigint, outData: FfiOut, outLen: FfiOut): bigint;
  galley_recorded_recovery_production(session: Deno.PointerValue, diagIndex: bigint, outVar: FfiOut, outLen: FfiOut, outIdx: FfiOut): bigint;
  galley_recorded_recovery_occurrence(session: Deno.PointerValue, diagIndex: bigint, outParent: FfiOut, outParentLen: FfiOut, outRhs: FfiOut, outSym: FfiOut, outVar: FfiOut, outVarLen: FfiOut): bigint;
  galley_tree_append_children(session: Deno.PointerValue, parent: bigint, first: bigint): bigint;
  galley_tree_insert_before(session: Deno.PointerValue, target: bigint, first: bigint): bigint;
  galley_tree_insert_after(session: Deno.PointerValue, target: bigint, first: bigint): bigint;
  galley_tree_remove_siblings(session: Deno.PointerValue, node: bigint, count: number, outHead: FfiOut): bigint;
  galley_tree_remove_self(session: Deno.PointerValue, node: bigint, outHead: FfiOut): bigint;
  galley_tree_promote_children_over_wrapper(session: Deno.PointerValue, wrapper: bigint, outHead: FfiOut): bigint;
  galley_tree_clean_children(session: Deno.PointerValue, node: bigint, outHead: FfiOut): bigint;
  galley_tree_unlink_wrapper(session: Deno.PointerValue, wrapper: bigint): bigint;
  galley_tree_insert_children_at(session: Deno.PointerValue, parent: bigint, index: number, first: bigint): bigint;
  galley_tree_remove_children_at(session: Deno.PointerValue, parent: bigint, index: number, count: number, outHead: FfiOut): bigint;
  galley_procedure_session(args: Deno.PointerValue): Deno.PointerValue;
  galley_procedure_current_node(args: Deno.PointerValue): bigint;
  galley_procedure_set_current_node(args: Deno.PointerValue, node: bigint): void;
  galley_procedure_drop_self(args: Deno.PointerValue): bigint;
  galley_procedure_drop_children(args: Deno.PointerValue): bigint;
  galley_procedure_drop_if_empty(args: Deno.PointerValue): bigint;
  galley_procedure_replace_with_children(args: Deno.PointerValue): bigint;
  galley_procedure_context_line(args: Deno.PointerValue): number;
  galley_procedure_context_column(args: Deno.PointerValue): number;
  galley_procedure_report_semantic_error(args: Deno.PointerValue, message: FfiOut, messageLen: number): bigint;
  galley_install_js_dispatch(callback: Deno.PointerValue): void;
}

// --- library discovery -------------------------------------------------

function libFileName(base = "galley-js-deno"): string {
  if (Deno.build.os === "darwin") return `lib${base}.dylib`;
  if (Deno.build.os === "windows") return `${base}.dll`;
  return `lib${base}.so`;
}

function exists(filePath: string): boolean {
  try {
    Deno.statSync(filePath);
    return true;
  } catch {
    return false;
  }
}

function joinPath(...parts: string[]): string {
  return parts.join("/").replace(/\/+/g, "/");
}

function defaultCacheDir(): string {
  const home = Deno.env.get("HOME") ?? "/tmp";
  if (Deno.build.os === "darwin") return joinPath(home, "Library", "Caches", "galley-bindings", "js-deno", "capi");
  if (Deno.build.os === "windows") {
    const base = Deno.env.get("LOCALAPPDATA") ?? Deno.env.get("TMPDIR") ?? home;
    return joinPath(base, "galley-bindings", "js-deno", "capi");
  }
  const base = Deno.env.get("XDG_CACHE_HOME") ?? joinPath(home, ".cache");
  return joinPath(base, "galley-bindings", "js-deno", "capi");
}

export function findLibrary(explicit?: string): string {
  if (explicit && exists(explicit)) return explicit;
  const envPath = Deno.env.get("GALLEY_LIBRARY_PATH");
  if (envPath && exists(envPath)) return envPath;
  // 1) cwd / language-dir copies (build.ts copies lib next to grammar)
  for (const candidate of [
    joinPath(Deno.cwd(), libFileName()),
    joinPath(Deno.cwd(), "libgalley-js-deno.dylib"),
    joinPath(Deno.cwd(), "libgalley-js-deno.so"),
  ]) {
    if (exists(candidate)) return candidate;
  }
  // 2) cache dir (same as build.ts prefix)
  const cacheLib = joinPath(defaultCacheDir(), "lib", libFileName());
  if (exists(cacheLib)) return cacheLib;
  // 3) sibling examples/js/deno for development (from src/, three levels up)
  try {
    const here = new URL(".", import.meta.url).pathname;
    for (const candidate of [
      joinPath(here, "../../../../examples/js/deno", libFileName()),
      joinPath(here, "../../../../../examples/js/deno", libFileName()),
    ]) {
      if (exists(candidate)) return candidate;
    }
  } catch {
    // ignore URL parsing errors
  }
  // fallback: let dlopen error with cache path
  return cacheLib;
}

// --- loader ------------------------------------------------------------

const BASE_SYMBOLS = {
  galley_version: { parameters: [], result: "pointer" },
  galley_parser_type: { parameters: [], result: "i64" },
  galley_error_recovery_mode: { parameters: [], result: "i64" },
  galley_has_ast: { parameters: [], result: "i32" },
  galley_has_procedures: { parameters: [], result: "i32" },
  galley_allows_no_ast_tree_procedures: { parameters: [], result: "i32" },
  galley_source_retention_enabled: { parameters: [], result: "i32" },
  galley_has_position_tracking: { parameters: [], result: "i32" },
  galley_has_input_streaming: { parameters: [], result: "i32" },
  galley_uses_verbatim: { parameters: [], result: "i32" },
  galley_stack_overflow_recovery_available: { parameters: [], result: "i32" },
  galley_symbol_count: { parameters: [], result: "u64" },
  galley_variable_count: { parameters: [], result: "u64" },
  galley_status_string: { parameters: ["i64"], result: "pointer" },
  galley_symbol_name: { parameters: ["pointer", "u64", "buffer", "buffer"], result: "i64" },
  galley_symbol_is_terminal: { parameters: ["pointer", "u64"], result: "i32" },
  galley_variable_name: { parameters: ["pointer", "u64", "buffer", "buffer"], result: "i64" },
  galley_session_create: { parameters: [], result: "pointer" },
  galley_session_create_ex: { parameters: ["buffer"], result: "pointer" },
  galley_session_destroy: { parameters: ["pointer"], result: "void" },
  galley_session_set_message_override: { parameters: ["pointer", "buffer", "usize", "buffer", "usize"], result: "i64" },
  galley_parse: { parameters: ["pointer", "buffer", "usize"], result: "i64" },
  galley_parse_file: { parameters: ["pointer", "buffer"], result: "i64" },
  galley_last_position: { parameters: ["pointer", "buffer", "buffer"], result: "i64" },
  galley_node_count: { parameters: ["pointer"], result: "u64" },
  galley_reserve_nodes: { parameters: ["pointer", "u64"], result: "i64" },
  galley_node_capacity: { parameters: ["pointer"], result: "u64" },
  galley_root_node: { parameters: ["pointer"], result: "u64" },
  galley_node_is_valid: { parameters: ["pointer", "u64"], result: "i32" },
  galley_node_child_count: { parameters: ["pointer", "u64"], result: "u32" },
  galley_node_first_child: { parameters: ["pointer", "u64"], result: "u64" },
  galley_node_last_child: { parameters: ["pointer", "u64"], result: "u64" },
  galley_node_next_sibling: { parameters: ["pointer", "u64"], result: "u64" },
  galley_node_prior_sibling: { parameters: ["pointer", "u64"], result: "u64" },
  galley_node_parent: { parameters: ["pointer", "u64"], result: "u64" },
  galley_walker_create: { parameters: ["pointer", "u64", "i32"], result: "pointer" },
  galley_walker_next: { parameters: ["pointer", "buffer", "buffer", "buffer"], result: "i32" },
  galley_walker_skip_children: { parameters: ["pointer"], result: "void" },
  galley_walker_destroy: { parameters: ["pointer"], result: "void" },
  galley_node_span: { parameters: ["pointer", "u64", "buffer", "buffer"], result: "i64" },
  galley_node_symbol_name: { parameters: ["pointer", "u64", "buffer", "buffer"], result: "i64" },
  galley_node_variable_index: { parameters: ["pointer", "u64"], result: "i64" },
  galley_node_text: { parameters: ["pointer", "u64", "buffer", "buffer"], result: "i64" },
  galley_node_line_column: { parameters: ["pointer", "u64", "buffer", "buffer"], result: "i64" },
  galley_has_diagnostic: { parameters: ["pointer"], result: "i32" },
  galley_diagnostic_kind: { parameters: ["pointer"], result: "i64" },
  galley_diagnostic_message: { parameters: ["pointer", "buffer"], result: "i64" },
  galley_diagnostic_message_ansi: { parameters: ["pointer", "buffer"], result: "i64" },
  galley_diagnostic_position: { parameters: ["pointer", "buffer", "buffer"], result: "i64" },
  galley_diagnostic_unexpected_token: { parameters: ["pointer", "buffer", "buffer"], result: "i64" },
  galley_diagnostic_expected_count: { parameters: ["pointer"], result: "i64" },
  galley_diagnostic_expected_at: { parameters: ["pointer", "u64", "buffer", "buffer"], result: "i64" },
  galley_diagnostic_context_count: { parameters: ["pointer"], result: "i64" },
  galley_diagnostic_context_at: { parameters: ["pointer", "u64", "buffer", "buffer"], result: "i64" },
  galley_diagnostic_indentation: { parameters: ["pointer", "buffer", "buffer"], result: "i64" },
  galley_syntax_error_count: { parameters: ["pointer"], result: "i64" },
  galley_semantic_error_count: { parameters: ["pointer"], result: "i64" },
  galley_diagnostic_semantic: { parameters: ["pointer", "buffer", "buffer", "buffer", "buffer"], result: "i64" },
  galley_diagnostic_recovery_kind: { parameters: ["pointer"], result: "i64" },
  galley_diagnostic_recovery_terminal: { parameters: ["pointer", "buffer", "buffer"], result: "i64" },
  galley_diagnostic_recovery_resume: { parameters: ["pointer", "buffer"], result: "i64" },
  galley_diagnostic_recovery_lhs_variable: { parameters: ["pointer", "buffer", "buffer"], result: "i64" },
  galley_diagnostic_recovery_production: { parameters: ["pointer", "buffer", "buffer", "buffer"], result: "i64" },
  galley_diagnostic_recovery_occurrence: { parameters: ["pointer", "buffer", "buffer", "buffer", "buffer", "buffer", "buffer"], result: "i64" },
  galley_recorded_diagnostic_count: { parameters: ["pointer"], result: "i64" },
  galley_recorded_diagnostic_kind: { parameters: ["pointer", "u64"], result: "i64" },
  galley_recorded_diagnostic_position: { parameters: ["pointer", "u64", "buffer", "buffer"], result: "i64" },
  galley_recorded_unexpected_token: { parameters: ["pointer", "u64", "buffer", "buffer"], result: "i64" },
  galley_recorded_diagnostic_message: { parameters: ["pointer", "u64", "buffer"], result: "i64" },
  galley_recorded_indentation: { parameters: ["pointer", "u64", "buffer", "buffer"], result: "i64" },
  galley_recorded_semantic: { parameters: ["pointer", "u64", "buffer", "buffer", "buffer", "buffer"], result: "i64" },
  galley_recorded_expected_count: { parameters: ["pointer", "u64"], result: "i64" },
  galley_recorded_expected_token: { parameters: ["pointer", "u64", "u64", "buffer", "buffer"], result: "i64" },
  galley_recorded_context_count: { parameters: ["pointer", "u64"], result: "i64" },
  galley_recorded_context_name: { parameters: ["pointer", "u64", "u64", "buffer", "buffer"], result: "i64" },
  // NB: the implementation exports galley_recorded_diagnostic_recovery_kind
  // (the header's shorter name is stale); `name` maps to the true symbol.
  galley_recorded_recovery_kind: { name: "galley_recorded_diagnostic_recovery_kind", parameters: ["pointer", "u64"], result: "i64" },
  galley_recorded_recovery_terminal: { parameters: ["pointer", "u64", "buffer", "buffer"], result: "i64" },
  galley_recorded_recovery_resume: { parameters: ["pointer", "u64", "buffer"], result: "i64" },
  galley_recorded_recovery_lhs_variable: { parameters: ["pointer", "u64", "buffer", "buffer"], result: "i64" },
  galley_recorded_recovery_production: { parameters: ["pointer", "u64", "buffer", "buffer", "buffer"], result: "i64" },
  galley_recorded_recovery_occurrence: { parameters: ["pointer", "u64", "buffer", "buffer", "buffer", "buffer", "buffer", "buffer"], result: "i64" },
  galley_tree_append_children: { parameters: ["pointer", "u64", "u64"], result: "i64" },
  galley_tree_insert_before: { parameters: ["pointer", "u64", "u64"], result: "i64" },
  galley_tree_insert_after: { parameters: ["pointer", "u64", "u64"], result: "i64" },
  galley_tree_remove_siblings: { parameters: ["pointer", "u64", "usize", "buffer"], result: "i64" },
  galley_tree_remove_self: { parameters: ["pointer", "u64", "buffer"], result: "i64" },
  galley_tree_promote_children_over_wrapper: { parameters: ["pointer", "u64", "buffer"], result: "i64" },
  galley_tree_clean_children: { parameters: ["pointer", "u64", "buffer"], result: "i64" },
  galley_tree_unlink_wrapper: { parameters: ["pointer", "u64"], result: "i64" },
  galley_tree_insert_children_at: { parameters: ["pointer", "u64", "usize", "u64"], result: "i64" },
  galley_tree_remove_children_at: { parameters: ["pointer", "u64", "usize", "usize", "buffer"], result: "i64" },
  galley_procedure_session: { parameters: ["pointer"], result: "pointer" },
  galley_procedure_current_node: { parameters: ["pointer"], result: "u64" },
  galley_procedure_set_current_node: { parameters: ["pointer", "u64"], result: "void" },
  galley_procedure_drop_self: { parameters: ["pointer"], result: "i64" },
  galley_procedure_drop_children: { parameters: ["pointer"], result: "i64" },
  galley_procedure_drop_if_empty: { parameters: ["pointer"], result: "i64" },
  galley_procedure_replace_with_children: { parameters: ["pointer"], result: "i64" },
  galley_procedure_context_line: { parameters: ["pointer"], result: "u32" },
  galley_procedure_context_column: { parameters: ["pointer"], result: "u32" },
  galley_procedure_report_semantic_error: { parameters: ["pointer", "buffer", "usize"], result: "i64" },
} as const;

const DISPATCH_SYMBOL = {
  galley_install_js_dispatch: { parameters: ["function"], result: "void" },
} as const;

function openNative(libPath: string, withDispatch: boolean) {
  return Deno.dlopen(libPath, withDispatch ? { ...BASE_SYMBOLS, ...DISPATCH_SYMBOL } : BASE_SYMBOLS);
}

// --- read helpers ----------------------------------------------------------

function readBytes(addr: bigint, len: bigint): Uint8Array {
  if (addr === 0n || len === 0n) return new Uint8Array(0);
  const ptr = Deno.UnsafePointer.create(addr);
  if (ptr === null) return new Uint8Array(0);
  const view = new Deno.UnsafePointerView(ptr);
  // slice(0) copies: the native memory dies on the next parse.
  return new Uint8Array(view.getArrayBuffer(Number(len)).slice(0));
}

function readCString(ptr: Deno.PointerValue): string | null {
  if (ptr === null) return null;
  return new Deno.UnsafePointerView(ptr).getCString();
}

function ptrOut(): BigUint64Array {
  return new BigUint64Array(1);
}

function lenOut(): BigUint64Array {
  return new BigUint64Array(1);
}

function u32Out(): Uint32Array {
  return new Uint32Array(1);
}

function i64Out(): BigInt64Array {
  return new BigInt64Array(1);
}

// --- FfiPort implementation ----------------------------------------------

export class DenoPort implements FfiPort {
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
    return readCString(this.native.galley_version()) ?? "";
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
    return readCString(this.native.galley_status_string(BigInt(status)));
  }

  // -- sessions ---------------------------------------------------------

  createSession(options: SessionCOptions | null): Handle {
    let handle: Deno.PointerValue;
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
      handle = this.native.galley_session_create_ex(new Uint8Array(buf));
    }
    if (handle === null) return null;
    return handle;
  }

  destroySession(handle: Handle): void {
    this.native.galley_session_destroy(handle as Deno.PointerValue);
  }

  setMessageOverride(handle: Handle, name: Uint8Array, message: Uint8Array): number {
    return Number(
      this.native.galley_session_set_message_override(handle as Deno.PointerValue, name, name.length, message, message.length),
    );
  }

  // -- parsing ----------------------------------------------------------

  parse(handle: Handle, data: Uint8Array): number {
    return Number(this.native.galley_parse(handle as Deno.PointerValue, data, data.length));
  }

  parseFile(handle: Handle, filePath: string): number {
    const bytes = textEncoder.encode(filePath);
    const nul = new Uint8Array(bytes.length + 1);
    nul.set(bytes);
    return Number(this.native.galley_parse_file(handle as Deno.PointerValue, nul));
  }

  lastPosition(handle: Handle): [number, number] | null {
    const outLine = u32Out();
    const outCol = u32Out();
    if (this.native.galley_last_position(handle as Deno.PointerValue, outLine, outCol) < 0n) return null;
    return [outLine[0], outCol[0]];
  }

  // -- arena and navigation ----------------------------------------------

  nodeCount(handle: Handle): number {
    return Number(this.native.galley_node_count(handle as Deno.PointerValue));
  }

  reserveNodes(handle: Handle, capacity: bigint): number {
    return Number(this.native.galley_reserve_nodes(handle as Deno.PointerValue, capacity));
  }

  nodeCapacity(handle: Handle): number {
    return Number(this.native.galley_node_capacity(handle as Deno.PointerValue));
  }

  rootNode(handle: Handle): bigint {
    return this.native.galley_root_node(handle as Deno.PointerValue);
  }

  nodeValid(handle: Handle, node: bigint): boolean {
    return this.native.galley_node_is_valid(handle as Deno.PointerValue, node) !== 0;
  }

  childCount(handle: Handle, node: bigint): number {
    return this.native.galley_node_child_count(handle as Deno.PointerValue, node);
  }

  firstChild(handle: Handle, node: bigint): bigint {
    return this.native.galley_node_first_child(handle as Deno.PointerValue, node);
  }

  lastChild(handle: Handle, node: bigint): bigint {
    return this.native.galley_node_last_child(handle as Deno.PointerValue, node);
  }

  nextSibling(handle: Handle, node: bigint): bigint {
    return this.native.galley_node_next_sibling(handle as Deno.PointerValue, node);
  }

  priorSibling(handle: Handle, node: bigint): bigint {
    return this.native.galley_node_prior_sibling(handle as Deno.PointerValue, node);
  }

  parent(handle: Handle, node: bigint): bigint {
    return this.native.galley_node_parent(handle as Deno.PointerValue, node);
  }

  // -- walker ------------------------------------------------------------

  walkerCreate(handle: Handle, node: bigint, skipSemanticErrors: boolean): Handle | null {
    const walker = this.native.galley_walker_create(handle as Deno.PointerValue, node, skipSemanticErrors ? 1 : 0);
    if (walker === null) return null;
    return walker;
  }

  walkerNext(walker: Handle): WalkedStep | null {
    const outNode = lenOut();
    const outDepth = u32Out();
    const outFlag = u32Out();
    if (this.native.galley_walker_next(walker as Deno.PointerValue, outNode, outDepth, outFlag) === 0) return null;
    return { node: outNode[0], depth: outDepth[0], isSemanticError: outFlag[0] !== 0 };
  }

  walkerSkipChildren(walker: Handle): void {
    this.native.galley_walker_skip_children(walker as Deno.PointerValue);
  }

  walkerDestroy(walker: Handle): void {
    this.native.galley_walker_destroy(walker as Deno.PointerValue);
  }

  // -- node accessors -----------------------------------------------------

  #tryCopyBytes(fn: (outData: BigUint64Array, outLen: BigUint64Array) => bigint): Uint8Array | null {
    const outData = ptrOut();
    const outLen = lenOut();
    if (fn(outData, outLen) < 0n) return null;
    if (outData[0] === 0n) return null;
    return readBytes(outData[0], outLen[0]);
  }

  #readSemanticPair(
    fn: (outVariable: BigUint64Array, outVariableLen: BigUint64Array, outMessage: BigUint64Array, outMessageLen: BigUint64Array) => bigint,
  ): [string, string] | null {
    const outVariable = ptrOut();
    const outVariableLen = lenOut();
    const outMessage = ptrOut();
    const outMessageLen = lenOut();
    if (fn(outVariable, outVariableLen, outMessage, outMessageLen) < 0n) return null;
    if (outVariable[0] === 0n || outMessage[0] === 0n) return null;
    return [
      textDecoder.decode(readBytes(outVariable[0], outVariableLen[0])),
      textDecoder.decode(readBytes(outMessage[0], outMessageLen[0])),
    ];
  }

  nodeSymbolName(handle: Handle, node: bigint): Uint8Array | null {
    const h = handle as Deno.PointerValue;
    const outData = ptrOut();
    const outLen = lenOut();
    if (this.native.galley_node_symbol_name(h, node, outData, outLen) < 0n) return null;
    return readBytes(outData[0], outLen[0]);
  }

  nodeText(handle: Handle, node: bigint): Uint8Array | null {
    const h = handle as Deno.PointerValue;
    const outData = ptrOut();
    const outLen = lenOut();
    if (this.native.galley_node_text(h, node, outData, outLen) < 0n) return null;
    return readBytes(outData[0], outLen[0]);
  }

  nodeSpan(handle: Handle, node: bigint): [bigint, bigint] | null {
    const outStart = lenOut();
    const outLen = lenOut();
    if (this.native.galley_node_span(handle as Deno.PointerValue, node, outStart, outLen) < 0n) return null;
    return [outStart[0], outLen[0]];
  }

  nodeLineColumn(handle: Handle, node: bigint): [number, number] | null {
    const outLine = u32Out();
    const outCol = u32Out();
    if (this.native.galley_node_line_column(handle as Deno.PointerValue, node, outLine, outCol) < 0n) return null;
    return [outLine[0], outCol[0]];
  }

  nodeVariableIndex(handle: Handle, node: bigint): number {
    return Number(this.native.galley_node_variable_index(handle as Deno.PointerValue, node));
  }

  symbolNameAt(handle: Handle, index: number): Uint8Array | null {
    const h = handle as Deno.PointerValue;
    const outData = ptrOut();
    const outLen = lenOut();
    if (this.native.galley_symbol_name(h, BigInt(index), outData, outLen) < 0n) return null;
    return readBytes(outData[0], outLen[0]);
  }

  symbolIsTerminal(handle: Handle, index: number): boolean {
    return this.native.galley_symbol_is_terminal(handle as Deno.PointerValue, BigInt(index)) !== 0;
  }

  variableNameAt(handle: Handle, index: number): Uint8Array | null {
    const h = handle as Deno.PointerValue;
    const outData = ptrOut();
    const outLen = lenOut();
    if (this.native.galley_variable_name(h, BigInt(index), outData, outLen) < 0n) return null;
    return readBytes(outData[0], outLen[0]);
  }

  // -- diagnostics ---------------------------------------------------------

  hasDiagnostic(handle: Handle): boolean {
    return this.native.galley_has_diagnostic(handle as Deno.PointerValue) !== 0;
  }

  diagnosticKind(handle: Handle): number {
    return Number(this.native.galley_diagnostic_kind(handle as Deno.PointerValue));
  }

  diagnosticMessage(handle: Handle): string | null {
    const out = ptrOut();
    if (this.native.galley_diagnostic_message(handle as Deno.PointerValue, out) !== 0n) return null;
    return readCString(Deno.UnsafePointer.create(out[0]));
  }

  diagnosticMessageAnsi(handle: Handle): string | null {
    const out = ptrOut();
    if (this.native.galley_diagnostic_message_ansi(handle as Deno.PointerValue, out) !== 0n) return null;
    return readCString(Deno.UnsafePointer.create(out[0]));
  }

  diagnosticPosition(handle: Handle): [number, number] | null {
    const outLine = u32Out();
    const outCol = u32Out();
    if (this.native.galley_diagnostic_position(handle as Deno.PointerValue, outLine, outCol) < 0n) return null;
    return [outLine[0], outCol[0]];
  }

  diagnosticUnexpectedToken(handle: Handle): Uint8Array | null {
    const h = handle as Deno.PointerValue;
    return this.#tryCopyBytes((od, ol) => this.native.galley_diagnostic_unexpected_token(h, od, ol));
  }

  diagnosticExpectedCount(handle: Handle): number {
    return Number(this.native.galley_diagnostic_expected_count(handle as Deno.PointerValue));
  }

  diagnosticExpectedAt(handle: Handle, index: number): Uint8Array | null {
    const h = handle as Deno.PointerValue;
    return this.#tryCopyBytes((od, ol) => this.native.galley_diagnostic_expected_at(h, BigInt(index), od, ol));
  }

  diagnosticContextCount(handle: Handle): number {
    return Number(this.native.galley_diagnostic_context_count(handle as Deno.PointerValue));
  }

  diagnosticContextAt(handle: Handle, index: number): Uint8Array | null {
    const h = handle as Deno.PointerValue;
    return this.#tryCopyBytes((od, ol) => this.native.galley_diagnostic_context_at(h, BigInt(index), od, ol));
  }

  syntaxErrorCount(handle: Handle): number {
    return Number(this.native.galley_syntax_error_count(handle as Deno.PointerValue));
  }

  semanticErrorCount(handle: Handle): number {
    return Number(this.native.galley_semantic_error_count(handle as Deno.PointerValue));
  }

  diagnosticSemantic(handle: Handle): [string, string] | null {
    const h = handle as Deno.PointerValue;
    return this.#readSemanticPair((ov, ovl, om, oml) => this.native.galley_diagnostic_semantic(h, ov, ovl, om, oml));
  }

  diagnosticIndentation(handle: Handle): [number, number] | null {
    const outSpaces = u32Out();
    const outWidth = u32Out();
    if (this.native.galley_diagnostic_indentation(handle as Deno.PointerValue, outSpaces, outWidth) !== 0n) return null;
    return [outSpaces[0], outWidth[0]];
  }

  diagnosticRecoveryKind(handle: Handle): number {
    return Number(this.native.galley_diagnostic_recovery_kind(handle as Deno.PointerValue));
  }

  diagnosticRecoveryTerminal(handle: Handle): Uint8Array | null {
    const h = handle as Deno.PointerValue;
    return this.#tryCopyBytes((od, ol) => this.native.galley_diagnostic_recovery_terminal(h, od, ol));
  }

  diagnosticRecoveryResume(handle: Handle): number | null {
    const out = i64Out();
    if (this.native.galley_diagnostic_recovery_resume(handle as Deno.PointerValue, out) !== 0n) return null;
    return Number(out[0]);
  }

  diagnosticRecoveryLhsVariable(handle: Handle): string | null {
    const h = handle as Deno.PointerValue;
    const outData = ptrOut();
    const outLen = lenOut();
    if (this.native.galley_diagnostic_recovery_lhs_variable(h, outData, outLen) < 0n || outData[0] === 0n) return null;
    return textDecoder.decode(readBytes(outData[0], outLen[0]));
  }

  diagnosticRecoveryProduction(handle: Handle): [string, number] | null {
    const h = handle as Deno.PointerValue;
    const outVar = ptrOut();
    const outLen = lenOut();
    const outIdx = u32Out();
    if (this.native.galley_diagnostic_recovery_production(h, outVar, outLen, outIdx) !== 0n) return null;
    return [textDecoder.decode(readBytes(outVar[0], outLen[0])), outIdx[0]];
  }

  diagnosticRecoveryOccurrence(handle: Handle): [string, number, number, string] | null {
    const h = handle as Deno.PointerValue;
    const outParent = ptrOut();
    const outParentLen = lenOut();
    const outRhs = u32Out();
    const outSym = u32Out();
    const outVar = ptrOut();
    const outVarLen = lenOut();
    if (this.native.galley_diagnostic_recovery_occurrence(h, outParent, outParentLen, outRhs, outSym, outVar, outVarLen) !== 0n) return null;
    return [
      textDecoder.decode(readBytes(outParent[0], outParentLen[0])),
      outRhs[0],
      outSym[0],
      textDecoder.decode(readBytes(outVar[0], outVarLen[0])),
    ];
  }

  recordedDiagnosticCount(handle: Handle): number {
    return Number(this.native.galley_recorded_diagnostic_count(handle as Deno.PointerValue));
  }

  recordedDiagnosticKind(handle: Handle, diagIndex: number): number {
    return Number(this.native.galley_recorded_diagnostic_kind(handle as Deno.PointerValue, BigInt(diagIndex)));
  }

  recordedDiagnosticPosition(handle: Handle, diagIndex: number): [number, number] | null {
    const outLine = u32Out();
    const outCol = u32Out();
    if (this.native.galley_recorded_diagnostic_position(handle as Deno.PointerValue, BigInt(diagIndex), outLine, outCol) < 0n) return null;
    return [outLine[0], outCol[0]];
  }

  recordedUnexpectedToken(handle: Handle, diagIndex: number): Uint8Array | null {
    const h = handle as Deno.PointerValue;
    const d = BigInt(diagIndex);
    return this.#tryCopyBytes((od, ol) => this.native.galley_recorded_unexpected_token(h, d, od, ol));
  }

  recordedDiagnosticMessage(handle: Handle, diagIndex: number): string | null {
    const out = ptrOut();
    if (this.native.galley_recorded_diagnostic_message(handle as Deno.PointerValue, BigInt(diagIndex), out) !== 0n) return null;
    return readCString(Deno.UnsafePointer.create(out[0]));
  }

  recordedIndentation(handle: Handle, diagIndex: number): [number, number] | null {
    const outSpaces = u32Out();
    const outWidth = u32Out();
    if (this.native.galley_recorded_indentation(handle as Deno.PointerValue, BigInt(diagIndex), outSpaces, outWidth) !== 0n) return null;
    return [outSpaces[0], outWidth[0]];
  }

  recordedSemantic(handle: Handle, diagIndex: number): [string, string] | null {
    const h = handle as Deno.PointerValue;
    const d = BigInt(diagIndex);
    return this.#readSemanticPair((ov, ovl, om, oml) => this.native.galley_recorded_semantic(h, d, ov, ovl, om, oml));
  }

  recordedExpectedCount(handle: Handle, diagIndex: number): number {
    return Number(this.native.galley_recorded_expected_count(handle as Deno.PointerValue, BigInt(diagIndex)));
  }

  recordedExpectedToken(handle: Handle, diagIndex: number, tokenIndex: number): Uint8Array | null {
    const h = handle as Deno.PointerValue;
    const d = BigInt(diagIndex);
    const t = BigInt(tokenIndex);
    return this.#tryCopyBytes((od, ol) => this.native.galley_recorded_expected_token(h, d, t, od, ol));
  }

  recordedContextCount(handle: Handle, diagIndex: number): number {
    return Number(this.native.galley_recorded_context_count(handle as Deno.PointerValue, BigInt(diagIndex)));
  }

  recordedContextName(handle: Handle, diagIndex: number, contextIndex: number): Uint8Array | null {
    const h = handle as Deno.PointerValue;
    const d = BigInt(diagIndex);
    const c = BigInt(contextIndex);
    return this.#tryCopyBytes((od, ol) => this.native.galley_recorded_context_name(h, d, c, od, ol));
  }

  recordedRecoveryKind(handle: Handle, diagIndex: number): number {
    return Number(this.native.galley_recorded_recovery_kind(handle as Deno.PointerValue, BigInt(diagIndex)));
  }

  recordedRecoveryTerminal(handle: Handle, diagIndex: number): Uint8Array | null {
    const h = handle as Deno.PointerValue;
    const d = BigInt(diagIndex);
    return this.#tryCopyBytes((od, ol) => this.native.galley_recorded_recovery_terminal(h, d, od, ol));
  }

  recordedRecoveryResume(handle: Handle, diagIndex: number): number | null {
    const out = i64Out();
    if (this.native.galley_recorded_recovery_resume(handle as Deno.PointerValue, BigInt(diagIndex), out) !== 0n) return null;
    return Number(out[0]);
  }

  recordedRecoveryLhsVariable(handle: Handle, diagIndex: number): string | null {
    const h = handle as Deno.PointerValue;
    const d = BigInt(diagIndex);
    const outData = ptrOut();
    const outLen = lenOut();
    if (this.native.galley_recorded_recovery_lhs_variable(h, d, outData, outLen) < 0n || outData[0] === 0n) return null;
    return textDecoder.decode(readBytes(outData[0], outLen[0]));
  }

  recordedRecoveryProduction(handle: Handle, diagIndex: number): [string, number] | null {
    const h = handle as Deno.PointerValue;
    const d = BigInt(diagIndex);
    const outVar = ptrOut();
    const outLen = lenOut();
    const outIdx = u32Out();
    if (this.native.galley_recorded_recovery_production(h, d, outVar, outLen, outIdx) !== 0n) return null;
    return [textDecoder.decode(readBytes(outVar[0], outLen[0])), outIdx[0]];
  }

  recordedRecoveryOccurrence(handle: Handle, diagIndex: number): [string, number, number, string] | null {
    const h = handle as Deno.PointerValue;
    const d = BigInt(diagIndex);
    const outParent = ptrOut();
    const outParentLen = lenOut();
    const outRhs = u32Out();
    const outSym = u32Out();
    const outVar = ptrOut();
    const outVarLen = lenOut();
    if (this.native.galley_recorded_recovery_occurrence(h, d, outParent, outParentLen, outRhs, outSym, outVar, outVarLen) !== 0n) return null;
    return [
      textDecoder.decode(readBytes(outParent[0], outParentLen[0])),
      outRhs[0],
      outSym[0],
      textDecoder.decode(readBytes(outVar[0], outVarLen[0])),
    ];
  }

  // -- tree editing ----------------------------------------------------------

  treeAppendChildren(handle: Handle, parent: bigint, first: bigint): number {
    return Number(this.native.galley_tree_append_children(handle as Deno.PointerValue, parent, first));
  }

  treeInsertBefore(handle: Handle, target: bigint, first: bigint): number {
    return Number(this.native.galley_tree_insert_before(handle as Deno.PointerValue, target, first));
  }

  treeInsertAfter(handle: Handle, target: bigint, first: bigint): number {
    return Number(this.native.galley_tree_insert_after(handle as Deno.PointerValue, target, first));
  }

  treeRemoveSiblings(handle: Handle, node: bigint, count: number): { status: number; head: bigint } {
    const outHead = lenOut();
    const st = this.native.galley_tree_remove_siblings(handle as Deno.PointerValue, node, count, outHead);
    return { status: Number(st), head: outHead[0] };
  }

  treeRemoveSelf(handle: Handle, node: bigint): { status: number; head: bigint } {
    const outHead = lenOut();
    const st = this.native.galley_tree_remove_self(handle as Deno.PointerValue, node, outHead);
    return { status: Number(st), head: outHead[0] };
  }

  treePromoteChildrenOverWrapper(handle: Handle, wrapper: bigint): { status: number; head: bigint } {
    const outHead = lenOut();
    const st = this.native.galley_tree_promote_children_over_wrapper(handle as Deno.PointerValue, wrapper, outHead);
    return { status: Number(st), head: outHead[0] };
  }

  treeCleanChildren(handle: Handle, node: bigint): { status: number; head: bigint } {
    const outHead = lenOut();
    const st = this.native.galley_tree_clean_children(handle as Deno.PointerValue, node, outHead);
    return { status: Number(st), head: outHead[0] };
  }

  treeUnlinkWrapper(handle: Handle, wrapper: bigint): number {
    return Number(this.native.galley_tree_unlink_wrapper(handle as Deno.PointerValue, wrapper));
  }

  treeInsertChildrenAt(handle: Handle, parent: bigint, index: number, first: bigint): number {
    return Number(this.native.galley_tree_insert_children_at(handle as Deno.PointerValue, parent, index, first));
  }

  treeRemoveChildrenAt(handle: Handle, parent: bigint, index: number, count: number): { status: number; head: bigint } {
    const outHead = lenOut();
    const st = this.native.galley_tree_remove_children_at(handle as Deno.PointerValue, parent, index, count, outHead);
    return { status: Number(st), head: outHead[0] };
  }

  // -- procedure hooks ----------------------------------------------------------

  procCurrentNode(args: Handle): bigint {
    return this.native.galley_procedure_current_node(args as Deno.PointerValue);
  }

  procSetCurrentNode(args: Handle, node: bigint): void {
    this.native.galley_procedure_set_current_node(args as Deno.PointerValue, node);
  }

  procDropSelf(args: Handle): number {
    return Number(this.native.galley_procedure_drop_self(args as Deno.PointerValue));
  }

  procDropChildren(args: Handle): number {
    return Number(this.native.galley_procedure_drop_children(args as Deno.PointerValue));
  }

  procDropIfEmpty(args: Handle): number {
    return Number(this.native.galley_procedure_drop_if_empty(args as Deno.PointerValue));
  }

  procReplaceWithChildren(args: Handle): number {
    return Number(this.native.galley_procedure_replace_with_children(args as Deno.PointerValue));
  }

  procContextLine(args: Handle): number {
    return this.native.galley_procedure_context_line(args as Deno.PointerValue);
  }

  procContextColumn(args: Handle): number {
    return this.native.galley_procedure_context_column(args as Deno.PointerValue);
  }

  procReportSemanticError(args: Handle, message: Uint8Array): number {
    return Number(
      this.native.galley_procedure_report_semantic_error(args as Deno.PointerValue, message, message.length),
    );
  }
}

const portCache = new Map<string, DenoPort>();

/** Port for the library at `explicitPath` (or default discovery), cached per path. */
export function getDenoPort(explicitPath?: string): DenoPort {
  const libPath = findLibrary(explicitPath);
  const cached = portCache.get(libPath);
  if (cached) return cached;
  // Libraries built for C procedures lack the JS dispatch symbol; dlopen
  // fails on missing symbols, so fall back to a dispatch-less table.
  let native: GalleySymbols;
  let supportsDispatch = true;
  try {
    native = openNative(libPath, true).symbols as unknown as GalleySymbols;
  } catch {
    native = openNative(libPath, false).symbols as unknown as GalleySymbols;
    supportsDispatch = false;
  }
  const port = new DenoPort(native, libPath, supportsDispatch);
  portCache.set(libPath, port);
  return port;
}
