/**
 * Bun `Session`: the core session bound to the `bun:ffi` port.
 *
 * Installs the host-procedure dispatch for the session's library (mirrors
 * Node's import-time shim setup); the installer is a no-op for libraries
 * built for C procedures.
 */

import { Session as CoreSession } from "@sanbus/galley-core";
import type { SessionOptions } from "@sanbus/galley-core";
import { getBunPort } from "./ffi.ts";
import { ensureDispatchFor } from "./dispatch.ts";

export type { SessionOptions };

export class Session extends CoreSession {
  constructor(options: SessionOptions = {}) {
    const port = getBunPort(options.libraryPath);
    try {
      ensureDispatchFor(port);
    } catch {
      // Missing installer — stays no-op.
    }
    super(port, options);
  }
}
