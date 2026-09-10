/**
 * Node adapter for the Galley JavaScript bindings: low-level calls into the
 * per-grammar NAPI addon (`bindings/js/node/addon.c`, compiled next to the
 * grammar by `galley-js-node`), implementing the core `FfiPort`.
 *
 * This is the single FFI boundary for the Node runtime. Library discovery, memory copying, and integer normalization live here;
 * all session logic lives in `@sanbus/galley-core`. No caller touches the
 * addon directly outside this module and `dispatch.ts`.
 */

import { Buffer } from "node:buffer";
import * as fs from "node:fs";
import { createRequire } from "node:module";
import * as path from "node:path";
import process from "node:process";
import type {
  FfiPort,
  Handle,
  SessionCOptions,
  TreeSnapshot,
  WalkedStep,
} from "@sanbus/galley-core";
import {
  GalleyError,
  MissingArtifactError,
  resolveArtifact,
  artifactFileName,
} from "@sanbus/galley-core";
const require = createRequire(import.meta.url);

/**
 * One bound parser library: every `galley_*` function as a direct call
 * returning NAPI-natural values (bigint for 64-bit, number for 32-bit and
 * below, Buffer for byte pairs, string for text, tuples for scalar outs).
 * Optional JS-shim entries are null on libraries that predate them.
 */
export interface AddonApi {
  // version / metadata
  galley_version(): string | null;
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
  galley_status_string(status: bigint): string | null;

  // symbol table
  galley_symbol_name(session: bigint, index: bigint): Buffer | null;
  galley_symbol_is_terminal(session: bigint, index: bigint): number;
  galley_variable_name(session: bigint, index: bigint): Buffer | null;

  // session
  galley_session_create(): bigint;
  galley_session_create_ex(options: SessionCOptionsOut): bigint;
  galley_session_destroy(session: bigint): void;
  galley_session_set_message_override(
    session: bigint,
    name: string,
    message: string,
  ): bigint;

  // parse
  galley_parse_sentinel(session: bigint, input: string): bigint;
  galley_parse(session: bigint, data: Uint8Array, len: number): bigint;
  galley_parse_file(session: bigint, filePath: string): bigint;
  galley_last_position(session: bigint): [number, number] | null;

  // node / tree
  galley_node_count(session: bigint): bigint;
  galley_reserve_nodes(session: bigint, capacity: bigint): bigint;
  galley_node_capacity(session: bigint): bigint;
  galley_root_node(session: bigint): bigint;
  galley_node_is_valid(session: bigint, node: bigint): number;
  galley_node_child_count(session: bigint, node: bigint): number;
  galley_node_first_child(session: bigint, node: bigint): bigint;
  galley_node_last_child(session: bigint, node: bigint): bigint;
  galley_node_next_sibling(session: bigint, node: bigint): bigint;
  galley_node_prior_sibling(session: bigint, node: bigint): bigint;
  galley_node_parent(session: bigint, node: bigint): bigint;
  galley_walker_create(session: bigint, node: bigint, skipSemanticErrors: number): bigint;
  galley_walker_next(walker: bigint): [bigint, number, number] | null;
  galley_walker_skip_children(walker: bigint): void;
  galley_walker_destroy(walker: bigint): void;
  galley_node_symbol_name(session: bigint, node: bigint): Buffer | null;
  galley_node_text(session: bigint, node: bigint): Buffer | null;
  galley_node_span(session: bigint, node: bigint): [bigint, bigint] | null;
  galley_node_line_column(session: bigint, node: bigint): [number, number] | null;
  galley_node_variable_index(session: bigint, node: bigint): bigint;
  galley_tree_snapshot(
    session: bigint,
    outParent: BigUint64Array,
    outFirstChild: BigUint64Array,
    outNext: BigUint64Array,
    outChildCount: Uint32Array,
    outVariable: BigInt64Array,
    outSpanStart: BigUint64Array,
    outSpanLen: BigUint64Array,
    capacity: bigint,
  ): bigint;

  // diagnostics (singular)
  galley_has_diagnostic(session: bigint): number;
  galley_diagnostic_kind(session: bigint): bigint;
  galley_diagnostic_message(session: bigint): string | null;
  galley_diagnostic_message_ansi(session: bigint): string | null;
  galley_diagnostic_position(session: bigint): [number, number] | null;
  galley_diagnostic_unexpected_token(session: bigint): Buffer | null;
  galley_diagnostic_expected_count(session: bigint): bigint;
  galley_diagnostic_expected_at(session: bigint, index: bigint): Buffer | null;
  galley_diagnostic_context_count(session: bigint): bigint;
  galley_diagnostic_context_at(session: bigint, index: bigint): Buffer | null;
  galley_diagnostic_indentation(session: bigint): [number, number] | null;
  galley_syntax_error_count(session: bigint): bigint;
  galley_semantic_error_count(session: bigint): bigint;
  galley_diagnostic_semantic(session: bigint): [string, string] | null;
  galley_diagnostic_recovery_kind(session: bigint): bigint;
  galley_diagnostic_recovery_terminal(session: bigint): Buffer | null;
  galley_diagnostic_recovery_resume(session: bigint): number | null;
  galley_diagnostic_recovery_lhs_variable(session: bigint): string | null;
  galley_diagnostic_recovery_production(session: bigint): [string, number] | null;
  galley_diagnostic_recovery_occurrence(
    session: bigint,
  ): [string, number, number, string] | null;

  // recorded
  galley_recorded_diagnostic_count(session: bigint): bigint;
  galley_recorded_diagnostic_kind(session: bigint, index: bigint): bigint;
  galley_recorded_diagnostic_position(
    session: bigint,
    index: bigint,
  ): [number, number] | null;
  galley_recorded_unexpected_token(session: bigint, index: bigint): Buffer | null;
  galley_recorded_diagnostic_message(session: bigint, index: bigint): string | null;
  galley_recorded_indentation(session: bigint, index: bigint): [number, number] | null;
  galley_recorded_semantic(session: bigint, index: bigint): [string, string] | null;
  galley_recorded_expected_count(session: bigint, index: bigint): bigint;
  galley_recorded_expected_token(
    session: bigint,
    index: bigint,
    tokenIndex: bigint,
  ): Buffer | null;
  galley_recorded_context_count(session: bigint, index: bigint): bigint;
  galley_recorded_context_name(
    session: bigint,
    index: bigint,
    contextIndex: bigint,
  ): Buffer | null;
  galley_recorded_diagnostic_recovery_kind(session: bigint, index: bigint): bigint;
  galley_recorded_recovery_terminal(session: bigint, index: bigint): Buffer | null;
  galley_recorded_recovery_resume(session: bigint, index: bigint): number | null;
  galley_recorded_recovery_lhs_variable(session: bigint, index: bigint): string | null;
  galley_recorded_recovery_production(
    session: bigint,
    index: bigint,
  ): [string, number] | null;
  galley_recorded_recovery_occurrence(
    session: bigint,
    index: bigint,
  ): [string, number, number, string] | null;

  // tree editing
  galley_tree_append_children(session: bigint, parent: bigint, first: bigint): bigint;
  galley_tree_insert_before(session: bigint, target: bigint, first: bigint): bigint;
  galley_tree_insert_after(session: bigint, target: bigint, first: bigint): bigint;
  galley_tree_remove_siblings(session: bigint, node: bigint, count: bigint): [bigint, bigint];
  galley_tree_remove_self(session: bigint, node: bigint): [bigint, bigint];
  galley_tree_promote_children_over_wrapper(session: bigint, wrapper: bigint): [bigint, bigint];
  galley_tree_clean_children(session: bigint, node: bigint): [bigint, bigint];
  galley_tree_unlink_wrapper(session: bigint, wrapper: bigint): bigint;
  galley_tree_insert_children_at(
    session: bigint,
    parent: bigint,
    index: bigint,
    first: bigint,
  ): bigint;
  galley_tree_remove_children_at(
    session: bigint,
    parent: bigint,
    index: bigint,
    count: bigint,
  ): [bigint, bigint];

  // procedure dispatch (shared JS shim; see @sanbus/galley-core/build/shim.mjs)
  // ID path (current builds); the name-carrying symbol remains the fallback
  // for libraries that predate integer hook IDs. Null on libraries without
  // the shim (C procedures, stale builds).
  install_id_dispatch: ((callback: (id: number, args: bigint) => void) => void) | null;
  install_name_dispatch: ((callback: (name: string, args: bigint) => void) => void) | null;
  galley_js_procedure_count: (() => number) | null;
  galley_js_procedure_name: ((index: number) => string | null) | null;
  // selective dispatch gates (null on C-procedure or stale libraries)
  galley_js_procedure_enable: ((name: string) => number) | null;
  galley_js_procedure_clear: (() => void) | null;

  // procedure-hook state; tree queries use galley_node_* on the session
  galley_procedure_session(args: bigint): bigint;
  galley_procedure_current_node(args: bigint): bigint;
  galley_procedure_set_current_node(args: bigint, node: bigint): void;
  galley_procedure_drop_self(args: bigint): bigint;
  galley_procedure_drop_children(args: bigint): bigint;
  galley_procedure_drop_if_empty(args: bigint): bigint;
  galley_procedure_replace_with_children(args: bigint): bigint;
  galley_procedure_context_line(args: bigint): number;
  galley_procedure_context_column(args: bigint): number;
  galley_procedure_report_semantic_error(args: bigint, message: string): bigint;
}

/** Option fields as the addon reads them (camelCase mirrors SessionCOptions). */
export interface SessionCOptionsOut {
  maxErrors: number;
  recoveryWindow: number;
  stackOverflowRecovery: number;
  syntaxErrorStackDepth: number;
  verbosity: number;
  astPreallocationRatio: number;
  astPreallocationCap: bigint;
}

export interface GalleyFFI {
  libPath: string;
  api: AddonApi;
}

// Cached library and path
let cached: GalleyFFI | null = null;
let cachedPath: string | null = null;

// --- library discovery -------------------------------------------------
// One place, named up front: an explicit path or GALLEY_LIBRARY_PATH.
// Anything else is a loud error, never a search. The contract names the
// parser library; the addon lives beside it under addonFileName().

const BUILD_HINT =
  `Build it first: npx galley-js-node <language-dir>\n` +
  `or set GALLEY_LIBRARY_PATH=/path/to/${libFileName()}`;

export function libFileName(base = "galley-js-node"): string {
  return artifactFileName(base, process.platform);
}

export function addonFileName(base = "galley-js-node"): string {
  return `${base}.node`;
}

function exists(filePath: string): boolean {
  try {
    fs.accessSync(filePath);
    return true;
  } catch {
    return false;
  }
}

export function findLibrary(explicit?: string): string {
  return resolveArtifact(explicit, {
    getEnv: (name) => process.env[name],
    resolvePath: (candidate) => path.resolve(candidate),
    existsSync: exists,
    buildHint: BUILD_HINT,
  });
}

function findAddon(libPath: string): string {
  const candidate = path.join(path.dirname(libPath), addonFileName());
  if (!exists(candidate)) {
    throw new MissingArtifactError(`at ${candidate}`, BUILD_HINT);
  }
  return candidate;
}

// --- loader ------------------------------------------------------------

export function loadLibrary(explicitPath?: string): GalleyFFI {
  const normalizedExplicit = explicitPath ? path.resolve(explicitPath) : undefined;
  if (cached && (!normalizedExplicit || cachedPath === normalizedExplicit)) return cached;

  const libPath = findLibrary(normalizedExplicit);
  const addonPath = findAddon(libPath);
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const addon = require(addonPath) as { load(path: string): AddonApi };
  const api = addon.load(libPath);

  const ffi: GalleyFFI = { libPath, api };
  cached = ffi;
  cachedPath = libPath;
  return ffi;
}

// Helpers -----------------------------------------------------------------

export function toBigInt(value: bigint | number): bigint {
  return typeof value === "bigint" ? value : BigInt(value);
}

export function isOk(status: bigint | number): boolean {
  const n = typeof status === "bigint" ? status : BigInt(status);
  return n >= 0n;
}

export function toNumber(value: bigint | number): number {
  return typeof value === "bigint" ? Number(value) : value;
}

function bytesToString(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString("utf-8");
}

// --- FfiPort implementation ----------------------------------------------

/**
 * Node's {@link FfiPort}: normalizes the addon's direct returns into the
 * structured values the core expects. Byte pairs arrive as owned Buffers;
 * the core only sees owned bytes.
 */
export class NodePort implements FfiPort {
  readonly ffi: GalleyFFI;
  readonly libraryPath: string;

  constructor(ffi: GalleyFFI) {
    this.ffi = ffi;
    this.libraryPath = ffi.libPath;
  }

  private get api(): AddonApi {
    return this.ffi.api;
  }

  // -- module-level queries --------------------------------------------

  version(): string {
    return this.api.galley_version() ?? "";
  }

  parserType(): number {
    return toNumber(this.api.galley_parser_type());
  }

  errorRecoveryMode(): number {
    return toNumber(this.api.galley_error_recovery_mode());
  }

  hasAst(): boolean {
    return this.api.galley_has_ast() !== 0;
  }

  hasProcedures(): boolean {
    return this.api.galley_has_procedures() !== 0;
  }

  allowsNoAstTreeProcedures(): boolean {
    return this.api.galley_allows_no_ast_tree_procedures() !== 0;
  }

  sourceRetentionEnabled(): boolean {
    return this.api.galley_source_retention_enabled() !== 0;
  }

  hasPositionTracking(): boolean {
    return this.api.galley_has_position_tracking() !== 0;
  }

  hasInputStreaming(): boolean {
    return this.api.galley_has_input_streaming() !== 0;
  }

  usesVerbatim(): boolean {
    return this.api.galley_uses_verbatim() !== 0;
  }

  stackOverflowRecoveryAvailable(): boolean {
    return this.api.galley_stack_overflow_recovery_available() !== 0;
  }

  symbolCount(): number {
    return toNumber(this.api.galley_symbol_count());
  }

  variableCount(): number {
    return toNumber(this.api.galley_variable_count());
  }

  statusString(status: number): string | null {
    return this.api.galley_status_string(BigInt(status));
  }

  // -- sessions ---------------------------------------------------------

  createSession(options: SessionCOptions | null): Handle {
    let handle: bigint;
    if (options === null) {
      handle = this.api.galley_session_create();
    } else {
      handle = this.api.galley_session_create_ex({
        maxErrors: options.maxErrors,
        recoveryWindow: options.recoveryWindow,
        stackOverflowRecovery: options.stackOverflowRecovery,
        syntaxErrorStackDepth: options.syntaxErrorStackDepth,
        verbosity: options.verbosity,
        astPreallocationRatio: options.astPreallocationRatio,
        astPreallocationCap: options.astPreallocationCap,
      });
    }
    if (handle === 0n || handle === null || handle === undefined) return null;
    return handle;
  }

  destroySession(handle: Handle): void {
    this.api.galley_session_destroy(handle as bigint);
  }

  setMessageOverride(handle: Handle, name: Uint8Array, message: Uint8Array): number {
    return toNumber(
      this.api.galley_session_set_message_override(
        handle as bigint,
        bytesToString(name),
        bytesToString(message),
      ),
    );
  }

  // -- parsing ----------------------------------------------------------

  parse(handle: Handle, data: Uint8Array): number {
    return toNumber(this.api.galley_parse(handle as bigint, data, data.length));
  }

  parseFile(handle: Handle, filePath: string): number {
    return toNumber(this.api.galley_parse_file(handle as bigint, filePath));
  }

  lastPosition(handle: Handle): [number, number] | null {
    return this.api.galley_last_position(handle as bigint);
  }

  // -- arena and navigation ----------------------------------------------

  nodeCount(handle: Handle): number {
    return toNumber(this.api.galley_node_count(handle as bigint));
  }

  reserveNodes(handle: Handle, capacity: bigint): number {
    return toNumber(this.api.galley_reserve_nodes(handle as bigint, capacity));
  }

  nodeCapacity(handle: Handle): number {
    return toNumber(this.api.galley_node_capacity(handle as bigint));
  }

  rootNode(handle: Handle): bigint {
    return this.api.galley_root_node(handle as bigint);
  }

  nodeValid(handle: Handle, node: bigint): boolean {
    return this.api.galley_node_is_valid(handle as bigint, node) !== 0;
  }

  childCount(handle: Handle, node: bigint): number {
    return this.api.galley_node_child_count(handle as bigint, node);
  }

  firstChild(handle: Handle, node: bigint): bigint {
    return this.api.galley_node_first_child(handle as bigint, node);
  }

  lastChild(handle: Handle, node: bigint): bigint {
    return this.api.galley_node_last_child(handle as bigint, node);
  }

  nextSibling(handle: Handle, node: bigint): bigint {
    return this.api.galley_node_next_sibling(handle as bigint, node);
  }

  priorSibling(handle: Handle, node: bigint): bigint {
    return this.api.galley_node_prior_sibling(handle as bigint, node);
  }

  parent(handle: Handle, node: bigint): bigint {
    return this.api.galley_node_parent(handle as bigint, node);
  }

  treeSnapshot(handle: Handle): TreeSnapshot {
    // No await between sizing and filling, so the count cannot change.
    for (let attempt = 0; attempt < 2; attempt++) {
      const count = this.nodeCount(handle);
      const parent = new BigUint64Array(count);
      const firstChild = new BigUint64Array(count);
      const next = new BigUint64Array(count);
      const childCount = new Uint32Array(count);
      const variable = new BigInt64Array(count);
      const spanStart = new BigUint64Array(count);
      const spanLen = new BigUint64Array(count);
      const total = toNumber(
        this.api.galley_tree_snapshot(
          handle as bigint, parent, firstChild, next, childCount,
          variable, spanStart, spanLen, BigInt(count),
        ),
      );
      if (total < 0) throw new GalleyError("galley_tree_snapshot failed", total);
      if (total === count) {
        return { count, parent, firstChild, next, childCount, variable, spanStart, spanLen };
      }
    }
    throw new GalleyError("node count changed during galley_tree_snapshot", -8);
  }

  // -- walker ------------------------------------------------------------

  walkerCreate(handle: Handle, node: bigint, skipSemanticErrors: boolean): Handle | null {
    const walker = this.api.galley_walker_create(handle as bigint, node, skipSemanticErrors ? 1 : 0);
    if (walker === 0n || walker === null || walker === undefined) return null;
    return walker;
  }

  walkerNext(walker: Handle): WalkedStep | null {
    const step = this.api.galley_walker_next(walker as bigint);
    if (step === null) return null;
    return { node: step[0], depth: step[1], isSemanticError: step[2] !== 0 };
  }

  walkerSkipChildren(walker: Handle): void {
    this.api.galley_walker_skip_children(walker as bigint);
  }

  walkerDestroy(walker: Handle): void {
    this.api.galley_walker_destroy(walker as bigint);
  }

  // -- node accessors -----------------------------------------------------

  nodeSymbolName(handle: Handle, node: bigint): Uint8Array | null {
    return this.api.galley_node_symbol_name(handle as bigint, node);
  }

  nodeText(handle: Handle, node: bigint): Uint8Array | null {
    return this.api.galley_node_text(handle as bigint, node);
  }

  nodeSpan(handle: Handle, node: bigint): [bigint, bigint] | null {
    return this.api.galley_node_span(handle as bigint, node);
  }

  nodeLineColumn(handle: Handle, node: bigint): [number, number] | null {
    return this.api.galley_node_line_column(handle as bigint, node);
  }

  nodeVariableIndex(handle: Handle, node: bigint): number {
    return toNumber(this.api.galley_node_variable_index(handle as bigint, node));
  }

  symbolNameAt(handle: Handle, index: number): Uint8Array | null {
    return this.api.galley_symbol_name(handle as bigint, BigInt(index));
  }

  symbolIsTerminal(handle: Handle, index: number): boolean {
    return this.api.galley_symbol_is_terminal(handle as bigint, BigInt(index)) !== 0;
  }

  variableNameAt(handle: Handle, index: number): Uint8Array | null {
    return this.api.galley_variable_name(handle as bigint, BigInt(index));
  }

  // -- diagnostics ---------------------------------------------------------

  hasDiagnostic(handle: Handle): boolean {
    return this.api.galley_has_diagnostic(handle as bigint) !== 0;
  }

  diagnosticKind(handle: Handle): number {
    return toNumber(this.api.galley_diagnostic_kind(handle as bigint));
  }

  diagnosticMessage(handle: Handle): string | null {
    return this.api.galley_diagnostic_message(handle as bigint);
  }

  diagnosticMessageAnsi(handle: Handle): string | null {
    return this.api.galley_diagnostic_message_ansi(handle as bigint);
  }

  diagnosticPosition(handle: Handle): [number, number] | null {
    return this.api.galley_diagnostic_position(handle as bigint);
  }

  diagnosticUnexpectedToken(handle: Handle): Uint8Array | null {
    return this.api.galley_diagnostic_unexpected_token(handle as bigint);
  }

  diagnosticExpectedCount(handle: Handle): number {
    return toNumber(this.api.galley_diagnostic_expected_count(handle as bigint));
  }

  diagnosticExpectedAt(handle: Handle, index: number): Uint8Array | null {
    return this.api.galley_diagnostic_expected_at(handle as bigint, BigInt(index));
  }

  diagnosticContextCount(handle: Handle): number {
    return toNumber(this.api.galley_diagnostic_context_count(handle as bigint));
  }

  diagnosticContextAt(handle: Handle, index: number): Uint8Array | null {
    return this.api.galley_diagnostic_context_at(handle as bigint, BigInt(index));
  }

  syntaxErrorCount(handle: Handle): number {
    return toNumber(this.api.galley_syntax_error_count(handle as bigint));
  }

  semanticErrorCount(handle: Handle): number {
    return toNumber(this.api.galley_semantic_error_count(handle as bigint));
  }

  diagnosticSemantic(handle: Handle): [string, string] | null {
    return this.api.galley_diagnostic_semantic(handle as bigint);
  }

  diagnosticIndentation(handle: Handle): [number, number] | null {
    return this.api.galley_diagnostic_indentation(handle as bigint);
  }

  diagnosticRecoveryKind(handle: Handle): number {
    return toNumber(this.api.galley_diagnostic_recovery_kind(handle as bigint));
  }

  diagnosticRecoveryTerminal(handle: Handle): Uint8Array | null {
    return this.api.galley_diagnostic_recovery_terminal(handle as bigint);
  }

  diagnosticRecoveryResume(handle: Handle): number | null {
    return this.api.galley_diagnostic_recovery_resume(handle as bigint);
  }

  diagnosticRecoveryLhsVariable(handle: Handle): string | null {
    return this.api.galley_diagnostic_recovery_lhs_variable(handle as bigint);
  }

  diagnosticRecoveryProduction(handle: Handle): [string, number] | null {
    return this.api.galley_diagnostic_recovery_production(handle as bigint);
  }

  diagnosticRecoveryOccurrence(handle: Handle): [string, number, number, string] | null {
    return this.api.galley_diagnostic_recovery_occurrence(handle as bigint);
  }

  recordedDiagnosticCount(handle: Handle): number {
    return toNumber(this.api.galley_recorded_diagnostic_count(handle as bigint));
  }

  recordedDiagnosticKind(handle: Handle, diagIndex: number): number {
    return toNumber(this.api.galley_recorded_diagnostic_kind(handle as bigint, BigInt(diagIndex)));
  }

  recordedDiagnosticPosition(handle: Handle, diagIndex: number): [number, number] | null {
    return this.api.galley_recorded_diagnostic_position(handle as bigint, BigInt(diagIndex));
  }

  recordedUnexpectedToken(handle: Handle, diagIndex: number): Uint8Array | null {
    return this.api.galley_recorded_unexpected_token(handle as bigint, BigInt(diagIndex));
  }

  recordedDiagnosticMessage(handle: Handle, diagIndex: number): string | null {
    return this.api.galley_recorded_diagnostic_message(handle as bigint, BigInt(diagIndex));
  }

  recordedIndentation(handle: Handle, diagIndex: number): [number, number] | null {
    return this.api.galley_recorded_indentation(handle as bigint, BigInt(diagIndex));
  }

  recordedSemantic(handle: Handle, diagIndex: number): [string, string] | null {
    return this.api.galley_recorded_semantic(handle as bigint, BigInt(diagIndex));
  }

  recordedExpectedCount(handle: Handle, diagIndex: number): number {
    return toNumber(this.api.galley_recorded_expected_count(handle as bigint, BigInt(diagIndex)));
  }

  recordedExpectedToken(handle: Handle, diagIndex: number, tokenIndex: number): Uint8Array | null {
    return this.api.galley_recorded_expected_token(
      handle as bigint, BigInt(diagIndex), BigInt(tokenIndex),
    );
  }

  recordedContextCount(handle: Handle, diagIndex: number): number {
    return toNumber(this.api.galley_recorded_context_count(handle as bigint, BigInt(diagIndex)));
  }

  recordedContextName(handle: Handle, diagIndex: number, contextIndex: number): Uint8Array | null {
    return this.api.galley_recorded_context_name(
      handle as bigint, BigInt(diagIndex), BigInt(contextIndex),
    );
  }

  recordedRecoveryKind(handle: Handle, diagIndex: number): number {
    return toNumber(this.api.galley_recorded_diagnostic_recovery_kind(handle as bigint, BigInt(diagIndex)));
  }

  recordedRecoveryTerminal(handle: Handle, diagIndex: number): Uint8Array | null {
    return this.api.galley_recorded_recovery_terminal(handle as bigint, BigInt(diagIndex));
  }

  recordedRecoveryResume(handle: Handle, diagIndex: number): number | null {
    return this.api.galley_recorded_recovery_resume(handle as bigint, BigInt(diagIndex));
  }

  recordedRecoveryLhsVariable(handle: Handle, diagIndex: number): string | null {
    return this.api.galley_recorded_recovery_lhs_variable(handle as bigint, BigInt(diagIndex));
  }

  recordedRecoveryProduction(handle: Handle, diagIndex: number): [string, number] | null {
    return this.api.galley_recorded_recovery_production(handle as bigint, BigInt(diagIndex));
  }

  recordedRecoveryOccurrence(
    handle: Handle,
    diagIndex: number,
  ): [string, number, number, string] | null {
    return this.api.galley_recorded_recovery_occurrence(handle as bigint, BigInt(diagIndex));
  }

  // -- tree editing ----------------------------------------------------------

  treeAppendChildren(handle: Handle, parent: bigint, first: bigint): number {
    return toNumber(this.api.galley_tree_append_children(handle as bigint, parent, first));
  }

  treeInsertBefore(handle: Handle, target: bigint, first: bigint): number {
    return toNumber(this.api.galley_tree_insert_before(handle as bigint, target, first));
  }

  treeInsertAfter(handle: Handle, target: bigint, first: bigint): number {
    return toNumber(this.api.galley_tree_insert_after(handle as bigint, target, first));
  }

  treeRemoveSiblings(handle: Handle, node: bigint, count: number): { status: number; head: bigint } {
    const [status, head] = this.api.galley_tree_remove_siblings(handle as bigint, node, BigInt(count));
    return { status: toNumber(status), head };
  }

  treeRemoveSelf(handle: Handle, node: bigint): { status: number; head: bigint } {
    const [status, head] = this.api.galley_tree_remove_self(handle as bigint, node);
    return { status: toNumber(status), head };
  }

  treePromoteChildrenOverWrapper(handle: Handle, wrapper: bigint): { status: number; head: bigint } {
    const [status, head] = this.api.galley_tree_promote_children_over_wrapper(handle as bigint, wrapper);
    return { status: toNumber(status), head };
  }

  treeCleanChildren(handle: Handle, node: bigint): { status: number; head: bigint } {
    const [status, head] = this.api.galley_tree_clean_children(handle as bigint, node);
    return { status: toNumber(status), head };
  }

  treeUnlinkWrapper(handle: Handle, wrapper: bigint): number {
    return toNumber(this.api.galley_tree_unlink_wrapper(handle as bigint, wrapper));
  }

  treeInsertChildrenAt(handle: Handle, parent: bigint, index: number, first: bigint): number {
    return toNumber(
      this.api.galley_tree_insert_children_at(handle as bigint, parent, BigInt(index), first),
    );
  }

  treeRemoveChildrenAt(
    handle: Handle,
    parent: bigint,
    index: number,
    count: number,
  ): { status: number; head: bigint } {
    const [status, head] = this.api.galley_tree_remove_children_at(
      handle as bigint, parent, BigInt(index), BigInt(count),
    );
    return { status: toNumber(status), head };
  }

  // -- procedure hooks ----------------------------------------------------------

  procCurrentNode(args: Handle): bigint {
    return this.api.galley_procedure_current_node(args as bigint);
  }

  procSetCurrentNode(args: Handle, node: bigint): void {
    this.api.galley_procedure_set_current_node(args as bigint, node);
  }

  procDropSelf(args: Handle): number {
    return toNumber(this.api.galley_procedure_drop_self(args as bigint));
  }

  procDropChildren(args: Handle): number {
    return toNumber(this.api.galley_procedure_drop_children(args as bigint));
  }

  procDropIfEmpty(args: Handle): number {
    return toNumber(this.api.galley_procedure_drop_if_empty(args as bigint));
  }

  procReplaceWithChildren(args: Handle): number {
    return toNumber(this.api.galley_procedure_replace_with_children(args as bigint));
  }

  procContextLine(args: Handle): number {
    return this.api.galley_procedure_context_line(args as bigint);
  }

  procContextColumn(args: Handle): number {
    return this.api.galley_procedure_context_column(args as bigint);
  }

  procReportSemanticError(args: Handle, message: Uint8Array): number {
    return toNumber(
      this.api.galley_procedure_report_semantic_error(args as bigint, bytesToString(message)),
    );
  }

  syncProcedures(names: string[]): void {
    if (this.api.galley_js_procedure_clear === null || this.api.galley_js_procedure_enable === null)
      return;
    this.api.galley_js_procedure_clear();
    for (const name of names) {
      this.api.galley_js_procedure_enable(name);
    }
    // Warm the ID table outside any parse so the hot path never queries.
    this.procedureNames();
  }

  #procedureNameTable: string[] | null = null;

  procedureNames(): string[] {
    if (this.#procedureNameTable !== null) return this.#procedureNameTable;
    const table: string[] = [];
    const count = this.api.galley_js_procedure_count;
    const procedureName = this.api.galley_js_procedure_name;
    if (count !== null && procedureName !== null) {
      const total = count();
      for (let i = 0; i < total; i++) {
        const name = procedureName(i);
        if (name === null) break;
        table.push(name);
      }
    }
    this.#procedureNameTable = table;
    return table;
  }
}

const portCache = new Map<string, NodePort>();

/** Port for the library at `explicitPath` (or default discovery), cached per path. */
export function getNodePort(explicitPath?: string): NodePort {
  const ffi = loadLibrary(explicitPath);
  const cachedPort = portCache.get(ffi.libPath);
  if (cachedPort) return cachedPort;
  const port = new NodePort(ffi);
  portCache.set(ffi.libPath, port);
  return port;
}
