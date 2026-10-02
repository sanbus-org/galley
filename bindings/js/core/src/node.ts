import type { Session } from "./session.ts";
import { decodeUtf8 } from "./text.ts";

/**
 * One of the two doors over node storage, as the address-level crossing a
 * `Session` call makes: the session door (`galley_node_*`, refused by the
 * core while a parse runs) or the hook door of one hook dispatch
 * (`galley_hook_*` over the parse's native door). The session picks the door
 * per call; a `Node` stores neither.
 * @internal
 */
export interface NodeDoor {
  /** True for the hook door of a running parse. */
  readonly isHook: boolean;
  /**
   * The core generation a node must carry to cross this door: the running
   * parse's on the hook door, the published tree's on the session door.
   */
  readonly generation: bigint;
  nodeValid(address: bigint): boolean;
  childCount(address: bigint): number;
  firstChild(address: bigint): bigint;
  lastChild(address: bigint): bigint;
  nextSibling(address: bigint): bigint;
  priorSibling(address: bigint): bigint;
  parent(address: bigint): bigint;
  text(address: bigint): Uint8Array | null;
  symbolNameBytes(address: bigint): Uint8Array | null;
  span(address: bigint): [bigint, bigint] | null;
  lineColumn(address: bigint): [number, number] | null;
  /** The raw variable index, or null when the node has no variable. */
  variableIndex(address: bigint): number | null;
  /**
   * One step of a walk over the host-owned 40-byte cursor: 1 yields a
   * node, 0 ends the walk (and keeps ending it), negative is a failure
   * (stale tree, session in use, malformed cursor bytes).
   */
  walkNext(cursor: ArrayBuffer): number;
  /** Head of the detached chain; `INVALID_NODE` when there were no children. */
  cleanChildren(address: bigint): bigint;
  appendChildren(parent: bigint, chain: bigint): void;
  insertBefore(target: bigint, chain: bigint): void;
  insertAfter(target: bigint, chain: bigint): void;
  /** Head of the detached chain; `INVALID_NODE` when empty. */
  removeSiblings(address: bigint, count: number): bigint;
  removeSelf(address: bigint): bigint;
  promoteChildrenOverWrapper(wrapper: bigint): bigint;
  unlinkWrapper(wrapper: bigint): void;
  insertChildrenAt(parent: bigint, index: number, chain: bigint): void;
  removeChildrenAt(parent: bigint, index: number, count: number): bigint;
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
 * closed session or a generation that is gone throws. Nodes handed out by
 * the hooks of a parse that publishes its tree stay valid until the
 * session parses again; nodes of a failed parse are gone.
 *
 * The session interns one object per (generation, address) while that
 * generation is live, so identity (`===`) answers "the same node of the
 * same parse" everywhere a node is reached; once its generation is
 * superseded, reading it again answers with a fresh, uninterned handle.
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
  readonly #generation: bigint;

  /**
   * Internal: the session's intern table ({@link createNode}) is the
   * creation gate, and the emitted types mark this constructor `private`,
   * so no package entry point can even compile a `new Node`. The leading
   * token stays module-private, so runtime reflection reaches the same
   * gate — a raw address carries no generation of its own, and without
   * the token the caller would be vouching for one that nothing verifies.
   */
  private constructor(token: symbol, session: Session, address: bigint, generation: bigint) {
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
  static create(token: symbol, session: Session, address: bigint, generation: bigint): Node {
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
  get generation(): bigint {
    return this.#generation;
  }

  /** Tuple of direct children, from first to last (empty when leaf). */
  children(): Node[] {
    return this.#session.children(this);
  }

  /** Text bytes of this node, or null for invalid node. */
  text(): Uint8Array | null {
    return this.#session.text(this);
  }

  /** Symbol name bytes as string, or null for invalid node. Terminal-only nodes → "". */
  symbolName(): string | null {
    const bytes = this.symbolNameBytes();
    if (bytes === null) return null;
    return decodeUtf8(bytes);
  }

  /** Raw symbol name bytes (Uint8Array) or null. */
  symbolNameBytes(): Uint8Array | null {
    return this.#session.symbolNameBytes(this);
  }

  /** (start, length) byte span, or null. */
  span(): [bigint, bigint] | null {
    return this.#session.span(this);
  }

  /** 1-based (line, column) of first byte, or null. */
  lineColumn(): [number, number] | null {
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
 * Builds a node stamped with `generation`. Internal: the session's intern
 * table calls it, and no package entry point re-exports it, so node
 * creation stays unreachable from the public surface while
 * `instanceof Node` keeps answering everywhere a node is reached.
 */
export function createNode(session: Session, address: bigint, generation: bigint): Node {
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
