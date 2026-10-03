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
import type { FfiPort, Handle, SessionCOptions, SnapshotColumns } from "./port.ts";
import { decodeUtf8 } from "./text.ts";
import { checkArtifactPath, checkMessageBytes, checkParseInput } from "./sources.ts";
import { rejectSessionOptions } from "./internal.ts";
import { Node, createNode, installWalkStart, nodeAddress } from "./node.ts";
import type { NodeDoor } from "./node.ts";
import { HookDoor, ProcedureArguments, ProcedureRegistry, registryFor, routerFor } from "./procedures.ts";
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
 * The published-generation cache value that means "ask the core again": a
 * refresh that failed (a parse started in between) leaves the cache
 * unknown instead of writing 0n, which would read as "nothing published".
 * No real generation is negative, so no handle ever matches it.
 */
const UNKNOWN_GENERATION = -1n;

function isInvalid(addr: bigint): boolean {
  return addr === INVALID_NODE;
}

/**
 * The session door as an address-level crossing: the galley_node_* family
 * over the session handle, which the core refuses while a parse runs.
 */
class SessionDoor implements NodeDoor {
  readonly isHook = false;
  readonly #port: FfiPort;
  readonly #handle: () => Handle;
  readonly #generation: () => bigint;
  readonly #check: (status: number) => void;

  constructor(port: FfiPort, handle: () => Handle, generation: () => bigint, check: (status: number) => void) {
    this.#port = port;
    this.#handle = handle;
    this.#generation = generation;
    this.#check = check;
  }

  get generation(): bigint {
    return this.#generation();
  }

  nodeValid(address: bigint): boolean {
    return this.#port.nodeValid(this.#handle(), address);
  }

  childCount(address: bigint): number {
    return this.#port.childCount(this.#handle(), address);
  }

  firstChild(address: bigint): bigint {
    return this.#port.firstChild(this.#handle(), address);
  }

  lastChild(address: bigint): bigint {
    return this.#port.lastChild(this.#handle(), address);
  }

  nextSibling(address: bigint): bigint {
    return this.#port.nextSibling(this.#handle(), address);
  }

  priorSibling(address: bigint): bigint {
    return this.#port.priorSibling(this.#handle(), address);
  }

  parent(address: bigint): bigint {
    return this.#port.parent(this.#handle(), address);
  }

  text(address: bigint): Uint8Array | null {
    return this.#port.nodeText(this.#handle(), address);
  }

  symbolNameBytes(address: bigint): Uint8Array | null {
    return this.#port.nodeSymbolName(this.#handle(), address);
  }

  span(address: bigint): [bigint, bigint] | null {
    return this.#port.nodeSpan(this.#handle(), address);
  }

  lineColumn(address: bigint): [number, number] | null {
    return this.#port.nodeLineColumn(this.#handle(), address);
  }

  variableIndex(address: bigint): number | null {
    const index = this.#port.nodeVariableIndex(this.#handle(), address);
    if (index === -1) return null;
    this.#check(index);
    return index;
  }

  walkNext(cursor: ArrayBuffer): number {
    return this.#port.walkNext(this.#handle(), cursor);
  }

  cleanChildren(address: bigint): bigint {
    const { status, head } = this.#port.treeCleanChildren(this.#handle(), address);
    this.#check(status);
    return head;
  }

  appendChildren(parent: bigint, chain: bigint): void {
    this.#check(this.#port.treeAppendChildren(this.#handle(), parent, chain));
  }

  insertBefore(target: bigint, chain: bigint): void {
    this.#check(this.#port.treeInsertBefore(this.#handle(), target, chain));
  }

  insertAfter(target: bigint, chain: bigint): void {
    this.#check(this.#port.treeInsertAfter(this.#handle(), target, chain));
  }

  removeSiblings(address: bigint, count: number): bigint {
    const { status, head } = this.#port.treeRemoveSiblings(this.#handle(), address, count);
    this.#check(status);
    return head;
  }

  removeSelf(address: bigint): bigint {
    const { status, head } = this.#port.treeRemoveSelf(this.#handle(), address);
    this.#check(status);
    return head;
  }

  insertChildrenAt(parent: bigint, index: number, chain: bigint): void {
    this.#check(this.#port.treeInsertChildrenAt(this.#handle(), parent, index, chain));
  }

  removeChildrenAt(parent: bigint, index: number, count: number): bigint {
    const { status, head } = this.#port.treeRemoveChildrenAt(this.#handle(), parent, index, count);
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
    installWalkStart((session, root, skipSemanticErrors) => {
      const door = session.#door(); // hook-aware; throws when closed
      const address = session.admit(root, door); // generation gate for that door
      // The walk is bound to the tree the node came from: stamp from the
      // node's own generation, which the gate above just proved live for
      // this door — no refresh of its own.
      const generation = root.generation;
      return Walker.create(
        WALKER_CONSTRUCTION_TOKEN,
        session,
        address,
        generation,
        skipSemanticErrors,
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
   * native door and the parse's core generation are constant for the parse)
   * and dropped by the parse's finish gate; null between parses.
   */
  #parseDoor: HookDoor | null = null;
  /**
   * True exactly while a hook runs. JavaScript runs one thread per session
   * and a parse is synchronous, so the only code that can run while a parse
   * of this session is in progress is a hook: a call made while this is set
   * is exactly a call inside a hook dispatch of the running parse.
   */
  #dispatching = false;
  /**
   * The core's generation of this session's published tree, as last read
   * from the core: after every parse the core did not refuse, on close, and
   * whenever a handle's generation disagrees with it; 0n when nothing is
   * published, `UNKNOWN_GENERATION` when a read failed and the next use must
   * ask again. Hosts never count generations, they cache what the core
   * reports.
   */
  #publishedGeneration = 0n;
  /**
   * The live generation's interned node handles, indexed by address (the
   * core's addresses are dense node indices), with the generation they
   * belong to; null when nothing is interned. One object per (session,
   * generation, address) while that generation is live, so `===` is the
   * sanctioned identity — "the same node of the same parse". Strong
   * rather than weak: the table retains exactly the live tree (~82
   * B/node) until the finish gate drops it or `close()` clears it, never
   * a superseded parse's nodes.
   */
  #internGeneration: bigint | null = null;
  #internedNodes: (Node | undefined)[] = [];
  /** The session door, crossed by every call outside a hook dispatch. */
  readonly #sessionDoor: NodeDoor;

  /**
   * Takes a bound port: factories resolve the backend first, so a
   * constructed session is always usable. There is no unready state.
   * The session's hooks start as a copy of the parser's defaults.
   */
  constructor(port: FfiPort, options: SessionOptions = {}) {
    if (!port) throw new TypeError("galley: Session needs a bound port");
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
    this.#sessionDoor = new SessionDoor(
      port,
      () => this.#requireHandle(),
      () => this.#publishedGeneration,
      (status) => this.#checkStatus(status),
    );

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
    this.#hookHandle = routerFor(port).register(this);
    try {
      this.#commitHooks(registryFor(port).copy());
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
   */
  #door(): NodeDoor {
    this.#requireHandle();
    return this.#dispatching && this.#parseDoor !== null ? this.#parseDoor : this.#sessionDoor;
  }

  /**
   * Publishes a fresh published-generation reading. Stamping alone never
   * touches the intern table: a newer generation takes it over lazily, at
   * the first node it creates, and the finish gate drops it outright when
   * the published generation differs from the table's (except UNKNOWN,
   * which names no generation and drops nothing).
   */
  #stampPublished(generation: bigint): void {
    this.#publishedGeneration = generation;
  }

  /**
   * Re-reads the published generation from the core into the cache. A
   * parse in flight makes the core refuse with `ErrorSessionInUse`, which
   * throws and leaves the cache as it was.
   */
  #refreshPublishedGeneration(): void {
    const { status, generation } = this.#port.publishedGeneration(this.#requireHandle());
    this.#checkStatus(status);
    this.#stampPublished(generation);
  }

  /**
   * Re-reads the published generation without throwing: a refusal (a
   * parse in flight) leaves the cache exactly as it was, which is still
   * the parse a snapshot's columns come from.
   */
  #refreshPublishedGenerationQuietly(): void {
    const { status, generation } = this.#port.publishedGeneration(this.#requireHandle());
    if (status >= 0) this.#stampPublished(generation);
  }

  /**
   * The single session-door generation gate: passes only the generation of
   * the tree the core published. A mismatch first asks the core again,
   * because the cache can lag it and a parse in flight must report
   * `ErrorSessionInUse` rather than a stale handle.
   * @internal
   */
  requireSessionGeneration(generation: bigint, what: string): void {
    if (generation !== 0n && generation === this.#publishedGeneration) return;
    this.#refreshPublishedGeneration();
    if (generation !== 0n && generation === this.#publishedGeneration) return;
    throw new SessionClosedError(`${what} is invalidated`);
  }

  /**
   * The single gate for a node argument crossing `door`: a `Node` must
   * belong to this session and carry the generation the door accepts,
   * because the crossing sends a bare address and native storage only
   * bounds-checks it, so a node of another session or generation would
   * alias whichever node holds that index here. A bare address never
   * reaches the crossing: {@link nodeAddress} refuses it at entry, because
   * it carries no session and no generation to vouch for it.
   *
   * @throws TypeError when `node` is not a `Node` or belongs to a
   *         different session.
   * @internal
   */
  admit(node: Node, door: NodeDoor): bigint {
    const address = nodeAddress(node);
    if (node.session.isClosed) throw new SessionClosedError("node's session is closed");
    if (node.session !== this) {
      throw new TypeError("node belongs to a different session than this operation");
    }
    if (door.isHook) {
      if (node.generation === 0n || node.generation !== door.generation) {
        throw new SessionClosedError("node is invalidated");
      }
    } else {
      this.requireSessionGeneration(node.generation, "node");
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
  #nodeForGeneration(generation: bigint, address: bigint): Node {
    // UNKNOWN names no parse at all: it never interns, so each read
    // answers a fresh, uninterned handle. There is no closed-session
    // branch: every post-close read throws SessionClosedError before
    // reaching this gate, and a close inside a hook aborts in the core.
    if (generation === UNKNOWN_GENERATION) {
      return createNode(this, address, generation);
    }
    if (generation !== this.#internGeneration) {
      const tableGeneration = this.#internGeneration;
      if (tableGeneration !== null) {
        // Only a newer generation takes the table over; an older one is
        // dead and never re-interned.
        if (generation < tableGeneration) return createNode(this, address, generation);
      } else if (
        // An empty table adopts only what is live now: the published
        // generation, or the running parse's own (its hooks build the
        // tree it may publish).
        generation !== this.#publishedGeneration &&
        (this.#parseDoor === null || generation !== this.#parseDoor.generation)
      ) {
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

  /**
   * Drops the intern table: its generation is dead (the published one
   * moved on or is gone) or the session closed, so the handles it
   * retained strongly must be released rather than carried.
   */
  #dropInternedNodes(): void {
    this.#internGeneration = null;
    this.#internedNodes = [];
  }

  /** Wraps an address read through `door`; invalid becomes null. */
  #wrap(door: NodeDoor, address: bigint): Node | null {
    return isInvalid(address) ? null : this.#nodeForGeneration(door.generation, address);
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
   * Runs hook `index` of the running parse, on the parsing thread. Hook
   * exceptions are logged and swallowed so a throwing hook never aborts
   * the parse.
   * @internal
   */
  dispatchHook(index: number, args: Handle): void {
    const fn = this.#hooksByIndex[index];
    if (!fn) return;
    const name = routerFor(this.#port).names[index];
    // The parse's native door and core generation are constant for the
    // parse: read them on its first dispatch, drop them in the finish gate.
    // Only the "a hook is running" flag is set per dispatch, which is what
    // lets a call choose its door when it is made.
    if (this.#parseDoor === null) {
      const door = this.#port.procDoor(args);
      const generation = this.#port.hookGeneration(door);
      this.#parseDoor = new HookDoor(door, generation, this.#port, (address) =>
        this.#nodeForGeneration(generation, address),
      );
    }
    this.#dispatching = true;
    if (fn.length === 0) {
      try {
        (fn as () => void)();
      } catch (err) {
        console.error(`galley procedure ${name} threw:`, err);
      } finally {
        this.#dispatching = false;
      }
      return;
    }
    const procedureArguments = new ProcedureArguments(args, this.#parseDoor, this, this.#port);
    try {
      fn(procedureArguments);
    } catch (err) {
      console.error(`galley procedure ${name} threw:`, err);
    } finally {
      procedureArguments.expire();
      this.#dispatching = false;
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
      routerFor(this.#port).unregister(this.#hookHandle);
    }
    this.#closed = true;
    // No door outlives the session: dispatch chooses the session door from
    // here on, and the empty table can never adopt a lingering parse
    // door's generation.
    this.#parseDoor = null;
    this.#stampPublished(0n);
    // Nothing is live on a closed session: the table must not retain the
    // handles it holds strongly, or the session would keep its whole tree
    // reachable after close.
    this.#dropInternedNodes();
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
   * parse's door and reads the core's published generation, so handles of
   * earlier parses fail instead of reading reallocated storage (a failed
   * parse publishes nothing: 0n; a failed read leaves the cache unknown).
   * The intern table is dropped here when the published generation differs
   * from the table's — never on a failed read (UNKNOWN differs from
   * everything but names nothing) — for that parse's nodes are dead weight
   * now, and the next node created re-adopts whatever generation is live. A parse the
   * core refused with `ErrorSessionInUse` changed nothing, so it reads
   * nothing and leaves every handle, the running parse's door, and its
   * intern table alone. Parsing itself never throws merely because a
   * walker is open. The hooks were fixed by the last commit, so nothing
   * is synchronized here.
   */
  #finishParse(nativeParse: () => number): number {
    let status: number;
    try {
      status = nativeParse();
    } catch (error) {
      this.#parseDoor = null;
      throw error;
    }
    if (status !== Status.ErrorSessionInUse) {
      // The parse is over: its door dies with it. A refused parse started
      // nothing, so it leaves the running parse's door alone.
      this.#parseDoor = null;
      const published = this.#port.publishedGeneration(this.#requireHandle());
      this.#stampPublished(published.status < 0 ? UNKNOWN_GENERATION : published.generation);
      if (
        this.#internGeneration !== null &&
        // A failed read names no generation: UNKNOWN differs from every
        // table's, and dropping on that difference would discard a table
        // that may still be the live one.
        this.#publishedGeneration !== UNKNOWN_GENERATION &&
        this.#internGeneration !== this.#publishedGeneration
      ) {
        this.#dropInternedNodes();
      }
    }
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
    // Stamp from a fresh read of the core, never the cache: a refusal (a
    // parse is in flight) answers like the native refusal does.
    const fresh = this.port.publishedGeneration(h);
    if (fresh.status < 0) return null;
    const address = this.port.rootNode(h);
    if (isInvalid(address)) return null;
    this.#stampPublished(fresh.generation);
    return this.#nodeForGeneration(fresh.generation, address);
  }

  nodeValid(node: Node): boolean {
    const door = this.#door();
    return door.nodeValid(this.admit(node, door));
  }

  childCount(node: Node): number {
    const door = this.#door();
    return door.childCount(this.admit(node, door));
  }

  /**
   * The one children iteration: count-bounded, first to last, every step
   * crossing the same door, and a mismatch between the count and the
   * chain still fails loudly.
   */
  children(node: Node): Node[] {
    const door = this.#door();
    const address = this.admit(node, door);
    const count = door.childCount(address);
    const out: Node[] = [];
    let child = door.firstChild(address);
    for (let i = 0; i < count; i++) {
      const wrapped = this.#wrap(door, child);
      if (wrapped === null) throw new Error("child count changed during iteration");
      out.push(wrapped);
      child = door.nextSibling(child);
    }
    return out;
  }

  firstChild(node: Node): Node | null {
    const door = this.#door();
    return this.#wrap(door, door.firstChild(this.admit(node, door)));
  }

  lastChild(node: Node): Node | null {
    const door = this.#door();
    return this.#wrap(door, door.lastChild(this.admit(node, door)));
  }

  nextSibling(node: Node): Node | null {
    const door = this.#door();
    return this.#wrap(door, door.nextSibling(this.admit(node, door)));
  }

  priorSibling(node: Node): Node | null {
    const door = this.#door();
    return this.#wrap(door, door.priorSibling(this.admit(node, door)));
  }

  parent(node: Node): Node | null {
    const door = this.#door();
    return this.#wrap(door, door.parent(this.admit(node, door)));
  }

  /**
   * Flat bulk read of the most recent successful parse in a single FFI
   * crossing: one array slot per node address, plus `node(address)` — the
   * one conversion from a stored address back to a node of the parse the
   * columns describe. Walk `parent`/`firstChild`/`next` directly instead
   * of one call per node.
   */
  snapshot(): TreeSnapshot {
    const handle = this.#requireHandle();
    // Stamp from the published-generation cache: the columns describe the
    // published tree, so node() must return nodes of exactly that parse. A
    // refusal (a parse is in flight) leaves the cache as it was, which is
    // still the parse the columns come from.
    this.#refreshPublishedGenerationQuietly();
    const generation = this.#publishedGeneration;
    const columns = this.port.treeSnapshot(handle);
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
   * contract: null at the end of the walk, a `SessionClosedError` when
   * the walker's generation is not the tree's anymore, the session's own
   * error for everything else.
   * @internal
   */
  walkStep(cursor: ArrayBuffer): { node: bigint; depth: number; isSemanticError: boolean } | null {
    const status = this.#door().walkNext(cursor);
    if (status === Status.ErrorStaleTree) throw new SessionClosedError("walker is invalidated");
    this.#checkStatus(status);
    if (status === 0) return null;
    const view = new DataView(cursor);
    const littleEndian = this.#port.walkCursorLittleEndian;
    return {
      node: view.getBigUint64(WALK_OFFSET_CURRENT, littleEndian),
      depth: view.getUint32(WALK_OFFSET_DEPTH, littleEndian),
      isSemanticError: view.getUint8(WALK_OFFSET_FLAG) !== 0,
    };
  }

  symbolNameBytes(node: Node): Uint8Array | null {
    const door = this.#door();
    return door.symbolNameBytes(this.admit(node, door));
  }

  symbolName(node: Node): string | null {
    const bytes = this.symbolNameBytes(node);
    if (bytes === null) return null;
    return decodeUtf8(bytes);
  }

  text(node: Node): Uint8Array | null {
    const door = this.#door();
    return door.text(this.admit(node, door));
  }

  span(node: Node): [bigint, bigint] | null {
    const door = this.#door();
    return door.span(this.admit(node, door));
  }

  lineColumn(node: Node): [number, number] | null {
    const door = this.#door();
    return door.lineColumn(this.admit(node, door));
  }

  variableIndex(node: Node): number | null {
    const door = this.#door();
    return door.variableIndex(this.admit(node, door));
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

  appendChildren(parent: Node, chain: Node): void {
    const door = this.#door();
    door.appendChildren(this.admit(parent, door), this.admit(chain, door));
  }

  insertBefore(target: Node, chain: Node): void {
    const door = this.#door();
    door.insertBefore(this.admit(target, door), this.admit(chain, door));
  }

  insertAfter(target: Node, chain: Node): void {
    const door = this.#door();
    door.insertAfter(this.admit(target, door), this.admit(chain, door));
  }

  removeSiblings(node: Node, count: number): Node | null {
    const door = this.#door();
    return this.#wrap(door, door.removeSiblings(this.admit(node, door), count));
  }

  removeSelf(node: Node): Node | null {
    const door = this.#door();
    return this.#wrap(door, door.removeSelf(this.admit(node, door)));
  }

  cleanChildren(node: Node): Node | null {
    const door = this.#door();
    return this.#wrap(door, door.cleanChildren(this.admit(node, door)));
  }

  insertChildrenAt(parent: Node, index: number, chain: Node): void {
    const door = this.#door();
    door.insertChildrenAt(this.admit(parent, door), index, this.admit(chain, door));
  }

  removeChildrenAt(parent: Node, index: number, count: number): Node | null {
    const door = this.#door();
    return this.#wrap(door, door.removeChildrenAt(this.admit(parent, door), index, count));
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

// The host-owned walk cursor, byte-for-byte `GalleyWalkCursor` from
// galley.h: generation u64 @0, root u64 @8, current u64 @16, depth u32
// @24, state u16 @28, options u8 @30, is_semantic_error u8 @31,
// structure_version u64 @32 — 40 bytes in the port's byte order (the
// last field is stamped by the core and never read host-side, so the
// zeroed ArrayBuffer supplies it).
const WALK_CURSOR_BYTES = 40;
const WALK_OFFSET_GENERATION = 0;
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
 * parses again or closes throws a `SessionClosedError` instead of
 * reading stale storage.
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
    generation: bigint,
    skipSemanticErrors: boolean,
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
    view.setBigUint64(WALK_OFFSET_GENERATION, generation, littleEndian);
    view.setBigUint64(WALK_OFFSET_ROOT, root, littleEndian);
    view.setBigUint64(WALK_OFFSET_CURRENT, 0n, littleEndian);
    view.setUint32(WALK_OFFSET_DEPTH, 0, littleEndian);
    view.setUint16(WALK_OFFSET_STATE, WALK_STATE_NOT_STARTED, littleEndian);
    view.setUint8(WALK_OFFSET_OPTIONS, skipSemanticErrors ? WALK_OPTION_SKIP_SEMANTIC_ERRORS : 0);
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
    generation: bigint,
    skipSemanticErrors: boolean,
    littleEndian: boolean,
    intern: (address: bigint) => Node,
  ): Walker {
    return new Walker(token, session, root, generation, skipSemanticErrors, littleEndian, intern);
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
