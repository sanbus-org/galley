/**
 * WebAssembly procedure-dispatch setup.
 *
 * Unlike the native adapters there is nothing to install: the wasm module
 * unconditionally imports `env.galley_js_dispatch`, which forwards every
 * parser hook to the core registry (unregistered names are no-ops there,
 * matching native semantics). This module only owns the `require()`-based
 * auto-scan of `procedures.*` in the language directory, mirroring the Node
 * adapter. Outside Node (browsers) the scan is skipped — register hooks
 * explicitly with `installProcedures` from `galley-js-core`.
 */

import { createRequire } from "node:module";
import * as path from "node:path";

import { installProcedures, listProcedures } from "galley-js-core";

let autoAttempted = false;

function isProcedureName(name: string): boolean {
  return name === "reduction" || name.startsWith("reduction_") || name.startsWith("hook_");
}

function isNode(): boolean {
  return (
    typeof process !== "undefined" &&
    typeof (process as unknown as { versions?: { node?: string } }).versions?.node === "string"
  );
}

export function ensureDispatch(wasmPath?: string): void {
  if (listProcedures().length > 0 || autoAttempted) return;
  autoAttempted = true;
  if (!isNode()) return;
  const require = createRequire(import.meta.url);
  const tryLoadModule = (modulePath: string): boolean => {
    try {
      const loadedModule = require(modulePath) as Record<string, unknown>;
      let hasHook = false;
      for (const [name, value] of Object.entries(loadedModule)) {
        if (typeof value !== "function" || !isProcedureName(name)) continue;
        hasHook = true;
        break;
      }
      if (hasHook) return installProcedures(loadedModule) > 0;
      const defaultExport = (loadedModule as Record<string, unknown>).default as
        | Record<string, unknown>
        | undefined;
      if (defaultExport && typeof defaultExport === "object") {
        return installProcedures(defaultExport) > 0;
      }
    } catch {}
    return false;
  };

  // One place: the directory holding the loaded module. Anything found
  // there belongs to this grammar; nothing else is even looked at.
  // Byte-fed modules ("<bytes>") have no directory: nothing to scan.
  if (!wasmPath || wasmPath === "<bytes>") return;
  const baseDirectory = path.dirname(path.resolve(wasmPath));
  const extensions = ["", ".js", ".ts"];
  for (const extension of extensions) {
    if (tryLoadModule(path.join(baseDirectory, `procedures${extension}`))) return;
  }
}
