/**
 * Neutral FFI port: the single seam between the runtime-neutral core
 * (`session.ts`, `node.ts`, `procedures.ts`) and each runtime adapter
 * (Node/koffi, Bun/`bun:ffi`, Deno/`Deno.dlopen`).
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

/** Native dispatch callback installed by the adapter; receives a decoded hook name. */
export type DispatchHandler = (name: string, args: Handle) => void;

export interface FfiPort {
  // -- module-level queries (mirror galley.h) --------------------------
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

  // -- procedure hooks (parse-time state) ---------------------------------------
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
}
