/**
 * Bun procedure-dispatch installer.
 *
 * Owns the one `JSCallback` every parser hook of a library re-enters: it
 * forwards (hook handle, hook index, arguments) to the port's
 * `hookDispatch`, which the core routes to the session that owns the
 * handle. The hook tables live in the core, one per session; this module
 * only bridges the native boundary, with one callback per port so two
 * workers (or two grammars) never share one.
 */

import { createRequire } from "node:module";
import * as path from "node:path";
import { JSCallback, FFIType } from "bun:ffi";

import { loadProceduresModule } from "@sanbus/galley-core/internal";
import type { BunPort } from "./ffi.ts";

const require = createRequire(import.meta.url);
// Held to prevent GC: the callback must stay reachable for the port's life.
const callbacks = new WeakMap<BunPort, unknown>();

/**
 * Synchronously loads the language directory's `procedures` module, if
 * any. Returns the module for the session to install into its own
 * registry; never touches another session's hooks.
 */
export function loadProcedures(languagePath: string): Record<string, unknown> | null {
  return loadProceduresModule(
    (specifier) => require(specifier) as unknown,
    path.join,
    languagePath,
  );
}

/** Creates the port's callback and records its native address for `setSessionHooks`. */
export function installDispatch(port: BunPort): void {
  const callback = new JSCallback(
    (hookHandle: bigint, hookIndex: number, argsPtr: number) => {
      port.hookDispatch?.(Number(hookHandle), hookIndex, argsPtr);
    },
    { args: [FFIType.u64, FFIType.u32, FFIType.ptr], returns: FFIType.void },
  );
  callbacks.set(port, callback);
  port.dispatchPointer = callback.ptr as number;
}
