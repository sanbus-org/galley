/**
 * The shared node-generation scenarios, run by every runtime's suite
 * (node, bun, deno, wasm) against its own session factory.
 *
 * A node is its owning session, the core's parse generation and an
 * address. The core stamps one generation per parse; hosts read it and
 * choose the door per call: from inside a hook dispatch of the running
 * parse a node crosses the parse's hook door, anywhere else the session
 * door, for every node operation. JavaScript has one thread per session and
 * parses synchronously, so the refusal reachable here is a hook that parses
 * its own session (the cross-thread refusal is covered by the Python and
 * Java suites).
 *
 * `newParser` resolves a parser of the keyvalue fixture; `SessionClosedError`,
 * `StaleTreeError` and `Status` come from the runtime's own entry so identity
 * checks hold; `collect` is that runtime's forced garbage collection, used by
 * the release scenario.
 */

/**
 * Creates and registers the snapshot's first `limit` nodes, returning
 * their addresses. The handles are created inside this frame — which has
 * returned before the caller awaits anything — because JavaScriptCore
 * scans the stack conservatively: a node left in a suspended async frame
 * would stay reachable across the forced collections. Only the addresses
 * (bigints) cross back out, and nothing here keeps a node alive.
 */
function registerInternedNodes(snap, registry, limit) {
  const addresses = [];
  for (let i = 0; i < Math.min(snap.count, limit); i++) {
    const node = snap.node(i);
    if (node === null) throw new Error(`galley: snapshot node ${i} is invalid`);
    addresses.push(node.address);
    registry.register(node, node.address);
  }
  return addresses;
}

export async function runGenerationScenarios({ test, assert, newParser, SessionClosedError, StaleTreeError, GalleyError, Status, collect }) {
  const decode = (bytes) => new TextDecoder().decode(bytes);

  await test("a refused parse leaves hook nodes and the published tree valid", async () => {
    // The core refuses a parse of a session that is already parsing and
    // changes nothing: a node stashed by hook 1 still reads in hook 2 after
    // the hook's own refused parse, and the tree the running parse
    // publishes is readable afterwards.
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      const refusals = [];
      const reads = [];
      let stashed = null;
      s.installProcedure("reduction_Pair", (args) => {
        if (stashed === null) {
          stashed = args.currentNode();
          try {
            s.parse("gamma:1");
          } catch (error) {
            refusals.push(error);
          }
        }
        reads.push(decode(stashed.text()));
      });
      s.parse("alpha:12,beta:3");
      assert.equal(refusals.length, 1);
      assert.ok(refusals[0] instanceof GalleyError);
      assert.equal(refusals[0].code, Status.ErrorSessionInUse);
      assert.deepEqual(reads, ["alpha:12", "alpha:12"]);
      assert.equal(decode(stashed.text()), "alpha:12");
      const root = s.rootNode();
      assert.equal(decode(s.text(root)), "alpha:12,beta:3");
    } finally {
      s.close();
    }
  });

  await test("a hook node after a successful parse reads through the session and is the walker's node", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      const stashed = [];
      s.installProcedure("reduction_Pair", (args) => {
        stashed.push(args.currentNode());
      });
      s.parse("alpha:12,beta:3");
      assert.equal(stashed.length, 2);
      const first = stashed[0];
      assert.equal(decode(first.text()), "alpha:12");
      assert.equal(decode(s.text(first)), "alpha:12");
      assert.equal(s.childCount(first), first.length);
      let found = null;
      const walker = s.rootNode().walk();
      for (const step of walker) {
        if (step.node.address === first.address) {
          found = step.node;
          break;
        }
      }
      assert.ok(found !== null);
      assert.ok(found === first);
      assert.ok(first === found);
    } finally {
      s.close();
    }
  });

  await test("a hook node of a parse that publishes nothing is refused afterwards", async () => {
    const parser = await newParser();
    // One error is the limit, so the failing parse raises instead of
    // recovering and publishes nothing: its nodes die with it.
    const s = await parser.openSession({ maxErrors: 1 });
    try {
      const stashed = [];
      s.installProcedure("reduction_Number", (args) => {
        stashed.push(args.currentNode());
      });
      assert.throws(() => s.parse("alpha:12,beta:"), GalleyError);
      assert.ok(stashed.length >= 1);
      assert.throws(() => stashed[0].text(), StaleTreeError);
      assert.throws(() => s.text(stashed[0]), StaleTreeError);
      s.clearProcedures();
      s.parse("alpha:12,beta:3");
      assert.throws(() => stashed[0].text(), StaleTreeError);
    } finally {
      s.close();
    }
  });

  await test("a hook node of a published failure lives until the next parse", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      const stashed = [];
      s.installProcedure("reduction_Number", (args) => {
        stashed.push(args.currentNode());
      });
      // The parser recovers from the missing Number, so the failure
      // publishes its tree and the nodes its hooks saw stay valid.
      assert.throws(() => s.parse("alpha:12,beta:"), GalleyError);
      s.clearProcedures();
      assert.ok(stashed.length >= 1);
      assert.equal(decode(stashed[0].text()), "12");
      s.parse("alpha:12,beta:3");
      assert.throws(() => stashed[0].text(), StaleTreeError);
    } finally {
      s.close();
    }
  });

  await test("a node of an earlier parse is not the node at the same address", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      s.parse("alpha:12");
      const firstRoot = s.rootNode();
      s.parse("alpha:12");
      const secondRoot = s.rootNode();
      assert.equal(firstRoot.address, secondRoot.address);
      assert.ok(firstRoot !== secondRoot);
      assert.ok(secondRoot !== firstRoot);
      assert.throws(() => firstRoot.text(), StaleTreeError);
      assert.equal(decode(secondRoot.text()), "alpha:12");
    } finally {
      s.close();
    }
  });

  await test("every node operation crosses the hook door inside a hook", async () => {
    // The session door refuses with `ErrorSessionInUse` while a parse runs,
    // so an operation that succeeds inside a hook crossed the hook door.
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      const trace = [];
      let done = false;
      s.installProcedure("reduction_Pair", (args) => {
        if (done) return;
        done = true;
        const node = args.currentNode();
        const count = s.childCount(node);
        trace.push(["count", count]);
        const kids = s.children(node);
        trace.push(["variableIndex", typeof s.variableIndex(node) === "number" || s.variableIndex(node) === null]);
        trace.push(["symbolName", s.symbolName(node)]);
        trace.push(["text", decode(s.text(node))]);
        trace.push(["span", s.span(node) !== null]);
        trace.push(["lineColumn", s.lineColumn(node) !== null]);
        trace.push(["navigation", s.parent(kids[0]) === node && s.nextSibling(kids[0]) === kids[1] &&
          s.priorSibling(kids[1]) === kids[0] && s.lastChild(node) === kids[count - 1] && s.firstChild(node) === kids[0]]);
        // removeSiblings + insertChildrenAt
        const head = s.removeSiblings(kids[0], 1);
        trace.push(["removeSiblings", s.childCount(node) === count - 1]);
        s.insertChildrenAt(node, 0, head);
        // removeChildrenAt + insertBefore
        const second = s.removeChildrenAt(node, 0, 1);
        s.insertBefore(s.firstChild(node), second);
        // removeSelf + insertAfter
        const third = s.removeSelf(s.firstChild(node));
        s.insertAfter(s.firstChild(node), third);
        // cleanChildren + appendChildren
        const chain = s.cleanChildren(node);
        s.appendChildren(node, chain);
        trace.push(["restored", s.childCount(node) >= count - 1]);
      });
      s.parse("alpha:12,beta:3");
      assert.ok(trace.length >= 9, "the hook ran every operation");
      for (const [name, value] of trace) {
        assert.ok(value !== false && value !== null, `${name} failed inside the hook`);
      }
      assert.equal(trace[0][1], 3);
    } finally {
      s.close();
    }
  });

  await test("the hook door refuses a node of an earlier parse on every capability", async () => {
    // The core checks the generation inside every hook-door call: a node of
    // the previous parse raises the one stale-tree error on a read, a link,
    // a count, an edit and a walk step — nothing answers null — while a node
    // of the running parse still reads and edits.
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      s.parse("alpha:12,beta:3");
      const previous = s.rootNode();
      const previousChild = s.firstChild(previous);
      const outcomes = [];
      const live = [];
      s.installProcedure("reduction_Pair", (args) => {
        const current = args.currentNode();
        for (const call of [
          () => s.text(previous),
          () => s.symbolName(previous),
          () => s.span(previous),
          () => s.lineColumn(previous),
          () => s.variableIndex(previous),
          () => s.firstChild(previous),
          () => s.lastChild(previous),
          () => s.nextSibling(previous),
          () => s.priorSibling(previous),
          () => s.parent(previous),
          () => s.childCount(previous),
          () => [...previous.walk()],
          () => s.appendChildren(previous, current),
          () => s.appendChildren(current, previous),
          // Both nodes of the previous parse: the host's own mixed-generation
          // check passes, so the core's decides.
          () => s.appendChildren(previous, previousChild),
          () => s.insertBefore(previous, previousChild),
          () => s.insertAfter(previous, previousChild),
          () => s.insertChildrenAt(previous, 0, previousChild),
          () => s.removeSiblings(previous, 1),
          () => s.removeChildrenAt(previous, 0, 1),
          () => s.cleanChildren(previous),
          () => s.removeSelf(previous),
          () => args.setCurrentNode(previous),
        ]) {
          try {
            call();
            outcomes.push("answered");
          } catch (error) {
            outcomes.push(error instanceof StaleTreeError ? "stale" : String(error));
          }
        }
        if (args.currentNode() !== current) outcomes.push("a refused set changed the current node");
        args.setCurrentNode(current);
        if (args.currentNode() !== current) outcomes.push("current node not set");
        live.push(decode(s.text(current)));
        const detached = s.cleanChildren(current);
        if (detached !== null) s.appendChildren(current, detached);
      });
      try {
        s.parse("alpha:12,beta:3");
      } finally {
        s.clearProcedures();
      }
      assert.deepEqual(outcomes, Array(23 * 2).fill("stale"));
      assert.deepEqual(live, ["alpha:12", "beta:3"]);
    } finally {
      s.close();
    }
  });

  await test("a walk inside a hook equals the post-parse walk", async () => {
    // A walk created and stepped inside a hook goes through the parse's
    // own door over the in-flight tree; replayed after the parse
    // publishes from the same roots, each yields the identical sequence.
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      const recorded = [];
      const hookRoots = [];
      s.installProcedure("reduction_Pair", (args) => {
        const node = args.currentNode();
        hookRoots.push(node);
        recorded.push([...node.walk()].map((step) => [step.node.address, step.depth]));
      });
      s.parse("alpha:12,beta:3");
      s.clearProcedures();
      assert.ok(recorded.length > 0);
      for (let index = 0; index < hookRoots.length; index++) {
        const replayed = [...hookRoots[index].walk()].map((step) => [step.node.address, step.depth]);
        assert.deepEqual(replayed, recorded[index]);
      }
      // walk() always hands back a walker, never null.
      assert.ok(s.rootNode().walk() !== null);
    } finally {
      s.close();
    }
  });

  await test("a hook walk prunes semantic error subtrees", async () => {
    // Error marks exist only in the in-flight tree: a semantic-failed
    // parse publishes nothing, so a walk inside the final hook is the
    // binding-side view that prunes a marked subtree where the plain
    // walk yields it.
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      const recorded = [];
      s.installProcedure("reduction_Number", (args) => {
        const node = args.currentNode();
        if (parseInt(decode(node.text()), 10) > 99) args.reportSemanticError("value out of range");
      });
      s.installProcedure("reduction_Document", (args) => {
        const node = args.currentNode();
        const full = [...node.walk()].map((step) => [step.node.address, step.depth, step.isSemanticError]);
        const pruned = [...node.walk(true)].map((step) => [step.node.address, step.depth]);
        recorded.push({ full, pruned });
      });
      assert.throws(
        () => s.parse("alpha:1,beta:2000"),
        (error) => error instanceof GalleyError && error.code === Status.ErrorSemantic,
      );
      assert.ok(recorded.length > 0);
      const { full, pruned } = recorded.at(-1);
      const flagged = full.filter((step) => step[2]).map((step) => step[0]);
      assert.ok(flagged.length > 0);          // the plain walk saw a mark
      assert.ok(pruned.length < full.length); // and the pruned walk dropped it
      const prunedAddresses = new Set(pruned.map((step) => step[0]));
      for (const address of flagged) assert.ok(!prunedAddresses.has(address));
    } finally {
      s.clearProcedures();
      s.close();
    }
  });

  await test("a walk from a non-root node yields its subtree with relative depths", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      s.parse("alpha:12,beta:3");
      const root = s.rootNode();
      const pair = root.firstChild().firstChild();
      assert.ok(pair !== null && pair !== root);
      const expected = [];
      const record = (node, depth) => {
        expected.push([node.address, depth]);
        for (const child of node.children()) record(child, depth + 1);
      };
      record(pair, 0);
      assert.ok(expected.length > 1);
      const walked = [...pair.walk()].map((step) => [step.node.address, step.depth]);
      assert.deepEqual(walked, expected);
      assert.deepEqual(walked[0], [pair.address, 0]);
      // A strict subtree: the full walk from the root visits more.
      assert.ok(walked.length < [...root.walk()].length);
    } finally {
      s.close();
    }
  });

  await test("walking starts only from a node: Walker is closed and Session has no walk", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      s.parse("alpha:12,beta:3");
      const root = s.rootNode();
      const walker = root.walk();
      const Walker = walker.constructor;
      // The constructor demands a module-private token: no argument
      // combination reachable from outside builds a walker.
      assert.throws(() => Reflect.construct(Walker, []), TypeError);
      assert.throws(() => Reflect.construct(Walker, [s, root.address, 1n, false, true, () => root]), TypeError);
      assert.throws(
        () => Reflect.construct(Walker, [Symbol("galley.Walker.construction"), s, root.address, 1n, false, true, () => root]),
        TypeError,
      );
      assert.throws(
        () => Walker.create(Symbol("galley.Walker.construction"), s, root.address, 1n, false, true, () => root),
        TypeError,
      );
      assert.ok(!("walk" in s));
      assert.ok(!("startWalk" in s));
    } finally {
      s.close();
    }
  });

  await test("node.walk on a stale or closed-session node throws what other node calls throw", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    s.parse("alpha:12,beta:3");
    const stale = s.rootNode();
    s.parse("alpha:12,beta:3");
    let expected = null;
    try {
      stale.text();
    } catch (error) {
      expected = error;
    }
    assert.ok(expected instanceof StaleTreeError);
    // A walk binds its cursor to the node's generation, so the refusal
    // arrives at its first step, where the core checks — the same failure
    // class, with the same message, every other node call raises.
    const staleWalk = stale.walk();
    assert.throws(() => staleWalk.next(), (error) => {
      assert.ok(error instanceof StaleTreeError);
      assert.match(error.message, /is stale/);
      return true;
    });
    const live = s.rootNode();
    s.close();
    expected = null;
    try {
      live.text();
    } catch (error) {
      expected = error;
    }
    assert.ok(expected instanceof SessionClosedError);
    assert.throws(() => live.walk(), (error) => error instanceof SessionClosedError && error.message === expected.message);
  });

  await test("a walk step after removing the current node reports invalid node", async () => {
    // The step has no live position to advance from: invalid node, and
    // the cursor never moves past the failure.
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      s.parse("alpha:12,beta:3");
      const root = s.rootNode();
      const walker = root.walk();
      let leaf = null;
      for (const step of walker) {
        if (step.depth >= 1 && step.node.length === 0) {
          leaf = step.node;
          break;
        }
      }
      assert.ok(leaf !== null);
      s.removeSelf(leaf);
      assert.throws(() => walker.next(), (error) => {
        assert.ok(error instanceof GalleyError);
        assert.equal(error.code, Status.ErrorInvalidNode);
        return true;
      });
      assert.throws(() => walker.next(), GalleyError);
    } finally {
      s.close();
    }
  });

  await test("walk steps see edits between steps", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      s.parse("alpha:12,beta:3");
      const root = s.rootNode();
      const baseline = [...root.walk()].map((step) => [step.node.address, step.depth]);
      assert.ok(baseline.length > 1);

      const walker = root.walk();
      const first = walker.next();
      assert.equal(first.value.node, root);
      const removed = s.firstChild(root);
      assert.ok(removed !== null);
      assert.equal(removed.address, baseline[1][0]);
      const head = s.removeSelf(removed);
      assert.ok(head !== null);
      // The remainder follows the live links: the removed subtree — and
      // only it — is gone from the sequence.
      let skip = 2;
      while (skip < baseline.length && baseline[skip][1] > baseline[1][1]) skip++;
      const remaining = [];
      for (let step = walker.next(); !step.done; step = walker.next()) {
        remaining.push([step.value.node.address, step.value.depth]);
      }
      assert.deepEqual(remaining, baseline.slice(skip));
      // Re-inserting the removed subtree brings it back into the walk.
      s.appendChildren(root, head);
      const restored = [...root.walk()].map((step) => step.node.address);
      assert.equal(restored.length, baseline.length);
      assert.ok(restored.includes(removed.address));
    } finally {
      s.close();
    }
  });

  await test("a hook node is the session node reached after the parse", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      const stashed = [];
      s.installProcedure("reduction_Pair", (args) => {
        stashed.push(args.currentNode());
      });
      s.parse("alpha:12");
      const pair = s.firstChild(s.firstChild(s.rootNode()));
      assert.ok(stashed[0] === pair);
    } finally {
      s.close();
    }
  });

  await test("a refused parse leaves the running parse's node identity intact", async () => {
    // The intern table belongs to the parse in flight while its hooks
    // dispatch: a refused parse changes nothing, so it must not drop the
    // table either — the hook's node is the same object across the
    // refusal, and the published tree's node at that address afterwards.
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      const refusals = [];
      let stashed = null;
      let afterRefusal = null;
      s.installProcedure("reduction_Pair", (args) => {
        if (stashed !== null) return;
        stashed = args.currentNode();
        try {
          s.parse("gamma:1");
        } catch (error) {
          refusals.push(error);
        }
        afterRefusal = args.currentNode();
      });
      s.parse("alpha:12,beta:3");
      assert.equal(refusals.length, 1);
      assert.ok(refusals[0] instanceof GalleyError);
      assert.equal(refusals[0].code, Status.ErrorSessionInUse);
      assert.ok(stashed !== null);
      assert.ok(afterRefusal === stashed);
      const snap = s.snapshot();
      assert.ok(snap.node(stashed.address) === stashed);
    } finally {
      s.close();
    }
  });

  await test("a parse that publishes nothing leaves every handle of the wiped tree dead", async () => {
    const parser = await newParser();
    // One error is the limit, so the failing parse raises instead of
    // recovering.
    const s = await parser.openSession({ maxErrors: 1 });
    try {
      s.parse("alpha:12,beta:3");
      const root = s.rootNode();
      const snap = s.snapshot();
      assert.ok(snap.node(root.address) === root);
      // The failure publishes nothing, so the core refuses the generation
      // the snapshot's handles carry — identity aside, nothing reads.
      assert.throws(() => s.parse("gamma:"), (error) => error.code === Status.ErrorSyntax);
      assert.throws(() => snap.node(root.address).text(), StaleTreeError);
      assert.throws(() => s.childCount(root), StaleTreeError);
      assert.throws(() => s.nodeCount(), StaleTreeError);
      // The recovery parse stamps a newer generation, which takes the
      // intern table over: its nodes are one object per address again,
      // and the dead generation never comes back into it.
      s.parse("alpha:12,beta:3");
      const recovered = s.rootNode();
      assert.ok(recovered !== root);
      assert.ok(s.snapshot().node(recovered.address) === recovered);
      assert.ok(s.firstChild(recovered) === s.firstChild(recovered));
    } finally {
      s.close();
    }
  });

  await test("close() releases the interned nodes", async () => {
    const released = new Set();
    const registry = new FinalizationRegistry((address) => released.add(address));
    const parser = await newParser();
    const s = await parser.openSession();
    let expected = [];
    try {
      s.parse("alpha:12,beta:3");
      expected = registerInternedNodes(s.snapshot(), registry, 5);
      // Smoke check only: a forced collection while the session is open
      // must find these retained — it proves the collection runs, not
      // that retention is exhaustive.
      collect();
      await new Promise((resolve) => setTimeout(resolve, 10));
      assert.equal(released.size, 0);
    } finally {
      s.close();
    }
    // After close the table is dropped, so every registered node must
    // become unreachable: collect until the registry reports them.
    for (let attempt = 0; attempt < 100 && released.size < expected.length; attempt++) {
      collect();
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    assert.equal(
      released.size,
      expected.length,
      `released ${released.size} of ${expected.length} interned nodes after close()`,
    );
  });

  await test("nothing published refuses instead of answering", async () => {
    // Before any parse there is no tree: rootNode is the one "nothing here"
    // probe and answers null, and every other session-door read — the input
    // and the position included — raises the stale-tree error rather than
    // reporting a zero or an empty value.
    const parser = await newParser();
    const assertNothingPublished = (s) => {
      assert.equal(s.rootNode(), null);
      assert.throws(() => s.nodeCount(), StaleTreeError);
      assert.throws(() => s.snapshot(), StaleTreeError);
      assert.throws(() => s.lastInput(), StaleTreeError);
      assert.throws(() => s.lastPosition(), StaleTreeError);
    };
    const s = await parser.openSession();
    try {
      assertNothingPublished(s);
      s.parse("alpha:12");
      assert.ok(s.nodeCount() > 0);
    } finally {
      s.close();
    }
    // A parse that publishes nothing leaves the same answer behind: one
    // error is the limit, so the parser raises instead of recovering.
    const strict = await parser.openSession({ maxErrors: 1 });
    try {
      strict.parse("alpha:12");
      assert.equal(decode(strict.lastInput()), "alpha:12");
      assert.throws(() => strict.parse("alpha:"), GalleyError);
      assertNothingPublished(strict);
    } finally {
      strict.close();
    }
  });

  await test("use after close is not a stale tree", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    s.parse("alpha:12,beta:3");
    const root = s.rootNode();
    s.close();
    // The closed session has its own error: a tree being gone is a
    // different failure, and neither stands in for the other.
    for (const use of [() => root.text(), () => s.nodeCount(), () => s.rootNode(), () => s.snapshot()]) {
      let raised = null;
      try {
        use();
      } catch (error) {
        raised = error;
      }
      assert.ok(raised instanceof SessionClosedError, `${raised} is not the closed-session error`);
      assert.ok(!(raised instanceof StaleTreeError), `${raised} stands in for the stale-tree error`);
    }
  });

  await test("a stale node cannot edit the tree that replaced it", async () => {
    // The edit gate is the read gate: every edit carrying a parse-1 node
    // refuses, whichever node the other argument is, so a dead tree is
    // never edited by accident.
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      s.parse("alpha:12");
      const stale = s.rootNode();
      const staleChild = stale.firstChild();
      s.parse("alpha:12,beta:3");
      const fresh = s.rootNode();
      const freshChild = fresh.firstChild();
      for (const edit of [
        () => stale.cleanChildren(),
        () => stale.appendChildren(freshChild),
        () => fresh.appendChildren(staleChild),
        () => s.removeSelf(stale),
        () => s.removeSiblings(stale, 1),
        () => s.insertBefore(stale, freshChild),
        () => s.insertAfter(stale, freshChild),
        () => s.insertAfter(freshChild, stale),
        () => s.insertChildrenAt(stale, 0, freshChild),
        () => s.insertChildrenAt(freshChild, 0, staleChild),
        () => s.removeChildrenAt(stale, 0, 1),
      ]) {
        assert.throws(edit, StaleTreeError);
      }
      // The fresh tree is untouched by every refusal.
      assert.ok(s.childCount(fresh) > 0);
    } finally {
      s.close();
    }
  });

}
