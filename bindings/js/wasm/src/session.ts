/**
 * WebAssembly `Session`: the core session bound to the wasm port.
 *
 * Created through async factories — `fromBytes` and `fromUrl` here;
 * the Node entry (`index.ts`) adds `fromDirectory`, which needs the
 * filesystem the browser entry never sees. Factories are async so
 * every JS entry shares one creation shape, and a factory either
 * resolves a usable session or rejects: there is no unready state.
 * The directory's `procedures` module, where the runtime can load it,
 * lands in the new session's own hook registry ahead of explicit
 * `procedures`.
 */

import { Session as CoreSession } from "@sanbus/galley-core";
import type { FfiPort, SessionOptions } from "@sanbus/galley-core";
import { portFromBytes, portFromUrl } from "./ffi.ts";

export type { SessionOptions };

export class Session extends CoreSession {
  private constructor(port: FfiPort, options: SessionOptions = {}, scannedProcedures: unknown = null) {
    super(port, options, scannedProcedures);
  }

  static async fromBytes(bytes: Uint8Array, options: SessionOptions = {}): Promise<Session> {
    return new Session(await portFromBytes(bytes), options);
  }

  static async fromUrl(url: string | URL, options: SessionOptions = {}): Promise<Session> {
    return new Session(await portFromUrl(url), options);
  }
}
