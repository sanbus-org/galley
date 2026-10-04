/**
 * The shared published-failure scenarios, run by every runtime's suite
 * (node, bun, deno, wasm) against its own session factory.
 *
 * A parse that fails after running to its end publishes its tree: semantic
 * errors mark nodes, recovered syntax errors leave flagged nodes over the
 * damaged input, and `parse` still throws. A parse the parser cannot recover
 * from publishes nothing. `newParser` resolves a parser of the keyvalue
 * fixture; `StaleTreeError`, `GalleyError` and `Status` come from the
 * runtime's own entry so identity checks hold.
 */

// Recovery skips `x,beta:` to resynchronize, then `2`: two recovered nodes.
const RECOVERED = "alpha:x,beta:2";
// Parses, but a hook reports one semantic error on the Number `2000`.
const SEMANTIC = "alpha:1,beta:2000";

export async function runPublishedFailureScenarios({ test, assert, newParser, StaleTreeError, GalleyError, Status }) {
  const decode = (bytes) => new TextDecoder().decode(bytes);

  /** Every step of the published tree's walk, with its symbol and span. */
  function steps(s, ...options) {
    const root = s.rootNode();
    assert.ok(root !== null);
    return [...root.walk(...options)].map((step) => {
      const [start, length] = s.span(step.node);
      return { step, symbol: s.symbolName(step.node), start: Number(start), length: Number(length) };
    });
  }

  await test("a semantic-only failure publishes its tree", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      // The hook is installed here: not every runtime auto-loads the
      // fixture's own.
      s.installProcedure("reduction_Number", (args) => {
        const node = args.currentNode();
        if (Number.parseInt(decode(node.text()), 10) > 999) args.reportSemanticError("value out of range");
      });
      assert.throws(() => s.parse(SEMANTIC), (error) => error instanceof GalleyError && error.code === Status.ErrorSemantic);

      const full = steps(s);
      const marked = full.filter((entry) => entry.step.isSemanticError);
      assert.equal(marked.length, 1);
      assert.deepEqual([marked[0].symbol, marked[0].start, marked[0].length], ["Number", 13, 4]);
      assert.ok(full.every((entry) => !entry.step.isRecovered));

      const pruned = steps(s, true);
      assert.ok(pruned.length < full.length);
      assert.ok(pruned.every((entry) => !entry.step.isSemanticError));
      // Nothing is recovered, so skipping recovered nodes changes nothing.
      assert.equal(steps(s, false, true).length, full.length);

      const snapshot = s.snapshot();
      assert.equal(snapshot.isSemanticError.reduce((sum, flag) => sum + flag, 0), 1);
      assert.equal(snapshot.isRecovered.reduce((sum, flag) => sum + flag, 0), 0);
      assert.equal(decode(s.lastInput()), SEMANTIC);
      assert.deepEqual(s.lastPosition(), [1, SEMANTIC.length + 2]);

      // The next parse retires the errored tree's nodes.
      const stale = s.rootNode();
      s.parse("alpha:12,beta:3");
      assert.throws(() => stale.text(), StaleTreeError);
    } finally {
      s.close();
    }
  });

  await test("a recovered syntax error publishes its tree", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      assert.throws(() => s.parse(RECOVERED), (error) => error instanceof GalleyError && error.code === Status.ErrorSyntax);

      const full = steps(s);
      const recovered = full.filter((entry) => entry.step.isRecovered);
      assert.equal(recovered.length, 2);
      assert.ok(full.every((entry) => !entry.step.isSemanticError));
      // The damaged Number covers the input recovery skipped: `x,beta:`.
      assert.deepEqual([recovered[0].symbol, recovered[0].start, recovered[0].length], ["Number", 6, 7]);

      // Skipping them leaves only undamaged nodes, none inside the damage.
      const undamaged = steps(s, false, true);
      assert.equal(undamaged.length, full.length - 2);
      for (const entry of undamaged) {
        assert.equal(entry.step.isRecovered, false);
        assert.ok(entry.start < 6 || entry.start >= 13);
      }

      // The snapshot column reads what the walk reports, node for node.
      const snapshot = s.snapshot();
      const flagged = [];
      for (let i = 0; i < snapshot.count; i++) if (snapshot.isRecovered[i]) flagged.push(BigInt(i));
      assert.deepEqual(flagged, recovered.map((entry) => entry.step.node.address));

      assert.equal(decode(s.lastInput()), RECOVERED);
      assert.ok(Array.isArray(s.lastPosition()));

      const stale = s.rootNode();
      s.parse("alpha:12,beta:3");
      assert.throws(() => stale.text(), StaleTreeError);
    } finally {
      s.close();
    }
  });

  await test("an unrecovered syntax error publishes nothing", async () => {
    const parser = await newParser();
    // One error is the limit, so the parser raises instead of recovering.
    const s = await parser.openSession({ maxErrors: 1 });
    try {
      assert.throws(() => s.parse(RECOVERED), GalleyError);
      assert.equal(s.rootNode(), null);
      assert.throws(() => s.lastInput(), StaleTreeError);
      assert.throws(() => s.lastPosition(), StaleTreeError);
      assert.throws(() => s.nodeCount(), StaleTreeError);
    } finally {
      s.close();
    }
  });

  await test("lastInput and lastPosition refuse before any parse", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      assert.throws(() => s.lastInput(), StaleTreeError);
      assert.throws(() => s.lastPosition(), StaleTreeError);
    } finally {
      s.close();
    }
  });

  await test("a failure without a root still publishes its input", async () => {
    // Recovery skips all of the input before the grammar's first symbol: the
    // parse publishes, but there is no tree to hold a root.
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      assert.throws(() => s.parse("?"), GalleyError);
      assert.equal(s.rootNode(), null);
      assert.equal(decode(s.lastInput()), "?");
    } finally {
      s.close();
    }
  });
}
