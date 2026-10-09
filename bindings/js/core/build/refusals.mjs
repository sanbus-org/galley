/**
 * The shared refusal and borrowed-memory scenarios, run by every runtime's
 * suite (node, bun, deno, wasm) against its own session factory.
 *
 * Every refusal raises, in every build: a hook's arguments are valid only
 * while the hook runs and the core refuses a call made with the ticket of a
 * hook that has returned; what describes a finished parse is refused inside a
 * hook with `session in use`, never answered with 0; a walker belongs to the
 * parse of the tree it was created over, finished or not. Text and input the
 * core returns are borrowed until the next parse, so every accessor must copy:
 * each read below is kept across parses that rewrite the memory it came from.
 *
 * `newParser` resolves a parser of the keyvalue fixture; `GalleyError`,
 * `StaleTreeError` and `Status` come from the runtime's own entry so identity
 * checks hold.
 */

const FIRST = "alpha:12,beta:3";
// Same length as FIRST, so each one lands in a buffer FIRST used: the session
// reuses two input buffers, and the third parse after a read rewrites the
// memory the read came from.
const CHURN = ["qqqqq:88,wwww:7", "xxxxx:77,yyyy:6", "ppppp:66,rrrr:5"];

export async function runRefusalScenarios({ test, assert, newParser, GalleyError, StaleTreeError, Status }) {
  const decode = (bytes) => new TextDecoder().decode(bytes);

  function churn(s) {
    for (const text of CHURN) s.parse(text);
  }

  /** What a stashed ProcedureArguments can do, one closure per capability. */
  function uses(args, node) {
    return [
      () => args.currentLine(),
      () => args.currentColumn(),
      () => args.currentNode(),
      () => args.dropSelf(),
      () => args.dropChildren(),
      () => args.dropIfEmpty(),
      () => args.replaceWithChildren(),
      () => args.reportSemanticError("late"),
      () => args.setCurrentNode(node),
    ];
  }

  function assertStaleHook(error) {
    assert.ok(error instanceof GalleyError);
    assert.equal(error.code, Status.ErrorStaleHook);
    assert.ok(!(error instanceof StaleTreeError));
    return true;
  }

  await test("procedure arguments die with their hook", async () => {
    // The core refuses every call made with a hook that has returned: from a
    // later hook of the same parse and after the parse alike. The object
    // keeps no expiry flag of its own.
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      let first = null;
      let last = null;
      const during = [];
      s.installProcedure("reduction_Pair", (args) => {
        if (first === null) first = args;
      });
      s.installProcedure("reduction_Document", (args) => {
        last = args;
        const node = args.currentNode();
        for (const use of uses(first, node)) {
          try {
            use();
            during.push(null);
          } catch (error) {
            during.push(error);
          }
        }
      });
      s.parse(FIRST);
      const calls = uses(first, null).length;
      assert.equal(during.length, calls);
      for (const error of during) assertStaleHook(error);
      const root = s.rootNode();
      for (const args of [first, last]) {
        for (const use of uses(args, root)) assert.throws(use, assertStaleHook);
      }
      assert.equal(decode(root.text()), FIRST);
    } finally {
      s.close();
    }
  });

  await test("a refused call with returned arguments changes nothing", async () => {
    // drop_self through the first Pair's arguments, made from a later Pair
    // hook, is refused and cannot drop that hook's node.
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      let first = null;
      const refusals = [];
      s.installProcedure("reduction_Pair", (args) => {
        if (first === null) {
          first = args;
          return;
        }
        try {
          first.dropSelf();
        } catch (error) {
          refusals.push(error);
        }
      });
      s.parse(FIRST);
      assert.equal(refusals.length, 1);
      assertStaleHook(refusals[0]);
      const pairs = [...s.rootNode().walk()]
        .filter((step) => step.node.symbolName() === "Pair")
        .map((step) => decode(step.node.text()));
      assert.deepEqual(pairs, ["alpha:12", "beta:3"]);
    } finally {
      s.close();
    }
  });

  await test("a message override change inside a hook is refused and changes nothing", async () => {
    // The parse reads the override table, so a change made from one of its
    // hooks is `session in use`, never absorbed; with no parse running the
    // same call works and takes effect.
    const parser = await newParser();
    const s = await parser.openSession();
    const text = "expected digits here";
    const messageOfBrokenParse = () => {
      try {
        s.parse("alpha:");
      } catch (error) {
        return error.diagnostic.message;
      }
      assert.fail("the broken sample must raise");
    };
    try {
      const refusals = [];
      s.installProcedure("reduction_Document", () => {
        try {
          s.setMessageOverride("Number", text);
          refusals.push(null);
        } catch (error) {
          refusals.push(error);
        }
      });
      s.parse(FIRST);
      assert.equal(refusals.length, 1);
      assert.ok(refusals[0] instanceof GalleyError);
      assert.equal(refusals[0].code, Status.ErrorSessionInUse);
      s.clearProcedures();
      assert.ok(!messageOfBrokenParse().includes(text));
      s.setMessageOverride("Number", text);
      assert.ok(messageOfBrokenParse().includes(text));
    } finally {
      s.close();
    }
  });

  await test("parsing copies the input", async () => {
    // The caller may overwrite its buffer once parse returns.
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      const buffer = new TextEncoder().encode(FIRST);
      s.parse(buffer);
      buffer.fill(0x5a);
      assert.equal(decode(s.lastInput()), FIRST);
      assert.equal(decode(s.rootNode().text()), FIRST);
    } finally {
      s.close();
    }
  });

  await test("finished-parse queries are refused inside a hook", async () => {
    // Inside a hook (this session, this thread) nothing that describes a
    // finished parse answers: not before the first parse publishes, not with
    // a tree published, never 0 or empty. "Session in use" comes first and is
    // not a stale tree.
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      const reads = {
        nodeCapacity: () => s.nodeCapacity(),
        nodeCount: () => s.nodeCount(),
        snapshot: () => s.snapshot(),
        lastInput: () => s.lastInput(),
        lastPosition: () => s.lastPosition(),
        rootNode: () => s.rootNode(),
      };
      let outcomes = [];
      s.installProcedure("reduction_Document", () => {
        outcomes = Object.entries(reads).map(([name, read]) => {
          try {
            read();
            return [name, "answered"];
          } catch (error) {
            return [name, error instanceof StaleTreeError ? "stale" : error.code];
          }
        });
      });
      const expected = Object.keys(reads).map((name) => [name, Status.ErrorSessionInUse]);
      for (let attempt = 0; attempt < 2; attempt++) {
        // Nothing published, then a tree published.
        s.parse(FIRST);
        assert.deepEqual(outcomes, expected, `attempt ${attempt}`);
      }
    } finally {
      s.close();
    }
  });

  await test("a completed walker raises stale tree after a reparse", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      s.parse(FIRST);
      const walker = s.rootNode().walk();
      assert.ok([...walker].length > 0);
      // A finished walk is still answered by the core: "done" only while its
      // tree is live, the stale-tree failure once it is not.
      assert.equal(walker.next().done, true);
      s.parse(FIRST);
      for (let attempt = 0; attempt < 2; attempt++) {
        assert.throws(() => walker.next(), (error) => error instanceof StaleTreeError);
      }
    } finally {
      s.close();
    }
  });

  await test("node text, names and input are copies that survive later parses", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      s.parse(FIRST);
      const nodes = [...s.rootNode().walk()].map((step) => step.node);
      const texts = nodes.map((node) => node.text());
      const names = nodes.map((node) => node.symbolNameBytes());
      const viaSession = nodes.map((node) => s.text(node));
      const input = s.lastInput();
      churn(s);
      assert.equal(decode(s.lastInput()), CHURN[CHURN.length - 1]);
      assert.equal(decode(input), FIRST);
      assert.equal(decode(texts[0]), FIRST);
      assert.ok(texts.some((text) => decode(text) === "alpha:12"));
      assert.ok(texts.some((text) => decode(text) === "beta:3"));
      assert.deepEqual(viaSession.map(decode), texts.map(decode));
      assert.equal(names.filter((name) => decode(name) === "Pair").length, 2);
    } finally {
      s.close();
    }
  });

  await test("text read inside a hook is a copy", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      const seen = [];
      s.installProcedure("reduction_Pair", (args) => {
        const node = args.currentNode();
        seen.push([node.text(), node.symbolNameBytes()]);
      });
      s.parse(FIRST);
      churn(s);
      assert.deepEqual(
        seen.slice(0, 2).map(([text, name]) => [decode(text), decode(name)]),
        [["alpha:12", "Pair"], ["beta:3", "Pair"]],
      );
    } finally {
      s.close();
    }
  });

  await test("diagnostics are copies that survive later parses", async () => {
    const parser = await newParser();
    const s = await parser.openSession();
    try {
      let failure = null;
      try {
        s.parse("alpha:");
      } catch (error) {
        failure = error;
      }
      assert.ok(failure instanceof GalleyError && failure.diagnostic !== null);
      const current = s.diagnostic();
      const recorded = s.diagnostics();
      const fields = (d) =>
        JSON.stringify({
          message: d.message,
          messageAnsi: d.messageAnsi,
          unexpected: d.unexpectedToken === null ? null : decode(d.unexpectedToken),
          expected: d.expectedTokens.map(decode),
          context: d.context,
          semantic: d.semantic,
          recoveryTerminal: d.recoveryTerminal === null ? null : decode(d.recoveryTerminal),
          recoveryLhs: d.recoveryLhsVariable,
          recoveryProduction: d.recoveryProduction,
          recoveryOccurrence: d.recoveryOccurrence,
        });
      const snapshot = () => [fields(failure.diagnostic), fields(current), ...recorded.map(fields)];
      const before = snapshot();
      assert.ok(failure.diagnostic.expectedTokens.length > 0);
      // Failures of the same shape rewrite the input buffers and the rendered
      // message; successes release the diagnostic memory.
      for (const text of ["beta:?", "gamma:", FIRST, "delta:", FIRST]) {
        try {
          s.parse(text);
        } catch {
          // a failing parse is the point
        }
      }
      assert.deepEqual(snapshot(), before);
    } finally {
      s.close();
    }
  });
}
