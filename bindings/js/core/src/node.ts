import type { Session } from "./session.ts";
import { decodeUtf8 } from "./text.ts";
import { SessionClosedError } from "./errors.ts";

/**
 * Session-bound handle for a node in the non-relocating AST storage.
 * Mirrors Python's `galley.Node`: keeps a strong reference to its Session
 * and raises after the session is closed or parses again — nodes read
 * only the parse generation that created them.
 */
export class Node {
  readonly #session: Session;
  readonly #address: bigint;
  /**
   * Parse generation stamped at construction. The constructor is the
   * single creation gate: every node carries the generation it belongs
   * to, so no accessor can read storage from an older parse.
   */
  readonly #generation: number;

  constructor(session: Session, address: bigint | number) {
    this.#session = session;
    this.#address = typeof address === "bigint" ? address : BigInt(address);
    this.#generation = session.parseGeneration;
  }

  /** Raw address (stable index in the session's node storage). */
  get address(): bigint {
    return this.#address;
  }

  /**
   * The single use gate: a closed session or a node left over from a
   * previous parse generation throws instead of reading stale storage.
   * Internal: {@link nodeAddress} runs it at every session crossing.
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
    this.ensureAlive();
    return this.#session.children(this);
  }

  /** Text bytes of this node, or null for invalid node. */
  text(): Uint8Array | null {
    this.ensureAlive();
    return this.#session.text(this);
  }

  /** Symbol name bytes as string, or null for invalid node. Terminal-only nodes → "". */
  symbolName(): string | null {
    this.ensureAlive();
    const bytes = this.#session.symbolNameBytes(this);
    if (bytes === null) return null;
    return decodeUtf8(bytes);
  }

  /** Raw symbol name bytes (Uint8Array) or null. */
  symbolNameBytes(): Uint8Array | null {
    this.ensureAlive();
    return this.#session.symbolNameBytes(this);
  }

  /** (start, length) byte span, or null. */
  span(): [bigint, bigint] | null {
    this.ensureAlive();
    return this.#session.span(this);
  }

  /** 1-based (line, column) of first byte, or null. */
  lineColumn(): [number, number] | null {
    this.ensureAlive();
    return this.#session.lineColumn(this);
  }

  /** Parent node, or null for root. */
  parent(): Node | null {
    this.ensureAlive();
    return this.#session.parent(this);
  }

  nextSibling(): Node | null {
    this.ensureAlive();
    return this.#session.nextSibling(this);
  }

  priorSibling(): Node | null {
    this.ensureAlive();
    return this.#session.priorSibling(this);
  }

  firstChild(): Node | null {
    this.ensureAlive();
    return this.#session.firstChild(this);
  }

  lastChild(): Node | null {
    this.ensureAlive();
    return this.#session.lastChild(this);
  }

  cleanChildren(): Node | null {
    this.ensureAlive();
    return this.#session.cleanChildren(this);
  }

  appendChildren(chain: Node | bigint | number): void {
    this.ensureAlive();
    this.#session.appendChildren(this, chain);
  }

  /** Number of direct children. */
  get length(): number {
    this.ensureAlive();
    return this.#session.childCount(this);
  }

  /** Child at index (negative indices supported). */
  at(index: number): Node {
    this.ensureAlive();
    const count = this.length;
    let i = index;
    if (i < 0) i += count;
    if (i < 0 || i >= count) throw new RangeError(`node index ${index} out of range (0..${count - 1})`);
    const arr = this.children();
    return arr[i];
  }

  *[Symbol.iterator](): Iterator<Node> {
    this.ensureAlive();
    for (const child of this.children()) yield child;
  }

  /**
   * Raw address for `Number(node)` / `BigInt(node)`. Comparison
   * belongs in {@link equals}: loose `==` against a bigint or number
   * coerces through the primitive conversion below and compares by
   * address alone, with no session check.
   */
  valueOf(): bigint {
    return this.#address;
  }

  toString(): string {
    return `Node(${this.#address.toString()})`;
  }

  equals(other: unknown): boolean {
    if (other instanceof Node) {
      return this.#address === other.#address && this.#session === other.#session;
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
 * The single gate for every crossing that accepts a node: a `Node`
 * handle must reference an open session on its own parse generation,
 * then yields its address. Raw addresses carry no generation and pass
 * through unguarded by design.
 */
export function nodeAddress(node: Node | bigint | number): bigint {
  if (typeof node === "bigint") return node;
  if (typeof node === "number") return BigInt(node);
  node.ensureAlive();
  return node.address;
}
