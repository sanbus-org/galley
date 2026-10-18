/**
 * Parsing session bound to this library's parser over `bindings/c/galley.h`.
 *
 * Runtime-neutral: all native calls go through the injected {@link FfiPort}.
 * Factories (`galley` on the universal entry, `openSession` on generated
 * package entries) resolve the backend first and hand a bound port to
 * this constructor.
 */

import { INVALID_NODE, NO_VARIABLE, Status, statusCarriesDiagnostic } from "./constants.ts";
import type { Kind, RecoveryTarget, Resume } from "./constants.ts";
import type { Diagnostic } from "./diagnostic.ts";
import { GalleyError, SessionClosedError, StaleTreeError } from "./errors.ts";
import type {
  CurrentDiagnosticFamily,
  FfiPort,
  Handle,
  HookTicket,
  NodeFamily,
  SessionCOptions,
  SnapshotColumns,
  StagedHandle,
} from "./port.ts";
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
 * The field reads of one diagnostic source — the session door's current
 * diagnostic, the hook door's twin, or one recorded diagnostic — as a set
 * of refusal-or-value crossings. Each member answers its value, with the
 * conditional fields answering the field's absence; a refusal raises
 * there, so it can never reach the snapshot as an empty field.
 * {@link Session} builds one set per source, and `#buildDiagnostic` is the
 * one snapshot builder over any of them.
 */
interface DiagnosticReads {
  hasDiagnostic(): boolean;
  kind(): number;
  position(): [number, number, number];
  message(): string;
  messageAnsi(): string;
  unexpectedToken(): Uint8Array | null;
  expectedCount(): number;
  expectedAt(index: number): Uint8Array;
  contextCount(): number;
  contextAt(index: number): Uint8Array;
  syntaxErrorCount(): number;
  semanticErrorCount(): number;
  semantic(): [string, string] | null;
  indentation(): [number, number] | null;
  recoveryKind(): number;
  recoveryTerminal(): Uint8Array | null;
  recoveryResume(): number | null;
  recoveryLhsVariable(): string | null;
  recoveryProduction(): [string, number] | null;
  recoveryOccurrence(): [string, number, number, string] | null;
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

let stagedHandleFor: (staged: StagedInput, port: FfiPort, what: string) => StagedHandle;
const STAGED_CONSTRUCTION_TOKEN = Symbol("StagedInput");

/**
 * Input copied once into the form the engine reads, parsed any number of
 * times with `session.parse(staged)` without paying the transfer again
 * (for WebAssembly, the copy into the guest's memory). It holds its own
 * copy of the bytes, parses in any session of the engine that staged it,
 * and is freed by `close()` or `using`.
 */
export class StagedInput {
  static {
    // The one way to reach the staged handle: `Session.parse` asks for it
    // by port, so an input never reaches an engine that did not stage it.
    stagedHandleFor = (staged, port, what) => {
      if (staged.#port !== port) {
        throw new TypeError(`${what} received input staged by another parser`);
      }
      if (staged.#handle === null) throw new SessionClosedError("staged input is closed");
      return staged.#handle;
    };
  }

  #port: FfiPort;
  #handle: StagedHandle | null;
  readonly byteLength: number;

  /** @internal Made by `Session.stage`. */
  constructor(token: symbol, port: FfiPort, bytes: Uint8Array) {
    if (token !== STAGED_CONSTRUCTION_TOKEN) {
      throw new TypeError("StagedInput is made by session.stage()");
    }
    this.#port = port;
    this.#handle = port.stageInput(bytes);
    this.byteLength = bytes.length;
  }

  close(): void {
    if (this.#handle === null) return;
    const handle = this.#handle;
    this.#handle = null;
    this.#port.releaseInput(handle);
  }

  [Symbol.dispose](): void {
    this.close();
  }
}

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
  /** This session's hooks by name: replaced whole by every change, never mutated.
   * Assigned from the parser defaults (a copy carrying the artifact's hook
   * names) before the constructor returns anything observable. */
  #hooks!: ProcedureRegistry;
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
   * The same parse's raw native door, the handle the hook-door diagnostic
   * family (`galley_hook_diagnostic_*`) reads through; set and dropped
   * together with {@link #parseDoor}.
   */
  #parseDoorHandle: Handle | null = null;
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

    const { status, handle } = port.createSession(cOptions);
    if (status < 0) throw this.errorFromStatus(status);
    if (handle === null || handle === undefined) {
      // A success without a handle is a broken backend, not OOM.
      throw new GalleyError("galley: session create reported success without a handle", Status.ErrorInternal, null);
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
    // Boundary trust: `status` is the port's raw status, already known negative.
    return new GalleyError(fallback ?? this.#statusMessage(status), status as Status, null, options);
  }

  /**
   * The failure of a parse, with that parse's diagnostic snapshot: exactly
   * the statuses that ended a parse that ran (`statusCarriesDiagnostic`)
   * carry one; a failure built from any other status carries none. While
   * attaching the snapshot the one skippable status is `session in use`
   * (another thread's parse can hold the session between this parse's
   * failure and the read): the failure then carries no snapshot; every
   * other refusal raises.
   */
  #parseFailure(status: number, options?: ErrorOptions): GalleyError {
    if (!statusCarriesDiagnostic(status)) return this.errorFromStatus(status, undefined, options);
    let diag: Diagnostic | null = null;
    if (this.#handle !== null) {
      try {
        const reads = this.#currentReads(this.#port.diagnostics, this.#handle);
        if (reads.hasDiagnostic()) diag = this.#buildDiagnostic(reads);
      } catch (error) {
        if (!(error instanceof GalleyError && error.code === Status.ErrorSessionInUse)) throw error;
      }
    }
    // Boundary trust: `status` is the port's raw status, already known negative.
    return new GalleyError(diag?.message ?? this.#statusMessage(status), status as Status, diag, options);
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
   * Scans `module` for exported procedure hooks the artifact defines
   * (shape: `reduction...`, `hook_...`, `hookX...`) and registers each on
   * this session in one step. Returns the number installed.
   */
  installProcedures(module: Record<string, unknown>): number {
    const next = this.#hooks.copy();
    const installed = next.installModule(module);
    if (installed > 0) this.#commitHooks(next);
    return installed;
  }

  /** Removes all of this session's hooks; the artifact's list stays with it. */
  clearProcedures(): void {
    const next = this.#hooks.copy();
    next.clear();
    this.#commitHooks(next);
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
      this.#parseDoorHandle = nativeDoor;
    }
    this.#dispatching = true;
    // Always pass the object: this language ignores a surplus argument,
    // and there is no arity to inspect (the fn.length heuristic missed
    // defaults and rest parameters alike).
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
   *
   * While a parse is in flight (a hook of it calling this, or another
   * thread's parse through a shared handle) the core refuses, so this
   * throws `session in use` and changes nothing: the handle, the router
   * registration, `#closed` and the intern table stay as they were and the
   * session keeps working.
   */
  close(): void {
    if (this.#closed) return;
    if (this.#handle !== null) {
      const status = this.#port.destroySession(this.#handle);
      if (status < 0) throw this.errorFromStatus(status);
      this.#handle = null;
      routerFor(this.#port).unregister(this.#hookHandle);
    }
    this.#closed = true;
    // No door outlives the session: dispatch chooses the session door from
    // here on, and the empty table can never adopt a lingering parse
    // door's generation.
    this.#parseDoor = null;
    this.#parseDoorHandle = null;
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

  parse(input: string | ArrayBufferView | ArrayBuffer | SharedArrayBuffer | StagedInput): number {
    const handle = this.#requireHandle();
    const port = this.#requirePort();
    if (input instanceof StagedInput) {
      const staged = stagedHandleFor(input, port, "galley: session.parse");
      return this.#finishParse(() => port.parseStaged(handle, staged));
    }
    const buf = checkParseInput(input, "galley: session.parse");
    return this.#finishParse(() => port.parse(handle, buf));
  }

  /**
   * Copies `input` once for repeated `parse` calls, so each of them skips
   * the transfer into the engine. Later changes to `input` do not reach the
   * copy. The caller closes it.
   */
  stage(input: string | ArrayBufferView | ArrayBuffer | SharedArrayBuffer): StagedInput {
    this.#requireHandle();
    const port = this.#requirePort();
    const buf = checkParseInput(input, "galley: session.stage");
    return new StagedInput(STAGED_CONSTRUCTION_TOKEN, port, buf);
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
      this.#parseDoorHandle = null;
      this.#hookFailure = null;
      throw error;
    }
    let hookFailure: { thrown: unknown } | null = null;
    if (status !== Status.ErrorSessionInUse) {
      // The parse is over: its door dies with it, and so does the exception
      // a hook of it raised once its failure carries it. A refused parse
      // started nothing, so it leaves the running parse's state alone.
      this.#parseDoor = null;
      this.#parseDoorHandle = null;
      hookFailure = this.#hookFailure;
      this.#hookFailure = null;
    }
    if (status < 0) {
      const cause = status === Status.ErrorHookFailed && hookFailure !== null
        ? { cause: hookFailure.thrown }
        : undefined;
      throw this.#parseFailure(status, cause);
    }
    return status;
  }

  // -- arena -----------------------------------------------------------

  /**
   * Node count of the published tree — 0 for a parser built without AST
   * construction, where a live tree has no nodes. Nothing published is the
   * core's stale-tree refusal (generation 0 is never live).
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
   * A live tree of a parser built without AST construction has no nodes:
   * its snapshot is empty (`count` 0). Every leg carries one generation, so
   * a parse that runs in between throws instead of returning columns that
   * mix two trees.
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
   * contract: null when the step left `INVALID_NODE` in the cursor's
   * `current` — the walk is done, and every further step keeps answering
   * it — and the session's own error (a `StaleTreeError` when the walker's
   * generation is not the tree's anymore) for a refusal. Every step that
   * runs is `Ok`.
   * @internal
   */
  walkStep(
    cursor: ArrayBuffer,
  ): { node: bigint; depth: number; isSemanticError: boolean; isRecovered: boolean } | null {
    const status = this.#door().walkNext(cursor);
    this.#checkStatus(status);
    const view = new DataView(cursor);
    const littleEndian = this.#port.walkCursorLittleEndian;
    if (view.getBigUint64(WALK_OFFSET_CURRENT, littleEndian) === INVALID_NODE) return null;
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

  /**
   * Whether the calling context has a diagnostic at all: the in-flight
   * parse's inside a hook (through the hook door), the previous parse's
   * elsewhere (through the session door). A refusal raises, never false.
   */
  hasDiagnostic(): boolean {
    return this.#diagnosticReads().hasDiagnostic();
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

  /**
   * The one read-or-raise path: a negative status becomes the host's
   * failure of that kind, anything else is the value. Every diagnostic
   * read crosses here, so no refusal ever becomes a value the snapshot
   * would spell empty.
   */
  #read<T>(value: T): Exclude<T, number> {
    if (typeof value === "number" && value < 0) throw this.errorFromStatus(value);
    return value as Exclude<T, number>;
  }

  /** {@link #read} for a value that is a bare number (a kind, a count, a resume side). */
  #readNumber(value: number): number {
    if (value < 0) throw this.errorFromStatus(value);
    return value;
  }

  /**
   * A conditional field: the value, or null for `galley_error_no_diagnostic`
   * (no diagnostic, or one of another kind — the field's absence). Every
   * other negative status raises like {@link #read}.
   */
  #field<T>(value: T): Exclude<T, number> | null {
    if (typeof value === "number") {
      if (value === Status.ErrorNoDiagnostic) return null;
      if (value < 0) throw this.errorFromStatus(value);
    }
    return value as Exclude<T, number>;
  }

  /**
   * A conditional list count: zero for `galley_error_no_diagnostic` (the
   * diagnostic carries no such list); every other negative status raises.
   */
  #countField(value: number): number {
    if (value === Status.ErrorNoDiagnostic) return 0;
    return this.#readNumber(value);
  }

  /** A conditional numeric field: null for `galley_error_no_diagnostic`. */
  #optionalNumber(value: number): number | null {
    if (value === Status.ErrorNoDiagnostic) return null;
    return this.#readNumber(value);
  }

  /** The reads of one door's current-diagnostic family over `handle`. */
  #currentReads(family: CurrentDiagnosticFamily, handle: Handle): DiagnosticReads {
    return {
      hasDiagnostic: () => this.#read(family.hasDiagnostic(handle)),
      kind: () => this.#readNumber(family.diagnosticKind(handle)),
      position: () => this.#read(family.diagnosticPosition(handle)),
      message: () => this.#read(family.diagnosticMessage(handle)),
      messageAnsi: () => this.#read(family.diagnosticMessageAnsi(handle)),
      unexpectedToken: () => this.#field(family.diagnosticUnexpectedToken(handle)),
      expectedCount: () => this.#countField(family.diagnosticExpectedCount(handle)),
      expectedAt: (index) => this.#read(family.diagnosticExpectedAt(handle, index)),
      contextCount: () => this.#countField(family.diagnosticContextCount(handle)),
      contextAt: (index) => this.#read(family.diagnosticContextAt(handle, index)),
      syntaxErrorCount: () => this.#readNumber(family.syntaxErrorCount(handle)),
      semanticErrorCount: () => this.#readNumber(family.semanticErrorCount(handle)),
      semantic: () => this.#field(family.diagnosticSemantic(handle)),
      indentation: () => this.#field(family.diagnosticIndentation(handle)),
      recoveryKind: () => this.#readNumber(family.diagnosticRecoveryKind(handle)),
      recoveryTerminal: () => this.#field(family.diagnosticRecoveryTerminal(handle)),
      recoveryResume: () => this.#optionalNumber(family.diagnosticRecoveryResume(handle)),
      recoveryLhsVariable: () => this.#field(family.diagnosticRecoveryLhsVariable(handle)),
      recoveryProduction: () => this.#field(family.diagnosticRecoveryProduction(handle)),
      recoveryOccurrence: () => this.#field(family.diagnosticRecoveryOccurrence(handle)),
    };
  }

  /** The reads of the recorded diagnostic at `index`. */
  #recordedReads(handle: Handle, index: number): DiagnosticReads {
    const port = this.#port;
    return {
      // Built only for an index below the recorded count.
      hasDiagnostic: () => true,
      kind: () => this.#readNumber(port.recordedDiagnosticKind(handle, index)),
      position: () => this.#read(port.recordedDiagnosticPosition(handle, index)),
      message: () => this.#read(port.recordedDiagnosticMessage(handle, index)),
      messageAnsi: () => this.#read(port.recordedDiagnosticMessageAnsi(handle, index)),
      unexpectedToken: () => this.#field(port.recordedUnexpectedToken(handle, index)),
      expectedCount: () => this.#countField(port.recordedExpectedCount(handle, index)),
      expectedAt: (tokenIndex) => this.#read(port.recordedExpectedToken(handle, index, tokenIndex)),
      contextCount: () => this.#countField(port.recordedContextCount(handle, index)),
      contextAt: (contextIndex) => this.#read(port.recordedContextName(handle, index, contextIndex)),
      // The recorded family has no count export: totals are the most
      // recent parse's, the session door's reads the current snapshot uses.
      syntaxErrorCount: () => this.#readNumber(port.diagnostics.syntaxErrorCount(handle)),
      semanticErrorCount: () => this.#readNumber(port.diagnostics.semanticErrorCount(handle)),
      semantic: () => this.#field(port.recordedSemantic(handle, index)),
      indentation: () => this.#field(port.recordedIndentation(handle, index)),
      recoveryKind: () => this.#readNumber(port.recordedRecoveryKind(handle, index)),
      recoveryTerminal: () => this.#field(port.recordedRecoveryTerminal(handle, index)),
      recoveryResume: () => this.#optionalNumber(port.recordedRecoveryResume(handle, index)),
      recoveryLhsVariable: () => this.#field(port.recordedRecoveryLhsVariable(handle, index)),
      recoveryProduction: () => this.#field(port.recordedRecoveryProduction(handle, index)),
      recoveryOccurrence: () => this.#field(port.recordedRecoveryOccurrence(handle, index)),
    };
  }

  /**
   * The diagnostic reads for the calling context, chosen now: inside a
   * hook dispatch of this session's running parse, the hook door's
   * current-diagnostic family over its native door; everywhere else the
   * session door's, which the core refuses while a parse runs.
   */
  #diagnosticReads(): DiagnosticReads {
    if (this.#dispatching && this.#parseDoorHandle !== null) {
      return this.#currentReads(this.port.hookDiagnostics, this.#parseDoorHandle);
    }
    return this.#currentReads(this.port.diagnostics, this.#requireHandle());
  }

  /**
   * The one diagnostic snapshot builder, shared by every source (the
   * session door's current diagnostic, the hook door's twin, a recorded
   * one): each read is a refusal-or-value crossing, so a refused member
   * raises instead of leaving an empty field.
   */
  #buildDiagnostic(reads: DiagnosticReads): Diagnostic {
    const kind = reads.kind() as Kind;
    const [offset, line, col] = reads.position();

    const expectedTokens: Uint8Array[] = [];
    const expCount = reads.expectedCount();
    for (let i = 0; i < expCount; i++) expectedTokens.push(reads.expectedAt(i));

    const context: string[] = [];
    const ctxCount = reads.contextCount();
    for (let i = 0; i < ctxCount; i++) context.push(decodeUtf8(reads.contextAt(i)));

    const recoveryKind = reads.recoveryKind();

    return {
      kind,
      offset,
      line,
      column: col,
      message: reads.message(),
      messageAnsi: reads.messageAnsi(),
      unexpectedToken: reads.unexpectedToken(),
      expectedTokens,
      context,
      syntaxErrorCount: reads.syntaxErrorCount(),
      semanticErrorCount: reads.semanticErrorCount(),
      semantic: reads.semantic(),
      indentation: reads.indentation(),
      recoveryKind: recoveryKind === 0 ? null : (recoveryKind as RecoveryTarget),
      recoveryTerminal: reads.recoveryTerminal(),
      recoveryResume: reads.recoveryResume() as Resume | null,
      recoveryLhsVariable: reads.recoveryLhsVariable(),
      recoveryProduction: reads.recoveryProduction(),
      recoveryOccurrence: reads.recoveryOccurrence(),
    };
  }

  /**
   * The previous parse's current diagnostic, or null when it produced
   * none. Inside a hook it answers the in-flight parse's diagnostic
   * through the hook door; a refusal raises, never null.
   */
  diagnostic(): Diagnostic | null {
    const reads = this.#diagnosticReads();
    if (!reads.hasDiagnostic()) return null;
    return this.#buildDiagnostic(reads);
  }

  /**
   * The diagnostics the most recent parse recorded, in recording order
   * (post-parse only: inside a hook the recorded family is refused with
   * `session in use`). An empty list means the parse recorded none.
   */
  diagnostics(): Diagnostic[] {
    const h = this.#requireHandle();
    const count = this.#readNumber(this.port.recordedDiagnosticCount(h));
    const out: Diagnostic[] = [];
    for (let i = 0; i < count; i++) out.push(this.#buildDiagnostic(this.#recordedReads(h, i)));
    return out;
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

  /**
   * The symbol name at `index`. A read at or past `symbolCount()` is the
   * core's `out of range` refusal, raised, never null.
   */
  symbolNameAt(index: number): Uint8Array {
    const h = this.#requireHandle();
    return this.#read(this.port.symbolNameAt(h, index));
  }

  /**
   * The terminal flag of the symbol at `index`. A read at or past
   * `symbolCount()` is the core's `out of range` refusal, raised.
   */
  symbolIsTerminal(index: number): boolean {
    const h = this.#requireHandle();
    return this.#read(this.port.symbolIsTerminal(h, index));
  }

  /**
   * The variable name at `index`. A read at or past `variableCount()` is
   * the core's `out of range` refusal, raised, never null.
   */
  variableNameAt(index: number): Uint8Array {
    const h = this.#requireHandle();
    return this.#read(this.port.variableNameAt(h, index));
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
