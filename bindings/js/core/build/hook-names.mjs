/**
 * The shared hook-name scenarios, run by every runtime's suite against its
 * own parser factories.
 *
 * One behavior in every adapter: an install of a name the artifact does not
 * define raises (naming the name, and the `hook_` or `reduction_` hook it
 * likely meant); the list is the parser's own, so per-production hooks and
 * escaped terminal names install and fire, while Zig-only spellings and
 * helpers are not hooks; an artifact whose config disables procedures
 * defines no hooks, so every install raises while parsing still works; a
 * module scan warns once per name per artifact, only for hook-shaped
 * exports the artifact lacks; every hook receives the arguments object.
 *
 * `newParser` resolves a parser of the keyvalue fixture;
 * `newDisabledParser` resolves one built with `procedures = false`.
 */

export async function runHookNameScenarios({ test, assert, newParser, newDisabledParser }) {
  await test("installProcedure refuses a name the artifact does not define", async () => {
    const parser = await newParser();
    parser.clearProcedures();
    assert.throws(
      () => parser.installProcedure("reduction_Nonexistent", () => {}),
      { name: "RangeError", message: /does not define a hook named "reduction_Nonexistent"$/ },
    );
    const session = await parser.openSession();
    try {
      assert.throws(
        () => session.installProcedure("helperFunction", () => {}),
        { name: "RangeError", message: /does not define a hook named "helperFunction"$/ },
      );
      assert.deepEqual(session.listProcedures(), {});
    } finally {
      session.close();
    }
  });

  await test("an unknown name suggests the hook_ or reduction_ hook it likely meant", async () => {
    const parser = await newParser();
    assert.throws(
      () => parser.installProcedure("print", () => {}),
      { name: "RangeError", message: /did you mean "hook_print"\?/ },
    );
    assert.throws(
      () => parser.installProcedure("Pair", () => {}),
      { name: "RangeError", message: /did you mean "reduction_Pair"\?/ },
    );
  });

  await test("production and escaped terminal hooks install and fire", async () => {
    const parser = await newParser();
    parser.clearProcedures();
    const fired = [];
    const session = await parser.openSession();
    try {
      session.installProcedure("reduction_Pair_0", () => fired.push("Pair_0"));
      session.installProcedure("reduction_terminal__x58", () => fired.push(":"));
      session.installProcedure("reduction_generative_terminal_digit", () => fired.push("digit"));
      session.parse("alpha:12,beta:3");
    } finally {
      session.close();
    }
    assert.equal(fired.filter((entry) => entry === "Pair_0").length, 2);
    assert.equal(fired.filter((entry) => entry === ":").length, 2);
    assert.equal(fired.filter((entry) => entry === "digit").length, 3);
  });

  await test("Zig-only spellings and helpers are not hooks", async () => {
    const parser = await newParser();
    for (const name of ['reduction_":"', "reduction_digit", "reduction__AugmentedStart"]) {
      assert.throws(() => parser.installProcedure(name, () => {}), { name: "RangeError" }, name);
    }
  });

  await test("a no-procedures artifact defines no hooks to install", async () => {
    const parser = await newDisabledParser();
    assert.throws(
      () => parser.installProcedure("reduction", () => {}),
      { name: "RangeError", message: /defines no procedure hooks/ },
    );
    const session = await parser.openSession();
    try {
      assert.throws(
        () => session.installProcedure("reduction_Pair", () => {}),
        { name: "RangeError", message: /defines no procedure hooks/ },
      );
      assert.ok(session.parse("alpha:12") > 0);
    } finally {
      session.close();
    }
  });

  await test("scan warns only for hook-shaped exports the artifact lacks", async () => {
    const parser = await newParser();
    parser.clearProcedures();
    const original = console.warn;
    const lines = [];
    console.warn = (message) => lines.push(String(message));
    let installed = 0;
    try {
      installed = parser.installProcedures({
        reduction_Pair: () => {},
        reductionPair: () => {},
        hookTypo: () => {},
        hooky: () => {},
        myHelper: () => {},
      });
    } finally {
      console.warn = original;
    }
    assert.equal(installed, 1);
    const scans = lines.filter((line) => line.startsWith("galley: ignoring export"));
    assert.equal(scans.length, 2);
    assert.ok(scans.some((line) => line.includes('"reductionPair"') && line.includes("does not define it")));
    assert.ok(scans.some((line) => line.includes('"hookTypo"') && line.includes("does not define it")));
    assert.ok(!scans.some((line) => line.includes("hooky") || line.includes("myHelper")));
  });

  await test("unknown scan warnings are reported once per name per parser", async () => {
    const first = await newParser();
    const second = await newParser();
    first.clearProcedures();
    second.clearProcedures();
    const original = console.warn;
    const lines = [];
    console.warn = (message) => lines.push(String(message));
    const session = await first.openSession();
    try {
      first.installProcedures({ hookScopetest: () => {} });
      first.installProcedures({ hookScopetest: () => {} }); // re-scan: quiet
      session.installProcedures({ hookScopetest: () => {} }); // the parser's session: quiet
      session.installProcedures({ hookScopetest: () => {} }); // again: quiet
      session.installProcedures({ hookSessiononly: () => {} }); // a new name: reports
      session.installProcedures({ hookSessiononly: () => {} }); // again: quiet
      second.installProcedures({ hookScopetest: () => {} }); // other parser: reports
    } finally {
      session.close();
      console.warn = original;
    }
    const scans = lines.filter((line) => line.startsWith("galley: ignoring export"));
    assert.equal(scans.length, 3, JSON.stringify(scans));
    assert.equal(scans.filter((line) => line.includes('"hookScopetest"')).length, 2);
    assert.equal(scans.filter((line) => line.includes('"hookSessiononly"')).length, 1);
  });

  await test("a default-parameter hook receives the ProcedureArguments object", async () => {
    const parser = await newParser();
    parser.clearProcedures();
    let seen = "unset";
    parser.installProcedure("reduction_Pair", (args = null) => { seen = args; });
    const session = await parser.openSession();
    try {
      session.parse("alpha:12,beta:3");
    } finally {
      session.close();
    }
    assert.ok(seen !== null && typeof seen.currentNode === "function");
  });
}
