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

import { JSCallback, FFIType } from "bun:ffi";

import type { BunPort } from "./ffi.ts";

// Held to prevent GC: the callback must stay reachable for the port's life.
const callbacks = new WeakMap<BunPort, unknown>();

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
