/**
 * The shared hook-failure scenarios, run by every runtime's suite (node,
 * bun, deno, wasm) against its own session factory.
 *
 * A hook that throws aborts the parse: `parse` throws the binding's failure
 * with the thrown value as its `cause`, the failure carries the status and
 * the diagnostic snapshot of where the parse stopped, and nothing is
 * published. `newParser` resolves a parser of the keyvalue fixture;
 * `GalleyError`, `StaleTreeError`, `Status` and `Kind` come from the
 * runtime's own entry so identity checks hold.
 */

const SAMPLE = "alpha:12,beta:3";

export async function runHookFailureScenarios({ test, assert, newParser, GalleyError, StaleTreeError, Status, Kind }) {
  await test("a hook that throws aborts the parse and publishes nothing", async () => {
    const parser = await newParser();
    parser.clearProcedures();
    const session = await parser.openSession();
    try {
      session.parse(SAMPLE);
      const earlier = session.rootNode();
      assert.ok(earlier !== null);
      const boom = new Error("boom");
      const fired = [];
      session.installProcedure("reduction_Number", (args) => {
        fired.push(args.currentNode());
        throw boom;
      });
      let failure = null;
      try {
        session.parse(SAMPLE);
      } catch (error) {
        failure = error;
      }
      assert.ok(failure instanceof GalleyError);
      assert.equal(fired.length, 1);
      assert.equal(failure.cause, boom);
      assert.equal(failure.code, Status.ErrorHookFailed);
      assert.ok(failure.diagnostic !== null);
      assert.equal(failure.diagnostic.kind, Kind.Hook);
      assert.ok(failure.diagnostic.line >= 1 && failure.diagnostic.column >= 1);
      assert.ok(failure.message.includes("reduction_Number"));
      assert.equal(session.rootNode(), null);
      assert.throws(() => session.nodeCount(), StaleTreeError);
      assert.throws(() => fired[0].text(), StaleTreeError);
      assert.throws(() => earlier.text(), StaleTreeError);
    } finally {
      session.close();
    }
  });

  await test("a hook failure after a recovered syntax error reports the hook", async () => {
    const parser = await newParser();
    parser.clearProcedures();
    const session = await parser.openSession();
    try {
      session.installProcedure("reduction_Document", () => {
        throw new Error("late failure");
      });
      let failure = null;
      try {
        session.parse("alpha:12,beta@3");
      } catch (error) {
        failure = error;
      }
      assert.ok(failure instanceof GalleyError);
      assert.equal(failure.code, Status.ErrorHookFailed);
      assert.equal(failure.diagnostic.kind, Kind.Hook);
      assert.ok(failure.message.includes("HookError"));
      assert.ok(failure.diagnostic.message.includes("HookError"));
      assert.ok(!failure.diagnostic.message.includes("SyntaxError"));
      // eslint-disable-next-line no-control-regex
      assert.equal(failure.diagnostic.messageAnsi.replace(/\x1b\[[0-9;]*m/g, ""), failure.diagnostic.message);
    } finally {
      session.close();
    }
  });

  await test("a hook may throw any value, even undefined, and it is the cause", async () => {
    const parser = await newParser();
    parser.clearProcedures();
    const session = await parser.openSession();
    try {
      session.installProcedure("reduction_Number", () => {
        throw undefined;
      });
      let failure = null;
      try {
        session.parse(SAMPLE);
      } catch (error) {
        failure = error;
      }
      assert.ok(failure instanceof GalleyError);
      assert.equal(failure.code, Status.ErrorHookFailed);
      assert.ok("cause" in failure);
      assert.equal(failure.cause, undefined);
    } finally {
      session.close();
    }
  });

  await test("a session parses again after a hook aborted the parse", async () => {
    const parser = await newParser();
    parser.clearProcedures();
    const session = await parser.openSession();
    try {
      let calls = 0;
      session.installProcedure("reduction_Number", () => {
        calls += 1;
        if (calls === 1) throw new RangeError("first parse only");
      });
      assert.throws(
        () => session.parse(SAMPLE),
        (error) => error instanceof GalleyError && error.cause instanceof RangeError,
      );
      assert.equal(session.parse(SAMPLE), SAMPLE.length);
      assert.equal(calls, 3);
      const root = session.rootNode();
      assert.ok(root !== null);
      assert.equal(new TextDecoder().decode(root.text()), SAMPLE);
      assert.equal(session.diagnostic(), null);
    } finally {
      session.close();
    }
  });

  await test("a hook failure of a nested session stays with that session", async () => {
    const parser = await newParser();
    parser.clearProcedures();
    const session = await parser.openSession();
    try {
      const innerBoom = new Error("inner");
      const innerFailures = [];
      const outerSeen = [];
      let nested = false;
      session.installProcedure("reduction_Pair", (args) => {
        outerSeen.push(new TextDecoder().decode(args.currentNode().text()));
        if (nested) return;
        nested = true;
        const inner = parser.openSession();
        try {
          inner.installProcedure("reduction_Number", () => {
            throw innerBoom;
          });
          try {
            inner.parse("alpha:9");
          } catch (error) {
            innerFailures.push(error);
          }
        } finally {
          inner.close();
        }
      });
      assert.equal(session.parse(SAMPLE), SAMPLE.length);
      assert.deepEqual(outerSeen, ["alpha:12", "beta:3"]);
      assert.equal(innerFailures.length, 1);
      assert.equal(innerFailures[0].cause, innerBoom);
      assert.ok(session.rootNode() !== null);
    } finally {
      session.close();
    }
  });
}
