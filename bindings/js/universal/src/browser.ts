/**
 * Browser entry for the universal Galley JavaScript bindings: wasm only.
 *
 * The same `galley` surface as the default entry with the filesystem
 * steps absent — no `node:` specifier exists anywhere in this module's
 * import graph, so bundlers resolve it without shims. Parsers come
 * from `galley.loadBytes` (raw module bytes) or `galley.loadUrl`
 * (fetched); there is no `load` and no language directory: browsers
 * have no filesystem. Each factory call hands out a new parser owning
 * its defaults; the compiled module beneath may be shared, since it
 * holds no per-parser state. Procedure hooks arrive explicitly through
 * the parser.
 */

import { Parser as CoreParser, Session as CoreSession } from "@sanbus/galley-core";
import type { FfiPort, SessionOptions } from "@sanbus/galley-core";
import { checkModuleBytes, checkModuleUrl, fetchModuleBytes, rejectSessionOptions } from "@sanbus/galley-core/internal";
import { instantiateWasm } from "@sanbus/galley-wasm/browser";

export {
  Walker,
  Node,
  GalleyError,
  MissingArtifactError,
  SessionClosedError,
  StaleTreeError,
  ProcedureArguments,
  INVALID_NODE,
  Status,
  ParserType,
  RecoveryMode,
  Kind,
  RecoveryTarget,
  Resume,
} from "@sanbus/galley-core";
export type { SessionOptions, WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";

export interface BrowserSessionOptions {
  /** No options yet; reserved. */
}

/**
 * Wasm-only parser: this entry serves no other leg, so the
 * backend reports literally.
 */
class BrowserParser extends CoreParser {
  /** Always wasm: the browser entry resolves no native leg. */
  get backend(): "wasm" {
    return "wasm";
  }

  constructor(port: FfiPort) {
    super(port, null);
  }

  override openSession(options: SessionOptions = {}): BrowserSession {
    return this.openSessionWith((defaults) => new BrowserSession(this.port, options, defaults));
  }
}

class BrowserSession extends CoreSession {
  /** Always wasm: the browser entry resolves no native leg. */
  get backend(): "wasm" {
    return "wasm";
  }
}

export { BrowserParser as Parser, BrowserSession as Session };

const NO_LOAD_OPTIONS: ReadonlySet<string> = new Set([]);

/**
 * Bare module loading: the only way to open raw bytes or a fetched
 * module in a browser. Hooks arrive explicitly only; every call hands
 * out a new parser. Synchronous except `loadUrl`, whose only async
 * step is the fetch.
 */
export const galley = {
  loadBytes(bytes: Uint8Array, options: BrowserSessionOptions = {}): BrowserParser {
    const source = checkModuleBytes(bytes, "galley: galley.loadBytes");
    rejectSessionOptions(options as Record<string, unknown>, "galley.loadBytes", NO_LOAD_OPTIONS);
    return new BrowserParser(instantiateWasm(source));
  },

  async loadUrl(url: string | URL, options: BrowserSessionOptions = {}): Promise<BrowserParser> {
    const source = checkModuleUrl(url, "galley: galley.loadUrl");
    rejectSessionOptions(options as Record<string, unknown>, "galley.loadUrl", NO_LOAD_OPTIONS);
    const bytes = await fetchModuleBytes(source, "galley: galley.loadUrl");
    return new BrowserParser(instantiateWasm(bytes));
  },
};
