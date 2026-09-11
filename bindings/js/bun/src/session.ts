/**
 * Bun `Session`: the core session bound to the `bun:ffi` port.
 */

import { Session as CoreSession } from "@sanbus/galley-core";
import type { SessionOptions } from "@sanbus/galley-core";
import { getBunPort } from "./ffi.ts";

export type { SessionOptions };

export class Session extends CoreSession {
  constructor(options: SessionOptions = {}) {
    super(getBunPort(options.libraryPath), options);
  }
}
