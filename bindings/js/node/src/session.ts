/**
 * Node `Session`: the core session bound to the addon port.
 *
 * Created through `Session.fromDirectory`: the adapter loads its
 * standard-named library (plus the NAPI addon beside it) from the
 * language directory, and the directory's `procedures` module — if
 * any — into the new session's own hook registry, ahead of explicit
 * `procedures`. `Session.fromFile` opens an explicit library file
 * instead, scanning the file's own directory for `procedures`. The
 * constructor is private; the factories are synchronous (only the
 * universal entry and `fromUrl` need `async`).
 */

import { Session as CoreSession, checkArtifactPath, checkLanguagePath } from "@sanbus/galley-core";
import type { SessionOptions } from "@sanbus/galley-core";
import { getNodePort, getNodePortFromFile } from "./ffi.ts";
import { loadProcedures, loadProceduresForFile } from "./dispatch.ts";

export type { SessionOptions };

export class Session extends CoreSession {
  private constructor(port: ReturnType<typeof getNodePort>, options: SessionOptions, scannedProcedures: unknown = null) {
    super(port, options, scannedProcedures);
  }

  static fromDirectory(languagePath: string, options: SessionOptions = {}): Session {
    const directory = checkLanguagePath(languagePath, "galley: Session.fromDirectory");
    return new Session(getNodePort(directory), options, loadProcedures(directory));
  }

  static fromFile(filePath: string, options: SessionOptions = {}): Session {
    const file = checkArtifactPath(filePath, "galley: Session.fromFile");
    return new Session(getNodePortFromFile(file), options, loadProceduresForFile(file));
  }
}
