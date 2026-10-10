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
  NodeFamily,
  HookTicket,
  DispatchHandler,
  SessionCOptions,
  SnapshotColumns,
} from "@sanbus/galley-core";
import { GalleyError, MissingArtifactError, NATIVE_LITTLE_ENDIAN, Status } from "@sanbus/galley-core";
import {
  resolveArtifact,
  resolveArtifactFile,
  artifactFileName,
  canonicalResolvePath,
} from "@sanbus/galley-core/internal";
import { installDispatch } from "./dispatch.ts";
const require = createRequire(import.meta.url);

/**
 * The node, tree and walk calls both doors expose, keyed by the C name after
 * `galley_`. The addon registers each twice: `galley_<name>` over a session
 * handle and `galley_hook_<name>` over a parse's door, with identical
 * signatures. A refusal arrives as a negative Number, never as a value.
 */
interface AddonDoorCalls {
  node_child_count(handle: bigint, generation: number, node: bigint): number;
  node_first_child(handle: bigint, generation: number, node: bigint): bigint | number;
  node_last_child(handle: bigint, generation: number, node: bigint): bigint | number;
  node_next_sibling(handle: bigint, generation: number, node: bigint): bigint | number;
  node_prior_sibling(handle: bigint, generation: number, node: bigint): bigint | number;
  node_parent(handle: bigint, generation: number, node: bigint): bigint | number;
  node_symbol_name(handle: bigint, generation: number, node: bigint): Buffer | number;
  node_text(handle: bigint, generation: number, node: bigint): Buffer | number;
  node_span(handle: bigint, generation: number, node: bigint): [bigint, bigint] | number;
  node_line_column(handle: bigint, generation: number, node: bigint): [number, number] | number;
  /** The raw variable index, null for a node without one, or a negative status. */
  node_variable_index(handle: bigint, generation: number, node: bigint): number | null;
  walk_next(handle: bigint, cursor: ArrayBuffer): bigint;
  tree_append_children(handle: bigint, generation: number, parent: bigint, firstGeneration: number, first: bigint): number;
  tree_insert_before(handle: bigint, generation: number, target: bigint, firstGeneration: number, first: bigint): number;
  tree_insert_after(handle: bigint, generation: number, target: bigint, firstGeneration: number, first: bigint): number;
  tree_remove_siblings(handle: bigint, generation: number, node: bigint, count: bigint): [number, bigint];
  tree_remove_self(handle: bigint, generation: number, node: bigint): [number, bigint];
  tree_clean_children(handle: bigint, generation: number, node: bigint): [number, bigint];
  tree_insert_children_at(
    handle: bigint,
    generation: number,
    parent: bigint,
    index: bigint,
    firstGeneration: number,
    first: bigint,
  ): number;
  tree_remove_children_at(
    handle: bigint,
    generation: number,
    parent: bigint,
    index: bigint,
    count: bigint,
  ): [number, bigint];
}

/** `AddonDoorCalls` under one door's C names: `galley_<name>` or `galley_hook_<name>`. */
type AddonDoorNames<Door extends "" | "hook_"> = {
  [Name in keyof AddonDoorCalls as `galley_${Door}${Name & string}`]: AddonDoorCalls[Name];
};

/**
 * One bound parser library: every `galley_*` function as a direct call
 * returning NAPI-natural values (bigint for 64-bit, number for 32-bit and
 * below, Buffer for byte pairs, string for text, tuples for scalar outs).
 * Optional JS-shim entries are null on libraries that predate them.
 */
export interface AddonApi extends AddonDoorNames<""> , AddonDoorNames<"hook_"> {
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
  galley_session_destroy(session: bigint): bigint;
  galley_session_set_message_override(
    session: bigint,
    name: string,
    message: string,
  ): bigint;

  // parse
  galley_parse(session: bigint, data: Uint8Array, len: number): bigint;
  galley_parse_file(session: bigint, filePath: string): bigint;
  // A negative Number is the core's refusal; empty input is a buffer-less null.
  galley_last_input(session: bigint): Uint8Array | number | null;
  galley_last_position(session: bigint): [number, number] | number | null;

  // node / tree
  //
  // Every session-door call takes the generation of the tree it addresses,
  // which the core compares against the published one, a plain Number. The
  // addon answers a refusal as a negative Number: a status, never INVALID_NODE.
  // Counts and statuses are Numbers; addresses stay BigInt.
  galley_node_count(session: bigint, generation: number): number;
  galley_reserve_nodes(session: bigint, capacity: bigint): bigint;
  galley_node_capacity(session: bigint): number;
  galley_root_node(session: bigint): { status: number; root: bigint; generation: number };
  galley_tree_snapshot(
    session: bigint,
    generation: number,
    outParent: BigUint64Array,
    outFirstChild: BigUint64Array,
    outNext: BigUint64Array,
    outChildCount: Uint32Array,
    outVariable: BigInt64Array,
    outSpanStart: BigUint64Array,
    outSpanLen: BigUint64Array,
    outIsSemanticError: Int32Array,
    outIsRecovered: Int32Array,
    capacity: bigint,
  ): number;

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

  // host hooks: the addon's one callback per library, and the per-session
  // hook state (see galley_session_set_hooks in galley.h)
  install_dispatch(callback: (hookHandle: number, hookIndex: number, hook: bigint) => number): void;
  galley_hooks_count(): number;
  galley_hooks_name(index: number): string | null;
  galley_session_set_hooks(session: bigint, hookHandle: number, enabled: Uint8Array): bigint;

  // procedure-hook state; node reads use the galley_hook_* twins below
  /** The hook's current node, or the core's refusal as a negative Number. */
  galley_procedure_current_node(session: bigint, hook: bigint): bigint | number;
  /** [status, door]: the parse's hook door as a handle, 0n when refused. */
  galley_procedure_door(session: bigint, hook: bigint): [number, bigint];
  galley_procedure_set_current_node(session: bigint, hook: bigint, generation: number, node: bigint): number;
  galley_procedure_drop_self(session: bigint, hook: bigint): number;
  galley_procedure_drop_children(session: bigint, hook: bigint): number;
  galley_procedure_drop_if_empty(session: bigint, hook: bigint): number;
  galley_procedure_context_line(session: bigint, hook: bigint): number;
  galley_procedure_context_column(session: bigint, hook: bigint): number;
  galley_procedure_report_semantic_error(session: bigint, hook: bigint, message: string): number;
  galley_hook_generation(door: bigint): [number, number];
  /** [status, generation] of the published tree (0 when none or stale). */
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

// Cached libraries, one per resolved artifact path.
const libraries = new Map<string, GalleyFFI>();

// --- library discovery -------------------------------------------------
// One place, named up front: the language directory must hold the
// adapter's standard-named files (the parser library plus the NAPI
// addon beside it). Anything else is a loud error, never a search.

const BUILD_HINT =
  `Build it first: npx galley-js-node <language-dir>\n` +
  `That leaves ${libFileName()} and ${addonFileName()} in the directory.`;

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

export function findLibrary(languagePath: string): string {
  return resolveArtifact(languagePath, libFileName(), path.join, {
    resolvePath: (candidate) => canonicalResolvePath(candidate, path.resolve, fs.realpathSync),
    existsSync: exists,
    buildHint: BUILD_HINT,
  });
}

/** Explicit-file twin of {@link findLibrary}: names the parser library itself. */
export function findLibraryFile(filePath: string): string {
  return resolveArtifactFile(filePath, {
    resolvePath: (candidate) => canonicalResolvePath(candidate, path.resolve, fs.realpathSync),
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

export function loadLibrary(languagePath: string): GalleyFFI {
  return loadLibraryFile(findLibrary(languagePath));
}

/** Loads the NAPI addon against an explicit parser library file. */
export function loadLibraryFromFile(filePath: string): GalleyFFI {
  return loadLibraryFile(findLibraryFile(filePath));
}

function loadLibraryFile(libPath: string): GalleyFFI {
  const cached = libraries.get(libPath);
  if (cached) return cached;

  const addonPath = findAddon(libPath);
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const addon = require(addonPath) as { load(path: string): AddonApi };
  const api = addon.load(libPath);

  const ffi: GalleyFFI = { libPath, api };
  libraries.set(libPath, ffi);
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
 * One door's node and tree calls, bound once from the addon's twin
 * registrations: `galley_<name>` for the session door, `galley_hook_<name>`
 * for the hook door. Each capability is declared here a single time and
 * instantiated for both prefixes. The addon answers a refusal as a negative
 * Number, which the core's door turns into the host's failure.
 */
function addonFamily(api: AddonApi, door: "" | "hook_"): NodeFamily {
  const calls = api as unknown as Record<string, unknown>;
  const bound = <Name extends keyof AddonDoorCalls>(name: Name): AddonDoorCalls[Name] =>
    calls[`galley_${door}${name}`] as AddonDoorCalls[Name];
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
    childCount: (handle, generation, node) => childCount(handle as bigint, generation, node),
    firstChild: (handle, generation, node) => firstChild(handle as bigint, generation, node),
    lastChild: (handle, generation, node) => lastChild(handle as bigint, generation, node),
    nextSibling: (handle, generation, node) => nextSibling(handle as bigint, generation, node),
    priorSibling: (handle, generation, node) => priorSibling(handle as bigint, generation, node),
    parent: (handle, generation, node) => parent(handle as bigint, generation, node),
    nodeSymbolName: (handle, generation, node) => symbolName(handle as bigint, generation, node),
    nodeText: (handle, generation, node) => text(handle as bigint, generation, node),
    nodeSpan: (handle, generation, node) => span(handle as bigint, generation, node),
    nodeLineColumn: (handle, generation, node) => lineColumn(handle as bigint, generation, node),
    nodeVariableIndex: (handle, generation, node) => variableIndex(handle as bigint, generation, node),
    walkNext: (handle, cursor) => toNumber(walkNext(handle as bigint, cursor)),
    treeAppendChildren: (handle, generation, parentNode, firstGeneration, first) =>
      appendChildren(handle as bigint, generation, parentNode, firstGeneration, first),
    treeInsertBefore: (handle, generation, target, firstGeneration, first) =>
      insertBefore(handle as bigint, generation, target, firstGeneration, first),
    treeInsertAfter: (handle, generation, target, firstGeneration, first) =>
      insertAfter(handle as bigint, generation, target, firstGeneration, first),
    treeRemoveSiblings: (handle, generation, node, count) => {
      const [status, head] = removeSiblings(handle as bigint, generation, node, BigInt(count));
      return { status, head };
    },
    treeRemoveSelf: (handle, generation, node) => {
      const [status, head] = removeSelf(handle as bigint, generation, node);
      return { status, head };
    },
    treeCleanChildren: (handle, generation, node) => {
      const [status, head] = cleanChildren(handle as bigint, generation, node);
      return { status, head };
    },
    treeInsertChildrenAt: (handle, generation, parentNode, index, firstGeneration, first) =>
      insertChildrenAt(handle as bigint, generation, parentNode, BigInt(index), firstGeneration, first),
    treeRemoveChildrenAt: (handle, generation, parentNode, index, count) => {
      const [status, head] = removeChildrenAt(
        handle as bigint, generation, parentNode, BigInt(index), BigInt(count),
      );
      return { status, head };
    },
  };
}


/**
 * Node's {@link FfiPort}: normalizes the addon's direct returns into the
 * structured values the core expects. Byte pairs arrive as owned Buffers;
 * the core only sees owned bytes.
 */
export class NodePort implements FfiPort {
  readonly ffi: GalleyFFI;
  readonly libraryPath: string;
  readonly session: NodeFamily;
  readonly hook: NodeFamily;
  hookDispatch: DispatchHandler | null = null;

  constructor(ffi: GalleyFFI) {
    this.ffi = ffi;
    this.libraryPath = ffi.libPath;
    this.session = addonFamily(ffi.api, "");
    this.hook = addonFamily(ffi.api, "hook_");
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

  destroySession(handle: Handle): number {
    return toNumber(this.api.galley_session_destroy(handle as bigint));
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

  lastPosition(handle: Handle): [number, number] | number {
    return this.api.galley_last_position(handle as bigint) ?? [0, 0];
  }

  lastInput(handle: Handle): Uint8Array | number {
    return this.api.galley_last_input(handle as bigint) ?? new Uint8Array(0);
  }

  // -- arena and navigation ----------------------------------------------
  //
  // These crossings never throw: a refusal travels as a negative value, the
  // one place the core's own status arrives, and the core's Session turns it
  // into the host's failure. A generation the core no longer holds is
  // refused here, not by this binding.

  nodeCount(handle: Handle, generation: number): number {
    return this.api.galley_node_count(handle as bigint, generation);
  }

  reserveNodes(handle: Handle, capacity: bigint): number {
    return toNumber(this.api.galley_reserve_nodes(handle as bigint, capacity));
  }

  nodeCapacity(handle: Handle): number {
    return this.api.galley_node_capacity(handle as bigint);
  }

  rootNode(handle: Handle): { status: number; root: bigint; generation: number } {
    return this.api.galley_root_node(handle as bigint);
  }

  treeSnapshot(handle: Handle, generation: number): SnapshotColumns | number {
    // No await between sizing and filling, so the count cannot change.
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
      const total = this.api.galley_tree_snapshot(
        handle as bigint, generation, parent, firstChild, next, childCount,
        variable, spanStart, spanLen, isSemanticError, isRecovered, BigInt(count),
      );
      if (total < 0) return total;
      if (total === count) {
        return { count, parent, firstChild, next, childCount, variable, spanStart, spanLen, isSemanticError, isRecovered };
      }
    }
    throw new GalleyError("node count changed during galley_tree_snapshot", Status.ErrorInternal);
  }

  // -- walking ------------------------------------------------------------

  /** Native code reads and writes the cursor struct in the platform's order. */
  readonly walkCursorLittleEndian = NATIVE_LITTLE_ENDIAN;

  // -- node accessors -----------------------------------------------------

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

  // -- procedure hooks ----------------------------------------------------------

  procCurrentNode(session: Handle, hook: HookTicket): bigint | number {
    return this.api.galley_procedure_current_node(session as bigint, hook);
  }

  procDoor(session: Handle, hook: HookTicket): { status: number; door: Handle } {
    const [status, door] = this.api.galley_procedure_door(session as bigint, hook);
    return { status, door };
  }

  procSetCurrentNode(session: Handle, hook: HookTicket, generation: number, node: bigint): number {
    return this.api.galley_procedure_set_current_node(session as bigint, hook, generation, node);
  }

  procDropSelf(session: Handle, hook: HookTicket): number {
    return this.api.galley_procedure_drop_self(session as bigint, hook);
  }

  procDropChildren(session: Handle, hook: HookTicket): number {
    return this.api.galley_procedure_drop_children(session as bigint, hook);
  }

  procDropIfEmpty(session: Handle, hook: HookTicket): number {
    return this.api.galley_procedure_drop_if_empty(session as bigint, hook);
  }


  procContextLine(session: Handle, hook: HookTicket): number {
    return this.api.galley_procedure_context_line(session as bigint, hook);
  }

  procContextColumn(session: Handle, hook: HookTicket): number {
    return this.api.galley_procedure_context_column(session as bigint, hook);
  }

  procReportSemanticError(session: Handle, hook: HookTicket, message: Uint8Array): number {
    return this.api.galley_procedure_report_semantic_error(session as bigint, hook, bytesToString(message));
  }

  hookGeneration(door: Handle): number {
    const [status, generation] = this.api.galley_hook_generation(door as bigint);
    return status < 0 ? status : generation;
  }

  setSessionHooks(session: Handle, hookHandle: number, enabled: Uint8Array): number {
    return toNumber(this.api.galley_session_set_hooks(session as bigint, hookHandle, enabled));
  }

  #hookNameTable: string[] | null = null;

  hookNames(): string[] {
    if (this.#hookNameTable !== null) return this.#hookNameTable;
    const table: string[] = [];
    const total = this.api.galley_hooks_count();
    for (let index = 0; index < total; index++) {
      const name = this.api.galley_hooks_name(index);
      if (name === null) break;
      table.push(name);
    }
    this.#hookNameTable = table;
    return table;
  }
}

const portCache = new Map<string, NodePort>();

/** Port for the language directory's library, cached per resolved path. */
export function getNodePort(languagePath: string): NodePort {
  return portForLibrary(findLibrary(languagePath));
}

/** Port for an explicit parser library file, cached per resolved path. */
export function getNodePortFromFile(filePath: string): NodePort {
  return portForLibrary(findLibraryFile(filePath));
}

function portForLibrary(libPath: string): NodePort {
  const cachedPort = portCache.get(libPath);
  if (cachedPort) return cachedPort;
  const ffi = loadLibraryFile(libPath);
  const port = new NodePort(ffi);
  // Dispatch rides with the port, not the Session: every consumer of the
  // port (adapter or universal loader) gets working procedure hooks.
  installDispatch(port);
  portCache.set(libPath, port);
  return port;
}
