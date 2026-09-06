/**
 * Parsing session bound to this library's parser.
 * Mirrors Python/Rust/Go sessions over `bindings/c/galley.h`.
 *
 * Runtime-neutral: all native calls go through the injected {@link FfiPort}.
 * Each adapter (`bindings/js/node`, `../bun`, `../deno`) subclasses `Session`
 * to supply its port from `SessionOptions.libraryPath`.
 */

import { INVALID_NODE } from "./constants.js";
import type { Diagnostic } from "./diagnostic.js";
import { GalleyError } from "./errors.js";
import type { FfiPort, Handle, SessionCOptions } from "./port.js";
import { decodeUtf8, encodeUtf8 } from "./text.js";
import { Node } from "./node.js";
import { setParsingSession } from "./procedures.js";

export interface SessionOptions {
  maxErrors?: number; // default 10
  recoveryWindow?: number; // default 500
  stackOverflowRecovery?: boolean; // default false
  syntaxErrorStackDepth?: number; // default 0
  verbosity?: number; // default 0
  astPreallocationRatio?: number; // default -1.0 (selects library default)
  astPreallocationCap?: number | bigint; // default 0
  messageOverrides?: Record<string, string>; // name -> message
  libraryPath?: string; // override shared-library location (consumed by the adapter)
}

function defaultOptions(): Required<Omit<SessionOptions, "messageOverrides" | "libraryPath">> & {
  messageOverrides: Record<string, string>;
} {
  return {
    maxErrors: 10,
    recoveryWindow: 500,
    stackOverflowRecovery: false,
    syntaxErrorStackDepth: 0,
    verbosity: 0,
    astPreallocationRatio: -1.0,
    astPreallocationCap: 0,
    messageOverrides: {},
  };
}

function toNodeAddress(node: Node | bigint | number): bigint {
  if (typeof node === "bigint") return node;
  if (typeof node === "number") return BigInt(node);
  return (node as Node).address;
}

function isInvalid(addr: bigint): boolean {
  return addr === INVALID_NODE;
}

function optNode(session: Session, addr: bigint): Node | null {
  if (isInvalid(addr)) return null;
  return new Node(session, addr);
}

export class Session {
  #handle: Handle | null = null;
  #port: FfiPort;
  #closed = false;

  constructor(port: FfiPort, options: SessionOptions = {}) {
    const merged = { ...defaultOptions(), ...options };
    const overrides = options.messageOverrides ?? merged.messageOverrides;
    this.#port = port;

    const hasNonDefault =
      options.maxErrors !== undefined ||
      options.recoveryWindow !== undefined ||
      options.stackOverflowRecovery !== undefined ||
      options.syntaxErrorStackDepth !== undefined ||
      options.verbosity !== undefined ||
      options.astPreallocationRatio !== undefined ||
      options.astPreallocationCap !== undefined;

    let cOptions: SessionCOptions | null = null;
    if (hasNonDefault) {
      cOptions = {
        maxErrors: merged.maxErrors,
        recoveryWindow: merged.recoveryWindow,
        stackOverflowRecovery: merged.stackOverflowRecovery ? 1 : 0,
        syntaxErrorStackDepth: merged.syntaxErrorStackDepth,
        verbosity: merged.verbosity,
        astPreallocationRatio: merged.astPreallocationRatio,
        astPreallocationCap:
          typeof merged.astPreallocationCap === "bigint"
            ? merged.astPreallocationCap
            : BigInt(merged.astPreallocationCap),
      };
    }

    const handle = this.#port.createSession(cOptions);
    if (handle === null || handle === undefined) {
      throw new GalleyError("out of memory", -7, null);
    }
    this.#handle = handle;

    for (const [name, message] of Object.entries(overrides)) {
      const st = this.#port.setMessageOverride(this.#handle, encodeUtf8(name), encodeUtf8(message));
      if (st < 0) {
        const err = this.#errorFromStatus(st, "failed to register message override");
        this.close();
        throw err;
      }
    }
  }

  get isClosed(): boolean {
    return this.#closed || this.#handle === null;
  }

  #requireHandle(): Handle {
    if (this.#closed || this.#handle === null) throw new Error("session is closed");
    return this.#handle;
  }

  #statusMessage(status: number): string {
    const s = this.#port.statusString(status);
    return s ?? "unknown galley error";
  }

  #errorFromStatus(status: number, fallback?: string): GalleyError {
    let diag: Diagnostic | null = null;
    try {
      if (this.#handle !== null && this.#port.hasDiagnostic(this.#handle)) {
        diag = this.#buildDiagnosticSingular();
      }
    } catch {
      // ignore
    }
    const message = fallback ?? diag?.message ?? this.#statusMessage(status);
    return new GalleyError(message, status, diag);
  }

  #checkStatus(status: number, fallback?: string): void {
    if (status < 0) throw this.#errorFromStatus(status, fallback);
  }

  // -- parser metadata (mirror galley.h; bound to this session's artifact) --

  version(): string {
    return this.#port.version();
  }

  parserType(): number {
    return this.#port.parserType();
  }

  errorRecoveryMode(): number {
    return this.#port.errorRecoveryMode();
  }

  hasAst(): boolean {
    return this.#port.hasAst();
  }

  hasProcedures(): boolean {
    return this.#port.hasProcedures();
  }

  allowsNoAstTreeProcedures(): boolean {
    return this.#port.allowsNoAstTreeProcedures();
  }

  sourceRetentionEnabled(): boolean {
    return this.#port.sourceRetentionEnabled();
  }

  hasPositionTracking(): boolean {
    return this.#port.hasPositionTracking();
  }

  hasInputStreaming(): boolean {
    return this.#port.hasInputStreaming();
  }

  usesVerbatim(): boolean {
    return this.#port.usesVerbatim();
  }

  stackOverflowRecoveryAvailable(): boolean {
    return this.#port.stackOverflowRecoveryAvailable();
  }

  symbolCount(): number {
    return this.#port.symbolCount();
  }

  variableCount(): number {
    return this.#port.variableCount();
  }

  statusString(status: number): string | null {
    return this.#port.statusString(status);
  }

  // -- lifecycle -------------------------------------------------------

  close(): void {
    if (this.#handle !== null) {
      this.#port.destroySession(this.#handle);
      this.#handle = null;
    }
    this.#closed = true;
  }

  /** For `using session = new Session()` (Explicit Resource Management). */
  [Symbol.dispose](): void {
    this.close();
  }

  // -- parsing ---------------------------------------------------------

  parse(input: string | Uint8Array): number {
    const handle = this.#requireHandle();
    const buf = typeof input === "string" ? encodeUtf8(input) : input;
    const previous = setParsingSession(this);
    let status: number;
    try {
      status = this.#port.parse(handle, buf);
    } finally {
      setParsingSession(previous);
    }
    if (status < 0) {
      throw this.#errorFromStatus(status);
    }
    return status;
  }

  parseSentinel(input: string | Uint8Array): number {
    return this.parse(input);
  }

  parseFile(filePath: string): number {
    const handle = this.#requireHandle();
    const previous = setParsingSession(this);
    let status: number;
    try {
      status = this.#port.parseFile(handle, filePath);
    } finally {
      setParsingSession(previous);
    }
    if (status < 0) {
      throw this.#errorFromStatus(status);
    }
    return status;
  }

  // -- arena -----------------------------------------------------------

  nodeCount(): number {
    return this.#port.nodeCount(this.#requireHandle());
  }

  reserveNodes(capacity: number | bigint): void {
    const h = this.#requireHandle();
    const st = this.#port.reserveNodes(h, typeof capacity === "bigint" ? capacity : BigInt(capacity));
    this.#checkStatus(st);
  }

  nodeCapacity(): number {
    return this.#port.nodeCapacity(this.#requireHandle());
  }

  // -- navigation ------------------------------------------------------

  rootNode(): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.#port.rootNode(h));
  }

  nodeValid(node: Node | bigint | number): boolean {
    const h = this.#requireHandle();
    return this.#port.nodeValid(h, toNodeAddress(node));
  }

  childCount(node: Node | bigint | number): number {
    const h = this.#requireHandle();
    return this.#port.childCount(h, toNodeAddress(node));
  }

  children(node: Node | bigint | number): Node[] {
    const h = this.#requireHandle();
    const addr = toNodeAddress(node);
    const count = this.childCount(addr);
    const out: Node[] = [];
    let child = this.#port.firstChild(h, addr);
    for (let i = 0; i < count; i++) {
      if (isInvalid(child)) throw new Error("child count changed during iteration");
      out.push(new Node(this, child));
      child = this.#port.nextSibling(h, child);
    }
    return out;
  }

  firstChild(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.#port.firstChild(h, toNodeAddress(node)));
  }

  lastChild(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.#port.lastChild(h, toNodeAddress(node)));
  }

  nextSibling(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.#port.nextSibling(h, toNodeAddress(node)));
  }

  priorSibling(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.#port.priorSibling(h, toNodeAddress(node)));
  }

  parent(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.#port.parent(h, toNodeAddress(node)));
  }

  /**
   * Pre-order walker over the subtree rooted at `root`, with the root at
   * depth 0. Pass true to prune subtrees rooted at semantic-error nodes.
   * Returns null for invalid roots and builds without AST construction.
   * Close the walker (or use `using`) before closing the session or
   * parsing again.
   */
  walk(root: Node | bigint | number, skipSemanticErrors = false): Walker | null {
    const h = this.#requireHandle();
    const handle = this.#port.walkerCreate(h, toNodeAddress(root), skipSemanticErrors);
    if (handle === null || handle === undefined) return null;
    return new Walker(this, this.#port, handle);
  }

  symbolNameBytes(node: Node | bigint | number): Uint8Array | null {
    const h = this.#requireHandle();
    return this.#port.nodeSymbolName(h, toNodeAddress(node));
  }

  symbolName(node: Node | bigint | number): string | null {
    const bytes = this.symbolNameBytes(node);
    if (bytes === null) return null;
    return decodeUtf8(bytes);
  }

  text(node: Node | bigint | number): Uint8Array | null {
    const h = this.#requireHandle();
    return this.#port.nodeText(h, toNodeAddress(node));
  }

  span(node: Node | bigint | number): [bigint, bigint] | null {
    const h = this.#requireHandle();
    return this.#port.nodeSpan(h, toNodeAddress(node));
  }

  lineColumn(node: Node | bigint | number): [number, number] | null {
    const h = this.#requireHandle();
    return this.#port.nodeLineColumn(h, toNodeAddress(node));
  }

  variableIndex(node: Node | bigint | number): number | null {
    const h = this.#requireHandle();
    const idx = this.#port.nodeVariableIndex(h, toNodeAddress(node));
    if (idx === -1) return null;
    if (idx < 0) throw this.#errorFromStatus(idx);
    return idx;
  }

  lastPosition(): [number, number] | null {
    const h = this.#requireHandle();
    return this.#port.lastPosition(h);
  }

  hasDiagnostic(): boolean {
    const h = this.#requireHandle();
    return this.#port.hasDiagnostic(h);
  }

  setMessageOverride(name: string, message: string): void {
    const h = this.#requireHandle();
    const st = this.#port.setMessageOverride(h, encodeUtf8(name), encodeUtf8(message));
    this.#checkStatus(st);
  }

  // -- diagnostics -----------------------------------------------------

  #buildDiagnosticSingular(): Diagnostic {
    const h = this.#requireHandle();
    const kind = this.#port.diagnosticKind(h);
    const pos = this.#port.diagnosticPosition(h);
    const line = pos ? pos[0] : 0;
    const col = pos ? pos[1] : 0;

    const message = this.#port.diagnosticMessage(h) ?? "";
    const messageAnsi = this.#port.diagnosticMessageAnsi(h) ?? "";

    const unexpected = this.#port.diagnosticUnexpectedToken(h);

    const expectedTokens: Uint8Array[] = [];
    const expCount = this.#port.diagnosticExpectedCount(h);
    if (expCount > 0) {
      for (let i = 0; i < expCount; i++) {
        const b = this.#port.diagnosticExpectedAt(h, i);
        if (b) expectedTokens.push(b);
      }
    }

    const context: string[] = [];
    const ctxCount = this.#port.diagnosticContextCount(h);
    if (ctxCount > 0) {
      for (let i = 0; i < ctxCount; i++) {
        const b = this.#port.diagnosticContextAt(h, i);
        if (b) context.push(decodeUtf8(b));
      }
    }

    const syntaxErrorCount = this.#port.syntaxErrorCount(h);
    const semanticErrorCount = this.#port.semanticErrorCount(h);
    const semantic = this.#port.diagnosticSemantic(h);
    const indentation = this.#port.diagnosticIndentation(h);
    const recovery = this.#readRecoverySingular(h);

    return {
      kind,
      line,
      column: col,
      message,
      messageAnsi,
      unexpectedToken: unexpected,
      expectedTokens,
      context,
      syntaxErrorCount: syntaxErrorCount < 0 ? 0 : syntaxErrorCount,
      semanticErrorCount: semanticErrorCount < 0 ? 0 : semanticErrorCount,
      semantic,
      indentation,
      ...recovery,
    };
  }

  diagnostic(): Diagnostic | null {
    const h = this.#requireHandle();
    if (!this.#port.hasDiagnostic(h)) return null;
    return this.#buildDiagnosticSingular();
  }

  diagnostics(): Diagnostic[] {
    const h = this.#requireHandle();
    const count = this.#port.recordedDiagnosticCount(h);
    if (count <= 0) return [];
    const out: Diagnostic[] = [];
    for (let i = 0; i < count; i++) {
      const d = this.#buildRecordedDiagnostic(i);
      if (d) out.push(d);
    }
    return out;
  }

  #buildRecordedDiagnostic(index: number): Diagnostic | null {
    const h = this.#requireHandle();
    const pos = this.#port.recordedDiagnosticPosition(h, index);
    if (pos === null) return null;

    const kind = this.#port.recordedDiagnosticKind(h, index);
    const [line, col] = pos;

    const message = this.#port.recordedDiagnosticMessage(h, index) ?? "";

    const unexpected = this.#port.recordedUnexpectedToken(h, index);

    const expectedTokens: Uint8Array[] = [];
    const expCount = this.#port.recordedExpectedCount(h, index);
    if (expCount > 0) {
      for (let j = 0; j < expCount; j++) {
        const b = this.#port.recordedExpectedToken(h, index, j);
        if (b) expectedTokens.push(b);
      }
    }

    const context: string[] = [];
    const ctxCount = this.#port.recordedContextCount(h, index);
    if (ctxCount > 0) {
      for (let j = 0; j < ctxCount; j++) {
        const b = this.#port.recordedContextName(h, index, j);
        if (b) context.push(decodeUtf8(b));
      }
    }

    const indentation = this.#port.recordedIndentation(h, index);
    const semantic = this.#port.recordedSemantic(h, index);
    const recovery = this.#readRecoveryRecorded(h, index);

    return {
      kind,
      line,
      column: col,
      message,
      messageAnsi: message,
      unexpectedToken: unexpected,
      expectedTokens,
      context,
      syntaxErrorCount: 0,
      semanticErrorCount: 0,
      semantic,
      indentation,
      ...recovery,
    };
  }

  // -- recovery ---------------------------------------------------------

  #readRecoverySingular(handle: Handle): Omit<
    Diagnostic,
    | "kind"
    | "line"
    | "column"
    | "message"
    | "messageAnsi"
    | "unexpectedToken"
    | "expectedTokens"
    | "context"
    | "syntaxErrorCount"
    | "semanticErrorCount"
    | "semantic"
    | "indentation"
  > {
    const h = handle;
    const kindVal = this.#port.diagnosticRecoveryKind(h);
    const recoveryKind = kindVal === 0 ? null : kindVal;

    const terminal = this.#port.diagnosticRecoveryTerminal(h);
    const resume = this.#port.diagnosticRecoveryResume(h);
    const lhs = this.#port.diagnosticRecoveryLhsVariable(h);
    const production = this.#port.diagnosticRecoveryProduction(h);
    const occurrence = this.#port.diagnosticRecoveryOccurrence(h);

    return {
      recoveryKind,
      recoveryTerminal: terminal,
      recoveryResume: resume,
      recoveryLhsVariable: lhs,
      recoveryProduction: production,
      recoveryOccurrence: occurrence,
    };
  }

  #readRecoveryRecorded(
    handle: Handle,
    idx: number,
  ): Omit<
    Diagnostic,
    | "kind"
    | "line"
    | "column"
    | "message"
    | "messageAnsi"
    | "unexpectedToken"
    | "expectedTokens"
    | "context"
    | "syntaxErrorCount"
    | "semanticErrorCount"
    | "semantic"
    | "indentation"
  > {
    const h = handle;
    const kindVal = this.#port.recordedRecoveryKind(h, idx);
    const recoveryKind = kindVal === 0 ? null : kindVal;

    const terminal = this.#port.recordedRecoveryTerminal(h, idx);
    const resume = this.#port.recordedRecoveryResume(h, idx);
    const lhs = this.#port.recordedRecoveryLhsVariable(h, idx);
    const production = this.#port.recordedRecoveryProduction(h, idx);
    const occurrence = this.#port.recordedRecoveryOccurrence(h, idx);

    return {
      recoveryKind,
      recoveryTerminal: terminal,
      recoveryResume: resume,
      recoveryLhsVariable: lhs,
      recoveryProduction: production,
      recoveryOccurrence: occurrence,
    };
  }

  // -- tree editing ----------------------------------------------------

  appendChildren(parent: Node | bigint, chain: Node | bigint): void {
    const h = this.#requireHandle();
    this.#checkStatus(this.#port.treeAppendChildren(h, toNodeAddress(parent), toNodeAddress(chain)));
  }

  insertBefore(target: Node | bigint, chain: Node | bigint): void {
    const h = this.#requireHandle();
    this.#checkStatus(this.#port.treeInsertBefore(h, toNodeAddress(target), toNodeAddress(chain)));
  }

  insertAfter(target: Node | bigint, chain: Node | bigint): void {
    const h = this.#requireHandle();
    this.#checkStatus(this.#port.treeInsertAfter(h, toNodeAddress(target), toNodeAddress(chain)));
  }

  removeSiblings(node: Node | bigint, count: number): Node | null {
    const h = this.#requireHandle();
    const { status, head } = this.#port.treeRemoveSiblings(h, toNodeAddress(node), count);
    this.#checkStatus(status);
    return optNode(this, head);
  }

  removeSelf(node: Node | bigint): Node | null {
    const h = this.#requireHandle();
    const { status, head } = this.#port.treeRemoveSelf(h, toNodeAddress(node));
    this.#checkStatus(status);
    return optNode(this, head);
  }

  promoteChildrenOverWrapper(wrapper: Node | bigint): Node | null {
    const h = this.#requireHandle();
    const { status, head } = this.#port.treePromoteChildrenOverWrapper(h, toNodeAddress(wrapper));
    this.#checkStatus(status);
    return optNode(this, head);
  }

  cleanChildren(node: Node | bigint): Node | null {
    const h = this.#requireHandle();
    const { status, head } = this.#port.treeCleanChildren(h, toNodeAddress(node));
    this.#checkStatus(status);
    return optNode(this, head);
  }

  unlinkWrapper(wrapper: Node | bigint): void {
    const h = this.#requireHandle();
    this.#checkStatus(this.#port.treeUnlinkWrapper(h, toNodeAddress(wrapper)));
  }

  insertChildrenAt(parent: Node | bigint, index: number, chain: Node | bigint): void {
    const h = this.#requireHandle();
    this.#checkStatus(
      this.#port.treeInsertChildrenAt(h, toNodeAddress(parent), index, toNodeAddress(chain)),
    );
  }

  removeChildrenAt(parent: Node | bigint, index: number, count: number): Node | null {
    const h = this.#requireHandle();
    const { status, head } = this.#port.treeRemoveChildrenAt(
      h,
      toNodeAddress(parent),
      index,
      count,
    );
    this.#checkStatus(status);
    return optNode(this, head);
  }

  // -- symbol table ----------------------------------------------------

  symbolNameAt(index: number): Uint8Array | null {
    const h = this.#requireHandle();
    return this.#port.symbolNameAt(h, index);
  }

  symbolIsTerminal(index: number): boolean {
    const h = this.#requireHandle();
    return this.#port.symbolIsTerminal(h, index);
  }

  variableNameAt(index: number): Uint8Array | null {
    const h = this.#requireHandle();
    return this.#port.variableNameAt(h, index);
  }
}

/** One pre-order step of a {@link Walker}. */
export interface WalkStep {
  node: Node;
  depth: number;
  isSemanticError: boolean;
}

/**
 * Pre-order tree walker over the last successful parse, yielding one
 * {@link WalkStep} per node. Shares the session's node storage: close the
 * walker (or use `using`) before closing the session or parsing again.
 * Created by {@link Session.walk}.
 */
export class Walker implements IterableIterator<WalkStep> {
  #session: Session;
  #port: FfiPort;
  #handle: Handle | null;

  constructor(session: Session, port: FfiPort, handle: Handle) {
    this.#session = session;
    this.#port = port;
    this.#handle = handle;
  }

  next(): IteratorResult<WalkStep> {
    if (this.#handle === null) return { done: true, value: undefined };
    const step = this.#port.walkerNext(this.#handle);
    if (step === null) return { done: true, value: undefined };
    return {
      done: false,
      value: {
        node: new Node(this.#session, step.node),
        depth: step.depth,
        isSemanticError: step.isSemanticError,
      },
    };
  }

  [Symbol.iterator](): IterableIterator<WalkStep> {
    return this;
  }

  /**
   * Prunes the children of the last yielded step; iteration continues with
   * its next sibling. No effect without a last step.
   */
  skipChildren(): void {
    if (this.#handle === null) return;
    this.#port.walkerSkipChildren(this.#handle);
  }

  close(): void {
    if (this.#handle !== null) {
      this.#port.walkerDestroy(this.#handle);
      this.#handle = null;
    }
  }

  /** For `using walker = session.walk(...)`. */
  [Symbol.dispose](): void {
    this.close();
  }
}
