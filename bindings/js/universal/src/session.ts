/**
 * Universal `Parser`, bound to the resolved backend.
 *
 * Parsers come from `openLanguageDirectory` (a directory holding the
 * standard-named artifact, wired with the entry's bundled hooks) or from
 * the `galley` object (`load`, `loadBytes`, `loadUrl`). The same source
 * always yields the identical parser, so hook tables are stable per
 * artifact. Sessions open from the parser through `openSession` and
 * share its table. A factory either returns a usable parser or throws:
 * there is no unready state. Every factory is synchronous except
 * `loadUrl`, whose only async step is the fetch. `backend` reports
 * which leg serves the parser.
 */

import { Parser as CoreParser, Session as CoreSession } from "@sanbus/galley-core";
import type { FfiPort, SessionOptions } from "@sanbus/galley-core";
import { checkArtifactPath, checkLanguagePath, checkModuleBytes, checkModuleUrl, fetchModuleBytes, hashModuleBytes } from "@sanbus/galley-core/internal";
import { rejectSessionOptions, __resetSharedRegistries } from "@sanbus/galley-core/internal";
import {
  detectRuntime,
  resolveSync,
  noteWasmFallback,
  type Backend,
} from "./loader.ts";

export type { SessionOptions };

export interface UniversalDirectoryOptions {
  /** No options; any option is rejected. */
}

/** Same options as {@link UniversalDirectoryOptions}, for `galley.load`. */
export interface UniversalFileOptions extends UniversalDirectoryOptions {}

export interface UniversalWasmOptions extends UniversalDirectoryOptions {}

function requireLanguagePath(languagePath: string): string {
  return checkLanguagePath(languagePath, "galley: openLanguageDirectory");
}

/**
 * Rejects parser tunables at acquisition time: factories resolve the
 * artifact only, and tunables belong to `openSession` on the returned
 * parser. Loud instead of silently dropping caller intent.
 */
const NO_LOAD_OPTIONS: ReadonlySet<string> = new Set([]);

let parserByPort = new WeakMap<FfiPort, Parser>();
// Byte- and URL-fed parsers pin by source identity for the process
// lifetime, matching the adapter caches beneath (ports, libraries,
// compiled modules are likewise never evicted).
const parserBySource = new Map<string, Parser>();

/** Test-only: drop cached parsers so suites isolate hook tables. */
export function __resetParserCache(): void {
  parserByPort = new WeakMap<FfiPort, Parser>();
  parserBySource.clear();
  __resetSharedRegistries();
}

/**
 * Shared parser for a resolved port: adapters cache ports per
 * canonical artifact path, so port identity unifies every spelling of
 * one file (including symlinks) into one default hook table. Separate legs
 * resolve separate ports and therefore separate parsers.
 */
function parserForPort(port: FfiPort, backend: Backend, bundledProcedures: unknown): Parser {
  const hit = parserByPort.get(port);
  if (hit !== undefined) {
    // A directory open over an already-resolved parser (a bare load can
    // precede it): wire the entry's namespace, filling only names
    // never installed, so explicit installs keep winning. Bare loads
    // pass null and wire nothing.
    hit.installBundledProcedures(bundledProcedures);
    return hit;
  }
  const made = Parser.create(port, backend, bundledProcedures);
  parserByPort.set(port, made);
  return made;
}

/**
 * Opens the parser at `languagePath`: resolves the backend and returns
 * the shared parser, wiring `bundledProcedures` (the generated entry's
 * statically imported hook namespace) into its defaults. Internal:
 * backs the generated package entry (its import-time wiring and
 * `openSession`); user code opens packages or files, never
 * directories directly.
 */
export function openLanguageDirectory(
  languagePath: string,
  options: UniversalDirectoryOptions = {},
  bundledProcedures: Record<string, unknown> | null = null,
): Parser {
  const directory = requireLanguagePath(languagePath);
  rejectSessionOptions(options as Record<string, unknown>, "openLanguageDirectory", NO_LOAD_OPTIONS);
  const resolved = resolveSync({ languagePath: directory }, detectRuntime());
  if (resolved.fallback) noteWasmFallback();
  return parserForPort(resolved.port, resolved.backend, bundledProcedures);
}

export class Parser extends CoreParser {
  readonly #backend: Backend;

  /** Which leg serves this parser (`"native"` or `"wasm"`). */
  get backend(): Backend {
    return this.#backend;
  }

  private constructor(port: FfiPort, backend: Backend, bundledProcedures: unknown = null) {
    super(port, bundledProcedures);
    this.#backend = backend;
  }

  /** Backs `galley` and `openLanguageDirectory`; user code never calls it. */
  static create(port: FfiPort, backend: Backend, bundledProcedures: unknown = null): Parser {
    return new Parser(port, backend, bundledProcedures);
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

  /** Backs `Parser.openSession`; user code never calls it. */
  static create(port: FfiPort, options: SessionOptions, backend: Backend): Session {
    return new Session(port, options, backend);
  }
}

/**
 * Bare artifact loading: the only way to open an explicit file, raw
 * bytes, or a fetched module. Wires nothing; hooks arrive explicitly only.
 */
export const galley = {
  load(filePath: string, options: UniversalFileOptions = {}): Parser {
    const file = checkArtifactPath(filePath, "galley: galley.load");
    rejectSessionOptions(options as Record<string, unknown>, "galley.load", NO_LOAD_OPTIONS);
    const resolved = resolveSync({ filePath: file }, detectRuntime());
    // Bare file loads wire nothing by contract; explicit installs only.
    return parserForPort(resolved.port, resolved.backend, null);
  },

  loadBytes(bytes: Uint8Array, options: UniversalWasmOptions = {}): Parser {
    const source = checkModuleBytes(bytes, "galley: galley.loadBytes");
    rejectSessionOptions(options as Record<string, unknown>, "galley.loadBytes", NO_LOAD_OPTIONS);
    const key = `bytes:${hashModuleBytes(source)}`;
    const hit = parserBySource.get(key);
    if (hit !== undefined) return hit;
    const resolved = resolveSync({ bytes: source }, detectRuntime());
    const made = Parser.create(resolved.port, resolved.backend, null);
    parserBySource.set(key, made);
    return made;
  },

  async loadUrl(url: string | URL, options: UniversalWasmOptions = {}): Promise<Parser> {
    const source = checkModuleUrl(url, "galley: galley.loadUrl");
    rejectSessionOptions(options as Record<string, unknown>, "galley.loadUrl", NO_LOAD_OPTIONS);
    const key = `url:${typeof source === "string" ? source : source.href}`;
    const hit = parserBySource.get(key);
    if (hit !== undefined) return hit;
    // The only async factory: the fetch. Compilation after it is synchronous.
    const bytes = await fetchModuleBytes(source, "galley: galley.loadUrl");
    const resolved = resolveSync({ bytes }, detectRuntime());
    const made = Parser.create(resolved.port, resolved.backend, null);
    parserBySource.set(key, made);
    return made;
  },
};
