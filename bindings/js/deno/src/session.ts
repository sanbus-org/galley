/**
 * Deno `Session`: the core session bound to the `Deno.dlopen` port.
 *
 * Installs the host-procedure dispatch for the session's library; the
 * installer is a no-op for libraries built for C procedures.
 */

import { Session as CoreSession } from "@sanbus/galley-core";
import type { SessionOptions } from "@sanbus/galley-core";
import { getDenoPort } from "./ffi.ts";
import { ensureDispatchFor } from "./dispatch.ts";

export type { SessionOptions };

export class Session extends CoreSession {
  constructor(options: SessionOptions = {}) {
    const port = getDenoPort(options.libraryPath);
    try {
      ensureDispatchFor(port);
    } catch {
      // Missing installer — stays no-op.
    }
    super(port, options);
  }
}
