/**
 * Bun adapter for the Galley JavaScript bindings: `bun:ffi` bindings over
 * `bindings/c/galley.h`, implementing the core `FfiPort`.
 *
 * Zero npm dependencies: `bun:ffi` is built into the runtime. The core
 * (`@sanbus/galley-core`) owns all session logic; memory copying and integer
 * normalization live here. Library discovery mirrors the Node adapter.
 */

import { Buffer } from "node:buffer";
import * as fs from "node:fs";
import * as path from "node:path";
import process from "node:process";
import { dlopen, FFIType, ptr, toArrayBuffer, CString } from "bun:ffi";
import type { FfiPort, NodeFamily, CurrentDiagnosticFamily, Handle, StagedHandle, HookTicket, DispatchHandler, SessionCOptions, SnapshotColumns } from "@sanbus/galley-core";
import { GalleyError, INVALID_NODE, NATIVE_LITTLE_ENDIAN, NO_VARIABLE, Status } from "@sanbus/galley-core";
import { resolveArtifactFile, resolveAdapterArtifact, artifactFileName, canonicalResolvePath, SHARED_NATIVE_LIBRARY_BASE } from "@sanbus/galley-core/internal";
import { installDispatch } from "./dispatch.ts";

/** Native handles are addresses; 0 is null. */
type NativeHandle = number;

/** Callable view of the native symbols (see `BASE_SYMBOLS` below). */
/**
 * The node, tree and walk calls both doors expose, keyed by the C name after
 * `galley_`. Each is declared once here and once in `DOOR_SYMBOLS`, and bound
 * twice: `galley_<name>` over a session handle and `galley_hook_<name>` over
 * a parse's door, with identical signatures.
 */
interface DoorCalls {
  node_child_count(handle: NativeHandle, generation: number, node: bigint): number;
  node_first_child(handle: NativeHandle, generation: number, node: bigint): number | bigint;
  node_last_child(handle: NativeHandle, generation: number, node: bigint): number | bigint;
  node_next_sibling(handle: NativeHandle, generation: number, node: bigint): number | bigint;
  node_prior_sibling(handle: NativeHandle, generation: number, node: bigint): number | bigint;
  node_parent(handle: NativeHandle, generation: number, node: bigint): number | bigint;
  node_span(handle: NativeHandle, generation: number, node: bigint, outStart: number, outLen: number): bigint;
  node_symbol_name(handle: NativeHandle, generation: number, node: bigint, outData: number, outLen: number): bigint;
  node_variable_index(handle: NativeHandle, generation: number, node: bigint): bigint;
  node_text(handle: NativeHandle, generation: number, node: bigint, outData: number, outLen: number): bigint;
  node_line_column(handle: NativeHandle, generation: number, node: bigint, outLine: number, outCol: number): bigint;
  walk_next(handle: NativeHandle, cursor: number): bigint;
  tree_append_children(handle: NativeHandle, generation: number, parent: bigint, firstGeneration: number, first: bigint): bigint;
  tree_insert_before(handle: NativeHandle, generation: number, target: bigint, firstGeneration: number, first: bigint): bigint;
  tree_insert_after(handle: NativeHandle, generation: number, target: bigint, firstGeneration: number, first: bigint): bigint;
  tree_remove_siblings(handle: NativeHandle, generation: number, node: bigint, count: bigint, outHead: number): bigint;
  tree_remove_self(handle: NativeHandle, generation: number, node: bigint, outHead: number): bigint;
  tree_clean_children(handle: NativeHandle, generation: number, node: bigint, outHead: number): bigint;
  tree_insert_children_at(handle: NativeHandle, generation: number, parent: bigint, index: bigint, firstGeneration: number, first: bigint): bigint;
  tree_remove_children_at(handle: NativeHandle, generation: number, parent: bigint, index: bigint, count: bigint, outHead: number): bigint;
}

/** `DoorCalls` under one door's C names: `galley_<name>` or `galley_hook_<name>`. */
type DoorNames<Door extends "" | "hook_"> = {
  [Name in keyof DoorCalls as `galley_${Door}${Name & string}`]: DoorCalls[Name];
};

/**
 * The current-diagnostic calls both doors expose, keyed by the C name after
 * `galley_`: the session door's `galley_<name>` over a session handle, the
 * hook door's `galley_hook_<name>` over a parse's door. Every status is i64.
 */
interface DiagCalls {
  has_diagnostic(handle: NativeHandle, outHas: NativeHandle): bigint;
  diagnostic_kind(handle: NativeHandle): bigint;
  diagnostic_message(handle: NativeHandle, out: NativeHandle): bigint;
  diagnostic_message_ansi(handle: NativeHandle, out: NativeHandle): bigint;
  diagnostic_position(handle: NativeHandle, outOffset: NativeHandle, outLine: NativeHandle, outCol: NativeHandle): bigint;
  diagnostic_unexpected_token(handle: NativeHandle, outData: NativeHandle, outLen: NativeHandle): bigint;
  diagnostic_expected_count(handle: NativeHandle): bigint;
  diagnostic_expected_at(handle: NativeHandle, index: bigint, outData: NativeHandle, outLen: NativeHandle): bigint;
  diagnostic_context_count(handle: NativeHandle): bigint;
  diagnostic_context_at(handle: NativeHandle, index: bigint, outData: NativeHandle, outLen: NativeHandle): bigint;
  syntax_error_count(handle: NativeHandle): bigint;
  semantic_error_count(handle: NativeHandle): bigint;
  diagnostic_semantic(handle: NativeHandle, outVariable: NativeHandle, outVariableLen: NativeHandle, outMessage: NativeHandle, outMessageLen: NativeHandle): bigint;
  diagnostic_indentation(handle: NativeHandle, outSpaces: NativeHandle, outWidth: NativeHandle): bigint;
  diagnostic_recovery_kind(handle: NativeHandle): bigint;
  diagnostic_recovery_terminal(handle: NativeHandle, outData: NativeHandle, outLen: NativeHandle): bigint;
  diagnostic_recovery_resume(handle: NativeHandle, out: NativeHandle): bigint;
  diagnostic_recovery_lhs_variable(handle: NativeHandle, outData: NativeHandle, outLen: NativeHandle): bigint;
  diagnostic_recovery_production(handle: NativeHandle, outVar: NativeHandle, outLen: NativeHandle, outIdx: NativeHandle): bigint;
  diagnostic_recovery_occurrence(handle: NativeHandle, outParent: NativeHandle, outParentLen: NativeHandle, outRhs: NativeHandle, outSym: NativeHandle, outVar: NativeHandle, outVarLen: NativeHandle): bigint;
}

/** `DiagCalls` under one door's C names. */
type DiagNames<Door extends "" | "hook_"> = {
  [Name in keyof DiagCalls as `galley_${Door}${Name & string}`]: DiagCalls[Name];
};

interface GalleySymbols extends DoorNames<"">, DoorNames<"hook_">, DiagNames<"">, DiagNames<"hook_"> {
  galley_version(): string;
  galley_parser_type(): bigint;
  galley_error_recovery_mode(): bigint;
  galley_has_ast(): number;
  galley_has_procedures(): number;
  galley_source_retention_enabled(): number;
  galley_has_position_tracking(): number;
  galley_has_input_streaming(): number;
  galley_uses_verbatim(): number;
  galley_stack_overflow_recovery_available(): number;
  galley_symbol_count(): bigint;
  galley_variable_count(): bigint;
  galley_status_string(status: bigint): string;
  galley_symbol_name(session: NativeHandle, index: bigint, outData: number, outLen: number): bigint;
  galley_symbol_is_terminal(session: NativeHandle, index: bigint, outIsTerminal: number): bigint;
  galley_variable_name(session: NativeHandle, index: bigint, outData: number, outLen: number): bigint;
  galley_session_create(options: number | null, outSession: number): bigint;
  galley_session_destroy(session: NativeHandle): bigint;
  galley_session_set_message_override(session: NativeHandle, name: number, nameLen: bigint, message: number, messageLen: bigint): bigint;
  galley_parse(session: NativeHandle, data: number, len: bigint): bigint;
  galley_parse_file(session: NativeHandle, path: number): bigint;
  galley_last_input(session: NativeHandle, outData: number, outLen: number): bigint;
  galley_last_position(session: NativeHandle, outLine: number, outCol: number): bigint;
  galley_node_count(session: NativeHandle, generation: number): number;
  galley_reserve_nodes(session: NativeHandle, capacity: bigint): bigint;
  galley_node_capacity(session: NativeHandle): bigint;
  galley_root_node(session: NativeHandle, outRoot: number, outGeneration: number): bigint;
  galley_tree_snapshot(
    session: NativeHandle,
    generation: number,
    outParent: number | null,
    outFirstChild: number | null,
    outNext: number | null,
    outChildCount: number | null,
    outVariable: number | null,
    outSpanStart: number | null,
    outSpanLen: number | null,
    outIsSemanticError: number | null,
    outIsRecovered: number | null,
    capacity: bigint,
  ): bigint;
  galley_recorded_diagnostic_count(session: NativeHandle): bigint;
  galley_recorded_diagnostic_kind(session: NativeHandle, diagIndex: bigint): bigint;
  galley_recorded_diagnostic_position(session: NativeHandle, diagIndex: bigint, outOffset: number, outLine: number, outCol: number): bigint;
  galley_recorded_unexpected_token(session: NativeHandle, diagIndex: bigint, outData: number, outLen: number): bigint;
  galley_recorded_diagnostic_message(session: NativeHandle, diagIndex: bigint, out: number): bigint;
  galley_recorded_diagnostic_message_ansi(session: NativeHandle, diagIndex: bigint, out: number): bigint;
  galley_recorded_indentation(session: NativeHandle, diagIndex: bigint, outSpaces: number, outWidth: number): bigint;
  galley_recorded_semantic(session: NativeHandle, diagIndex: bigint, outVariable: number, outVariableLen: number, outMessage: number, outMessageLen: number): bigint;
  galley_recorded_expected_count(session: NativeHandle, diagIndex: bigint): bigint;
  galley_recorded_expected_token(session: NativeHandle, diagIndex: bigint, tokenIndex: bigint, outData: number, outLen: number): bigint;
  galley_recorded_context_count(session: NativeHandle, diagIndex: bigint): bigint;
  galley_recorded_context_name(session: NativeHandle, diagIndex: bigint, ctxIndex: bigint, outData: number, outLen: number): bigint;
  // Use the true symbol name.
  galley_recorded_diagnostic_recovery_kind(session: NativeHandle, diagIndex: bigint): bigint;
  galley_recorded_recovery_terminal(session: NativeHandle, diagIndex: bigint, outData: number, outLen: number): bigint;
  galley_recorded_recovery_resume(session: NativeHandle, diagIndex: bigint, out: number): bigint;
  galley_recorded_recovery_lhs_variable(session: NativeHandle, diagIndex: bigint, outData: number, outLen: number): bigint;
  galley_recorded_recovery_production(session: NativeHandle, diagIndex: bigint, outVar: number, outLen: number, outIdx: number): bigint;
  galley_recorded_recovery_occurrence(session: NativeHandle, diagIndex: bigint, outParent: number, outParentLen: number, outRhs: number, outSym: number, outVar: number, outVarLen: number): bigint;
  galley_procedure_current_node(session: NativeHandle, hook: bigint): bigint;
  galley_procedure_door(session: NativeHandle, hook: bigint, outDoor: number): bigint;
  galley_procedure_set_current_node(session: NativeHandle, hook: bigint, generation: number, node: bigint): bigint;
  galley_procedure_drop_self(session: NativeHandle, hook: bigint): bigint;
  galley_procedure_drop_children(session: NativeHandle, hook: bigint): bigint;
  galley_procedure_drop_if_empty(session: NativeHandle, hook: bigint): bigint;
  galley_procedure_context_line(session: NativeHandle, hook: bigint): bigint;
  galley_procedure_context_column(session: NativeHandle, hook: bigint): bigint;
  galley_procedure_report_semantic_error(session: NativeHandle, hook: bigint, message: number, messageLen: bigint): bigint;
  // hook door: parse-time node/tree accessors over the live parse
  galley_hook_generation(door: NativeHandle, outGeneration: number): bigint;
  // host hooks (see galley_session_set_hooks in galley.h)
  galley_hooks_count(): bigint;
  galley_hooks_name(index: bigint, outData: number, outLen: number): bigint;
  galley_session_set_hooks(session: NativeHandle, dispatch: NativeHandle, hookHandle: bigint, enabled: number | null, enabledCount: bigint): bigint;
}

// --- library discovery -------------------------------------------------
// One place, named up front: the language directory must hold the
// adapter's standard-named library file or the shared native library
// `galley build` leaves (it serves every native adapter). Anything else
// is a loud error naming both tried paths, never a search.

const BUILD_HINT =
  `Build it first: npx galley build <language-dir>\n` +
  `That leaves ${artifactFileName(SHARED_NATIVE_LIBRARY_BASE, process.platform)} in the directory ` +
  `(or bunx galley-js-bun <language-dir> for the adapter-named ${libFileName()}).`;

export function libFileName(base = "galley-js-bun"): string {
  return artifactFileName(base, process.platform);
}

function exists(candidate: string): boolean {
  try {
    fs.accessSync(candidate);
    return true;
  } catch {
    return false;
  }
}

export function findLibrary(languagePath: string): string {
  return resolveAdapterArtifact(
    languagePath,
    libFileName(),
    artifactFileName(SHARED_NATIVE_LIBRARY_BASE, process.platform),
    path.join,
    {
      resolvePath: (candidate) => canonicalResolvePath(candidate, path.resolve, fs.realpathSync),
      existsSync: exists,
      buildHint: BUILD_HINT,
    },
  );
}

/** Explicit-file twin of {@link findLibrary}: names the library itself. */
export function findLibraryFile(filePath: string): string {
  return resolveArtifactFile(filePath, {
    resolvePath: (candidate) => canonicalResolvePath(candidate, path.resolve, fs.realpathSync),
    existsSync: exists,
    buildHint: BUILD_HINT,
  });
}

// --- loader ------------------------------------------------------------

const BASE_SYMBOLS = {
  galley_version: { args: [], returns: FFIType.cstring },
  galley_parser_type: { args: [], returns: FFIType.i64 },
  galley_error_recovery_mode: { args: [], returns: FFIType.i64 },
  galley_has_ast: { args: [], returns: FFIType.i32 },
  galley_has_procedures: { args: [], returns: FFIType.i32 },
  galley_source_retention_enabled: { args: [], returns: FFIType.i32 },
  galley_has_position_tracking: { args: [], returns: FFIType.i32 },
  galley_has_input_streaming: { args: [], returns: FFIType.i32 },
  galley_uses_verbatim: { args: [], returns: FFIType.i32 },
  galley_stack_overflow_recovery_available: { args: [], returns: FFIType.i32 },
  galley_symbol_count: { args: [], returns: FFIType.u64 },
  galley_variable_count: { args: [], returns: FFIType.u64 },
  galley_status_string: { args: [FFIType.i64], returns: FFIType.cstring },
  galley_symbol_name: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_symbol_is_terminal: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr], returns: FFIType.i64 },
  galley_variable_name: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_session_create: { args: [FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_session_destroy: { args: [FFIType.ptr], returns: FFIType.i64 },
  galley_session_set_message_override: { args: [FFIType.ptr, FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_parse: { args: [FFIType.ptr, FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_parse_file: { args: [FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_last_input: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_last_position: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_node_count: { args: [FFIType.ptr, FFIType.u64_fast], returns: FFIType.i64_fast },
  galley_reserve_nodes: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_node_capacity: { args: [FFIType.ptr], returns: FFIType.i64 },
  galley_root_node: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_tree_snapshot: {
    args: [FFIType.ptr, FFIType.u64_fast, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.u64],
    returns: FFIType.i64,
  },
  galley_has_diagnostic: { args: [FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_diagnostic_count: { args: [FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_diagnostic_kind: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_recorded_diagnostic_position: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_unexpected_token: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_diagnostic_message: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr], returns: FFIType.i64 },
  galley_recorded_diagnostic_message_ansi: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr], returns: FFIType.i64 },
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
  galley_procedure_current_node: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_procedure_door: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr], returns: FFIType.i64 },
  galley_procedure_set_current_node: { args: [FFIType.ptr, FFIType.u64, FFIType.u64_fast, FFIType.u64], returns: FFIType.i64 },
  galley_procedure_drop_self: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_procedure_drop_children: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_procedure_drop_if_empty: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_procedure_context_line: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_procedure_context_column: { args: [FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_procedure_report_semantic_error: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
  galley_hook_generation: { args: [FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
} as const;

/**
 * The node, tree and walk symbols, declared once and opened under both
 * prefixes (see `doorSymbols`). The generation is an `u64_fast` number, the
 * node an exact `u64`.
 */
const DOOR_SYMBOLS = {
  node_child_count: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64], returns: FFIType.i64_fast },
  node_first_child: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64], returns: FFIType.i64 },
  node_last_child: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64], returns: FFIType.i64 },
  node_next_sibling: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64], returns: FFIType.i64 },
  node_prior_sibling: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64], returns: FFIType.i64 },
  node_parent: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64], returns: FFIType.i64 },
  node_span: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  node_symbol_name: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  node_variable_index: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64], returns: FFIType.i64 },
  node_text: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  node_line_column: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  walk_next: { args: [FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  tree_append_children: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64, FFIType.u64_fast, FFIType.u64], returns: FFIType.i64 },
  tree_insert_before: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64, FFIType.u64_fast, FFIType.u64], returns: FFIType.i64 },
  tree_insert_after: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64, FFIType.u64_fast, FFIType.u64], returns: FFIType.i64 },
  tree_remove_siblings: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64, FFIType.u64, FFIType.ptr], returns: FFIType.i64 },
  tree_remove_self: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64, FFIType.ptr], returns: FFIType.i64 },
  tree_clean_children: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64, FFIType.ptr], returns: FFIType.i64 },
  tree_insert_children_at: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64, FFIType.u64, FFIType.u64_fast, FFIType.u64], returns: FFIType.i64 },
  tree_remove_children_at: { args: [FFIType.ptr, FFIType.u64_fast, FFIType.u64, FFIType.u64, FFIType.u64, FFIType.ptr], returns: FFIType.i64 },
} as const satisfies Record<keyof DoorCalls, unknown>;

/** `DOOR_SYMBOLS` under one door's C names: `galley_<name>` or `galley_hook_<name>`. */
function doorSymbols(door: "" | "hook_") {
  return Object.fromEntries(
    Object.entries(DOOR_SYMBOLS).map(([name, symbol]) => [`galley_${door}${name}`, symbol]),
  );
}

/**
 * The current-diagnostic symbols, declared once and opened under both door
 * prefixes (see `diagSymbols`). Every one answers i64; the door-pair
 * `has_diagnostic` entries are declared next to the host hooks below.
 */
const DIAG_SYMBOLS = {
  diagnostic_kind: { args: [FFIType.ptr], returns: FFIType.i64 },
  diagnostic_message: { args: [FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  diagnostic_message_ansi: { args: [FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  diagnostic_position: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  diagnostic_unexpected_token: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  diagnostic_expected_count: { args: [FFIType.ptr], returns: FFIType.i64 },
  diagnostic_expected_at: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  diagnostic_context_count: { args: [FFIType.ptr], returns: FFIType.i64 },
  diagnostic_context_at: { args: [FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  diagnostic_indentation: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  syntax_error_count: { args: [FFIType.ptr], returns: FFIType.i64 },
  semantic_error_count: { args: [FFIType.ptr], returns: FFIType.i64 },
  diagnostic_semantic: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  diagnostic_recovery_kind: { args: [FFIType.ptr], returns: FFIType.i64 },
  diagnostic_recovery_terminal: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  diagnostic_recovery_resume: { args: [FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  diagnostic_recovery_lhs_variable: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  diagnostic_recovery_production: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  diagnostic_recovery_occurrence: { args: [FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
} as const satisfies Record<Exclude<keyof DiagCalls, "has_diagnostic">, unknown>;

/** `DIAG_SYMBOLS` under one door's C names: `galley_<name>` or `galley_hook_<name>`. */
function diagSymbols(door: "" | "hook_") {
  return Object.fromEntries(
    Object.entries(DIAG_SYMBOLS).map(([name, symbol]) => [`galley_${door}${name}`, symbol]),
  );
}

const HOOK_SYMBOLS = {
  galley_hooks_count: { args: [], returns: FFIType.u64 },
  galley_hooks_name: { args: [FFIType.u64, FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_hook_has_diagnostic: { args: [FFIType.ptr, FFIType.ptr], returns: FFIType.i64 },
  galley_session_set_hooks: { args: [FFIType.ptr, FFIType.ptr, FFIType.u64, FFIType.ptr, FFIType.u64], returns: FFIType.i64 },
} as const;

function openNative(libPath: string): { symbols: GalleySymbols } {
  return dlopen(libPath, { ...BASE_SYMBOLS, ...doorSymbols(""), ...doorSymbols("hook_"), ...diagSymbols(""), ...diagSymbols("hook_"), ...HOOK_SYMBOLS }) as unknown as { symbols: GalleySymbols };
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

/** Read a native `(data, len)` byte pair: the bytes, or the refusal as a negative Number. */
function copyBytesResult(
  call: (outData: BigUint64Array, outLen: BigUint64Array) => bigint,
): Uint8Array | number {
  const outData = ptrOut64();
  const outLen = ptrOut64();
  const status = call(outData, outLen);
  if (status < 0n) return Number(status);
  return readBytes(outData[0], outLen[0]);
}

/** Read a native `(data, len)` string: the text, or the refusal as a negative Number. */
function stringResult(
  call: (outData: BigUint64Array, outLen: BigUint64Array) => bigint,
): string | number {
  const outData = ptrOut64();
  const outLen = ptrOut64();
  const status = call(outData, outLen);
  if (status < 0n) return Number(status);
  return new TextDecoder().decode(readBytes(outData[0], outLen[0]));
}

/** Read a native semantic `(variable, message)` pair, or the refusal as a negative Number. */
function semanticResult(
  call: (outVariable: BigUint64Array, outVariableLen: BigUint64Array, outMessage: BigUint64Array, outMessageLen: BigUint64Array) => bigint,
): [string, string] | number {
  const outVariable = ptrOut64();
  const outVariableLen = ptrOut64();
  const outMessage = ptrOut64();
  const outMessageLen = ptrOut64();
  const status = call(outVariable, outVariableLen, outMessage, outMessageLen);
  if (status < 0n) return Number(status);
  const decoder = new TextDecoder();
  return [
    decoder.decode(readBytes(outVariable[0], outVariableLen[0])),
    decoder.decode(readBytes(outMessage[0], outMessageLen[0])),
  ];
}

// --- FfiPort implementation ----------------------------------------------

/**
 * One door's node and tree calls, bound from the twin registrations:
 * `galley_<name>` for the session door, `galley_hook_<name>` for the hook
 * door. Each capability is written here once and used for both. A refusal is
 * a negative status, which the core's door turns into the host's failure.
 * `outWords` is the port's two out-value slots, shared by both families: a JS
 * realm is single-threaded and no crossing re-enters JS.
 */
function bunFamily(native: GalleySymbols, door: "" | "hook_", outWords: BigUint64Array): NodeFamily {
  const calls = native as unknown as Record<string, unknown>;
  const bound = <Name extends keyof DoorCalls>(name: Name): DoorCalls[Name] =>
    calls[`galley_${door}${name}`] as DoorCalls[Name];
  const outHalves = new Uint32Array(outWords.buffer);
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
  return {
    childCount: (handle, generation, node) => childCount(handle as NativeHandle, generation, node),
    firstChild: (handle, generation, node) => firstChild(handle as NativeHandle, generation, node),
    lastChild: (handle, generation, node) => lastChild(handle as NativeHandle, generation, node),
    nextSibling: (handle, generation, node) => nextSibling(handle as NativeHandle, generation, node),
    priorSibling: (handle, generation, node) => priorSibling(handle as NativeHandle, generation, node),
    parent: (handle, generation, node) => parent(handle as NativeHandle, generation, node),
    nodeSymbolName: (handle, generation, node) => {
      const status = symbolName(handle as NativeHandle, generation, node, ptr(outWords), ptr(outWords, 8));
      return status < 0n ? Number(status) : readBytes(outWords[0], outWords[1]);
    },
    nodeText: (handle, generation, node) => {
      const status = text(handle as NativeHandle, generation, node, ptr(outWords), ptr(outWords, 8));
      return status < 0n ? Number(status) : readBytes(outWords[0], outWords[1]);
    },
    nodeSpan: (handle, generation, node) => {
      const status = span(handle as NativeHandle, generation, node, ptr(outWords), ptr(outWords, 8));
      return status < 0n ? Number(status) : [outWords[0], outWords[1]];
    },
    nodeLineColumn: (handle, generation, node) => {
      const status = lineColumn(handle as NativeHandle, generation, node, ptr(outWords), ptr(outWords, 8));
      return status < 0n ? Number(status) : [outHalves[0], outHalves[2]];
    },
    nodeVariableIndex: (handle, generation, node) => {
      const index = variableIndex(handle as NativeHandle, generation, node);
      return index === NO_VARIABLE ? null : Number(index);
    },
    walkNext: (handle, cursor) => Number(walkNext(handle as NativeHandle, ptr(cursor))),
    treeAppendChildren: (handle, generation, parentNode, firstGeneration, first) =>
      Number(appendChildren(handle as NativeHandle, generation, parentNode, firstGeneration, first)),
    treeInsertBefore: (handle, generation, target, firstGeneration, first) =>
      Number(insertBefore(handle as NativeHandle, generation, target, firstGeneration, first)),
    treeInsertAfter: (handle, generation, target, firstGeneration, first) =>
      Number(insertAfter(handle as NativeHandle, generation, target, firstGeneration, first)),
    treeRemoveSiblings: (handle, generation, node, count) => {
      const status = removeSiblings(handle as NativeHandle, generation, node, BigInt(count), ptr(outWords));
      return { status: Number(status), head: outWords[0] };
    },
    treeRemoveSelf: (handle, generation, node) => {
      const status = removeSelf(handle as NativeHandle, generation, node, ptr(outWords));
      return { status: Number(status), head: outWords[0] };
    },
    treeCleanChildren: (handle, generation, node) => {
      const status = cleanChildren(handle as NativeHandle, generation, node, ptr(outWords));
      return { status: Number(status), head: outWords[0] };
    },
    treeInsertChildrenAt: (handle, generation, parentNode, index, firstGeneration, first) =>
      Number(insertChildrenAt(handle as NativeHandle, generation, parentNode, BigInt(index), firstGeneration, first)),
    treeRemoveChildrenAt: (handle, generation, parentNode, index, count) => {
      const status = removeChildrenAt(
        handle as NativeHandle, generation, parentNode, BigInt(index), BigInt(count), ptr(outWords),
      );
      return { status: Number(status), head: outWords[0] };
    },
  };
}

/**
 * One door's current-diagnostic family, bound from the twin registrations:
 * `galley_<name>` for the session door, `galley_hook_<name>` for the hook
 * door. Counts and kinds normalize to Numbers; a refusal stays a negative
 * Number for the core, which is the one place it becomes a host failure.
 */
function bunDiagFamily(native: GalleySymbols, door: "" | "hook_"): CurrentDiagnosticFamily {
  const calls = native as unknown as Record<string, unknown>;
  const bound = <Name extends keyof DiagCalls>(name: Name): DiagCalls[Name] =>
    calls[`galley_${door}${name}`] as DiagCalls[Name];
  const hasDiagnostic = bound("has_diagnostic");
  const kind = bound("diagnostic_kind");
  const message = bound("diagnostic_message");
  const messageAnsi = bound("diagnostic_message_ansi");
  const position = bound("diagnostic_position");
  const unexpectedToken = bound("diagnostic_unexpected_token");
  const expectedCount = bound("diagnostic_expected_count");
  const expectedAt = bound("diagnostic_expected_at");
  const contextCount = bound("diagnostic_context_count");
  const contextAt = bound("diagnostic_context_at");
  const syntaxErrorCount = bound("syntax_error_count");
  const semanticErrorCount = bound("semantic_error_count");
  const semantic = bound("diagnostic_semantic");
  const indentation = bound("diagnostic_indentation");
  const recoveryKind = bound("diagnostic_recovery_kind");
  const recoveryTerminal = bound("diagnostic_recovery_terminal");
  const recoveryResume = bound("diagnostic_recovery_resume");
  const recoveryLhsVariable = bound("diagnostic_recovery_lhs_variable");
  const recoveryProduction = bound("diagnostic_recovery_production");
  const recoveryOccurrence = bound("diagnostic_recovery_occurrence");
  // Every current-diagnostic status is i64; Number() normalizes it.
  const num = (value: bigint | number): number => Number(value);
  return {
    hasDiagnostic: (handle) => {
      const out = u32Out();
      const status = num(hasDiagnostic(handle as NativeHandle, ptr(out)));
      if (status < 0) return status;
      return out[0] !== 0;
    },
    diagnosticKind: (handle) => num(kind(handle as NativeHandle)),
    diagnosticMessage: (handle) => {
      const out = ptrOut64();
      const status = num(message(handle as NativeHandle, ptr(out)));
      if (status < 0) return status;
      return readCString(out[0]);
    },
    diagnosticMessageAnsi: (handle) => {
      const out = ptrOut64();
      const status = num(messageAnsi(handle as NativeHandle, ptr(out)));
      if (status < 0) return status;
      return readCString(out[0]);
    },
    diagnosticPosition: (handle) => {
      const outOffset = ptrOut64();
      const outLine = u32Out();
      const outCol = u32Out();
      const status = num(position(handle as NativeHandle, ptr(outOffset), ptr(outLine), ptr(outCol)));
      if (status < 0) return status;
      return [Number(outOffset[0]), outLine[0], outCol[0]];
    },
    diagnosticUnexpectedToken: (handle) =>
      copyBytesResult((od, ol) => unexpectedToken(handle as NativeHandle, ptr(od), ptr(ol))),
    diagnosticExpectedCount: (handle) => num(expectedCount(handle as NativeHandle)),
    diagnosticExpectedAt: (handle, index) =>
      copyBytesResult((od, ol) => expectedAt(handle as NativeHandle, BigInt(index), ptr(od), ptr(ol))),
    diagnosticContextCount: (handle) => num(contextCount(handle as NativeHandle)),
    diagnosticContextAt: (handle, index) =>
      copyBytesResult((od, ol) => contextAt(handle as NativeHandle, BigInt(index), ptr(od), ptr(ol))),
    syntaxErrorCount: (handle) => num(syntaxErrorCount(handle as NativeHandle)),
    semanticErrorCount: (handle) => num(semanticErrorCount(handle as NativeHandle)),
    diagnosticSemantic: (handle) =>
      semanticResult((ov, ovl, om, oml) =>
        semantic(handle as NativeHandle, ptr(ov), ptr(ovl), ptr(om), ptr(oml))),
    diagnosticIndentation: (handle) => {
      const outSpaces = u32Out();
      const outWidth = u32Out();
      const status = num(indentation(handle as NativeHandle, ptr(outSpaces), ptr(outWidth)));
      if (status < 0) return status;
      return [outSpaces[0], outWidth[0]];
    },
    diagnosticRecoveryKind: (handle) => num(recoveryKind(handle as NativeHandle)),
    diagnosticRecoveryTerminal: (handle) =>
      copyBytesResult((od, ol) => recoveryTerminal(handle as NativeHandle, ptr(od), ptr(ol))),
    diagnosticRecoveryResume: (handle) => {
      const out = i64Out();
      const status = num(recoveryResume(handle as NativeHandle, ptr(out)));
      if (status < 0) return status;
      return Number(out[0]);
    },
    diagnosticRecoveryLhsVariable: (handle) =>
      stringResult((od, ol) => recoveryLhsVariable(handle as NativeHandle, ptr(od), ptr(ol))),
    diagnosticRecoveryProduction: (handle) => {
      const outVar = ptrOut64();
      const outLen = ptrOut64();
      const outIdx = u32Out();
      const status = num(recoveryProduction(handle as NativeHandle, ptr(outVar), ptr(outLen), ptr(outIdx)));
      if (status < 0) return status;
      return [new TextDecoder().decode(readBytes(outVar[0], outLen[0])), outIdx[0]];
    },
    diagnosticRecoveryOccurrence: (handle) => {
      const outParent = ptrOut64();
      const outParentLen = ptrOut64();
      const outRhs = u32Out();
      const outSym = u32Out();
      const outVar = ptrOut64();
      const outVarLen = ptrOut64();
      const status = num(
        recoveryOccurrence(
          handle as NativeHandle, ptr(outParent), ptr(outParentLen), ptr(outRhs), ptr(outSym), ptr(outVar), ptr(outVarLen),
        ),
      );
      if (status < 0) return status;
      const decoder = new TextDecoder();
      return [
        decoder.decode(readBytes(outParent[0], outParentLen[0])),
        outRhs[0],
        outSym[0],
        decoder.decode(readBytes(outVar[0], outVarLen[0])),
      ];
    },
  };
}


export class BunPort implements FfiPort {
  hookDispatch: DispatchHandler | null = null;
  readonly native: GalleySymbols;
  readonly libraryPath: string;
  /**
   * The native address of this port's one `JSCallback`, handed to the
   * library with every session's hooks; set by `installDispatch`. Each
   * worker owns its own callback, so the address is per session, not per
   * library.
   */
  dispatchPointer = 0;
  /**
   * The out-value slots every node crossing, on either door, writes into: two
   * 64-bit words, which the `Uint32Array` view reads as 32-bit values at
   * even indices. One pair per port is enough because a JS realm is
   * single-threaded and no node crossing re-enters JS; results are copied
   * out before the call returns, so nothing is allocated per call.
   */
  readonly #outWords = new BigUint64Array(2);

  readonly session: NodeFamily;
  readonly hook: NodeFamily;
  readonly diagnostics: CurrentDiagnosticFamily;
  readonly hookDiagnostics: CurrentDiagnosticFamily;

  constructor(native: GalleySymbols, libraryPath: string) {
    this.native = native;
    this.libraryPath = libraryPath;
    this.session = bunFamily(native, "", this.#outWords);
    this.hook = bunFamily(native, "hook_", this.#outWords);
    this.diagnostics = bunDiagFamily(native, "");
    this.hookDiagnostics = bunDiagFamily(native, "hook_");
  }

  setSessionHooks(session: Handle, hookHandle: number, enabled: Uint8Array): number {
    // An artifact with no hooks commits an empty table: bun:ffi cannot
    // take a pointer to empty memory, so an empty `enabled` crosses as
    // null, which the API already reads as "enable none" at count 0.
    return Number(
      this.native.galley_session_set_hooks(
        session as NativeHandle,
        this.dispatchPointer,
        BigInt(hookHandle),
        enabled.length > 0 ? ptr(enabled) : null,
        BigInt(enabled.length),
      ),
    );
  }

  #hookNameTable: string[] | null = null;

  hookNames(): string[] {
    if (this.#hookNameTable !== null) return this.#hookNameTable;
    const table: string[] = [];
    const decoder = new TextDecoder();
    const total = this.native.galley_hooks_count();
    const out = ptrOut64();
    const outLen = ptrOut64();
    for (let index = 0n; index < total; index++) {
      const status = this.native.galley_hooks_name(index, ptr(out), ptr(outLen));
      if (status < 0n) {
        // Cannot happen below galley_hooks_count; raising beats silently
        // shortening the table.
        throw new GalleyError(
          this.statusString(Number(status)) ?? `status ${status}`,
          Number(status) as Status,
        );
      }
      table.push(decoder.decode(readBytes(out[0], outLen[0])));
    }
    this.#hookNameTable = table;
    return table;
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

  createSession(options: SessionCOptions | null): { status: number; handle: Handle | null } {
    // Null options crosses as a NULL pointer (the library's defaults), never
    // as a zeroed struct. The view backing the options stays bound to
    // `optionsBytes` — a named local, not a temporary a GC could see become
    // unreachable — until the native call has read it.
    let optionsBytes: Uint8Array | null = null;
    if (options !== null) {
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
      optionsBytes = new Uint8Array(buf);
    }
    const out = ptrOut64();
    const status = Number(
      this.native.galley_session_create(optionsBytes === null ? null : ptr(optionsBytes), ptr(out)),
    );
    if (status < 0) return { status, handle: null };
    const handle = out[0];
    return { status, handle: handle === 0n ? null : Number(handle) };
  }

  destroySession(handle: Handle): number {
    return Number(this.native.galley_session_destroy(handle as NativeHandle));
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

  // Native engines read the caller's memory in place: staging only pins
  // a private copy, so changes to the source never reach it.
  stageInput(data: Uint8Array): StagedHandle {
    return data.slice();
  }

  parseStaged(handle: Handle, staged: StagedHandle): number {
    return this.parse(handle, staged as Uint8Array);
  }

  releaseInput(_staged: StagedHandle): void {}

  parseFile(handle: Handle, filePath: string): number {
    const bytes = Buffer.from(filePath, "utf-8");
    const nul = Buffer.alloc(bytes.length + 1);
    bytes.copy(nul);
    return Number(this.native.galley_parse_file(handle as NativeHandle, ptr(nul)));
  }

  lastPosition(handle: Handle): [number, number] | number {
    const outLine = u32Out();
    const outCol = u32Out();
    const status = this.native.galley_last_position(handle as NativeHandle, ptr(outLine), ptr(outCol));
    if (status < 0n) return Number(status);
    return [outLine[0], outCol[0]];
  }

  lastInput(handle: Handle): Uint8Array | number {
    const h = handle as NativeHandle;
    const outData = ptrOut64();
    const outLen = ptrOut64();
    const status = this.native.galley_last_input(h, ptr(outData), ptr(outLen));
    if (status < 0n) return Number(status);
    return readBytes(outData[0], outLen[0]);
  }

  // -- arena and navigation ----------------------------------------------

  nodeCount(handle: Handle, generation: number): number {
    return this.native.galley_node_count(handle as NativeHandle, generation);
  }

  reserveNodes(handle: Handle, capacity: bigint): number {
    return Number(this.native.galley_reserve_nodes(handle as NativeHandle, capacity));
  }

  nodeCapacity(handle: Handle): number {
    return Number(this.native.galley_node_capacity(handle as NativeHandle));
  }

  rootNode(handle: Handle): { status: number; root: bigint; generation: number } {
    this.#outWords[0] = INVALID_NODE;
    const status = this.native.galley_root_node(handle as NativeHandle, ptr(this.#outWords), ptr(this.#outWords, 8));
    return { status: Number(status), root: this.#outWords[0], generation: Number(this.#outWords[1]) };
  }

  treeSnapshot(handle: Handle, generation: number): SnapshotColumns | number {
    for (let attempt = 0; attempt < 2; attempt++) {
      const count = this.nodeCount(handle, generation);
      if (count < 0) return count;
      const parent = new BigUint64Array(count);
      const firstChild = new BigUint64Array(count);
      const next = new BigUint64Array(count);
      const childCount = new Uint32Array(count);
      const variable = new BigInt64Array(count);
      const spanStart = new BigUint64Array(count);
      const spanLen = new BigUint64Array(count);
      const isSemanticError = new Int32Array(count);
      const isRecovered = new Int32Array(count);
      // A zero count (nothing parsed yet, or a stale last result) still
      // crosses so the gate can answer; bun:ffi cannot take a pointer to
      // empty memory, so empty columns pass as null.
      const column = (array: Parameters<typeof ptr>[0]) => (count > 0 ? ptr(array) : null);
      const total = this.native.galley_tree_snapshot(
        handle as NativeHandle, generation, column(parent), column(firstChild), column(next), column(childCount),
        column(variable), column(spanStart), column(spanLen), column(isSemanticError), column(isRecovered), BigInt(count),
      );
      if (total < 0n) return Number(total);
      if (total === BigInt(count)) {
        return { count, parent, firstChild, next, childCount, variable, spanStart, spanLen, isSemanticError, isRecovered };
      }
    }
    throw new GalleyError("node count changed during galley_tree_snapshot", Status.ErrorInternal);
  }

  // -- walking ------------------------------------------------------------

  /** Native code reads and writes the cursor struct in the platform's order. */
  readonly walkCursorLittleEndian = NATIVE_LITTLE_ENDIAN;

  // -- node accessors -----------------------------------------------------

  symbolNameAt(handle: Handle, index: number): Uint8Array | number {
    const h = handle as NativeHandle;
    return copyBytesResult((od, ol) => this.native.galley_symbol_name(h, BigInt(index), ptr(od), ptr(ol)));
  }

  symbolIsTerminal(handle: Handle, index: number): boolean | number {
    const out = u32Out();
    const status = this.native.galley_symbol_is_terminal(handle as NativeHandle, BigInt(index), ptr(out));
    if (status < 0n) return Number(status);
    return out[0] !== 0;
  }

  variableNameAt(handle: Handle, index: number): Uint8Array | number {
    const h = handle as NativeHandle;
    return copyBytesResult((od, ol) => this.native.galley_variable_name(h, BigInt(index), ptr(od), ptr(ol)));
  }

  // -- diagnostics ---------------------------------------------------------
  //
  // The current-diagnostic family lives on `diagnostics` (session door) and
  // `hookDiagnostics` (hook door), built once in the constructor; the flat
  // recorded family below is post-parse only.

  recordedDiagnosticCount(handle: Handle): number {
    return Number(this.native.galley_recorded_diagnostic_count(handle as NativeHandle));
  }

  recordedDiagnosticKind(handle: Handle, diagIndex: number): number {
    return Number(this.native.galley_recorded_diagnostic_kind(handle as NativeHandle, BigInt(diagIndex)));
  }

  recordedDiagnosticPosition(handle: Handle, diagIndex: number): [number, number, number] | number {
    const outOffset = ptrOut64();
    const outLine = u32Out();
    const outCol = u32Out();
    const status = this.native.galley_recorded_diagnostic_position(handle as NativeHandle, BigInt(diagIndex), ptr(outOffset), ptr(outLine), ptr(outCol));
    if (status < 0n) return Number(status);
    return [Number(outOffset[0]), outLine[0], outCol[0]];
  }

  recordedUnexpectedToken(handle: Handle, diagIndex: number): Uint8Array | number {
    const h = handle as NativeHandle;
    const d = BigInt(diagIndex);
    return copyBytesResult((od, ol) => this.native.galley_recorded_unexpected_token(h, d, ptr(od), ptr(ol)));
  }

  recordedDiagnosticMessage(handle: Handle, diagIndex: number): string | number {
    const out = ptrOut64();
    const status = this.native.galley_recorded_diagnostic_message(handle as NativeHandle, BigInt(diagIndex), ptr(out));
    if (status < 0n) return Number(status);
    return readCString(out[0]);
  }

  recordedDiagnosticMessageAnsi(handle: Handle, diagIndex: number): string | number {
    const out = ptrOut64();
    const status = this.native.galley_recorded_diagnostic_message_ansi(handle as NativeHandle, BigInt(diagIndex), ptr(out));
    if (status < 0n) return Number(status);
    return readCString(out[0]);
  }

  recordedIndentation(handle: Handle, diagIndex: number): [number, number] | number {
    const outSpaces = u32Out();
    const outWidth = u32Out();
    const status = this.native.galley_recorded_indentation(handle as NativeHandle, BigInt(diagIndex), ptr(outSpaces), ptr(outWidth));
    if (status < 0n) return Number(status);
    return [outSpaces[0], outWidth[0]];
  }

  recordedSemantic(handle: Handle, diagIndex: number): [string, string] | number {
    const h = handle as NativeHandle;
    const d = BigInt(diagIndex);
    return semanticResult((ov, ovl, om, oml) =>
      this.native.galley_recorded_semantic(h, d, ptr(ov), ptr(ovl), ptr(om), ptr(oml)));
  }

  recordedExpectedCount(handle: Handle, diagIndex: number): number {
    return Number(this.native.galley_recorded_expected_count(handle as NativeHandle, BigInt(diagIndex)));
  }

  recordedExpectedToken(handle: Handle, diagIndex: number, tokenIndex: number): Uint8Array | number {
    const h = handle as NativeHandle;
    const d = BigInt(diagIndex);
    const t = BigInt(tokenIndex);
    return copyBytesResult((od, ol) => this.native.galley_recorded_expected_token(h, d, t, ptr(od), ptr(ol)));
  }

  recordedContextCount(handle: Handle, diagIndex: number): number {
    return Number(this.native.galley_recorded_context_count(handle as NativeHandle, BigInt(diagIndex)));
  }

  recordedContextName(handle: Handle, diagIndex: number, contextIndex: number): Uint8Array | number {
    const h = handle as NativeHandle;
    const d = BigInt(diagIndex);
    const c = BigInt(contextIndex);
    return copyBytesResult((od, ol) => this.native.galley_recorded_context_name(h, d, c, ptr(od), ptr(ol)));
  }

  recordedRecoveryKind(handle: Handle, diagIndex: number): number {
    return Number(this.native.galley_recorded_diagnostic_recovery_kind(handle as NativeHandle, BigInt(diagIndex)));
  }

  recordedRecoveryTerminal(handle: Handle, diagIndex: number): Uint8Array | number {
    const h = handle as NativeHandle;
    const d = BigInt(diagIndex);
    return copyBytesResult((od, ol) => this.native.galley_recorded_recovery_terminal(h, d, ptr(od), ptr(ol)));
  }

  recordedRecoveryResume(handle: Handle, diagIndex: number): number {
    const out = i64Out();
    const status = this.native.galley_recorded_recovery_resume(handle as NativeHandle, BigInt(diagIndex), ptr(out));
    if (status < 0n) return Number(status);
    return Number(out[0]);
  }

  recordedRecoveryLhsVariable(handle: Handle, diagIndex: number): string | number {
    const h = handle as NativeHandle;
    const d = BigInt(diagIndex);
    return stringResult((od, ol) => this.native.galley_recorded_recovery_lhs_variable(h, d, ptr(od), ptr(ol)));
  }

  recordedRecoveryProduction(handle: Handle, diagIndex: number): [string, number] | number {
    const h = handle as NativeHandle;
    const d = BigInt(diagIndex);
    const outVar = ptrOut64();
    const outLen = ptrOut64();
    const outIdx = u32Out();
    const status = this.native.galley_recorded_recovery_production(h, d, ptr(outVar), ptr(outLen), ptr(outIdx));
    if (status < 0n) return Number(status);
    return [new TextDecoder().decode(readBytes(outVar[0], outLen[0])), outIdx[0]];
  }

  recordedRecoveryOccurrence(handle: Handle, diagIndex: number): [string, number, number, string] | number {
    const h = handle as NativeHandle;
    const d = BigInt(diagIndex);
    const outParent = ptrOut64();
    const outParentLen = ptrOut64();
    const outRhs = u32Out();
    const outSym = u32Out();
    const outVar = ptrOut64();
    const outVarLen = ptrOut64();
    const status = this.native.galley_recorded_recovery_occurrence(h, d, ptr(outParent), ptr(outParentLen), ptr(outRhs), ptr(outSym), ptr(outVar), ptr(outVarLen));
    if (status < 0n) return Number(status);
    const decoder = new TextDecoder();
    return [
      decoder.decode(readBytes(outParent[0], outParentLen[0])),
      outRhs[0],
      outSym[0],
      decoder.decode(readBytes(outVar[0], outVarLen[0])),
    ];
  }

  // -- procedure hooks ----------------------------------------------------------

  procCurrentNode(session: Handle, hook: HookTicket): bigint | number {
    const node = this.native.galley_procedure_current_node(session as NativeHandle, hook);
    return node < 0n ? Number(node) : node;
  }

  procDoor(session: Handle, hook: HookTicket): { status: number; door: Handle } {
    const outDoor = ptrOut64();
    const status = Number(this.native.galley_procedure_door(session as NativeHandle, hook, ptr(outDoor)));
    return { status, door: status < 0 ? null : Number(outDoor[0]) };
  }

  procSetCurrentNode(session: Handle, hook: HookTicket, generation: number, node: bigint): number {
    return Number(this.native.galley_procedure_set_current_node(session as NativeHandle, hook, generation, node));
  }

  procDropSelf(session: Handle, hook: HookTicket): number {
    return Number(this.native.galley_procedure_drop_self(session as NativeHandle, hook));
  }

  procDropChildren(session: Handle, hook: HookTicket): number {
    return Number(this.native.galley_procedure_drop_children(session as NativeHandle, hook));
  }

  procDropIfEmpty(session: Handle, hook: HookTicket): number {
    return Number(this.native.galley_procedure_drop_if_empty(session as NativeHandle, hook));
  }


  procContextLine(session: Handle, hook: HookTicket): number {
    return Number(this.native.galley_procedure_context_line(session as NativeHandle, hook));
  }

  procContextColumn(session: Handle, hook: HookTicket): number {
    return Number(this.native.galley_procedure_context_column(session as NativeHandle, hook));
  }

  procReportSemanticError(session: Handle, hook: HookTicket, message: Uint8Array): number {
    return Number(
      this.native.galley_procedure_report_semantic_error(
        session as NativeHandle,
        hook,
        ptr(message),
        BigInt(message.length),
      ),
    );
  }

  hookGeneration(door: Handle): number {
    const outGeneration = ptrOut64();
    const status = this.native.galley_hook_generation(door as NativeHandle, ptr(outGeneration));
    return status < 0n ? Number(status) : Number(outGeneration[0]);
  }

}

const portCache = new Map<string, BunPort>();

/** Port for the language directory's library, cached per resolved path. */
export function getBunPort(languagePath: string): BunPort {
  return portForLibrary(findLibrary(languagePath));
}

/** Port for an explicit library file, cached per resolved path. */
export function getBunPortFromFile(filePath: string): BunPort {
  return portForLibrary(findLibraryFile(filePath));
}

function portForLibrary(libPath: string): BunPort {
  const cached = portCache.get(libPath);
  if (cached) return cached;
  const port = new BunPort(openNative(libPath).symbols, libPath);
  // Dispatch rides with the port, not the Session: every consumer of the
  // port (adapter or universal loader) gets working procedure hooks.
  installDispatch(port);
  portCache.set(libPath, port);
  return port;
}
