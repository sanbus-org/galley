/**
 * Node `Session`: the core session bound to the addon port.
 *
 * Installs the host-procedure dispatch for the session's library.
 */

import { Session as CoreSession } from "@sanbus/galley-core";
import type { SessionOptions } from "@sanbus/galley-core";
import { getNodePort } from "./ffi.ts";
import { ensureDispatchFor } from "./dispatch.ts";

export type { SessionOptions };

export class Session extends CoreSession {
  constructor(options: SessionOptions = {}) {
    const port = getNodePort(options.libraryPath);
    // Ensure host-procedure dispatch is installed for this library even if
    // the first Session is created before any installProcedure call.
    try {
      ensureDispatchFor(port.ffi, port);
    } catch {
      // Missing installer — stays no-op.
    }
    super(port, options);
  }
}
