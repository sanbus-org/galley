/**
 * Generic snapshot walk for the Try-it page's non-JSON checkers.
 *
 * One FFI crossing (`session.snapshot()`) yields flat per-node arrays;
 * this module walks every node once and reports the total, with no
 * knowledge of any grammar. JSON keeps its own classifying walk
 * (`lang/json/snapshot-stats.js`); every other language reports plain
 * node counts here, so AST + visit stays one code path per kind.
 */

export function countNodes(session) {
  const snap = session.snapshot();
  let nodes = 0;
  for (let node = 0; node < snap.count; node++) {
    // Read each node's linkage so the walk touches the whole snapshot,
    // mirroring the classifying walk's full traversal.
    if (snap.childCount[node] >= 0) nodes += 1;
  }
  return { node: nodes };
}
