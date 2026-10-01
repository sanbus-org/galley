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
 * and `Status` come from the runtime's own entry so identity checks hold.
 */

export async function runGenerationScenarios({ test, assert, newParser, SessionClosedError, GalleyError, Status }) {
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

  await test("a hook node after a successful parse reads through the session and equals its node", async () => {
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
      try {
        for (const step of walker) {
          if (step.node.address === first.address) {
            found = step.node;
            break;
          }
        }
      } finally {
        walker.close();
      }
      assert.ok(found !== null);
      assert.ok(found.equals(first));
      assert.ok(first.equals(found));
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
      assert.ok(!firstRoot.equals(secondRoot));
      assert.ok(!secondRoot.equals(firstRoot));
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
        trace.push(["navigation", s.parent(kids[0]).equals(node) && s.nextSibling(kids[0]).equals(kids[1]) &&
          s.priorSibling(kids[1]).equals(kids[0]) && s.lastChild(node).equals(kids[count - 1]) && s.firstChild(node).equals(kids[0])]);
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

  await test("a walk inside a hook is refused, not empty", async () => {
    // Walkers exist only on the session door, which the core refuses while
    // a parse runs: a refused creation throws session in use, never the
    // null that means an invalid root.
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      s.parse("alpha:12");
      const previousRoot = s.rootNode();
      const codes = [];
      s.installProcedure("reduction_Pair", () => {
        try {
          s.walk(previousRoot);
        } catch (error) {
          codes.push(error instanceof GalleyError ? error.code : String(error));
        }
      });
      s.parse("alpha:12");
      assert.deepEqual(codes, [Status.ErrorSessionInUse]);
      s.clearProcedures();
      assert.equal(s.walk(2n ** 40n), null);
      const walker = s.walk(s.rootNode());
      assert.ok(walker !== null);
      walker.close();
    } finally {
      s.close();
    }
  });

  await test("a hook node equals the session node reached after the parse", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      const stashed = [];
      s.installProcedure("reduction_Pair", (args) => {
        stashed.push(args.currentNode());
      });
      s.parse("alpha:12");
      const pair = s.firstChild(s.firstChild(s.rootNode()));
      assert.ok(stashed[0].equals(pair));
    } finally {
      s.close();
    }
  });
}
