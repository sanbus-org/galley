/**
 * WebAssembly procedure-dispatch setup.
 *
 * Unlike the native adapters there is nothing to install: the wasm module
 * unconditionally imports `env.galley_js_dispatch_id`, which forwards every
 * parser hook ID to the core registry (unregistered names are no-ops there,
 * matching native semantics). The Node entry wires the `require()`-based
 * auto-scan of `procedures.*` in the language directory (see `files.ts`),
 * mirroring the Node adapter. Outside Node (browsers) the scan is skipped
 * — register hooks explicitly with `installProcedures` from
 * `@sanbus/galley-core`.
 */

import { listProcedures } from "@sanbus/galley-core";

let autoAttempted = false;
let dirScanner: ((wasmPath: string | undefined) => void) | null = null;

/**
 * The Node entry wires the language-directory auto-scan (`files.ts`);
 * browsers leave it unset and register hooks explicitly with
 * `installProcedures` from `@sanbus/galley-core`. The unset scanner is
 * the capability check: no runtime predicate needed (Deno reports a
 * `process.versions.node` string, so `isNode()` never excluded it
 * anyway).
 */
export function seedDirScanner(scanner: (wasmPath: string | undefined) => void): void {
  dirScanner = scanner;
}

export function ensureDispatch(wasmPath?: string): void {
  if (listProcedures().length > 0 || autoAttempted) return;
  autoAttempted = true;
  try {
    dirScanner?.(wasmPath);
  } catch {
    // Missing installer — stays no-op.
  }
}
