import type { Session } from "./session.ts";
import { decodeUtf8 } from "./text.ts";
import { SessionClosedError } from "./errors.ts";

/**
 * One of the two doors over node storage: a `Session` after a parse, or
 * the parse's `HookDoor` during one. Both expose the same reads and
 * edits, so a `Node` is a handle that delegates every accessor to the
 * door that owns its storage. Each door gates its own crossings — its
 * liveness, the node's parse generation, and that a node argument
 * belongs to this door — through `nodeAddress`, so no accessor can
 * cross without passing it.
 */
export interface NodeDoor {
  childCount(node: Node | bigint | number): number;
  firstChild(node: Node | bigint | number): Node | null;
  lastChild(node: Node | bigint | number): Node | null;
  nextSibling(node: Node | bigint | number): Node | null;
  priorSibling(node: Node | bigint | number): Node | null;
  parent(node: Node | bigint | number): Node | null;
  text(node: Node | bigint | number): Uint8Array | null;
  symbolNameBytes(node: Node | bigint | number): Uint8Array | null;
  span(node: Node | bigint | number): [bigint, bigint] | null;
  lineColumn(node: Node | bigint | number): [number, number] | null;
  cleanChildren(node: Node | bigint | number): Node | null;
  appendChildren(parent: Node | bigint | number, chain: Node | bigint | number): void;
}

/**
 * The one children iteration: count-bounded, first to last. Both doors
 * run it — the session door after a parse, the hook door during one —
 * so every step crosses (and is gated by) the door that owns the node and
 * a mismatch between the count and the chain still fails loudly.
 */
export function childrenVia(door: NodeDoor, node: Node | bigint | number): Node[] {
  const count = door.childCount(node);
  const out: Node[] = [];
  let child = door.firstChild(node);
  for (let i = 0; i < count; i++) {
    if (child === null) throw new Error("child count changed during iteration");
    out.push(child);
    child = door.nextSibling(child);
  }
  return out;
}

/**
 * Handle for a node in the non-relocating AST storage, bound to one of
 * the two doors: its `Session` (post-parse) or the parse's `HookDoor`
 * (parse-time). Every accessor is one delegation to that door, which
 * gates it: a closed session or a re-parsed generation throws.
 */
export class Node {
  readonly #session: Session;
  readonly #door: NodeDoor;
  readonly #address: bigint;
  /**
   * Parse generation stamped at construction. The constructor is the
   * single creation gate: every node carries the generation it belongs
   * to, so no accessor can read storage from an older parse.
   */
  readonly #generation: number;

  constructor(session: Session, address: bigint | number, door?: NodeDoor) {
    this.#session = session;
    this.#door = door ?? session;
    this.#address = typeof address === "bigint" ? address : BigInt(address);
    this.#generation = session.parseGeneration;
  }

  /** Raw address (stable index in the session's node storage). */
  get address(): bigint {
    return this.#address;
  }

  /**
   * The door this node belongs to: its session, or the parse's hook door.
   * Internal: the doors' gate compares it to refuse a node from another
   * door.
   * @internal
   */
  get door(): NodeDoor {
    return this.#door;
  }

  /**
   * The liveness check behind `nodeAddress`: a closed session or a node
   * left over from a previous parse generation throws instead of reading
   * stale storage. Internal: only the doors' gate calls it.
   * @internal
   */
  ensureAlive(): void {
    if (this.#session.isClosed) {
      throw new SessionClosedError("node's session is closed");
    }
    if (this.#generation !== this.#session.parseGeneration) {
      throw new SessionClosedError("node is invalidated");
    }
  }

  /** Tuple of direct children, from first to last (empty when leaf). */
  children(): Node[] {
    return childrenVia(this.#door, this);
  }

  /** Text bytes of this node, or null for invalid node. */
  text(): Uint8Array | null {
    return this.#door.text(this);
  }

  /** Symbol name bytes as string, or null for invalid node. Terminal-only nodes → "". */
  symbolName(): string | null {
    const bytes = this.symbolNameBytes();
    if (bytes === null) return null;
    return decodeUtf8(bytes);
  }

  /** Raw symbol name bytes (Uint8Array) or null. */
  symbolNameBytes(): Uint8Array | null {
    return this.#door.symbolNameBytes(this);
  }

  /** (start, length) byte span, or null. */
  span(): [bigint, bigint] | null {
    return this.#door.span(this);
  }

  /** 1-based (line, column) of first byte, or null. */
  lineColumn(): [number, number] | null {
    return this.#door.lineColumn(this);
  }

  /** Parent node, or null for root. */
  parent(): Node | null {
    return this.#door.parent(this);
  }

  nextSibling(): Node | null {
    return this.#door.nextSibling(this);
  }

  priorSibling(): Node | null {
    return this.#door.priorSibling(this);
  }

  firstChild(): Node | null {
    return this.#door.firstChild(this);
  }

  lastChild(): Node | null {
    return this.#door.lastChild(this);
  }

  cleanChildren(): Node | null {
    return this.#door.cleanChildren(this);
  }

  /**
   * Appends `chain` behind this node's last child. The chain must live
   * on this node's door; the door's gate refuses one that does not.
   *
   * @throws TypeError when `chain` is a `Node` on a different door.
   */
  appendChildren(chain: Node | bigint | number): void {
    this.#door.appendChildren(this, chain);
  }

  /** Number of direct children. */
  get length(): number {
    return this.#door.childCount(this);
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

  /**
   * Raw address for `Number(node)` / `BigInt(node)`. Comparison
   * belongs in {@link equals}: loose `==` against a bigint or number
   * coerces through the primitive conversion below and compares by
   * address alone, with no door check.
   */
  valueOf(): bigint {
    return this.#address;
  }

  toString(): string {
    return `Node(${this.#address.toString()})`;
  }

  equals(other: unknown): boolean {
    if (other instanceof Node) {
      return this.#address === other.#address && this.#door === other.#door;
    }
    if (typeof other === "bigint") return this.#address === other;
    if (typeof other === "number") return this.#address === BigInt(other);
    return false;
  }

  // Conversion for `Number(node)`, `+node`, and template strings.
  // `==` also routes here (default hint), so it stays address-only;
  // equals() is the sanctioned comparison.
  [Symbol.toPrimitive](hint: string): bigint | string | number {
    if (hint === "number") return Number(this.#address);
    if (hint === "string") return this.toString();
    return this.#address;
  }
}

/**
 * The single gate for every node argument a door accepts: a `Node`
 * handle must reference an open session on its own parse generation and
 * belong to `door` — the crossing sends a bare address and native storage
 * only bounds-checks it, so a node from another door would alias whichever
 * node holds that index here. Raw addresses carry no generation or door
 * and pass through unguarded by design.
 *
 * @throws TypeError when `node` is a `Node` on a different door.
 */
export function nodeAddress(node: Node | bigint | number, door: NodeDoor): bigint {
  if (typeof node === "bigint") return node;
  if (typeof node === "number") return BigInt(node);
  node.ensureAlive();
  if (node.door !== door) {
    throw new TypeError("node belongs to a different door than this operation");
  }
  return node.address;
}
