/**
 * Forced full garbage collection — one implementation shared by every
 * runtime's suite (node, wasm, bun, deno): the release scenario needs a
 * real collection wherever it runs.
 *
 * - Bun provides `Bun.gc`.
 * - Deno's suite runs through `deno task test`, which passes
 *   `--v8-flags=--expose-gc`, leaving `globalThis.gc`.
 * - node (and wasm under node) expose `gc` in a fresh VM context after
 *   flipping `--expose-gc` at runtime; a runtime where none of these
 *   lands says so instead of silently skipping the collection.
 */
let forcedGc;

if (typeof Bun !== "undefined" && typeof Bun.gc === "function") {
  forcedGc = () => {
    Bun.gc(true);
    Bun.gc(true);
  };
} else if (typeof globalThis.gc === "function") {
  const gc = globalThis.gc;
  forcedGc = () => {
    gc();
    gc();
  };
} else {
  try {
    const v8 = await import("node:v8");
    const vm = await import("node:vm");
    v8.setFlagsFromString("--expose-gc");
    const gc = vm.runInNewContext("gc");
    v8.setFlagsFromString("--no-expose-gc");
    forcedGc = () => {
      gc();
      gc();
    };
  } catch {
    throw new Error(
      "galley: forced gc unavailable — run the suite through its test command " +
        "(`deno task test` passes --v8-flags=--expose-gc)",
    );
  }
}

/** Runs one forced full collection (twice, so weak refs settle). */
export function collect() {
  forcedGc();
}
