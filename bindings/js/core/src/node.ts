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
 * Handle for a node in the non-relocating AST storage: its owning
 * `Session`, the core's parse generation it belongs to, and its address.
 * Every accessor is one delegation to the session, which chooses the door
 * when the call is made (the parse's hook door from inside a hook of its
 * running parse, the post-parse door everywhere else) and gates it: a
 * closed session or a generation that is gone throws. Nodes handed out by
 * the hooks of a parse that publishes its tree stay valid until the
 * session parses again; nodes of a failed parse are gone.
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
   * Wraps a raw address, stamped with the generation of the door a call
   * made now would cross unless `generation` says otherwise. A raw address
   * carries no generation of its own, so this is the explicit conversion
   * and the caller vouches for it.
   */
  constructor(session: Session, address: bigint | number, generation?: bigint) {
    this.#session = session;
    this.#address = typeof address === "bigint" ? address : BigInt(address);
    this.#generation = generation ?? session.currentGeneration;
  }

  /** Raw address (stable index in the session's node storage). */
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
  appendChildren(chain: Node | bigint | number): void {
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

  /**
   * Raw address for `Number(node)` / `BigInt(node)`. Comparison
   * belongs in {@link equals}: loose `==` against a bigint or number
   * coerces through the primitive conversion below and compares by
   * address alone, with no generation check.
   */
  valueOf(): bigint {
    return this.#address;
  }

  toString(): string {
    return `Node(${this.#address.toString()})`;
  }

  equals(other: unknown): boolean {
    if (other instanceof Node) {
      return (
        this.#address === other.#address &&
        this.#generation === other.#generation &&
        this.#session === other.#session
      );
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
