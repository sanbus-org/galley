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
 * `newParser` resolves a parser of the keyvalue fixture; `SessionClosedError`
 * and `Status` come from the runtime's own entry so identity checks hold;
 * `collect` is that runtime's forced garbage collection, used by the
 * release scenario.
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

export async function runGenerationScenarios({ test, assert, newParser, SessionClosedError, GalleyError, Status, collect }) {
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
      const walker = s.walk(s.rootNode());
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

  await test("a hook node of a failed parse is refused afterwards", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      const stashed = [];
      s.installProcedure("reduction_Number", (args) => {
        stashed.push(args.currentNode());
      });
      assert.throws(() => s.parse("alpha:12,beta:"), GalleyError);
      assert.ok(stashed.length >= 1);
      assert.throws(() => stashed[0].text(), SessionClosedError);
      assert.throws(() => s.text(stashed[0]), SessionClosedError);
      s.clearProcedures();
      s.parse("alpha:12,beta:3");
      assert.throws(() => stashed[0].text(), SessionClosedError);
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
      assert.throws(() => firstRoot.text(), SessionClosedError);
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
        trace.push(["valid", s.nodeValid(node)]);
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
        // unlinkWrapper + insertChildrenAt
        const wrapper = s.lastChild(node);
        s.unlinkWrapper(wrapper);
        s.insertChildrenAt(node, s.childCount(node), wrapper);
        // promoteChildrenOverWrapper splices a wrapper's children in its
        // place; the call itself crossing the hook door is what is checked.
        s.promoteChildrenOverWrapper(s.lastChild(node));
        trace.push(["promote", true]);
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

  await test("a walk inside a hook equals the post-parse walk", async () => {
    // A walk created and stepped inside a hook goes through the parse's
    // own door over the in-flight tree; replayed after the parse
    // publishes from the same roots, each yields the identical sequence.
    // A raw address never reaches the walk at all — `walk` takes a node
    // and refuses anything else at entry.
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      const recorded = [];
      const hookRoots = [];
      s.installProcedure("reduction_Pair", (args) => {
        const node = args.currentNode();
        hookRoots.push(node);
        recorded.push([...s.walk(node)].map((step) => [step.node.address, step.depth]));
      });
      s.parse("alpha:12,beta:3");
      s.clearProcedures();
      assert.ok(recorded.length > 0);
      for (let index = 0; index < hookRoots.length; index++) {
        const replayed = [...s.walk(hookRoots[index])].map((step) => [step.node.address, step.depth]);
        assert.deepEqual(replayed, recorded[index]);
      }
      assert.throws(() => s.walk(2n ** 40n), TypeError);
      // walk() always hands back a walker, never null.
      assert.ok(s.walk(s.rootNode()) !== null);
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
        const full = [...s.walk(node)].map((step) => [step.node.address, step.depth, step.isSemanticError]);
        const pruned = [...s.walk(node, true)].map((step) => [step.node.address, step.depth]);
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

  await test("a walk step after removing the current node reports invalid node", async () => {
    // The step has no live position to advance from: invalid node, and
    // the cursor never moves past the failure.
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      s.parse("alpha:12,beta:3");
      const root = s.rootNode();
      const walker = s.walk(root);
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
      const baseline = [...s.walk(root)].map((step) => [step.node.address, step.depth]);
      assert.ok(baseline.length > 1);

      const walker = s.walk(root);
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
      const restored = [...s.walk(root)].map((step) => step.node.address);
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

  await test("a failed parse drops the intern table", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      s.parse("alpha:12,beta:3");
      const root = s.rootNode();
      const snap = s.snapshot();
      assert.ok(snap.node(root.address) === root);
      // The failure publishes nothing: the pre-failure snapshot's node()
      // never re-interns that generation — every call answers with a
      // fresh, uninterned handle, and each reads as invalidated.
      assert.throws(() => s.parse("gamma:"), (error) => error.code === Status.ErrorSyntax);
      const first = snap.node(root.address);
      const second = snap.node(root.address);
      assert.ok(first !== root);
      assert.ok(first !== second);
      assert.throws(() => first.text(), SessionClosedError);
      // The recovery parse interns its own generation afresh.
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

  await test("a failed published-generation read drops nothing and UNKNOWN never interns", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    // The fixture's default procedures read nodes while a parse runs,
    // which would re-adopt any table state this test sets up: only this
    // test's own hook may cross the gate.
    s.clearProcedures();
    const port = s.port;
    const realPublishedGeneration = port.publishedGeneration;
    const failingRead = () => ({ status: Status.ErrorSessionInUse, generation: 0n });
    let stashed = null;
    // Reading inside the hook interns the parse's own generation, so the
    // table holds a handle of exactly the parse whose published read fails.
    s.installProcedure("reduction_Pair", (args) => {
      if (stashed === null) stashed = args.currentNode();
    });
    try {
      s.parse("alpha:12,beta:3");
      const root = s.rootNode();
      const snap = s.snapshot();
      assert.ok(snap.node(root.address) === root);
      // A parse that succeeds while its published-generation read fails
      // stamps UNKNOWN: dropping on that difference would discard the
      // live table the hook just interned into.
      stashed = null;
      port.publishedGeneration = failingRead;
      s.parse("alpha:12");
      port.publishedGeneration = realPublishedGeneration;
      assert.ok(stashed !== null);
      const parseTree = s.snapshot();
      assert.ok(parseTree.node(stashed.address) === stashed);
      // With the hook silent (stashed is set), a real read moves the
      // published generation past the table and drops it — correctly:
      // the tree underneath stays live.
      s.parse("gamma:1");
      // The failing read then stamps UNKNOWN over the empty table, and
      // the snapshot's UNKNOWN node() must never make the table adopt
      // it — repeated reads stay fresh handles.
      port.publishedGeneration = failingRead;
      s.parse("alpha:12");
      const unknownSnap = s.snapshot();
      assert.ok(unknownSnap.count > 0);
      assert.ok(unknownSnap.node(0) !== unknownSnap.node(0));
      // Restoring the read lets the next node adopt the live generation.
      port.publishedGeneration = realPublishedGeneration;
      const live = s.rootNode();
      assert.ok(live !== null);
      assert.ok(s.snapshot().node(live.address) === live);
    } finally {
      port.publishedGeneration = realPublishedGeneration;
      s.close();
    }
  });
}
