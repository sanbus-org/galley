/**
 * Neutral FFI port: the single seam between the runtime-neutral core
 * (`session.ts`, `node.ts`, `procedures.ts`) and each runtime adapter
 * (Node/addon, Bun/`bun:ffi`, Deno/`Deno.dlopen`).
 *
 * The port mirrors `bindings/c/galley.h`, but with structured returns
 * instead of C out-parameters: adapters own all memory copying (bytes are
 * already-copied `Uint8Array`s here, valid after the next parse) and all
 * integer normalization (addresses are `bigint`, counts and statuses are
 * `number`). Opaque native pointers (sessions, walkers, procedure args)
 * cross the seam as `Handle` and are never inspected by the core.
 */

export type Handle = unknown;

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

/** One pre-order walker step. */
export interface WalkedStep {
  node: bigint;
  depth: number;
  isSemanticError: boolean;
}

/**
 * Flat bulk read of the most recent successful parse, one slot per node
 * address. `parent` holds `INVALID_NODE` for the root, `firstChild`/`next`
 * hold `INVALID_NODE` where the link does not exist, `variable` holds -1
 * for nodes without a variable, `spanStart`/`spanLen` are byte
 * offsets into the parsed input, and `isSemanticError` holds 1 where the
 * node carries a semantic error, 0 elsewhere — `WalkedStep`'s flag as a
 * raw column. Parent, firstChild, and next alone
 * describe the whole tree with no further calls.
 */
export interface TreeSnapshot {
  count: number;
  parent: BigUint64Array;
  firstChild: BigUint64Array;
  next: BigUint64Array;
  childCount: Uint32Array;
  variable: BigInt64Array;
  spanStart: BigUint64Array;
  spanLen: BigUint64Array;
  isSemanticError: Int32Array;
}

/**
 * The one callback an adapter forwards every hook of its library to:
 * the handle the session registered, the hook's index, and its native
 * arguments (valid only until the callback returns).
 */
export type DispatchHandler = (hookHandle: number, hookIndex: number, args: Handle) => void;

export interface FfiPort {
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
  /** End position of the most recent successful parse; null on failure. */
  lastPosition(handle: Handle): [number, number] | null;
  /**
   * Retained input of the most recent successful parse: the buffer
   * snapshot spans index. Empty before the first parse; null only on
   * native failure.
   */
  lastInput(handle: Handle): Uint8Array | null;

  // -- arena and navigation ----------------------------------------------
  nodeCount(handle: Handle): number;
  /** Negative status on failure (e.g. capacity exceeded). */
  reserveNodes(handle: Handle, capacity: bigint): number;
  nodeCapacity(handle: Handle): number;
  rootNode(handle: Handle): bigint;
  nodeValid(handle: Handle, node: bigint): boolean;
  childCount(handle: Handle, node: bigint): number;
  firstChild(handle: Handle, node: bigint): bigint;
  lastChild(handle: Handle, node: bigint): bigint;
  nextSibling(handle: Handle, node: bigint): bigint;
  priorSibling(handle: Handle, node: bigint): bigint;
  parent(handle: Handle, node: bigint): bigint;
  /** Flat bulk read of the most recent successful parse (see `TreeSnapshot`). */
  treeSnapshot(handle: Handle): TreeSnapshot;

  // -- walker ------------------------------------------------------------
  /** Null without AST construction or on invalid arguments. */
  walkerCreate(handle: Handle, node: bigint, skipSemanticErrors: boolean): Handle | null;
  /** Null when the walk is done. */
  walkerNext(walker: Handle): WalkedStep | null;
  walkerSkipChildren(walker: Handle): void;
  walkerDestroy(walker: Handle): void;

  // -- node accessors (null on invalid node) ------------------------------
  nodeSymbolName(handle: Handle, node: bigint): Uint8Array | null;
  nodeText(handle: Handle, node: bigint): Uint8Array | null;
  nodeSpan(handle: Handle, node: bigint): [bigint, bigint] | null;
  nodeLineColumn(handle: Handle, node: bigint): [number, number] | null;
  /** Raw variable index; -1 when the node has no variable. */
  nodeVariableIndex(handle: Handle, node: bigint): number;
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

  // -- tree editing ----------------------------------------------------------
  treeAppendChildren(handle: Handle, parent: bigint, first: bigint): number;
  treeInsertBefore(handle: Handle, target: bigint, first: bigint): number;
  treeInsertAfter(handle: Handle, target: bigint, first: bigint): number;
  treeRemoveSiblings(handle: Handle, node: bigint, count: number): { status: number; head: bigint };
  treeRemoveSelf(handle: Handle, node: bigint): { status: number; head: bigint };
  treePromoteChildrenOverWrapper(handle: Handle, wrapper: bigint): { status: number; head: bigint };
  treeCleanChildren(handle: Handle, node: bigint): { status: number; head: bigint };
  treeUnlinkWrapper(handle: Handle, wrapper: bigint): number;
  treeInsertChildrenAt(handle: Handle, parent: bigint, index: number, first: bigint): number;
  treeRemoveChildrenAt(
    handle: Handle,
    parent: bigint,
    index: number,
    count: number,
  ): { status: number; head: bigint };

  // -- procedure hooks (per-hook state) ------------------------------------------
  // `args` is valid only while its hook runs.
  /**
   * The parse's door: the same handle for every hook of one parse, valid
   * until that parse ends. Hook-door accessors below cross through it.
   */
  procDoor(args: Handle): Handle;
  procCurrentNode(args: Handle): bigint;
  procSetCurrentNode(args: Handle, node: bigint): void;
  procDropSelf(args: Handle): number;
  procDropChildren(args: Handle): number;
  procDropIfEmpty(args: Handle): number;
  procReplaceWithChildren(args: Handle): number;
  procContextLine(args: Handle): number;
  procContextColumn(args: Handle): number;
  /** Running semantic-error total, or a negative status code. */
  procReportSemanticError(args: Handle, message: Uint8Array): number;

  // -- hook door: parse-time node/tree accessors over the live parse ------
  // Unshared by construction: the parse holds the session exclusively for
  // its whole run, so these cross with the parse's door, not a session.
  hookNodeChildCount(door: Handle, node: bigint): number;
  hookNodeFirstChild(door: Handle, node: bigint): bigint;
  hookNodeLastChild(door: Handle, node: bigint): bigint;
  hookNodeNextSibling(door: Handle, node: bigint): bigint;
  hookNodePriorSibling(door: Handle, node: bigint): bigint;
  hookNodeParent(door: Handle, node: bigint): bigint;
  hookNodeSymbolName(door: Handle, node: bigint): Uint8Array | null;
  hookNodeText(door: Handle, node: bigint): Uint8Array | null;
  hookNodeSpan(door: Handle, node: bigint): [bigint, bigint] | null;
  hookNodeLineColumn(door: Handle, node: bigint): [number, number] | null;
  hookTreeAppendChildren(door: Handle, parent: bigint, first: bigint): number;
  hookTreeCleanChildren(door: Handle, node: bigint): { status: number; head: bigint };
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
