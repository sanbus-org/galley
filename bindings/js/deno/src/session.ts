/**
 * Deno `Session`: the core session bound to the `Deno.dlopen` port.
 *
 * Created through `Session.fromDirectory`: the adapter loads its
 * standard-named library from the language directory (`fromFile`
 * opens an explicit file instead). Hook modules arrive explicitly
 * through `procedures` (there is no synchronous module scan on this
 * runtime); when a `procedures` file is present but unloaded and no
 * explicit hooks were given, the factory warns once. The constructor
 * is private; the factories are synchronous (only the universal entry
 * needs `async`).
 */

import { Session as CoreSession, checkArtifactPath, checkLanguagePath } from "@sanbus/galley-core";
import type { SessionOptions } from "@sanbus/galley-core";
import { getDenoPort, getDenoPortFromFile } from "./ffi.ts";
import { warnIfProceduresSkipped } from "./dispatch.ts";

export type { SessionOptions };

export class Session extends CoreSession {
  private constructor(port: ReturnType<typeof getDenoPort>, options: SessionOptions) {
    super(port, options);
  }

  static fromDirectory(languagePath: string, options: SessionOptions = {}): Session {
    const directory = checkLanguagePath(languagePath, "galley: Session.fromDirectory");
    const port = getDenoPort(directory);
    warnIfProceduresSkipped(directory, options.procedures);
    return new Session(port, options);
  }

  static fromFile(filePath: string, options: SessionOptions = {}): Session {
    const file = checkArtifactPath(filePath, "galley: Session.fromFile");
    const port = getDenoPortFromFile(file);
    return new Session(port, options);
  }
}
