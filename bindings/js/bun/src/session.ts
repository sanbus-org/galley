/**
 * Bun `Session`: the core session bound to the `bun:ffi` port.
 *
 * Created through `Session.fromDirectory`: the adapter loads its
 * standard-named library from the language directory, and the
 * directory's `procedures` module — if any — into the new session's
 * own hook registry, ahead of explicit `procedures`. The constructor
 * is private; the factory is synchronous (only the universal entry
 * and `fromUrl` need `async`).
 */

import { Session as CoreSession, checkArtifactPath, checkLanguagePath } from "@sanbus/galley-core";
import type { SessionOptions } from "@sanbus/galley-core";
import { getBunPort, getBunPortFromFile } from "./ffi.ts";
import { loadProcedures, loadProceduresForFile } from "./dispatch.ts";

export type { SessionOptions };

export class Session extends CoreSession {
  private constructor(port: ReturnType<typeof getBunPort>, options: SessionOptions, scannedProcedures: unknown = null) {
    super(port, options, scannedProcedures);
  }

  static fromDirectory(languagePath: string, options: SessionOptions = {}): Session {
    const directory = checkLanguagePath(languagePath, "galley: Session.fromDirectory");
    return new Session(getBunPort(directory), options, loadProcedures(directory));
  }

  static fromFile(filePath: string, options: SessionOptions = {}): Session {
    const file = checkArtifactPath(filePath, "galley: Session.fromFile");
    return new Session(getBunPortFromFile(file), options, loadProceduresForFile(file));
  }
}
