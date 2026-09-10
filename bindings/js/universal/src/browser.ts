/**
 * Browser entry for the universal Galley JavaScript bindings: wasm only.
 *
 * The same surface as the default entry with the native steps absent —
 * no `node:` specifier exists anywhere in this module's import graph, so
 * bundlers resolve it without shims. Browsers cannot load native
 * libraries: `await init({ url })` (or `{ bytes }`) first, then use the
 * synchronous `Session` API. Register procedure hooks explicitly with
 * `installProcedures` from `@sanbus/galley-core`.
 */

import { init as initWasm, getWasmPort } from "@sanbus/galley-wasm/browser";
import type { FfiPort } from "@sanbus/galley-core";
import type { InitOptions } from "./loader.ts";

export * from "@sanbus/galley-core";
export {
  Session,
  initSync,
  getWasmPort,
  seedDefault,
  NeedInitError,
  wasmFileName,
  version,
  parserType,
  errorRecoveryMode,
  hasAst,
  hasProcedures,
  allowsNoAstTreeProcedures,
  sourceRetentionEnabled,
  hasPositionTracking,
  hasInputStreaming,
  usesVerbatim,
  stackOverflowRecoveryAvailable,
  symbolCount,
  variableCount,
  statusString,
  has_ast,
  has_procedures,
  has_position_tracking,
} from "@sanbus/galley-wasm/browser";
export type { SessionOptions, WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";
export type { InitOptions as WasmInitOptions } from "@sanbus/galley-wasm/browser";
// One options object: the browser entry reads the same `InitOptions`
// as the default entry (`wasmBytes`, `wasmPath` included).
export type { InitOptions };

/** A resolved backend: the port plus which leg of the chain served it. */
export interface BrowserBackend {
  port: FfiPort;
  backend: "wasm";
}

let ready: BrowserBackend | null = null;
let warned = false;

/**
 * Initialize the WebAssembly backend, caching the result. Browsers skip
 * native attempts (no FFI); the one-time notice names the cost. Option
 * names match the default entry: `wasmBytes` carries in-memory bytes,
 * `wasmPath` pins the module file.
 */
export async function init(options: InitOptions = {}): Promise<BrowserBackend> {
  const wasmPath = options.wasmPath ?? options.libraryPath;
  await initWasm({ libraryPath: wasmPath, url: options.url, bytes: options.wasmBytes });
  if (!options.quiet && !warned) {
    warned = true;
    console.warn(
      "galley: using the WebAssembly backend; throughput trails native codegen " +
        "(roughly three quarters). Silence with { quiet: true }.",
    );
  }
  ready = { port: getWasmPort(wasmPath), backend: "wasm" };
  return ready;
}

/** The initialized backend, or null when `init()` has not completed. */
export function currentBackend(): BrowserBackend | null {
  return ready;
}

/** Backend selected by the last `init()` (`"wasm"`, or null). */
export function backend(): "wasm" | null {
  return ready?.backend ?? null;
}

/** Test-only: clear cached resolution and the fallback notice. */
export function __resetLoader(): void {
  ready = null;
  warned = false;
}
