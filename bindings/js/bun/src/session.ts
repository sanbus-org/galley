/**
 * Bun `Session`: the core session bound to the `bun:ffi` port.
 *
 * Installs the host-procedure dispatch for the session's library (mirrors
 * Node's import-time shim setup); the installer is a no-op for libraries
 * built for C procedures.
 */

import { Session as CoreSession } from "galley-js-core";
import type { SessionOptions } from "galley-js-core";
import { getBunPort } from "./ffi.js";
import { ensureDispatchFor } from "./dispatch.js";

export type { SessionOptions };

export class Session extends CoreSession {
  constructor(options: SessionOptions = {}) {
    const port = getBunPort(options.libraryPath);
    try {
      ensureDispatchFor(port);
    } catch {
      // installer missing (C build) — ignore.
    }
    super(port, options);
  }
}
