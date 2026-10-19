/**
 * The shared session-options scenarios, run by every runtime's suite (node,
 * deno, bun, wasm) against its own session factory.
 *
 * Hosts keep no option defaults: a value the caller gives crosses to the
 * core's own setter, a value outside the option's domain comes back as this
 * host's invalid-argument error before any session exists, and a key left
 * out makes no call at all. `runOptionScenarios` drives that through the
 * public session factory; `runOptionSeamScenarios` observes the
 * construction crossing directly on a recording port, so "only the keys the
 * caller gave are set" and "the options object is destroyed on every path"
 * are asserted rather than assumed.
 *
 * `newParser` resolves a parser of the keyvalue fixture; `Parser`,
 * `GalleyError` and `Status` come from the runtime's own entry so identity
 * checks hold. `refusedCap` is the one target-specific refusal: a count the
 * target cannot hold (wasm32 passes 2n ** 64n - 1n; native targets hold any
 * u64 and pass null).
 */

const FIRST = "alpha:12,beta:3";

export async function runOptionScenarios({ test, assert, newParser, GalleyError, Status, refusedCap = null }) {
  /** Opens with `options`, expecting the invalid-argument refusal. */
  async function expectRefused(parser, options) {
    let refusal = null;
    try {
      const s = await parser.openSession(options);
      s.close();
    } catch (error) {
      refusal = error;
    }
    const shape = Object.entries(options).map(([key, value]) => `${key}=${value}`).join(", ");
    assert.ok(refusal instanceof GalleyError, `expected a refusal for ${shape}`);
    assert.equal(refusal.code, Status.ErrorInvalidArgument, `expected invalid argument for ${shape}`);
  }

  await test("a refused option value is invalid argument", async () => {
    // A value outside one option's domain, per option: the setter refuses,
    // the session is never created, and the refusal surfaces as this host's
    // invalid-argument error.
    const parser = await newParser();
    const refusals = [
      { maxErrors: 0 },
      { maxErrors: -1 },
      { recoveryWindow: 0 },
      { verbosity: -1 },
      { syntaxErrorStackDepth: 65 },
      { astPreallocationRatio: -1 },
      // The bun adapter answers NaN itself: bun:ffi sends NaN as 0.0 (Bun 1.3).
      { astPreallocationRatio: Number.NaN },
      { astPreallocationRatio: Number.POSITIVE_INFINITY },
    ];
    if (!parser.stackOverflowRecoveryAvailable()) refusals.push({ stackOverflowRecovery: true });
    if (refusedCap !== null) refusals.push({ astPreallocationCap: refusedCap });
    for (const options of refusals) await expectRefused(parser, options);
    // The refusals leave the parser usable.
    const s = await parser.openSession();
    try {
      s.parse(FIRST);
    } finally {
      s.close();
    }
  });

  await test("explicit option values open a session that parses", async () => {
    // Every tunable at once, including the two zeroes that are valid: ratio
    // 0 (no scaled contribution) and an explicit 0 stack depth.
    const parser = await newParser();
    const s = await parser.openSession({
      maxErrors: 3,
      recoveryWindow: 50,
      stackOverflowRecovery: false,
      syntaxErrorStackDepth: 0,
      verbosity: 0,
      astPreallocationRatio: 0,
      astPreallocationCap: 4096,
    });
    try {
      assert.ok(s.parse(FIRST) > 0);
    } finally {
      s.close();
    }
    // The cap also crosses as a BigInt.
    const wide = await parser.openSession({ astPreallocationCap: 4096n });
    try {
      assert.ok(wide.parse(FIRST) > 0);
    } finally {
      wide.close();
    }
  });

  await test("no options opens a session that parses", async () => {
    // An omitted bag and an empty bag both open on the core's defaults.
    const parser = await newParser();
    for (const options of [undefined, {}]) {
      const s = options === undefined ? await parser.openSession() : await parser.openSession(options);
      try {
        assert.ok(s.parse(FIRST) > 0);
      } finally {
        s.close();
      }
    }
  });
}

export async function runOptionSeamScenarios({ test, assert, Parser, GalleyError, Status }) {
  // A port recording the construction crossing: which setters ran, with
  // which values, and when the native object was destroyed.
  function recordingPort(calls, createStatus = 0) {
    const port = {
      createOptions() {
        calls.push("createOptions");
        return { status: 0, handle: { kind: "options" } };
      },
      destroyOptions() {
        calls.push("destroyOptions");
        return 0;
      },
      setMaxErrors(_options, value) {
        calls.push(["setMaxErrors", value]);
        return 0;
      },
      setRecoveryWindow(_options, value) {
        calls.push(["setRecoveryWindow", value]);
        return 0;
      },
      setStackOverflowRecovery(_options, value) {
        calls.push(["setStackOverflowRecovery", value]);
        return 0;
      },
      setSyntaxErrorStackDepth(_options, value) {
        calls.push(["setSyntaxErrorStackDepth", value]);
        return 0;
      },
      setVerbosity(_options, value) {
        calls.push(["setVerbosity", value]);
        return 0;
      },
      setAstPreallocationRatio(_options, value) {
        calls.push(["setAstPreallocationRatio", value]);
        return 0;
      },
      setAstPreallocationCap(_options, value) {
        calls.push(["setAstPreallocationCap", value]);
        return 0;
      },
      createSession() {
        calls.push("createSession");
        if (createStatus < 0) return { status: createStatus, handle: null };
        return { status: 0, handle: { kind: "session" } };
      },
      destroySession() {
        calls.push("destroySession");
        return 0;
      },
      hookNames() {
        return [];
      },
      setSessionHooks() {
        return 0;
      },
      hasProcedures() {
        return false;
      },
      statusString() {
        return null;
      },
      session: {},
    };
    return port;
  }

  await test("only the keys the caller gave reach the options object", async () => {
    // One setter per present key, in a fixed order, and none for a key left
    // out: the object crosses the seam exactly as the caller shaped it.
    const calls = [];
    const parser = new Parser(recordingPort(calls));
    const s = parser.openSession({ verbosity: 2, stackOverflowRecovery: true, astPreallocationCap: 4096 });
    assert.deepEqual(calls, [
      "createOptions",
      ["setStackOverflowRecovery", 1],
      ["setVerbosity", 2],
      ["setAstPreallocationCap", 4096n],
      "createSession",
      "destroyOptions",
    ]);
    s.close();
    assert.equal(calls[calls.length - 1], "destroySession");
  });

  await test("an empty bag sets nothing", async () => {
    const calls = [];
    const parser = new Parser(recordingPort(calls));
    const s = parser.openSession({});
    assert.deepEqual(calls, ["createOptions", "createSession", "destroyOptions"]);
    s.close();
  });

  await test("a refused setting destroys the object and creates no session", async () => {
    const calls = [];
    const port = recordingPort(calls);
    port.setMaxErrors = (_options, value) => {
      calls.push(["setMaxErrors", value]);
      return Status.ErrorInvalidArgument;
    };
    const parser = new Parser(port);
    let refusal = null;
    try {
      parser.openSession({ maxErrors: 0 });
    } catch (error) {
      refusal = error;
    }
    assert.ok(refusal instanceof GalleyError);
    assert.equal(refusal.code, Status.ErrorInvalidArgument);
    assert.deepEqual(calls, ["createOptions", ["setMaxErrors", 0], "destroyOptions"]);
  });

  await test("a refused session create still destroys the object", async () => {
    const calls = [];
    const parser = new Parser(recordingPort(calls, Status.ErrorOutOfMemory));
    let refusal = null;
    try {
      parser.openSession();
    } catch (error) {
      refusal = error;
    }
    assert.ok(refusal instanceof GalleyError);
    assert.equal(refusal.code, Status.ErrorOutOfMemory);
    assert.deepEqual(calls, ["createOptions", "createSession", "destroyOptions"]);
  });
}
