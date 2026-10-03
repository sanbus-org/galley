/**
 * Small helpers every FFI adapter shares, so the node-door crossings are
 * shaped once: a link answer, and the BigInt a 64-bit parameter needs.
 */

/**
 * Splits a link call's 64-bit answer into an address or a status. The core
 * answers a non-negative address (`INVALID_NODE` for no link) or a negative
 * status; adapters hand a status on as a Number and an address as a BigInt,
 * so an address is never mistaken for a status. A backend that answers a
 * safe integer as a Number (small addresses) is widened here.
 */
export function linkOrStatus(value: number | bigint): bigint | number {
  if (typeof value === "number") return value < 0 ? value : BigInt(value);
  return value < 0n ? Number(value) : value;
}

/**
 * The generation as the BigInt a 64-bit native parameter keeps its fast call
 * with. A one-entry memo keyed by the number: the BigInt is derived from it,
 * so the two cannot drift, and it is recomputed only when the generation
 * changes, i.e. once per parse. One instance per port.
 */
export class GenerationBigInt {
  #number = -1;
  #bigint = -1n;

  of(generation: number): bigint {
    if (generation !== this.#number) {
      this.#bigint = BigInt(generation);
      this.#number = generation;
    }
    return this.#bigint;
  }
}
