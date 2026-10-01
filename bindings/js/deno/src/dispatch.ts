/**
 * Deno procedure-dispatch installer.
 *
 * Owns the one `UnsafeCallback` every parser hook of a library re-enters:
 * it forwards (hook handle, hook index, arguments) to the port's
 * `hookDispatch`, which the core routes to the session that owns the
 * handle. The hook tables live in the core, one per session; this module
 * only bridges the native boundary, with one callback per port so two
 * workers (or two grammars) never share one. Deno consumers register hooks
 * explicitly (pass `procedures` to the session): there is no synchronous
 * module scan on this runtime.
 */

import { noteSkippedScan } from "@sanbus/galley-core/internal";
import type { DenoPort } from "./ffi.ts";

// Held to prevent GC: the callback must stay reachable for the port's life.
const callbacks = new WeakMap<DenoPort, unknown>();

/**
 * Deno has no synchronous module loader, so there is nothing to scan:
 * always null. Exported for a uniform adapter surface (see the
 * universal loader); Deno sessions take `procedures` explicitly.
 */
export function loadProcedures(_languagePath: string): Record<string, unknown> | null {
  return null;
}

function scanJoin(directory: string, file: string): string {
  return directory.endsWith("/") ? directory + file : `${directory}/${file}`;
}

/**
 * Stat probe for a `procedures` file Deno cannot auto-load: returns the
 * found path, or null. Powers the skipped-scan warning (and the
 * universal loader's); loading itself stays explicit.
 */
function probeProceduresFile(directory: string): string | null {
  for (const file of ["procedures", "procedures.js", "procedures.ts"]) {
    const candidate = scanJoin(directory, file);
    try {
      Deno.statSync(candidate);
      return candidate;
    } catch {
      // Absent or unreadable: try the next name.
    }
  }
  return null;
}

/** Procedures file in a language directory, if one is there. */
export function findProceduresFile(directory: string): string | null {
  return probeProceduresFile(directory);
}

/** Warn for a directory open without explicit `procedures`. */
export function warnIfProceduresSkipped(directory: string, explicit: unknown): void {
  noteSkippedScan(findProceduresFile(directory), explicit);
}

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
