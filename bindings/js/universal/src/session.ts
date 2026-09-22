/**
 * Universal `Language`: the artifact handle bound to the resolved backend.
 *
 * Languages come from `openLanguageDirectory` (a directory holding the
 * standard-named artifact, with `procedures` scanned) or from the
 * `galley` object (`load`, `loadBytes`, `loadUrl`). The same source
 * always yields the identical handle, so hook tables are stable per
 * artifact. Sessions open from the handle through `openSession` and
 * share its table. A factory either resolves a usable handle or
 * rejects: there is no unready state. `backend` reports which leg
 * serves the handle.
 */

import { Language as CoreLanguage, Session as CoreSession } from "@sanbus/galley-core";
import type { FfiPort, SessionOptions } from "@sanbus/galley-core";
import { checkArtifactPath, checkLanguagePath, checkModuleBytes, checkModuleUrl, hashModuleBytes } from "@sanbus/galley-core/internal";
import { rejectSessionOptions, __resetSharedRegistries } from "@sanbus/galley-core/internal";
import {
  detectRuntime,
  resolveSync,
  resolveAsync,
  noteWasmFallback,
  noteSkippedScan,
  type Backend,
} from "./loader.ts";

export type { SessionOptions };

export interface UniversalDirectoryOptions {
  /** Pin one backend instead of the native-first probe. */
  backend?: Backend;
  /**
   * Internal: the caller installs bundled hooks itself (the generated
   * entry's `initialize`), so the unscanned-file notice stays silent.
   */
  expectProcedures?: boolean;
}

/** Same options as {@link UniversalDirectoryOptions}, for `galley.load`. */
export interface UniversalFileOptions extends UniversalDirectoryOptions {}

export interface UniversalWasmOptions {
  /** No options yet; reserved. */
}

function requireLanguagePath(languagePath: string): string {
  return checkLanguagePath(languagePath, "galley: openLanguageDirectory");
}

/**
 * Rejects parser tunables at acquisition time: factories resolve the
 * artifact only, and tunables belong to `openSession` on the returned
 * handle. Loud instead of silently dropping caller intent.
 */
const DIRECTORY_LOAD_OPTIONS: ReadonlySet<string> = new Set(["backend", "expectProcedures"]);
const FILE_LOAD_OPTIONS: ReadonlySet<string> = new Set(["backend"]);
const BYTES_LOAD_OPTIONS: ReadonlySet<string> = new Set([]);

let languageByPort = new WeakMap<FfiPort, Language>();
// Byte- and URL-fed handles pin by source identity for the process
// lifetime, matching the adapter caches beneath (ports, libraries,
// compiled modules are likewise never evicted).
const languageBySource = new Map<string, Language>();

/** Test-only: drop cached handles so suites isolate hook tables. */
export function __resetLanguageCache(): void {
  languageByPort = new WeakMap<FfiPort, Language>();
  languageBySource.clear();
  __resetSharedRegistries();
}

/**
 * Shared handle for a resolved port: adapters cache ports per
 * canonical artifact path, so port identity unifies every spelling of
 * one file (including symlinks) into one hook table. Separate legs
 * resolve separate ports and therefore separate handles.
 */
function languageForPort(port: FfiPort, backend: Backend, scanned: unknown): Language {
  const hit = languageByPort.get(port);
  if (hit !== undefined) {
    // A directory open over an already-resolved handle (a bare load can
    // precede it): wire whatever the scan found, filling only names
    // never installed, so explicit installs keep winning. Bare loads
    // pass null and never scan.
    hit.installBundledProcedures(scanned);
    return hit;
  }
  const made = Language.create(port, backend, scanned);
  languageByPort.set(port, made);
  return made;
}

function hasHooks(language: Language): Record<string, unknown> | undefined {
  return Object.keys(language.listProcedures()).length > 0 ? {} : undefined;
}

/**
 * Opens the language at `languagePath`: resolves the backend, loads the
 * directory's bundled `procedures` where the runtime allows, and returns
 * the shared handle. Internal: backs the generated package entry
 * (`openSession`); user code opens packages or files, never directories
 * directly.
 */
export async function openLanguageDirectory(
  languagePath: string,
  options: UniversalDirectoryOptions = {},
): Promise<Language> {
  const directory = requireLanguagePath(languagePath);
  rejectSessionOptions(options as Record<string, unknown>, "openLanguageDirectory", DIRECTORY_LOAD_OPTIONS);
  const { backend, expectProcedures } = options;
  const runtime = detectRuntime();
  const source = { languagePath: directory, backend };
  const resolved = resolveSync(source, runtime) ?? await resolveAsync(source, runtime);
  if (resolved.backend === "wasm") noteWasmFallback();
  const language = languageForPort(resolved.port, resolved.backend, resolved.procedures);
  noteSkippedScan(resolved.unscannedProcedures, expectProcedures === true ? {} : hasHooks(language));
  return language;
}

export class Language extends CoreLanguage {
  readonly #backend: Backend;

  /** Which leg serves this handle (`"native"` or `"wasm"`). */
  get backend(): Backend {
    return this.#backend;
  }

  private constructor(port: FfiPort, backend: Backend, scannedProcedures: unknown = null) {
    super(port, scannedProcedures);
    this.#backend = backend;
  }

  /** Backs `galley` and `openLanguageDirectory`; user code never calls it. */
  static create(port: FfiPort, backend: Backend, scannedProcedures: unknown = null): Language {
    return new Language(port, backend, scannedProcedures);
  }

  override openSession(options: SessionOptions = {}): Session {
    return Session.create(this.port, options, this.backend);
  }
}

export class Session extends CoreSession {
  readonly #backend: Backend;

  /** Which leg serves this session (`"native"` or `"wasm"`). */
  get backend(): Backend {
    return this.#backend;
  }

  private constructor(port: FfiPort, options: SessionOptions, backend: Backend) {
    super(port, options);
    this.#backend = backend;
  }

  /** Backs `Language.openSession`; user code never calls it. */
  static create(port: FfiPort, options: SessionOptions, backend: Backend): Session {
    return new Session(port, options, backend);
  }
}

/**
 * Bare artifact loading: the only way to open an explicit file, raw
 * bytes, or a fetched module. Never scans; hooks arrive explicitly
 * only. Mirrors Python's `galley` loader namespace.
 */
export const galley = {
  async load(filePath: string, options: UniversalFileOptions = {}): Promise<Language> {
    const file = checkArtifactPath(filePath, "galley: galley.load");
    rejectSessionOptions(options as Record<string, unknown>, "galley.load", FILE_LOAD_OPTIONS);
    const { backend } = options;
    const runtime = detectRuntime();
    const source = { filePath: file, backend };
    const resolved = resolveSync(source, runtime) ?? await resolveAsync(source, runtime);
    if (resolved.backend === "wasm") noteWasmFallback();
    // Bare file loads never scan by contract; explicit installs only.
    return languageForPort(resolved.port, resolved.backend, null);
  },

  async loadBytes(bytes: Uint8Array, options: UniversalWasmOptions = {}): Promise<Language> {
    const source = checkModuleBytes(bytes, "galley: galley.loadBytes");
    rejectSessionOptions(options as Record<string, unknown>, "galley.loadBytes", BYTES_LOAD_OPTIONS);
        const runtime = detectRuntime();
    const key = `bytes:${hashModuleBytes(source)}`;
    const hit = languageBySource.get(key);
    if (hit !== undefined) return hit;
    // Bytes always resolve asynchronously: the async gate compiles
    // off-thread through the shared module cache, while the synchronous
    // path would block on compilation.
    const resolved = await resolveAsync({ bytes: source }, runtime);
    noteWasmFallback();
    const made = Language.create(resolved.port, resolved.backend, null);
    languageBySource.set(key, made);
    return made;
  },

  async loadUrl(url: string | URL, options: UniversalWasmOptions = {}): Promise<Language> {
    const source = checkModuleUrl(url, "galley: galley.loadUrl");
    rejectSessionOptions(options as Record<string, unknown>, "galley.loadUrl", BYTES_LOAD_OPTIONS);
        const key = `url:${typeof source === "string" ? source : source.href}`;
    const hit = languageBySource.get(key);
    if (hit !== undefined) return hit;
    const resolved = await resolveAsync({ url: source }, detectRuntime());
    noteWasmFallback();
    const made = Language.create(resolved.port, resolved.backend, null);
    languageBySource.set(key, made);
    return made;
  },
};
