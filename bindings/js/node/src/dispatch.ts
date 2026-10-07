/**
 * Node procedure-dispatch installer.
 *
 * Owns the one NAPI callback the addon re-enters for every parser hook of
 * a library: it forwards (hook handle, hook index, hook ticket) to the
 * port's `hookDispatch`, which the core routes to the session that owns
 * the handle. The hook tables live in the core, one per session; this
 * module only bridges the native boundary, with one callback per loaded
 * library so two grammars in one process never share a port.
 */

import type { NodePort } from "./ffi.ts";

/**
 * Hands the addon the callback its parse frames re-enter. The addon keeps
 * a reference to it for the library's lifetime.
 */
export function installDispatch(port: NodePort): void {
  port.ffi.api.install_dispatch((hookHandle, hookIndex, hook) => {
    port.hookDispatch?.(hookHandle, hookIndex, hook);
  });
}
