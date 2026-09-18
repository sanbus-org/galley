/**
 * Browser entry for the universal Galley JavaScript bindings: wasm only.
 *
 * The same surface as the default entry with the native steps absent —
 * no `node:` specifier exists anywhere in this module's import graph, so
 * bundlers resolve it without shims. Sessions come from async factories:
 * `fromBytes` (raw module bytes) or `fromUrl` (fetched). There is no
 * `fromDirectory`: browsers have no filesystem. Procedure hooks arrive
 * through the session's `procedures` option.
 */

import { Session as CoreSession } from "@sanbus/galley-core";
import type { FfiPort, SessionOptions } from "@sanbus/galley-core";
import { portFromBytes, portFromUrl } from "@sanbus/galley-wasm/browser";

export * from "@sanbus/galley-core";
export type { SessionOptions, WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";

export interface BrowserSessionOptions extends SessionOptions {
  /** Suppress the one-time WebAssembly performance notice. */
  quiet?: boolean;
}

let warned = false;

function noteBrowserWasm(quiet: boolean | undefined): void {
  if (quiet || warned) return;
  warned = true;
  console.warn(
    "galley: using the WebAssembly backend; throughput trails native codegen " +
      "(roughly three quarters). Silence with { quiet: true }.",
  );
}

/** Test-only: clear the one-time notice. */
export function __resetLoader(): void {
  warned = false;
}

export class Session extends CoreSession {
  private constructor(port: FfiPort, options: SessionOptions) {
    super(port, options);
  }

  static async fromBytes(bytes: Uint8Array, options: BrowserSessionOptions = {}): Promise<Session> {
    const { quiet, ...rest } = options;
    noteBrowserWasm(quiet);
    return new Session(await portFromBytes(bytes, "galley"), rest);
  }

  static async fromUrl(url: string | URL, options: BrowserSessionOptions = {}): Promise<Session> {
    const { quiet, ...rest } = options;
    noteBrowserWasm(quiet);
    return new Session(await portFromUrl(url, "galley"), rest);
  }
}
