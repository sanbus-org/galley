/**
 * WebAssembly `Session`: the core session bound to the wasm port.
 *
 * Runs the adapter auto-scan for host procedures (a no-op outside Node or
 * when hooks are already registered); the guest import itself is always
 * wired at instantiation.
 */

import { Session as CoreSession } from "@sanbus/galley-core";
import type { SessionOptions } from "@sanbus/galley-core";
import { getWasmPort } from "./ffi.ts";
import { ensureDispatch } from "./dispatch.ts";

export type { SessionOptions };

export class Session extends CoreSession {
  constructor(options: SessionOptions = {}) {
    const port = getWasmPort(options.libraryPath);
    try {
      ensureDispatch(options.libraryPath ?? port.libraryPath);
    } catch {
      // auto-scan is best-effort; explicit installProcedures always works.
    }
    super(port, options);
  }
}
