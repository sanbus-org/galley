/**
 * Node-only file and module access for the WebAssembly adapter.
 *
 * Imported exclusively by the Node entry (`index.ts`), never by the
 * browser entry (`browser.ts`): every `node:` specifier in this package
 * lives in this one module, so a bundler resolving the `browser` export
 * condition never sees them. `ffi.ts` and `dispatch.ts` reach this
 * module only through the seeds wired in `index.ts`.
 */

import { createRequire } from "node:module";
import * as fs from "node:fs";
import * as path from "node:path";
import process from "node:process";

import { installProcedures } from "@sanbus/galley-core";
import type { FileIo } from "./ffi.ts";

/** `FileIo` over the real filesystem and process environment. */
export const nodeFileIo: FileIo = {
  existsSync(localPath: string): boolean {
    try {
      fs.accessSync(localPath);
      return true;
    } catch {
      return false;
    }
  },
  readFile(localPath: string): Uint8Array {
    return new Uint8Array(fs.readFileSync(localPath));
  },
  resolvePath(candidate: string): string {
    return path.resolve(candidate);
  },
  getenv(name: string): string | undefined {
    return process.env[name];
  },
};

function isProcedureName(name: string): boolean {
  return name === "reduction" || name.startsWith("reduction_") || name.startsWith("hook_");
}

function tryLoadModule(
  require: (modulePath: string) => unknown,
  modulePath: string,
): boolean {
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
}

/**
 * `require()`-based auto-scan of `procedures.*` in the directory holding
 * the loaded module. Anything found there belongs to this grammar;
 * nothing else is even looked at. Byte-fed modules ("<bytes>") have no
 * directory: nothing to scan.
 */
export function scanLanguageDir(wasmPath: string | undefined): void {
  if (!wasmPath || wasmPath === "<bytes>") return;
  const require = createRequire(import.meta.url);
  const baseDirectory = path.dirname(path.resolve(wasmPath));
  for (const extension of ["", ".js", ".ts"]) {
    if (tryLoadModule(require, path.join(baseDirectory, `procedures${extension}`))) return;
  }
}
