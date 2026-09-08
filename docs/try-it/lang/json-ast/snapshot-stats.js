/**
 * Snapshot-based counting for the docs JSON checker grammar
 * (`docs/try-it/lang/json/ll.grm`, built with AST on and procedures off).
 *
 * One FFI crossing (`session.snapshot()`) yields flat per-node arrays;
 * this module classifies every node from data the page already holds:
 *
 * - `Value` nodes sort by the first non-blank byte of their span:
 *   `{` object, `[` array, `"` string, `t`/`f` boolean, `n` null,
 *   anything else number.
 * - Each non-empty `ObjectMembers` / `ObjectMembersTail` node is one
 *   member, hence one key (empty productions are childless leaves).
 *
 * Everything else (hidden blanks, number tails, wrapper nodes) is ignored.
 */

const decoder = new TextDecoder();

const BLANK = new Set([0x20, 0x09, 0x0a, 0x0d]);

export function countSnapshot(session, inputBytes) {
  const snap = session.snapshot();
  const stats = {
    object: 0,
    array: 0,
    number: 0,
    string: 0,
    null: 0,
    boolean: 0,
    key: 0,
  };
  const names = new Map();
  const variableName = (index) => {
    if (index < 0) return null;
    let name = names.get(index);
    if (name === undefined) {
      const bytes = session.variableNameAt(index);
      name = bytes ? decoder.decode(bytes) : null;
      names.set(index, name);
    }
    return name;
  };
  const firstContentByte = (start, length) => {
    const end = Math.min(start + length, inputBytes.length);
    for (let offset = start; offset < end; offset++) {
      const byte = inputBytes[offset];
      if (!BLANK.has(byte)) return byte;
    }
    return 0;
  };
  for (let node = 0; node < snap.count; node++) {
    const name = variableName(Number(snap.variable[node]));
    if (name === "Value") {
      const byte = firstContentByte(Number(snap.spanStart[node]), Number(snap.spanLen[node]));
      if (byte === 0x7b) stats.object++;
      else if (byte === 0x5b) stats.array++;
      else if (byte === 0x22) stats.string++;
      else if (byte === 0x74 || byte === 0x66) stats.boolean++;
      else if (byte === 0x6e) stats.null++;
      else stats.number++;
    } else if (
      (name === "ObjectMembers" || name === "ObjectMembersTail") &&
      snap.childCount[node] > 0
    ) {
      stats.key++;
    }
  }
  return stats;
}
