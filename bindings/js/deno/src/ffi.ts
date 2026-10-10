/**
 * Deno adapter for the Galley JavaScript bindings: `Deno.dlopen` bindings
 * over `bindings/c/galley.h`, implementing the core `FfiPort`.
 *
 * Zero dependencies: no npm packages, no build step for the adapter itself.
 * The core (`@sanbus/galley-core`, resolved to its compiled `dist` via the
 * package `deno.json` import map) owns all session logic; memory copying
 * and integer normalization live here. Requires `--allow-ffi` (dlopen)
 * and `--allow-read` (library discovery, `parseFile`).
 */

import type { FfiPort, NodeFamily, Handle, HookTicket, DispatchHandler, SessionCOptions, SnapshotColumns } from "@sanbus/galley-core";
import { GalleyError, INVALID_NODE, NATIVE_LITTLE_ENDIAN, NO_VARIABLE, Status } from "@sanbus/galley-core";
import { GenerationBigInt, resolveArtifactFile, resolveAdapterArtifact, artifactFileName, canonicalResolvePath, SHARED_NATIVE_LIBRARY_BASE } from "@sanbus/galley-core/internal";
import { installDispatch } from "./dispatch.ts";

const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

/** Callable view of the native symbols (see `BASE_SYMBOLS` below). */
type FfiOut = Uint8Array | Uint32Array | Int32Array | BigUint64Array | BigInt64Array;

/**
 * The node, tree and walk calls both doors expose, keyed by the C name after
 * `galley_`. Each is declared once here and once in `DOOR_SYMBOLS`, and bound
 * twice: `galley_<name>` over a session handle and `galley_hook_<name>` over
 * a parse's door, with identical signatures.
 */
interface DoorCalls {
  node_child_count(handle: Deno.PointerValue, generation: bigint, node: bigint): number | bigint;
  node_first_child(handle: Deno.PointerValue, generation: bigint, node: bigint): number | bigint;
  node_last_child(handle: Deno.PointerValue, generation: bigint, node: bigint): number | bigint;
  node_next_sibling(handle: Deno.PointerValue, generation: bigint, node: bigint): number | bigint;
  node_prior_sibling(handle: Deno.PointerValue, generation: bigint, node: bigint): number | bigint;
  node_parent(handle: Deno.PointerValue, generation: bigint, node: bigint): number | bigint;
  node_span(handle: Deno.PointerValue, generation: bigint, node: bigint, outStart: FfiOut, outLen: FfiOut): bigint;
  node_symbol_name(handle: Deno.PointerValue, generation: bigint, node: bigint, outData: FfiOut, outLen: FfiOut): bigint;
  node_variable_index(handle: Deno.PointerValue, generation: bigint, node: bigint): number | bigint;
  node_text(handle: Deno.PointerValue, generation: bigint, node: bigint, outData: FfiOut, outLen: FfiOut): bigint;
  node_line_column(handle: Deno.PointerValue, generation: bigint, node: bigint, outLine: FfiOut, outCol: FfiOut): bigint;
  walk_next(handle: Deno.PointerValue, cursor: ArrayBuffer): bigint;
  tree_append_children(handle: Deno.PointerValue, generation: bigint, parent: bigint, firstGeneration: bigint, first: bigint): bigint;
  tree_insert_before(handle: Deno.PointerValue, generation: bigint, target: bigint, firstGeneration: bigint, first: bigint): bigint;
  tree_insert_after(handle: Deno.PointerValue, generation: bigint, target: bigint, firstGeneration: bigint, first: bigint): bigint;
  tree_remove_siblings(handle: Deno.PointerValue, generation: bigint, node: bigint, count: number, outHead: FfiOut): bigint;
  tree_remove_self(handle: Deno.PointerValue, generation: bigint, node: bigint, outHead: FfiOut): bigint;
  tree_clean_children(handle: Deno.PointerValue, generation: bigint, node: bigint, outHead: FfiOut): bigint;
  tree_insert_children_at(handle: Deno.PointerValue, generation: bigint, parent: bigint, index: number, firstGeneration: bigint, first: bigint): bigint;
  tree_remove_children_at(handle: Deno.PointerValue, generation: bigint, parent: bigint, index: number, count: number, outHead: FfiOut): bigint;
}

/** `DoorCalls` under one door's C names: `galley_<name>` or `galley_hook_<name>`. */
type DoorNames<Door extends "" | "hook_"> = {
  [Name in keyof DoorCalls as `galley_${Door}${Name & string}`]: DoorCalls[Name];
};

interface GalleySymbols extends DoorNames<"">, DoorNames<"hook_"> {
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
  galley_session_destroy(session: Deno.PointerValue): bigint;
  galley_session_set_message_override(session: Deno.PointerValue, name: FfiOut, nameLen: number, message: FfiOut, messageLen: number): bigint;
  galley_parse(session: Deno.PointerValue, data: FfiOut, len: number): bigint;
  galley_parse_file(session: Deno.PointerValue, path: FfiOut): bigint;
  galley_last_input(session: Deno.PointerValue, outData: FfiOut, outLen: FfiOut): bigint;
  galley_last_position(session: Deno.PointerValue, outLine: FfiOut, outCol: FfiOut): bigint;
  galley_node_count(session: Deno.PointerValue, generation: bigint): number | bigint;
  galley_reserve_nodes(session: Deno.PointerValue, capacity: bigint): bigint;
  galley_node_capacity(session: Deno.PointerValue): bigint;
  galley_root_node(session: Deno.PointerValue, outRoot: FfiOut, outGeneration: FfiOut): bigint;
  galley_tree_snapshot(
    session: Deno.PointerValue,
    generation: bigint,
    outParent: FfiOut,
    outFirstChild: FfiOut,
    outNext: FfiOut,
    outChildCount: FfiOut,
    outVariable: FfiOut,
    outSpanStart: FfiOut,
    outSpanLen: FfiOut,
    outIsSemanticError: FfiOut,
    outIsRecovered: FfiOut,
    capacity: bigint,
  ): bigint;
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
  galley_procedure_current_node(session: Deno.PointerValue, hook: bigint): bigint;
  galley_procedure_door(session: Deno.PointerValue, hook: bigint, outDoor: FfiOut): bigint;
  galley_procedure_set_current_node(session: Deno.PointerValue, hook: bigint, generation: bigint, node: bigint): bigint;
  galley_procedure_drop_self(session: Deno.PointerValue, hook: bigint): bigint;
  galley_procedure_drop_children(session: Deno.PointerValue, hook: bigint): bigint;
  galley_procedure_drop_if_empty(session: Deno.PointerValue, hook: bigint): bigint;
  galley_procedure_context_line(session: Deno.PointerValue, hook: bigint): bigint;
  galley_procedure_context_column(session: Deno.PointerValue, hook: bigint): bigint;
  galley_procedure_report_semantic_error(session: Deno.PointerValue, hook: bigint, message: FfiOut, messageLen: number): bigint;
  galley_hook_generation(door: Deno.PointerValue, outGeneration: FfiOut): bigint;
  // host hooks (see galley_session_set_hooks in galley.h)
  galley_hooks_count(): bigint;
  galley_hooks_name_data(index: bigint): bigint;
  galley_hooks_name_length(index: bigint): bigint;
  galley_session_set_hooks(session: Deno.PointerValue, dispatch: Deno.PointerValue, hookHandle: bigint, enabled: FfiOut, enabledCount: bigint): bigint;
}

// --- library discovery -------------------------------------------------
// One place, named up front: the language directory must hold the
// adapter's standard-named library file or the shared native library
// `galley build` leaves (it serves every native adapter). Anything else
// is a loud error naming both tried paths, never a search.

const BUILD_HINT =
  "Build it first: npx galley build <language-dir>\n" +
  `That leaves ${artifactFileName(SHARED_NATIVE_LIBRARY_BASE, Deno.build.os)} in the directory ` +
  `(or deno task build in your language dir for the adapter-named ${libFileName()}).`;

export function libFileName(base = "galley-js-deno"): string {
  return artifactFileName(base, Deno.build.os);
}

function exists(filePath: string): boolean {
  try {
    Deno.statSync(filePath);
    return true;
  } catch {
    return false;
  }
}

// Identity lexical step (Deno reports the path it was given, as
// before); the shared helper still canonicalizes existing files and
// keeps the absent-file fallback semantics in one place.
function resolveCanonical(candidate: string): string {
  return canonicalResolvePath(candidate, (lexical) => lexical, Deno.realPathSync);
}

export function findLibrary(languagePath: string): string {
  const joinPath = (directory: string, file: string): string =>
    directory.endsWith("/") ? directory + file : `${directory}/${file}`;
  return resolveAdapterArtifact(
    languagePath,
    libFileName(),
    artifactFileName(SHARED_NATIVE_LIBRARY_BASE, Deno.build.os),
    joinPath,
    {
      resolvePath: resolveCanonical,
      existsSync: exists,
      buildHint: BUILD_HINT,
    },
  );
}

/** Explicit-file twin of {@link findLibrary}: names the library itself. */
export function findLibraryFile(filePath: string): string {
  return resolveArtifactFile(filePath, {
    resolvePath: resolveCanonical,
    existsSync: exists,
    buildHint: BUILD_HINT,
  });
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
  galley_session_destroy: { parameters: ["pointer"], result: "i64" },
  galley_session_set_message_override: { parameters: ["pointer", "buffer", "usize", "buffer", "usize"], result: "i64" },
  galley_parse: { parameters: ["pointer", "buffer", "usize"], result: "i64" },
  galley_parse_file: { parameters: ["pointer", "buffer"], result: "i64" },
  galley_last_input: { parameters: ["pointer", "buffer", "buffer"], result: "i64" },
  galley_last_position: { parameters: ["pointer", "buffer", "buffer"], result: "i64" },
  galley_node_count: { parameters: ["pointer", "u64"], result: "i64" },
  galley_reserve_nodes: { parameters: ["pointer", "u64"], result: "i64" },
  galley_node_capacity: { parameters: ["pointer"], result: "i64" },
  galley_root_node: { parameters: ["pointer", "buffer", "buffer"], result: "i64" },
  galley_tree_snapshot: {
    parameters: ["pointer", "u64", "buffer", "buffer", "buffer", "buffer", "buffer", "buffer", "buffer", "buffer", "buffer", "u64"],
    result: "i64",
  },
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
  galley_procedure_current_node: { parameters: ["pointer", "u64"], result: "i64" },
  galley_procedure_door: { parameters: ["pointer", "u64", "buffer"], result: "i64" },
  galley_procedure_set_current_node: { parameters: ["pointer", "u64", "u64", "u64"], result: "i64" },
  galley_procedure_drop_self: { parameters: ["pointer", "u64"], result: "i64" },
  galley_procedure_drop_children: { parameters: ["pointer", "u64"], result: "i64" },
  galley_procedure_drop_if_empty: { parameters: ["pointer", "u64"], result: "i64" },
  galley_procedure_context_line: { parameters: ["pointer", "u64"], result: "i64" },
  galley_procedure_context_column: { parameters: ["pointer", "u64"], result: "i64" },
  galley_procedure_report_semantic_error: { parameters: ["pointer", "u64", "buffer", "usize"], result: "i64" },
  galley_hook_generation: { parameters: ["pointer", "buffer"], result: "i64" },
} as const;

/**
 * The node, tree and walk symbols, declared once and opened under both
 * prefixes (see `doorSymbols`).
 */
const DOOR_SYMBOLS = {
  node_child_count: { parameters: ["pointer", "u64", "u64"], result: "i64" },
  node_first_child: { parameters: ["pointer", "u64", "u64"], result: "i64" },
  node_last_child: { parameters: ["pointer", "u64", "u64"], result: "i64" },
  node_next_sibling: { parameters: ["pointer", "u64", "u64"], result: "i64" },
  node_prior_sibling: { parameters: ["pointer", "u64", "u64"], result: "i64" },
  node_parent: { parameters: ["pointer", "u64", "u64"], result: "i64" },
  node_span: { parameters: ["pointer", "u64", "u64", "buffer", "buffer"], result: "i64" },
  node_symbol_name: { parameters: ["pointer", "u64", "u64", "buffer", "buffer"], result: "i64" },
  node_variable_index: { parameters: ["pointer", "u64", "u64"], result: "i64" },
  node_text: { parameters: ["pointer", "u64", "u64", "buffer", "buffer"], result: "i64" },
  node_line_column: { parameters: ["pointer", "u64", "u64", "buffer", "buffer"], result: "i64" },
  walk_next: { parameters: ["pointer", "buffer"], result: "i64" },
  tree_append_children: { parameters: ["pointer", "u64", "u64", "u64", "u64"], result: "i64" },
  tree_insert_before: { parameters: ["pointer", "u64", "u64", "u64", "u64"], result: "i64" },
  tree_insert_after: { parameters: ["pointer", "u64", "u64", "u64", "u64"], result: "i64" },
  tree_remove_siblings: { parameters: ["pointer", "u64", "u64", "usize", "buffer"], result: "i64" },
  tree_remove_self: { parameters: ["pointer", "u64", "u64", "buffer"], result: "i64" },
  tree_clean_children: { parameters: ["pointer", "u64", "u64", "buffer"], result: "i64" },
  tree_insert_children_at: { parameters: ["pointer", "u64", "u64", "usize", "u64", "u64"], result: "i64" },
  tree_remove_children_at: { parameters: ["pointer", "u64", "u64", "usize", "usize", "buffer"], result: "i64" },
} as const satisfies Record<keyof DoorCalls, unknown>;

/** `DOOR_SYMBOLS` under one door's C names: `galley_<name>` or `galley_hook_<name>`. */
function doorSymbols(door: "" | "hook_") {
  return Object.fromEntries(
    Object.entries(DOOR_SYMBOLS).map(([name, symbol]) => [`galley_${door}${name}`, symbol]),
  ) as {
    [Name in keyof typeof DOOR_SYMBOLS as `galley_${typeof door}${Name}`]: (typeof DOOR_SYMBOLS)[Name];
  };
}

const HOOK_SYMBOLS = {
  galley_hooks_count: { parameters: [], result: "u64" },
  galley_hooks_name_data: { parameters: ["u64"], result: "u64" },
  galley_hooks_name_length: { parameters: ["u64"], result: "u64" },
  galley_session_set_hooks: { parameters: ["pointer", "pointer", "u64", "buffer", "u64"], result: "i64" },
} as const;

function openNative(libPath: string) {
  return Deno.dlopen(libPath, { ...BASE_SYMBOLS, ...doorSymbols(""), ...doorSymbols("hook_"), ...HOOK_SYMBOLS });
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

/**
 * One door's node and tree calls, bound from the twin registrations:
 * `galley_<name>` for the session door, `galley_hook_<name>` for the hook
 * door. Each capability is written here once and used for both. A refusal is
 * a negative status, which the core's door turns into the host's failure.
 * `first` and `second` are the port's two out-value words, shared by both
 * families: a JS realm is single-threaded and no crossing re-enters JS.
 */
function denoFamily(
  native: GalleySymbols,
  door: "" | "hook_",
  generations: GenerationBigInt,
  words: { firstWord: BigUint64Array; secondWord: BigUint64Array; firstHalf: Uint32Array; secondHalf: Uint32Array },
): NodeFamily {
  const calls = native as unknown as Record<string, unknown>;
  const bound = <Name extends keyof DoorCalls>(name: Name): DoorCalls[Name] =>
    calls[`galley_${door}${name}`] as DoorCalls[Name];
  const { firstWord, secondWord, firstHalf, secondHalf } = words;
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
  const pointer = (handle: Handle) => handle as Deno.PointerValue;
  return {
    childCount: (handle, generation, node) => Number(childCount(pointer(handle), generations.of(generation), node)),
    firstChild: (handle, generation, node) => firstChild(pointer(handle), generations.of(generation), node),
    lastChild: (handle, generation, node) => lastChild(pointer(handle), generations.of(generation), node),
    nextSibling: (handle, generation, node) => nextSibling(pointer(handle), generations.of(generation), node),
    priorSibling: (handle, generation, node) => priorSibling(pointer(handle), generations.of(generation), node),
    parent: (handle, generation, node) => parent(pointer(handle), generations.of(generation), node),
    nodeSymbolName: (handle, generation, node) => {
      const status = symbolName(pointer(handle), generations.of(generation), node, firstWord, secondWord);
      return status < 0n ? Number(status) : readBytes(firstWord[0], secondWord[0]);
    },
    nodeText: (handle, generation, node) => {
      const status = text(pointer(handle), generations.of(generation), node, firstWord, secondWord);
      return status < 0n ? Number(status) : readBytes(firstWord[0], secondWord[0]);
    },
    nodeSpan: (handle, generation, node) => {
      const status = span(pointer(handle), generations.of(generation), node, firstWord, secondWord);
      return status < 0n ? Number(status) : [firstWord[0], secondWord[0]];
    },
    nodeLineColumn: (handle, generation, node) => {
      const status = lineColumn(pointer(handle), generations.of(generation), node, firstHalf, secondHalf);
      return status < 0n ? Number(status) : [firstHalf[0], secondHalf[0]];
    },
    nodeVariableIndex: (handle, generation, node) => {
      const index = variableIndex(pointer(handle), generations.of(generation), node);
      return index === NO_VARIABLE ? null : Number(index);
    },
    walkNext: (handle, cursor) => Number(walkNext(pointer(handle), cursor)),
    treeAppendChildren: (handle, generation, parentNode, firstGeneration, first) =>
      Number(appendChildren(pointer(handle), generations.of(generation), parentNode, BigInt(firstGeneration), first)),
    treeInsertBefore: (handle, generation, target, firstGeneration, first) =>
      Number(insertBefore(pointer(handle), generations.of(generation), target, BigInt(firstGeneration), first)),
    treeInsertAfter: (handle, generation, target, firstGeneration, first) =>
      Number(insertAfter(pointer(handle), generations.of(generation), target, BigInt(firstGeneration), first)),
    treeRemoveSiblings: (handle, generation, node, count) => {
      const status = removeSiblings(pointer(handle), generations.of(generation), node, count, firstWord);
      return { status: Number(status), head: firstWord[0] };
    },
    treeRemoveSelf: (handle, generation, node) => {
      const status = removeSelf(pointer(handle), generations.of(generation), node, firstWord);
      return { status: Number(status), head: firstWord[0] };
    },
    treeCleanChildren: (handle, generation, node) => {
      const status = cleanChildren(pointer(handle), generations.of(generation), node, firstWord);
      return { status: Number(status), head: firstWord[0] };
    },
    treeInsertChildrenAt: (handle, generation, parentNode, index, firstGeneration, first) =>
      Number(insertChildrenAt(pointer(handle), generations.of(generation), parentNode, index, BigInt(firstGeneration), first)),
    treeRemoveChildrenAt: (handle, generation, parentNode, index, count) => {
      const status = removeChildrenAt(pointer(handle), generations.of(generation), parentNode, index, count, firstWord);
      return { status: Number(status), head: firstWord[0] };
    },
  };
}


export class DenoPort implements FfiPort {
  hookDispatch: DispatchHandler | null = null;
  readonly native: GalleySymbols;
  readonly libraryPath: string;
  /**
   * The native address of this port's one `UnsafeCallback`, handed to the
   * library with every session's hooks; set by `installDispatch`. Each
   * worker owns its own callback, so the address is per session, not per
   * library.
   */
  dispatchPointer: Deno.PointerValue = null;
  /**
   * The out-value slots every node crossing, on either door, writes into: two
   * 64-bit words, each also viewed as one 32-bit value at the same address.
   * One set per port is enough because a JS realm is single-threaded and no
   * node crossing re-enters JS; results are copied out before the call
   * returns, so nothing is allocated per call.
   */
  readonly #outBuffer = new ArrayBuffer(16);
  readonly #firstWord = new BigUint64Array(this.#outBuffer, 0, 1);
  readonly #secondWord = new BigUint64Array(this.#outBuffer, 8, 1);
  readonly #firstHalf = new Uint32Array(this.#outBuffer, 0, 1);
  readonly #secondHalf = new Uint32Array(this.#outBuffer, 8, 1);

  readonly session: NodeFamily;
  readonly hook: NodeFamily;

  constructor(native: GalleySymbols, libraryPath: string) {
    this.native = native;
    this.libraryPath = libraryPath;
    const words = {
      firstWord: this.#firstWord,
      secondWord: this.#secondWord,
      firstHalf: this.#firstHalf,
      secondHalf: this.#secondHalf,
    };
    this.session = denoFamily(native, "", this.#generation, words);
    this.hook = denoFamily(native, "hook_", this.#generation, words);
  }

  setSessionHooks(session: Handle, hookHandle: number, enabled: Uint8Array): number {
    return Number(
      this.native.galley_session_set_hooks(
        session as Deno.PointerValue,
        this.dispatchPointer,
        BigInt(hookHandle),
        enabled,
        BigInt(enabled.length),
      ),
    );
  }

  #hookNameTable: string[] | null = null;

  hookNames(): string[] {
    if (this.#hookNameTable !== null) return this.#hookNameTable;
    const table: string[] = [];
    const total = this.native.galley_hooks_count();
    for (let index = 0n; index < total; index++) {
      const address = this.native.galley_hooks_name_data(index);
      if (address === 0n) break;
      table.push(textDecoder.decode(readBytes(address, this.native.galley_hooks_name_length(index))));
    }
    this.#hookNameTable = table;
    return table;
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

  destroySession(handle: Handle): number {
    return Number(this.native.galley_session_destroy(handle as Deno.PointerValue));
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

  lastPosition(handle: Handle): [number, number] | number {
    const outLine = u32Out();
    const outCol = u32Out();
    const status = this.native.galley_last_position(handle as Deno.PointerValue, outLine, outCol);
    if (status < 0n) return Number(status);
    return [outLine[0], outCol[0]];
  }

  lastInput(handle: Handle): Uint8Array | number {
    const h = handle as Deno.PointerValue;
    const outData = ptrOut();
    const outLen = lenOut();
    const status = this.native.galley_last_input(h, outData, outLen);
    if (status < 0n) return Number(status);
    return readBytes(outData[0], outLen[0]);
  }

  // -- arena and navigation ----------------------------------------------

  /** The generation as the BigInt a `u64` parameter needs to keep V8's fast call (a Number there takes the slow path). */
  readonly #generation = new GenerationBigInt();

  nodeCount(handle: Handle, generation: number): number {
    return Number(this.native.galley_node_count(handle as Deno.PointerValue, this.#generation.of(generation)));
  }

  reserveNodes(handle: Handle, capacity: bigint): number {
    return Number(this.native.galley_reserve_nodes(handle as Deno.PointerValue, capacity));
  }

  nodeCapacity(handle: Handle): number {
    return Number(this.native.galley_node_capacity(handle as Deno.PointerValue));
  }

  rootNode(handle: Handle): { status: number; root: bigint; generation: number } {
    this.#firstWord[0] = INVALID_NODE;
    const status = this.native.galley_root_node(handle as Deno.PointerValue, this.#firstWord, this.#secondWord);
    return { status: Number(status), root: this.#firstWord[0], generation: Number(this.#secondWord[0]) };
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
      const total = this.native.galley_tree_snapshot(
        handle as Deno.PointerValue, this.#generation.of(generation), parent, firstChild, next, childCount,
        variable, spanStart, spanLen, isSemanticError, isRecovered, BigInt(count),
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

  // -- procedure hooks ----------------------------------------------------------

  procCurrentNode(session: Handle, hook: HookTicket): bigint | number {
    const node = this.native.galley_procedure_current_node(session as Deno.PointerValue, hook);
    return node < 0n ? Number(node) : node;
  }

  procDoor(session: Handle, hook: HookTicket): { status: number; door: Handle } {
    const outDoor = lenOut();
    const status = Number(this.native.galley_procedure_door(session as Deno.PointerValue, hook, outDoor));
    return { status, door: status < 0 ? null : Deno.UnsafePointer.create(outDoor[0]) };
  }

  procSetCurrentNode(session: Handle, hook: HookTicket, generation: number, node: bigint): number {
    return Number(
      this.native.galley_procedure_set_current_node(session as Deno.PointerValue, hook, this.#generation.of(generation), node),
    );
  }

  procDropSelf(session: Handle, hook: HookTicket): number {
    return Number(this.native.galley_procedure_drop_self(session as Deno.PointerValue, hook));
  }

  procDropChildren(session: Handle, hook: HookTicket): number {
    return Number(this.native.galley_procedure_drop_children(session as Deno.PointerValue, hook));
  }

  procDropIfEmpty(session: Handle, hook: HookTicket): number {
    return Number(this.native.galley_procedure_drop_if_empty(session as Deno.PointerValue, hook));
  }


  procContextLine(session: Handle, hook: HookTicket): number {
    return Number(this.native.galley_procedure_context_line(session as Deno.PointerValue, hook));
  }

  procContextColumn(session: Handle, hook: HookTicket): number {
    return Number(this.native.galley_procedure_context_column(session as Deno.PointerValue, hook));
  }

  procReportSemanticError(session: Handle, hook: HookTicket, message: Uint8Array): number {
    return Number(
      this.native.galley_procedure_report_semantic_error(session as Deno.PointerValue, hook, message, message.length),
    );
  }

  hookGeneration(door: Handle): number {
    const outGeneration = lenOut();
    const status = this.native.galley_hook_generation(door as Deno.PointerValue, outGeneration);
    return status < 0n ? Number(status) : Number(outGeneration[0]);
  }

}

const portCache = new Map<string, DenoPort>();

/** Port for the language directory's library, cached per resolved path. */
export function getDenoPort(languagePath: string): DenoPort {
  return portForLibrary(findLibrary(languagePath));
}

/** Port for an explicit library file, cached per resolved path. */
export function getDenoPortFromFile(filePath: string): DenoPort {
  return portForLibrary(findLibraryFile(filePath));
}

function portForLibrary(libPath: string): DenoPort {
  const cached = portCache.get(libPath);
  if (cached) return cached;
  const port = new DenoPort(openNative(libPath).symbols as unknown as GalleySymbols, libPath);
  // Dispatch rides with the port, not the Session: every consumer of the
  // port (adapter or universal loader) gets working procedure hooks.
  installDispatch(port);
  portCache.set(libPath, port);
  return port;
}
