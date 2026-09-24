/**
 * Parsing session bound to this library's parser over `bindings/c/galley.h`.
 *
 * Runtime-neutral: all native calls go through the injected {@link FfiPort}.
 * Factories (`galley` on the universal entry, `openSession` on generated
 * package entries) resolve the backend first and hand a bound port to
 * this constructor.
 */

import { INVALID_NODE, Status } from "./constants.ts";
import type { Kind, RecoveryTarget, Resume } from "./constants.ts";
import type { Diagnostic } from "./diagnostic.ts";
import { GalleyError, SessionClosedError } from "./errors.ts";
import type { FfiPort, Handle, SessionCOptions, TreeSnapshot } from "./port.ts";
import { decodeUtf8 } from "./text.ts";
import { checkArtifactPath, checkMessageBytes, checkParseInput } from "./sources.ts";
import { rejectSessionOptions } from "./internal.ts";
import { Node, nodeAddress } from "./node.ts";
import { ProcedureArguments, ProcedureRegistry, registryFor } from "./procedures.ts";
import type { HookFn } from "./procedures.ts";

export interface SessionOptions {
  maxErrors?: number; // default 10
  recoveryWindow?: number; // default 500
  stackOverflowRecovery?: boolean; // default false
  syntaxErrorStackDepth?: number; // default 0
  verbosity?: number; // default 0
  astPreallocationRatio?: number; // default -1.0 (selects library default)
  astPreallocationCap?: number | bigint; // default 0
}

function defaultOptions(): Required<SessionOptions> {
  return {
    maxErrors: 10,
    recoveryWindow: 500,
    stackOverflowRecovery: false,
    syntaxErrorStackDepth: 0,
    verbosity: 0,
    astPreallocationRatio: -1.0,
    astPreallocationCap: 0,
  };
}

/** Exactly the keys session construction accepts: the parser tunables. */
const SESSION_TUNABLES: ReadonlySet<string> = new Set(Object.keys(defaultOptions()));

function isInvalid(addr: bigint): boolean {
  return addr === INVALID_NODE;
}

function optNode(session: Session, addr: bigint): Node | null {
  if (isInvalid(addr)) return null;
  return new Node(session, addr);
}

/**
 * Per-port stack of synced hook sets, innermost last. Native procedure
 * gates are library-global, so a nested parse on a port-sharing session
 * would otherwise leave the inner set installed when control returns to
 * the still-running outer parse. The parse bracket pushes on entry and
 * restores the enclosing set on unwind; push and pop are paired in
 * `finally`, so the stack is always empty between parses.
 *
 * Anchored on the port object itself under a registered symbol — not in
 * module state — so duplicated core installs in one process share one
 * stack per port, the same reason `activeDispatch` lives on the port.
 * `Symbol.for` is identical across module copies by definition. Ports
 * that refuse extension (never ours, but `FfiPort` is public) fall back
 * to a module WeakMap instead of throwing on assignment.
 */
const GATE_STACK = Symbol.for("@sanbus/galley/gateStack");
const GATE_STACK_FALLBACK = Symbol.for("@sanbus/galley/gateStackFallback");

/**
 * Fallback stacks for ports that refuse extension (never ours, but
 * `FfiPort` is public). Shared through `globalThis` under a registered
 * symbol — not a module `WeakMap` — so duplicated core installs still
 * share one stack per port instead of silently splitting.
 */
function fallbackGateStacks(): WeakMap<FfiPort, string[][]> {
  const holder = globalThis as unknown as Record<symbol, WeakMap<FfiPort, string[][]> | undefined>;
  let maps = holder[GATE_STACK_FALLBACK];
  if (maps === undefined) {
    maps = new WeakMap();
    holder[GATE_STACK_FALLBACK] = maps;
  }
  return maps;
}

function gateStackFor(port: FfiPort, create: boolean): string[][] | undefined {
  if (Object.isExtensible(port)) {
    const holder = port as unknown as Record<symbol, string[][] | undefined>;
    let stack = holder[GATE_STACK];
    if (stack === undefined && create) {
      stack = [];
      holder[GATE_STACK] = stack;
    }
    return stack;
  }
  const maps = fallbackGateStacks();
  let stack = maps.get(port);
  if (stack === undefined && create) {
    stack = [];
    maps.set(port, stack);
  }
  return stack;
}

function pushGates(port: FfiPort, names: string[]): void {
  // Sync before pushing: a throwing sync must not leave an entry the
  // unwind would later pop as if it were a live frame.
  port.syncProcedures(names);
  gateStackFor(port, true)?.push(names);
}

function popGates(port: FfiPort, ownNames: string[]): void {
  const stack = gateStackFor(port, false);
  if (stack === undefined) {
    // Defensive only: every push creates, and push/pop pair in `finally`.
    port.syncProcedures(ownNames);
    return;
  }
  stack.pop();
  const outer = stack[stack.length - 1];
  port.syncProcedures(outer ?? ownNames);
}

export class Session {
  #handle: Handle | null = null;
  #port: FfiPort;
  #closed = false;
  #procedures: ProcedureRegistry;
  /**
   * Parse generation, bumped by every parse and close. Nodes and walkers
   * stamp it at creation and refuse use once it moves, so no accessor or
   * step ever reads reallocated storage.
   */
  #generation = 0;

  /**
   * Takes a bound port: factories resolve the backend first, so a
   * constructed session is always usable. There is no unready state.
   * Hooks come from the port's shared table, so every session on one
   * port reads one registry.
   */
  constructor(port: FfiPort, options: SessionOptions = {}) {
    if (!port) throw new TypeError("galley: Session needs a bound port");
    // Same boundary check as every load factory: a backend pin or a
    // typo'd tunable throws instead of being silently dropped.
    rejectSessionOptions(
      options as unknown as Record<string, unknown>,
      "Session",
      SESSION_TUNABLES,
      "it takes only parser tunables: install hooks on the language handle, " +
        "set message overrides through setMessageOverride, and pin backends on load calls",
    );
    const merged = { ...defaultOptions(), ...options };
    this.#port = port;
    this.#procedures = registryFor(port);

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

    const handle = port.createSession(cOptions);
    if (handle === null || handle === undefined) {
      throw new GalleyError("out of memory", Status.ErrorOutOfMemory, null);
    }
    this.#handle = handle;
  }

  get isClosed(): boolean {
    return this.#closed;
  }

  /**
   * Current parse generation. Internal: `Node` construction and `Walker`
   * steps read this, so handles bound to an older parse fail instead of
   * reading stale storage.
   * @internal
   */
  get parseGeneration(): number {
    return this.#generation;
  }

  #requirePort(): FfiPort {
    if (this.#closed) throw new SessionClosedError("session is closed");
    return this.#port;
  }

  /**
   * The bound port. Every session method reaches the backend through
   * here, so closed sessions fail in one place instead of surfacing
   * native garbage.
   */
  private get port(): FfiPort {
    return this.#requirePort();
  }

  #requireHandle(): Handle {
    this.#requirePort();
    if (this.#closed || this.#handle === null) throw new SessionClosedError("session is closed");
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
    // Boundary trust: `status` is the port's raw status, already known negative.
    return new GalleyError(message, status as Status, diag);
  }

  #checkStatus(status: number, fallback?: string): void {
    if (status < 0) throw this.#errorFromStatus(status, fallback);
  }

  // -- procedures (this session reads its language's shared registry) --

  /**
   * Runs the shared hook for `name` (silent no-op when unregistered).
   * Published on the port as `activeDispatch` for the duration of each
   * parse so native callbacks reach the language's shared registry.
   * Hook exceptions are logged and swallowed so a throwing hook never
   * aborts the parse.
   */
  #dispatchProcedure(name: string, args: Handle, table: Map<string, HookFn>): void {
    const fn = table.get(name);
    if (!fn) return;
    try {
      if (fn.length === 0) {
        (fn as () => void)();
      } else {
        (fn as HookFn)(new ProcedureArguments(args, this, this.#port));
      }
    } catch (err) {
      console.error(`galley procedure ${name} threw:`, err);
    }
  }

  // -- lifecycle -------------------------------------------------------

  /**
   * Idempotent: closing an already-closed session does nothing — no
   * second destroy, no generation advance.
   */
  close(): void {
    if (this.#closed) return;
    if (this.#handle !== null) {
      this.#port.destroySession(this.#handle);
      this.#handle = null;
    }
    this.#closed = true;
    this.#generation++;
  }

  /** For `using session = ...` (Explicit Resource Management). */
  [Symbol.dispose](): void {
    this.close();
  }

  /** For `await using session = await openSession(...)`. */
  async [Symbol.asyncDispose](): Promise<void> {
    this.close();
  }

  // -- parsing ---------------------------------------------------------

  parse(input: string | ArrayBufferView | ArrayBuffer | SharedArrayBuffer): number {
    const handle = this.#requireHandle();
    const port = this.#requirePort();
    const buf = checkParseInput(input, "galley: session.parse");
    // Snapshot isolation: installs and clears made mid-parse apply to
    // later parses only, so dispatch reads the entry table, not the
    // live one.
    const table = this.#procedures.snapshot();
    pushGates(port, [...table.keys()]);
    const previous = port.activeDispatch;
    port.activeDispatch = (name, args) => this.#dispatchProcedure(name, args, table);
    let status: number;
    try {
      status = port.parse(handle, buf);
    } finally {
      // Dispatch restore nests inside the gate restore: a throwing
      // gate sync must not leak this session's dispatch into the
      // enclosing parse.
      try {
        popGates(port, [...table.keys()]);
      } finally {
        port.activeDispatch = previous;
      }
    }
    // Bump even on failure: the storage may have moved, so nodes and
    // walkers from the previous parse fail instead of reading it.
    // Parsing itself never throws merely because a walker is open.
    this.#generation++;
    if (status < 0) {
      throw this.#errorFromStatus(status);
    }
    return status;
  }

  parseFile(filePath: string | URL): number {
    const handle = this.#requireHandle();
    const port = this.#requirePort();
    const file = checkArtifactPath(filePath, "galley: session.parseFile");
    // Snapshot isolation, same as parse: dispatch reads the entry table.
    const table = this.#procedures.snapshot();
    pushGates(port, [...table.keys()]);
    const previous = port.activeDispatch;
    port.activeDispatch = (name, args) => this.#dispatchProcedure(name, args, table);
    let status: number;
    try {
      status = port.parseFile(handle, file);
    } finally {
      // Same nesting as parse: dispatch always restores even when the
      // gate sync throws.
      try {
        popGates(port, [...table.keys()]);
      } finally {
        port.activeDispatch = previous;
      }
    }
    // Same invalidation as parse: nodes and walkers from the previous
    // parse fail instead of reading reallocated storage.
    this.#generation++;
    if (status < 0) {
      throw this.#errorFromStatus(status);
    }
    return status;
  }

  // -- arena -----------------------------------------------------------

  nodeCount(): number {
    return this.port.nodeCount(this.#requireHandle());
  }

  reserveNodes(capacity: number | bigint): void {
    const h = this.#requireHandle();
    const st = this.port.reserveNodes(h, typeof capacity === "bigint" ? capacity : BigInt(capacity));
    this.#checkStatus(st);
  }

  nodeCapacity(): number {
    return this.port.nodeCapacity(this.#requireHandle());
  }

  // -- navigation ------------------------------------------------------

  rootNode(): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.port.rootNode(h));
  }

  nodeValid(node: Node | bigint | number): boolean {
    const h = this.#requireHandle();
    return this.port.nodeValid(h, nodeAddress(node));
  }

  childCount(node: Node | bigint | number): number {
    const h = this.#requireHandle();
    return this.port.childCount(h, nodeAddress(node));
  }

  children(node: Node | bigint | number): Node[] {
    const h = this.#requireHandle();
    const addr = nodeAddress(node);
    const count = this.childCount(addr);
    const out: Node[] = [];
    let child = this.port.firstChild(h, addr);
    for (let i = 0; i < count; i++) {
      if (isInvalid(child)) throw new Error("child count changed during iteration");
      out.push(new Node(this, child));
      child = this.port.nextSibling(h, child);
    }
    return out;
  }

  firstChild(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.port.firstChild(h, nodeAddress(node)));
  }

  lastChild(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.port.lastChild(h, nodeAddress(node)));
  }

  nextSibling(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.port.nextSibling(h, nodeAddress(node)));
  }

  priorSibling(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.port.priorSibling(h, nodeAddress(node)));
  }

  parent(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    return optNode(this, this.port.parent(h, nodeAddress(node)));
  }

  /**
   * Flat bulk read of the most recent successful parse in a single FFI
   * crossing: one array slot per node address. Walk `parent`/`firstChild`/
   * `next` directly instead of one call per node.
   */
  snapshot(): TreeSnapshot {
    return this.port.treeSnapshot(this.#requireHandle());
  }

  /**
   * Pre-order walker over the subtree rooted at `root`, with the root at
   * depth 0. Pass true to prune subtrees rooted at semantic-error nodes.
   * Returns null for invalid roots and builds without AST construction.
   * The walker is bound to the current parse generation: stepping it
   * after the session parses again or closes throws a
   * `SessionClosedError`, so parsing with an abandoned walker still
   * succeeds and the walker fails at its next step.
   */
  walk(root: Node | bigint | number, skipSemanticErrors = false): Walker | null {
    const h = this.#requireHandle();
    const handle = this.port.walkerCreate(h, nodeAddress(root), skipSemanticErrors);
    if (handle === null || handle === undefined) return null;
    return new Walker(this, this.port, handle, this.#generation);
  }

  symbolNameBytes(node: Node | bigint | number): Uint8Array | null {
    const h = this.#requireHandle();
    return this.port.nodeSymbolName(h, nodeAddress(node));
  }

  symbolName(node: Node | bigint | number): string | null {
    const bytes = this.symbolNameBytes(node);
    if (bytes === null) return null;
    return decodeUtf8(bytes);
  }

  text(node: Node | bigint | number): Uint8Array | null {
    const h = this.#requireHandle();
    return this.port.nodeText(h, nodeAddress(node));
  }

  span(node: Node | bigint | number): [bigint, bigint] | null {
    const h = this.#requireHandle();
    return this.port.nodeSpan(h, nodeAddress(node));
  }

  lineColumn(node: Node | bigint | number): [number, number] | null {
    const h = this.#requireHandle();
    return this.port.nodeLineColumn(h, nodeAddress(node));
  }

  variableIndex(node: Node | bigint | number): number | null {
    const h = this.#requireHandle();
    const idx = this.port.nodeVariableIndex(h, nodeAddress(node));
    if (idx === -1) return null;
    if (idx < 0) throw this.#errorFromStatus(idx);
    return idx;
  }

  lastPosition(): [number, number] | null {
    const h = this.#requireHandle();
    return this.port.lastPosition(h);
  }

  /**
   * Retained input of the most recent successful parse as bytes: the
   * buffer that snapshot spans index. Empty before the first parse.
   */
  lastInput(): Uint8Array {
    const h = this.#requireHandle();
    return this.port.lastInput(h) ?? new Uint8Array(0);
  }

  hasDiagnostic(): boolean {
    const h = this.#requireHandle();
    return this.port.hasDiagnostic(h);
  }

  setMessageOverride(name: string | Uint8Array, message: string | Uint8Array): void {
    const h = this.#requireHandle();
    const st = this.port.setMessageOverride(
      h,
      checkMessageBytes(name, "galley: session.setMessageOverride"),
      checkMessageBytes(message, "galley: session.setMessageOverride"),
    );
    this.#checkStatus(st);
  }

  // -- diagnostics -----------------------------------------------------

  #buildDiagnosticSingular(): Diagnostic {
    const h = this.#requireHandle();
    const kind = this.port.diagnosticKind(h) as Kind;
    const pos = this.port.diagnosticPosition(h);
    const line = pos ? pos[0] : 0;
    const col = pos ? pos[1] : 0;

    const message = this.port.diagnosticMessage(h) ?? "";
    const messageAnsi = this.port.diagnosticMessageAnsi(h) ?? "";

    const unexpected = this.port.diagnosticUnexpectedToken(h);

    const expectedTokens: Uint8Array[] = [];
    const expCount = this.port.diagnosticExpectedCount(h);
    if (expCount > 0) {
      for (let i = 0; i < expCount; i++) {
        const b = this.port.diagnosticExpectedAt(h, i);
        if (b) expectedTokens.push(b);
      }
    }

    const context: string[] = [];
    const ctxCount = this.port.diagnosticContextCount(h);
    if (ctxCount > 0) {
      for (let i = 0; i < ctxCount; i++) {
        const b = this.port.diagnosticContextAt(h, i);
        if (b) context.push(decodeUtf8(b));
      }
    }

    const syntaxErrorCount = this.port.syntaxErrorCount(h);
    const semanticErrorCount = this.port.semanticErrorCount(h);
    const semantic = this.port.diagnosticSemantic(h);
    const indentation = this.port.diagnosticIndentation(h);
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
    if (!this.port.hasDiagnostic(h)) return null;
    return this.#buildDiagnosticSingular();
  }

  diagnostics(): Diagnostic[] {
    const h = this.#requireHandle();
    const count = this.port.recordedDiagnosticCount(h);
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
    const pos = this.port.recordedDiagnosticPosition(h, index);
    if (pos === null) return null;

    const kind = this.port.recordedDiagnosticKind(h, index) as Kind;
    const [line, col] = pos;

    const message = this.port.recordedDiagnosticMessage(h, index) ?? "";

    const unexpected = this.port.recordedUnexpectedToken(h, index);

    const expectedTokens: Uint8Array[] = [];
    const expCount = this.port.recordedExpectedCount(h, index);
    if (expCount > 0) {
      for (let j = 0; j < expCount; j++) {
        const b = this.port.recordedExpectedToken(h, index, j);
        if (b) expectedTokens.push(b);
      }
    }

    const context: string[] = [];
    const ctxCount = this.port.recordedContextCount(h, index);
    if (ctxCount > 0) {
      for (let j = 0; j < ctxCount; j++) {
        const b = this.port.recordedContextName(h, index, j);
        if (b) context.push(decodeUtf8(b));
      }
    }

    const indentation = this.port.recordedIndentation(h, index);
    const semantic = this.port.recordedSemantic(h, index);
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
    const kindVal = this.port.diagnosticRecoveryKind(h);
    const recoveryKind = kindVal === 0 ? null : (kindVal as RecoveryTarget);

    const terminal = this.port.diagnosticRecoveryTerminal(h);
    const resume = this.port.diagnosticRecoveryResume(h) as Resume | null;
    const lhs = this.port.diagnosticRecoveryLhsVariable(h);
    const production = this.port.diagnosticRecoveryProduction(h);
    const occurrence = this.port.diagnosticRecoveryOccurrence(h);

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
    const kindVal = this.port.recordedRecoveryKind(h, idx);
    const recoveryKind = kindVal === 0 ? null : (kindVal as RecoveryTarget);

    const terminal = this.port.recordedRecoveryTerminal(h, idx);
    const resume = this.port.recordedRecoveryResume(h, idx) as Resume | null;
    const lhs = this.port.recordedRecoveryLhsVariable(h, idx);
    const production = this.port.recordedRecoveryProduction(h, idx);
    const occurrence = this.port.recordedRecoveryOccurrence(h, idx);

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

  appendChildren(parent: Node | bigint | number, chain: Node | bigint | number): void {
    const h = this.#requireHandle();
    this.#checkStatus(this.port.treeAppendChildren(h, nodeAddress(parent), nodeAddress(chain)));
  }

  insertBefore(target: Node | bigint | number, chain: Node | bigint | number): void {
    const h = this.#requireHandle();
    this.#checkStatus(this.port.treeInsertBefore(h, nodeAddress(target), nodeAddress(chain)));
  }

  insertAfter(target: Node | bigint | number, chain: Node | bigint | number): void {
    const h = this.#requireHandle();
    this.#checkStatus(this.port.treeInsertAfter(h, nodeAddress(target), nodeAddress(chain)));
  }

  removeSiblings(node: Node | bigint | number, count: number): Node | null {
    const h = this.#requireHandle();
    const { status, head } = this.port.treeRemoveSiblings(h, nodeAddress(node), count);
    this.#checkStatus(status);
    return optNode(this, head);
  }

  removeSelf(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    const { status, head } = this.port.treeRemoveSelf(h, nodeAddress(node));
    this.#checkStatus(status);
    return optNode(this, head);
  }

  promoteChildrenOverWrapper(wrapper: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    const { status, head } = this.port.treePromoteChildrenOverWrapper(h, nodeAddress(wrapper));
    this.#checkStatus(status);
    return optNode(this, head);
  }

  cleanChildren(node: Node | bigint | number): Node | null {
    const h = this.#requireHandle();
    const { status, head } = this.port.treeCleanChildren(h, nodeAddress(node));
    this.#checkStatus(status);
    return optNode(this, head);
  }

  unlinkWrapper(wrapper: Node | bigint | number): void {
    const h = this.#requireHandle();
    this.#checkStatus(this.port.treeUnlinkWrapper(h, nodeAddress(wrapper)));
  }

  insertChildrenAt(parent: Node | bigint | number, index: number, chain: Node | bigint | number): void {
    const h = this.#requireHandle();
    this.#checkStatus(
      this.port.treeInsertChildrenAt(h, nodeAddress(parent), index, nodeAddress(chain)),
    );
  }

  removeChildrenAt(parent: Node | bigint | number, index: number, count: number): Node | null {
    const h = this.#requireHandle();
    const { status, head } = this.port.treeRemoveChildrenAt(
      h,
      nodeAddress(parent),
      index,
      count,
    );
    this.#checkStatus(status);
    return optNode(this, head);
  }

  // -- symbol table ----------------------------------------------------

  symbolNameAt(index: number): Uint8Array | null {
    const h = this.#requireHandle();
    return this.port.symbolNameAt(h, index);
  }

  symbolIsTerminal(index: number): boolean {
    const h = this.#requireHandle();
    return this.port.symbolIsTerminal(h, index);
  }

  variableNameAt(index: number): Uint8Array | null {
    const h = this.#requireHandle();
    return this.port.variableNameAt(h, index);
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
 * {@link WalkStep} per node. Bound to the parse generation that created
 * it: stepping after the session parses again or closes throws a
 * `SessionClosedError` instead of reading stale storage. Created by
 * {@link Session.walk}.
 */
export class Walker implements IterableIterator<WalkStep> {
  #session: Session;
  #port: FfiPort;
  #handle: Handle | null;
  #generation: number;
  #closed = false;

  constructor(session: Session, port: FfiPort, handle: Handle, generation: number) {
    this.#session = session;
    this.#port = port;
    this.#handle = handle;
    this.#generation = generation;
  }

  /**
   * The single gate for steps: closed walkers, closed sessions, and
   * walkers left over from a previous parse generation all throw instead
   * of reading reallocated storage.
   */
  #requireHandle(): Handle {
    if (this.#closed || this.#handle === null) throw new SessionClosedError("walker is closed");
    if (this.#session.isClosed) throw new SessionClosedError("session is closed");
    if (this.#generation !== this.#session.parseGeneration) {
      throw new SessionClosedError("walker is invalidated");
    }
    return this.#handle;
  }

  next(): IteratorResult<WalkStep> {
    const step = this.#port.walkerNext(this.#requireHandle());
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
    this.#port.walkerSkipChildren(this.#requireHandle());
  }

  close(): void {
    if (this.#handle !== null) {
      this.#port.walkerDestroy(this.#handle);
      this.#handle = null;
    }
    this.#closed = true;
  }

  /** For `using walker = session.walk(...)`. */
  [Symbol.dispose](): void {
    this.close();
  }
}
