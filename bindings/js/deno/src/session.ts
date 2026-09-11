/**
 * Deno `Session`: the core session bound to the `Deno.dlopen` port.
 */

import { Session as CoreSession } from "@sanbus/galley-core";
import type { SessionOptions } from "@sanbus/galley-core";
import { getDenoPort } from "./ffi.ts";

export type { SessionOptions };

export class Session extends CoreSession {
  constructor(options: SessionOptions = {}) {
    super(getDenoPort(options.libraryPath), options);
  }
}
