/**
 * Node `Session`: the core session bound to the addon port.
 */

import { Session as CoreSession } from "@sanbus/galley-core";
import type { SessionOptions } from "@sanbus/galley-core";
import { getNodePort } from "./ffi.ts";

export type { SessionOptions };

export class Session extends CoreSession {
  constructor(options: SessionOptions = {}) {
    super(getNodePort(options.libraryPath), options);
  }
}
