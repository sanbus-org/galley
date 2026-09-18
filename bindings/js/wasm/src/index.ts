/**
 * Galley JavaScript bindings over WebAssembly — public surface.
 *
 * Binds the runtime-neutral `@sanbus/galley-core` to the wasm port. Mirrors the
 * layout of the Node adapter and the C header `bindings/c/galley.h`.
 *
 * Sessions come from factories: `Session.fromDirectory` (a
 * directory holding the standard-named module file, synchronous),
 * `Session.fromBytes` (raw module bytes), or `Session.fromUrl`
 * (fetched, asynchronous). The browser entry (`browser.ts`) omits
 * `fromDirectory`: browsers have no filesystem.
 */

import { Session as CoreSession } from "@sanbus/galley-core";
import type { FfiPort, SessionOptions } from "@sanbus/galley-core";
import { checkArtifactPath, checkLanguagePath } from "@sanbus/galley-core";
import { getWasmPort, portFromBytes, portFromUrl, loadProcedures, loadProceduresForFile } from "./ffi.ts";
import { seedFileIo, seedProceduresScan } from "./ffi.ts";
import { nodeFileIo, scanLanguageDir, scanLanguageFile } from "./files.ts";

// Node entry owns the Node capabilities: the real filesystem plus the
// procedure scans. The browser entry (`browser.ts`) never imports this
// module.
seedFileIo(nodeFileIo);
seedProceduresScan({ forDirectory: scanLanguageDir, forFile: scanLanguageFile });

// Core surface (Session base is shadowed by the adapter subclass below).
export * from "@sanbus/galley-core";
export { getWasmPort, instantiateWasm, portFromBytes, portFromUrl, __resetModuleCache, __resetWasmAcquisition, loadProcedures, loadProceduresForFile, wasmFileName } from "./ffi.ts";
export type { WasmPortSource } from "./ffi.ts";
export type { SessionOptions };
export type { WalkStep, Diagnostic, TreeSnapshot } from "@sanbus/galley-core";

export class Session extends CoreSession {
  private constructor(port: FfiPort, options: SessionOptions, scannedProcedures: unknown = null) {
    super(port, options, scannedProcedures);
  }

  static fromDirectory(languagePath: string, options: SessionOptions = {}): Session {
    const directory = checkLanguagePath(languagePath, "galley-wasm: Session.fromDirectory");
    const session = new Session(
      getWasmPort({ languagePath: directory }),
      options,
      loadProcedures(directory),
    );
    return session;
  }

  static fromFile(filePath: string, options: SessionOptions = {}): Session {
    const file = checkArtifactPath(filePath, "galley-wasm: Session.fromFile");
    return new Session(getWasmPort({ filePath: file }), options, loadProceduresForFile(file));
  }

  static async fromBytes(bytes: Uint8Array, options: SessionOptions = {}): Promise<Session> {
    return new Session(await portFromBytes(bytes), options);
  }

  static async fromUrl(url: string | URL, options: SessionOptions = {}): Promise<Session> {
    return new Session(await portFromUrl(url), options);
  }
}
