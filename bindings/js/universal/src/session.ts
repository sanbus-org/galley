/**
 * Universal `Parser`, bound to the resolved backend.
 *
 * Parsers come from `openLanguageDirectory` (a directory holding the
 * standard-named artifact, wired with the entry's bundled hooks) or from
 * the `galley` object (`load`, `loadBytes`, `loadUrl`). Every factory
 * call hands out a new parser owning its defaults, so loading one
 * artifact twice never shares hook state — the loaded native module
 * beneath is shared (adapters cache ports and libraries) because it
 * cannot unload and holds no per-parser state. A package import
 * evaluates its entry once, so a package keeps one parser per process.
 * Sessions open from the parser through `openSession` and start with a
 * copy of its defaults. A factory either returns a usable parser or
 * throws: there is no unready state. Every factory is synchronous
 * except `loadUrl`, whose only async step is the fetch. `backend`
 * reports which leg serves the parser.
 */

import { Parser as CoreParser, Session as CoreSession } from "@sanbus/galley-core";
import type { FfiPort, SessionOptions } from "@sanbus/galley-core";
import { checkArtifactPath, checkLanguagePath, checkModuleBytes, checkModuleUrl, fetchModuleBytes, ProcedureRegistry } from "@sanbus/galley-core/internal";
import { rejectSessionOptions } from "@sanbus/galley-core/internal";
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

/**
 * Opens the parser at `languagePath`: resolves the backend and returns
 * a fresh parser, wiring `bundledProcedures` (the generated entry's
 * statically imported hook namespace) into its defaults. Internal:
 * backs the generated package entry (its import-time wiring and
 * `openSession`); user code opens packages or files, never
 * directories directly. The entry evaluates once per package, so the
 * package holds one parser per process.
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
  return Parser.create(resolved.port, resolved.backend, bundledProcedures);
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
    return this.openSessionWith((defaults) =>
      Session.create(this.port, options, this.backend, defaults),
    );
  }
}

export class Session extends CoreSession {
  readonly #backend: Backend;

  /** Which leg serves this session (`"native"` or `"wasm"`). */
  get backend(): Backend {
    return this.#backend;
  }

  private constructor(
    port: FfiPort,
    options: SessionOptions,
    backend: Backend,
    defaults: ProcedureRegistry,
  ) {
    super(port, options, defaults);
    this.#backend = backend;
  }

  /** Backs `Parser.openSession`; user code never calls it. */
  static create(
    port: FfiPort,
    options: SessionOptions,
    backend: Backend,
    defaults: ProcedureRegistry,
  ): Session {
    return new Session(port, options, backend, defaults);
  }
}

/**
 * Bare artifact loading: the only way to open an explicit file, raw
 * bytes, or a fetched module. Wires nothing; hooks arrive explicitly
 * only. Each call returns a new parser with its own (empty) defaults.
 */
export const galley = {
  load(filePath: string, options: UniversalFileOptions = {}): Parser {
    const file = checkArtifactPath(filePath, "galley: galley.load");
    rejectSessionOptions(options as Record<string, unknown>, "galley.load", NO_LOAD_OPTIONS);
    const resolved = resolveSync({ filePath: file }, detectRuntime());
    // Bare file loads wire nothing by contract; explicit installs only.
    return Parser.create(resolved.port, resolved.backend, null);
  },

  loadBytes(bytes: Uint8Array, options: UniversalWasmOptions = {}): Parser {
    const source = checkModuleBytes(bytes, "galley: galley.loadBytes");
    rejectSessionOptions(options as Record<string, unknown>, "galley.loadBytes", NO_LOAD_OPTIONS);
    const resolved = resolveSync({ bytes: source }, detectRuntime());
    return Parser.create(resolved.port, resolved.backend, null);
  },

  async loadUrl(url: string | URL, options: UniversalWasmOptions = {}): Promise<Parser> {
    const source = checkModuleUrl(url, "galley: galley.loadUrl");
    rejectSessionOptions(options as Record<string, unknown>, "galley.loadUrl", NO_LOAD_OPTIONS);
    // The only async factory: the fetch. Compilation after it is synchronous.
    const bytes = await fetchModuleBytes(source, "galley: galley.loadUrl");
    const resolved = resolveSync({ bytes }, detectRuntime());
    return Parser.create(resolved.port, resolved.backend, null);
  },
};
