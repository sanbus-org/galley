/**
 * Deno procedure-dispatch installer.
 *
 * Owns the one `UnsafeCallback` every parser hook of a library re-enters:
 * it forwards (hook handle, hook index, arguments) to the port's
 * `hookDispatch`, which the core routes to the session that owns the
 * handle. The hook tables live in the core, one per session; this module
 * only bridges the native boundary, with one callback per port so two
 * workers (or two grammars) never share one.
 */

import type { DenoPort } from "./ffi.ts";

// Held to prevent GC: the callback must stay reachable for the port's life.
const callbacks = new WeakMap<DenoPort, unknown>();

/** Creates the port's callback and records its native address for `setSessionHooks`. */
export function installDispatch(port: DenoPort): void {
  const callback = new Deno.UnsafeCallback(
    { parameters: ["u64", "u32", "pointer"], result: "void" },
    (hookHandle, hookIndex, argsPtr) => {
      port.hookDispatch?.(Number(hookHandle), hookIndex as number, argsPtr);
    },
  );
  callbacks.set(port, callback);
  port.dispatchPointer = callback.pointer;
}
