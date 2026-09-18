/**
 * Universal `Session`: the core session bound to the resolved backend.
 *
 * Created through async factories — `fromDirectory` (a language
 * directory, native-first per runtime), `fromFile` (an explicit
 * artifact file, native-first per runtime), `fromBytes` (raw wasm), or
 * `fromUrl` (fetched) — so every JS entry shares one creation shape.
 * A factory either resolves a usable session or rejects: there is no
 * unready state. `backend` reports which leg serves the session.
 */

import { Session as CoreSession } from "@sanbus/galley-core";
import type { FfiPort, SessionOptions } from "@sanbus/galley-core";
import { checkArtifactPath, checkLanguagePath, checkModuleBytes, checkModuleUrl } from "@sanbus/galley-core";
import {
  detectRuntime,
  resolveSync,
  resolveAsync,
  noteWasmFallback,
  noteSkippedScan,
  type Backend,
} from "./loader.ts";

export type { SessionOptions };

export interface UniversalDirectoryOptions extends SessionOptions {
  /** Pin one backend instead of the native-first probe. */
  backend?: Backend;
  /** Suppress the one-time WebAssembly performance notice. */
  quiet?: boolean;
}

/** Same options as {@link UniversalDirectoryOptions}, for `fromFile`. */
export interface UniversalFileOptions extends UniversalDirectoryOptions {}

export interface UniversalWasmOptions extends SessionOptions {
  /** Suppress the one-time WebAssembly performance notice. */
  quiet?: boolean;
}

function requireLanguagePath(languagePath: string): string {
  return checkLanguagePath(languagePath, "galley: Session.fromDirectory");
}

export class Session extends CoreSession {
  readonly #backend: Backend;

  /** Which leg serves this session (`"native"` or `"wasm"`). */
  get backend(): Backend {
    return this.#backend;
  }

  private constructor(port: FfiPort, options: SessionOptions, backend: Backend, scannedProcedures: unknown = null) {
    super(port, options, scannedProcedures);
    this.#backend = backend;
  }

  static async fromDirectory(
    languagePath: string,
    options: UniversalDirectoryOptions = {},
  ): Promise<Session> {
    const directory = requireLanguagePath(languagePath);
    const { backend, quiet, ...sessionOptions } = options;
    const runtime = detectRuntime();
    const source = { languagePath: directory, backend };
    const resolved = resolveSync(source, runtime) ?? await resolveAsync(source, runtime);
    if (resolved.backend === "wasm") noteWasmFallback(quiet);
    noteSkippedScan(resolved.unscannedProcedures, sessionOptions.procedures);
    return new Session(
      resolved.port,
      sessionOptions,
      resolved.backend,
      resolved.procedures,
    );
  }

  static async fromFile(
    filePath: string,
    options: UniversalFileOptions = {},
  ): Promise<Session> {
    const file = checkArtifactPath(filePath, "galley: Session.fromFile");
    const { backend, quiet, ...sessionOptions } = options;
    const runtime = detectRuntime();
    const source = { filePath: file, backend };
    const resolved = resolveSync(source, runtime) ?? await resolveAsync(source, runtime);
    if (resolved.backend === "wasm") noteWasmFallback(quiet);
    noteSkippedScan(resolved.unscannedProcedures, sessionOptions.procedures);
    return new Session(
      resolved.port,
      sessionOptions,
      resolved.backend,
      resolved.procedures,
    );
  }

  static async fromBytes(bytes: Uint8Array, options: UniversalWasmOptions = {}): Promise<Session> {
    const source = checkModuleBytes(bytes, "galley: Session.fromBytes");
    const { quiet, ...sessionOptions } = options;
    const runtime = detectRuntime();
    const resolved = resolveSync({ bytes: source }, runtime) ?? await resolveAsync({ bytes: source }, runtime);
    noteWasmFallback(quiet);
    return new Session(resolved.port, sessionOptions, resolved.backend);
  }

  static async fromUrl(url: string | URL, options: UniversalWasmOptions = {}): Promise<Session> {
    const source = checkModuleUrl(url, "galley: Session.fromUrl");
    const { quiet, ...sessionOptions } = options;
    const resolved = await resolveAsync({ url: source }, detectRuntime());
    noteWasmFallback(quiet);
    return new Session(resolved.port, sessionOptions, resolved.backend);
  }
}
