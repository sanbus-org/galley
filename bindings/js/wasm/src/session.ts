/**
 * WebAssembly `Session`: the core session bound to the wasm port.
 */

import { Session as CoreSession } from "@sanbus/galley-core";
import type { SessionOptions } from "@sanbus/galley-core";
import { getWasmPort } from "./ffi.ts";

export type { SessionOptions };

export class Session extends CoreSession {
  constructor(options: SessionOptions = {}) {
    super(getWasmPort(options.libraryPath), options);
  }
}
