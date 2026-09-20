/**
 * Browser entry for the universal Galley JavaScript bindings: wasm only.
 *
 * The same `galley` surface as the default entry with the filesystem
 * steps absent — no `node:` specifier exists anywhere in this module's
 * import graph, so bundlers resolve it without shims. Languages come
 * from `galley.loadBytes` (raw module bytes) or `galley.loadUrl`
 * (fetched); there is no `load` and no language directory: browsers
 * have no filesystem. Procedure hooks arrive explicitly through the
 * language handle.
 */

import { Language as CoreLanguage, Session as CoreSession } from "@sanbus/galley-core";
import type { SessionOptions } from "@sanbus/galley-core";
import { checkModuleBytes, checkModuleUrl, hashModuleBytes, rejectSessionOptions } from "@sanbus/galley-core/internal";
import { portFromBytes, portFromUrl } from "@sanbus/galley-wasm/browser";

export {
  Walker,
  Node,
  GalleyError,
  MissingArtifactError,
  SessionClosedError,
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

let warned = false;

function envQuiet(): boolean {
  try {
    const proc = (globalThis as Record<string, unknown>).process as
      | { env?: Record<string, string | undefined> }
      | undefined;
    const value = proc?.env?.GALLEY_QUIET;
    if (value === "1" || value === "true") return true;
  } catch {
    // Unreachable globals count as unset.
  }
  return false;
}

function noteBrowserWasm(): void {
  if (envQuiet() || warned) return;
  warned = true;
  console.warn(
    "galley: using the WebAssembly backend; throughput trails native codegen " +
      "(roughly three quarters). Silence with GALLEY_QUIET=1.",
  );
}

/** Test-only: clear the one-time notice. */
export function __resetLoader(): void {
  warned = false;
  languageCache.clear();
}

/**
 * Wasm-only language handle: this entry serves no other leg, so the
 * backend reports literally.
 */
class BrowserLanguage extends CoreLanguage {
  /** Always wasm: the browser entry resolves no native leg. */
  get backend(): "wasm" {
    return "wasm";
  }

  override openSession(options: SessionOptions = {}): BrowserSession {
    return new BrowserSession(this.port, options);
  }
}

class BrowserSession extends CoreSession {
  /** Always wasm: the browser entry resolves no native leg. */
  get backend(): "wasm" {
    return "wasm";
  }
}

export { BrowserLanguage as Language, BrowserSession as Session };

// Byte- and URL-fed handles pin by source identity for the process
// lifetime, matching the adapter caches beneath.
const NO_LOAD_OPTIONS: ReadonlySet<string> = new Set([]);

const languageCache = new Map<string, BrowserLanguage>();

async function cachedLanguage(key: string, make: () => Promise<BrowserLanguage>): Promise<BrowserLanguage> {
  const hit = languageCache.get(key);
  if (hit !== undefined) return hit;
  const made = await make();
  languageCache.set(key, made);
  return made;
}

/**
 * Bare module loading: the only way to open raw bytes or a fetched
 * module in a browser. Hooks arrive explicitly only.
 */
export const galley = {
  async loadBytes(bytes: Uint8Array, options: BrowserSessionOptions = {}): Promise<BrowserLanguage> {
    const source = checkModuleBytes(bytes, "galley: galley.loadBytes");
    rejectSessionOptions(options as Record<string, unknown>, "galley.loadBytes", NO_LOAD_OPTIONS);
    const key = `bytes:${hashModuleBytes(source)}`;
    return cachedLanguage(key, async () => {
      noteBrowserWasm();
      return new BrowserLanguage(await portFromBytes(source, "galley"));
    });
  },

  async loadUrl(url: string | URL, options: BrowserSessionOptions = {}): Promise<BrowserLanguage> {
    const source = checkModuleUrl(url, "galley: galley.loadUrl");
    rejectSessionOptions(options as Record<string, unknown>, "galley.loadUrl", NO_LOAD_OPTIONS);
    const key = `url:${typeof source === "string" ? source : source.href}`;
    return cachedLanguage(key, async () => {
      noteBrowserWasm();
      return new BrowserLanguage(await portFromUrl(source, "galley"));
    });
  },
};
