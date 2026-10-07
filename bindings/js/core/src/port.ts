/**
 * Neutral FFI port: the single seam between the runtime-neutral core
 * (`session.ts`, `node.ts`, `procedures.ts`) and each runtime adapter
 * (Node/addon, Bun/`bun:ffi`, Deno/`Deno.dlopen`).
 *
 * The port mirrors `bindings/c/galley.h`, but with structured returns
 * instead of C out-parameters: adapters own all memory copying (bytes are
 * already-copied `Uint8Array`s here, valid after the next parse) and all
 * integer normalization (addresses are `bigint`, counts and statuses are
 * `number`). Opaque native pointers (sessions, hook doors)
 * cross the seam as `Handle` and are never inspected by the core; the walk
 * cursor crosses as a 40-byte `ArrayBuffer`, copied in and out per step
 * because a wasm guest may grow its memory during the call.
 */

export type Handle = unknown;

/**
 * The ticket the core issues for one hook call. It is all a binding knows of
 * a hook: every `galley_procedure_*` call takes the session and the ticket,
 * and the core refuses the ticket of a hook that has returned
 * (`galley_error_stale_hook`), so a binding keeps no expiry state of its own.
 * Tickets are 64-bit and never reused.
 */
export type HookTicket = bigint;

/**
 * The platform's native byte order, detected once. The walk cursor is a
 * struct the native side reads and writes in place, so hosts that pass
 * bytes straight through must view it in native order; wasm guests are
 * always little-endian regardless of the host. A typed array stores in
 * native order (a DataView would only re-interpret in the order it is
 * told), so the first byte of a written 1 is the platform's low byte.
 */
const endianProbe = new Uint16Array(1);
endianProbe[0] = 1;
export const NATIVE_LITTLE_ENDIAN = new Uint8Array(endianProbe.buffer)[0] === 1;

/** `GalleyCOptions` fields as plain data; null selects library defaults. */
export interface SessionCOptions {
  maxErrors: number;
  recoveryWindow: number;
  stackOverflowRecovery: number;
  syntaxErrorStackDepth: number;
  verbosity: number;
  astPreallocationRatio: number;
  astPreallocationCap: bigint;
}

/**
 * Flat bulk read of the published parse, one slot per node
 * address. `parent` holds `INVALID_NODE` for the root, `firstChild`/`next`
 * hold `INVALID_NODE` where the link does not exist, `variable` holds the
 * core's `NO_VARIABLE` for nodes without a variable (the session's public
 * snapshot spells it -1), `spanStart`/`spanLen` are byte
 * offsets into the parsed input, and `isSemanticError` / `isRecovered` hold
 * 1 where the node carries a semantic error / is a node syntax-error
 * recovery kept in place of damaged input, 0 elsewhere — a walk step's flags
 * as raw columns. Parent, firstChild, and next alone
 * describe the whole tree with no further calls.
 *
 * The port returns the columns alone; the session's public
 * `TreeSnapshot` extends this with `node(address)`, the sanctioned
 * conversion back to a node of the parse these columns describe.
 */
export interface SnapshotColumns {
  count: number;
  parent: BigUint64Array;
  firstChild: BigUint64Array;
  next: BigUint64Array;
  childCount: Uint32Array;
  variable: BigInt64Array;
  spanStart: BigUint64Array;
  spanLen: BigUint64Array;
  isSemanticError: Int32Array;
  isRecovered: Int32Array;
}

/**
 * The one callback an adapter forwards every hook of its library to:
 * the handle the session registered, the hook's index, and the ticket of
 * this hook call.
 */
export type DispatchHandler = (hookHandle: number, hookIndex: number, hook: HookTicket) => void;

/**
 * One door's node and tree calls: the `galley_node_*` / `galley_tree_*` /
 * `galley_walk_next` family over a session handle, or its `galley_hook_*`
 * twin over a parse's hook door. The two families take the same arguments
 * after the handle and answer the same way, so the core holds one
 * implementation per capability and an adapter instantiates each twice, once
 * per prefix; the door is the handle plus which family to call.
 *
 * Every call takes the generation of the tree it addresses, which the core
 * compares against the door's tree. A value below zero is the core's
 * refusal (stale tree, session in use, invalid node, null argument), never
 * an answer: addresses are unsigned and counts are non-negative, so nothing
 * a caller could mistake for a result is negative.
 */
export interface NodeFamily {
  /** Direct child count. */
  childCount(handle: Handle, generation: number, node: bigint): number;
  /**
   * One link: the address (`INVALID_NODE` when the link does not exist) as a
   * BigInt, or the core's refusal as a negative Number.
   */
  firstChild(handle: Handle, generation: number, node: bigint): bigint | number;
  lastChild(handle: Handle, generation: number, node: bigint): bigint | number;
  nextSibling(handle: Handle, generation: number, node: bigint): bigint | number;
  priorSibling(handle: Handle, generation: number, node: bigint): bigint | number;
  parent(handle: Handle, generation: number, node: bigint): bigint | number;
  nodeSymbolName(handle: Handle, generation: number, node: bigint): Uint8Array | number;
  nodeText(handle: Handle, generation: number, node: bigint): Uint8Array | number;
  nodeSpan(handle: Handle, generation: number, node: bigint): [bigint, bigint] | number;
  nodeLineColumn(handle: Handle, generation: number, node: bigint): [number, number] | number;
  /**
   * Raw variable index, `null` when the node has no variable (the core's
   * `GALLEY_NO_VARIABLE`); a negative value is the core's refusal.
   */
  nodeVariableIndex(handle: Handle, generation: number, node: bigint): number | null;
  /**
   * One step of a walk over the host-owned 40-byte cursor, which carries
   * its own generation: 1 yields a node, 0 ends the walk (and keeps ending
   * it while its tree is live), negative is a failure (stale tree, session
   * in use, malformed cursor bytes).
   */
  walkNext(handle: Handle, cursor: ArrayBuffer): number;
  // Tree edits. A call with a second node passes each node's own generation;
  // the core refuses a pair from two parses, so nothing here compares them.
  treeAppendChildren(
    handle: Handle,
    generation: number,
    parent: bigint,
    firstGeneration: number,
    first: bigint,
  ): number;
  treeInsertBefore(
    handle: Handle,
    generation: number,
    target: bigint,
    firstGeneration: number,
    first: bigint,
  ): number;
  treeInsertAfter(
    handle: Handle,
    generation: number,
    target: bigint,
    firstGeneration: number,
    first: bigint,
  ): number;
  treeRemoveSiblings(
    handle: Handle,
    generation: number,
    node: bigint,
    count: number,
  ): { status: number; head: bigint };
  treeRemoveSelf(handle: Handle, generation: number, node: bigint): { status: number; head: bigint };
  treeCleanChildren(handle: Handle, generation: number, node: bigint): { status: number; head: bigint };
  treeInsertChildrenAt(
    handle: Handle,
    generation: number,
    parent: bigint,
    index: number,
    firstGeneration: number,
    first: bigint,
  ): number;
  treeRemoveChildrenAt(
    handle: Handle,
    generation: number,
    parent: bigint,
    index: number,
    count: number,
  ): { status: number; head: bigint };
}

export interface FfiPort {
  /** The session door's node and tree calls; the handle is a session. */
  readonly session: NodeFamily;
  /** The hook door's twins; the handle is the parse's door (`procDoor`). */
  readonly hook: NodeFamily;

  // -- parser metadata (mirror galley.h; sessions expose these per artifact) --
  version(): string;
  parserType(): number;
  errorRecoveryMode(): number;
  hasAst(): boolean;
  hasProcedures(): boolean;
  allowsNoAstTreeProcedures(): boolean;
  sourceRetentionEnabled(): boolean;
  hasPositionTracking(): boolean;
  hasInputStreaming(): boolean;
  usesVerbatim(): boolean;
  stackOverflowRecoveryAvailable(): boolean;
  symbolCount(): number;
  variableCount(): number;
  statusString(status: number): string | null;

  // -- sessions ---------------------------------------------------------
  /** Null handle on initialization failure (most commonly allocation failure). */
  createSession(options: SessionCOptions | null): Handle;
  destroySession(handle: Handle): void;
  /** Negative status on failure. */
  setMessageOverride(handle: Handle, name: Uint8Array, message: Uint8Array): number;

  // -- parsing ----------------------------------------------------------
  /** Bytes parsed, or a negative status code. */
  parse(handle: Handle, data: Uint8Array): number;
  /** Bytes parsed, or a negative status code. */
  parseFile(handle: Handle, path: string): number;
  /**
   * End position of the published parse, or the core's negative status when
   * it refuses (nothing published, a parse in flight).
   */
  lastPosition(handle: Handle): [number, number] | number;
  /**
   * Retained input of the published parse: the buffer snapshot spans index,
   * or the core's negative status when it refuses (nothing published, a
   * parse in flight).
   */
  lastInput(handle: Handle): Uint8Array | number;

  // -- arena and navigation ----------------------------------------------
  //
  // Node and tree calls live on `session` and `hook` (see NodeFamily); what
  // stays here names no node, or reads the published tree as a whole.
  /** Node count of the tree `generation` names. */
  nodeCount(handle: Handle, generation: number): number;
  /** Negative status on failure (e.g. capacity exceeded). */
  reserveNodes(handle: Handle, capacity: bigint): number;
  /** Node storage capacity, or a negative status (a parse is in flight). */
  nodeCapacity(handle: Handle): number;
  /**
   * The published tree's root and the generation every one of its nodes
   * carries, written in one crossing: the only source of that generation and
   * the one "is there a tree here" probe. `INVALID_NODE` and 0n mean nothing
   * is published; a negative status is a refusal (session in use).
   */
  rootNode(handle: Handle): { status: number; root: bigint; generation: number };
  /** Flat bulk read of the published tree (see `SnapshotColumns`). */
  treeSnapshot(handle: Handle, generation: number): SnapshotColumns | number;

  // -- walking ------------------------------------------------------------
  /**
   * The byte order native code reads and writes the walk cursor struct
   * in: the platform's order for FFI ports that hand bytes straight to
   * native code, little for a wasm guest.
   */
  readonly walkCursorLittleEndian: boolean;
  // -- symbol tables -------------------------------------------------------
  symbolNameAt(handle: Handle, index: number): Uint8Array | null;
  symbolIsTerminal(handle: Handle, index: number): boolean;
  variableNameAt(handle: Handle, index: number): Uint8Array | null;

  // -- diagnostics ---------------------------------------------------------
  hasDiagnostic(handle: Handle): boolean;
  diagnosticKind(handle: Handle): number;
  diagnosticMessage(handle: Handle): string | null;
  diagnosticMessageAnsi(handle: Handle): string | null;
  diagnosticPosition(handle: Handle): [number, number] | null;
  diagnosticUnexpectedToken(handle: Handle): Uint8Array | null;
  diagnosticExpectedCount(handle: Handle): number;
  diagnosticExpectedAt(handle: Handle, index: number): Uint8Array | null;
  diagnosticContextCount(handle: Handle): number;
  diagnosticContextAt(handle: Handle, index: number): Uint8Array | null;
  syntaxErrorCount(handle: Handle): number;
  semanticErrorCount(handle: Handle): number;
  /** (variable, message); null when there is no semantic diagnostic. */
  diagnosticSemantic(handle: Handle): [string, string] | null;
  /** (spaces, width); null when not an indentation diagnostic. */
  diagnosticIndentation(handle: Handle): [number, number] | null;

  // -- recovery, current diagnostic ------------------------------------------
  diagnosticRecoveryKind(handle: Handle): number;
  diagnosticRecoveryTerminal(handle: Handle): Uint8Array | null;
  diagnosticRecoveryResume(handle: Handle): number | null;
  diagnosticRecoveryLhsVariable(handle: Handle): string | null;
  diagnosticRecoveryProduction(handle: Handle): [string, number] | null;
  diagnosticRecoveryOccurrence(handle: Handle): [string, number, number, string] | null;

  // -- recovery, recorded diagnostics ------------------------------------------
  recordedDiagnosticCount(handle: Handle): number;
  recordedDiagnosticKind(handle: Handle, diagIndex: number): number;
  recordedDiagnosticPosition(handle: Handle, diagIndex: number): [number, number] | null;
  recordedUnexpectedToken(handle: Handle, diagIndex: number): Uint8Array | null;
  recordedDiagnosticMessage(handle: Handle, diagIndex: number): string | null;
  recordedIndentation(handle: Handle, diagIndex: number): [number, number] | null;
  recordedSemantic(handle: Handle, diagIndex: number): [string, string] | null;
  recordedExpectedCount(handle: Handle, diagIndex: number): number;
  recordedExpectedToken(handle: Handle, diagIndex: number, tokenIndex: number): Uint8Array | null;
  recordedContextCount(handle: Handle, diagIndex: number): number;
  recordedContextName(handle: Handle, diagIndex: number, contextIndex: number): Uint8Array | null;
  recordedRecoveryKind(handle: Handle, diagIndex: number): number;
  recordedRecoveryTerminal(handle: Handle, diagIndex: number): Uint8Array | null;
  recordedRecoveryResume(handle: Handle, diagIndex: number): number | null;
  recordedRecoveryLhsVariable(handle: Handle, diagIndex: number): string | null;
  recordedRecoveryProduction(handle: Handle, diagIndex: number): [string, number] | null;
  recordedRecoveryOccurrence(
    handle: Handle,
    diagIndex: number,
  ): [string, number, number, string] | null;

  // -- procedure hooks (per-hook state) ------------------------------------------
  // A hook is named by its session and ticket. Every call below answers with
  // its value (>= 0) or a negative status; a ticket whose hook has returned is
  // `galley_error_stale_hook`.
  /**
   * The parse's door: the same handle for every hook of one parse, valid
   * until that parse ends. The `hook` family crosses through it.
   */
  procDoor(session: Handle, hook: HookTicket): { status: number; door: Handle };
  /** The hook's current node (`INVALID_NODE` when none), or the refusal as a negative Number. */
  procCurrentNode(session: Handle, hook: HookTicket): bigint | number;
  /**
   * Sets the hook's current node to a node of the parse that owns the hook
   * (`INVALID_NODE` clears it, no generation check). A negative status is the
   * core's refusal: stale tree, invalid node, stale hook, null argument.
   */
  procSetCurrentNode(session: Handle, hook: HookTicket, generation: number, node: bigint): number;
  procDropSelf(session: Handle, hook: HookTicket): number;
  procDropChildren(session: Handle, hook: HookTicket): number;
  procDropIfEmpty(session: Handle, hook: HookTicket): number;
  procReplaceWithChildren(session: Handle, hook: HookTicket): number;
  procContextLine(session: Handle, hook: HookTicket): number;
  procContextColumn(session: Handle, hook: HookTicket): number;
  /** Running semantic-error total, or a negative status code. */
  procReportSemanticError(session: Handle, hook: HookTicket, message: Uint8Array): number;

  /**
   * The core's parse generation of the parse that owns `door`: constant
   * for the whole parse, so the core reads it once per hook dispatch. A
   * negative value is the core's refusal (a null door), never a generation.
   */
  hookGeneration(door: Handle): number;
  /**
   * Hook names in hook-index order, from the library's own list; empty
   * for a library that forwards no hooks to a host. Queried once and
   * cached by the adapter.
   */
  hookNames(): string[];
  /**
   * Replaces `session`'s native hook state in one step: `enabled` holds
   * one flag per hook index (`hookNames().length` in all). Every enabled
   * hook then reaches `hookDispatch` with `hookHandle`. Returns the native
   * status: negative when refused, `-13` while a parse is in flight.
   */
  setSessionHooks(session: Handle, hookHandle: number, enabled: Uint8Array): number;
  /**
   * The callback the adapter's native trampoline forwards each hook to,
   * or null. The core installs it once per port, routing by handle to
   * the session that owns the hook. Anchored on the port — not on module
   * state — so dispatch survives duplicated module installs (bundler
   * copies, transforming loaders): both sides of the native boundary
   * already share the port object.
   */
  hookDispatch: DispatchHandler | null;
}
