/**
 * Parsing session bound to this library's parser over `bindings/c/galley.h`.
 *
 * Runtime-neutral: all native calls go through the injected {@link FfiPort}.
 * Factories (`galley` on the universal entry, `openSession` on generated
 * package entries) resolve the backend first and hand a bound port to
 * this constructor.
 */

import { INVALID_NODE, NO_VARIABLE, Status } from "./constants.ts";
import type { Kind, RecoveryTarget, Resume } from "./constants.ts";
import type { Diagnostic } from "./diagnostic.ts";
import { GalleyError, SessionClosedError, StaleTreeError } from "./errors.ts";
import type { FfiPort, Handle, HookTicket, NodeFamily, SessionCOptions, SnapshotColumns } from "./port.ts";
import { decodeUtf8 } from "./text.ts";
import { checkArtifactPath, checkMessageBytes, checkParseInput } from "./sources.ts";
import { rejectSessionOptions } from "./internal.ts";
import { Node, createNode, installWalkStart, nodeAddress } from "./node.ts";
import type { NodeDoor } from "./node.ts";
import { ProcedureArguments, ProcedureRegistry, routerFor } from "./procedures.ts";
import type { HookFn, HookOwner } from "./procedures.ts";

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

/**
 * Flat bulk read of the most recent successful parse: the columns of one
 * parse plus the sanctioned conversion back to nodes. The snapshot
 * remembers the parse generation it describes, so `node(address)` answers
 * with a node of exactly that parse — reading through it after a
 * re-parse throws instead of reading the tree that replaced it.
 */
export interface TreeSnapshot extends SnapshotColumns {
  /**
   * The node at `address` of the parse these columns describe, or null
   * for `INVALID_NODE`.
   *
   * @throws TypeError when `address` is neither a bigint nor a
   *         safe-integer number.
   * @throws RangeError when `address` is at or past `count`, or negative.
   */
  node(address: number | bigint): Node | null;
}

/**
 * What a stale-tree failure says, whichever door or crossing found the tree
 * gone: what happened and what to do next.
 */
const STALE_TREE_MESSAGE =
  "this handle's tree is stale: the session parsed again since; read rootNode() for a current node";

function isInvalid(addr: bigint): boolean {
  return addr === INVALID_NODE;
}

/**
 * A door as an address-level crossing: one family of core calls
 * (`galley_node_*` over the session handle, or the `galley_hook_*` twins
 * over a parse's native door) and the handle to call it on. Every call
 * carries the generation it addresses, which the core compares against the
 * door's tree, so this binding keeps no cached copy of that generation and
 * no per-call state: the caller passes the node's own generation, or the one
 * `rootNode()` stamped.
 */
class Door implements NodeDoor {
  readonly #family: NodeFamily;
  readonly #handle: Handle;
  /** The session that owns this door, for the one refusal conversion. */
  readonly #session: Session;

  constructor(session: Session, family: NodeFamily, handle: Handle) {
    this.#session = session;
    this.#family = family;
    this.#handle = handle;
  }

  /**
   * Throws the core's refusal when `status` is negative. Every crossing
   * goes through here, so a refusal is never a value a caller could
   * mistake for an answer. A status is always a Number; a value that is a
   * BigInt (an address) is never a status.
   */
  #check(status: number): void {
    if (status < 0) throw this.#session.errorFromStatus(status);
  }

  /** A link answer: a status (negative) throws, an address is a BigInt. */
  #link(value: bigint | number): bigint {
    if (typeof value === "bigint") {
      if (value < 0n) throw this.#session.errorFromStatus(Number(value));
      return value;
    }
    if (value < 0) throw this.#session.errorFromStatus(value);
    return BigInt(value);
  }

  #cross<T>(value: T | number): T {
    if (typeof value === "number" && value < 0) throw this.#session.errorFromStatus(value);
    return value as T;
  }

  childCount(generation: number, address: bigint): number {
    const count = this.#family.childCount(this.#handle, generation, address);
    if (count < 0) throw this.#session.errorFromStatus(count);
    return count;
  }

  firstChild(generation: number, address: bigint): bigint {
    return this.#link(this.#family.firstChild(this.#handle, generation, address));
  }

  lastChild(generation: number, address: bigint): bigint {
    return this.#link(this.#family.lastChild(this.#handle, generation, address));
  }

  nextSibling(generation: number, address: bigint): bigint {
    return this.#link(this.#family.nextSibling(this.#handle, generation, address));
  }

  priorSibling(generation: number, address: bigint): bigint {
    return this.#link(this.#family.priorSibling(this.#handle, generation, address));
  }

  parent(generation: number, address: bigint): bigint {
    return this.#link(this.#family.parent(this.#handle, generation, address));
  }

  text(generation: number, address: bigint): Uint8Array {
    return this.#cross(this.#family.nodeText(this.#handle, generation, address));
  }

  symbolNameBytes(generation: number, address: bigint): Uint8Array {
    return this.#cross(this.#family.nodeSymbolName(this.#handle, generation, address));
  }

  span(generation: number, address: bigint): [bigint, bigint] {
    return this.#cross(this.#family.nodeSpan(this.#handle, generation, address));
  }

  lineColumn(generation: number, address: bigint): [number, number] {
    return this.#cross(this.#family.nodeLineColumn(this.#handle, generation, address));
  }

  variableIndex(generation: number, address: bigint): number | null {
    const index = this.#family.nodeVariableIndex(this.#handle, generation, address);
    if (index === null) return null;
    this.#check(index);
    return index;
  }

  walkNext(cursor: ArrayBuffer): number {
    return this.#family.walkNext(this.#handle, cursor);
  }

  cleanChildren(generation: number, address: bigint): bigint {
    const { status, head } = this.#family.treeCleanChildren(this.#handle, generation, address);
    this.#check(status);
    return head;
  }

  appendChildren(generation: number, parent: bigint, chainGeneration: number, chain: bigint): void {
    this.#check(this.#family.treeAppendChildren(this.#handle, generation, parent, chainGeneration, chain));
  }

  insertBefore(generation: number, target: bigint, chainGeneration: number, chain: bigint): void {
    this.#check(this.#family.treeInsertBefore(this.#handle, generation, target, chainGeneration, chain));
  }

  insertAfter(generation: number, target: bigint, chainGeneration: number, chain: bigint): void {
    this.#check(this.#family.treeInsertAfter(this.#handle, generation, target, chainGeneration, chain));
  }

  removeSiblings(generation: number, address: bigint, count: number): bigint {
    const { status, head } = this.#family.treeRemoveSiblings(this.#handle, generation, address, count);
    this.#check(status);
    return head;
  }

  removeSelf(generation: number, address: bigint): bigint {
    const { status, head } = this.#family.treeRemoveSelf(this.#handle, generation, address);
    this.#check(status);
    return head;
  }

  insertChildrenAt(generation: number, parent: bigint, index: number, chainGeneration: number, chain: bigint): void {
    this.#check(this.#family.treeInsertChildrenAt(this.#handle, generation, parent, index, chainGeneration, chain));
  }

  removeChildrenAt(generation: number, parent: bigint, index: number, count: number): bigint {
    const { status, head } = this.#family.treeRemoveChildrenAt(this.#handle, generation, parent, index, count);
    this.#check(status);
    return head;
  }
}

/**
 * The module-private credential the {@link Walker} constructor demands.
 * Never exported, so no package entry point can hand it out: every walker
 * comes from the walk-start path `Session` installs for `Node.walk`.
 */
const WALKER_CONSTRUCTION_TOKEN: symbol = Symbol("galley.Walker.construction");

/**
 * One parsing session. Owns its hooks: a registry copied from the
 * parser's defaults when the session opens, applied to the library at once
 * on every change, so the hooks a parse runs with are fixed for that parse.
 * Changing hooks from a hook, or while a parse is in flight anywhere,
 * throws a `GalleyError` with status `-13` (`ErrorSessionInUse`).
 */
export class Session implements HookOwner {
  static {
    // The one walk-start path. It lives in the class body to reach the
    // private door, port and intern table, and it is installed behind
    // `Node.walk` only: no member of `Session` starts a walk, so
    // `Node.walk` is the single way in. The door is hook-aware and throws
    // when the session is closed; the generation gate is the one every
    // node argument crosses.
    installWalkStart((session, root, skipSemanticErrors, skipRecovered) => {
      session.#door(); // throws when the session is closed
      const address = session.admit(root);
      // The walk is bound to the tree the node came from: the cursor carries
      // the node's own generation, and the core refuses it at the first step
      // if that tree is gone — nothing asks the core here.
      const generation = root.generation;
      return Walker.create(
        WALKER_CONSTRUCTION_TOKEN,
        session,
        address,
        generation,
        skipSemanticErrors,
        skipRecovered,
        session.#port.walkCursorLittleEndian,
        (nodeAddress) => session.#nodeForGeneration(generation, nodeAddress),
      );
    });
  }

  #handle: Handle | null = null;
  #port: FfiPort;
  #closed = false;
  /** This session's hooks by name: replaced whole by every change, never mutated. */
  #hooks = new ProcedureRegistry();
  /** The same hooks by the library's hook index: the dispatch lookup. */
  #hooksByIndex: (HookFn | undefined)[] = [];
  /** The handle the library hands back with this session's hooks. */
  #hookHandle = 0;
  /**
   * The running parse's hook door, learned from its first dispatch (the
   * native door is constant for the parse) and dropped by the parse's finish
   * gate; null between parses.
   */
  #parseDoor: Door | null = null;
  /**
   * The core generation of the running parse, read through
   * `galley_hook_generation` on its first dispatch: only the stamp for the
   * nodes its hooks produce, never compared with anything — the core checks
   * every node it is handed.
   */
  #parseGeneration = 0;
  /**
   * True exactly while a hook runs. JavaScript runs one thread per session
   * and a parse is synchronous, so the only code that can run while a parse
   * of this session is in progress is a hook: a call made while this is set
   * is exactly a call inside a hook dispatch of the running parse.
   */
  #dispatching = false;

  /**
   * What the hook of the running parse threw, kept by the upcall that caught
   * it; the parse that returns `ErrorHookFailed` raises its failure with this
   * as the cause and drops it. A box, because a hook may throw `undefined`.
   */
  #hookFailure: { thrown: unknown } | null = null;
  /**
   * The newest generation's interned node handles, indexed by address (the
   * core's addresses are dense node indices), with the generation they
   * belong to; null when nothing is interned. One object per (session,
   * generation, address), so `===` is the sanctioned identity — "the same
   * node of the same parse". Strong rather than weak (~82 B/node): the table
   * is replaced when a node of a newer generation arrives and cleared by
   * `close()`, so it holds one parse's nodes and never a superseded one's.
   */
  #internGeneration: number | null = null;
  #internedNodes: (Node | undefined)[] = [];
  /** The session door, crossed by every call outside a hook dispatch. */
  readonly #sessionDoor: Door;

  /**
   * Takes a bound port: factories resolve the backend first, so a
   * constructed session is always usable. There is no unready state.
   * The session's hooks start as a copy of the defaults of the parser
   * it opens from — handed in, never read from shared state.
   */
  constructor(port: FfiPort, options: SessionOptions = {}, defaults: ProcedureRegistry) {
    if (!port) throw new TypeError("galley: Session needs a bound port");
    if (!defaults) {
      throw new TypeError("galley: Session opens from a parser; use parser.openSession()");
    }
    // Same boundary check as every load factory: a backend pin or a
    // typo'd tunable throws instead of being silently dropped.
    rejectSessionOptions(
      options as unknown as Record<string, unknown>,
      "Session",
      SESSION_TUNABLES,
      "it takes only parser tunables: install hooks on the parser or the session, " +
        "set message overrides through setMessageOverride, and pin backends on load calls",
    );
    const merged = { ...defaultOptions(), ...options };
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

    const handle = port.createSession(cOptions);
    if (handle === null || handle === undefined) {
      throw new GalleyError("out of memory", Status.ErrorOutOfMemory, null);
    }
    this.#handle = handle;
    this.#sessionDoor = new Door(this, port.session, handle);
    this.#hookHandle = routerFor(port).register(this);
    try {
      this.#commitHooks(defaults.copy());
    } catch (error) {
      this.close();
      throw error;
    }
  }

  get isClosed(): boolean {
    return this.#closed;
  }

  /**
   * The door a call crosses, chosen now: from inside a hook dispatch of
   * this session's running parse, that parse's hook door; everywhere else
   * the session door, which the core refuses while a parse runs. The only
   * place the choice is made.
   *
   */
  #door(): NodeDoor {
    this.#requireHandle();
    if (this.#dispatching && this.#parseDoor !== null) return this.#parseDoor;
    return this.#sessionDoor;
  }

  /**
   * The published tree's root and generation, read from the core in one
   * crossing — the only source of that generation, and the one "is there a
   * tree here" probe. Nothing published is `{ root: INVALID_NODE,
   * generation: 0n }`; a refusal throws.
   */
  #published(): { root: bigint; generation: number } {
    const { status, root, generation } = this.#port.rootNode(this.#requireHandle());
    if (status < 0) throw this.errorFromStatus(status);
    return { root, generation };
  }

  /**
   * The single gate for a node argument: a `Node` must belong to this
   * session. The crossing then sends a bare address with the node's own
   * generation, and the core owns whether that generation is live on the
   * door in use (stale tree otherwise), on either door. A bare address never
   * reaches the crossing: {@link nodeAddress} refuses it at entry, because
   * it carries no session and no generation to vouch for it.
   *
   * @throws TypeError when `node` is not a `Node` or belongs to a
   *         different session.
   * @internal
   */
  admit(node: Node): bigint {
    const address = nodeAddress(node);
    if (node.session.isClosed) throw new SessionClosedError("node's session is closed");
    if (node.session !== this) {
      throw new TypeError("node belongs to a different session than this operation");
    }
    return address;
  }

  /**
   * The one creation path for `Node` handles, and the lazy generation
   * gate: the table holds the live generation's nodes — the published
   * tree's, or the running parse's while its hooks dispatch — one object
   * per address, so `===` answers "the same node of the same parse"
   * everywhere a node is reached: links, children, `rootNode`, hook
   * arguments, snapshot `node()`, and walker steps alike. A newer
   * generation resets the table; an older one — a stale snapshot's
   * `node()` after a re-parse or a failed parse — answers with a fresh,
   * uninterned handle each call, because its generation is no longer
   * live.
   *
   * Module-private: unreachable from any package entry point, and the
   * `Node` constructor it calls demands a token this module never
   * exports.
   */
  #nodeForGeneration(generation: number, address: bigint): Node {
    // There is no closed-session branch: every post-close read throws
    // SessionClosedError before reaching this gate, and a close inside a
    // hook aborts in the core.
    if (generation !== this.#internGeneration) {
      const tableGeneration = this.#internGeneration;
      if (tableGeneration !== null && generation < tableGeneration) {
        // Only a newer generation takes the table over; an older one is
        // dead and never re-interned. Which generation is live is the
        // core's business — every read of this handle asks it.
        return createNode(this, address, generation);
      }
      this.#internGeneration = generation;
      this.#internedNodes = [];
    }
    const index = Number(address);
    const interned = this.#internedNodes[index];
    if (interned !== undefined) return interned;
    const node = createNode(this, address, generation);
    this.#internedNodes[index] = node;
    return node;
  }

  /** Wraps an address read at `generation`; invalid becomes null. */
  #wrap(generation: number, address: bigint): Node | null {
    return isInvalid(address) ? null : this.#nodeForGeneration(generation, address);
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

  /**
   * The one status-to-failure conversion, shared with {@link Door}
   * so no crossing spells one out. A stale tree is one failure however it
   * arrived — the core's own stale status, or a walk step — so it is always
   * the `StaleTreeError` subclass, and `instanceof GalleyError` still
   * catches it.
   * @internal
   */
  errorFromStatus(status: number, fallback?: string, options?: ErrorOptions): GalleyError {
    if (status === Status.ErrorStaleTree) {
      return new StaleTreeError(STALE_TREE_MESSAGE);
    }
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
    return new GalleyError(message, status as Status, diag, options);
  }

  #checkStatus(status: number, fallback?: string): void {
    if (status < 0) throw this.errorFromStatus(status, fallback);
  }

  // -- procedures (this session's own hooks) --

  /** Installs a hook on this session only. Takes effect from the next parse. */
  installProcedure(name: string, fn: HookFn | (() => void)): void {
    const next = this.#hooks.copy();
    next.install(name, fn);
    this.#commitHooks(next);
  }

  /**
   * Scans `module` for exported procedure hooks (`reduction`,
   * `reduction_*`, `hook_*`) and registers each on this session in one
   * step. Returns the number installed.
   */
  installProcedures(module: Record<string, unknown>): number {
    const next = this.#hooks.copy();
    const installed = next.installModule(module);
    if (installed > 0) this.#commitHooks(next);
    return installed;
  }

  /** Removes all of this session's hooks. */
  clearProcedures(): void {
    this.#commitHooks(new ProcedureRegistry());
  }

  /** Returns a copy of this session's hooks (name -> callable). */
  listProcedures(): Record<string, HookFn> {
    const table: Record<string, HookFn> = {};
    for (const name of this.#hooks.names()) {
      const hook = this.#hooks.get(name);
      if (hook !== undefined) table[name] = hook;
    }
    return table;
  }

  /** The hook for `name` on this session, if any. */
  procedureHook(name: string): HookFn | undefined {
    return this.#hooks.get(name);
  }

  /**
   * Single gate for every hook change: hands the library the enabled set
   * first, so a refusal (a parse in flight) leaves the hooks and the
   * library exactly as they were, then publishes the registry and its
   * by-index view.
   */
  #commitHooks(next: ProcedureRegistry): void {
    const handle = this.#requireHandle();
    const byIndex = routerFor(this.#port).resolve(next);
    const enabled = Uint8Array.from(byIndex, (hook) => (hook === undefined ? 0 : 1));
    this.#checkStatus(this.#port.setSessionHooks(handle, this.#hookHandle, enabled));
    this.#hooks = next;
    this.#hooksByIndex = byIndex;
  }

  /**
   * Runs hook `index` of the running parse, on the parsing thread, under the
   * ticket the core issued for this call. Answers zero, or one when the hook
   * threw (or its door could not open): nothing may escape an upcall into the
   * core, so the thrown value is kept and the core aborts the parse.
   * @internal
   */
  dispatchHook(index: number, hook: HookTicket): number {
    const fn = this.#hooksByIndex[index];
    if (!fn) return 0;
    try {
      this.#runHook(fn, hook);
      return 0;
    } catch (thrown) {
      this.#hookFailure = { thrown };
      return 1;
    } finally {
      this.#dispatching = false;
    }
  }

  #runHook(fn: HookFn | (() => void), hook: HookTicket): void {
    // The parse's native door and core generation are constant for the
    // parse: read them on its first dispatch, drop them in the finish gate.
    // Only the "a hook is running" flag is set per dispatch, which is what
    // lets a call choose its door when it is made.
    if (this.#parseDoor === null) {
      const opened = this.#port.procDoor(this.#requireHandle(), hook);
      if (opened.status < 0) throw this.errorFromStatus(opened.status);
      const nativeDoor = opened.door;
      const generation = this.#port.hookGeneration(nativeDoor);
      if (generation < 0) throw this.errorFromStatus(generation);
      this.#parseGeneration = generation;
      this.#parseDoor = new Door(this, this.#port.hook, nativeDoor);
    }
    this.#dispatching = true;
    if (fn.length === 0) {
      (fn as () => void)();
      return;
    }
    const procedureArguments = new ProcedureArguments(
      hook,
      this.#requireHandle(),
      this,
      this.#port,
      (address) => this.#wrap(this.#parseGeneration, address),
    );
    (fn as HookFn)(procedureArguments);
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
      routerFor(this.#port).unregister(this.#hookHandle);
    }
    this.#closed = true;
    // No door outlives the session: dispatch chooses the session door from
    // here on, and the empty table can never adopt a lingering parse
    // door's generation.
    this.#parseDoor = null;
    // Nothing is live on a closed session: the table must not retain the
    // handles it holds strongly, or the session would keep its whole tree
    // reachable after close.
    this.#internGeneration = null;
    this.#internedNodes = [];
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
    return this.#finishParse(() => port.parse(handle, buf));
  }

  parseFile(filePath: string | URL): number {
    const handle = this.#requireHandle();
    const port = this.#requirePort();
    const file = checkArtifactPath(filePath, "galley: session.parseFile");
    return this.#finishParse(() => port.parseFile(handle, file));
  }

  /**
   * Single gate for every parse leg: runs the native call, then drops the
   * parse's door. Nothing else is recorded: the core owns which generation
   * is live, and every read of a handle asks it, so this binding keeps no
   * copy of it to fall behind. The intern table needs no drop here either —
   * the next node created at a newer generation takes it over. A parse the
   * core refused with `ErrorSessionInUse` changed nothing, so it leaves the
   * running parse's door and its intern table alone. Parsing itself never
   * throws merely because a walker is open. The hooks were fixed by the
   * last commit, so nothing is synchronized here.
   */
  #finishParse(nativeParse: () => number): number {
    let status: number;
    try {
      status = nativeParse();
    } catch (error) {
      this.#parseDoor = null;
      this.#hookFailure = null;
      throw error;
    }
    let hookFailure: { thrown: unknown } | null = null;
    if (status !== Status.ErrorSessionInUse) {
      // The parse is over: its door dies with it, and so does the exception
      // a hook of it raised once its failure carries it. A refused parse
      // started nothing, so it leaves the running parse's state alone.
      this.#parseDoor = null;
      hookFailure = this.#hookFailure;
      this.#hookFailure = null;
    }
    if (status < 0) {
      const cause = status === Status.ErrorHookFailed && hookFailure !== null
        ? { cause: hookFailure.thrown }
        : undefined;
      throw this.errorFromStatus(status, undefined, cause);
    }
    return status;
  }

  // -- arena -----------------------------------------------------------

  /**
   * Node count of the published tree. Nothing published is the core's
   * stale-tree refusal (generation 0 is never live), never a zero.
   */
  nodeCount(): number {
    const generation = this.#published().generation;
    const count = this.port.nodeCount(this.#requireHandle(), generation);
    if (typeof count !== "number" || count < 0) {
      throw this.errorFromStatus(count as number);
    }
    return count;
  }

  reserveNodes(capacity: number | bigint): void {
    const h = this.#requireHandle();
    const st = this.port.reserveNodes(h, typeof capacity === "bigint" ? capacity : BigInt(capacity));
    this.#checkStatus(st);
  }

  /**
   * Current node storage capacity in nodes. Throws `GalleyError` (session in
   * use) while a parse runs.
   */
  nodeCapacity(): number {
    const capacity = this.port.nodeCapacity(this.#requireHandle());
    if (capacity < 0) throw this.errorFromStatus(capacity);
    return capacity;
  }

  // -- navigation ------------------------------------------------------

  /**
   * Root of the published tree, or null when nothing is published — the one
   * "is there a tree here" probe. The returned node carries the generation
   * the core reported, which every later read hands back to the core.
   */
  rootNode(): Node | null {
    const { root, generation } = this.#published();
    if (isInvalid(root)) return null;
    return this.#nodeForGeneration(generation, root);
  }

  childCount(node: Node): number {
    const door = this.#door();
    return door.childCount(node.generation, this.admit(node));
  }

  /**
   * The one children iteration: count-bounded, first to last, every step
   * crossing the same door, and a mismatch between the count and the
   * chain still fails loudly.
   */
  children(node: Node): Node[] {
    const door = this.#door();
    const address = this.admit(node);
    const generation = node.generation;
    const count = door.childCount(generation, address);
    const out: Node[] = [];
    let child = door.firstChild(generation, address);
    for (let i = 0; i < count; i++) {
      const wrapped = this.#wrap(generation, child);
      if (wrapped === null) throw new Error("child count changed during iteration");
      out.push(wrapped);
      child = door.nextSibling(generation, child);
    }
    return out;
  }

  firstChild(node: Node): Node | null {
    const door = this.#door();
    return this.#wrap(node.generation, door.firstChild(node.generation, this.admit(node)));
  }

  lastChild(node: Node): Node | null {
    const door = this.#door();
    return this.#wrap(node.generation, door.lastChild(node.generation, this.admit(node)));
  }

  nextSibling(node: Node): Node | null {
    const door = this.#door();
    return this.#wrap(node.generation, door.nextSibling(node.generation, this.admit(node)));
  }

  priorSibling(node: Node): Node | null {
    const door = this.#door();
    return this.#wrap(node.generation, door.priorSibling(node.generation, this.admit(node)));
  }

  parent(node: Node): Node | null {
    const door = this.#door();
    return this.#wrap(node.generation, door.parent(node.generation, this.admit(node)));
  }

  /**
   * Flat bulk read of the published tree in a single FFI crossing: one
   * array slot per node address, plus `node(address)` — the one conversion
   * from a stored address back to a node of the parse the columns describe.
   * Walk `parent`/`firstChild`/`next` directly instead of one call per
   * node.
   *
   * Every leg carries one generation, so a parse that runs in between
   * throws instead of returning columns that mix two trees.
   */
  snapshot(): TreeSnapshot {
    const handle = this.#requireHandle();
    const generation = this.#published().generation;
    const read = this.port.treeSnapshot(handle, generation);
    if (typeof read !== "object") throw this.errorFromStatus(read as number);
    const columns = read;
    // The core marks a node without a variable with its non-negative
    // `GALLEY_NO_VARIABLE`; this API's column spells it -1.
    const variable = columns.variable;
    for (let i = 0; i < variable.length; i++) {
      if (variable[i] === NO_VARIABLE) variable[i] = -1n;
    }
    const count = columns.count;
    const limit = BigInt(count);
    return {
      ...columns,
      node: (address: number | bigint): Node | null => {
        let index: bigint;
        if (typeof address === "bigint") {
          index = address;
        } else if (typeof address === "number" && Number.isSafeInteger(address)) {
          index = BigInt(address);
        } else {
          // Only an address crosses: no stringified, fractional or boxed
          // value coerces into one.
          throw new TypeError(
            `galley: snapshot.node expects a bigint or a safe-integer number, got ${
              typeof address === "number" ? "a non-safe-integer number" : typeof address
            }`,
          );
        }
        if (index === INVALID_NODE) return null;
        if (index < 0n || index >= limit) {
          throw new RangeError(
            `node address ${index} out of range for a snapshot of ${count} nodes`,
          );
        }
        return this.#nodeForGeneration(generation, index);
      },
    };
  }

  /**
   * One step of a walk: crosses the door of the calling context — the
   * hook door inside a hook dispatch of this session's running parse, the
   * session door everywhere else — and maps the status onto the walker's
   * contract: null at the end of the walk, the session's own error (a
   * `StaleTreeError` when the walker's generation is not the tree's anymore)
   * for a refusal.
   * @internal
   */
  walkStep(
    cursor: ArrayBuffer,
  ): { node: bigint; depth: number; isSemanticError: boolean; isRecovered: boolean } | null {
    const status = this.#door().walkNext(cursor);
    this.#checkStatus(status);
    if (status === 0) return null;
    const view = new DataView(cursor);
    const littleEndian = this.#port.walkCursorLittleEndian;
    return {
      node: view.getBigUint64(WALK_OFFSET_CURRENT, littleEndian),
      depth: view.getUint32(WALK_OFFSET_DEPTH, littleEndian),
      isSemanticError: (view.getUint8(WALK_OFFSET_FLAG) & WALK_FLAG_SEMANTIC_ERROR) !== 0,
      isRecovered: (view.getUint8(WALK_OFFSET_FLAG) & WALK_FLAG_RECOVERED) !== 0,
    };
  }

  symbolNameBytes(node: Node): Uint8Array {
    const door = this.#door();
    return door.symbolNameBytes(node.generation, this.admit(node));
  }

  symbolName(node: Node): string {
    return decodeUtf8(this.symbolNameBytes(node));
  }

  text(node: Node): Uint8Array {
    const door = this.#door();
    return door.text(node.generation, this.admit(node));
  }

  span(node: Node): [bigint, bigint] {
    const door = this.#door();
    return door.span(node.generation, this.admit(node));
  }

  lineColumn(node: Node): [number, number] {
    const door = this.#door();
    return door.lineColumn(node.generation, this.admit(node));
  }

  variableIndex(node: Node): number | null {
    const door = this.#door();
    return door.variableIndex(node.generation, this.admit(node));
  }

  /**
   * The `[line, column]` where the published parse ended (zeros when the
   * parser was built without position tracking). Follows the published tree
   * like every node read: throws `StaleTreeError` whenever nothing is
   * published, before the first parse included.
   */
  lastPosition(): [number, number] {
    const h = this.#requireHandle();
    const read = this.port.lastPosition(h);
    if (typeof read === "number") throw this.errorFromStatus(read);
    return read;
  }

  /**
   * Retained input of the published parse as bytes: the buffer that
   * snapshot spans index. Follows the published tree like every node read:
   * throws `StaleTreeError` whenever nothing is published, before the first
   * parse included.
   */
  lastInput(): Uint8Array {
    const h = this.#requireHandle();
    const read = this.port.lastInput(h);
    if (typeof read === "number") throw this.errorFromStatus(read);
    return read;
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

  appendChildren(parent: Node, chain: Node): void {
    const door = this.#door();
    door.appendChildren(parent.generation, this.admit(parent), chain.generation, this.admit(chain));
  }

  insertBefore(target: Node, chain: Node): void {
    const door = this.#door();
    door.insertBefore(target.generation, this.admit(target), chain.generation, this.admit(chain));
  }

  insertAfter(target: Node, chain: Node): void {
    const door = this.#door();
    door.insertAfter(target.generation, this.admit(target), chain.generation, this.admit(chain));
  }

  removeSiblings(node: Node, count: number): Node | null {
    const door = this.#door();
    return this.#wrap(node.generation, door.removeSiblings(node.generation, this.admit(node), count));
  }

  removeSelf(node: Node): Node | null {
    const door = this.#door();
    return this.#wrap(node.generation, door.removeSelf(node.generation, this.admit(node)));
  }

  cleanChildren(node: Node): Node | null {
    const door = this.#door();
    return this.#wrap(node.generation, door.cleanChildren(node.generation, this.admit(node)));
  }

  insertChildrenAt(parent: Node, index: number, chain: Node): void {
    const door = this.#door();
    door.insertChildrenAt(parent.generation, this.admit(parent), index, chain.generation, this.admit(chain));
  }

  removeChildrenAt(parent: Node, index: number, count: number): Node | null {
    const door = this.#door();
    return this.#wrap(parent.generation, door.removeChildrenAt(parent.generation, this.admit(parent), index, count));
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
  /**
   * The node syntax-error recovery kept in place of damaged input; its span
   * covers the input recovery skipped.
   */
  isRecovered: boolean;
}

// The host-owned walk cursor, byte-for-byte `GalleyWalkCursor` from
// galley.h: generation u64 @0, root u64 @8, current u64 @16, depth u32
// @24, state u16 @28, options u8 @30, flags u8 @31,
// structure_version u64 @32 — 40 bytes in the port's byte order (the
// last field is stamped by the core and never read host-side, so the
// zeroed ArrayBuffer supplies it).
const WALK_CURSOR_BYTES = 40;
const WALK_OFFSET_GENERATION = 0;

/**
 * Writes a non-negative safe integer into the 8 cursor bytes at `offset` as
 * two 32-bit halves, so the generation, a plain number everywhere else,
 * never becomes a BigInt on its way into the cursor.
 */
function setUint64FromNumber(view: DataView, offset: number, value: number, littleEndian: boolean): void {
  const low = value % 0x100000000;
  const high = (value - low) / 0x100000000;
  view.setUint32(offset + (littleEndian ? 0 : 4), low, littleEndian);
  view.setUint32(offset + (littleEndian ? 4 : 0), high, littleEndian);
}
const WALK_OFFSET_ROOT = 8;
const WALK_OFFSET_CURRENT = 16;
const WALK_OFFSET_DEPTH = 24;
const WALK_OFFSET_STATE = 28;
const WALK_OFFSET_OPTIONS = 30;
const WALK_OFFSET_FLAG = 31;
const WALK_STATE_NOT_STARTED = 0;
const WALK_STATE_YIELDED = 1;
const WALK_STATE_YIELDED_SKIP_CHILDREN = 2;
const WALK_OPTION_SKIP_SEMANTIC_ERRORS = 1;
const WALK_OPTION_SKIP_RECOVERED = 2;
const WALK_FLAG_SEMANTIC_ERROR = 1;
const WALK_FLAG_RECOVERED = 2;

/**
 * Pre-order tree walker over a node's subtree, yielding one
 * {@link WalkStep} per node, the walk's root at depth 0. Created by
 * {@link Node.walk}, never constructed directly.
 *
 * The walker owns no native resource: it is one host-side 40-byte
 * cursor, so abandoning it is free and parsing again with one open never
 * disturbs the parse — the walker fails at its next step instead. Each
 * step picks its door like any node call, so a walk created inside a
 * hook of a running parse walks that parse's in-flight tree, and the
 * same walk replayed after the parse publishes reproduces it. Steps
 * follow the live links, so edits between steps are visible; a step
 * whose position is no longer inside the walk's root (removed, or moved
 * elsewhere) throws an `invalid node` error.
 *
 * Single-pass: iteration resumes, never restarts — a second loop
 * continues where the first left off. Bound to the core's parse
 * generation of the tree it was created over: stepping after the session
 * parses again throws a `StaleTreeError` instead of reading stale storage,
 * and stepping after it closes throws a `SessionClosedError`.
 */
export class Walker implements IterableIterator<WalkStep> {
  #session: Session;
  #cursor: ArrayBuffer;
  /** The byte order native code reads and writes the cursor struct in. */
  #littleEndian: boolean;
  /** The session's intern gate, bound to this walker's parse generation. */
  #intern: (address: bigint) => Node;

  /**
   * Internal: the walk start `Session` installs behind `Node.walk` is the
   * only creation path, and the emitted types mark this constructor
   * `private`. The leading token stays module-private, so runtime
   * reflection reaches the same gate.
   */
  private constructor(
    token: symbol,
    session: Session,
    root: bigint,
    generation: number,
    skipSemanticErrors: boolean,
    skipRecovered: boolean,
    littleEndian: boolean,
    intern: (address: bigint) => Node,
  ) {
    if (token !== WALKER_CONSTRUCTION_TOKEN) {
      throw new TypeError("galley: Walker cannot be constructed directly");
    }
    this.#session = session;
    this.#littleEndian = littleEndian;
    this.#intern = intern;
    this.#cursor = new ArrayBuffer(WALK_CURSOR_BYTES);
    const view = new DataView(this.#cursor);
    setUint64FromNumber(view, WALK_OFFSET_GENERATION, generation, littleEndian);
    view.setBigUint64(WALK_OFFSET_ROOT, root, littleEndian);
    view.setBigUint64(WALK_OFFSET_CURRENT, 0n, littleEndian);
    view.setUint32(WALK_OFFSET_DEPTH, 0, littleEndian);
    view.setUint16(WALK_OFFSET_STATE, WALK_STATE_NOT_STARTED, littleEndian);
    view.setUint8(
      WALK_OFFSET_OPTIONS,
      (skipSemanticErrors ? WALK_OPTION_SKIP_SEMANTIC_ERRORS : 0) | (skipRecovered ? WALK_OPTION_SKIP_RECOVERED : 0),
    );
    view.setUint8(WALK_OFFSET_FLAG, 0);
  }

  /**
   * The in-class entry a `private` constructor leaves open, for this
   * module's walk start: any token but the module's own throws
   * exactly like a direct construction would.
   */
  static create(
    token: symbol,
    session: Session,
    root: bigint,
    generation: number,
    skipSemanticErrors: boolean,
    skipRecovered: boolean,
    littleEndian: boolean,
    intern: (address: bigint) => Node,
  ): Walker {
    return new Walker(token, session, root, generation, skipSemanticErrors, skipRecovered, littleEndian, intern);
  }

  /**
   * The one host gate before any touch: a closed session throws before a
   * step can reach native code. Staleness is the core's answer on the
   * step itself (`Status.ErrorStaleTree`), never on a host-side write.
   */
  #requireLive(): void {
    if (this.#session.isClosed) throw new SessionClosedError("session is closed");
  }

  next(): IteratorResult<WalkStep> {
    this.#requireLive();
    const step = this.#session.walkStep(this.#cursor);
    if (step === null) return { done: true, value: undefined };
    return {
      done: false,
      value: {
        node: this.#intern(step.node),
        depth: step.depth,
        isSemanticError: step.isSemanticError,
        isRecovered: step.isRecovered,
      },
    };
  }

  [Symbol.iterator](): IterableIterator<WalkStep> {
    return this;
  }

  /**
   * Prunes the children of the last yielded step; iteration continues with
   * its next sibling. No effect without a last step. A pure host-side
   * state write (state 1 → 2): staleness is the next step's answer, not
   * this one's.
   */
  skipChildren(): void {
    this.#requireLive();
    const view = new DataView(this.#cursor);
    if (view.getUint16(WALK_OFFSET_STATE, this.#littleEndian) === WALK_STATE_YIELDED) {
      view.setUint16(WALK_OFFSET_STATE, WALK_STATE_YIELDED_SKIP_CHILDREN, this.#littleEndian);
    }
  }
}
