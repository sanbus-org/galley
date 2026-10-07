import type { Session, Walker } from "./session.ts";
import type { Status } from "./constants.ts";
import { decodeUtf8 } from "./text.ts";

/**
 * A door over node storage, as the address-level crossing a `Session` call
 * makes: the session door (`galley_node_*`, refused by the core while a
 * parse runs) or the hook door of the running parse (`galley_hook_*` over
 * its native door). The two differ only in the handle they are opened on:
 * one implementation serves both, and the core checks the generation inside
 * every call on either. The session picks the door per call; a `Node`
 * stores neither.
 * @internal
 */
export interface NodeDoor {
  /*
   * Every crossing takes the generation of the tree its node belongs to,
   * right before the address. A refusal throws; nothing answers null.
   */
  /** Direct child count; a refusal throws. */
  childCount(generation: number, address: bigint): number;
  /** One link, or {@link INVALID_NODE} when it does not exist. */
  firstChild(generation: number, address: bigint): bigint;
  lastChild(generation: number, address: bigint): bigint;
  nextSibling(generation: number, address: bigint): bigint;
  priorSibling(generation: number, address: bigint): bigint;
  parent(generation: number, address: bigint): bigint;
  text(generation: number, address: bigint): Uint8Array;
  symbolNameBytes(generation: number, address: bigint): Uint8Array;
  span(generation: number, address: bigint): [bigint, bigint];
  lineColumn(generation: number, address: bigint): [number, number];
  /** The raw variable index, or null when the node has no variable. */
  variableIndex(generation: number, address: bigint): number | null;
  /**
   * One step of a walk over the host-owned 40-byte cursor, which carries
   * its own generation: 1 yields a node, 0 ends the walk (and keeps ending
   * it while its tree is live), negative is a failure (stale tree, session
   * in use, malformed cursor bytes).
   */
  walkNext(cursor: ArrayBuffer): number;
  /** Head of the detached chain; `INVALID_NODE` when there were no children. */
  cleanChildren(generation: number, address: bigint): bigint;
  /*
   * The edits with a second node pass its own generation beside the first:
   * the core refuses a pair from two parses.
   */
  appendChildren(generation: number, parent: bigint, chainGeneration: number, chain: bigint): void;
  insertBefore(generation: number, target: bigint, chainGeneration: number, chain: bigint): void;
  insertAfter(generation: number, target: bigint, chainGeneration: number, chain: bigint): void;
  /** Head of the detached chain; `INVALID_NODE` when empty. */
  removeSiblings(generation: number, address: bigint, count: number): bigint;
  removeSelf(generation: number, address: bigint): bigint;
  insertChildrenAt(generation: number, parent: bigint, index: number, chainGeneration: number, chain: bigint): void;
  removeChildrenAt(generation: number, parent: bigint, index: number, count: number): bigint;
}

/**
 * The module-private credential the {@link Node} constructor demands.
 * Never exported — no package entry point can hand it out — so the
 * emitted types mark the constructor `private` and every runtime
 * construction that reaches it without the token throws: node creation
 * lives in the session's intern table, through {@link createNode}.
 */
const NODE_CONSTRUCTION_TOKEN: symbol = Symbol("galley.Node.construction");

/**
 * Handle for a node in the non-relocating AST storage: its owning
 * `Session`, the core's parse generation it belongs to, and its address.
 * Every accessor is one delegation to the session, which chooses the door
 * when the call is made (the parse's hook door from inside a hook of its
 * running parse, the post-parse door everywhere else) and gates it: a
 * closed session throws `SessionClosedError`, and a generation that is gone
 * throws `StaleTreeError` — the core owns that check on both doors, so
 * this handle carries the generation every read hands back and the session
 * keeps no cached copy of it. Nodes handed out by the hooks of a
 * parse that publishes its tree stay valid until the session parses again;
 * nodes of a failed parse are gone.
 *
 * There is no validity probe: whether this handle is usable is answered by
 * a real read, which throws.
 *
 * The session interns one object per (generation, address) while that
 * generation is the newest it has seen, so identity (`===`) answers "the
 * same node of the same parse" everywhere a node is reached; an older
 * generation is dead and answers with a fresh, uninterned handle each call.
 * The address is display-only: no public method accepts a bare
 * address where a `Node` is expected — {@link nodeAddress} refuses one.
 */
export class Node {
  readonly #session: Session;
  readonly #address: bigint;
  /**
   * The core's parse generation, stamped at construction. The constructor
   * is the single creation gate: every node carries the generation it
   * belongs to, so no accessor can read storage from another parse.
   */
  readonly #generation: number;

  /**
   * Internal: the session's intern table ({@link createNode}) is the
   * creation gate, and the emitted types mark this constructor `private`,
   * so no package entry point can even compile a `new Node`. The leading
   * token stays module-private, so runtime reflection reaches the same
   * gate — a raw address carries no generation of its own, and without
   * the token the caller would be vouching for one that nothing verifies.
   */
  private constructor(token: symbol, session: Session, address: bigint, generation: number) {
    if (token !== NODE_CONSTRUCTION_TOKEN) {
      throw new TypeError("galley: Node cannot be constructed directly");
    }
    this.#session = session;
    this.#address = address;
    this.#generation = generation;
  }

  /**
   * The in-class entry a `private` constructor leaves open, for this
   * module's {@link createNode}: it forwards the token it demands, and
   * any other token throws exactly like a direct construction would.
   */
  static create(token: symbol, session: Session, address: bigint, generation: number): Node {
    return new Node(token, session, address, generation);
  }

  /**
   * Raw address (stable index in the session's node storage), for
   * display only: it never converts back into something a call accepts.
   */
  get address(): bigint {
    return this.#address;
  }

  /** The owning session. Internal: the session's gate compares it. @internal */
  get session(): Session {
    return this.#session;
  }

  /** The core generation this node belongs to. Internal: the session's gate compares it. @internal */
  get generation(): number {
    return this.#generation;
  }

  /** Tuple of direct children, from first to last (empty when leaf). */
  children(): Node[] {
    return this.#session.children(this);
  }

  /** Text bytes of this node. A refused node throws. */
  text(): Uint8Array {
    return this.#session.text(this);
  }

  /** Symbol name as a string; terminal-only nodes → "". A refused node throws. */
  symbolName(): string {
    return decodeUtf8(this.symbolNameBytes());
  }

  /** Raw symbol name bytes (Uint8Array). A refused node throws. */
  symbolNameBytes(): Uint8Array {
    return this.#session.symbolNameBytes(this);
  }

  /** (start, length) byte span. A refused node throws. */
  span(): [bigint, bigint] {
    return this.#session.span(this);
  }

  /** 1-based (line, column) of first byte. A refused node throws. */
  lineColumn(): [number, number] {
    return this.#session.lineColumn(this);
  }

  /** Parent node, or null for root. */
  parent(): Node | null {
    return this.#session.parent(this);
  }

  nextSibling(): Node | null {
    return this.#session.nextSibling(this);
  }

  priorSibling(): Node | null {
    return this.#session.priorSibling(this);
  }

  firstChild(): Node | null {
    return this.#session.firstChild(this);
  }

  lastChild(): Node | null {
    return this.#session.lastChild(this);
  }

  /**
   * Pre-order walker over the subtree rooted at this node, this node
   * included at depth 0. Pass true for `skipSemanticErrors` to prune
   * subtrees rooted at semantic-error nodes, and for `skipRecovered` to
   * prune those rooted at nodes syntax-error recovery kept in place of
   * damaged input; with both the walk yields only undamaged, valid nodes.
   * The walker owns no native resource: abandoning
   * it is free, and parsing again with one open succeeds — its next step
   * throws a `StaleTreeError` instead. Each step picks its door like
   * any node call, so a walk created inside a hook of a running parse
   * walks that parse's in-flight tree. Steps follow the live links, so
   * edits between steps are visible; a step whose position is no longer
   * inside the walk's root (removed, or moved elsewhere) throws an
   * `invalid node` error.
   */
  walk(skipSemanticErrors = false, skipRecovered = false): Walker {
    return walkStart(this.#session, this, skipSemanticErrors, skipRecovered);
  }

  cleanChildren(): Node | null {
    return this.#session.cleanChildren(this);
  }

  /**
   * Appends `chain` behind this node's last child. The chain must belong
   * to the same session and be live for the same door; the session's gate
   * refuses one that is not.
   *
   * @throws TypeError when `chain` is a `Node` of a different session.
   */
  appendChildren(chain: Node): void {
    this.#session.appendChildren(this, chain);
  }

  /** Number of direct children. */
  get length(): number {
    return this.#session.childCount(this);
  }

  /** Child at index (negative indices supported). */
  at(index: number): Node {
    const count = this.length;
    let i = index;
    if (i < 0) i += count;
    if (i < 0 || i >= count) throw new RangeError(`node index ${index} out of range (0..${count - 1})`);
    const arr = this.children();
    return arr[i];
  }

  *[Symbol.iterator](): Iterator<Node> {
    yield* this.children();
  }

  toString(): string {
    return `Node(${this.#address.toString()})`;
  }
}

/**
 * The walk-start path `Node.walk` calls, installed once by `Session`'s class
 * body, which alone reaches the door, port and intern table a walk needs.
 * Held here so `node.ts` imports only types from `session.ts`: a value import
 * back would make the module graph cyclic.
 */
let walkStart: (session: Session, root: Node, skipSemanticErrors: boolean, skipRecovered: boolean) => Walker;

/**
 * Installs the walk-start path behind `Node.walk`. Internal: only `Session`
 * calls it, and no package entry point re-exports it.
 */
export function installWalkStart(
  start: (session: Session, root: Node, skipSemanticErrors: boolean, skipRecovered: boolean) => Walker,
): void {
  walkStart = start;
}

/**
 * Builds a node stamped with `generation`. Internal: the session's intern
 * table calls it, and no package entry point re-exports it, so node
 * creation stays unreachable from the public surface while
 * `instanceof Node` keeps answering everywhere a node is reached.
 */
export function createNode(session: Session, address: bigint, generation: number): Node {
  return Node.create(NODE_CONSTRUCTION_TOKEN, session, address, generation);
}

/**
 * The single gate for a public node argument: the address of `value` when
 * it is a `Node`, otherwise a `TypeError`. A bare address carries no
 * session and no generation, so accepting one would read whichever node
 * happens to hold that index in whichever parse is current; every method
 * that takes a node crosses here at entry.
 *
 * @throws TypeError when `value` is not a `Node`.
 */
export function nodeAddress(value: unknown): bigint {
  if (!(value instanceof Node)) {
    throw new TypeError(`galley: expected a Node, got ${typeof value}`);
  }
  return value.address;
}
