/**
 * Node procedure-dispatch installer.
 *
 * Owns the one NAPI callback the addon re-enters for every parser hook of
 * a library: it forwards (hook handle, hook index, arguments) to the
 * port's `hookDispatch`, which the core routes to the session that owns
 * the handle. The hook tables live in the core, one per session; this
 * module only bridges the native boundary, with one callback per loaded
 * library so two grammars in one process never share a port.
 */

import * as path from "node:path";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);

import { loadProceduresModule } from "@sanbus/galley-core/internal";
import type { NodePort } from "./ffi.ts";

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

/**
 * Hands the addon the callback its parse frames re-enter. The addon keeps
 * a reference to it for the library's lifetime.
 */
export function installDispatch(port: NodePort): void {
  port.ffi.api.install_dispatch((hookHandle, hookIndex, args) => {
    port.hookDispatch?.(hookHandle, hookIndex, args);
  });
}
